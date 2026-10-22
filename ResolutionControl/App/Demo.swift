import Foundation

/// Invented, fixed displays for promotional images (`--snapshot … --demo`): nothing here is read from the system.
enum Demo {
    /// Rates offered per size (the 120 Hz one is ProMotion on the built-in display).
    private static func modes(_ sizes: [(w: Int, h: Int, hiDPI: Bool)], rates: [Double], defaultSize: (Int, Int), nativeWidth: Int) -> [DisplayMode] {
        var id: Int32 = 0
        return sizes.flatMap { s in
            rates.map { hz -> DisplayMode in
                id += 1
                let scale = s.hiDPI ? 2 : 1
                return DisplayMode(id: id, size: ModeSize(width: s.w, height: s.h, hiDPI: s.hiDPI),
                                   pixelWidth: s.w * scale, pixelHeight: s.h * scale, refresh: hz,
                                   isDefault: s.hiDPI && (s.w, s.h) == defaultSize,
                                   isNative: s.hiDPI && s.w * 2 == nativeWidth)
            }
        }
    }

    static var displays: [Display] {
        let builtin = modes([(1147, 745, true), (1352, 878, true), (1512, 982, true), (1800, 1169, true),
                             (1920, 1200, false), (2560, 1600, false)],
                            rates: [120, 60, 59.94, 50, 48, 47.95], defaultSize: (1512, 982), nativeWidth: 3024)
        let studio = modes([(1920, 1080, true), (2048, 1152, true), (2304, 1296, true), (2560, 1440, true),
                            (2880, 1620, true), (1920, 1080, false), (2560, 1440, false)],
                           rates: [60], defaultSize: (2560, 1440), nativeWidth: 5120)
        func current(_ list: [DisplayMode], _ w: Int, _ hz: Double) -> DisplayMode? {
            list.first { $0.size.width == w && $0.size.hiDPI && $0.refresh == hz }
        }
        return [Display(id: 1, uuid: nil, name: "Built-in Retina Display", isBuiltin: true, modes: builtin,
                        current: current(builtin, 1512, 120)),
                Display(id: 2, uuid: nil, name: "Studio Display", isBuiltin: false, modes: studio,
                        current: current(studio, 2560, 60))]
    }

    static let colorProfiles = ["Display P3", "Generic RGB Profile", "sRGB IEEE61966-2.1"]
}
