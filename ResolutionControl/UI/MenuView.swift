import OSLog
import SwiftUI

/// Pages in the menu: list, settings, editor of an entry (nil ID = new entry).
enum Page: Equatable {
    case main
    case settings
    case editor(UUID?)

    @MainActor static var initial: Page {
        if Runtime.arguments.contains("--editor") { return .editor(AppModel.shared.profiles.last?.id) }
        if Runtime.arguments.contains("--settings") { return .settings }
        return .main
    }

    var depth: Int {
        switch self {
        case .main: 0
        case .settings: 1
        case .editor: 2
        }
    }
}

struct MenuView: View {
    @Environment(AppModel.self) private var model
    @State private var page = Page.initial
    @State private var forward = true

    var body: some View {
        VStack(spacing: 8) {
            Group {
                switch page {
                case .main:
                    MainPage()
                case .settings:
                    SettingsPage(back: { go(.main) }, edit: { go(.editor($0)) })
                case .editor(let id):
                    ProfileEditor(original: model.profiles.first { $0.id == id }, done: { go(.settings) })
                }
            }
            .transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading),
                                    removal: .move(edge: forward ? .leading : .trailing)).combined(with: .opacity))
            FooterBar(settingsActive: page != .main) { go(page == .main ? .settings : .main) }
        }
        .padding(10)
        .frame(width: 380)
    }

    private func go(_ next: Page) {
        forward = next.depth > page.depth
        withAnimation(.snappy(duration: 0.25)) { page = next }
    }
}

/// Main page: display with its current resolution, below it the user's list – one tap switches.
struct MainPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 8) {
            Module {
                HStack(spacing: 8) {
                    DeviceBadge(symbol: AppModel.menuBarSymbol, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.display?.name ?? "No Display").font(.system(size: 13, weight: .semibold))
                        Text(currentLabel).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Spacer()
                }
                if model.displays.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(model.displays) { d in
                            DisplayChip(name: d.name, selected: d.id == model.display?.id) { model.selectedDisplayID = d.id }
                        }
                        Spacer()
                    }
                }
                if let error = model.lastError {
                    SettingNote(error, tint: .red)
                }
            }

            Module(spacing: 2) {
                let shown = model.profiles.filter(\.shown)
                if shown.isEmpty {
                    SettingNote("No resolutions in the list. Add them in Settings.")
                        .padding(.vertical, 6)
                }
                ForEach(shown) { p in
                    ProfileRow(profile: p)
                }
            }
        }
    }

    private var currentLabel: String {
        guard let d = model.display, let m = d.current else { return "–" }
        return "\(m.size.detail) · \(d.refreshLabel(m.refresh))"
    }
}

/// A row of the list. No SwiftUI Button (the row changes when switching), hover only via opacity.
struct ProfileRow: View {
    @Environment(AppModel.self) private var model
    let profile: Profile
    @State private var hover = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let display = model.display
        let resolved = display?.resolve(profile.target, profile.refresh)
        let active = display.map { model.isActive(profile, on: $0) } ?? false
        HStack(spacing: 9) {
            DeviceBadge(symbol: profile.symbol, size: 26, tint: profile.badgeTint.color)
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.name).font(.system(size: 12.5, weight: active ? .semibold : .regular))
                Text(detail(display, resolved)).font(.system(size: 10.5)).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .opacity(active ? 1 : 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(.primary.opacity(hover ? 0.07 : 0), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { choose() }
        .demoTarget(profile.name)
        .help(resolved == nil ? "Not available on this display" : "Switch to this resolution")
        .opacity(resolved == nil ? 0.45 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { choose() }
    }

    private func detail(_ d: Display?, _ r: Resolved?) -> String {
        guard let d, let r else { return "Not available" }
        return "\(r.approximate ? "≈ " : "")\(r.mode.size.detail) · \(d.refreshLabel(r.mode.refresh))"
    }

    /// Close the menu first, then switch – otherwise the open window jumps around on the mode change.
    private func choose() {
        guard let display = model.display, display.resolve(profile.target, profile.refresh) != nil else { return }
        let profile = profile
        MenuBarMenu.close(dismiss) { AppModel.shared.apply(profile) }
    }
}

extension ProfileTint {
    var color: Color {
        switch self {
        case .blue: .blue
        case .teal: .teal
        case .green: .green
        case .yellow: .yellow
        case .orange: .orange
        case .pink: .pink
        case .purple: .purple
        case .gray: .gray
        }
    }
}

/// Display picker when several displays are connected.
struct DisplayChip: View {
    let name: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(selected ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.primary.opacity(0.07)), in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Show the resolutions of \(name)")
    }
}

/// Footer as in all apps: name on the left, Settings and Quit on the right.
struct FooterBar: View {
    let settingsActive: Bool
    let toggleSettings: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text("Resolution Control")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.tertiary)
            Spacer()
            RoundIconButton(symbol: "gearshape.fill", size: 24, active: settingsActive, help: "Settings", action: toggleSettings)
            RoundIconButton(symbol: "power", size: 24, help: "Quit Resolution Control") {
                NSApp.terminate(nil)
            }
        }
        .padding(.horizontal, 4)
    }
}

/// Close the menu from code. SwiftUI's menu bar item has no click action (`action == nil`, confirmed with lldb),
/// so `performClick` has no effect. SwiftUI does give the menu content a presentation connection, however
/// (`WindowMenuBarExtraBehavior.hide`): `dismiss()` closes the window and clears the item's highlight.
/// Fallback if the window is still visible afterwards: hide it and clear the highlight by hand.
enum MenuBarMenu {
    static var window: NSWindow? { NSApp.windows.first { $0.className.contains("MenuBarExtraWindow") } }

    static var button: NSButton? {
        for window in NSApp.windows where window.className.contains("StatusBarWindow") {
            if let button = find(in: window.contentView) { return button }
        }
        return nil
    }

    /// Closes the menu and then calls `then` – only once the window is gone (otherwise it jumps on the mode change).
    static func close(_ dismiss: DismissAction, then: @escaping @MainActor () -> Void) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            MainActor.assumeIsolated {
                if let window, window.isVisible {
                    window.orderOut(nil)
                    button?.highlight(false)
                    log.notice("Menu dismissed via fallback")
                } else {
                    log.notice("Menu dismissed via dismiss")
                }
                then()
            }
        }
    }

    private static let log = Logger(subsystem: "io.github.ape97.resolutioncontrol", category: "menu")

    private static func find(in view: NSView?) -> NSButton? {
        guard let view else { return nil }
        if let button = view as? NSButton, view.className.contains("StatusBarButton") { return button }
        for sub in view.subviews { if let hit = find(in: sub) { return hit } }
        return nil
    }
}
