import SwiftUI

/// Force simulation state. Deliberately a plain class (not @Observable):
/// TimelineView drives redraw every frame and the Canvas reads/advances the
/// simulation directly, so observation would only cause update loops.
final class GraphSimulation {
    struct Node {
        let name: String
        var position: CGPoint
        var velocity = CGVector(dx: 0, dy: 0)
        var radius: CGFloat = 5
        var state: Concept.MasteryState = .new
    }
    struct Edge {
        let a: Int
        let b: Int
        let width: CGFloat
        var directed = false      // prerequisite arrows (a → b)
    }

    private(set) var nodes: [Node] = []
    private(set) var edges: [Edge] = []
    private var settledFrames = 0
    private var lastSize: CGSize = .zero

    func configure(concepts: [Concept], links: [ConceptLink],
                   dependencies: [ConceptDependency] = [], in size: CGSize) {
        // Keep positions of existing nodes so re-configuration doesn't scatter the net.
        let existing = Dictionary(nodes.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        nodes = concepts.map { concept in
            var node = existing[concept.name] ?? Node(
                name: concept.name,
                position: CGPoint(x: center.x + .random(in: -90...90),
                                  y: center.y + .random(in: -130...130))
            )
            node.radius = 6 + concept.masteryLevel * 10
            node.state = concept.masteryState
            return node
        }
        let index = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($0.element.name, $0.offset) })
        if dependencies.isEmpty {
            edges = links.compactMap { link in
                guard let a = index[link.conceptA], let b = index[link.conceptB], a != b else { return nil }
                return Edge(a: a, b: b, width: min(3, 0.8 + CGFloat(link.weight) * 0.5))
            }
        } else {
            // Dependency mode (cluster detail): arrows only, prerequisite → dependent.
            edges = dependencies.compactMap { dep in
                guard let a = index[dep.prerequisite], let b = index[dep.dependent], a != b else { return nil }
                return Edge(a: a, b: b, width: 1.4, directed: true)
            }
        }
        settledFrames = 0
    }

    /// One physics tick: node repulsion + spring attraction on edges +
    /// centering force, with damping. Goes idle once motion dies down.
    func step(in size: CGSize) {
        // The view may configure before the canvas reaches its final size;
        // shift the whole net to the new center and wake the simulation.
        if abs(size.width - lastSize.width) > 1 || abs(size.height - lastSize.height) > 1 {
            let dx = (size.width - lastSize.width) / 2
            let dy = (size.height - lastSize.height) / 2
            for i in nodes.indices {
                nodes[i].position.x += dx
                nodes[i].position.y += dy
            }
            lastSize = size
            settledFrames = 0
        }
        guard nodes.count > 1, settledFrames < 30 else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        var forces = [CGVector](repeating: .init(dx: 0, dy: 0), count: nodes.count)

        for i in nodes.indices {
            forces[i].dx += (center.x - nodes[i].position.x) * 0.015
            forces[i].dy += (center.y - nodes[i].position.y) * 0.015
            for j in nodes.indices where j > i {
                var dx = nodes[i].position.x - nodes[j].position.x
                var dy = nodes[i].position.y - nodes[j].position.y
                var d2 = dx * dx + dy * dy
                if d2 < 1 { dx = .random(in: -1...1); dy = .random(in: -1...1); d2 = dx * dx + dy * dy }
                let distance = sqrt(d2)
                let repulsion = 1400 / d2
                forces[i].dx += dx / distance * repulsion
                forces[i].dy += dy / distance * repulsion
                forces[j].dx -= dx / distance * repulsion
                forces[j].dy -= dy / distance * repulsion
            }
        }
        for edge in edges {
            let dx = nodes[edge.b].position.x - nodes[edge.a].position.x
            let dy = nodes[edge.b].position.y - nodes[edge.a].position.y
            let distance = max(1, sqrt(dx * dx + dy * dy))
            let attraction = (distance - 72) * 0.02
            forces[edge.a].dx += dx / distance * attraction
            forces[edge.a].dy += dy / distance * attraction
            forces[edge.b].dx -= dx / distance * attraction
            forces[edge.b].dy -= dy / distance * attraction
        }

        var maxSpeed: CGFloat = 0
        for i in nodes.indices {
            var v = CGVector(dx: (nodes[i].velocity.dx + forces[i].dx) * 0.82,
                             dy: (nodes[i].velocity.dy + forces[i].dy) * 0.82)
            let speed = sqrt(v.dx * v.dx + v.dy * v.dy)
            if speed > 6 { v.dx *= 6 / speed; v.dy *= 6 / speed }
            nodes[i].velocity = v
            nodes[i].position.x = min(max(nodes[i].position.x + v.dx, 24), size.width - 24)
            nodes[i].position.y = min(max(nodes[i].position.y + v.dy, 24), size.height - 24)
            maxSpeed = max(maxSpeed, speed)
        }
        settledFrames = maxSpeed < 0.05 ? settledFrames + 1 : 0
    }

    func node(at point: CGPoint) -> Node? {
        nodes.min { a, b in
            hypot(a.position.x - point.x, a.position.y - point.y) <
            hypot(b.position.x - point.x, b.position.y - point.y)
        }.flatMap { nearest in
            hypot(nearest.position.x - point.x, nearest.position.y - point.y) <= nearest.radius + 14
                ? nearest : nil
        }
    }
}

/// The knowledge net (mockup 1c): concepts as dots, co-occurrence as edges.
/// Node size = mastery, color = state; pinch to zoom, drag to pan, tap a dot
/// for the concept sheet.
struct ForceGraphView: View {
    let concepts: [Concept]
    let links: [ConceptLink]
    var dependencies: [ConceptDependency] = []
    var frontier: Set<String> = []        // dashed "ready to learn" rings
    var onSelect: (String) -> Void

    @State private var sim = GraphSimulation()
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    private func nodeColor(_ state: Concept.MasteryState) -> Color {
        switch state {
        case .new: Theme.stateNew
        case .learning: Theme.stateLearning
        case .known: Theme.stateKnown
        }
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1 / 30)) { _ in
                Canvas { ctx, size in
                    sim.step(in: size)
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    ctx.translateBy(x: offset.width + center.x * (1 - scale),
                                    y: offset.height + center.y * (1 - scale))
                    ctx.scaleBy(x: scale, y: scale)

                    for edge in sim.edges {
                        let from = sim.nodes[edge.a].position
                        let to = sim.nodes[edge.b].position
                        var path = Path()
                        path.move(to: from)
                        path.addLine(to: to)
                        ctx.stroke(path, with: .color(Color(hex: edge.directed ? 0xD5DBE3 : 0xDDE3EA)),
                                   lineWidth: edge.width)
                        if edge.directed {
                            // Arrowhead just outside the target node's radius.
                            let angle = atan2(to.y - from.y, to.x - from.x)
                            let tip = CGPoint(x: to.x - cos(angle) * (sim.nodes[edge.b].radius + 3),
                                              y: to.y - sin(angle) * (sim.nodes[edge.b].radius + 3))
                            var arrow = Path()
                            arrow.move(to: tip)
                            arrow.addLine(to: CGPoint(x: tip.x - cos(angle - 0.45) * 7,
                                                      y: tip.y - sin(angle - 0.45) * 7))
                            arrow.addLine(to: CGPoint(x: tip.x - cos(angle + 0.45) * 7,
                                                      y: tip.y - sin(angle + 0.45) * 7))
                            arrow.closeSubpath()
                            ctx.fill(arrow, with: .color(Color(hex: 0xC9D0D9)))
                        }
                    }
                    for node in sim.nodes {
                        let rect = CGRect(x: node.position.x - node.radius,
                                          y: node.position.y - node.radius,
                                          width: node.radius * 2, height: node.radius * 2)
                        ctx.fill(Path(ellipseIn: rect), with: .color(nodeColor(node.state)))
                        if frontier.contains(node.name) {
                            let ring = rect.insetBy(dx: -5, dy: -5)
                            ctx.stroke(Path(ellipseIn: ring),
                                       with: .color(Theme.stateLearning),
                                       style: StrokeStyle(lineWidth: 2.5, dash: [4, 3]))
                        }
                        if node.radius > 9 || frontier.contains(node.name) {
                            ctx.draw(
                                Text(node.name)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color(hex: 0x4B5563)),
                                at: CGPoint(x: node.position.x, y: node.position.y + node.radius + 11)
                            )
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                let world = CGPoint(
                    x: (location.x - offset.width - center.x * (1 - scale)) / scale,
                    y: (location.y - offset.height - center.y * (1 - scale)) / scale
                )
                if let node = sim.node(at: world) { onSelect(node.name) }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        offset = CGSize(width: baseOffset.width + value.translation.width,
                                        height: baseOffset.height + value.translation.height)
                    }
                    .onEnded { _ in baseOffset = offset }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in scale = min(3, max(0.5, baseScale * value)) }
                    .onEnded { _ in baseScale = scale }
            )
            .onAppear {
                sim.configure(concepts: concepts, links: links,
                              dependencies: dependencies, in: geo.size)
            }
            .onChange(of: concepts.count) {
                sim.configure(concepts: concepts, links: links,
                              dependencies: dependencies, in: geo.size)
            }
            .onChange(of: links.count) {
                sim.configure(concepts: concepts, links: links,
                              dependencies: dependencies, in: geo.size)
            }
        }
        .accessibilityIdentifier("knowledgeGraph")
    }
}
