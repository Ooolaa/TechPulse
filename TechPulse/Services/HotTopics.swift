import Foundation

/// The 🔥 lane's vocabulary.
///
/// This lived on `KnowledgePack` and did not belong there: ADR-0003 rejects an
/// aliases field on the Pack format outright, because a list written when a
/// Pack was generated ages the moment it is written. Hosting it here keeps the
/// Feed working today without pretending it is Pack data, and gives #12 one
/// place to replace when Hot Topics become observed from the reader's Sources.
enum HotTopics {

    /// The Cluster the rolling "what the world is doing right now" Concepts sit in.
    static let cluster = "Hot Topics"

    /// Lowercased text aliases for the Feed's 🔥 filter — matched against
    /// article text directly, so the filter works even before on-device
    /// analysis tags Concepts. Specific enough not to false-positive.
    static let aliases: [String] = [
        "ai agent", "agentic", "vibe coding", "reasoning model", "world model",
        "synthetic data", "open-weight", "open weights", "small language model",
        "diffusion model", "text-to-video", "video generation", "humanoid",
        "robotics", "vision language", "multimodal",
    ]
}
