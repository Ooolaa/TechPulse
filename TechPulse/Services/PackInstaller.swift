import Foundation
import SwiftData

// MARK: - Reading a stored record

private extension [String] {
    /// The same names, with any later repeat of one dropped.
    ///
    /// A stored `InstalledPack` is not trusted to name each Concept once. A Pack
    /// installed before `PackValidator` compared names without case could
    /// declare both "RAG" and "rag", which resolve onto a single stored row, and
    /// the record then names that row twice. Such records exist on readers'
    /// devices and are read at every launch, so every path off one has to
    /// tolerate the repeat rather than trust a guarantee it never got.
    var namedOnce: [String] {
        var seen: Set<String> = []
        return filter { seen.insert($0).inserted }
    }
}

// MARK: - The active-Pack seam

/// What the rest of the app reads instead of a compiled-in pack: the Pack
/// currently installed, and the reading order derived from it.
///
/// One load point (`load(context:)`) so later work can run against any Pack
/// rather than only the built-in one.
@MainActor
struct ActivePack {
    let field: String
    let specialtyCluster: String?
    let clusterOrder: [String]
    let stages: [PackFile.PackStage]
    /// Sources the Pack's author suggests, for the app to offer. Subscribing is
    /// the reader's to do — a Source is chosen, not installed.
    let suggestedSources: [PackFile.PackSource]
    /// Names of this Pack's Concepts, in authored order, as they exist in the
    /// store — so every one of them resolves to a Concept that is really there.
    let conceptNames: [String]
    /// The specialty Cluster's Concepts, in authored order — the "side quest"
    /// lane, reported separately from the staged path.
    let sideQuestConcepts: [String]
    /// Where this Pack came from. The reader is told, and launch uses it to
    /// leave a Pack they chose themselves alone.
    let origin: PackOrigin

    init(field: String, specialtyCluster: String?, clusterOrder: [String],
         stages: [PackFile.PackStage], suggestedSources: [PackFile.PackSource],
         conceptNames: [String], sideQuestConcepts: [String],
         origin: PackOrigin) {
        self.field = field
        self.specialtyCluster = specialtyCluster
        self.clusterOrder = clusterOrder
        self.stages = stages
        self.suggestedSources = suggestedSources
        self.conceptNames = conceptNames
        self.sideQuestConcepts = sideQuestConcepts
        self.origin = origin
    }

    /// Reads a stored record, which is not trusted to name each Concept once —
    /// see `[String].namedOnce`. Normalising here rather than at each reader
    /// keeps one dot from being counted as two everywhere downstream: the
    /// reading order, the library's Concept count, the side-quest total.
    init(record: InstalledPack) {
        self.init(field: record.field,
                  specialtyCluster: record.specialtyCluster,
                  clusterOrder: record.clusterOrder,
                  stages: record.stages,
                  suggestedSources: record.suggestedSources,
                  conceptNames: record.conceptNames.namedOnce,
                  sideQuestConcepts: record.sideQuestConcepts.namedOnce,
                  origin: record.packOrigin)
    }

    private static var cached: ActivePack?

    /// The Pack the engines run against when a caller does not name one.
    ///
    /// Cached rather than fetched per call: the engines are called from view
    /// bodies, and a SwiftData fetch per recomputation would be paid on every
    /// redraw. `refresh(context:)` is the only writer, called at launch and
    /// after anything installs a Pack.
    ///
    /// Falls back to the compiled pack, which should be unreachable — launch
    /// installs the built-in Pack before anything reads this. It is a net
    /// under a first launch that failed to install, not a code path in use.
    static var inUse: ActivePack { cached ?? .compiled }

    /// Re-reads the active Pack. `PackInstaller.install` calls this, so
    /// installing anything is enough to keep the engines current.
    static func refresh(context: ModelContext) {
        cached = load(context: context)
    }

    /// Drops the cache. For tests, which share one process across stores.
    static func resetCache() {
        cached = nil
    }

    static func load(context: ModelContext) -> ActivePack? {
        let descriptor = FetchDescriptor<InstalledPack>(predicate: #Predicate { $0.isActive })
        return (try? context.fetch(descriptor))?.first.map(ActivePack.init)
    }

    /// The order Concepts should be met in — what reduces a Frontier holding
    /// several ready Concepts to the single Next Dot.
    ///
    /// ADR-0004: authored Stages first, then whatever they leave out in
    /// Dependency order. Alphabetical is not a fallback; a Pack with no Stages
    /// still gets an order that means something.
    func pathOrder(dependencies: [ConceptDependency]) -> [String] {
        let members = Set(conceptNames)
        var order: [String] = []
        var placed: Set<String> = []

        for name in stages.flatMap(\.concepts) where members.contains(name) {
            if placed.insert(name).inserted { order.append(name) }
        }
        for name in topologicalOrder(dependencies: dependencies) where !placed.contains(name) {
            placed.insert(name)
            order.append(name)
        }
        return order
    }

    /// Kahn's algorithm over the Pack's Concepts: a Concept never appears
    /// before one it depends on. Ties break by the Pack's authored order, so
    /// the result is stable rather than arbitrary.
    ///
    /// Both indexes keep the first mention of a name and let any repeat
    /// collapse, rather than trapping on it. `init(record:)` already drops
    /// repeats, so nothing loaded from the store arrives here with one; this is
    /// the guard for an `ActivePack` built directly, and for the cost of being
    /// wrong — it runs behind the next-dot banner on every launch, where a trap
    /// is not a failed ordering but an app that cannot be opened again.
    private func topologicalOrder(dependencies: [ConceptDependency]) -> [String] {
        let members = Set(conceptNames)
        let rank = Dictionary(conceptNames.enumerated().map { ($1, $0) },
                              uniquingKeysWith: { first, _ in first })
        let edges = dependencies.filter {
            members.contains($0.prerequisite) && members.contains($0.dependent)
        }

        var remaining = Dictionary(conceptNames.map { ($0, 0) },
                                   uniquingKeysWith: { first, _ in first })
        var dependents: [String: [String]] = [:]
        for edge in edges {
            remaining[edge.dependent, default: 0] += 1
            dependents[edge.prerequisite, default: []].append(edge.dependent)
        }

        var ready = remaining.filter { $0.value == 0 }.map(\.key)
            .sorted { (rank[$0] ?? 0) < (rank[$1] ?? 0) }
        var order: [String] = []
        while !ready.isEmpty {
            let name = ready.removeFirst()
            order.append(name)
            for dependent in dependents[name] ?? [] {
                remaining[dependent]? -= 1
                if remaining[dependent] == 0 {
                    ready.append(dependent)
                    ready.sort { (rank[$0] ?? 0) < (rank[$1] ?? 0) }
                }
            }
        }
        // A cycle would strand Concepts here, but PackValidator rejects those
        // before install; append any stragglers rather than silently dropping.
        return order + conceptNames.filter { !order.contains($0) }
    }
}

// MARK: - Installing and exporting

/// Installs a validated Pack into the store, and snapshots the active one back
/// out to the Pack file format.
@MainActor
enum PackInstaller {

    /// Creates the Pack's Concepts, Clusters, Dependencies and Semantic Links,
    /// and offers its suggested Sources.
    ///
    /// Installing again over the top is the update path: a Concept that still
    /// exists keeps its Mastery, its Lit state and its history, and adopts the
    /// Pack's corrected definition and Cluster. A Concept the new Pack drops is
    /// left alone entirely — it stops being part of the Pack, it is not deleted.
    ///
    /// `vector` exists so tests can install a Pack without Apple's embedding
    /// having an opinion; production always uses the default.
    @discardableResult
    static func install(_ pack: PackFile, origin: PackOrigin,
                        context: ModelContext,
                        vector: @MainActor (String) -> [Double]? = SemanticLinker.embed
    ) throws -> InstalledPack {
        try PackValidator.validate(pack)

        do {
            // Retire the previous Pack. Its Concepts stay — what you learned is
            // yours, not the Pack's.
            for record in (try? context.fetch(FetchDescriptor<InstalledPack>())) ?? [] {
                record.isActive = false
            }

            let existing = (try? context.fetch(FetchDescriptor<Concept>())) ?? []
            let byExactName = Dictionary(existing.map { ($0.name, $0) },
                                         uniquingKeysWith: { first, _ in first })
            let byLowerName = Dictionary(existing.map { ($0.name.lowercased(), $0) },
                                         uniquingKeysWith: { first, _ in first })

            // The Concept that now stands for each of the Pack's names. A
            // reader's own reading may already have created "rag" where the
            // Pack says "RAG"; that row keeps its name and its history, and
            // everything downstream refers to it by the name it really has.
            var resolved: [String: Concept] = [:]
            for packConcept in pack.concepts {
                if let found = byExactName[packConcept.name]
                    ?? byLowerName[packConcept.name.lowercased()] {
                    // Keep Mastery and history; take the author's corrections.
                    found.category = packConcept.cluster
                    found.conceptDefinition = packConcept.definition
                    resolved[packConcept.name] = found
                } else {
                    let concept = Concept(name: packConcept.name, category: packConcept.cluster,
                                          definition: packConcept.definition)
                    concept.masteryLevel = 0.0      // a dim dot until you light it
                    context.insert(concept)
                    resolved[packConcept.name] = concept
                }
            }

            // A Dependency is authored as part of a Pack, so the active Pack
            // owns the whole graph: rebuild it rather than letting edges from
            // every past install accumulate. A corrected Pack that drops or
            // reverses an edge would otherwise keep the old one forever — and
            // a reversed pair is a cycle, which no Frontier can advance past.
            for edge in (try? context.fetch(FetchDescriptor<ConceptDependency>())) ?? [] {
                context.delete(edge)
            }
            var edges: Set<String> = []
            for packConcept in pack.concepts {
                guard let dependent = resolved[packConcept.name] else { continue }
                for dependency in packConcept.dependencies {
                    guard let prerequisite = resolved[dependency] else { continue }
                    let edge = "\(prerequisite.name)→\(dependent.name)"
                    guard edges.insert(edge).inserted else { continue }
                    context.insert(ConceptDependency(prerequisite: prerequisite.name,
                                                     dependent: dependent.name))
                }
            }
            // Semantic Links are derived from the Pack's own definitions, so
            // the Pack owns them the way it owns its Dependencies: rebuild,
            // rather than let every past install's edges accumulate. Nothing of
            // the reader's is lost by this — a Semantic Link records what two
            // Concepts mean, never anything they did.
            for link in (try? context.fetch(FetchDescriptor<SemanticLink>())) ?? [] {
                context.delete(link)
            }
            // Computed over the Concepts as the store now names them, so an
            // edge can never point at a name no fetch would find. Only the
            // Pack's own Concepts take part: what the reader's reading turned
            // up is theirs, and is not part of the map the Pack draws.
            rebuildSemanticLinks(for: pack.concepts.compactMap { packConcept in
                resolved[packConcept.name].map {
                    LinkableConcept(name: $0.name, definition: packConcept.definition)
                }
            }, context: context, vector: vector)

            // No Co-read Link is manufactured here. ADR-0002: a Dependency is a
            // claim about learning order, a Semantic Link is a claim about what
            // two Concepts mean, and a Co-read Link is a record of what you
            // actually read together. Installing a Pack is not reading.
            //
            // Nor is the reader subscribed to the Pack's suggested Sources. A
            // Source is chosen by the reader; the suggestions are kept on the
            // record for the app to offer.

            // Stages name Concepts too, so they resolve the same way — a record
            // whose stages and conceptNames disagree would fail its own export.
            let stages = pack.stages.map { stage in
                PackFile.PackStage(title: stage.title, subtitle: stage.subtitle,
                                   concepts: stage.concepts.compactMap { resolved[$0]?.name })
            }

            let record = InstalledPack(
                field: pack.field,
                specialtyCluster: pack.specialtyCluster,
                clusterOrder: pack.clusterOrder,
                stages: stages,
                suggestedSources: pack.suggestedSources,
                conceptNames: pack.concepts.compactMap { resolved[$0.name]?.name },
                sideQuestConcepts: pack.concepts
                    .filter { $0.cluster == pack.specialtyCluster }
                    .compactMap { resolved[$0.name]?.name },
                origin: origin)
            context.insert(record)
            try context.save()
            // The engines read a cached Pack; installing one that nobody can
            // see would be worse than not installing it.
            ActivePack.refresh(context: context)
            return record
        } catch {
            // Never leave the live context holding a Pack that was not saved:
            // `ActivePack.load` would report it as installed.
            context.rollback()
            throw error
        }
    }

    /// Replaces every Semantic Link with the ones these Concepts support.
    ///
    /// Shared by install and by the launch backfill, so a Pack that arrived
    /// before Semantic Links existed ends up with exactly the map it would
    /// have got had it been installed today. Does not save — the caller owns
    /// the transaction.
    static func rebuildSemanticLinks(
        for concepts: [LinkableConcept], context: ModelContext,
        vector: @MainActor (String) -> [Double]? = SemanticLinker.embed
    ) {
        for link in (try? context.fetch(FetchDescriptor<SemanticLink>())) ?? [] {
            context.delete(link)
        }
        for edge in SemanticLinker.link(concepts, vector: vector) {
            context.insert(SemanticLink(conceptA: edge.conceptA, conceptB: edge.conceptB,
                                        strength: edge.strength))
        }
    }

    /// Snapshots the active Pack back to the file format.
    ///
    /// Only the Pack's own Concepts go in — Concepts the reader's own reading
    /// discovered are theirs, not part of a map worth sharing.
    static func exportActivePack(context: ModelContext) -> PackFile? {
        guard let record = (try? context.fetch(
            FetchDescriptor<InstalledPack>(predicate: #Predicate { $0.isActive })
        ))?.first else { return nil }

        // Read through `namedOnce` for the same reason `ActivePack.init(record:)`
        // does: a record naming one row twice would otherwise export as two
        // identical Concepts — a file this very validator refuses to import.
        let conceptNames = record.conceptNames.namedOnce
        let members = Set(conceptNames)
        let byName = Dictionary(
            ((try? context.fetch(FetchDescriptor<Concept>())) ?? [])
                .filter { members.contains($0.name) }
                .map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first })

        let dependenciesByDependent = Dictionary(
            grouping: ((try? context.fetch(FetchDescriptor<ConceptDependency>())) ?? [])
                .filter { members.contains($0.dependent) && members.contains($0.prerequisite) },
            by: \.dependent)

        // Authored order for Concepts, sorted Dependencies: a store fetch has
        // no inherent order, and export must not depend on one.
        let concepts = conceptNames.compactMap { name -> PackFile.PackConcept? in
            guard let concept = byName[name] else { return nil }
            return .init(name: concept.name, cluster: concept.category,
                         definition: concept.conceptDefinition,
                         dependencies: (dependenciesByDependent[name] ?? [])
                            .map(\.prerequisite).sorted())
        }

        return PackFile(field: record.field,
                        specialtyCluster: record.specialtyCluster,
                        clusterOrder: record.clusterOrder,
                        concepts: concepts,
                        stages: record.stages,
                        suggestedSources: record.suggestedSources)
    }
}
