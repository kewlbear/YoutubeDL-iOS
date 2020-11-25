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
import AVFoundation
import Photos

public enum NotificationRequestIdentifier: String {
    case transcode
}

@available(iOS 12.0, *)
open class Downloader: NSObject {

    public enum Kind: String {
        case complete, videoOnly, audioOnly, otherVideo
        
        public var url: URL {
            do {
                return try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
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
    }
    
    public static let shared = Downloader(backgroundURLSessionIdentifier: "YoutubeDL")
    
    open var session: URLSession = URLSession.shared
    
    let decimalFormatter = NumberFormatter()
    
    let percentFormatter = NumberFormatter()
    
    let dateComponentsFormatter = DateComponentsFormatter()
    
    var t = ProcessInfo.processInfo.systemUptime
    
    open var t0 = ProcessInfo.processInfo.systemUptime
    
    var topViewController: UIViewController? {
        if #available(iOS 14.0, *) {
            return nil
        } else {
            return (UIApplication.shared.keyWindow?.rootViewController as? UINavigationController)?.topViewController
        }
    }
    
    open var transcoder: Transcoder?
    
    open var progress = Progress()
    
    init(backgroundURLSessionIdentifier: String?) {
        super.init()
        
        decimalFormatter.numberStyle = .decimal

        percentFormatter.numberStyle = .percent
        percentFormatter.minimumFractionDigits = 1
        
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

        let task = session.downloadTask(with: request)
        task.taskDescription = kind.rawValue
//        print(#function, request, trace)
        task.priority = URLSessionTask.highPriority
        return task
    }
    
    func tryMerge() {
        let t0 = ProcessInfo.processInfo.systemUptime
        
        DispatchQueue.main.async {
            self.progress.kind = nil
            self.progress.localizedDescription = NSLocalizedString("Merging...", comment: "Progress description")
            self.progress.localizedAdditionalDescription = nil
            self.progress.totalUnitCount = 0
            self.progress.completedUnitCount = 0
            self.progress.estimatedTimeRemaining = nil
        }
        
        let videoAsset = AVAsset(url: Kind.videoOnly.url)
        let audioAsset = AVAsset(url: Kind.audioOnly.url)
        
        guard let videoAssetTrack = videoAsset.tracks(withMediaType: .video).first,
              let audioAssetTrack = audioAsset.tracks(withMediaType: .audio).first else {
            print(#function,
                  videoAsset.tracks(withMediaType: .video),
                  audioAsset.tracks(withMediaType: .audio))
            DispatchQueue.main.async {
                self.topViewController?.navigationItem.title = NSLocalizedString("Merge failed", comment: "Message")
            }
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
            DispatchQueue.main.async {
                self.topViewController?.navigationItem.title = error.localizedDescription
            }
            return
        }
        
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            print(#function, "unable to init export session")
            return
        }
        let outputURL = Kind.videoOnly.url.deletingLastPathComponent().appendingPathComponent("output.mp4")
        
        try? FileManager.default.removeItem(at: outputURL)
        
        session.outputURL = outputURL
        session.outputFileType = .mp4
        print(#function, "merging...")
        DispatchQueue.main.async {
            self.topViewController?.navigationItem.title = NSLocalizedString("Merging...", comment: "Message") 
        }
        session.exportAsynchronously {
            print(#function, "finished merge", session.status.rawValue)
            print(#function, "took", self.dateComponentsFormatter.string(from: ProcessInfo.processInfo.systemUptime - t0) ?? "?")
            if session.status == .completed {
                self.export(outputURL)
            } else {
                print(#function, session.error ?? "no error?")
                DispatchQueue.main.async {
                    self.topViewController?.navigationItem.title = "Merge failed: \(session.error?.localizedDescription ?? "no error?")"
                }
            }
        }
    }
    
    open func transcode() {
        DispatchQueue.main.async {
            guard UIApplication.shared.applicationState == .active else {
                notify(body: NSLocalizedString("AskTranscode", comment: "Notification body"), identifier: NotificationRequestIdentifier.transcode.rawValue)
                return
            }
            
            let alert = UIAlertController(title: nil, message: NSLocalizedString("DoNotSwitch", comment: "Alert message"), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Action"), style: .default, handler: nil))
            self.topViewController?.present(alert, animated: true, completion: nil)
        }
        
        _ = assemble(to: Kind.audioOnly.url, size: .max)
        
        let size = assemble(to: Kind.videoOnly.url, size: .max)
        guard size < 1 else {
            tryMerge()
            return
        }

        _ = assemble(to: Kind.otherVideo.url, size: .max)
        
        do {
            try FileManager.default.removeItem(at: Kind.videoOnly.url)
        }
        catch {
            print(#function, error)
        }

        DispatchQueue.main.async {
            self.progress.kind = nil
            self.progress.localizedDescription = NSLocalizedString("Transcoding...", comment: "Progress description")
            self.progress.totalUnitCount = 100
            
            self.topViewController?.navigationItem.title = NSLocalizedString("Transcoding...", comment: "Message")
        }

        let t0 = ProcessInfo.processInfo.systemUptime

        transcoder = Transcoder()
        var ret: Int32?

        func requestProgress() {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                self.transcoder?.progressBlock = { progress in
                    self.transcoder?.progressBlock = nil

                    let elapsed = ProcessInfo.processInfo.systemUptime - t0
                    let speed = progress / elapsed
                    let ETA = (1 - progress) / speed

                    guard ETA.isFinite else { return }

                    DispatchQueue.main.async {
                        self.progress.completedUnitCount = Int64(progress * 100)
                        self.progress.estimatedTimeRemaining = ETA
                        
                        self.topViewController?.navigationItem.title
                            = String(format: NSLocalizedString("TranscodeProgressFormat", comment: "Message"),
                                     self.percentFormatter.string(from: NSNumber(value: progress)) ?? "?",
                                     self.dateComponentsFormatter.string(from: ETA) ?? "?")
                    }
                }

//                self.transcoder?.frameBlock = { pixelBuffer in
//                    self.transcoder?.frameBlock = nil
//
//                    DispatchQueue.main.async {
//                        (self.topViewController as? DownloadViewController)?.pixelBuffer = pixelBuffer
//                    }
//                }
                if ret == nil {
                    requestProgress()
                }
            }
        }

        requestProgress()

        ret = transcoder?.transcode(from: Kind.otherVideo.url, to: Kind.videoOnly.url)

        transcoder = nil

        print(#function, ret ?? "nil?", "took", dateComponentsFormatter.string(from: ProcessInfo.processInfo.systemUptime - t0) ?? "?")

        notify(body: NSLocalizedString("FinishedTranscoding", comment: "Notification body"))

        tryMerge()
    }
}

@available(iOS 12.0, *)
extension Downloader: URLSessionDelegate {
    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        print(#function, session, error ?? "no error")
    }
    
    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        print(#function, session)
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
    
    fileprivate func export(_ url: URL) {
        DispatchQueue.main.async {
            self.progress.localizedDescription = nil
            self.progress.localizedAdditionalDescription = nil
            self.progress.kind = .file
            self.progress.fileOperationKind = .copying
            self.progress.fileURL = url
            self.progress.completedUnitCount = 0
            self.progress.estimatedTimeRemaining = nil
            self.progress.throughput = nil
            self.progress.fileTotalCount = 1
            
            self.topViewController?.navigationItem.title = NSLocalizedString("Exporting...", comment: "Message")
        }
        
        PHPhotoLibrary.shared().performChanges({
            _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            //                            changeRequest.contentEditingOutput = output
        }) { (success, error) in
            print(#function, success, error ?? "")
            
            notify(body: NSLocalizedString("Download complete!", comment: "Notification body"))
            DispatchQueue.main.async {
                self.progress.fileCompletedCount = 1
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: url.path) as NSDictionary
                    self.progress.completedUnitCount = Int64(attributes.fileSize())
                }
                catch {
                    self.progress.localizedDescription = error.localizedDescription
                }
                
                self.topViewController?.navigationItem.title = NSLocalizedString("Finished", comment: "Message") 
            }
        }
    }
        
    func assemble(to url: URL, size: UInt64) -> UInt64 {
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
            print(#function, error)
        }
        
        removeItem(at: url)
        
        do {
            try FileManager.default.moveItem(at: partURL, to: url)
        }
        catch {
            print(#function, error)
        }
        
        return offset
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let (_, range, size) = (downloadTask.response as? HTTPURLResponse)?.contentRange
            ?? (nil, -1 ..< -1, -1)
//        print(#function, session, location)
        
        let kind = Kind(rawValue: downloadTask.taskDescription ?? "") ?? .complete

        do {
            if range.isEmpty {
                removeItem(at: kind.url)
                try FileManager.default.moveItem(at: location, to: kind.url)
            } else {
                let part = kind.url.appendingPathExtension("part-\(range.lowerBound)")
                removeItem(at: part)
                try FileManager.default.moveItem(at: location, to: part)

                guard range.upperBound >= size else {
                    session.getTasksWithCompletionHandler { (_, _, tasks) in
                        tasks.first {
                            $0.originalRequest?.url == downloadTask.originalRequest?.url
                                && ($0.originalRequest?.value(forHTTPHeaderField: "Range") ?? "")
                                .hasPrefix("bytes=\(range.upperBound)-") }?
                            .resume()
                    }
                    return
                }
            }
            
            DispatchQueue.main.async {
                if self.progress.fileTotalCount != nil {
                    self.progress.fileCompletedCount = (self.progress.fileCompletedCount ?? 0) + 1
                }

                self.topViewController?.navigationItem.prompt = NSLocalizedString("Download finished", comment: "Message")
            }
            
            session.getTasksWithCompletionHandler { (_, _, tasks) in
                print(#function, tasks)
                if let task = tasks.first(where: {
                    let range = $0.originalRequest?.value(forHTTPHeaderField: "Range") ?? ""
                    return $0.state == .suspended && (range.isEmpty || range.hasPrefix("bytes=0-"))
                }) {
                    DispatchQueue.main.async {
                        task.taskDescription.flatMap { Kind(rawValue: $0) }.map { kind in
                            do {
                                try "".write(to: kind.url, atomically: false, encoding: .utf8)
                            }
                            catch {
                                print(error)
                            }
                            self.progress.fileURL = kind.url
                        }
                    }
                    task.resume()
                }
                
                if tasks.isEmpty {
                    self.transcode()
                }
            }
            
            switch kind {
            case .complete:
                export(kind.url)
            case .videoOnly, .audioOnly:
                guard transcoder == nil else {
                    break
                }
                if range.isEmpty {
                    tryMerge()
                } else {
                    DispatchQueue.global(qos: .userInitiated).async {
                        _ = self.assemble(to: kind.url, size: .max)
                        self.tryMerge()
                    }
                }
            case .otherVideo:
                DispatchQueue.global(qos: .userInitiated).async {
                    self.transcode()
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
            self.progress.totalUnitCount = size
            self.progress.completedUnitCount = count
            self.progress.throughput = Int(bytesPerSec)
            self.progress.estimatedTimeRemaining = remain
            
            self.topViewController?.navigationItem.prompt
                = String(format: NSLocalizedString("DownloadProgressFormat", comment: "Message"),
                         percent ?? "?%",
                         ByteCountFormatter.string(fromByteCount: size, countStyle: .file),
                         ByteCountFormatter.string(fromByteCount: Int64(bytesPerSec), countStyle: .file),
                         self.dateComponentsFormatter.string(from: remain) ?? "?",
                         downloadTask.taskDescription ?? "no description?") 
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
