import AppKit
import CoreGraphics
import Observation
import os

/// Central app state.
///
/// Performance pattern: if the app needs a tick, use exactly one `Timer` (with `tolerance`, run-loop mode `.common`).
/// Sampled values go into `@ObservationIgnored` buffers and are handed to observed properties only while the menu is
/// open – otherwise SwiftUI re-evaluates the invisible menu on every tick.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    /// SF Symbol in the menu bar (and in the app icon).
    static let menuBarSymbol = "display"

    /// Incremented once the menu window has closed (resets sub-pages and lists).
    private(set) var menuGeneration = 0
    private(set) var isMenuOpen = false

    /// Connected displays with all their modes; re-read only on display changes (no timer).
    private(set) var displays: [Display] = []
    var selectedDisplayID: CGDirectDisplayID?
    private(set) var profiles: [Profile]
    /// Last failure when switching (shown in the header of the main page).
    private(set) var lastError: String?

    @ObservationIgnored private var closeChecks: Set<ObjectIdentifier> = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var reloadPending = false

    private init() {
        // Test runs use the default profiles and persist nothing. `--profiles <plist>` (snapshot only) shows an
        // exported list, e.g. `defaults export io.github.ape97.resolutioncontrol` – read, never written.
        profiles = Runtime.headless ? AppModel.snapshotProfiles : ProfileStore.load()
        displays = Runtime.isDemo ? Demo.displays : DisplaySystem.online()
        if !Runtime.headless {
            observeMenu()
            observeDisplays()
        }
    }

    // MARK: Displays

    /// Display the list acts on: the selected one, otherwise the built-in or first.
    var display: Display? { displays.first { $0.id == selectedDisplayID } ?? displays.first }

    func reloadDisplays() {
        displays = Runtime.isDemo ? Demo.displays : DisplaySystem.online()
    }

    /// macOS reports every switch/attach several times – collect and re-read once.
    private func observeDisplays() {
        CGDisplayRegisterReconfigurationCallback({ _, flags, _ in
            guard !flags.contains(.beginConfigurationFlag) else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { AppModel.shared.scheduleReload() } }
        }, nil)
    }

    private func scheduleReload() {
        guard !reloadPending else { return }
        reloadPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            MainActor.assumeIsolated {
                AppModel.shared.reloadPending = false
                AppModel.shared.reloadDisplays()
            }
        }
    }

    func isActive(_ profile: Profile, on display: Display) -> Bool {
        guard let current = display.current, let target = display.resolve(profile.target, profile.refresh) else { return false }
        return current.size == target.mode.size && abs(current.refresh - target.mode.refresh) < 0.01
    }

    /// Apply a profile to the selected display (mode only if it changes; color profile only if chosen).
    func apply(_ profile: Profile) {
        guard let display else { return }
        guard let target = display.resolve(profile.target, profile.refresh) else {
            lastError = "\(profile.name) is not available on \(display.name)."
            return
        }
        var ok = true
        if !isActive(profile, on: display) { ok = DisplaySystem.apply(target.mode, to: display.id) }
        if ok { ok = DisplaySystem.apply(profile.color, to: display) }
        lastError = ok ? nil : "Could not switch to \(profile.name)."
        reloadDisplays()
    }

    // MARK: Editing the list

    func save(_ profile: Profile) {
        if let i = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[i] = profile
        } else {
            profiles.append(profile)
        }
        persist()
    }

    func delete(_ id: UUID) {
        profiles.removeAll { $0.id == id }
        persist()
    }

    func move(_ id: UUID, by offset: Int) {
        guard let i = profiles.firstIndex(where: { $0.id == id }) else { return }
        let j = i + offset
        guard profiles.indices.contains(j) else { return }
        profiles.swapAt(i, j)
        persist()
    }

    func toggleShown(_ id: UUID) {
        guard let i = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[i].shown.toggle()
        persist()
    }

    private func persist() {
        if !Runtime.headless { ProfileStore.save(profiles) }
    }

    // MARK: Menu open / closed

    private func menuOpened() {
        guard !isMenuOpen else { return }
        isMenuOpen = true
    }

    private func menuClosed() {
        isMenuOpen = false
        menuGeneration += 1
    }

    /// Opened = the menu window becomes key; closed = the window is no longer visible
    /// (a mere loss of focus from a context menu or tooltip does not count).
    private func observeMenu() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppModel.shared.menuOpened() }
        })
        observers.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { note in
            guard let window = note.object as? NSWindow else { return }
            MainActor.assumeIsolated { AppModel.shared.awaitClose(window) }
        })
    }

    private func awaitClose(_ window: NSWindow) {
        guard closeChecks.insert(ObjectIdentifier(window)).inserted else { return }
        func check() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak window] in
                MainActor.assumeIsolated {
                    let model = AppModel.shared
                    guard let window, !window.isKeyWindow else {
                        if let window { model.closeChecks.remove(ObjectIdentifier(window)) }
                        return
                    }
                    if window.isVisible { return check() }
                    model.closeChecks.remove(ObjectIdentifier(window))
                    // Measuring aid: scripts/measure-menu.sh ends on this line.
                    Logger(subsystem: "io.github.ape97.resolutioncontrol", category: "menu").notice("Menu closed")
                    model.menuClosed()
                }
            }
        }
        check()
    }

    // MARK: Testing

    /// For snapshots and the performance test: set up state as if the menu had been open for a few seconds.
    func prepareSnapshot() {}

    private static var snapshotProfiles: [Profile] {
        guard Runtime.isSnapshot, !Runtime.isDemo, let path = Runtime.value(after: "--profiles"),
              let data = (NSDictionary(contentsOfFile: path) as? [String: Any])?[ProfileStore.key] as? Data else { return Profile.defaults }
        return ProfileStore.decode(data)
    }

    /// Performance test: exactly one update as with the menu open. Without a timer the content changes only when
    /// macOS reports a display change – then all modes are re-read (read-only, switches nothing).
    func testStep() { reloadDisplays() }
}
