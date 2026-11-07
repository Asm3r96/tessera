import AppKit
import SwiftUI

@main
struct TesseraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuPanel(model: AppModel.shared, updater: Updater.shared)
        } label: {
            MenuBarIcon(updater: Updater.shared)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu bar icon. A small dot shows when an update is available.
struct MenuBarIcon: View {
    @ObservedObject var updater: Updater

    var body: some View {
        Image(nsImage: updater.available == nil ? Self.plain : Self.badged)
            .accessibilityLabel(updater.available == nil ? "Tessera" : "Tessera, update available")
    }

    private static let plain: NSImage = {
        let image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Tessera")!
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))!
        image.isTemplate = true
        return image
    }()

    private static let badged: NSImage = {
        let base = plain
        let image = NSImage(size: NSSize(width: base.size.width + 3, height: base.size.height), flipped: false) { rect in
            base.draw(in: NSRect(x: 0, y: 0, width: base.size.width, height: base.size.height))
            let dot = NSRect(x: rect.maxX - 7, y: rect.maxY - 7, width: 7, height: 7)
            // Cut a ring around the dot so it stands apart from the grid.
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.shared.start()
        Updater.shared.start()
    }
}
