# Social Export

A macOS app with a Share extension that turns photos into ready-to-post JPEGs for Instagram, Threads
and Facebook in one step.

Select photos in Photos (or image files in Finder), choose Share > Social Export, and the extension
writes one correctly sized sRGB JPEG per platform into `~/Pictures/Socials/<platform>/`. There is no
window to click through. When the run finishes you get one notification saying how many photos were
exported, or which file failed and why.

## Download

Signed and notarized builds, with automatic updates: <https://apps.tonalphoto.com/social-export/>

## Requirements

- macOS 27 or later
- Apple silicon

## First run

1. Open Social Export once and allow notifications.
2. If "Social Export" is missing from the Share menu, enable it in System Settings > General >
   Login Items & Extensions > Sharing. macOS asks for this once per Mac.
3. In Photos, select photos, then Share > Social Export.

## Default export recipes

| Platform  | Size                  | JPEG quality |
|-----------|-----------------------|--------------|
| Instagram | 1080 px wide          | 0.85         |
| Threads   | 1080 px wide          | 0.85         |
| Facebook  | 2048 px longest edge  | 0.85 in 1.0.2, 0.95 from the next release |

For every platform:

- Height (or the shorter edge) scales proportionally, and images are never upscaled. An input smaller
  than the target is re-encoded at its own size.
- Output is converted to sRGB, with the EXIF orientation baked into the pixels.
- Metadata is stripped: no GPS, camera, date, IPTC or XMP. An sRGB ICC profile is embedded.
- The output file keeps the input's base name with a `.jpg` extension. Exporting the same name again
  overwrites the earlier file.

The recipes are editable in the app's window, and "Reset to defaults" restores the table above. Values
you have saved are kept across updates.

## Building from source

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen),
so there is no `.xcodeproj` in the repo.

```sh
brew install xcodegen
xcodegen generate
open SocialExport.xcodeproj
```

`tools/build.sh` does the same generation, then runs a Release `xcodebuild` and re-signs the embedded
Sparkle helpers, leaving the app at `build/Social Export.app`. It signs with a "Developer ID
Application" certificate and the team set in `project.yml`, so to build it under your own account,
change `DEVELOPMENT_TEAM`, the bundle identifiers and the app-group identifiers in `project.yml` to
your own first.

The core logic (sizing, colour conversion, metadata stripping, output paths, settings storage) is a
Swift package, `SocialExportCore`, and its tests run without Xcode signing:

```sh
swift test
```

One performance test is skipped by default; run it with `SOCIAL_EXPORT_PERF=1 swift test`.

## Diagnostics

- Unified log: `log show --predicate 'subsystem == "com.tonalphoto.socialexport"' --last 10m`
- Each run of the extension also appends one line to `~/Pictures/Socials/.social-export.log`.

## Licence

MIT. See [LICENSE](LICENSE).
