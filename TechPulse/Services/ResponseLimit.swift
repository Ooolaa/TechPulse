import Foundation

/// The one bound on a response the app is willing to parse.
///
/// Every fetch here pulls bytes chosen by someone else — a publisher's feed, a
/// publisher's page, an arXiv search built from a Concept name — so each one
/// asks the same two questions before parsing: did it come back OK, and is it a
/// plausible size. The questions were asked three times in three shapes, and
/// the third fetcher only asked one of them (#28).
///
/// `PRIVACY.md` renders this as a promise, which is the reason it is one value
/// and not three: the sentence "responses over 5 MB are discarded rather than
/// parsed or stored" is true of the whole app only while every fetcher shares
/// the number. Note what the cap does and does not do — the response is already
/// in memory by the time it is measured, so this bounds what the app *keeps and
/// works on*, not what `URLSession` allocates.
enum ResponseLimit {
    /// 5 MB dwarfs any legitimate feed, article page or search result.
    nonisolated static let maxBytes = 5_000_000

    /// Whether a fetched response is worth parsing.
    ///
    /// A response that is not `HTTPURLResponse` has no status to judge, so size
    /// alone decides — which is what all three fetchers already did, and is
    /// what makes this substitutable for each of them.
    nonisolated static func accepts(data: Data, response: URLResponse?) -> Bool {
        let statusOK = (response as? HTTPURLResponse)
            .map { (200..<300).contains($0.statusCode) } ?? true
        return statusOK && data.count <= maxBytes
    }
}
