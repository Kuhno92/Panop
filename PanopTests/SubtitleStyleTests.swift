import AVFoundation
import Foundation
@testable import Panop
import Testing

@Suite("Subtitle style")
struct SubtitleStyleTests {
    @Test
    func `a style is saved as one string and read back`() throws {
        var style = SubtitleStyle()
        style.size = .extraLarge
        style.tint = .yellow
        style.backdrop = .none
        style.raised = true

        let back = try #require(SubtitleStyle(rawValue: style.rawValue))

        #expect(back == style)
    }

    @Test
    func `nothing saved, or something unreadable, is the standard look`() {
        #expect(SubtitleStyle(rawValue: "") == nil)
        #expect(SubtitleStyle(rawValue: "not json") == nil)
        #expect(SubtitleStyle().isCustomised == false)
        #expect(SubtitleStyle.standard == SubtitleStyle())
    }

    @Test
    func `a saved style missing a field, or holding a value no longer known, still reads`() {
        let missing = SubtitleStyle(rawValue: #"{"size":"large"}"#)
        #expect(missing?.size == .large)
        #expect(missing?.tint == .white)

        let unknown = SubtitleStyle(rawValue: #"{"size":"huge","tint":"cyan"}"#)
        #expect(unknown?.size == .medium)
        #expect(unknown?.tint == .cyan)
    }

    @Test
    func `the same style is always the same saved text`() {
        let first = SubtitleStyle().rawValue
        for _ in 0 ..< 50 {
            #expect(SubtitleStyle().rawValue == first)
        }
    }

    @Test
    func `any change counts as customised`() {
        var style = SubtitleStyle()
        style.raised = true
        #expect(style.isCustomised)
    }

    @Test
    func `sizes grow in order`() {
        let scales = SubtitleStyle.Size.allCases.map(\.scale)
        #expect(scales == scales.sorted())
        #expect(SubtitleStyle.Size.medium.scale == 1)
    }

    @Test
    func `the system player is left alone until the style is changed`() {
        #expect(SubtitleStyle().textStyleRule == nil)

        var style = SubtitleStyle()
        style.size = .large
        #expect(style.textStyleRule != nil)
    }

    @Test
    func `without a backdrop the system rule asks for an edge, with one for a box`() throws {
        var plain = SubtitleStyle()
        plain.tint = .cyan
        plain.backdrop = .none
        var boxed = plain
        boxed.backdrop = .solid

        let plainRule = try #require(plain.textStyleRule)
        let boxedRule = try #require(boxed.textStyleRule)

        #expect(plainRule.textMarkupAttributes[kCMTextMarkupAttribute_CharacterEdgeStyle as String] != nil)
        #expect(plainRule.textMarkupAttributes[kCMTextMarkupAttribute_BackgroundColorARGB as String] == nil)
        #expect(boxedRule.textMarkupAttributes[kCMTextMarkupAttribute_BackgroundColorARGB as String] != nil)
    }
}
