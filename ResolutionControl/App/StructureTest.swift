import AppKit
import ObjectiveC
import SwiftUI

/// Performance test (scripts/check.sh), invisible: the menu in a window that is never shown, `AppModel.testStep()` several times.
/// Counts how often AppKit rebuilds the window structure or tracking areas in the process. Every such rebuild makes macOS
/// reset the pointer while the menu is open – ~40–60 ms each time with an accessibility pointer.
/// At most one rebuild is allowed (the list grows on the first step), none afterwards. Also measures the CPU time
/// per update and 5 s of an idle open menu (limit < 5 %).
@MainActor
enum StructureTest {
    static let steps = 15
    private static var counting = false
    private static var structural = 0
    private static var tracking = 0
    private static var missing: [String] = []

    static func run(writingTo path: String) {
        hook(NSWindow.self, "_updateStructuralRegionsOnNextDisplayCycle", boolArgument: false) { structural += 1 }
        hook(NSView.self, "_setTrackingAreasDirty:", boolArgument: true) { tracking += 1 }

        let model = AppModel.shared
        model.prepareSnapshot()
        let host = NSHostingView(rootView: MenuView().environment(model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 600), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.contentView = host
        settle(host, window, seconds: 1)

        counting = true
        var stepCPU = 0.0
        for _ in 0..<steps {
            let before = cpuSeconds()
            model.testStep()
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            stepCPU += cpuSeconds() - before
            settle(host, window, seconds: 0.3)
        }
        counting = false

        // Idle open menu: do nothing for 5 s, measure process CPU (window never visible → no screen drawing).
        let idleStart = cpuSeconds()
        settle(host, window, seconds: 5)
        let idlePercent = (cpuSeconds() - idleStart) / 5 * 100
        let stepMS = stepCPU / Double(steps) * 1000

        let failures = missing.map { "selector missing (macOS changed?): \($0)" }
            + (structural > 1 ? ["structural changes while open: \(structural) in \(steps) steps"] : [])
            + (tracking > 1 ? ["tracking areas dirty while open: \(tracking) in \(steps) steps"] : [])
            + (idlePercent >= 5 ? ["open menu idle CPU \(idlePercent) % (limit 5 %)"] : [])
        let report: [String: Any] = ["steps": steps, "structural": structural, "tracking": tracking,
                                     "stepMS": (stepMS * 10).rounded() / 10, "idlePercent": (idlePercent * 100).rounded() / 100,
                                     "ok": failures.isEmpty, "failures": failures]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
        NSApp.terminate(nil)
    }

    /// CPU time consumed by the own process (user + system) in seconds.
    private static func cpuSeconds() -> Double {
        var u = rusage()
        getrusage(RUSAGE_SELF, &u)
        func sec(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1e6 }
        return sec(u.ru_utime) + sec(u.ru_stime)
    }

    private static func settle(_ host: NSView, _ window: NSWindow, seconds: Double) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }

    /// Counts calls of a (private) AppKit method. Hook methods without arguments that take a pointer type, not `AnyObject?`
    /// (otherwise a crash on release).
    private static func hook(_ cls: AnyClass, _ name: String, boolArgument: Bool, count: @escaping @MainActor () -> Void) {
        let sel = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(cls, sel) else { missing.append(name); return }
        let old = method_getImplementation(method)
        let note = { MainActor.assumeIsolated { if counting { count() } } }
        if boolArgument {
            typealias F = @convention(c) (AnyObject, Selector, Bool) -> Void
            let original = unsafeBitCast(old, to: F.self)
            let block: @convention(block) (AnyObject, Bool) -> Void = { obj, flag in note(); original(obj, sel, flag) }
            method_setImplementation(method, imp_implementationWithBlock(block))
        } else {
            typealias F = @convention(c) (AnyObject, Selector, UnsafeRawPointer?) -> Void
            let original = unsafeBitCast(old, to: F.self)
            let block: @convention(block) (AnyObject, UnsafeRawPointer?) -> Void = { obj, arg in note(); original(obj, sel, arg) }
            method_setImplementation(method, imp_implementationWithBlock(block))
        }
    }
}
