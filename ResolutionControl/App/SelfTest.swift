import AppKit

/// Invisible self-test (scripts/check.sh): checks the core logic and writes the result as JSON.
/// No window, no focus, no changes to system settings or other processes – nothing the user should notice.
/// Displays are only read, never switched.
@MainActor
enum SelfTest {
    static func run(writingTo path: String) {
        var failures: [String] = []
        var report: [String: Any] = [:]
        func expect(_ ok: Bool, _ message: @autoclosure () -> String) { if !ok { failures.append(message()) } }
        report["version"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"

        let symbols = [AppModel.menuBarSymbol, "eye.fill", "eye.slash", "pencil", "trash", "plus", "chevron.up", "chevron.down",
                       "list.bullet", "character.cursor.ibeam", "rectangle.dashed", "waveform.path", "paintpalette.fill"]
            + Profile.defaults.map(\.symbol)
            + [Profile(name: "", target: .size(ModeSize(width: 1, height: 1, hiDPI: true))).symbol, "circle.fill"]
            + Profile.iconChoices
        for s in symbols where NSImage(systemSymbolName: s, accessibilityDescription: nil) == nil {
            failures.append("symbol missing: \(s)")
        }

        // Built-in list and persistence (own test domain, removed afterwards).
        let names = Profile.defaults.map(\.name)
        expect(names == ["Default", "More Space", "HD", "2K"], "defaults: \(names)")
        var custom = Profile(name: "Test", target: .size(ModeSize(width: 2048, height: 1330, hiDPI: false)), refresh: .fixed(59.94),
                             color: .file("/System/Library/ColorSync/Profiles/sRGB Profile.icc"))
        custom.shown = false
        custom.icon = "film"
        custom.tint = .pink
        expect(Set(Profile.defaults.map(\.badgeTint)).count == 4 && Set(Profile.defaults.map(\.symbol)).count == 4,
               "defaults need distinct colors and icons")
        expect(Profile.defaults.allSatisfy { Profile.iconChoices.contains($0.symbol) }, "default icons must be choosable")
        // A list from version 1.0.3 (without icon/tint) must stay readable and get defaults by target.
        let old = #"[{"id":"7C1A4F3E-2B7D-4E3A-9C55-0E1B2C3D4E5F","name":"Alt","target":{"standard":{}},"refresh":{"auto":{}},"color":{"keep":{}},"shown":true}]"#
        if let list = try? JSONDecoder().decode([Profile].self, from: Data(old.utf8)), let p = list.first {
            expect(p.icon == nil && p.symbol == "textformat.size" && p.badgeTint == .blue, "old profile fallback: \(p.symbol) \(p.badgeTint)")
        } else {
            failures.append("old profile list (1.0.3) not decodable")
        }
        for d in Profile.defaults {
            var bare = d
            bare.icon = nil
            bare.tint = nil
            let p = ProfileStore.withDefaultLook(bare)
            expect(p.symbol == d.symbol && p.badgeTint == d.badgeTint, "old \(d.name) must get default look")
        }
        let suite = "io.github.ape97.resolutioncontrol.selftest"
        if let store = UserDefaults(suiteName: suite) {
            expect(ProfileStore.load(from: store) == Profile.defaults, "empty store must give defaults")
            ProfileStore.save(Profile.defaults + [custom], to: store)
            expect(ProfileStore.load(from: store) == Profile.defaults + [custom], "store roundtrip")
            store.set(Data("broken".utf8), forKey: ProfileStore.key)
            expect(ProfileStore.load(from: store) == Profile.defaults, "broken store must give defaults")
            store.removePersistentDomain(forName: suite)
        }

        // MacBook panel 3024 × 1964 recreated: Apple's five sizes (2×), 16:10 sizes, 1:1 modes; 120 and 60 Hz each.
        let mbp = synthetic(panel: (3024, 1964), defaultSize: ModeSize(width: 1512, height: 982, hiDPI: true),
                            hiDPI: [(1024, 665), (1147, 745), (1352, 878), (1512, 982), (1800, 1169), (1512, 945), (1920, 1200)],
                            lowRes: [(1512, 982), (1920, 1200), (2048, 1330), (2560, 1600), (3024, 1964)],
                            rates: [120, 60, 59.94], builtin: true)
        expect(mbp.appleSizes.map(\.label) == ["1024 × 665", "1147 × 745", "1352 × 878", "1512 × 982", "1800 × 1169"],
               "apple sizes: \(mbp.appleSizes.map(\.label))")
        expect(mbp.hasProMotion, "MacBook must have ProMotion")
        expect(mbp.appleLabel(ModeSize(width: 1512, height: 982, hiDPI: true)) == "Default", "label Default")
        expect(mbp.appleLabel(ModeSize(width: 1800, height: 1169, hiDPI: true)) == "More Space", "label More Space")
        expect(mbp.appleLabel(ModeSize(width: 1024, height: 665, hiDPI: true)) == "Larger Text", "label Larger Text")
        let mbpResults = Profile.defaults.map { describe(mbp, $0) }
        expect(mbpResults == ["1512x982@2x 120", "1800x1169@2x 120", "1920x1200@1x 60", "2560x1600@1x 60"], "MacBook: \(mbpResults)")
        expect(describe(mbp, custom) == "2048x1330@1x 59.94", "custom: \(describe(mbp, custom))")
        expect(mbp.refreshLabel(.auto) == "ProMotion" && mbp.refreshLabel(120) == "ProMotion" && mbp.refreshLabel(59.94) == "59.94 Hz",
               "refresh labels")
        expect(mbp.scaling(mode(mbp, 1512, 982, true)) == "Pixel-exact", "scaling 2x")
        expect(mbp.scaling(mode(mbp, 1512, 982, false)) == "Integer ×2", "scaling integer")
        expect(mbp.scaling(mode(mbp, 1920, 1200, false)) == "Upscaled ×1.57", "scaling HD: \(mbp.scaling(mode(mbp, 1920, 1200, false)))")
        expect(mbp.scaling(mode(mbp, 1800, 1169, true)) == "Downsampled ×1.19", "scaling More Space")

        // Active detection: same size and rate.
        let model = AppModel.shared
        let atStandard = mbp.with(current: mode(mbp, 1512, 982, true, 120))
        expect(model.isActive(Profile.defaults[0], on: atStandard), "Default active at 1512x982@120")
        expect(!model.isActive(Profile.defaults[1], on: atStandard), "More Space not active at 1512x982")
        let atHD60 = mbp.with(current: mode(mbp, 1920, 1200, false, 60))
        expect(model.isActive(Profile.defaults[2], on: atHD60), "HD active at 1920x1200@60")
        let atHD120 = mbp.with(current: mode(mbp, 1920, 1200, false, 120))
        expect(!model.isActive(Profile.defaults[2], on: atHD120), "HD not active at 120 Hz")

        // 4K monitor 16:9 without ProMotion: HD/2K land on the most similar 1:1 size, Default follows its default.
        let uhd = synthetic(panel: (3840, 2160), defaultSize: ModeSize(width: 1920, height: 1080, hiDPI: true),
                            hiDPI: [(1280, 720), (1920, 1080), (2560, 1440)],
                            lowRes: [(1280, 720), (1920, 1080), (2560, 1440), (3840, 2160)], rates: [60, 50], builtin: false)
        let uhdResults = Profile.defaults.map { describe(uhd, $0) }
        expect(uhdResults == ["1920x1080@2x 60", "2560x1440@2x 60", "≈1920x1080@1x 60", "≈2560x1440@1x 60"], "4K: \(uhdResults)")
        expect(!uhd.hasProMotion && uhd.refreshLabel(.auto) == "Highest", "4K refresh")

        // Only read real displays.
        let displays = DisplaySystem.online()
        expect(!displays.isEmpty, "no displays found")
        report["displays"] = displays.map { d in
            "\(d.name) \(d.panel.width)x\(d.panel.height) modes=\(d.modes.count) current=\(d.current.map { "\($0.size.detail)@\($0.refresh)" } ?? "-") "
                + Profile.defaults.map { describe(d, $0) }.joined(separator: ", ")
        }
        for d in displays {
            expect(d.current != nil, "\(d.name): current mode unknown")
            expect(d.standardSize != nil && d.moreSpaceSize != nil, "\(d.name): no Apple sizes")
            if d.isBuiltin && d.panel == (3024, 1964) {
                let real = Profile.defaults.map { describe(d, $0) }
                expect(real == mbpResults, "built-in: \(real)")
            }
            let colors = ColorProfile.installed(for: d)
            report["colorProfiles"] = colors.count
            expect(colors.contains { $0.name.contains("sRGB") }, "\(d.name): no sRGB color profile found")
        }

        report["ok"] = failures.isEmpty
        report["failures"] = failures
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
        NSApp.terminate(nil)
    }

    private static func describe(_ d: Display, _ p: Profile) -> String {
        guard let r = d.resolve(p.target, p.refresh) else { return "-" }
        let m = r.mode
        let hz = m.refresh == m.refresh.rounded() ? "\(Int(m.refresh))" : String(format: "%.2f", m.refresh)
        return "\(r.approximate ? "≈" : "")\(m.size.width)x\(m.size.height)@\(m.size.hiDPI ? 2 : 1)x \(hz)"
    }

    private static func mode(_ d: Display, _ w: Int, _ h: Int, _ hiDPI: Bool, _ hz: Double = 60) -> DisplayMode {
        d.modes.first { $0.size == ModeSize(width: w, height: h, hiDPI: hiDPI) && $0.refresh == hz }!
    }

    private static func synthetic(panel: (Int, Int), defaultSize: ModeSize, hiDPI: [(Int, Int)], lowRes: [(Int, Int)],
                                  rates: [Double], builtin: Bool) -> Display {
        var modes: [DisplayMode] = []
        var id: Int32 = 0
        for (sizes, retina) in [(hiDPI, true), (lowRes, false)] {
            for (w, h) in sizes {
                for (i, hz) in rates.enumerated() {
                    let size = ModeSize(width: w, height: h, hiDPI: retina)
                    let px = retina ? (w * 2, h * 2) : (w, h)
                    modes.append(DisplayMode(id: id, size: size, pixelWidth: px.0, pixelHeight: px.1, refresh: hz,
                                             isDefault: size == defaultSize && i == 0, isNative: px == panel))
                    id += 1
                }
            }
        }
        return Display(id: 999, uuid: nil, name: "Test", isBuiltin: builtin, modes: modes, current: nil)
    }
}

extension Display {
    func with(current: DisplayMode) -> Display {
        Display(id: id, uuid: uuid, name: name, isBuiltin: isBuiltin, modes: modes, current: current)
    }
}
