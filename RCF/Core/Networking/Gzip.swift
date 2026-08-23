import Foundation
import zlib

/// libz-backed gzip decompression for tail binary frames (0x1f8b magic).
nonisolated enum Gzip {
    /// Returns true when the payload starts with the gzip magic bytes.
    static func isGzipped(_ data: Data) -> Bool {
        data.count > 2 && data[data.startIndex] == 0x1f && data[data.startIndex + 1] == 0x8b
    }

    /// Inflates a gzip payload. Throws on malformed input.
    static func decompress(_ data: Data) throws -> Data {
        var stream = z_stream()
        stream.next_in = UnsafeMutablePointer<Bytef>(mutating: (data as NSData).bytes.bindMemory(to: Bytef.self, capacity: data.count))
        stream.avail_in = uInt(data.count)

        // 15 + 32 = auto-detect gzip/zlib headers, window size 32KB.
        guard inflateInit2_(&stream, 15 + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw CloudflareError.decoding(URLError(.cannotDecodeRawData))
        }
        defer { inflateEnd(&stream) }

        var output = Data()
        let chunkSize = 32_768
        let buffer = UnsafeMutablePointer<Bytef>.allocate(capacity: chunkSize)
        defer { buffer.deallocate() }

        repeat {
            stream.next_out = buffer
            stream.avail_out = uInt(chunkSize)
            let status = inflate(&stream, Z_NO_FLUSH)
            switch status {
            case Z_OK, Z_STREAM_END:
                let produced = chunkSize - Int(stream.avail_out)
                output.append(buffer, count: produced)
            default:
                throw CloudflareError.decoding(URLError(.cannotDecodeRawData))
            }
        } while stream.avail_out == 0

        return output
    }

    /// Convenience: frame bytes → UTF-8 string (decompressing when gzipped).
    static func decodeFrame(_ data: Data) throws -> String {
        let payload = isGzipped(data) ? try decompress(data) : data
        guard let text = String(data: payload, encoding: .utf8) else {
            throw CloudflareError.decoding(URLError(.cannotDecodeContentData))
        }
        return text
    }
}
