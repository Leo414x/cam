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

**Spec coverage (both source specs fully integrated as of 2026-06-16):**
- The original MVP build prompt — all 16 source files in the prescribed
  structure exist and are implemented.
- `leica-color-params-for-cc.md` — `generateLeicaLUT`, the 8-band `HSLShiftTable`,
  all four spatial param structs (`MicroContrast`/`Grain`/`Vignette`/`Halation`),
  the helper math, the 5 presets, and the documented pipeline order are all in.
There is no outstanding spec work. Remaining items below are intentional
MVP-scope decisions, not unimplemented spec content.

Implemented:
- Camera: `AVCaptureSession` (`.photo`, back wide-angle), live preview via
  `AVCaptureVideoDataOutput` → Core Image → Metal, photo capture via
  `AVCapturePhotoOutput` (HEIF w/ JPEG fallback), permissions + error states,
  exposure compensation (−3…+3 EV, ⅓-stop, swipe), tap-to-focus, ISO readout.
- Pipeline (integrated from `leica-color-params-for-cc.md`):
  - **Color is baked into a procedural 33³ 3D LUT** (`LUTFilter.generateLeicaLUT`):
    camera calibration → 8-band HSL shifts (smooth band crossfade) → global
    saturation compression → split toning → monotone-cubic (Fritsch–Carlson)
    tone curve; monochrome styles use a weighted B&W conversion before the curve.
    Cached per `style.id`. Real `.cube` loader still present.
  - **Spatial filters after the LUT** (`LeicaFilters`): Kelvin white-balance,
    luminance-weighted micro-contrast (clarity), highlight halation (bloom),
    highlight-aware film grain, natural vignette — each with per-style params
    (`MicroContrastParams` / `GrainParams` / `VignetteParams` / `HalationParams`).
  - Order (capture): WB → LUT → micro-contrast → halation → grain → vignette.
    Preview: LUT → micro-contrast → vignette (micro-contrast runs in preview too
    now, for WYSIWYG; halation/grain still capture-only).
  - micro-contrast is **multi-scale** (3 bands: fine/mid/coarse) with radii
    **scaled to the image long edge** (ref 1440 in `LeicaFilters`), so it is
    resolution-independent and preview matches capture. alpha lowered to ~60%
    of the original fitted values to avoid over-sharpening.
- Styles (5 Leica): Classic / Contemporary / Natural / Vivid / Monochrom.
  Defined as `LeicaStyle` presets in `StyleLibrary.swift`; HSL tables there too.
  Color math validated numerically (HSL round-trip, monotone in-range tone curve).
- **Dazz LUT styles (1 so far): KJ · Kuji.** Separate LUT-based path that does
  not touch the Leica styles:
  - `AppStyle` enum (`.leica` / `.dazz`) is the unified selection type used by
    the camera, picker and `ImagePipeline`. `AppStyleLibrary.all` = Leica then
    Dazz; picker draws a divider before the Dazz section.
  - `DazzSingleLUTStyle` (`Styles/DazzStyle.swift`) + `DazzLibrary.all`.
  - `DazzLUTStripLoader` decodes a 256×16 Dazz strip (`x=b·16+r, y=g`) into a
    16³ `CIColorCube` (can trilinearly resample to 33). `DazzLUTFilter` applies
    it with `mix(original, lut, intensity)` and caches cube data by
    `lutResourceName+cubeSize` (parsed once, not per frame). Preview and export
    use the SAME path. LUT: `Resources/LUTs/Dazz/f_villau2z.png`.
  - Only this one style is imported; the other ~128 are intentionally deferred.
  - Decode validated against the asset (monotone neutral ramp, full luma range,
    magenta-leaning mids matching KJ's fitted "magenta+darker" bias).
  - **Asset rights caveat:** these LUTs were extracted from a third-party APK.
    Before commercial distribution, confirm rights or replace with original
    LUTs generated from the fitted parameters in
    `dazz_style_parameters_translated.csv`.
- **Dazz Retro Polaroid pack (8 presets: PO1–PO8).** A full multi-layer effect
  pack (not just a LUT), separate from the Kuji strip path:
  - `AppStyle.dazzRetro(DazzRetroPolaroidPreset)`; presets in
    `Styles/DazzRetroPolaroid.swift` (`DazzRetroLibrary.all`), built from
    `polaroid_full_manifest.json` defaults. Models: `DazzRetroPolaroidPreset`
    (id/code/name/lut + `style` + `textures`), `DazzRetroStyleAdjustments`,
    `DazzRetroTextureSettings`.
  - **`DazzRetro512LookupLoader`** decodes a **512×512** 8×8-tile GPUImage atlas
    (`blue→tile, red→x, green→y`) into a `CIColorCube` (size 33, trilinear) — a
    SEPARATE loader from the 256×16 `DazzLUTStripLoader`. `DazzRetroLUTFilter`
    caches cube data by `resourceName+cubeSize`.
  - **`DazzRetroProcessor`** runs the full chain: LUT → style (exposure, WB
    temp/tint, brightness/contrast/saturation, shadows/highlights, sharpen) →
    textures (dust=colorDodge, light leak=lighten, procedural vignette, grain).
    `applyStyle`/`applyTextures` flags allow LUT-only A/B. Texture CIImages
    cached. Frame/mask is modeled but **deferred** (no frame compositing path).
  - Same `process()` call for preview and export (parity). Pipeline routes
    `.dazzRetro` in `ImagePipeline` for both paths.
  - UI: PO1–PO8 pills in a third picker section (divider by `AppStyle.groupKey`);
    `DazzRetroEditPanel` (sliders: LUT intensity, brightness, contrast,
    saturation, sharpen, temp, tint, vignette, grain, dust, light leak; edits
    mutate the selected preset live) opened by the slider button; and
    `DazzRetroDemoView` (8 presets applied to a bundled sample, full-vs-LUT-only
    toggle) opened by the grid button — both in the readout bar.
  - Param ranges follow `style_parameter_defaults_v3_2_2.csv` (note: wb tint
    baseline is **1**, not 0). Bundled: 8 LUTs (`Resources/LUTs/Dazz/Polaroid`),
    dust_1–8 + leak_1–8 (`Resources/Textures/...`), `sample_polaroid_origin.jpg`.
  - Verified headlessly (Core Image on macOS) against the real assets: 8 LUTs
    decode non-blank and differ; full pipeline yields 8 visibly distinct
    polaroid renders. Same third-party-APK asset-rights caveat applies.
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
