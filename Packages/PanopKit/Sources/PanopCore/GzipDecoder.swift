import Foundation

/// Incremental gzip decompression (RFC 1952 framing over RFC 1951 DEFLATE).
///
/// Foundation has no portable gzip, and XMLTV guides are routinely served as
/// `epg.xml.gz`, so the portable core carries its own. Feed it network chunks of
/// any size, including one byte at a time; output appears as soon as it is
/// decodable and memory stays bounded by the 32 KiB window plus one chunk's
/// output.
///
/// Concatenated members are decoded as one stream, as `gzip -d` does. The CRC
/// and length trailer of every member is verified, which is also what catches a
/// download cut short in the middle of the trailer.
///
/// Call ``finish()`` after the last chunk. A stream that ends before its final
/// trailer throws ``Failure/truncated``: a partial guide must never be mistaken
/// for a complete one.
public struct GzipDecoder {
    public enum Failure: Error, Equatable {
        /// The data does not begin with a gzip header.
        case notGzip
        /// Structurally invalid DEFLATE data.
        case corrupt
        /// The trailer's CRC-32 or length disagrees with the decoded bytes.
        case checksumMismatch
        /// The input ended before the stream did.
        case truncated
    }

    private enum State {
        case memberHeader
        case blockHeader
        case stored(remaining: Int)
        case codes
        case trailer
        /// Trailing bytes after the last member that are not another member.
        case ignoringTrailer
    }

    private static let windowSize = 32 * 1024

    private var state = State.memberHeader
    private var input: [UInt8] = []
    /// Absolute bit index into `input`.
    private var bitPos = 0
    private var isFinalBlock = false
    private var literals = Huffman.fixedLiterals
    private var distances = Huffman.fixedDistances

    /// Last `windowSize` bytes produced, kept so a back-reference can reach
    /// across chunk boundaries.
    private var history: [UInt8] = []
    /// Output of the current `consume` call, preceded by `history`.
    private var output: [UInt8] = []
    private var checksumMark = 0

    private var crc: UInt32 = 0xFFFF_FFFF
    private var memberSize: UInt32 = 0
    private var completedMembers = 0

    public init() {}

    /// Decodes as much of `chunk` as possible and returns the bytes produced.
    public mutating func consume(_ chunk: Data) throws -> Data {
        if bitPos >= 8 {
            let consumed = bitPos >> 3
            input.removeFirst(consumed)
            bitPos -= consumed << 3
        }
        input.append(contentsOf: chunk)

        output = history
        let prefix = output.count
        checksumMark = prefix
        output.reserveCapacity(prefix + chunk.count * 4)

        // Always leave the decoder in a consistent state, even when throwing.
        defer {
            history = Array(output.suffix(Self.windowSize))
            output = []
        }
        while try step() {}
        foldChecksum()
        return Data(output[prefix...])
    }

    /// Verifies the stream ended cleanly. Call once, after the last chunk.
    public func finish() throws {
        switch state {
        case .ignoringTrailer:
            return
        case .memberHeader where completedMembers > 0:
            // Some tools pad the end of a file with zero bytes.
            if input[(bitPos >> 3)...].allSatisfy({ $0 == 0 }) {
                return
            }
            throw Failure.truncated
        default:
            throw Failure.truncated
        }
    }

    // MARK: - State machine

    /// Advances one step. Returns true when it made progress and should be
    /// called again, false when it needs more input.
    private mutating func step() throws -> Bool {
        switch state {
        case .memberHeader: try readMemberHeader()
        case .blockHeader: try readBlockHeader()
        case let .stored(remaining): copyStored(remaining)
        case .codes: try decodeSymbols()
        case .trailer: try readTrailer()
        case .ignoringTrailer: false
        }
    }

    private mutating func readMemberHeader() throws -> Bool {
        var pos = bitPos >> 3
        let available = input.count

        guard available - pos >= 10 else { return false }
        guard input[pos] == 0x1F, input[pos + 1] == 0x8B, input[pos + 2] == 8 else {
            if completedMembers > 0 {
                state = .ignoringTrailer
                return true
            }
            throw Failure.notGzip
        }
        let flags = input[pos + 3]
        pos += 10

        if flags & 0x04 != 0 {
            guard available - pos >= 2 else { return false }
            pos += 2 + (Int(input[pos]) | Int(input[pos + 1]) << 8)
            guard pos <= available else { return false }
        }
        for flag in [UInt8(0x08), UInt8(0x10)] where flags & flag != 0 {
            // NUL-terminated file name / comment.
            guard let end = input[pos...].firstIndex(of: 0) else { return false }
            pos = end + 1
        }
        if flags & 0x02 != 0 {
            pos += 2
            guard pos <= available else { return false }
        }

        bitPos = pos << 3
        crc = 0xFFFF_FFFF
        memberSize = 0
        state = .blockHeader
        return true
    }

    private mutating func readBlockHeader() throws -> Bool {
        let start = bitPos
        guard let header = readBits(3) else { return false }
        isFinalBlock = header & 1 == 1

        switch header >> 1 {
        case 0:
            bitPos = (bitPos + 7) & ~7
            guard input.count - (bitPos >> 3) >= 4 else {
                bitPos = start
                return false
            }
            let at = bitPos >> 3
            let length = Int(input[at]) | Int(input[at + 1]) << 8
            let inverse = Int(input[at + 2]) | Int(input[at + 3]) << 8
            guard length == (~inverse & 0xFFFF) else { throw Failure.corrupt }
            bitPos += 32
            state = .stored(remaining: length)
        case 1:
            literals = Huffman.fixedLiterals
            distances = Huffman.fixedDistances
            state = .codes
        case 2:
            guard try readDynamicTables() else {
                bitPos = start
                return false
            }
            state = .codes
        default:
            throw Failure.corrupt
        }
        return true
    }

    private mutating func copyStored(_ remaining: Int) -> Bool {
        let at = bitPos >> 3
        let take = min(remaining, input.count - at)
        if take > 0 {
            output.append(contentsOf: input[at ..< at + take])
            bitPos += take << 3
        }
        if take == remaining {
            state = isFinalBlock ? .trailer : .blockHeader
            return true
        }
        state = .stored(remaining: remaining - take)
        return false
    }

    private mutating func decodeSymbols() throws -> Bool {
        while true {
            let start = bitPos
            let symbol = try decode(literals)
            if symbol < 0 {
                return false
            }

            if symbol < 256 {
                output.append(UInt8(truncatingIfNeeded: symbol))
                continue
            }
            if symbol == 256 {
                state = isFinalBlock ? .trailer : .blockHeader
                return true
            }
            guard symbol <= 285 else { throw Failure.corrupt }

            let lengthIndex = symbol - 257
            guard let lengthExtra = readBits(Self.lengthExtraBits[lengthIndex]) else {
                bitPos = start
                return false
            }
            let length = Self.lengthBase[lengthIndex] + Int(lengthExtra)

            let distanceSymbol = try decode(distances)
            guard distanceSymbol >= 0 else {
                bitPos = start
                return false
            }
            guard distanceSymbol < 30 else { throw Failure.corrupt }
            guard let distanceExtra = readBits(Self.distanceExtraBits[distanceSymbol]) else {
                bitPos = start
                return false
            }
            let distance = Self.distanceBase[distanceSymbol] + Int(distanceExtra)
            guard distance <= output.count else { throw Failure.corrupt }

            // Byte by byte on purpose: source and destination overlap when
            // distance < length, and that overlap is how runs are encoded.
            var from = output.count - distance
            for _ in 0 ..< length {
                output.append(output[from])
                from += 1
            }
        }
    }

    private mutating func readTrailer() throws -> Bool {
        var at = (bitPos + 7) >> 3
        guard input.count - at >= 8 else { return false }
        foldChecksum()

        let expectedCRC = UInt32(input[at]) | UInt32(input[at + 1]) << 8
            | UInt32(input[at + 2]) << 16 | UInt32(input[at + 3]) << 24
        let expectedSize = UInt32(input[at + 4]) | UInt32(input[at + 5]) << 8
            | UInt32(input[at + 6]) << 16 | UInt32(input[at + 7]) << 24
        guard ~crc == expectedCRC, memberSize == expectedSize else {
            throw Failure.checksumMismatch
        }
        at += 8
        bitPos = at << 3
        completedMembers += 1
        state = .memberHeader
        return true
    }

    /// Folds bytes produced since the last call into the running CRC and size.
    private mutating func foldChecksum() {
        guard output.count > checksumMark else { return }
        var value = crc
        output.withUnsafeBufferPointer { buffer in
            for index in checksumMark ..< buffer.count {
                value = Self.crcTable[Int((value ^ UInt32(buffer[index])) & 0xFF)] ^ (value >> 8)
            }
        }
        crc = value
        memberSize &+= UInt32(truncatingIfNeeded: output.count - checksumMark)
        checksumMark = output.count
    }

    // MARK: - Bits

    /// Reads `count` (at most 16) bits, LSB first. Returns nil, without
    /// advancing, when the input does not hold that many.
    private mutating func readBits(_ count: Int) -> UInt32? {
        if count == 0 {
            return 0
        }
        guard input.count * 8 - bitPos >= count else { return nil }
        let value = peek(count)
        bitPos += count
        return value
    }

    /// Up to 16 bits at the cursor, zero-padded past the end of input.
    private func peek(_ count: Int) -> UInt32 {
        let byte = bitPos >> 3
        var window: UInt32 = 0
        for offset in 0 ..< 3 where byte + offset < input.count {
            window |= UInt32(input[byte + offset]) << UInt32(8 * offset)
        }
        return (window >> UInt32(bitPos & 7)) & ((1 << UInt32(count)) - 1)
    }

    /// Decodes one symbol. Returns -1, without advancing, when the input ends
    /// inside the code.
    private mutating func decode(_ table: Huffman) throws -> Int {
        let available = input.count * 8 - bitPos
        guard available > 0 else { return -1 }

        let entry = table.fast[Int(peek(Huffman.fastBits))]
        if entry != 0 {
            let length = Int(entry & 15)
            guard length <= available else { return -1 }
            bitPos += length
            return Int(entry >> 4)
        }

        // Codes longer than the fast table, walked bit by bit canonically.
        var code = 0
        var first = 0
        var index = 0
        for length in 1 ... 15 {
            guard length <= available else { return -1 }
            let position = bitPos + length - 1
            code |= Int(input[position >> 3] >> UInt8(position & 7)) & 1
            let count = Int(table.counts[length])
            if code - count < first {
                bitPos += length
                return Int(table.symbols[index + (code - first)])
            }
            index += count
            first += count
            first <<= 1
            code <<= 1
        }
        throw Failure.corrupt
    }

    /// Reads a dynamic block's code definitions. Returns false, leaving the
    /// cursor wherever it got to, when the input runs out; the caller rewinds.
    private mutating func readDynamicTables() throws -> Bool {
        guard
            let literalCount = readBits(5), let distanceCount = readBits(5), let lengthCodeCount = readBits(4)
        else { return false }
        let literalTotal = Int(literalCount) + 257
        let distanceTotal = Int(distanceCount) + 1
        let lengthCodeTotal = Int(lengthCodeCount) + 4
        guard literalTotal <= 286, distanceTotal <= 30 else { throw Failure.corrupt }

        var lengthCodeLengths = [UInt8](repeating: 0, count: 19)
        for index in 0 ..< lengthCodeTotal {
            guard let value = readBits(3) else { return false }
            lengthCodeLengths[Self.lengthCodeOrder[index]] = UInt8(value)
        }
        let lengthCodes = try Huffman(lengths: lengthCodeLengths)

        guard let lengths = try readCodeLengths(using: lengthCodes, count: literalTotal + distanceTotal) else {
            return false
        }
        guard lengths[256] != 0 else { throw Failure.corrupt }

        literals = try Huffman(lengths: Array(lengths[0 ..< literalTotal]))
        distances = try Huffman(lengths: Array(lengths[literalTotal...]))
        return true
    }

    /// Reads the run-length coded list of code lengths for a dynamic block.
    /// Returns nil when the input runs out.
    private mutating func readCodeLengths(using codes: Huffman, count: Int) throws -> [UInt8]? {
        var lengths = [UInt8](repeating: 0, count: count)
        var index = 0
        while index < count {
            let symbol = try decode(codes)
            guard symbol >= 0 else { return nil }

            if symbol < 16 {
                lengths[index] = UInt8(symbol)
                index += 1
                continue
            }
            // 16 repeats the previous length; 17 and 18 repeat zero.
            let (extraBits, base) = symbol == 16 ? (2, 3) : symbol == 17 ? (3, 3) : (7, 11)
            if symbol == 16, index == 0 {
                throw Failure.corrupt
            }
            guard let extra = readBits(extraBits) else { return nil }
            let repeatCount = base + Int(extra)
            guard index + repeatCount <= count else { throw Failure.corrupt }

            let value: UInt8 = symbol == 16 ? lengths[index - 1] : 0
            for offset in 0 ..< repeatCount {
                lengths[index + offset] = value
            }
            index += repeatCount
        }
        return lengths
    }

    // MARK: - Tables

    private static let lengthBase = [
        3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
        35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258
    ]
    private static let lengthExtraBits = [
        0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
        3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0
    ]
    private static let distanceBase = [
        1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
        257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577
    ]
    private static let distanceExtraBits = [
        0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
        7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13
    ]
    private static let lengthCodeOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

    private static let crcTable: [UInt32] = (0 ..< 256).map { index in
        var value = UInt32(index)
        for _ in 0 ..< 8 {
            value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
        }
        return value
    }
}

/// A canonical Huffman code, decoded through a small lookup table for the
/// common short codes and a bit-by-bit walk for the rare long ones.
private struct Huffman {
    /// Codes up to this many bits resolve in one table lookup.
    static let fastBits = 9

    /// Number of codes of each length.
    var counts = [UInt16](repeating: 0, count: 16)
    /// Symbols ordered by code length, then by value.
    var symbols: [UInt16]
    /// Indexed by the next `fastBits` bits of input: `symbol << 4 | length`,
    /// or 0 when the code is longer than `fastBits`.
    var fast = [UInt16](repeating: 0, count: 1 << fastBits)

    init(lengths: [UInt8]) throws {
        symbols = [UInt16](repeating: 0, count: lengths.count)
        for length in lengths {
            counts[Int(length)] += 1
        }
        counts[0] = 0

        // Reject codes that use more of the code space than exists.
        var remaining = 1
        for length in 1 ... 15 {
            remaining = (remaining << 1) - Int(counts[length])
            if remaining < 0 {
                throw GzipDecoder.Failure.corrupt
            }
        }

        var offsets = [Int](repeating: 0, count: 16)
        for length in 1 ..< 15 {
            offsets[length + 1] = offsets[length] + Int(counts[length])
        }
        var nextCode = [Int](repeating: 0, count: 16)
        var code = 0
        for length in 1 ... 15 {
            code = (code + Int(counts[length - 1])) << 1
            nextCode[length] = code
        }

        for (symbol, length) in lengths.enumerated() where length != 0 {
            let length = Int(length)
            symbols[offsets[length]] = UInt16(symbol)
            offsets[length] += 1

            let assigned = nextCode[length]
            nextCode[length] += 1
            guard length <= Self.fastBits else { continue }

            // Deflate packs codes MSB first into an LSB-first bit stream, so
            // the table is indexed by the reversed code.
            var reversed = 0
            for bit in 0 ..< length where assigned >> bit & 1 == 1 {
                reversed |= 1 << (length - 1 - bit)
            }
            let entry = UInt16(symbol << 4 | length)
            var slot = reversed
            while slot < fast.count {
                fast[slot] = entry
                slot += 1 << length
            }
        }
    }

    static let fixedLiterals: Huffman = {
        var lengths = [UInt8](repeating: 8, count: 288)
        for index in 144 ..< 256 {
            lengths[index] = 9
        }
        for index in 256 ..< 280 {
            lengths[index] = 7
        }
        // The lengths are constants, so this cannot throw.
        return (try? Huffman(lengths: lengths)) ?? Huffman()
    }()

    static let fixedDistances: Huffman = (try? Huffman(lengths: [UInt8](repeating: 5, count: 30))) ?? Huffman()

    /// An empty code that decodes nothing. Only reachable if the constant
    /// tables above were ever wrong.
    private init() {
        symbols = []
    }
}
