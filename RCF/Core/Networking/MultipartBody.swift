import Foundation

/// Builds multipart/form-data bodies (KV value writes, DNS zone-file import).
nonisolated struct MultipartBody: Sendable {
    struct Part: Sendable {
        let name: String
        let filename: String?
        let contentType: String?
        let data: Data
    }

    private(set) var parts: [Part] = []
    let boundary: String

    init(boundary: String = "rcf-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    /// Adds a plain form field.
    mutating func field(name: String, value: String) {
        parts.append(Part(name: name, filename: nil, contentType: nil, data: Data(value.utf8)))
    }

    /// Adds a file part (e.g. the BIND file for DNS import).
    mutating func file(name: String, filename: String, contentType: String, data: Data) {
        parts.append(Part(name: name, filename: filename, contentType: contentType, data: data))
    }

    /// Value for the HTTP Content-Type header.
    var contentTypeHeader: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    /// Serialized body: --boundary headers, part data, closing boundary.
    func encoded() -> Data {
        var body = Data()
        let crlf = "\r\n"
        for part in parts {
            body.append(Data(("--\(boundary)\(crlf)").utf8))
            var disposition = "Content-Disposition: form-data; name=\"\(part.name)\""
            if let filename = part.filename {
                disposition += "; filename=\"\(filename)\""
            }
            body.append(Data((disposition + crlf).utf8))
            if let contentType = part.contentType {
                body.append(Data(("Content-Type: \(contentType)\(crlf)").utf8))
            }
            body.append(Data(crlf.utf8))
            body.append(part.data)
            body.append(Data(crlf.utf8))
        }
        body.append(Data(("--\(boundary)--\(crlf)").utf8))
        return body
    }
}
