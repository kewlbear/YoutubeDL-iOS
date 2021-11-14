//
//  Copyright (c) 2020 Changbeom Ahn
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation
import PythonKit
import PythonSupport
import AVFoundation
import Photos
import UIKit

public struct Info: CustomStringConvertible {
    let info: PythonObject

    var dict: [String: PythonObject]? {
        Dictionary(info)
    }

    public var title: String? {
        dict?["title"].flatMap { String($0) }
    }

    var format: Format? {
        dict.map { Format(format: $0) }
    }
    
    public var formats: [Format] {
        let array: [PythonObject]? = dict?["formats"].flatMap { Array($0) }
        let dicts: [[String: PythonObject]?]? = array?.map { Dictionary($0) }
        return dicts?.compactMap { $0.flatMap { Format(format: $0) } } ?? []
    }
    
    public var description: String {
        "\(dict?["title"] ?? "no title?")"
    }
}

let chunkSize: Int64 = 2_000_000

@dynamicMemberLookup
public struct Format: CustomStringConvertible {
    public let format: [String: PythonObject]
    
    var url: URL? { self[dynamicMember: "url"].flatMap { URL(string: $0) } }
    
    var httpHeaders: [String: String] {
        format["http_headers"].flatMap { Dictionary($0) } ?? [:]
    }
    
    public var urlRequest: URLRequest? {
        guard let url = url else {
            return nil
        }
        var request = URLRequest(url: url)
        for (field, value) in httpHeaders {
            request.addValue(value, forHTTPHeaderField: field)
        }
        
        return request
    }
    
    public var height: Int? { format["height"].flatMap { Int($0) } }
    
    public var filesize: Int64? { format["filesize"].flatMap { Int64($0) } }
    
    public var isAudioOnly: Bool { self.vcodec == "none" }
    
    public var isVideoOnly: Bool { self.acodec == "none" }
    
    public var description: String {
        "\(format["format"] ?? "no format?") \(format["ext"] ?? "no ext?") \(format["vcodec"] ?? "no vcodec?") \(format["filesize"] ?? "no size?")"
    }
    
    public subscript(dynamicMember key: String) -> String? {
        format[key].flatMap { String($0) }
    }
}

public let defaultOptions: PythonObject = [
    "format": "bestvideo,bestaudio[ext=m4a]",
    "nocheckcertificate": true,
    "verbose": true,
]

public enum YoutubeDLError: Error {
    case canceled
}

open class YoutubeDL: NSObject {
    public enum Error: Swift.Error {
        case noPythonModule
    }
    
    public struct Options: OptionSet {
        public let rawValue: Int
        
        public static let noRemux = Options(rawValue: 1 << 0)
        public static let noTranscode = Options(rawValue: 1 << 1)
        public static let chunked = Options(rawValue: 1 << 2)
        public static let background = Options(rawValue: 1 << 3)

        public static let all: Options = [.noRemux, .noTranscode, .chunked, .background]
        
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }
    
    public static var shouldDownloadPythonModule: Bool {
        do {
            _ = try YoutubeDL()
            return false
        }
        catch Error.noPythonModule {
            return true
        }
        catch {
            guard let error = error as? PythonError,
                  case let .exception(e, _) = error,
                  e.description == "No module named 'youtube_dl'" else { // FIXME: better way?
                return false
            }
            return true
        }
    }
    
    public static let latestDownloadURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp")!
    
    public static var pythonModuleURL: URL = {
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("io.github.kewlbear.youtubedl-ios") else { fatalError() }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }
        catch {
            fatalError(error.localizedDescription)
        }
        return directory.appendingPathComponent("yt_dlp")
    }()
    
    open var transcoder: Transcoder?
    
    public let version: String?
    
    public lazy var downloader = Downloader.shared
    
//    public var videoExists: Bool { FileManager.default.fileExists(atPath: Kind.videoOnly.url.path) }
    
    public lazy var downloadsDirectory: URL = downloader.directory {
        didSet { downloader.directory = downloadsDirectory }
    }
    
    internal let pythonObject: PythonObject

    internal let options: PythonObject
    
    lazy var finished: AsyncStream<URL> = {
        AsyncStream { continuation in
            finishedContinuation = continuation
        }
    }()
    
    var finishedContinuation: AsyncStream<URL>.Continuation?
    
    var keepIntermediates = false
    
    lazy var postDownloadTask = Task {
        for await (url, kind) in downloader.stream {
            print(#function, kind, url.lastPathComponent)
            switch kind {
            case .complete:
                export(url)
            case .videoOnly, .audioOnly:
                guard transcoder == nil else {
                    break
                }
                tryMerge(title: url.title)
            case .otherVideo:
//                    Task {
                await transcode(url: url)
////                    }
            }
        }
    }
    
    public init(options: PythonObject = defaultOptions) throws {
        guard FileManager.default.fileExists(atPath: Self.pythonModuleURL.path) else {
            throw Error.noPythonModule
        }
        
        let sys = try Python.attemptImport("sys")
        if !(Array(sys.path) ?? []).contains(Self.pythonModuleURL.path) {
            runSimpleString("""
                class Pop:
                    def __init__(self, args, bufsize=-1, executable=None,
                                 stdin=None, stdout=None, stderr=None,
                                 preexec_fn=None, close_fds=True,
                                 shell=False, cwd=None, env=None, universal_newlines=None,
                                 startupinfo=None, creationflags=0,
                                 restore_signals=True, start_new_session=False,
                                 pass_fds=(), *, user=None, group=None, extra_groups=None,
                                 encoding=None, errors=None, text=None, umask=-1, pipesize=-1):
                        raise OSError("Popen is not supported")
                
                    def communicate(self, input=None, timeout=None):
                        pass
                
                    def kill(self):
                        pass

                    def wait(self):
                        pass

                import subprocess
                subprocess.Popen = Pop
                """)
            
            sys.path.insert(1, Self.pythonModuleURL.path)
        }
        
        let pythonModule = try Python.attemptImport("yt_dlp")
        pythonObject = pythonModule.YoutubeDL(options)
        
        self.options = options ?? defaultOptions
        
        version = String(pythonModule.version.__version__)
    }
    
    public convenience init(_ options: PythonObject? = nil, initializePython: Bool = true, downloadPythonModule: Bool = true) async throws {
        if initializePython {
            PythonSupport.initialize()
        }
        
        if !FileManager.default.fileExists(atPath: Self.pythonModuleURL.path) {
            guard downloadPythonModule else {
                throw Error.noPythonModule
            }
            try await Self.downloadPythonModule()
        }
        
        try self.init(options: options ?? defaultOptions)
    }
        
    open func download(url: URL, options: Options = [.background, .chunked], formatSelector: ((Info?) async -> [Format])? = nil) async throws -> URL {
        var (formats, info) = try extractInfo(url: url)
        
        let title = info?.title?.replacingOccurrences(of: "/", with: "_") ?? "No title"
        
        if let formatSelector = formatSelector {
            formats = await formatSelector(info)
            guard !formats.isEmpty else { throw YoutubeDLError.canceled }
        }
        
        _ = postDownloadTask
        
        for format in formats {
            Task {
                try await download(format: format, faster: options.contains(.chunked), title: title)
            }
        }
        
        for await url in finished {
            // FIXME: validate url
            return url
        }
        fatalError()
    }
    
    func makeURL(title: String, kind: Kind, ext: String) -> URL {
        downloadsDirectory.appendingPathComponent(
            title
                .appending(Kind.separator)
                .appending(kind.rawValue))
            .appendingPathExtension(ext)
    }
    
    open func download(format: Format, faster: Bool, title: String) async throws {
        let kind: Kind = format.isVideoOnly
        ? (!format.isTranscodingNeeded ? .videoOnly : .otherVideo)
        : (format.isAudioOnly ? .audioOnly : .complete)
        
        func download(for request: URLRequest) async throws {
            let progress: Progress? = downloader.progress
            progress?.kind = .file
            progress?.fileOperationKind = .downloading
            let url = makeURL(title: title, kind: kind, ext: format.ext ?? "no ext?")
            do {
                try Data().write(to: url)
            }
            catch {
                print(#function, error)
            }
            progress?.fileURL = url
            
            removeItem(at: url)

            let task = downloader.download(request: request, url: url)
            print(#function, "start download:", task.info)
        }
        
        if faster, let size = format.filesize {
            guard var request = format.urlRequest else { fatalError() }
            // https://github.com/ytdl-org/youtube-dl/issues/15271#issuecomment-362834889
            let end = request.setRange(start: 0, fullSize: size)
            print(#function, "first chunked size:", end)
            
            return try await download(for: request)
        } else {
            guard let request = format.urlRequest else { fatalError() }
            
            return try await download(for: request)
        }
    }
   
    open func extractInfo(url: URL) throws -> ([Format], Info?) {
        print(#function, url)
        let info = try pythonObject.extract_info.throwing.dynamicallyCall(withKeywordArguments: ["": url.absoluteString, "download": false, "process": true])
//        print(#function, "throttled:", pythonObject.throttled)
        
        let format_selector = pythonObject.build_format_selector(options["format"])
        let formats_to_download = format_selector(info)
        var formats: [Format] = []
        for format in formats_to_download {
            guard let dict: [String: PythonObject] = Dictionary(format) else { fatalError() }
            formats.append(Format(format: dict))
        }
        
        return (formats, Info(info: info))
    }
    
    func tryMerge(title: String) {
        let t0 = ProcessInfo.processInfo.systemUptime
       
        let videoURL = makeURL(title: title, kind: .videoOnly, ext: "mp4")
        let audioURL: URL = makeURL(title: title, kind: .audioOnly, ext: "m4a")
        let videoAsset = AVAsset(url: videoURL)
        let audioAsset = AVAsset(url: audioURL)
        
        guard let videoAssetTrack = videoAsset.tracks(withMediaType: .video).first,
              let audioAssetTrack = audioAsset.tracks(withMediaType: .audio).first else {
            print(#function,
                  videoAsset.tracks(withMediaType: .video),
                  audioAsset.tracks(withMediaType: .audio))
            return
        }
        
        let composition = AVMutableComposition()
        let videoCompositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let audioCompositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        
        do {
            try videoCompositionTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: videoAssetTrack.timeRange.duration), of: videoAssetTrack, at: .zero)
            try audioCompositionTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: audioAssetTrack.timeRange.duration), of: audioAssetTrack, at: .zero)
            print(#function, videoAssetTrack.timeRange, audioAssetTrack.timeRange)
        }
        catch {
            print(#function, error)
            return
        }
        
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            print(#function, "unable to init export session")
            return
        }
        let outputURL = downloadsDirectory.appendingPathComponent(title).appendingPathExtension("mp4")
        
        removeItem(at: outputURL)
        
        session.outputURL = outputURL
        session.outputFileType = .mp4
        print(#function, "merging...")
        
        DispatchQueue.main.async {
            let progress = self.downloader.progress
            progress.kind = nil
            progress.localizedDescription = NSLocalizedString("Merging...", comment: "Progress description")
            progress.localizedAdditionalDescription = nil
            progress.totalUnitCount = 0
            progress.completedUnitCount = 0
            progress.estimatedTimeRemaining = nil
        }
        
        session.exportAsynchronously {
            print(#function, "finished merge", session.status.rawValue)
            print(#function, "took", self.downloader.dateComponentsFormatter.string(from: ProcessInfo.processInfo.systemUptime - t0) ?? "?")
            if session.status == .completed {
                if !self.keepIntermediates {
                    removeItem(at: videoURL)
                    removeItem(at: audioURL)
                }
                
                self.export(outputURL)
            } else {
                print(#function, session.error ?? "no error?")
            }
        }
    }
    
    open func transcode(url: URL) async {
        DispatchQueue.main.async {
            guard UIApplication.shared.applicationState == .active else {
                notify(body: NSLocalizedString("AskTranscode", comment: "Notification body"), identifier: NotificationRequestIdentifier.transcode.rawValue)
                return
            }

//            let alert = UIAlertController(title: nil, message: NSLocalizedString("DoNotSwitch", comment: "Alert message"), preferredStyle: .alert)
//            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Action"), style: .default, handler: nil))
//            self.topViewController?.present(alert, animated: true, completion: nil)
        }
       
        let outURL = makeURL(title: url.title, kind: .videoOnly, ext: "mp4")
        
        removeItem(at: outURL)

        DispatchQueue.main.async {
            let progress = self.downloader.progress
            progress.kind = nil
            progress.localizedDescription = NSLocalizedString("Transcoding...", comment: "Progress description")
            progress.totalUnitCount = 100
        }

        let t0 = ProcessInfo.processInfo.systemUptime

        if transcoder == nil {
            transcoder = Transcoder()
        }
        var ret: Int32?

        @Sendable func requestProgress() {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                self.transcoder?.progressBlock = { progress in
                    self.transcoder?.progressBlock = nil

                    let elapsed = ProcessInfo.processInfo.systemUptime - t0
                    let speed = progress / elapsed
                    let ETA = (1 - progress) / speed

                    guard ETA.isFinite else { return }

                    DispatchQueue.main.async {
                        let _progress = self.downloader.progress
                        _progress.completedUnitCount = Int64(progress * 100)
                        _progress.estimatedTimeRemaining = ETA
                    }
                }

                if self.transcoder != nil {
                    requestProgress()
                }
            }
        }

        requestProgress()

        ret = await transcoder?.transcode(from: url, to: outURL)

        transcoder = nil

        print(#function, ret ?? "nil?", "took", downloader.dateComponentsFormatter.string(from: ProcessInfo.processInfo.systemUptime - t0) ?? "?")

        guard ret == 0 else { return }
        
        if !keepIntermediates {
            removeItem(at: url)
        }
        
        notify(body: NSLocalizedString("FinishedTranscoding", comment: "Notification body"))

        tryMerge(title: url.title)
    }
    
    internal func export(_ url: URL) {
        DispatchQueue.main.async {
            let progress = self.downloader.progress
            progress.localizedDescription = nil
            progress.localizedAdditionalDescription = nil
            progress.kind = .file
            progress.fileOperationKind = .copying
            progress.fileURL = url
            progress.completedUnitCount = 0
            progress.estimatedTimeRemaining = nil
            progress.throughput = nil
            progress.fileTotalCount = 1
        }
        
        PHPhotoLibrary.shared().performChanges({
            _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            //                            changeRequest.contentEditingOutput = output
        }) { (success, error) in
            print(#function, success, error ?? "")
            
            if let continuation = self.finishedContinuation {
                continuation.yield(url)
            } else {
                notify(body: NSLocalizedString("Download complete!", comment: "Notification body"))
            }
            DispatchQueue.main.async {
                let progress = self.downloader.progress
                progress.fileCompletedCount = 1
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: url.path) as NSDictionary
                    progress.completedUnitCount = Int64(attributes.fileSize())
                }
                catch {
                    progress.localizedDescription = error.localizedDescription
                }
            }
        }
    }
        
    fileprivate static func movePythonModule(_ location: URL) throws {
        removeItem(at: pythonModuleURL)
        
        try FileManager.default.moveItem(at: location, to: pythonModuleURL)
    }
    
    public static func downloadPythonModule(from url: URL = latestDownloadURL, completionHandler: @escaping (Swift.Error?) -> Void) {
        let task = URLSession.shared.downloadTask(with: url) { (location, response, error) in
            guard let location = location else {
                completionHandler(error)
                return
            }
            do {
                try movePythonModule(location)

                completionHandler(nil)
            }
            catch {
                print(#function, error)
                completionHandler(error)
            }
        }
        
        task.resume()
    }
    
    public static func downloadPythonModule(from url: URL = latestDownloadURL) async throws {
        if #available(iOS 15.0, *) {
            let (location, _) = try await URLSession.shared.download(from: url)
            try movePythonModule(location)
        } else {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
                downloadPythonModule(from: url) { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }
}

let av1CodecPrefix = "av01."

public extension Format {
    var isRemuxingNeeded: Bool { isVideoOnly || isAudioOnly }
    
    var isTranscodingNeeded: Bool {
        self.ext == "mp4"
            ? (self.vcodec ?? "").hasPrefix(av1CodecPrefix)
            : self.ext != "m4a"
    }
}

extension URL {
    var part: URL {
        appendingPathExtension("part")
    }
    
    var title: String {
        let name = deletingPathExtension().lastPathComponent
        guard let range = name.range(of: Kind.separator, options: [.backwards]) else { return name }
        return String(name[..<range.lowerBound])
    }
}

extension URLSessionDownloadTask {
    var info: String {
        "\(taskDescription ?? "no task description") \(originalRequest?.value(forHTTPHeaderField: "Range") ?? "no range")"
    }
}
