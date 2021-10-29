//
//  Copyright (c) 2021 Changbeom Ahn
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

final class YoutubeDLTests: XCTestCase {
    func testExtractInfo() async throws {
        let youtubeDL = try await YoutubeDL()
        let (formats, info) = try youtubeDL.extractInfo(url: URL(string: "https://www.youtube.com/watch?v=WdFj7fUnmC0")!)
        print(formats, info ?? "nil")
        XCTAssertEqual(info?.title, "YoutubeDL iOS app demo")
        XCTAssertGreaterThan(formats.count, 0)
    }

    func testDownload() async throws {
        let youtubeDL = try await YoutubeDL()
        youtubeDL.downloader = Downloader(backgroundURLSessionIdentifier: nil)
        let url = try await youtubeDL.download(url: URL(string: "https://www.youtube.com/watch?v=WdFj7fUnmC0")!)
        print(#function, url)
    }

    func testError() async throws {
        let youtubeDL = try await YoutubeDL()
        do {
            _ = try youtubeDL.extractInfo(url: URL(string: "https://apple.com")!)
        } catch {
            guard let pyError = error as? PythonError, case let .exception(exception, traceback: traceback) = pyError else {
                throw error
            }
            print(exception, traceback ?? "nil")
            let message = String(exception.args[0]) ?? ""
            XCTAssert(message.contains("Unsupported URL: "))
        }
    }

    static var allTests = [
        ("testExtractInfo", testExtractInfo),
    ]
}
