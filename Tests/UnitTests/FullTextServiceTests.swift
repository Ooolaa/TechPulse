import Testing
import Foundation
@testable import TechPulse

@Suite("Full-text extraction")
struct FullTextServiceTests {

    private func paragraph(_ index: Int) -> String {
        "<p>Paragraph \(index): " + String(repeating: "meaningful readable sentence content ", count: 3) + "</p>"
    }

    @Test("prefers the <article> region and drops script/style/nav crumbs")
    func articleRegion() throws {
        let html = """
        <html><head><style>body { color: red }</style>
        <script>var tracking = "junk that must not appear";</script></head>
        <body>
        <nav><p>Home News About Subscribe Cookie settings</p></nav>
        <article>
        \((1...6).map(paragraph).joined())
        <p>Share</p>
        </article>
        <footer><p>All rights reserved worldwide by the publisher corporation.</p></footer>
        </body></html>
        """
        let text = try #require(FullTextService.extractReadableText(html: html))
        #expect(text.contains("Paragraph 1"))
        #expect(text.contains("Paragraph 6"))
        #expect(!text.contains("tracking"))
        #expect(!text.contains("Share"))                 // < 60-char crumb dropped
        #expect(!text.contains("rights reserved"))       // outside <article>
    }

    @Test("falls back to whole-page paragraphs without <article>")
    func wholePage() throws {
        let html = "<html><body><div>" + (1...6).map(paragraph).joined() + "</div></body></html>"
        let text = try #require(FullTextService.extractReadableText(html: html))
        #expect(text.contains("Paragraph 3"))
    }

    @Test("too little text → nil (paywall / JS-rendered page)")
    func tooShort() {
        let html = "<html><body><article><p>Please enable JavaScript to continue reading this content here.</p></article></body></html>"
        #expect(FullTextService.extractReadableText(html: html) == nil)
    }

    @Test("entities decoded via strippingHTML")
    func entities() throws {
        let body = "<p>" + String(repeating: "Research &amp; development matters greatly in modern systems engineering. ", count: 8) + "</p>"
        let html = "<article>\(body)</article>"
        let text = try #require(FullTextService.extractReadableText(html: html))
        #expect(text.contains("Research & development"))
    }
}
