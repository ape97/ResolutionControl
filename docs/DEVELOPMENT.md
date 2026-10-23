# Development

Everything you need to change, build, install and release Resolution Control yourself.

## Prerequisites

- macOS 26 or later, Xcode 26 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

The Xcode project is generated from `project.yml` and not checked in. Run `xcodegen generate` and open
`ResolutionControl.xcodeproj` if you want to work in Xcode; the scripts below generate it themselves.

## Project layout

```
project.yml                 XcodeGen project (version in MARKETING_VERSION)
Config/Signing.xcconfig     ad-hoc signing by default, optional Config/Local.xcconfig
ResolutionControl/
  App/                      app entry, AppModel (state, settings), Displays (CoreGraphics/ColorSync), Profiles (list model, storage), Demo, SelfTest, StructureTest
  UI/                       MenuView, SettingsPage, ProfileEditor, DesignKit (shared styles)
  Resources/                Info.plist, asset catalog (app icon)
scripts/                    check, deploy, status, screenshots, release, idle, measure-menu, icon
docs/                       PLATFORM.md (tested macOS/Xcode), images/ (README screenshots)
```

## Scripts

| Script | What it does |
|---|---|
| `./scripts/check.sh` | The gate. Warning-free Release build, invisible snapshots of every page into `build/check/`, self-test, performance test. Ends with `RESULT: GREEN` or `RED`. Changes nothing on the system. |
| `./scripts/deploy.sh` | Runs the check; only if green, installs to `/Applications`, restarts the app and measures idle CPU. |
| `./scripts/status.sh` | Shows the installed version, running state, login item and signature, and compares the system with the last tested one in `docs/PLATFORM.md`. |
| `./scripts/screenshots.sh` | Renders every page with demo data and composes the README images in `docs/images/`: every page in dark mode, the main page in light mode too. Each animation in `scripts/scenes/*.json` (cursor, clicks and captions over the rendered pages, `compose.swift --scene`) becomes `docs/images/<name>.gif`; the app icon is copied to `docs/images/icon.png`. GIFs need `ffmpeg` (`brew install ffmpeg`). |
| `./scripts/release.sh` | Builds the downloadable, ad-hoc signed and stripped `build/release/ResolutionControl-<version>.zip`. |
| `./scripts/idle.sh [seconds]` | Measures the running app's CPU use and memory footprint with the menu closed. |
| `./scripts/measure-menu.sh` | Measures CPU use while the menu is open (start it, then use the menu). |
| `./scripts/icon.sh <sf-symbol> <top-hex> <bottom-hex>` | Generates the app icon in all sizes into the asset catalog (uses `scripts/icon.swift`). |

Typical loop: edit, `./scripts/check.sh`, look at `build/check/*.png`, then `./scripts/deploy.sh` to use it.

## Command-line modes

The app binary (`ResolutionControl.app/Contents/MacOS/ResolutionControl`) understands a few arguments used by the scripts:

- `--snapshot <base> [page]` renders the menu off-screen to `<base>-light.png`, `<base>-dark.png` and `<base>-symbol.png`
  and exits. No window is shown. Pages: none (main menu), `--settings`, `--editor` (editor for the last entry), `--update <version>` (pretends a newer release exists).
- `--demo` (with `--snapshot`) uses invented data (`App/Demo.swift`), so screenshots never show your own displays or list.
- `--profiles <plist>` (with `--snapshot`, without `--demo`) renders an exported defaults file, for example from `defaults export <bundle id> <file>`. The file is read, never written.
- `--selftest <file.json>` runs the logic tests (built-in list, storage, mode matching against the real displays) and writes the result as JSON.
- `--structuretest <file.json>` checks that menu updates stay structurally quiet (otherwise macOS keeps resetting the pointer) and writes the result as JSON.
- `--check-update <file.json>` asks GitHub once for the latest release, exactly like the update check, and writes the
  result as JSON (current and latest version, whether the notice would show). Manual test only, never part of `check.sh`.

## Signing

Builds are ad-hoc signed (`Config/Signing.xcconfig`), so no developer account is needed. macOS ties the login item to
the code signature, so with ad-hoc signing you may have to switch **Open at Login** on again after a rebuild. To sign
with your own certificate, create the git-ignored `Config/Local.xcconfig`:

```
CODE_SIGN_IDENTITY = Apple Development
DEVELOPMENT_TEAM = YOURTEAMID
```

## Releasing

Every published release reaches users who switched on **Check for Updates** within a day, so releases are deliberate:

- Only GitHub releases count: commits, pushes and tags never trigger the notice, and neither do drafts or pre-releases
  (`releases/latest` skips them). Use `gh release create … --prerelease` for a build someone should try first.
- Bundle small changes; documentation, images and scripts alone don't need a release.
- Tag every release `v<version>` with a plain numeric version (`1.10.0` is newer than `1.9.3`).
- Never publish a release just to test the notice: build a zip with a lower version locally and run it with `--check-update`.

1. Raise `MARKETING_VERSION` in `project.yml`.
2. `./scripts/check.sh` must be green; refresh the README images with `./scripts/screenshots.sh` if the UI changed.
3. `./scripts/release.sh` builds the zip. It always signs ad hoc, even with `Local.xcconfig` present, because a personal
   certificate would put the developer's name into the signature, and it strips the binary so no build paths remain.
   The signature's designated requirement is the bundle identifier instead of the ad-hoc default (one exact build), so
   permissions granted in System Settings stay valid after an update.
4. Commit, tag and publish, for example with the GitHub CLI:
   ```sh
   git tag -a v1.2.0 -m "Resolution Control 1.2.0" && git push origin v1.2.0
   gh release create v1.2.0 build/release/ResolutionControl-1.2.0.zip --title "Resolution Control 1.2.0" --notes "…"
   ```

## After a macOS or Xcode update

Run `./scripts/status.sh`. If the system differs from the last `tested:` line in `docs/PLATFORM.md`, run
`./scripts/check.sh`, fix what broke and append a new `tested:` line. `docs/PLATFORM.md` also lists the system
interfaces most likely to change.

## How it works

- Display modes come from `CGDisplayCopyAllDisplayModes` (including the normally hidden 1x modes) and are applied with
  `CGConfigureDisplayWithDisplayMode`, committed with `CGCompleteDisplayConfiguration(…, .permanently)`.
- Display changes arrive through `CGDisplayRegisterReconfigurationCallback`, so the app never polls.
- Color profiles are listed from the ColorSync folders and set with `ColorSyncDeviceSetCustomProfiles`.
- The list is stored as JSON in the app's user defaults; a missing or unreadable list falls back to the built-in entries,
  and older lists stay readable.
- The menu is a SwiftUI `MenuBarExtra` (`.window` style); the app registers itself as a login item with `SMAppService`
  on the first launch from `/Applications`.
- While the menu is open the layout never changes structurally, because every structural change makes macOS reset the mouse pointer (`--structuretest` checks this).
- **Update check** (`App/UpdateCheck.swift`, off by default): at most once a day (on launch, when the menu opens, after
  waking; no timer) a single `GET https://api.github.com/repos/ape97/ResolutionControl/releases/latest`. Only `tag_name` and
  `html_url` are read; a newer version shows a notice in the menu whose **Download** opens the release page. Nothing is
  downloaded or installed by the app.
- Limits: only modes macOS offers for the display; no custom timings, rotation, HDR presets or color depth.

## Contributing

Keep changes small and focused, run `./scripts/check.sh` before opening a pull request, and describe what you tested.
Settings get a short explanation below them (`SettingNote` in `UI/DesignKit.swift`).
