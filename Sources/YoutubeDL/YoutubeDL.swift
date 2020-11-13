import Foundation
import PythonKit

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
        "\(format["format"] ?? "no format?") \(format["ext"] ?? "no ext?") \(format["filesize"] ?? "no size?")"
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
    let youtubeDL: PythonObject

    let options: PythonObject
    
    public init(options: PythonObject = defaultOptions) throws {
        let youtube_dl = try Python.attemptImport("youtube_dl")
        youtubeDL = youtube_dl.YoutubeDL(options)
        self.options = options
    }
    
    open func download(url: URL, urlSession: URLSession = .shared, completionHandler: @escaping (Result<URL, Error>) -> Void) {
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
        let info = try youtubeDL.extract_info.throwing.dynamicallyCall(withKeywordArguments: ["": url.absoluteString, "download": false, "process": true])
        
        let format_selector = youtubeDL.build_format_selector(options["format"])
        let formats_to_download = format_selector(info)
        var formats: [Format] = []
        for format in formats_to_download {
            guard let dict: [String: PythonObject] = Dictionary(format) else { fatalError() }
            formats.append(Format(format: dict))
        }
        
        return (formats, Info(info: info))
    }
}
