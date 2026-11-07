import SwiftUI

struct MenuPanel: View {
    @ObservedObject var model: AppModel
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
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Tessera").font(.headline)
                Spacer()
                Button {
                    editing = Mode(name: "New Mode", columns: [Column(weight: 1, rows: 1), Column(weight: 1, rows: 1)])
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("New mode")
            }

            if !model.hasAccess { accessBanner }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Array(model.modes.enumerated()), id: \.element.id) { index, mode in
                    ModeCard(mode: mode,
                             hovering: model.hovered == mode.id,
                             onHover: { model.hovered = $0 ? mode.id : (model.hovered == mode.id ? nil : model.hovered) },
                             shortcut: index < 9 ? "⌃⌥\(index + 1)" : nil,
                             apply: { model.apply(mode) },
                             edit: { editing = mode })
                }
            }

            Divider()

            HStack {
                Text("Gap")
                Slider(value: $model.gap, in: 0...24, step: 2)
                Text("\(Int(model.gap)) pt")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
            Toggle("Open at login", isOn: $model.launchAtLogin)
            HStack {
                Text("Point at a screen, then press ⌃⌥ and a number.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
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
        }
        .padding(10)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
            .background(Color.primary.opacity(hovering ? 0.1 : 0.05),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button(action: edit) {
                    Image(systemName: "slider.horizontal.3")
                        .padding(5)
                        .background(.regularMaterial, in: Circle())
                }
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
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.accentColor.opacity(isMain ? 0.45 : 0.2))
                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1))
                        .frame(width: max(zone.width * geometry.size.width - 3, 0),
                               height: max(zone.height * geometry.size.height - 3, 0))
                        .offset(x: zone.minX * geometry.size.width + 1.5,
                                y: zone.minY * geometry.size.height + 1.5)
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
                .padding(8)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

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
                Button("Save") { onSave(draft.mode) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    }
}
