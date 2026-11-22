import Foundation
import Compression

/// Minimal gzip (RFC 1952) decompression using the Compression framework.
/// App Store Connect sales reports are delivered as gzipped TSV bodies.
enum Gzip {
    static func inflate(_ data: Data) -> Data? {
        let b = [UInt8](data)
        guard b.count > 18, b[0] == 0x1f, b[1] == 0x8b, b[2] == 8 else { return nil }
        let flags = b[3]
        var off = 10
        if flags & 0x04 != 0 { // FEXTRA
            guard off + 2 <= b.count else { return nil }
            let xlen = Int(b[off]) | (Int(b[off + 1]) << 8)
            off += 2 + xlen
        }
        if flags & 0x08 != 0 { while off < b.count && b[off] != 0 { off += 1 }; off += 1 } // FNAME
        if flags & 0x10 != 0 { while off < b.count && b[off] != 0 { off += 1 }; off += 1 } // FCOMMENT
        if flags & 0x02 != 0 { off += 2 } // FHCRC
        guard off < b.count - 8 else { return nil }

        let bodyCount = b.count - 8 - off
        let n = b.count
        // gzip trailer's ISIZE (uncompressed size mod 2^32).
        let isize = Int(b[n - 4]) | (Int(b[n - 3]) << 8) | (Int(b[n - 2]) << 16) | (Int(b[n - 1]) << 24)
        let dstSize = max(isize, bodyCount * 20) + 64

        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: dstSize)
        defer { dst.deallocate() }
        let produced = data.withUnsafeBytes { raw -> Int in
            let src = raw.bindMemory(to: UInt8.self).baseAddress!.advanced(by: off)
            return compression_decode_buffer(dst, dstSize, src, bodyCount, nil, COMPRESSION_ZLIB)
        }
        guard produced > 0 else { return nil }
        return Data(bytes: dst, count: produced)
    }
}
