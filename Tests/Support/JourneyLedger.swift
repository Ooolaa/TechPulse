import Foundation

/// One step of a UI journey, named by the screenshot that proves it happened.
///
/// A step is required unless the journey says, in words, why its absence is
/// legitimate. That sentence is the whole point: `if element.exists { … }` also
/// expressed "this might not be here", but expressed it to nobody (#30).
struct JourneyStep: Equatable {
    let name: String

    /// `nil` when the step must run. Otherwise the written reason it may not.
    let skippableBecause: String?

    static func required(_ name: String) -> JourneyStep {
        JourneyStep(name: name, skippableBecause: nil)
    }

    static func optional(_ name: String, because reason: String) -> JourneyStep {
        JourneyStep(name: name, skippableBecause: reason)
    }
}

/// What a journey promised to do, against what it actually did.
///
/// The journey declares its steps up front and records each one as it runs.
/// A required step that never ran is a failure naming itself; a skippable one
/// that never ran is printed with its reason. Nothing is silent, which is the
/// property #30 asked for: before this, a skipped step left the suite green and
/// only a stale PNG timestamp gave it away, four days later.
struct JourneyLedger {
    let declared: [JourneyStep]
    private(set) var ran: [String] = []

    init(_ declared: [JourneyStep]) {
        self.declared = declared
    }

    mutating func record(_ name: String) {
        ran.append(name)
    }

    /// Required steps that never ran, in declaration order.
    var missing: [String] {
        declared
            .filter { $0.skippableBecause == nil && !ran.contains($0.name) }
            .map(\.name)
    }

    /// Steps whose absence the journey declared legitimate, and did not run —
    /// reported with the reason rather than passed over.
    var skipped: [(name: String, reason: String)] {
        declared.compactMap { step in
            guard let reason = step.skippableBecause, !ran.contains(step.name) else { return nil }
            return (step.name, reason)
        }
    }

    /// Steps that ran without being declared. The declaration is meant to be a
    /// description of the journey, and one that has drifted describes nothing.
    var undeclared: [String] {
        let names = Set(declared.map(\.name))
        var seen: Set<String> = []
        return ran.filter { !names.contains($0) && seen.insert($0).inserted }
    }

    /// Steps recorded more than once: the name no longer identifies one step,
    /// and its screenshot no longer shows the step you think it does.
    var duplicated: [String] {
        var counts: [String: Int] = [:]
        for name in ran { counts[name, default: 0] += 1 }
        var unique: [String] = []
        for name in ran where counts[name, default: 0] > 1 && !unique.contains(name) {
            unique.append(name)
        }
        return unique
    }

    /// Everything wrong with this run in one message, or `nil` if the journey
    /// did what it said it would.
    var failureReport: String? {
        var lines: [String] = []
        if !missing.isEmpty {
            lines.append("steps that never ran: \(missing.joined(separator: ", "))")
        }
        if !undeclared.isEmpty {
            lines.append("steps that ran but were never declared: \(undeclared.joined(separator: ", "))")
        }
        if !duplicated.isEmpty {
            lines.append("steps recorded twice: \(duplicated.joined(separator: ", "))")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "; ")
    }

    /// The skipped steps and their reasons, or `nil` if none were skipped.
    var skipReport: String? {
        guard !skipped.isEmpty else { return nil }
        return skipped
            .map { "skipped \($0.name) — \($0.reason)" }
            .joined(separator: "; ")
    }
}

/// The journey's screenshots, checked like the evidence they are meant to be.
///
/// #26 was cracked by noticing that `4-marked-known.png` was four days old, by
/// comparing file timestamps by hand. A file left behind by an earlier run
/// proves nothing about this one, so freshness is checked here instead.
struct ScreenshotEvidence {
    let directory: String
    let runStarted: Date

    /// Writes one screenshot. Returns the reason it is not evidence, or `nil`.
    func write(_ png: Data, named name: String) -> String? {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: path(for: name), contents: png) else {
            return "\(name).png could not be written to \(directory)"
        }
        return problem(with: name)
    }

    /// The reason this screenshot is not proof that this run took it, or `nil`.
    func problem(with name: String) -> String? {
        let path = path(for: name)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
            return "\(name).png was never written, so the step it stands for did not happen"
        }
        if (attributes[.size] as? Int ?? 0) == 0 {
            return "\(name).png is empty, so it shows nothing"
        }
        // A second of slack: the run's start and the file's timestamp come from
        // different clocks (the test process and the filesystem).
        if let modified = attributes[.modificationDate] as? Date,
           modified < runStarted.addingTimeInterval(-1) {
            return "\(name).png is left over from \(modified.formatted()) — this run did not write it"
        }
        return nil
    }

    private func path(for name: String) -> String {
        "\(directory)/\(name).png"
    }
}
