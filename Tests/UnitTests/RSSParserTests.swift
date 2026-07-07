import Testing
import Foundation
@testable import TechPulse

@Suite("RSS parser")
struct RSSParserTests {

    @Test("parses RSS 2.0 items")
    func rss2() {
        let xml = """
        <?xml version="1.0"?>
        <rss version="2.0"><channel>
          <item>
            <title>Hello &amp; welcome</title>
            <link>https://example.com/a</link>
            <guid>guid-1</guid>
            <description><![CDATA[<p>Body <b>text</b> here.</p>]]></description>
            <pubDate>Mon, 06 Jul 2026 08:30:00 GMT</pubDate>
          </item>
        </channel></rss>
        """
        let items = RSSParser.parse(Data(xml.utf8))
        #expect(items.count == 1)
        #expect(items[0].guid == "guid-1")
        #expect(items[0].title == "Hello & welcome")
        #expect(items[0].content.contains("Body"))
        #expect(items[0].publishedAt != nil)
    }

    @Test("parses Atom entries with href links")
    func atom() {
        let xml = """
        <?xml version="1.0"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <title>Atom post</title>
            <id>tag:example.com,2026:1</id>
            <link href="https://example.com/atom-1"/>
            <summary>Short summary</summary>
            <updated>2026-07-06T08:30:00Z</updated>
          </entry>
        </feed>
        """
        let items = RSSParser.parse(Data(xml.utf8))
        #expect(items.count == 1)
        #expect(items[0].guid == "tag:example.com,2026:1")
        #expect(items[0].link == "https://example.com/atom-1")
        #expect(items[0].publishedAt != nil)
    }

    @Test("item without guid falls back to link, skips titleless items")
    func fallbacks() {
        let xml = """
        <rss><channel>
          <item><title>No guid</title><link>https://example.com/x</link></item>
          <item><link>https://example.com/no-title</link></item>
        </channel></rss>
        """
        let items = RSSParser.parse(Data(xml.utf8))
        #expect(items.count == 1)
        #expect(items[0].guid == "https://example.com/x")
    }

    @Test("date formats: RFC822 with zone name and ISO8601")
    func dates() {
        #expect(RSSParser.parseDate("Mon, 06 Jul 2026 08:30:00 +0800") != nil)
        #expect(RSSParser.parseDate("Mon, 06 Jul 2026 08:30:00 GMT") != nil)
        #expect(RSSParser.parseDate("2026-07-06T08:30:00Z") != nil)
        #expect(RSSParser.parseDate("not a date") == nil)
    }

    @Test("HTML stripping removes tags and entities")
    func stripping() {
        #expect("<p>A &amp; B</p>".strippingHTML == "A & B")
        #expect("Plain".strippingHTML == "Plain")
    }
}
