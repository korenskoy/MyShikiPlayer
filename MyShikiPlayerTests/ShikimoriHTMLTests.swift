//
//  ShikimoriHTMLTests.swift
//  MyShikiPlayerTests
//

import Foundation
import Testing
@testable import MyShikiPlayer

@Suite("ShikimoriHTML.parse — block segments")
struct ShikimoriHTMLBlockTests {
    @Test func emptyInputProducesNoSegments() {
        #expect(ShikimoriHTML.parse("").isEmpty)
        #expect(ShikimoriHTML.parse("   \n  ").isEmpty)
    }

    @Test func plainParagraphCollapsedToPlainSegment() {
        let segments = ShikimoriHTML.parse("Hello, <b>world</b>!")
        #expect(segments.count == 1)
        guard case .plain(let raw) = segments[0] else {
            Issue.record("Expected .plain, got \(segments[0])"); return
        }
        #expect(raw.contains("Hello"))
        #expect(raw.contains("<b>world</b>"))
    }

    @Test func headingsExtractLevel() {
        let segments = ShikimoriHTML.parse("<h1>Big</h1><h3>Small</h3>")
        #expect(segments.count == 2)
        guard case .heading(let lvl1, let t1) = segments[0],
              case .heading(let lvl3, let t3) = segments[1]
        else {
            Issue.record("Expected two headings"); return
        }
        #expect(lvl1 == 1)
        #expect(t1 == "Big")
        #expect(lvl3 == 3)
        #expect(t3 == "Small")
    }

    @Test func emptyHeadingDropped() {
        // Whitespace-only headings must not produce empty segments.
        let segments = ShikimoriHTML.parse("<h2>   </h2>")
        #expect(segments.isEmpty)
    }

    @Test func unorderedListCollectsItems() {
        let segments = ShikimoriHTML.parse("<ul><li>one</li><li>two</li></ul>")
        #expect(segments.count == 1)
        guard case .list(let items) = segments[0] else {
            Issue.record("Expected .list, got \(segments[0])"); return
        }
        #expect(items == ["one", "two"])
    }

    @Test func preTagBecomesCodeBlockWithLanguage() {
        let html = #"<pre><code class="language-swift">let x = 1</code></pre>"#
        let segments = ShikimoriHTML.parse(html)
        #expect(segments.count == 1)
        guard case .codeBlock(let lang, let text) = segments[0] else {
            Issue.record("Expected .codeBlock, got \(segments[0])"); return
        }
        #expect(lang == "swift")
        #expect(text == "let x = 1")
    }

    @Test func preTagWithoutLanguageStillBecomesCodeBlock() {
        let segments = ShikimoriHTML.parse("<pre>raw</pre>")
        #expect(segments.count == 1)
        guard case .codeBlock(let lang, let text) = segments[0] else {
            Issue.record("Expected .codeBlock"); return
        }
        #expect(lang == nil)
        #expect(text == "raw")
    }

    @Test func blockquoteBecomesMarkdownQuote() {
        let segments = ShikimoriHTML.parse("<blockquote>quoted line</blockquote>")
        #expect(segments.count == 1)
        guard case .markdownQuote(let raw) = segments[0] else {
            Issue.record("Expected .markdownQuote"); return
        }
        #expect(raw == "quoted line")
    }

    @Test func spoilerBlockExtractsLabelAndContent() {
        let html = #"""
        <div class="b-spoiler_block">
          <span tabindex="0">click me</span>
          <div>hidden text <b>bold</b></div>
        </div>
        """#
        let segments = ShikimoriHTML.parse(html)
        #expect(segments.count == 1)
        guard case .spoiler(let label, let content) = segments[0] else {
            Issue.record("Expected .spoiler, got \(segments[0])"); return
        }
        #expect(label == "click me")
        #expect(content.contains("hidden text"))
        #expect(content.contains("<b>bold</b>"))
    }

    @Test func spoilerWithoutLabelStillParses() {
        let html = #"<div class="b-spoiler_block"><div>secret</div></div>"#
        let segments = ShikimoriHTML.parse(html)
        #expect(segments.count == 1)
        guard case .spoiler(let label, let content) = segments[0] else {
            Issue.record("Expected .spoiler"); return
        }
        #expect(label == nil)
        #expect(content.contains("secret"))
    }

    @Test func bQuoteExtractsAuthorAndContent() {
        let html = #"""
        <div class="b-quote" data-attrs="123;456;Username">
          <div class="quote-content">quoted body</div>
        </div>
        """#
        let segments = ShikimoriHTML.parse(html)
        #expect(segments.count == 1)
        guard case .quote(let content, let author) = segments[0] else {
            Issue.record("Expected .quote, got \(segments[0])"); return
        }
        #expect(author == "Username")
        #expect(content.contains("quoted body"))
    }

    @Test func bImageBecomesImageSegment() {
        let html = #"""
        <a class="b-image" href="https://shikimori.org/system/uploads/full.jpg">
          <img src="https://shikimori.org/system/uploads/thumb.jpg">
        </a>
        """#
        let segments = ShikimoriHTML.parse(html)
        #expect(segments.count == 1)
        guard case .image(let url) = segments[0] else {
            Issue.record("Expected .image"); return
        }
        // `<a href>` is the full-resolution original — must win over the thumb.
        #expect(url.absoluteString == "https://shikimori.org/system/uploads/full.jpg")
    }

    @Test func plainImgBlockBecomesImageSegment() {
        let segments = ShikimoriHTML.parse(#"<img src="https://example.com/pic.png">"#)
        #expect(segments.count == 1)
        guard case .image(let url) = segments[0] else {
            Issue.record("Expected .image"); return
        }
        #expect(url.absoluteString == "https://example.com/pic.png")
    }

    @Test func mixedBlockAndInlineKeepsOrder() {
        let html = #"""
        Intro <b>line</b>
        <h2>Heading</h2>
        Outro
        """#
        let segments = ShikimoriHTML.parse(html)
        // expect: plain, heading, plain
        #expect(segments.count == 3)
        if case .plain(let p1) = segments[0] {
            #expect(p1.contains("Intro"))
        } else { Issue.record("Expected first .plain") }
        if case .heading(let lvl, let t) = segments[1] {
            #expect(lvl == 2)
            #expect(t == "Heading")
        } else { Issue.record("Expected .heading second") }
        if case .plain(let p2) = segments[2] {
            #expect(p2.contains("Outro"))
        } else { Issue.record("Expected last .plain") }
    }
}

@Suite("ShikimoriHTML.parseInlines — inline runs")
struct ShikimoriHTMLInlineTests {
    @Test func plainTextProducesSingleTextRun() {
        let runs = ShikimoriHTML.parseInlines("hello")
        #expect(runs.count == 1)
        if case .text(let s) = runs[0] {
            #expect(s == "hello")
        } else { Issue.record("Expected .text") }
    }

    @Test func boldTagYieldsStyledRun() {
        let runs = ShikimoriHTML.parseInlines("<b>x</b>")
        #expect(runs.count == 1)
        guard case .styled(let text, let style) = runs[0] else {
            Issue.record("Expected .styled"); return
        }
        #expect(text == "x")
        #expect(style.bold == true)
        #expect(style.italic == false)
    }

    @Test func brTagBecomesNewline() {
        let runs = ShikimoriHTML.parseInlines("a<br>b")
        // Expect: text "a", text "\n", text "b"
        #expect(runs.count == 3)
        if case .text(let mid) = runs[1] { #expect(mid == "\n") }
    }

    @Test func smileyImageProducesSmileyToken() {
        let html = #"<img class="smiley" alt=":ololo:" src="/smileys/ololo.gif">"#
        let runs = ShikimoriHTML.parseInlines(html)
        #expect(runs.count == 1)
        guard case .smiley(let token) = runs[0] else {
            Issue.record("Expected .smiley"); return
        }
        #expect(token == ":ololo:")
    }

    @Test func bMentionWithCommentTypeBecomesCommentReference() {
        // Decoded data-attrs: {"type":"comment","id":42,"userId":7,"text":"Nick"}
        let html = #"""
        <a class="b-mention bubbled"
           data-attrs="{&quot;type&quot;:&quot;comment&quot;,&quot;id&quot;:42,&quot;userId&quot;:7,&quot;text&quot;:&quot;Nick&quot;}">@Nick</a>
        """#
        let runs = ShikimoriHTML.parseInlines(html)
        // `<s>` prefix handling and other quirks may surround it; assert at least one
        // commentReference is present.
        let hasRef = runs.contains { run in
            if case .commentReference(let id, let author) = run {
                return id == 42 && author == 7
            }
            return false
        }
        #expect(hasRef, "Expected commentReference in \(runs)")
    }

    @Test func bLinkAnimeBecomesAnimeInline() {
        let html = #"""
        <a class="bubbled b-link"
           data-attrs="{&quot;type&quot;:&quot;anime&quot;,&quot;id&quot;:9999,&quot;name&quot;:&quot;Foo&quot;,&quot;russian&quot;:&quot;Фу&quot;}">label</a>
        """#
        let runs = ShikimoriHTML.parseInlines(html)
        #expect(runs.count == 1)
        guard case .anime(let id, let name) = runs[0] else {
            Issue.record("Expected .anime"); return
        }
        #expect(id == 9999)
        // `russian` wins when present.
        #expect(name == "Фу")
    }

    @Test func externalAnchorWithSafeHrefBecomesExternal() {
        let html = #"<a href="https://example.com/page">click</a>"#
        let runs = ShikimoriHTML.parseInlines(html)
        guard case .external(let url, let label) = runs[0] else {
            Issue.record("Expected .external"); return
        }
        #expect(url.absoluteString == "https://example.com/page")
        #expect(label == "click")
    }

    @Test func inlineCodeYieldsInlineCodeRun() {
        let runs = ShikimoriHTML.parseInlines("<code>foo()</code>")
        #expect(runs.count == 1)
        if case .inlineCode(let s) = runs[0] {
            #expect(s == "foo()")
        } else { Issue.record("Expected .inlineCode") }
    }

    @Test func unknownTagsRecurseIntoChildren() {
        let runs = ShikimoriHTML.parseInlines("<unknown>visible</unknown>")
        // `unknown` is recursed as transparent — the inner text must surface.
        let hasText = runs.contains { if case .text(let s) = $0 { return s == "visible" }; return false }
        #expect(hasText)
    }
}
