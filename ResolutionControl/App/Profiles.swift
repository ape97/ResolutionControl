import Foundation

/// An entry of the user's list: name, resolution, refresh rate, optional color profile, symbol and color.
struct Profile: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var target: Target
    var refresh: Refresh = .auto
    var color: ColorChoice = .keep
    /// Visible in the menu (otherwise only in Settings).
    var shown = true
    /// Symbol and color in the menu. Optional so lists from older versions stay readable (missing = default by target).
    var icon: String?
    var tint: ProfileTint?

    /// Built-in list: Apple's two sizes with ProMotion, plus HD- and 2K-like entries with a fixed rate.
    /// 1920 × 1200 and 2560 × 1600 (16:10) are exactly the area below the camera housing on a MacBook and render 1:1;
    /// on other displays `Display.resolve` picks the most similar available size.
    static let defaults: [Profile] = [
        Profile(name: "Default", target: .standard, icon: "textformat.size", tint: .blue),
        Profile(name: "More Space", target: .moreSpace, icon: "rectangle.3.group", tint: .green),
        Profile(name: "HD", target: .size(ModeSize(width: 1920, height: 1200, hiDPI: false)), refresh: .fixed(60),
                icon: "square.grid.3x3", tint: .orange),
        Profile(name: "2K", target: .size(ModeSize(width: 2560, height: 1600, hiDPI: false)), refresh: .fixed(60),
                icon: "display", tint: .purple),
    ]

    /// Choice in the editor: twelve plain symbols (the first four are the defaults by target).
    static let iconChoices = ["textformat.size", "rectangle.3.group", "sparkles.rectangle.stack", "square.grid.3x3",
                              "display", "tv", "laptopcomputer", "film", "photo", "doc.text", "person.2", "star.fill"]

    var symbol: String {
        if let icon { return icon }
        return switch target {
        case .standard: "textformat.size"
        case .moreSpace: "rectangle.3.group"
        case .size(let s): s.hiDPI ? "sparkles.rectangle.stack" : "square.grid.3x3"
        }
    }

    var badgeTint: ProfileTint {
        if let tint { return tint }
        return switch target {
        case .standard: .blue
        case .moreSpace: .green
        case .size(let s): s.hiDPI ? .teal : .orange
        }
    }
}

/// Color of an entry; the mapping to SwiftUI colors lives in `UI/MenuView.swift`.
enum ProfileTint: String, Codable, CaseIterable {
    case blue, teal, green, yellow, orange, pink, purple, gray
}

/// List in UserDefaults (JSON). If it is missing or unreadable, the built-in list applies.
enum ProfileStore {
    static let key = "profiles"

    static func load(from defaults: UserDefaults = .standard) -> [Profile] {
        defaults.data(forKey: key).map(decode) ?? Profile.defaults
    }

    static func decode(_ data: Data) -> [Profile] {
        guard let list = try? JSONDecoder().decode([Profile].self, from: data) else { return Profile.defaults }
        return list.map(withDefaultLook)
    }

    /// Entries from versions before 1.0.4 have neither color nor icon. If one matches a built-in entry (name and target),
    /// it gets that entry's look – otherwise HD and 2K would look the same (both 1×).
    static func withDefaultLook(_ profile: Profile) -> Profile {
        guard profile.icon == nil, profile.tint == nil,
              let match = Profile.defaults.first(where: { $0.name == profile.name && $0.target == profile.target }) else { return profile }
        var p = profile
        p.icon = match.icon
        p.tint = match.tint
        return p
    }

    static func save(_ list: [Profile], to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(list) { defaults.set(data, forKey: key) }
    }
}
