import Foundation
@testable import PanopCore
import Testing

/// Fixtures were produced by zlib, so these tests check the decoder against an
/// independent encoder rather than against itself. Each covers one DEFLATE
/// block type or framing feature.
private enum Fixture {
    static let stored = "H4sIAAAAAAAEEwERAO7/aGVsbG8sIGd6aXAgd29ybGTrg0aCEQAAAA=="
    static let fixed = "H4sIAAAAAAACE8tIzcnJ11FIr8osUCjPL8pJAQDrg0aCEQAAAA=="
    static let members = "H4sIAAAAAAACE0vLLCouUchNzU1KLbIGAJ30W1sNAAAAH4sIAAAAAAACE1MoTk3Oz0tRyE3NTUotAgC5M1GMDgAAAA=="
    static let fname = "H4sICAAAAAAC/2d1aWRlLnhtbADLS8xNTVEoSKzMyU9MAQCVo6HDDQAAAA=="
    static let badCRC = "H4sIAAAAAAACE8tIzcnJ11FIr8osUCjPL8pJAQAUg0aCEQAAAA=="
    static let dynamic = """
    H4sIAAAAAAACE5XZS44bMQxF0XlW4SXoiSJFZjkJOkjn/0Wy/CAzlwfqyzlhwNKBXbz16fnL0228vv16/3T7/vv57cfbmx9f/3y5
    vfv69/bh9+dvP2/j9uv589PPV5/+T+o0ue8n52lS95N2msz7yXWanPeTfpqs+8k4Tdr95D5+o8sx5Wl03U/W8UMv56TjNfll9HhP
    uhyVjjcVl1HjUBaWIsdUFNiKNsaixFpUmMsc3MsUBjMnFzMNi5mLi5mOxczAYubmvy2JxczCYmxgMSYsxiYWY8bF2MJizLkYCyzG
    NhdjicVYYTFrYDFLWMya/P/IsJi1sJjlWMwKLmZtLGYlF7MKi/HBxbiwGJ9YjBsW4wuLccdiPPgjzMZiPLEYLy4mBhYT4mJiYjFh
    XEwsLCYci4nAYmJjMZFYTBQWswcWs8UfeycXsw2L2YuL2Y7F7OBi9sZidmIxu7CYHFhMCovJicWkYTG5sJj0xqYUWExuLiYTi8ni
    YmpgMSUspiYWU4bF1MJiyrGYCiymNhZTycVUYTEao7Nei+/XYzYW7GF8wx6Lr9jD+Y49gi/ZY/MteyRfs0fxPfscO+w6K65H59xx
    5XPuHQ98zsXjIc94g885elz5nKvHw0kk53PuHteDOIePK59z+HjoVJPzOZePK58X0sf10M7t48rnHD8e+Jzzx5XPC/3j4diq0fca
    Jdh4C5bxGizjPVjGi7CMN2EZr8KyRheW8TIs67Th1YjDq1OHVyMPr04fbgTi1SjEq5GIV6MRr0YkXrwSyxuZWM47sbwRiuW8FMsb
    qVjOW7Gcx2L5brxf4LlYznuxggdjBS/GCp6MFY1mrODRWNGoxgqejRWNbqzg4VjBy7E2T8favB1rz8YLKl6PtXk+1ub9WLsRkLV5
    QdZuJGRt3pCVjYis5BVZyTOykndkJQ/JSl6SldF4wclbspLHZGWjJqt4TlY1erKKB2VVoyireFJW8aas4lFZxauyimdlFerK/wCs
    OgInHyIAAA==
    """
    static let multiBlock = """
    H4sIAAAAAAAAE3yVSa7CQBDF9pyij0BXNdM/DiiIMH8GwfERu7aQvLci5dmpHMfzUKZ/5bEbyv9z3BzK+nZ5ncv28i775+l6L9Py
    GE/DfXL8ktXIRU+GkbUn08hlTzYjoydnRq56cm5k9uRC3wgzLQ1tPbnSh2KnqppmQNVTxVRVTc2BqiqGoq5QSlVZnEBtoZWquriA
    6kItVX0hl1Bd7CXUF4IJ/7AwV6gvFBPqi8WECkMxocK4gQrjbVFhnECFoZhUYVgg1ReKSfWFYlJ1sZhUXygm/fviLVZfKCb9HnIv
    FYZiUoVhg6bCUEzzgwhUhfF/pMKwQFNfKKapLxTTfnR9AAAA//98lktOw0AQBfecYo7g9md6huOAjGIgDpBE4fhsU0SqfSmKXtW0
    vJe30295vx6/ziWGctmO6/npc9vXMudzuRzW8n3dXj/Ky8/ptt+xM9BmaATYbuxyjy6D/uwINoytQEdDscEyGZpAZ/2zQBdDG9Bq
    KBdQXx2o+pqAqi4WU9UXiqmqi8VU9YViqvpiMVWFoZiqwriBCkMxVYVxAhWGYqoKwwKpvlBMqi8Uk6qLxaT6QjHp7wtzpfpCMam+
    WEyqMBSTKowbqDAU0/wgAlVhKKapMCzQ1BeKaeoLxTTVxWKa+kIxzd8X51JfKKb5RcReXYWhmK7CsEFXYSim+0EEqsJQTFdhXEB9
    oZiuvlBM9w8OrqW+UEwM/sCCsBpbyPpRHAmrtEpWrQ1kVVuS9btIVsU1smru3w5qDu1EqLmJrH98cLRQc8wn/LVxtVBzzCcezP0B
    AAD//3yWTU7DQBTG9pxijtBk/jkOKIgAbYG2KsdnhYTfwvtvE9vzlFN6Of+kt9vx85KWNV3343Z5+NhPW1qW9piur1v6uu3P7+np
    +3w//Rs3brttD9wO23Zup20XbNeDbQe3i23JYV1tO7nNts3cFv02QlurjQu3Km4J1NRc5VbNhXxWVcd8sqojiazqmE9WdQSRVR3z
    yaqOHLKaYz5ZzTGfrOJCPlnNMZ/sb47UippjPkXNhXyKqmM+RdWRRFF1zKeougBC1TGfouoCBzXHfIqaYz5VxYV8qppjPtXfHKlV
    Ncd8qt9LYquqjvlUVRdIqDrmU/1ccqvqmE9TdeTQ1BzzaWqO+TQVF/Jpao75NH9zpNbUHPNpfi8DNlXHfJqqI4mu6phP93PJrapj
    Pl3VkUNXc8ynqznm0/0XJUBTc8yn+5sL1NQc8xl+L4ltqDrmM1QdSQxVx3yGn0tuVR3zGaoucFBzzGeoOeYz/BeF0KaaYz7T3xyp
    TTXHfKbfS2Kbqo75TFUXSKg65jP9XHKr6pjPVHV/HH4BAAD//wMArDoCJx8iAAA=
    """

    static func data(_ base64: String) -> Data {
        Data(base64Encoded: base64.filter { !$0.isWhitespace }) ?? Data()
    }
}

/// The plaintext behind the `dynamic` and `multiBlock` fixtures.
private let generatedText = Data(
    (0 ..< 200).map { "line \($0): the quick brown fox jumps \($0 * 7 % 13) times\n" }.joined().utf8
)

private func decode(_ base64: String, chunkSize: Int) throws -> Data {
    let input = Fixture.data(base64)
    var decoder = GzipDecoder()
    var output = Data()
    var offset = 0
    while offset < input.count {
        let end = min(offset + chunkSize, input.count)
        output += try decoder.consume(input.subdata(in: offset ..< end))
        offset = end
    }
    try decoder.finish()
    return output
}

@Suite("Gzip decoding")
struct GzipDecoderTests {
    /// One-byte chunks put a boundary inside every header, code and trailer,
    /// which is what exercises the rewind-and-wait logic.
    static let chunkSizes = [1, 2, 5, 13, 100, 1_000_000]

    @Test(arguments: chunkSizes)
    func `decodes a stored block`(chunkSize: Int) throws {
        #expect(try decode(Fixture.stored, chunkSize: chunkSize) == Data("hello, gzip world".utf8))
    }

    @Test(arguments: chunkSizes)
    func `decodes a fixed Huffman block`(chunkSize: Int) throws {
        #expect(try decode(Fixture.fixed, chunkSize: chunkSize) == Data("hello, gzip world".utf8))
    }

    @Test(arguments: chunkSizes)
    func `decodes a dynamic Huffman block with back-references`(chunkSize: Int) throws {
        #expect(try decode(Fixture.dynamic, chunkSize: chunkSize) == generatedText)
    }

    @Test(arguments: chunkSizes)
    func `decodes several blocks in one member`(chunkSize: Int) throws {
        #expect(try decode(Fixture.multiBlock, chunkSize: chunkSize) == generatedText)
    }

    @Test(arguments: chunkSizes)
    func `decodes concatenated members as one stream`(chunkSize: Int) throws {
        #expect(try decode(Fixture.members, chunkSize: chunkSize) == Data("first member; second member".utf8))
    }

    @Test(arguments: chunkSizes)
    func `skips an optional file name in the header`(chunkSize: Int) throws {
        #expect(try decode(Fixture.fname, chunkSize: chunkSize) == Data("named payload".utf8))
    }

    @Test
    func `ignores zero padding after the last member`() throws {
        var input = Fixture.data(Fixture.fixed)
        input.append(Data(repeating: 0, count: 5))
        var decoder = GzipDecoder()
        let output = try decoder.consume(input)
        try decoder.finish()
        #expect(output == Data("hello, gzip world".utf8))
    }

    @Test
    func `rejects data that is not gzip`() {
        var decoder = GzipDecoder()
        #expect(throws: GzipDecoder.Failure.notGzip) {
            _ = try decoder.consume(Data("<?xml version=\"1.0\"?><tv></tv>".utf8))
        }
    }

    /// The trailer is the only defence against a corrupted download that still
    /// inflates to plausible text.
    @Test
    func `a wrong checksum is detected`() {
        #expect(throws: GzipDecoder.Failure.checksumMismatch) {
            _ = try decode(Fixture.badCRC, chunkSize: 4)
        }
    }

    /// A guide cut off mid-download must fail, never yield a shorter guide.
    @Test(arguments: [10, 20, 40, 60])
    func `a truncated stream fails at finish`(keep: Int) throws {
        let input = Fixture.data(Fixture.dynamic).prefix(keep)
        var decoder = GzipDecoder()
        _ = try decoder.consume(Data(input))
        #expect(throws: GzipDecoder.Failure.truncated) {
            try decoder.finish()
        }
    }

    @Test
    func `an empty stream is truncated`() {
        let decoder = GzipDecoder()
        #expect(throws: GzipDecoder.Failure.truncated) {
            try decoder.finish()
        }
    }

    @Test
    func `garbage after a valid header is corrupt not a crash`() {
        var input = Fixture.data(Fixture.dynamic)
        for index in 20 ..< 60 {
            input[index] = 0xFF
        }
        var decoder = GzipDecoder()
        #expect(throws: GzipDecoder.Failure.self) {
            _ = try decoder.consume(input)
            try decoder.finish()
        }
    }

    /// Feeds thousands of mutated streams. The property is only that the
    /// decoder returns or throws; a trap would take the whole app down on a
    /// hostile or damaged guide.
    @Test
    func `arbitrary corruption never traps`() {
        let original = Fixture.data(Fixture.dynamic)
        var seed: UInt64 = 0x1234_5678
        func next() -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(seed >> 33)
        }
        for _ in 0 ..< 300 {
            var input = original
            for _ in 0 ..< 1 + next() % 4 {
                input[10 + next() % (input.count - 10)] = UInt8(truncatingIfNeeded: next())
            }
            var decoder = GzipDecoder()
            _ = try? decoder.consume(input)
            try? decoder.finish()
        }
    }
}
