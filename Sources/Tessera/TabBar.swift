import AppKit
import SwiftUI

struct TabChip: Identifiable {
    let id: Int
    let window: AXUIElement
    let icon: NSImage?
    let name: String
    /// Read while the bar shows. Never saved.
    var title: String
    let shown: Bool
}

/// One zone that holds more than one tab.
struct TabGroup {
    /// "screen-zone", stable while the mode stays applied.
    let key: String
    /// Top-left screen coordinates.
    let zone: CGRect
    let chips: [TabChip]
}

/// What the tab bars ask Tessera to do.
struct TabActions {
    var show: (AXUIElement) -> Void
    /// Returns false when the window has no close button.
    var close: (AXUIElement) -> Bool
    var dragMoved: (AXUIElement, CGPoint) -> Void
    var dragEnded: (AXUIElement, CGPoint) -> Void
}

final class TabBarState: ObservableObject {
    @Published var chips: [TabChip] = []
    @Published var expanded = false
    @Published var notice: String?
    @Published var hovered: Int?
    var dragging = false
}

/// Small marks above each zone with tabs. Resting the pointer on them opens a bar with every tab.
final class TabBars {
    var actions = TabActions(show: { _ in }, close: { _ in false }, dragMoved: { _, _ in }, dragEnded: { _, _ in })
    private var panels: [String: TabPanel] = [:]

    func update(_ groups: [TabGroup]) {
        let keys = Set(groups.map(\.key))
        for (key, panel) in panels where !keys.contains(key) {
            panel.orderOut(nil)
            panels[key] = nil
        }
        for group in groups {
            let panel = panels[group.key] ?? TabPanel(actions: { [weak self] in self?.actions })
            panels[group.key] = panel
            panel.update(group)
        }
    }

    func hideAll() { update([]) }
}

private final class TabPanel: NSPanel {
    let state = TabBarState()
    private var zone = CGRect.zero
    private var collapseWork: DispatchWorkItem?

    init(actions: @escaping () -> TabActions?) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        let host = TabHostingView(rootView: TabBarView(state: state, actions: actions))
        host.onHover = { [weak self] inside in self?.hover(inside) }
        contentView = host
    }

    override var canBecomeKey: Bool { false }

    func update(_ group: TabGroup) {
        let titles = Dictionary(state.chips.map { ($0.window, $0.title) }, uniquingKeysWith: { a, _ in a })
        state.chips = group.chips.map { chip in
            var chip = chip
            chip.title = state.expanded ? WindowArranger.title(of: chip.window) : titles[chip.window] ?? ""
            return chip
        }
        zone = group.zone
        layout()
        orderFrontRegardless()
    }

    private func hover(_ inside: Bool) {
        collapseWork?.cancel()
        if inside {
            guard !state.expanded else { return }
            for index in state.chips.indices { state.chips[index].title = WindowArranger.title(of: state.chips[index].window) }
            state.expanded = true
            layout()
        } else {
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.state.dragging else { return }
                self.state.expanded = false
                self.state.notice = nil
                self.layout()
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
    }

    /// Collapsed: a strip of marks centered on the zone's top edge. Expanded: a bar over the top of the zone.
    private func layout() {
        let count = CGFloat(state.chips.count)
        let size = state.expanded
            ? CGSize(width: min(zone.width - 16, count * 180 + 72), height: state.notice == nil ? 50 : 72)
            : CGSize(width: count * 22 + 20, height: 14)
        let topLeft = CGRect(x: zone.midX - size.width / 2, y: zone.minY - 7, width: size.width, height: size.height)
        setFrame(Screens.topLeft(topLeft).integral, display: true)
    }
}

/// Reports when the pointer enters or leaves, also while Tessera is not the active app.
private final class TabHostingView: NSHostingView<TabBarView> {
    var onHover: (Bool) -> Void = { _ in }
    private var area: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let created = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                     owner: self, userInfo: nil)
        addTrackingArea(created)
        area = created
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHover(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHover(false)
    }
}

struct TabBarView: View {
    @ObservedObject var state: TabBarState
    let actions: () -> TabActions?

    var body: some View {
        Group {
            if state.expanded { bar } else { marks }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var marks: some View {
        HStack(spacing: 4) {
            ForEach(state.chips) { chip in
                Capsule()
                    .fill(chip.shown ? Color.accentColor : Color.accentColor.opacity(0.45))
                    .frame(width: chip.shown ? 22 : 12, height: 5)
                    .contentShape(Rectangle().inset(by: -5))
                    .onTapGesture { actions()?.show(chip.window) }
            }
        }
        .padding(.horizontal, 6)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(state.chips.count) tabs")
    }

    private var bar: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                step(-1, "chevron.left", "Previous tab")
                ForEach(state.chips) { chip in
                    ChipView(chip: chip, state: state, actions: actions)
                }
                step(1, "chevron.right", "Next tab")
            }
            if let notice = state.notice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        .padding(.horizontal, 2)
    }

    private func step(_ offset: Int, _ symbol: String, _ label: String) -> some View {
        Button {
            guard let current = state.chips.firstIndex(where: \.shown) else { return }
            let count = state.chips.count
            actions()?.show(state.chips[((current + offset) % count + count) % count].window)
        } label: {
            Image(systemName: symbol).frame(width: 18, height: 28)
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct ChipView: View {
    let chip: TabChip
    @ObservedObject var state: TabBarState
    let actions: () -> TabActions?
    private var hovering: Bool { state.hovered == chip.id }

    var body: some View {
        HStack(spacing: 6) {
            if let icon = chip.icon {
                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
            }
            Text(chip.title.isEmpty ? chip.name : chip.title)
                .font(.callout.weight(chip.shown ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Button {
                close()
            } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 16, height: 16)
            }
            .buttonStyle(.borderless)
            .opacity(hovering ? 1 : 0)
            .help("Close window")
            .accessibilityLabel("Close \(chip.name)")
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .frame(maxWidth: 180, minHeight: 30)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(chip.shown ? Color.accentColor.opacity(0.22) : (hovering ? Color.primary.opacity(0.08) : .clear)))
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { state.hovered = chip.id } else if state.hovered == chip.id { state.hovered = nil }
        }
        .onTapGesture { actions()?.show(chip.window) }
        .simultaneousGesture(DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { _ in
                state.dragging = true
                actions()?.dragMoved(chip.window, Screens.mouse)
            }
            .onEnded { _ in
                state.dragging = false
                actions()?.dragEnded(chip.window, Screens.mouse)
            })
        .help(chip.name)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(chip.name), \(chip.title)")
        .accessibilityAddTraits(chip.shown ? [.isButton, .isSelected] : .isButton)
    }

    private func close() {
        if actions()?.close(chip.window) == false {
            state.notice = "\(chip.name) has no close button for this window."
        }
    }
}
