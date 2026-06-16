# CLAUDE.md — LeicaCam

Working notes for Claude Code across sessions and machines. Read this first.

## What this is

A minimal iOS camera app that produces "Leica-style" photos: AVFoundation
capture → real-time GPU color-grading pipeline (procedural 3D LUT + film-look
post-processing) → premium minimal SwiftUI viewfinder inspired by Leica M
cameras.

- **Target:** iPhone 12+, iOS 17+ · portrait only
- **Stack:** Swift / SwiftUI, AVFoundation, Core Image, Metal / MetalKit, Photos
- **Dependencies:** none (Apple frameworks only)
- **Project generation:** XcodeGen (`project.yml`) — the `.xcodeproj` is NOT
  committed; it's generated locally.
- **Repo:** https://github.com/Leo414x/cam (public)

See `README.md` for the full architecture write-up and the pipeline table.

## Multi-machine setup (use git, NOT iCloud)

> **Do not develop this in an iCloud Drive / Desktop-synced folder.** iCloud and
> Xcode/DerivedData fight each other (partial syncs, `.icloud` placeholder files,
> corrupted build state, merge surprises). Sync **only** through git. Keep the
> working copy in a plain local path such as `~/dev/cam` — outside
> `~/Desktop`, `~/Documents`, and any iCloud-managed directory.

**First time on a new machine:**

```bash
brew install xcodegen          # one-time
git clone https://github.com/Leo414x/cam.git ~/dev/cam
cd ~/dev/cam
xcodegen generate              # regenerates LeicaCam.xcodeproj from project.yml
open LeicaCam.xcodeproj
```

Then set your signing team in Xcode (target → Signing & Capabilities); signing
is intentionally blank in `project.yml` and is never committed.

**Every session — start by syncing:**

```bash
cd ~/dev/cam
git pull
xcodegen generate              # re-run if project.yml or the file tree changed
```

**End of session — push so the other machine can pick up:**

```bash
git add -A
git commit -m "…"
git push
```

**Rules of thumb for staying in sync:**
- `project.yml` is the source of truth for the project structure, NOT the
  `.xcodeproj` (which is git-ignored). After adding/removing/moving files or
  changing build settings, edit `project.yml` and re-run `xcodegen generate`.
- Never commit `*.xcodeproj`, `DerivedData/`, `build/`, or `xcuserdata/` — see
  `.gitignore`.
- Camera features only run on a physical device. The simulator renders the full
  UI but shows a black viewfinder (no camera feed). Use it for UI work only.
- Verify a build before pushing:
  ```bash
  xcodebuild -project LeicaCam.xcodeproj -scheme LeicaCam \
    -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build
  ```

## Current development status

**Status: MVP complete and building.** Compiles clean (Swift 5 language mode,
Xcode 26 / iOS 17 SDK), launches on simulator without crashing, UI matches the
intended Leica-minimal layout.

Implemented:
- Camera: `AVCaptureSession` (`.photo`, back wide-angle), live preview via
  `AVCaptureVideoDataOutput` → Core Image → Metal, photo capture via
  `AVCapturePhotoOutput` (HEIF w/ JPEG fallback), permissions + error states,
  exposure compensation (−3…+3 EV, ⅓-stop, swipe), tap-to-focus, ISO readout.
- Pipeline: 8-step capture chain + lighter live-preview subset. Procedural 3D
  LUTs for 3 styles; real `.cube` loader present. Filters: warm WB,
  micro-contrast (unsharp/clarity), highlight rolloff, luminance-masked split
  toning, highlight-aware film grain, vignette, weighted-luminance monochrome.
- Styles: Classic / Monochrom / Contemporary.
- UI: viewfinder, style pills, rule-of-thirds grid, focus reticle, shutter
  (haptic + flash), review screen (save/discard, hold-to-compare, watermark
  toggle), Photos saving (add-only), optional "save original" toggle.

Known gaps / next candidates (also in README "Known limitations"):
- No bundled shutter **sound** (haptics only) — hook is ready in
  `Resources/Sounds/` + `HapticsManager`.
- Tap-to-focus view→device point mapping is a portrait approximation.
- Watermark hardcodes `28mm` (single-lens MVP).
- Not yet run/tuned on a physical device — LUT/look values are first-pass and
  meant to be refined against real captures.

## Conventions

- Match the existing comment density and naming; Core Image steps are numbered
  to match the pipeline table in `README.md`.
- Keep zero third-party dependencies.
- `@Published` mutations from AV delegate callbacks are dispatched to the main
  queue (delegates fire on background queues).
