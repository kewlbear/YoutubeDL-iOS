//
//  Copyright (c) 2023 Changbeom Ahn
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

import XCTest
@testable import YoutubeDL
import PythonKit
import PythonSupport
    
final class YoutubeDL_iOSTests: XCTestCase {
    func testPy_IsInitialized() {
        XCTAssertEqual(Py_IsInitialized(), 0)
        PythonSupport.initialize()
        XCTAssertEqual(Py_IsInitialized(), 1)
    }
    
    func testExtractInfo() async throws {
        let youtubeDL = YoutubeDL()
        let (formats, info) = try await youtubeDL.extractInfo(url: URL(string: "https://www.youtube.com/watch?v=WdFj7fUnmC0")!)
        print(formats, info)
        XCTAssertEqual(info.title, "YoutubeDL iOS app demo")
        XCTAssertGreaterThan(formats.count, 0)
    }

    func testDownload() async throws {
        let youtubeDL = YoutubeDL()
        youtubeDL.downloader = Downloader(backgroundURLSessionIdentifier: nil)
        isTest = true
        let url = try await youtubeDL.download(url: URL(string: "https://www.youtube.com/watch?v=WdFj7fUnmC0")!)
        print(#function, url)
    }

    func testDownloads() async throws {
        let youtubeDL = YoutubeDL()
        youtubeDL.downloader = Downloader(backgroundURLSessionIdentifier: nil)
        isTest = true
        var url = try await youtubeDL.download(url: URL(string: "https://www.youtube.com/watch?v=WdFj7fUnmC0")!)
        print(#function, url)
        url = try await youtubeDL.download(url: URL(string: "https://youtu.be/TaUuUDIg6no")!)
        print(#function, url)
    }

    func testError() async throws {
        let youtubeDL = YoutubeDL()
        do {
            _ = try await youtubeDL.extractInfo(url: URL(string: "https://apple.com")!)
        } catch {
            guard let pyError = error as? PythonError, case let .exception(exception, traceback: traceback) = pyError else {
                throw error
            }
            print(exception, traceback ?? "nil")
            let message = String(exception.args[0]) ?? ""
            XCTAssert(message.contains("Unsupported URL: "))
        }
    }

    func testPythonDecoder() async throws {
        let youtubeDL = YoutubeDL()
        let (formats, info) = try await youtubeDL.extractInfo(url: URL(string: "https://www.youtube.com/watch?v=WdFj7fUnmC0")!)
        print(formats, info)
    }
    
    func testDirect() async throws {
        print(FileManager.default.currentDirectoryPath)
        try await yt_dlp(argv: [
//            "-F",
//            "-f", "bestvideo+bestaudio[ext=m4a]/best",
            "https://m.youtube.com/watch?v=ezEYcU9Pp_w",
            "--no-check-certificates",
        ], progress: { dict in
            print(#function, dict["status"] ?? "no status?", dict["filename"] ?? "no filename?", dict["elapsed"] ?? "no elapsed", dict.keys)
        }, log: { level, message in
            print(#function, level, message)
        })
    }
    
    func testExtractMP3() async throws {
        print(FileManager.default.currentDirectoryPath)
        try await yt_dlp(argv: [
            "-x", "--audio-format", "mp3", "--embed-thumbnail", "--add-metadata",
            "https://youtu.be/Qc7_zRjH808",
            "--no-check-certificates",
        ])
    }
    
    @available(iOS 16.0, *)
    func testJson() async throws {
        print(FileManager.default.currentDirectoryPath)
        var filename: String?
        try await yt_dlp(argv: [
            "--write-info-json",
            "--skip-download",
            "https://youtube.com/shorts/y6bGD7WxHIU?feature=share",
            "--no-check-certificates",
        ], log: { level, message in
            print(#function, level, message)
            if let range = message.range(of: "Writing video metadata as JSON to: ") {
                filename = String(message[range.upperBound...])
            }
        })

        guard let filename else { fatalError() }
        let data = try Data(contentsOf: URL(filePath: filename))
        let info = try JSONDecoder().decode(Info.self, from: data)
        print(#function, info)
    }
                         
    static var allTests = [
        ("testExtractInfo", testExtractInfo),
    ]
}
