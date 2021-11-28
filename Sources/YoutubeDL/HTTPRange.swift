//
//  HTTPRange.swift
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

extension HTTPURLResponse {
    public var contentRange: (String?, Range<Int64>, Int64)? {
        var contentRange: String?
        if #available(iOS 13.0, *) {
            contentRange = value(forHTTPHeaderField: "Content-Range")
        } else {
            contentRange = allHeaderFields["Content-Range"] as? String
        }
//        print(#function, contentRange ?? "no Content-Range?")
        
        guard let string = contentRange else { return nil }
        let scanner = Scanner(string: string)
        var prefix: NSString?
        var start: Int64 = -1
        var end: Int64 = -1
        var size: Int64 = -1
        guard scanner.scanUpToCharacters(from: .decimalDigits, into: &prefix),
              scanner.scanInt64(&start),
              scanner.scanString("-", into: nil),
              scanner.scanInt64(&end),
              scanner.scanString("/", into: nil),
              scanner.scanInt64(&size) else { return nil }
        return (prefix as String?, Range(start...end), size)
    }
}

extension URLRequest {
    public mutating func setRange(start: Int64, fullSize: Int64) -> Int64 {
        let end = start + chunkSize - 1
        setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
        return end
    }
}
