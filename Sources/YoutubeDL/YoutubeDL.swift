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

let chunkSize: Int64 = 10_000_000

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
]

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
    
    public let version: String?
    
    public lazy var downloader = Downloader.shared
    
    internal let pythonObject: PythonObject

    internal let options: PythonObject
    
    public init(options: PythonObject = defaultOptions) throws {
        guard FileManager.default.fileExists(atPath: Self.pythonModuleURL.path) else {
            throw Error.noPythonModule
        }
        
        let sys = try Python.attemptImport("sys")
        if !(Array(sys.path) ?? []).contains(Self.pythonModuleURL.path) {
            sys.path.insert(1, Self.pythonModuleURL.path)
        }
        
        runSimpleString("""
            class Pop:
                pass

            import subprocess
            subprocess.Popen = Pop
            """)
        
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
        
    open func download(url: URL, options: Options = [.chunked, .background]) async throws -> URL {
        let (formats, info) = try extractInfo(url: url)
        
        for format in formats {
            let url = try await download(format: format, faster: options.contains(.chunked))
            print(#function, "downloaded to:", url)
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            self.downloader.continuation = continuation
        }
    }
    
    open func download(format: Format, faster: Bool) async throws -> URL {
        let kind: Downloader.Kind = format.isVideoOnly
        ? (!format.isTranscodingNeeded ? .videoOnly : .otherVideo)
        : (format.isAudioOnly ? .audioOnly : .complete)
        
        func download(for request: URLRequest) async throws -> URL {
            let progress: Progress? = downloader.progress
            progress?.kind = .file
            progress?.fileOperationKind = .downloading
            do {
                try "".write(to: kind.url, atomically: false, encoding: .utf8)
            }
            catch {
                print(error)
            }
            progress?.fileURL = kind.url
            
            let task = downloader.download(request: request, kind: kind)
            print(#function, "start download:", task.info)
            
            return try await withCheckedThrowingContinuation { continuation in
                self.downloader.continuation = continuation
            }
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
    
    open func download(url: URL, urlSession: URLSession = .shared, completionHandler: @escaping (Result<URL, Swift.Error>) -> Void) {
        DispatchQueue.global().async {
            do {
                let (formats, info) = try self.extractInfo(url: url)
            }
            catch {
                completionHandler(.failure(error))
            }
        }
    }
    
    open func extractInfo(url: URL) throws -> ([Format], Info?) {
        print(#function, url)
        let info = try pythonObject.extract_info.throwing.dynamicallyCall(withKeywordArguments: ["": url.absoluteString, "download": false, "process": true])
        
        let format_selector = pythonObject.build_format_selector(options["format"])
        let formats_to_download = format_selector(info)
        var formats: [Format] = []
        for format in formats_to_download {
            guard let dict: [String: PythonObject] = Dictionary(format) else { fatalError() }
            formats.append(Format(format: dict))
        }
        
        return (formats, Info(info: info))
    }
    
    fileprivate static func movePythonModule(_ location: URL) throws {
        do {
            try FileManager.default.removeItem(at: pythonModuleURL)
        }
        catch {
            print(error)
        }
        
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
}

extension URLSessionDownloadTask {
    var info: String {
        "\(taskDescription ?? "no task description") \(originalRequest?.value(forHTTPHeaderField: "Range") ?? "no range")"
    }
}
