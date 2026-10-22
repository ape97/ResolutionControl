import SwiftUI

/// Third page: create or change an entry – name, resolution (Apple's sizes and all other modes of the
/// display), refresh rate, optionally a color profile, plus color and symbol for the menu.
struct ProfileEditor: View {
    @Environment(AppModel.self) private var model
    let original: Profile?
    let done: () -> Void
    @State private var draft: Profile
    @State private var colorProfiles: [ColorProfile] = []

    init(original: Profile?, done: @escaping () -> Void) {
        self.original = original
        self.done = done
        let size = AppModel.shared.display?.current?.size
        _draft = State(initialValue: original ?? Profile(name: "", target: size.map(Target.size) ?? .standard))
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                RoundIconButton(symbol: "chevron.left", size: 24, help: "Back", action: done)
                Text(original == nil ? "New Resolution" : "Edit Resolution").font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 2)

            if let display = model.display {
                Module(spacing: 10) {
                    field("Name", symbol: "character.cursor.ibeam", tint: .gray) {
                        TextField("Name", text: $draft.name, prompt: Text("e.g. Presentation"))
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                    }
                    field("Resolution", symbol: "rectangle.dashed", tint: .accentColor) {
                        Picker("Resolution", selection: $draft.target) { resolutionItems(display) }
                            .help("The screen resolution this profile switches to")
                    }
                    field("Refresh Rate", symbol: "waveform.path", tint: .orange) {
                        Picker("Refresh Rate", selection: $draft.refresh) { refreshItems(display) }
                            .help("How many times per second the screen redraws; higher looks smoother")
                    }
                    field("Color Profile", symbol: "paintpalette.fill", tint: .pink) {
                        Picker("Color Profile", selection: $draft.color) {
                            Text("Don't Change").tag(ColorChoice.keep)
                            Text("Display Default").tag(ColorChoice.factory)
                            if case .file(let path) = draft.color, !colorProfiles.contains(where: { $0.path == path }) {
                                Text((path as NSString).lastPathComponent).tag(draft.color)
                            }
                            if !colorProfiles.isEmpty {
                                Divider()
                                ForEach(colorProfiles) { Text($0.name).tag(ColorChoice.file($0.path)) }
                            }
                        }
                        .help("Adjust the screen's colors when switching; Don't Change keeps the current ones")
                    }
                }
                .onChange(of: draft.target) { fitRefresh(display) }

                Module(spacing: 10) {
                    field("Color", symbol: "circle.fill", tint: draft.badgeTint.color) { tintChoices }
                    field("Icon", symbol: draft.symbol, tint: draft.badgeTint.color) { iconChoices }
                }

                SettingNote(explanation(display))
                    .padding(.horizontal, 4)
                    .onAppear { colorProfiles = ColorProfile.installed(for: display) }
            }

            HStack {
                Spacer()
                Button("Cancel", action: done).controlSize(.small)
                    .help("Close without saving")
                Button("Save") {
                    var p = draft
                    p.name = p.name.trimmingCharacters(in: .whitespaces)
                    model.save(p)
                    done()
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                .help(draft.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Enter a name to save this profile" : "Save this profile")
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 2)
        }
    }

    private func field<C: View>(_ title: String, symbol: String, tint: Color, @ViewBuilder control: () -> C) -> some View {
        HStack {
            SettingLabel(symbol: symbol, title: title, tint: tint)
            Spacer(minLength: 12)
            control()
                .labelsHidden()
                .pickerStyle(.menu)
                .buttonSizing(.flexible)
                .frame(width: 200)
        }
    }

    // MARK: Color and symbol

    private var tintChoices: some View {
        HStack(spacing: 5) {
            ForEach(ProfileTint.allCases, id: \.self) { t in
                Button { draft.tint = t } label: {
                    Circle()
                        .fill(t.color.gradient)
                        .frame(width: 17, height: 17)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2).padding(1).opacity(draft.badgeTint == t ? 1 : 0))
                        .overlay(Circle().strokeBorder(t.color, lineWidth: 1.5).padding(-2).opacity(draft.badgeTint == t ? 1 : 0))
                        .frame(width: 20, height: 21)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(t.rawValue.capitalized)
            }
        }
    }

    private var iconChoices: some View {
        Grid(horizontalSpacing: 6.8, verticalSpacing: 6) {
            ForEach(0..<2, id: \.self) { row in
                GridRow {
                    ForEach(Profile.iconChoices[(row * 6)..<(row * 6 + 6)], id: \.self) { symbol in
                        let selected = draft.symbol == symbol
                        Button { draft.icon = symbol } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.75))
                                .frame(width: 27, height: 27)
                                .background(selected ? AnyShapeStyle(draft.badgeTint.color.gradient) : AnyShapeStyle(.primary.opacity(0.07)),
                                            in: Circle())
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Use this icon for the profile")
                    }
                }
            }
        }
    }

    // MARK: Pickers

    @ViewBuilder
    private func resolutionItems(_ d: Display) -> some View {
        let apple = d.appleSizes
        Section("Follows macOS") {
            Text("Default (\(d.standardSize?.label ?? "–"))").tag(Target.standard)
            Text("More Space (\(d.moreSpaceSize?.label ?? "–"))").tag(Target.moreSpace)
        }
        Section("macOS Sizes") {
            ForEach(apple.reversed(), id: \.self) { s in
                Text(d.appleLabel(s).map { "\(s.label) – \($0)" } ?? s.label).tag(Target.size(s))
            }
        }
        Section("Retina (2×)") {
            ForEach(d.sizes.filter { $0.hiDPI && !apple.contains($0) }.reversed(), id: \.self) { s in
                Text(s.detail).tag(Target.size(s))
            }
        }
        Section("Pixels 1:1 (1×)") {
            ForEach(d.sizes.filter { !$0.hiDPI && !apple.contains($0) }.reversed(), id: \.self) { s in
                Text(s.detail).tag(Target.size(s))
            }
        }
        // A saved size this display doesn't know stays selectable.
        if case .size(let s) = draft.target, !d.sizes.contains(s) {
            Section("Other Display") { Text("\(s.detail)").tag(draft.target) }
        }
    }

    @ViewBuilder
    private func refreshItems(_ d: Display) -> some View {
        Text(d.hasProMotion ? "\(maxRate(d)) Hz – ProMotion (variable)" : "Highest (\(maxRate(d)) Hz)").tag(Refresh.auto)
        ForEach(fixedRates(d), id: \.self) { hz in
            Text(d.refreshLabel(hz)).tag(Refresh.fixed(hz))
        }
    }

    private func maxRate(_ d: Display) -> Int {
        Int((d.resolve(draft.target, .auto)?.mode.refresh ?? 0).rounded())
    }

    /// Fixed rates of the chosen size; the highest corresponds to "auto" (ProMotion on a MacBook) and is therefore omitted.
    private func fixedRates(_ d: Display) -> [Double] {
        guard let size = d.resolve(draft.target, .auto)?.mode.size else { return [] }
        return Array(d.refreshRates(for: size).dropFirst())
    }

    /// After a size change, move a fixed rate that no longer exists to the nearest one.
    private func fitRefresh(_ d: Display) {
        guard case .fixed(let hz) = draft.refresh else { return }
        let rates = fixedRates(d)
        guard !rates.contains(hz) else { return }
        draft.refresh = rates.min { abs($0 - hz) < abs($1 - hz) }.map(Refresh.fixed) ?? .auto
    }

    private func explanation(_ d: Display) -> String {
        guard let r = d.resolve(draft.target, draft.refresh) else { return "Not available on \(d.name)." }
        let m = r.mode
        var parts = ["Looks like \(m.size.label), rendered at \(m.pixelWidth) × \(m.pixelHeight) pixels (\(d.scaling(m).lowercased()))."]
        if r.approximate { parts.insert("Not available on \(d.name) – nearest match.", at: 0) }
        if d.hasProMotion {
            // On the built-in display macOS offers the highest rate only as variable, never fixed.
            parts.append(m.refresh > 100
                ? "ProMotion on (variable up to \(Int(m.refresh.rounded())) Hz)."
                : "ProMotion off (fixed \(d.refreshLabel(m.refresh))). macOS offers \(maxRate(d)) Hz on this display only as ProMotion.")
        }
        return parts.joined(separator: " ")
    }
}
