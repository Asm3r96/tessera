/// Changes the menu order without changing a layout or its identity.
public enum ModeOrder {
    public static func move(_ modes: inout [Mode], from source: Int, to destination: Int) {
        guard modes.indices.contains(source), modes.indices.contains(destination), source != destination else { return }
        modes.insert(modes.remove(at: source), at: destination)
    }
}
