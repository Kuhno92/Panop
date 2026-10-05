@testable import Panop
import Testing

@Suite("Detail formatting")
struct DetailFormatTests {
    @Test(arguments: [("2004-09-22", 2004), ("2004", 2004), ("22/09/2004", 2004), ("Aired 1999.", 1999)])
    func `the year is found in whatever the panel wrote`(text: String, year: Int) {
        #expect(DetailFormat.year(from: text) == year)
    }

    @Test(arguments: ["", "n/a", "12345", "0000-00-00", "99"])
    func `no year is made up`(text: String) {
        #expect(DetailFormat.year(from: text) == nil)
    }

    @Test
    func `genres split on the separators panels use, and are capped`() {
        #expect(DetailFormat.genres("Drama, Mystery / Thriller | Crime", limit: 3) == ["Drama", "Mystery", "Thriller"])
        #expect(DetailFormat.genres(nil).isEmpty)
        #expect(DetailFormat.genres(" , ").isEmpty)
    }

    @Test
    func `quality names the resolution and the codecs, and nothing it was not told`() {
        #expect(DetailFormat.quality(height: 1080, video: "hevc", audio: "ac3") == "1080p · HEVC · AC3")
        #expect(DetailFormat.quality(height: nil, video: "h264", audio: nil) == "H.264")
        #expect(DetailFormat.quality(height: 0, video: nil, audio: nil) == nil)
        #expect(DetailFormat.quality(height: nil, video: "weirdcodec", audio: nil) == "WEIRDCODEC")
    }

    @Test
    func `a date is written out when the panel gave one, and left alone when it did not`() {
        #expect(DetailFormat.date("2004-09-22") != "2004-09-22")
        #expect(DetailFormat.date("2004-09-22")?.contains("2004") == true)
        #expect(DetailFormat.date("Spring 2004") == "Spring 2004")
        #expect(DetailFormat.date("") == nil)
        #expect(DetailFormat.date(nil) == nil)
    }

    @Test
    func `a rating has one decimal`() {
        #expect(DetailFormat.rating(8.44) == DetailFormat.rating(8.4))
    }
}
