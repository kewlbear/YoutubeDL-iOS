//
//  HTTPRange.swift
//  
//
//  Created by 안창범 on 2020/11/12.
//

import Foundation

extension HTTPURLResponse {
    public var contentRange: (String?, Range<Int64>, Int64)? {
        var contentRange: String?
        if #available(iOS 13.0, *) {
            contentRange = value(forHTTPHeaderField: "Content-Range")
        } else {
            // Fallback on earlier versions
            assertionFailure()
            return nil
        }
        print(#function, contentRange ?? "no Content-Range?")
        
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
        let random = (1..<(chunkSize * 95 / 100)).randomElement().map { start + $0 }
        let end = random ?? (fullSize - 1)
        setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
        return end
    }
}
