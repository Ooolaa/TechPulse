import Foundation

/// A Pack the reader is holding but has not installed yet.
///
/// A Pack is a graph of names: Dependencies and Stages both refer to Concepts
/// by the name they were authored under. So an edit that changes which Concepts
/// exist has to reach those references too, or the draft stops being
/// installable — `PackValidator` refuses a dangling Dependency and a Stage
/// naming a Concept the Pack does not contain. Every mutation here leaves a
/// draft the validator still accepts, which is the whole point of the type: the
/// reader edits, and Install is not where they find out.
///
/// The one edit that cannot keep that promise is emptying the Pack. A Pack with
/// no Concepts is not a map, and `PackValidator.noConcepts` is what says so —
/// removing the last Concept is refused at install like any other empty Pack,
/// because nothing here can invent one back.
///
/// Ported from CareerPulse (`Services/PackDraft.swift` at `af8ab0c`), with one
/// change the validator has since forced. #22 made `PackValidator` reject two
/// Concept names differing only in case — they resolve onto a single stored row
/// — so the rename guard folds case too. The ported guard compared the new name
/// exactly, which let a rename of "RAG" to "vector database" sit beside "Vector
/// Database" and produce a draft that would not install.
///
/// `origin` travels with the draft rather than being passed at install: a draft
/// is a Pack *and* where it came from, and `PackInstaller.install` wants both.
struct PackDraft {
    var file: PackFile
    /// Where this Pack came from — what the reader is told about it, and what
    /// the installed record carries.
    var origin: PackOrigin

    /// Drops a Concept, and every reference to it.
    mutating func removeConcept(named name: String) {
        file.concepts.removeAll { $0.name == name }
        for index in file.concepts.indices {
            file.concepts[index].dependencies.removeAll { $0 == name }
        }
        for index in file.stages.indices {
            file.stages[index].concepts.removeAll { $0 == name }
        }
        // A Stage with nothing left in it draws an empty rung on the "You are
        // here" ladder. The validator tolerates one; the reader should not have
        // to look at it.
        file.stages.removeAll { $0.concepts.isEmpty }
    }

    /// Renames a Concept, carrying the new name through its Dependencies and
    /// Stages.
    ///
    /// A no-op where the new name is blank, unchanged, or one another Concept
    /// already answers to — folded without case, which is how `PackValidator`
    /// and `PackInstaller` both read a Pack's names. Silence rather than a
    /// thrown error: the caller is a text field, and the draft it is editing is
    /// simply not changed.
    mutating func renameConcept(_ oldName: String, to rawNewName: String) {
        let newName = rawNewName.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = newName.lowercased()
        guard !newName.isEmpty, newName != oldName,
              !file.concepts.contains(where: {
                  $0.name != oldName && $0.name.lowercased() == key
              })
        else { return }

        for index in file.concepts.indices {
            if file.concepts[index].name == oldName {
                file.concepts[index].name = newName
            }
            file.concepts[index].dependencies = file.concepts[index].dependencies
                .map { $0 == oldName ? newName : $0 }
        }
        for index in file.stages.indices {
            file.stages[index].concepts = file.stages[index].concepts
                .map { $0 == oldName ? newName : $0 }
        }
    }

    /// The draft's Concepts grouped into their Clusters, in the Pack's own
    /// Cluster order, skipping Clusters nothing is in.
    ///
    /// The Pack's order rather than the Concepts' — `clusterOrder` is the
    /// author's opinion about which part of the field comes first, and reading
    /// the order off whichever Concept happened to be emitted first would throw
    /// it away.
    var conceptsByCluster: [(cluster: String, concepts: [PackFile.PackConcept])] {
        let grouped = Dictionary(grouping: file.concepts, by: \.cluster)
        return file.clusterOrder.compactMap { cluster in
            grouped[cluster].map { (cluster, $0) }
        }
    }
}
