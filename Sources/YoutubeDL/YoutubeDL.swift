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
import FFmpegSupport

// https://github.com/pvieito/PythonKit/pull/30#issuecomment-751132191
let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)

func loadSymbol<T>(_ name: String) -> T {
    unsafeBitCast(dlsym(RTLD_DEFAULT, name), to: T.self)
}

let Py_IsInitialized: @convention(c) () -> Int32 = loadSymbol("Py_IsInitialized")

public struct Info: Codable {
    public var id: String
    public var title: String
    public var formats: [Format]
    public var description: String?
    public var upload_date: String?
    public var uploader: String?
    public var uploader_id: String?
    public var uploader_url: String?
    public var channel_id: String?
    public var channel_url: String?
    public var duration: TimeInterval?
    public var view_count: Int?
    public var average_rating: Double?
    public var age_limit: Int?
    public var webpage_url: String?
    public var categories: [String]?
    public var tags: [String]?
    public var playable_in_embed: Bool?
    public var is_live: Bool?
    public var was_live: Bool?
    public var live_status: String?
    public var release_timestamp: Int?
    
    public struct Chapter: Codable {
        public var title: String?
        public var start_time: TimeInterval?
        public var end_time: TimeInterval?
    }
    
    public var chapters: [Chapter]?
    public var like_count: Int?
    public var channel: String?
    public var availability: String?
    public var __post_extractor: String?
    public var original_url: String?
    public var webpage_url_basename: String
    public var extractor: String?
    public var extractor_key: String?
    public var playlist: [String]?
    public var playlist_index: Int?
    public var thumbnail: String?
    public var display_id: String?
    public var duration_string: String?
    public var requested_subtitles: [String]?
    public var __has_drm: Bool?
}

public extension Info {
    var safeTitle: String {
        String(title[..<(title.index(title.startIndex, offsetBy: 40, limitedBy: title.endIndex) ?? title.endIndex)])
            .replacingOccurrences(of: "/", with: "_")
    }
}

public struct Format: Codable {
    public var asr: Int?
    public var filesize: Int?
    public var format_id: String
    public var format_note: String?
    public var fps: Double?
    public var height: Int?
    public var quality: Double?
    public var tbr: Double?
    public var url: String
    public var width: Int?
    public var language: String?
    public var language_preference: Int?
    public var ext: String
    public var vcodec: String?
    public var acodec: String?
    public var dynamic_range: String?
    public var abr: Double?
    public var vbr: Double?
    
    public struct DownloaderOptions: Codable {
        public var http_chunk_size: Int
    }
    
    public var downloader_options: DownloaderOptions?
    public var container: String?
    public var `protocol`: String
    public var audio_ext: String
    public var video_ext: String
    public var format: String
    public var resolution: String?
    public var http_headers: [String: String]
}

let chunkSize: Int64 = 10_485_760 // https://github.com/yt-dlp/yt-dlp/blob/720c309932ea6724223d0a6b7781a0e92a74262c/yt_dlp/extractor/youtube.py#L2552

public extension Format {
    var urlRequest: URLRequest? {
        guard let url = URL(string: url) else {
            return nil
        }
        var request = URLRequest(url: url)
        for (field, value) in http_headers {
            request.addValue(value, forHTTPHeaderField: field)
        }
        
        return request
    }
    
    var isAudioOnly: Bool { vcodec == "none" }
    
    var isVideoOnly: Bool { acodec == "none" }
}

public let defaultOptions: PythonObject = [
    "format": "bestvideo,bestaudio[ext=m4a]/best",
    "nocheckcertificate": true,
    "verbose": true,
]

public enum YoutubeDLError: Error {
    case noPythonModule
    case canceled
}

open class YoutubeDL: NSObject {
    public struct Options: OptionSet, Codable {
        public let rawValue: Int
        
        public static let noRemux       = Options(rawValue: 1 << 0)
        public static let noTranscode   = Options(rawValue: 1 << 1)
        public static let chunked       = Options(rawValue: 1 << 2)
        public static let background    = Options(rawValue: 1 << 3)

        public static let all: Options = [.noRemux, .noTranscode, .chunked, .background]
        
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }
    
    struct Download: Codable {
        var formats: [Format]
        var directory: URL
        var safeTitle: String
        var options: Options
        var timeRange: TimeRange?
        var bitRate: Double?
        var transcodePending: Bool
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
    
    public var version: String?
    
    public var downloader = Downloader.shared
    
//    public var videoExists: Bool { FileManager.default.fileExists(atPath: Kind.videoOnly.url.path) }
    
    public lazy var downloadsDirectory: URL = downloader.directory {
        didSet { downloader.directory = downloadsDirectory }
    }
    
    internal var pythonObject: PythonObject?

    internal var options: PythonObject?
    
    lazy var finished: AsyncStream<URL> = {
        AsyncStream { continuation in
            finishedContinuation = continuation
        }
    }()
    
    var finishedContinuation: AsyncStream<URL>.Continuation?
    
    open var keepIntermediates = false
    
    lazy var postDownloadTask = Task {
        for await (url, kind) in downloader.stream {
            print(#function, kind, url.lastPathComponent)
            
            switch kind {
            case .complete:
                export(url)
            case .videoOnly, .audioOnly:
                let directory = url.deletingLastPathComponent()
                guard let download = pendingDownloads.first(where: { $0.directory.path == directory.path }) else {
                    print(#function, "no download with", directory, pendingDownloads.map(\.directory))
                    return
                }
                guard tryMerge(directory: directory, title: url.title, timeRange: download.timeRange) else { return }
                finishedContinuation?.yield(url)
            case .otherVideo:
                do {
                    try await transcode(directory: url.deletingLastPathComponent())
                    finishedContinuation?.yield(url)
                } catch {
                    print(error)
                }
            }
        }
    }
    
    lazy var pendingDownloads: [Download] = {
        loadPendingDownloads()
    }() {
        didSet { savePendingDownloads() }
    }
    
    var pendingDownloadsURL: URL { downloadsDirectory.appendingPathComponent("PendingDownloads.json") }
    
    public var pendingTranscode: URL? {
        pendingDownloads.first { $0.transcodePending }?.directory
    }
    
    public override init() {
        super.init()
        
        _ = postDownloadTask
    }
    
    func loadPythonModule(downloadPythonModule: Bool = true) async throws -> PythonObject {
        if Py_IsInitialized() == 0 {
            PythonSupport.initialize()
        }
        
        if !FileManager.default.fileExists(atPath: Self.pythonModuleURL.path) {
            guard downloadPythonModule else {
                throw YoutubeDLError.noPythonModule
            }
            try await Self.downloadPythonModule()
        }
        
        let sys = try Python.attemptImport("sys")
        if !(Array(sys.path) ?? []).contains(Self.pythonModuleURL.path) {
            injectFakePopen(handler: popenHandler)
            
            sys.path.insert(1, Self.pythonModuleURL.path)
        }
        
        let pythonModule = try Python.attemptImport("yt_dlp")
        version = String(pythonModule.version.__version__)
        return pythonModule
    }
    
    func injectFakePopen(handler: PythonFunction) {
        runSimpleString("""
            import errno
            import os
            
            class Pop:
                def __init__(self, *args, **kwargs):
                    print('Popen.__init__:', self, args)#, kwargs)
                    if args[0][0] in ['ffmpeg', 'ffprobe']:
                        self.__args = args
                    else:
                        raise FileNotFoundError(errno.ENOENT, os.strerror(errno.ENOENT), args[0])
            
                def communicate(self, *args, **kwargs):
                    print('Popen.communicate:', self, args, kwargs)
                    return self.handler(self, self.__args)

                def kill(self):
                    print('Popen.kill:', self)

                def wait(self, **kwargs):
                    print('Popen.wait:', self, kwargs)

                def __enter__(self):
                    return self
                
                def __exit__(self, type, value, traceback):
                    pass
            
            import subprocess
            subprocess.Popen = Pop
            """)
        
        let subprocess = Python.import("subprocess")
        subprocess.Popen.handler = handler.pythonObject
    }
    
    lazy var popenHandler = PythonFunction { args in
        print(#function, args)
        let popen = args[0]
        var result = Array<String?>(repeating: nil, count: 2)
        if var args: [String] = Array(args[1][0]) {
            // save standard out/error
            let stdout = dup(STDOUT_FILENO)
            let stderr = dup(STDERR_FILENO)
            
            // redirect standard out/error
            let outPipe = Pipe()
            let errPipe = Pipe()
            dup2(outPipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
            dup2(errPipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
            
            let exitCode = self.handleFFmpeg(args: args)
            
            // restore standard out/error
            dup2(stdout, STDOUT_FILENO)
            dup2(stderr, STDERR_FILENO)
            
            popen.returncode = PythonObject(exitCode)
            
            func read(pipe: Pipe) -> String? {
                guard let string = String(data: pipe.fileHandleForReading.availableData, encoding: .utf8) else {
                    print(#function, "not UTF-8?")
                    return nil
                }
                print(#function, string)
                return string
            }
            
            result[0] = read(pipe: outPipe)
            result[1] = read(pipe: errPipe)
            return Python.tuple(result)
        }
        return Python.tuple(result)
    }
    
    func handleFFmpeg(args: [String]) -> Int {
        var args = args
        
        let pipe = Pipe()
        defer {
            do {
//                print(#function, "close")
                try pipe.fileHandleForWriting.close()
            } catch {
                print(#function, error)
            }
        }
        
        if args.contains("-i") {
            if let timeRange {
                args.insert(contentsOf: [
                    "-ss", "\(timeRange.lowerBound)",
                    "-t", "\(timeRange.upperBound - timeRange.lowerBound)",
                ], at: 1)
            }
            
            if let progressBlock = willTranscode?() {
                if #available(iOS 15.0, *) {
                    let maxTime: Double
                    if let duration {
                        maxTime = duration * 1_000_000
                    } else if let timeRange = timeRange {
                        maxTime = (timeRange.upperBound - timeRange.lowerBound) * 1_000_000
                    } else {
                        maxTime = 1_000_000 // FIXME: probe?
                    }
                    
                    var info = [String: String]()
                    pipe.fileHandleForReading.readabilityHandler = { fileHandle in
                        guard let string = String(data: fileHandle.availableData, encoding: .utf8) else { return }
                        for components in string.split(separator: "\n").map({ $0.split(separator: "=") }).filter({ $0.count == 2}) {
                            let key = String(components[0])
                            info[key] = String(components[1])
                            if key == "progress" {
                                //                        print(#function, info)
                                if let time = Int(info["out_time_us"] ?? ""),
                                   time >= 0 { // FIXME: reset global variable(s) causing it
                                    let progress = Double(time) / maxTime
                                    //                                        print(#function, "progress:", progress
                                    //                                  , info["out_time_us"] ?? "nil", time
                                    //                                        )
                                    progressBlock(progress)
                                }
                                guard info["progress"] != "end" else {
                                    fileHandle.readabilityHandler = nil
                                    break
                                }
                                info.removeAll()
                            }
                        }
                        //                            print(#function, string)
                    }
                } else {
                    // Fallback on earlier versions
                }
                
                args.insert(contentsOf: [
                    "-progress", "pipe:\(pipe.fileHandleForWriting.fileDescriptor)",
                    "-nostats",
                ], at: 1)
            }
        }
        
//        print(#function, args)
        return args[0] == "ffmpeg" ? ffmpeg(args) : ffprobe(args)
    }
    
    var willTranscode: (() -> ((Double) -> Void)?)?
    
    func makePythonObject(_ options: PythonObject? = nil, initializePython: Bool = true) async throws -> PythonObject {
        let pythonModule = try await loadPythonModule()
        let options = options ?? defaultOptions
        pythonObject = pythonModule.YoutubeDL(options)
        self.options = options
        return pythonObject!
    }
        
    public typealias FormatSelector = (Info) async -> ([Format], URL?, TimeRange?, Double?, String)
    
    open func download(url: URL, options: Options = [.background, .chunked], formatSelector: FormatSelector? = nil) async throws -> URL {
        downloader.progress = Progress()
        
        var (formats, info) = try await extractInfo(url: url)
        
        var directory: URL?
        var timeRange: Range<TimeInterval>?
        let bitRate: Double?
        let title: String
        if let formatSelector = formatSelector {
            (formats, directory, timeRange, bitRate, title) = await formatSelector(info)
            guard !formats.isEmpty else { throw YoutubeDLError.canceled }
        } else {
            bitRate = formats[0].vbr
            title = info.safeTitle
        }
        
        pendingDownloads.append(Download(formats: [],
                                         directory: directory ?? downloadsDirectory,
                                         safeTitle: title,
                                         options: options,
                                         timeRange: timeRange,
                                         bitRate: bitRate,
                                         transcodePending: false))
        
        await downloader.session.allTasks.forEach { $0.cancel() }
        
        for format in formats {
            try download(format: format, resume: !downloader.isDownloading || isTest, chunked: options.contains(.chunked), directory: directory ?? downloadsDirectory, title: info.safeTitle)
        }
        
        for await url in finished {
            // FIXME: validate url
            return url
        }
        fatalError()
    }
    
    func savePendingDownloads() {
        do {
            try JSONEncoder().encode(pendingDownloads).write(to: pendingDownloadsURL)
        } catch {
            print(#function, error)
        }
    }
    
    func loadPendingDownloads() -> [Download] {
        do {
            return try JSONDecoder().decode([Download].self,
                                            from: try Data(contentsOf: pendingDownloadsURL))
        } catch {
            print(#function, error)
            return []
        }
    }
    
    func processPendingDownload() {
        guard let index = pendingDownloads.firstIndex(where: { !$0.formats.isEmpty }) else {
            return
        }

        let format = pendingDownloads[index].formats.remove(at: 0)
        
        Task {
            let download = pendingDownloads[index]
            try self.download(format: format, resume: true, chunked: download.options.contains(.chunked), directory: download.directory, title: download.safeTitle)
        }
    }
    
    func makeURL(directory: URL? = nil, title: String, kind: Kind, ext: String) -> URL {
        (directory ?? downloadsDirectory).appendingPathComponent(
            title
                .appending(Kind.separator)
                .appending(kind.rawValue))
            .appendingPathExtension(ext)
    }
    
    open func download(format: Format, resume: Bool, chunked: Bool, directory: URL, title: String) throws {
        let kind: Kind = format.isVideoOnly
        ? (!format.isTranscodingNeeded ? .videoOnly : .otherVideo)
        : (format.isAudioOnly ? .audioOnly : .complete)
        
        func download(for request: URLRequest, resume: Bool) throws {
            let progress: Progress? = downloader.progress
            progress?.kind = .file
            progress?.fileOperationKind = .downloading
            let url = makeURL(directory: directory, title: title, kind: kind, ext: format.ext)
            do {
                try Data().write(to: url)
            }
            catch {
                print(#function, error)
            }
            progress?.fileURL = url
            
            removeItem(at: url)

            let task = downloader.download(request: request, url: url, resume: resume)
            
            if task.hasPrefix(0) {
                guard FileManager.default.createFile(atPath: url.appendingPathExtension("part").path, contents: nil) else { fatalError() }
            }
            
            print(#function, "start download:", task.info)
        }
        
        if chunked, let size = format.filesize {
            guard var request = format.urlRequest else { fatalError() }
            var start: Int64 = 0
            while start < size {
                // https://github.com/ytdl-org/youtube-dl/issues/15271#issuecomment-362834889
                let end = request.setRange(start: start, fullSize: Int64(size))
//                print(#function, "first chunked size:", end + 1)
                
                try download(for: request, resume: resume && start == 0)
                start = end + 1
            }
        } else {
            guard let request = format.urlRequest else { fatalError() }
            
            try download(for: request, resume: resume)
        }
    }
   
    open func extractInfo(url: URL) async throws -> ([Format], Info) {
        let pythonObject: PythonObject
        if let _pythonObject = self.pythonObject {
            pythonObject = _pythonObject
        } else {
            pythonObject = try await makePythonObject()
        }

        print(#function, url)
        let info = try pythonObject.extract_info.throwing.dynamicallyCall(withKeywordArguments: ["": url.absoluteString, "download": false, "process": true])
        print(info)
//        print(#function, "throttled:", pythonObject.throttled)
        
        let format_selector = pythonObject.build_format_selector(options!["format"])
        let formats_to_download = format_selector(info)
        var formats: [Format] = []
        let decoder = PythonDecoder()
        for format in formats_to_download {
            let format = try decoder.decode(Format.self, from: format)
            formats.append(format)
        }
        
        return (formats, try decoder.decode(Info.self, from: info))
    }
    
    func tryMerge(directory: URL, title: String, timeRange: TimeRange?) -> Bool {
        let t0 = ProcessInfo.processInfo.systemUptime
       
        let videoURL = makeURL(directory: directory, title: title, kind: .videoOnly, ext: "mp4")
        let audioURL: URL = makeURL(directory: directory, title: title, kind: .audioOnly, ext: "m4a")
        let videoAsset = AVAsset(url: videoURL)
        let audioAsset = AVAsset(url: audioURL)
        
        guard let videoAssetTrack = videoAsset.tracks(withMediaType: .video).first,
              let audioAssetTrack = audioAsset.tracks(withMediaType: .audio).first else {
            print(#function,
                  videoAsset.tracks(withMediaType: .video),
                  audioAsset.tracks(withMediaType: .audio))
            return false
        }
        
        let composition = AVMutableComposition()
        let videoCompositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let audioCompositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        
        do {
            try videoCompositionTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: videoAssetTrack.timeRange.duration), of: videoAssetTrack, at: .zero)
            let range: CMTimeRange
            if let timeRange = timeRange {
                range = CMTimeRange(start: CMTime(seconds: timeRange.lowerBound, preferredTimescale: 1),
                                    end: CMTime(seconds: timeRange.upperBound, preferredTimescale: 1))
            } else {
                range = CMTimeRange(start: .zero, duration: audioAssetTrack.timeRange.duration)
            }
            try audioCompositionTrack?.insertTimeRange(range, of: audioAssetTrack, at: .zero)
            print(#function, videoAssetTrack.timeRange, range)
        }
        catch {
            print(#function, error)
            return false
        }
        
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            print(#function, "unable to init export session")
            return false
        }
        let outputURL = directory.appendingPathComponent(title).appendingPathExtension("mp4")
        
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
        return true
    }
    
    open func transcode(directory: URL) async throws {
        guard let download = pendingDownloads.first(where: { $0.directory.path == directory.path }) else {
            print(#function, "no download with", directory, pendingDownloads.map(\.directory))
            return
        }
        
        DispatchQueue.main.async {
            guard UIApplication.shared.applicationState == .active else {
                guard let index = self.pendingDownloads.firstIndex(where: { $0.directory.path == directory.path }) else { fatalError() }
                self.pendingDownloads[index].transcodePending = true
                
                notify(body: NSLocalizedString("AskTranscode", comment: "Notification body"), identifier: NotificationRequestIdentifier.transcode.rawValue)
                return
            }
            
            //            let alert = UIAlertController(title: nil, message: NSLocalizedString("DoNotSwitch", comment: "Alert message"), preferredStyle: .alert)
            //            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Action"), style: .default, handler: nil))
            //            self.topViewController?.present(alert, animated: true, completion: nil)
        }
        
        let url = makeURL(directory: directory, title: download.safeTitle, kind: .otherVideo, ext: "webm") // FIXME: ext
        let outURL = makeURL(directory: directory, title: download.safeTitle, kind: .videoOnly, ext: "mp4")
        
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
        
        transcoder?.progressBlock = { progress in
            print(#function, "progress:", progress)
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
        
        defer {
            transcoder = nil
        }
        
        try transcoder?.transcode(from: url, to: outURL, timeRange: download.timeRange, bitRate: download.bitRate)
        
        print(#function, "took", downloader.dateComponentsFormatter.string(from: ProcessInfo.processInfo.systemUptime - t0) ?? "?")
        
        if !keepIntermediates {
            removeItem(at: url)
        }
        
        notify(body: NSLocalizedString("FinishedTranscoding", comment: "Notification body"))
        
        tryMerge(directory: url.deletingLastPathComponent(), title: url.title, timeRange: download.timeRange)
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
        let stopWatch = StopWatch(); defer { stopWatch.report() }
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

// https://github.com/yt-dlp/yt-dlp/blob/4f08e586553755ab61f64a5ef9b14780d91559a7/yt_dlp/YoutubeDL.py#L338
public func yt_dlp(argv: [String], progress: (([String: PythonObject]) -> Void)? = nil, log: ((String, String) -> Void)? = nil, makeTranscodeProgressBlock: (() -> ((Double) -> Void)?)? = nil) async throws {
    let context = Context()
    let yt_dlp = try await YtDlp(context: context)
    
    let (ydl_opts, all_urls) = try yt_dlp.parseOptions(args: argv)
    
    // https://github.com/yt-dlp/yt-dlp#adding-logger-and-progress-hook
    
    if let log {
        ydl_opts["logger"] = makeLogger(name: "MyLogger", log)
    }
    
    if let progress {
        ydl_opts["progress_hooks"] = [makeProgressHook(progress)]
    }
    
    let myPP = yt_dlp.makePostProcessor(name: "MyPP") { pythonSelf, info in
            do {
                let formats = try info.checking["requested_formats"]
                    .map { try PythonDecoder().decode([Format].self, from: $0) }
                guard let vbr = formats?.first(where: { $0.vbr != nil })?.vbr.map(Int.init) else {
                    return ([], info)
                }
                pythonSelf._downloader.params["postprocessor_args"]
                    .checking["merger+ffmpeg"]?
                    .extend(["-b:v", "\(vbr)k"])
                
                duration = TimeInterval(info["duration"])
//                print(#function, "vbr:", vbr, "duration:", duration ?? "nil", args[0]._downloader.params)
            } catch {
                print(#function, error)
            }
//            print(#function, "MyPP.run:", info["requested_formats"])//, args)
            return ([], info)
        }
    
//    print(#function, ydl_opts)
    let ydl = yt_dlp.makeYoutubeDL(ydlOpts: ydl_opts)
    
    ydl.add_post_processor(myPP, when: "before_dl")
    
    context.willTranscode = makeTranscodeProgressBlock
    
    try ydl.download.throwing.dynamicallyCall(withArguments: all_urls)
}

/// Make custom logger. https://github.com/yt-dlp/yt-dlp#adding-logger-and-progress-hook
/// - Parameters:
///   - name: Python class name
///   - log: closure to be called for each log messages
/// - Returns: logger Python object
public func makeLogger(name: String, _ log: @escaping (String, String) -> Void) -> PythonObject {
    PythonClass(name, members: [
        "debug": PythonInstanceMethod { params in
            let isDebug = String(params[1])!.hasPrefix("[debug] ")
            log(isDebug ? "debug" : "info", String(params[1]) ?? "")
            return Python.None
        },
        "info": PythonInstanceMethod { params in
            log("info", String(params[1]) ?? "")
            return Python.None
        },
        "warning": PythonInstanceMethod { params in
            log("warning", String(params[1]) ?? "")
            return Python.None
        },
        "error": PythonInstanceMethod { params in
            log("error", String(params[1]) ?? "")
            
            let traceback = Python.import("traceback")
            traceback.print_exc()
            
            return Python.None
        },
    ])
        .pythonObject()
}

public func makeProgressHook(_ progress: @escaping ([String: PythonObject]) -> Void) -> PythonObject {
    PythonFunction { (d: PythonObject) in
        let dict: [String: PythonObject] = Dictionary(d) ?? [:]
        progress(dict)
        return Python.None
    }
        .pythonObject
}

var timeRange: TimeRange?

var duration: TimeInterval?

typealias Context = YoutubeDL

public class YtDlp {
    public class YoutubeDL {
        let ydl: PythonObject
        
        let urls: PythonObject
        
        init(ydl: PythonObject, urls: PythonObject) {
            self.ydl = ydl
            self.urls = urls
        }
    }
    
    let yt_dlp: PythonObject
    
    let context: Context
    
    public convenience init() async throws {
        try await self.init(context: Context())
    }
    
    init(context: Context) async throws {
        yt_dlp = try await context.loadPythonModule()
        self.context = context
    }
    
    public func parseOptions(args: [String]) throws -> (ydlOpts: PythonObject, allURLs: PythonObject) {
        let (parser, _, all_urls, ydl_opts) = try yt_dlp.parse_options.throwing.dynamicallyCall(withKeywordArguments: ["argv": args])
            .tuple4
        
        parser.destroy()
        
        return (ydl_opts, all_urls)
    }

    public func makePostProcessor(name: String, run: @escaping (PythonObject, PythonObject) -> ([String], PythonObject)) -> PythonObject {
        PythonClass(name, superclasses: [yt_dlp.postprocessor.PostProcessor], members: [
            "run": PythonFunction { args in
                let `self` = args[0]
                let info = args[1]
                let (filesToDelete, infoDict) = run(self, info)
                return Python.tuple([filesToDelete.pythonObject, infoDict])
            }
        ])
            .pythonObject()
    }

    func makeYoutubeDL(ydlOpts: PythonObject) -> PythonObject {
        yt_dlp.YoutubeDL(ydlOpts)
    }
}

public extension YtDlp.YoutubeDL {
    convenience init(args: [String]) async throws {
        let yt_dlp = try await YtDlp()
        let (ydlOpts, allUrls) = try yt_dlp.parseOptions(args: args)
        self.init(ydl: yt_dlp.makeYoutubeDL(ydlOpts: ydlOpts), urls: allUrls)
    }
    
    func download(urls: [URL]? = nil) throws {
        let urls = urls?.map(\.absoluteString).pythonObject ?? self.urls
        try ydl.download.throwing.dynamicallyCall(withArguments: urls)
    }
}
