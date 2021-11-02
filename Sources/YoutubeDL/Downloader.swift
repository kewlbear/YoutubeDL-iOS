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
    
    public var url: URL {
        do {
            let url = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("Downloads")
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
                .appendingPathComponent("video")
                .appendingPathExtension(self != .audioOnly
                                        ? (self == .otherVideo ? "other" : "mp4")
                                        : "m4a")
        }
        catch {
            print(error)
            fatalError()
        }
    }
    
    public var description: String { rawValue }
}

@available(iOS 12.0, *)
open class Downloader: NSObject {

    typealias Continuation = CheckedContinuation
   
    public static let shared = Downloader(backgroundURLSessionIdentifier: "YoutubeDL-iOS")
    
    open var session: URLSession = URLSession.shared
    
    let decimalFormatter = NumberFormatter()
    
    let percentFormatter = NumberFormatter()
    
    let dateComponentsFormatter = DateComponentsFormatter()
    
    var t = ProcessInfo.processInfo.systemUptime
    
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

    func removeItem(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            print(#function, "removed", url.lastPathComponent)
        }
        catch {
            let error = error as NSError
            if error.domain != NSCocoaErrorDomain || error.code != CocoaError.fileNoSuchFile.rawValue {
                print(#function, error)
            }
        }
    }
    
    open func download(request: URLRequest, kind: Kind) -> URLSessionDownloadTask {
        removeItem(at: kind.url)

        currentRequest = request
        
        let task = session.downloadTask(with: request)
        task.taskDescription = kind.rawValue
        task.priority = URLSessionTask.highPriority
        
        task.resume()
        return task
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
        if let error = error {
            print(#function, session, task, error)
        }
    }
}

@available(iOS 12.0, *)
extension Downloader: URLSessionDownloadDelegate {
   
    func assemble(to url: URL, size: UInt64, kind: Kind? = nil) -> UInt64 {
        let partURL = url.appendingPathExtension("part")
        FileManager.default.createFile(atPath: partURL.path, contents: nil, attributes: nil)
        
        var offset: UInt64 = 0
        
        do {
            let file = try FileHandle(forWritingTo: partURL)
            
            repeat {
                let part = url.appendingPathExtension("part-\(offset)")
                let data = try Data(contentsOf: part, options: .alwaysMapped)
                
                if #available(iOS 13.0, *) {
                    try file.seek(toOffset: offset)
                } else {
                    file.seek(toFileOffset: offset)
                }
                
                file.write(data)
                
                removeItem(at: part)
                
                offset += UInt64(data.count)
            } while offset < size - 1
        }
        catch {
            print(#function, error.localizedDescription)
        }
        
        removeItem(at: url)
        
        do {
            try FileManager.default.moveItem(at: partURL, to: url)
            
            kind.map {
                _ = streamContinuation?.yield((url, $0))
            }
        }
        catch {
            print(#function, error)
        }
        
        return offset
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
//        guard currentRequest == nil || downloadTask.originalRequest == currentRequest && downloadTask.originalRequest?.value(forHTTPHeaderField: "Range") == currentRequest?.value(forHTTPHeaderField: "Range") else {
//            print(#function, "ignore", downloadTask.info, "(current request:", currentRequest ?? "nil", ")")
//            return
//        }
        
        let (_, range, size) = (downloadTask.response as? HTTPURLResponse)?.contentRange
            ?? (nil, -1 ..< -1, -1)
        print(#function, range, size, downloadTask.info, currentRequest?.value(forHTTPHeaderField: "Range") ?? "no current request or range"
//              , session, location
        )
        
        let kind = Kind(rawValue: downloadTask.taskDescription ?? "") ?? .complete

        do {
            if range.isEmpty {
                removeItem(at: kind.url)
                try FileManager.default.moveItem(at: location, to: kind.url)
                print(#function, "moved to", kind.url)
                
                streamContinuation?.yield((kind.url, kind))
            } else {
                let part = kind.url.appendingPathExtension("part-\(range.lowerBound)")
                removeItem(at: part)
                try FileManager.default.moveItem(at: location, to: part)
                print(#function, "moved to", part)

                guard range.upperBound >= size else {
                    guard var request = downloadTask.originalRequest else {
                        print(#function, "no original request")
                        return
                    }
                    let end = request.setRange(start: range.upperBound, fullSize: size)
                    let task = download(request: request, kind: kind)
                    print(#function, "continue download to offset \(end)", task)
                    return
                }
                
                _ = assemble(to: kind.url, size: UInt64(size))
                
                streamContinuation?.yield((kind.url, kind))
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
        self.t = t
        
        let elapsed = t - t0
        let (_, range, size) = (downloadTask.response as? HTTPURLResponse)?.contentRange ?? (nil, 0..<0, totalBytesExpectedToWrite)
        let count = range.lowerBound + totalBytesWritten
        let bytesPerSec = Double(count) / elapsed
        let remain = Double(size - count) / bytesPerSec
        
        let percent = percentFormatter.string(from: NSNumber(value: Double(count) / Double(size)))
        
        DispatchQueue.main.async {
            let progress = self.progress
            progress.totalUnitCount = size
            progress.completedUnitCount = count
            progress.throughput = Int(bytesPerSec)
            progress.estimatedTimeRemaining = remain
        }
    }
}

// FIXME: move to view controller?
@available(iOS 12.0, *)
public func notify(body: String, identifier: String = "Download") {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound, .providesAppNotificationSettings]) { (granted, error) in
        print(#function, "granted =", granted, error ?? "no error")
        guard granted else {
            return
        }
        
        let content = UNMutableNotificationContent()
        content.body = body
        let notificationRequest = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(notificationRequest, withCompletionHandler: nil)
    }
}
