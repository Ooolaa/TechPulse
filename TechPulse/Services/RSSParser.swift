import Foundation

struct ParsedFeedItem {
    var guid = ""
    var title = ""
    var link = ""
    var content = ""
    var publishedAt: Date?
}

/// What one document turned out to be.
///
/// The two halves are separate because "no entries" and "not a feed" are
/// different answers, and a caller deciding whether a URL is worth subscribing
/// to needs them apart (#58): a brand-new feed that has published nothing is
/// still a feed, and an HTML page that happens to parse as XML is not one
/// however many `<item>`-shaped things it contains.
struct ParsedFeed {
    let items: [ParsedFeedItem]

    /// Whether the document's **root** element announced itself as a feed —
    /// `<rss>`, `<feed>` or RDF. The root rather than any element anywhere,
    /// because a page is free to contain the word and a feed is not free to
    /// bury its own root.
    let isFeedDocument: Bool
}

/// Tolerant feed parser: handles RSS 2.0 (`<item>`), Atom (`<entry>`)
/// and RSS 1.0/RDF, which covers all seeded sources.
final class RSSParser: NSObject, XMLParserDelegate {
    private var items: [ParsedFeedItem] = []
    private var current: ParsedFeedItem?
    private var buffer = ""

    /// The root element's name, or nil while nothing has been opened yet.
    private var root: String?

    /// The three roots a feed can have. RDF arrives as `RDF`; the comparison is
    /// lowercased, as every other element name here is.
    private static let feedRoots: Set<String> = ["rss", "feed", "rdf"]

    /// Everything one document is, in one parse.
    static func read(_ data: Data) -> ParsedFeed {
        let delegate = RSSParser()
        let parser = XMLParser(data: data)
        // Security: never resolve external entities (XXE / billion-laughs).
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        parser.parse()
        return ParsedFeed(items: delegate.items,
                          isFeedDocument: delegate.root.map(feedRoots.contains) ?? false)
    }

    /// The items alone, for the callers that only ever wanted those. A wrapper
    /// over `read`, so there is one parse and one reading of what a feed is.
    static func parse(_ data: Data) -> [ParsedFeedItem] {
        read(data).items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let name = elementName.lowercased()
        if root == nil { root = name }
        if name == "item" || name == "entry" {
            current = ParsedFeedItem()
        } else if current != nil {
            buffer = ""
            // Atom links carry the URL in an href attribute.
            if name == "link", let href = attributeDict["href"], current?.link.isEmpty == true {
                current?.link = href
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        buffer += String(data: CDATABlock, encoding: .utf8) ?? ""
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.lowercased()
        guard var item = current else { return }
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "item", "entry":
            if item.guid.isEmpty { item.guid = item.link.isEmpty ? item.title : item.link }
            if !item.title.isEmpty { items.append(item) }
            current = nil
            return
        case "title":
            item.title = text
        case "guid", "id":
            item.guid = text
        case "link":
            if item.link.isEmpty { item.link = text }
        case "description", "summary":
            if item.content.isEmpty { item.content = text }
        case "content:encoded", "content":
            if text.count > item.content.count { item.content = text }
        case "pubdate", "published", "updated", "dc:date":
            if item.publishedAt == nil { item.publishedAt = Self.parseDate(text) }
        default:
            break
        }
        current = item
        buffer = ""
    }

    // MARK: Date parsing — RFC 822 (RSS) and ISO 8601 (Atom)

    private static let rfc822: [DateFormatter] = {
        ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz",
         "dd MMM yyyy HH:mm:ss Z"].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            return formatter
        }
    }()

    static func parseDate(_ string: String) -> Date? {
        for formatter in rfc822 {
            if let date = formatter.date(from: string) { return date }
        }
        return (try? Date(string, strategy: .iso8601))
            ?? (try? Date(string, strategy: .iso8601.time(includingFractionalSeconds: true)))
    }
}

extension String {
    /// RSS descriptions arrive as HTML; strip tags and common entities for display.
    var strippingHTML: String {
        replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
