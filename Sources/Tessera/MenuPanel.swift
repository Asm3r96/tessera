import SwiftUI
import TesseraCore

struct MenuPanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: Updater
    @ObservedObject var hotKeys: HotKeys
    @Environment(\.dismiss) private var dismiss
    private var editing: Mode? {
        get { model.editing }
        nonmutating set { model.editing = newValue }
    }

    var body: some View {
        Group {
            if let mode = editing {
                ModeEditor(draft: Draft(mode),
                           isNew: !model.modes.contains { $0.id == mode.id },
                           onSave: { model.save($0); editing = nil },
                           onDelete: { model.delete(mode); editing = nil },
                           onCancel: { editing = nil })
                    .id(mode.id)
            } else {
                overview
            }
        }
        .frame(width: 340)
        .onAppear { model.refresh() }
        .onDisappear { model.hovered = nil }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Tessera").font(.headline)
                Spacer()
                Button {
                    dismiss()
                    model.showSettings()
                } label: {
                    Image(systemName: "gearshape").frame(width: 26, height: 26).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassCircle()
                .help("Settings")
                .accessibilityLabel("Settings")
                Button {
                    editing = Mode(name: "New Mode", columns: [Column(weight: 1, rows: 1), Column(weight: 1, rows: 1)])
                } label: {
                    Image(systemName: "plus").frame(width: 26, height: 26).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassCircle()
                .help("New mode")
                .accessibilityLabel("New mode")
            }
            .glassGroup(spacing: 8)

            if let release = updater.available { updateBanner(release) }
            if !model.hasAccess { accessBanner }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Array(model.modes.enumerated()), id: \.element.id) { index, mode in
                    ModeCard(mode: mode,
                             hovering: model.hovered == mode.id,
                             onHover: { model.hovered = $0 ? mode.id : (model.hovered == mode.id ? nil : model.hovered) },
                             shortcut: hotKeys.label(forLayout: index),
                             apply: { model.apply(mode) },
                             edit: { editing = mode })
                }
            }
            .glassGroup(spacing: 10)

            VStack(spacing: 10) {
                HStack {
                    Text("Gap")
                    Slider(value: $model.gap, in: 0...24, step: 2)
                    Text("\(Int(model.gap)) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
                Divider()
                settingRow("Open at login", isOn: $model.launchAtLogin)
                if updater.isRelease {
                    Divider()
                    settingRow("Check for updates", isOn: $updater.enabled)
                }
            }
            .padding(12)
            .glass(cornerRadius: 16)
            Text("Hover a mode to preview it. Drag a window onto a zone’s center to swap or replace. Hold ⌘ to add it as a tab. Drop elsewhere to float it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Tessera \(Self.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if updater.isRelease { updateCheckButton }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .glassButton()
            }
        }
        .padding(16)
    }

    private func settingRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"

    /// Checks for an update now. Shows a short result next to the version.
    @ViewBuilder
    private var updateCheckButton: some View {
        switch updater.manual {
        case .checking:
            ProgressView().controlSize(.mini).accessibilityLabel("Checking for updates")
        case .upToDate:
            Label("Up to date", systemImage: "checkmark").font(.caption).foregroundStyle(.secondary)
        case .failed:
            Label("Can’t check now", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.secondary)
        case .idle:
            Button {
                updater.checkNow()
            } label: {
                Image(systemName: "arrow.clockwise").font(.caption)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Check for updates")
            .accessibilityLabel("Check for updates")
        }
    }

    private func updateBanner(_ release: Release) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tessera \(release.version.description) is available").font(.callout.weight(.medium))
                    Link("What’s new", destination: release.page).font(.caption)
                }
                Spacer()
                if updater.installing {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Update") { updater.install() }
                        .glassButton(prominent: true)
                        .controlSize(.small)
                }
            }
            if let failure = updater.failure {
                Text(failure).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(12)
        .glass(cornerRadius: 16)
    }

    private var accessBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Allow Accessibility access").font(.callout.weight(.medium))
                Text("Tessera needs it to move windows.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open") { model.openAccessibilitySettings() }
                .glassButton()
        }
        .padding(12)
        .glass(cornerRadius: 16)
    }
}

struct ModeCard: View {
    let mode: Mode
    let hovering: Bool
    let onHover: (Bool) -> Void
    let shortcut: String?
    let apply: () -> Void
    let edit: () -> Void

    var body: some View {
        Button(action: apply) {
            VStack(alignment: .leading, spacing: 8) {
                ModePreview(mode: mode).frame(height: 64)
                HStack {
                    Text(mode.name).font(.callout.weight(.medium)).lineLimit(1)
                    Spacer()
                    if let shortcut {
                        Text(shortcut).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .glass(cornerRadius: 16, interactive: true)
        .scaleEffect(hovering ? 1.02 : 1)
        .animation(.spring(duration: 0.25), value: hovering)
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button(action: edit) {
                    Image(systemName: "slider.horizontal.3")
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .glassCircle()
                .buttonStyle(.plain)
                .padding(6)
                .help("Edit mode")
            }
        }
        .onHover(perform: onHover)
        .help("Arrange the windows on this screen")
    }
}

struct ModePreview: View {
    let mode: Mode

    var body: some View {
        GeometryReader { geometry in
            let main = mode.fillOrder.first
            ZStack(alignment: .topLeading) {
                ForEach(Array(mode.zones.enumerated()), id: \.offset) { _, zone in
                    let isMain = zone == main
                    let width = max(zone.width * geometry.size.width - 3, 0)
                    let height = max(zone.height * geometry.size.height - 3, 0)
                    let x = zone.minX * geometry.size.width + 1.5
                    let y = zone.minY * geometry.size.height + 1.5
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.gradient.opacity(isMain ? 0.85 : 0.3))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.white.opacity(isMain ? 0.25 : 0.12), lineWidth: 0.5))
                        .frame(width: width, height: height)
                        .offset(x: x, y: y)
                }
            }
        }
    }
}

final class Draft: ObservableObject {
    @Published var mode: Mode
    init(_ mode: Mode) { self.mode = mode }
}

struct ModeEditor: View {
    @ObservedObject var draft: Draft
    let isNew: Bool
    let onSave: (Mode) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    private var totalWeight: Double { max(draft.mode.columns.map(\.weight).reduce(0, +), 0.0001) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Button(action: onCancel) { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                TextField("Name", text: $draft.mode.name)
                    .textFieldStyle(.plain)
                    .font(.headline)
            }

            ModePreview(mode: draft.mode)
                .frame(height: 120)
                .padding(10)
                .glass(cornerRadius: 16)

            ForEach($draft.mode.columns) { $column in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Width \(Int((column.weight / totalWeight * 100).rounded()))%")
                            .monospacedDigit()
                        Spacer()
                        Stepper("\(column.rows) \(column.rows == 1 ? "row" : "rows")", value: $column.rows, in: 1...4)
                        Button {
                            draft.mode.columns.removeAll { $0.id == column.id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .disabled(draft.mode.columns.count <= 1)
                        .help("Remove column")
                    }
                    Slider(value: $column.weight, in: 0.5...4, step: 0.25)
                }
            }

            Button {
                draft.mode.columns.append(Column(weight: 1, rows: 1))
            } label: {
                Label("Add Column", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .disabled(draft.mode.columns.count >= 5)

            Divider()

            HStack {
                if !isNew {
                    Button("Delete", role: .destructive, action: onDelete)
                }
                Spacer()
                Button("Cancel", action: onCancel)
                    .glassButton()
                Button("Save") { onSave(draft.mode) }
                    .keyboardShortcut(.defaultAction)
                    .glassButton(prominent: true)
            }
        }
        .padding(16)
    }
}
