import Foundation
import SwiftData

/// Skill-tree logic over the knowledge pack: what's lit, what's ready to
/// learn next, where the gaps are, and which articles fill them.
@MainActor
enum KnowledgePathEngine {

    /// "Lit" = the user has engaged with it (learning or known), per design 4a.
    static func isLit(_ concept: Concept) -> Bool {
        concept.masteryState != .new
    }

    struct ClusterStats {
        let name: String
        let total: Int
        let lit: Int
        var ratio: Double { total == 0 ? 0 : Double(lit) / Double(total) }
    }

    /// Pack clusters in reading order, then any extra categories (resume, articles).
    static func clusterStats(concepts: [Concept]) -> [ClusterStats] {
        let grouped = Dictionary(grouping: concepts, by: \.category)
        let packNames = KnowledgePack.clusterOrder
        let extraNames = grouped.keys.filter { !packNames.contains($0) }.sorted()
        return (packNames + extraNames).compactMap { name in
            guard let members = grouped[name], !members.isEmpty else { return nil }
            return ClusterStats(name: name, total: members.count,
                                lit: members.filter(isLit).count)
        }
    }

    /// The cluster holding you back: lowest completion among pack clusters.
    static func gapCluster(concepts: [Concept]) -> String? {
        clusterStats(concepts: concepts)
            .filter { KnowledgePack.clusterOrder.contains($0.name) && $0.ratio < 1 }
            .min { $0.ratio < $1.ratio }?.name
    }

    /// Frontier = dim concepts whose prerequisites are all lit (design 4b's
    /// dashed "ready to learn" ring). Restricted to knowledge-pack concepts:
    /// stray article-extracted concepts have no dependency structure and would
    /// otherwise all count as "ready", flooding recommendations with noise.
    static func frontier(concepts: [Concept], dependencies: [ConceptDependency]) -> Set<String> {
        let packNames = Set(KnowledgePack.concepts.map(\.name))
        let litNames = Set(concepts.filter(isLit).map(\.name))
        let prereqsByDependent = Dictionary(grouping: dependencies, by: \.dependent)
        var result = Set<String>()
        for concept in concepts where !isLit(concept) && packNames.contains(concept.name) {
            let prereqs = prereqsByDependent[concept.name]?.map(\.prerequisite) ?? []
            if prereqs.allSatisfy(litNames.contains) {
                result.insert(concept.name)
            }
        }
        return result
    }

    struct Recommendation {
        let concept: Concept
        let litPrerequisites: [String]
        let articles: [Article]
        let followUpGap: String?
    }

    /// "YOUR NEXT DOT" (design 4c): the first frontier concept in learning-path
    /// order, with its lit prerequisites and the cached articles that mention it.
    static func nextDot(concepts: [Concept], dependencies: [ConceptDependency],
                        articles: [Article]) -> Recommendation? {
        let frontierNames = frontier(concepts: concepts, dependencies: dependencies)
        guard !frontierNames.isEmpty else { return nil }

        let pathOrder = KnowledgePack.stages.flatMap(\.conceptNames) + KnowledgePack.sideQuestConcepts
        let orderedName = pathOrder.first(where: frontierNames.contains)
            ?? frontierNames.sorted().first!
        guard let concept = concepts.first(where: { $0.name == orderedName }) else { return nil }

        let litNames = Set(concepts.filter(isLit).map(\.name))
        let prereqs = dependencies.filter { $0.dependent == concept.name }
            .map(\.prerequisite).filter(litNames.contains)
        let matching = articles.filter { article in
            article.concepts.contains { $0.name == concept.name }
                || article.title.localizedCaseInsensitiveContains(concept.name)
        }
        return Recommendation(concept: concept, litPrerequisites: prereqs,
                              articles: matching.sorted { $0.publishedAt > $1.publishedAt },
                              followUpGap: gapCluster(concepts: concepts))
    }

    /// "Fills your gap: X" tag for an article (design 4c): the first frontier
    /// or gap-cluster concept this article touches.
    static func gapTag(for article: Article, frontierNames: Set<String>,
                       gapClusterName: String?) -> String? {
        if let hit = article.concepts.first(where: { frontierNames.contains($0.name) }) {
            return "Fills your gap: \(hit.name)"
        }
        if let gapClusterName,
           let hit = article.concepts.first(where: { $0.category == gapClusterName && $0.masteryState == .new }) {
            return "Fills your gap: \(gapClusterName) → \(hit.name)"
        }
        return nil
    }

    struct StageProgress {
        let title: String
        let subtitle: String
        let total: Int
        let lit: Int
        var isComplete: Bool { lit == total && total > 0 }
    }

    /// Learning path (design 4d): per-stage completion; "you are here" is the
    /// first incomplete stage.
    static func stageProgress(concepts: [Concept]) -> [StageProgress] {
        let byName = Dictionary(concepts.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        return KnowledgePack.stages.map { stage in
            let members = stage.conceptNames.compactMap { byName[$0] }
            return StageProgress(title: stage.title, subtitle: stage.subtitle,
                                 total: stage.conceptNames.count,
                                 lit: members.filter(isLit).count)
        }
    }

    static func sideQuestProgress(concepts: [Concept]) -> (lit: Int, total: Int) {
        let byName = Dictionary(concepts.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        let members = KnowledgePack.sideQuestConcepts.compactMap { byName[$0] }
        return (members.filter(isLit).count, KnowledgePack.sideQuestConcepts.count)
    }
}
