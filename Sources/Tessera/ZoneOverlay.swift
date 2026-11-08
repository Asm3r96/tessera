import AppKit
import SwiftUI
import TesseraCore

struct ZoneItem: Identifiable {
    let id: Int
    /// Top-left screen coordinates.
    var frame: CGRect
    let icon: NSImage?
    let title: String
    var detail: String
    var highlighted = false
    /// The pointer is on the drop target but has not rested long enough.
    var hovered = false
    /// The drop target in top-left screen coordinates. Nil for previews, which have no targets.
    var target: CGRect?

    init(id: Int, frame: CGRect, icon: NSImage?, title: String, detail: String) {
        self.id = id
        self.frame = frame
        self.icon = icon
        self.title = title
        self.detail = detail
        target = DropTarget.rect(in: frame)
    }
}

private final class OverlayState: ObservableObject {
    @Published var items: [ZoneItem] = []
    @Published var banner: String?
}

/// Click-through panels that draw zones above the windows, one panel per screen.
final class ZoneOverlay {
    private var panels: [CGDirectDisplayID: (panel: NSPanel, state: OverlayState)] = [:]

    func show(screenID: CGDirectDisplayID, area: CGRect, items: [ZoneItem], banner: String? = nil) {
        guard let screen = Screens.screen(id: screenID) else { return }
        let entry = panels[screenID] ?? makePanel()
        panels[screenID] = entry
        entry.state.items = items.map { item in
            var local = item
            local.frame = item.frame.offsetBy(dx: -area.minX, dy: -area.minY)
            local.target = item.target?.offsetBy(dx: -item.frame.minX, dy: -item.frame.minY)
            return local
        }
        entry.state.banner = banner
        if entry.panel.frame != screen.visibleFrame {
            entry.panel.setFrame(screen.visibleFrame, display: true)
        }
        entry.panel.orderFrontRegardless()
    }

    func hideAll() {
        for entry in panels.values { entry.panel.orderOut(nil) }
    }

    private func makePanel() -> (panel: NSPanel, state: OverlayState) {
        let state = OverlayState()
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: OverlayView(state: state))
        return (panel, state)
    }
}

private struct OverlayView: View {
    @ObservedObject var state: OverlayState

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(state.items) { item in
                ZoneTile(item: item)
                    .frame(width: item.frame.width, height: item.frame.height)
                    .offset(x: item.frame.minX, y: item.frame.minY)
            }
            if let banner = state.banner {
                Label(banner, systemImage: "macwindow.on.rectangle")
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.easeOut(duration: 0.12), value: state.items.map { [$0.highlighted, $0.hovered] })
        .animation(.easeOut(duration: 0.12), value: state.banner)
    }
}

private struct ZoneTile: View {
    let item: ZoneItem

    var body: some View {
        if let target = item.target {
            // Drag: a faint zone outline, and the drop target in its center.
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                box
                    .frame(width: target.width, height: target.height)
                    .offset(x: target.minX, y: target.minY)
            }
        } else {
            box
        }
    }

    private var box: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let strength = item.highlighted ? 1.0 : (item.hovered ? 0.6 : 0.0)
        return shape
            .fill(Color.accentColor.opacity(0.1 + 0.2 * strength))
            .overlay(shape.strokeBorder(Color.accentColor.opacity(0.45 + 0.5 * strength),
                                        lineWidth: item.highlighted ? 3 : 1.5))
            .overlay {
                VStack(spacing: 8) {
                    if let icon = item.icon {
                        Image(nsImage: icon).resizable().frame(width: 56, height: 56)
                    } else {
                        Image(systemName: "plus.rectangle.on.rectangle")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(.secondary)
                    }
                    Text(item.title).font(.title3.weight(.semibold)).lineLimit(1)
                    if !item.detail.isEmpty {
                        Text(item.detail)
                            .font(.callout)
                            .foregroundStyle(item.highlighted ? Color.accentColor : .secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(maxWidth: 280)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .scaleEffect(item.highlighted ? 1.04 : 1)
                .padding(16)
            }
    }
}
