import AppKit
import SwiftUI

struct ZoneItem: Identifiable {
    let id: Int
    /// Top-left screen coordinates.
    let frame: CGRect
    let icon: NSImage?
    let title: String
    var detail: String
    var highlighted = false
}

private final class OverlayState: ObservableObject {
    @Published var items: [ZoneItem] = []
}

/// Click-through panels that draw zones above the windows, one panel per screen.
final class ZoneOverlay {
    private var panels: [CGDirectDisplayID: (panel: NSPanel, state: OverlayState)] = [:]

    func show(screenID: CGDirectDisplayID, area: CGRect, items: [ZoneItem]) {
        guard let screen = Screens.screen(id: screenID) else { return }
        let entry = panels[screenID] ?? makePanel()
        panels[screenID] = entry
        entry.state.items = items.map { item in
            ZoneItem(id: item.id, frame: item.frame.offsetBy(dx: -area.minX, dy: -area.minY), icon: item.icon,
                     title: item.title, detail: item.detail, highlighted: item.highlighted)
        }
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.easeOut(duration: 0.12), value: state.items.map(\.highlighted))
    }
}

private struct ZoneTile: View {
    let item: ZoneItem

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        shape
            .fill(Color.accentColor.opacity(item.highlighted ? 0.3 : 0.1))
            .overlay(shape.strokeBorder(Color.accentColor.opacity(item.highlighted ? 0.95 : 0.45),
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
