import AppKit
import ColorSync
import CoreGraphics

/// Size as macOS shows it in the menu ("looks like"), plus whether it renders as Retina (2×) or 1:1.
struct ModeSize: Codable, Hashable, Comparable {
    var width: Int
    var height: Int
    var hiDPI: Bool

    static func < (a: ModeSize, b: ModeSize) -> Bool {
        (a.width, a.height, a.hiDPI ? 1 : 0) < (b.width, b.height, b.hiDPI ? 1 : 0)
    }

    var aspect: Double { Double(width) / Double(max(height, 1)) }
    var label: String { "\(width) × \(height)" }
    /// Short form for lists: size and render scale.
    var detail: String { "\(label) (\(hiDPI ? "2×" : "1×"))" }
}

/// Refresh rate of a profile: the highest available (on the built-in display = ProMotion) or fixed.
enum Refresh: Codable, Hashable {
    case auto
    case fixed(Double)
}

/// Which resolution a profile means. `standard`/`moreSpace` follow Apple's choices for the respective display.
enum Target: Codable, Hashable {
    case standard
    case moreSpace
    case size(ModeSize)
}

/// Color profile that a profile additionally applies.
enum ColorChoice: Codable, Hashable {
    case keep
    case factory
    case file(String)
}

/// An entry from `CGDisplayCopyAllDisplayModes` (including the otherwise hidden modes).
struct DisplayMode: Hashable {
    let id: Int32
    let size: ModeSize
    let pixelWidth: Int
    let pixelHeight: Int
    let refresh: Double
    let isDefault: Bool
    let isNative: Bool
    let cg: CGDisplayMode?

    static func == (a: DisplayMode, b: DisplayMode) -> Bool { a.id == b.id && a.size == b.size && a.refresh == b.refresh }
    func hash(into h: inout Hasher) { h.combine(id); h.combine(size) }

    init(id: Int32, size: ModeSize, pixelWidth: Int, pixelHeight: Int, refresh: Double,
         isDefault: Bool = false, isNative: Bool = false, cg: CGDisplayMode? = nil) {
        self.id = id
        self.size = size
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refresh = refresh
        self.isDefault = isDefault
        self.isNative = isNative
        self.cg = cg
    }

    init(_ m: CGDisplayMode) {
        // ioFlags: 0x4 = Apple's default resolution, 0x02000000 = native panel resolution.
        self.init(id: m.ioDisplayModeID,
                  size: ModeSize(width: m.width, height: m.height, hiDPI: m.pixelWidth > m.width),
                  pixelWidth: m.pixelWidth, pixelHeight: m.pixelHeight, refresh: m.refreshRate,
                  isDefault: m.ioFlags & 0x4 != 0, isNative: m.ioFlags & 0x0200_0000 != 0, cg: m)
    }
}

/// Result of "profile on this display".
struct Resolved: Equatable {
    let mode: DisplayMode
    /// The requested size does not exist here – the nearest one was chosen.
    let approximate: Bool
}

struct Display: Identifiable {
    let id: CGDirectDisplayID
    let uuid: CFUUID?
    let name: String
    let isBuiltin: Bool
    let modes: [DisplayMode]
    let current: DisplayMode?

    /// Panel pixels (largest native mode, otherwise the largest mode overall).
    var panel: (width: Int, height: Int) {
        let pool = modes.contains { $0.isNative } ? modes.filter(\.isNative) : modes
        let best = pool.max { $0.pixelWidth * $0.pixelHeight < $1.pixelWidth * $1.pixelHeight }
        return (best?.pixelWidth ?? 0, best?.pixelHeight ?? 0)
    }

    var hasHiDPI: Bool { modes.contains { $0.size.hiDPI } }

    /// Built-in display above 100 Hz = ProMotion (the 120 Hz mode is the variable one).
    var hasProMotion: Bool { isBuiltin && modes.contains { $0.refresh > 100 } }

    var sizes: [ModeSize] { Array(Set(modes.map(\.size))).sorted() }

    /// The sizes System Settings offers: the panel's aspect ratio, Retina where possible.
    var appleSizes: [ModeSize] {
        let p = panel
        guard p.height > 0 else { return [] }
        let aspect = Double(p.width) / Double(p.height)
        return sizes.filter { $0.hiDPI == hasHiDPI && abs($0.aspect - aspect) < 0.01 }
    }

    var standardSize: ModeSize? {
        modes.first(where: \.isDefault)?.size ?? appleSizes.first { $0.width * 2 == panel.width } ?? appleSizes.last
    }

    var moreSpaceSize: ModeSize? { appleSizes.last }

    func size(for target: Target) -> ModeSize? {
        switch target {
        case .standard: standardSize
        case .moreSpace: moreSpaceSize
        case .size(let s): s
        }
    }

    func refreshRates(for size: ModeSize) -> [Double] {
        Array(Set(modes.filter { $0.size == size }.map(\.refresh))).sorted(by: >)
    }

    /// Resolve a profile: exact size, otherwise the most similar one (same rendering, area and aspect ratio);
    /// rate "auto" = highest, otherwise the nearest fixed one.
    func resolve(_ target: Target, _ refresh: Refresh) -> Resolved? {
        guard let wanted = size(for: target) else { return nil }
        var size = wanted
        if !modes.contains(where: { $0.size == wanted }) {
            func cost(_ s: ModeSize) -> Double {
                abs(log(Double(s.width * s.height) / Double(max(wanted.width * wanted.height, 1))))
                    + abs(s.aspect - wanted.aspect) * 2 + (s.hiDPI == wanted.hiDPI ? 0 : 10)
            }
            guard let near = sizes.min(by: { cost($0) < cost($1) }) else { return nil }
            size = near
        }
        let pool = modes.filter { $0.size == size }
        let pick: DisplayMode?
        switch refresh {
        case .auto: pick = pool.max { $0.refresh < $1.refresh }
        case .fixed(let hz): pick = pool.min { abs($0.refresh - hz) < abs($1.refresh - hz) }
        }
        return pick.map { Resolved(mode: $0, approximate: size != wanted) }
    }

    func refreshLabel(_ hz: Double) -> String {
        if hz == 0 { return "Default" }
        if hasProMotion && hz > 100 { return "ProMotion" }
        return hz == hz.rounded() ? "\(Int(hz)) Hz" : String(format: "%.2f Hz", hz)
    }

    func refreshLabel(_ r: Refresh) -> String {
        switch r {
        case .auto: hasProMotion ? "ProMotion" : "Highest"
        case .fixed(let hz): refreshLabel(hz)
        }
    }

    /// Label of a size as in System Settings.
    func appleLabel(_ s: ModeSize) -> String? {
        let list = appleSizes
        if s == standardSize { return "Default" }
        if s == list.last { return "More Space" }
        if s == list.first, list.count > 1 { return "Larger Text" }
        return nil
    }

    /// How sharp: panel pixels per rendered pixel (1 = coincident).
    func scaling(_ m: DisplayMode) -> String {
        let p = panel
        guard m.pixelWidth > 0, p.width > 0 else { return "" }
        let f = Double(p.width) / Double(m.pixelWidth)
        if abs(f - 1) < 0.005 { return "Pixel-exact" }
        if abs(f - f.rounded()) < 0.005 { return "Integer ×\(Int(f.rounded()))" }
        return String(format: f > 1 ? "Upscaled ×%.2f" : "Downsampled ×%.2f", f > 1 ? f : 1 / f)
    }
}

/// Reading and switching through the public CoreGraphics/ColorSync interfaces (no root, no helper).
enum DisplaySystem {
    static func online() -> [Display] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        let names = Dictionary(NSScreen.screens.compactMap { s -> (CGDirectDisplayID, String)? in
            guard let n = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (n.uint32Value, s.localizedName)
        }, uniquingKeysWith: { a, _ in a })
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        return ids.prefix(Int(count)).compactMap { id in
            // Mirrored secondary displays follow their primary – don't offer them separately.
            guard CGDisplayMirrorsDisplay(id) == kCGNullDirectDisplay else { return nil }
            let all = (CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] ?? [])
                .filter { $0.isUsableForDesktopGUI() }
                .map(DisplayMode.init)
            guard !all.isEmpty else { return nil }
            let current = CGDisplayCopyDisplayMode(id).map(DisplayMode.init)
            let builtin = CGDisplayIsBuiltin(id) != 0
            return Display(id: id, uuid: CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
                           name: names[id] ?? (builtin ? "Built-in Display" : "Display"),
                           isBuiltin: builtin, modes: all, current: current)
        }
        .sorted { ($0.isBuiltin ? 0 : 1, $0.id) < ($1.isBuiltin ? 0 : 1, $1.id) }
    }

    /// Set a mode permanently (like System Settings).
    static func apply(_ mode: DisplayMode, to display: CGDirectDisplayID) -> Bool {
        guard let cg = mode.cg else { return false }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        guard CGConfigureDisplayWithDisplayMode(config, display, cg, nil) == .success else {
            CGCancelDisplayConfiguration(config)
            return false
        }
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }

    static func apply(_ color: ColorChoice, to display: Display) -> Bool {
        guard let uuid = display.uuid else { return false }
        let value: CFTypeRef
        switch color {
        case .keep: return true
        case .factory: value = kCFNull
        case .file(let path): value = URL(fileURLWithPath: path) as CFURL
        }
        let profiles = [kColorSyncDeviceDefaultProfileID.takeUnretainedValue(): value,
                        kColorSyncProfileUserScope.takeUnretainedValue(): kCFPreferencesCurrentUser] as CFDictionary
        return ColorSyncDeviceSetCustomProfiles(kColorSyncDisplayDeviceClass.takeUnretainedValue(), uuid, profiles)
    }
}

/// Installed RGB color profiles suitable as a display profile (profiles of other displays excluded).
struct ColorProfile: Identifiable, Hashable {
    let path: String
    let name: String
    var id: String { path }

    static func installed(for display: Display) -> [ColorProfile] {
        if Runtime.isDemo { return Demo.colorProfiles.map { ColorProfile(path: "/demo/\($0)", name: $0) } }
        let uuid = display.uuid.flatMap { CFUUIDCreateString(nil, $0) as String? } ?? "-"
        let dirs = ["/System/Library/ColorSync/Profiles", "/Library/ColorSync/Profiles",
                    "/Library/ColorSync/Profiles/Displays", NSHomeDirectory() + "/Library/ColorSync/Profiles"]
        var seen = Set<String>()
        var out: [ColorProfile] = []
        for dir in dirs {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
            for f in files where f.hasSuffix(".icc") || f.hasSuffix(".icm") {
                if dir.hasSuffix("/Displays") && !f.contains(uuid) { continue }
                let url = URL(fileURLWithPath: dir).appendingPathComponent(f)
                guard let p = ColorSyncProfileCreateWithURL(url as CFURL, nil)?.takeRetainedValue(),
                      let header = ColorSyncProfileCopyHeader(p)?.takeRetainedValue() as Data?, header.count >= 20
                else { continue }
                // The header is in host byte order here: read class and color space backwards.
                let cls = String(bytes: header[12..<16].reversed(), encoding: .ascii) ?? ""
                let space = String(bytes: header[16..<20].reversed(), encoding: .ascii) ?? ""
                guard ["mntr", "spac"].contains(cls), space == "RGB " else { continue }
                let name = ColorSyncProfileCopyDescriptionString(p)?.takeRetainedValue() as String? ?? f
                guard seen.insert(name).inserted else { continue }
                out.append(ColorProfile(path: url.path, name: name))
            }
        }
        return out.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
