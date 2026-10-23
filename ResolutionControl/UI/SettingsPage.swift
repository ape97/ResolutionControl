import SwiftUI

/// Second page: which resolutions appear in the menu and in what order, login item and version.
struct SettingsPage: View {
    @Environment(AppModel.self) private var model
    let back: () -> Void
    let edit: (UUID?) -> Void
    @State private var launchAtLogin = LoginItem.isEnabled
    /// Deleting needs a second tap on the (then red) trash can.
    @State private var pendingDelete: UUID?

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                RoundIconButton(symbol: "chevron.left", size: 24, help: "Back", action: back)
                Text("Settings").font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 2)

            Module(spacing: 4) {
                HStack {
                    SettingLabel(symbol: "list.bullet", title: "Menu List", tint: .accentColor)
                    Spacer()
                    RoundIconButton(symbol: "plus", size: 22, help: "Add Resolution") { edit(nil) }
                }
                SettingNote("Resolutions in the menu. Hide, reorder, edit or add them here.")
                    .padding(.bottom, 2)
                ForEach(Array(model.profiles.enumerated()), id: \.element.id) { index, p in
                    row(p, first: index == 0, last: index == model.profiles.count - 1)
                }
            }

            UpdateSettings()

            Module {
                HStack {
                    SettingLabel(symbol: "power", title: "Open at Login", tint: .green)
                    Spacer()
                    Toggle("Open at Login", isOn: Binding(get: { launchAtLogin }, set: { LoginItem.set($0); launchAtLogin = LoginItem.isEnabled }))
                        .labelsHidden()
                        .toggleStyle(.setting)
                        .controlSize(.small)
                        .help("Start Resolution Control automatically when you log in")
                }
                SettingNote("Starts Resolution Control automatically when you log in.")
            }

            HStack {
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")")
                Spacer()
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 4)
        }
    }

    private func row(_ p: Profile, first: Bool, last: Bool) -> some View {
        HStack(spacing: 5) {
            RoundIconButton(symbol: p.shown ? "eye.fill" : "eye.slash", size: 22, active: p.shown,
                            help: p.shown ? "Shown in menu – click to hide" : "Hidden – click to show in menu") {
                model.toggleShown(p.id)
            }
            DeviceBadge(symbol: p.symbol, size: 22, tint: p.badgeTint.color)
                .opacity(p.shown ? 1 : 0.55)
            VStack(alignment: .leading, spacing: 0) {
                Text(p.name).font(.system(size: 12)).lineLimit(1)
                Text(summary(p)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).monospacedDigit()
            }
            .opacity(p.shown ? 1 : 0.55)
            Spacer(minLength: 4)
            RoundIconButton(symbol: "chevron.up", size: 22, help: "Move Up") { model.move(p.id, by: -1) }
                .opacity(first ? 0.3 : 1).disabled(first)
            RoundIconButton(symbol: "chevron.down", size: 22, help: "Move Down") { model.move(p.id, by: 1) }
                .opacity(last ? 0.3 : 1).disabled(last)
            RoundIconButton(symbol: "pencil", size: 22, help: "Edit") { edit(p.id) }
            RoundIconButton(symbol: "trash", size: 22, active: pendingDelete == p.id, activeColor: .red,
                            help: pendingDelete == p.id ? "Click again to delete" : "Delete") {
                if pendingDelete == p.id {
                    model.delete(p.id)
                    pendingDelete = nil
                } else {
                    pendingDelete = p.id
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func summary(_ p: Profile) -> String {
        guard let d = model.display, let r = d.resolve(p.target, p.refresh) else { return "Not available" }
        let size = switch p.target {
        case .standard: "Default"
        case .moreSpace: "More Space"
        case .size: "\(r.approximate ? "≈ " : "")\(r.mode.size.detail)"
        }
        return "\(size) · \(d.refreshLabel(p.refresh))\(p.color == .keep ? "" : " · Color")"
    }
}
