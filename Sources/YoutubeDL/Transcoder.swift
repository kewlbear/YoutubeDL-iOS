//
//  Transcoder.swift
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

import CoreVideo
import ExitHook

enum TranscoderError: Error {
    case unexpected
}

extension Int32: Error {
    
}

open class Transcoder {
    open var isCancelled = false
    
    var progressBlock: ((Double) -> Void)?
    
    var frameBlock: ((CVPixelBuffer) -> Void)?
    
    public init() {
        
    }
    
    public func transcode(from: URL, to url: URL) -> Int32 {
        let progress = "\(NSTemporaryDirectory())/ffmpeg-progress"
        
        do {
            try FileManager.default.removeItem(atPath: progress)
            print("progress: removed")
        }
        catch {
            print("progress:", error)
        }
        
        var fileHandle: FileHandle?
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            fileHandle = FileHandle(forReadingAtPath: progress)
            guard fileHandle != nil else {
                print("progress: no file")
                return
            }
            fileHandle?.readabilityHandler = {
                let data = $0.availableData
                guard let string = String(data: data, encoding: .utf8) else {
                    print("progress:", data)
                    return
                }
                print("progress:", string)
            }
        }
        
        let args: [String?] = ["app",
                               "-progress", progress,
                               "-i", from.path,
                               url.path,
                               nil]
        
        var argv = args.map { $0.flatMap { strdup($0) } }
        defer {
            argv.forEach { $0.map { free($0) } }
        }

        return ffmpeg(Int32(args.count - 1), &argv)
    }
}

func AVERROR(_ e: Int32) -> Int32 {
    -e
}
