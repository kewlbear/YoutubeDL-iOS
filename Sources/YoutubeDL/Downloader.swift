//
//  Downloader.swift
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

import UIKit

public enum NotificationRequestIdentifier: String {
    case transcode
}

public enum Kind: String, CustomStringConvertible {
    case complete, videoOnly, audioOnly, otherVideo
   
    public var description: String { rawValue }
    
    static let separator = "-"
}

@available(iOS 12.0, *)
open class Downloader: NSObject {

    typealias Continuation = CheckedContinuation
   
    public static let shared = Downloader(backgroundURLSessionIdentifier: "YoutubeDL-iOS")
    
    open lazy var session: URLSession = URLSession.shared
    
    var isDownloading = false
    
    let decimalFormatter = NumberFormatter()
    
    let percentFormatter = NumberFormatter()
    
    public let dateComponentsFormatter = DateComponentsFormatter()
    
    var t = ProcessInfo.processInfo.systemUptime
    
    var bytesWritten: Int64 = 0
    
    open var t0 = ProcessInfo.processInfo.systemUptime
   
    open var progress = Progress()
    
    var currentRequest: URLRequest?
    
    var didFinishBackgroundEvents: Continuation<Void, Never>?
    
    lazy var stream: AsyncStream<(URL, Kind)> = {
        AsyncStream { continuation in
            streamContinuation = continuation
        }
    }()
    
    var streamContinuation: AsyncStream<(URL, Kind)>.Continuation?
    
    public lazy var directory: URL = {
        let url = try! FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Downloads")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
    
    init(backgroundURLSessionIdentifier: String?, createURLSession: Bool = true) {
        super.init()
        
        decimalFormatter.numberStyle = .decimal

        percentFormatter.numberStyle = .percent
        percentFormatter.minimumFractionDigits = 1
        
        guard createURLSession else { return }
        
        var configuration: URLSessionConfiguration
        if let identifier = backgroundURLSessionIdentifier {
            configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        } else {
            configuration = .default
        }

        configuration.networkServiceType = .responsiveAV
        
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        print(session, "created")
    }

    open func download(request: URLRequest, url: URL, resume: Bool) -> URLSessionDownloadTask {
        currentRequest = request
        
        let task = session.downloadTask(with: request)
        task.taskDescription = url.relativePath
//        task.priority = URLSessionTask.highPriority
        
        if resume {
            isDownloading = true
            task.resume()
        }
        return task
    }
}

public func removeItem(at url: URL) {
    do {
        try FileManager.default.removeItem(at: url)
//        print(#function, "removed", url.lastPathComponent)
    }
    catch {
        let error = error as NSError
        if error.domain != NSCocoaErrorDomain || error.code != CocoaError.fileNoSuchFile.rawValue {
            print(#function, error)
        }
    }
}

@available(iOS 12.0, *)
extension Downloader: URLSessionDelegate {
    public convenience init(identifier: String) async {
        self.init(backgroundURLSessionIdentifier: identifier, createURLSession: false)
        
        await withCheckedContinuation { (continuation: Continuation<Void, Never>) in
            didFinishBackgroundEvents = continuation
            
            let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
            session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        }
    }
    
    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        print(#function, session, error ?? "no error")
    }
    
    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        print(#function, session)
        didFinishBackgroundEvents?.resume()
    }
}

@available(iOS 12.0, *)
extension Downloader: URLSessionTaskDelegate {
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
//        print(#function, session, task, error ?? "no error")
        if let error = error {
            print(#function, session, task, error)
        }
    }
}

public class StopWatch {
    let t0 = Date()
    
    let name: String
    
    public init(name: String = #function) {
        self.name = name
        report(item: #function)
    }
    
    deinit {
//        report(item: #function)
    }
    
    public func report(item: String? = nil) {
        let now = Date()
        print(now, item ?? name, "took", now.timeIntervalSince(t0), "seconds")
    }
}

@available(iOS 12.0, *)
extension Downloader: URLSessionDownloadDelegate {
   
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let taskDescription = downloadTask.taskDescription else {
            print(#function, "no task description", downloadTask)
            return
        }
        
//        guard currentRequest == nil || downloadTask.originalRequest == currentRequest && downloadTask.originalRequest?.value(forHTTPHeaderField: "Range") == currentRequest?.value(forHTTPHeaderField: "Range") else {
//            print(#function, "ignore", downloadTask.info, "(current request:", currentRequest ?? "nil", ")")
//            return
//        }
        
        let (_, range, size) = (downloadTask.response as? HTTPURLResponse)?.contentRange
            ?? (nil, -1 ..< -1, -1)
        print(#function, range, size, downloadTask.info, currentRequest?.value(forHTTPHeaderField: "Range") ?? "no current request or range"
//              , session, location
        )
        
        let kind = downloadTask.kind
        let url = downloadTask.taskDescription.map {
            URL(fileURLWithPath: $0, relativeTo: directory)
        } ?? directory.appendingPathComponent("complete.mp4")

        do {
            func resume(selector: @escaping ([URLSessionDownloadTask]) -> URLSessionDownloadTask?) {
                Task {
                    let tasks = await session.tasks.2
                    guard let task = selector(tasks.filter { $0.state == .suspended }) else {
                        print(#function, "no more task", tasks.map(\.state.rawValue))
                        return
                    }
                    print(#function, task.kind, task.originalRequest?.value(forHTTPHeaderField: "Range") ?? "no range", task.taskDescription ?? "no task description")
                    task.resume()
                }
            }
            
            if range.isEmpty {
                notify(body: "finished \(url.lastPathComponent)")
                removeItem(at: url)
                try FileManager.default.moveItem(at: location, to: url)
                print(#function, "moved to", url.path)
                
                resume { tasks in
                    tasks.first { $0.hasPrefix(0) }
                    ?? tasks.first
                }
                
                streamContinuation?.yield((url, kind))
            } else {
                //                notify(body: "\(range.upperBound * 100 / size)% \(url.lastPathComponent)")
                let part = url.appendingPathExtension("part")
                let file = try FileHandle(forWritingTo: part)
                
                try file.seek(toOffset: UInt64(range.lowerBound))
                
                let data = try Data(contentsOf: location, options: .alwaysMapped)
                
                file.write(data)
                
                try file.close()
                
                guard range.upperBound >= size else {
                    resume { tasks in
                        tasks.first {
                            $0.taskDescription == downloadTask.taskDescription
                            && $0.hasPrefix(range.upperBound)
                        }
                        ?? tasks.first { $0.hasPrefix(0) }
                        ?? tasks.first
                    }
                    return
                }
                
                resume { tasks in
                    tasks.first { $0.hasPrefix(0) }
                    ?? tasks.first
                }
                
                try FileManager.default.moveItem(at: part, to: url)
                
                let result = streamContinuation?.yield((url, kind))
                guard case .enqueued(remaining: _) = result else { fatalError() }
            }
            
            DispatchQueue.main.async {
                if self.progress.fileTotalCount != nil {
                    self.progress.fileCompletedCount = (self.progress.fileCompletedCount ?? 0) + 1
                }
            }
        }
        catch {
            print(error)
        }
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let t = ProcessInfo.processInfo.systemUptime
        guard t - self.t > 0.9 else {
            return
        }
        
        let elapsed = t - self.t
        self.t = t
        let (_, range, size) = (downloadTask.response as? HTTPURLResponse)?.contentRange ?? (nil, 0..<0, totalBytesExpectedToWrite)
        let count = range.lowerBound + totalBytesWritten - self.bytesWritten
        self.bytesWritten = range.lowerBound + totalBytesWritten
        let bytesPerSec = Double(count) / elapsed
        let remain = Double(size - self.bytesWritten) / bytesPerSec
        
        DispatchQueue.main.async {
            let progress = self.progress
            progress.totalUnitCount = size
            progress.completedUnitCount = self.bytesWritten
            progress.throughput = Int(bytesPerSec)
            progress.estimatedTimeRemaining = remain
        }
    }
}

extension URLSessionDownloadTask {
    public var kind: Kind {
        Kind(rawValue: URL(fileURLWithPath: taskDescription ?? "")
                .deletingPathExtension()
                .path.components(separatedBy: Kind.separator)
                .last ?? "")
        ?? .complete
    }
    
    func hasPrefix(_ start: Int64) -> Bool {
        (originalRequest?.value(forHTTPHeaderField: "Range") ?? "")
            .hasPrefix("bytes=\(start)-")
    }
}

var isTest = false

// FIXME: move to view controller?
@available(iOS 12.0, *)
public func notify(body: String, identifier: String = "Download") {
    guard !isTest else { return }
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound, .providesAppNotificationSettings]) { (granted, error) in
        guard granted else {
            print(#function, "granted =", granted, error ?? "no error")
            return
        }
        
        print(#function, body)
        let content = UNMutableNotificationContent()
        content.body = body
        let notificationRequest = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(notificationRequest, withCompletionHandler: nil)
    }
}
