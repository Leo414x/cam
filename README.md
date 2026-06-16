# LeicaCam

A minimal iOS camera app that produces "Leica-style" photos. It captures with
AVFoundation, applies a real-time color-grading pipeline (procedural 3D LUT +
post-processing) on the GPU, and presents a premium, minimal viewfinder inspired
by Leica M cameras.

- **Target:** iPhone 12+, iOS 17+
- **Stack:** Swift / SwiftUI, AVFoundation, Core Image, Metal / MetalKit, Photos
- **Dependencies:** none (Apple frameworks only)

---

## Build

The project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
so the `.xcodeproj` doesn't need to be committed.

```bash
brew install xcodegen          # if you don't have it
cd LeicaCam
xcodegen generate              # writes LeicaCam.xcodeproj
open LeicaCam.xcodeproj
```

Then in Xcode:

1. Select the **LeicaCam** target → **Signing & Capabilities** → choose your
   team (signing is intentionally left blank in `project.yml`).
2. **The camera only works on a physical device.** On the simulator the app
   launches and the full UI renders, but there is no camera feed.
3. Build & run on an iPhone 12 or newer.

Command-line build check (compiles for the simulator):

```bash
xcodebuild -project LeicaCam.xcodeproj -scheme LeicaCam \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build
```

---

## Architecture

```
Camera (AVFoundation)            Processing (Core Image + Metal)        UI (SwiftUI)
─────────────────────            ───────────────────────────────       ────────────
CameraService ──video frames──▶  ImagePipeline.processPreview ──▶ MetalRenderer ──▶ CameraView
     │                                  (steps 1,2,5,7)                  (MTKView)
     │
     └─shutter──▶ PhotoCaptureProcessor ──▶ ImagePipeline.processCapture ──▶ ReviewView ──▶ Photos
                                                  (all 8 steps)
```

### Camera (`Camera/`)
- **`CameraService`** — owns the `AVCaptureSession` (`.photo` preset, back
  wide-angle). Streams `AVCaptureVideoDataOutput` frames to the pipeline + Metal
  preview, drives `AVCapturePhotoOutput`, and exposes published state (EV, ISO,
  focus, captured image) to SwiftUI. Handles permissions and error states.
- **`PhotoCaptureProcessor`** — one-shot `AVCapturePhotoCaptureDelegate`. Reads
  the captured HEIF/JPEG, runs the full pipeline, returns processed + original
  `UIImage`s.
- **`CameraPreviewView`** — `UIViewRepresentable` hosting the Metal preview;
  wires tap-to-focus and vertical-swipe exposure compensation.

### Processing (`Processing/`)
- **`ImagePipeline`** — orchestrates the chain. Two paths: a light **preview**
  pass (white balance → LUT → split-tone/mono → vignette) and the full
  **capture** pass (all 8 steps).
- **`LUTFilter`** — procedural 3D LUT generator (`CIColorCubeWithColorSpace`),
  one per style, cached. Also parses real `.cube` files (see below).
- **`LeicaFilters`** — the individual Core Image building blocks: warm WB shift,
  micro-contrast (unsharp/clarity), highlight rolloff (tone curve), split
  toning (luminance-masked warm/cool), film grain (highlight-aware), natural
  vignette, weighted-luminance monochrome.
- **`MetalRenderer`** — `MTKView` rendering `CIImage` frames through a
  Metal-backed `CIContext`, aspect-filled into the viewfinder. Draws on demand.

### Styles (`Styles/`)
- **`LeicaStyle`** — value-type preset (LUT kind + post-processing parameters).
- **`StyleLibrary`** — the three built-ins: **Classic**, **Monochrom**,
  **Contemporary**.

### Views (`Views/`)
`CameraView` (viewfinder + shutter), `StylePickerView` (pills), `ControlsOverlay`
(grid + focus reticle), `ReviewView` (save/discard + hold-to-compare), `Theme`.

### Utilities (`Utilities/`)
`HapticsManager` (shutter / save / selection haptics), `WatermarkRenderer`
(optional "28mm ƒ/1.4 Summilux" EXIF-style watermark).

---

## The processing pipeline

| # | Step              | Preview | Capture | Implementation |
|---|-------------------|:-------:|:-------:|----------------|
| 1 | Warm white balance|   ✓     |   ✓     | `CIColorMatrix` channel bias |
| 2 | 3D LUT grading    |   ✓     |   ✓     | procedural `CIColorCubeWithColorSpace` |
| 3 | Micro-contrast    |         |   ✓     | `CIUnsharpMask` (large radius = clarity) |
| 4 | Highlight rolloff |         |   ✓     | `CIToneCurve` film shoulder |
| 5 | Split toning      |   ✓     |   ✓     | luminance-masked warm/cool blend |
| 6 | Film grain        |         |   ✓     | `CIRandomGenerator`, highlight-aware, soft-light |
| 7 | Natural vignette  |   ✓     |   ✓     | `CIVignetteEffect`, subtle |
| 8 | Output            |   ✓     |   ✓     | render via Metal `CIContext` |

Monochrome styles substitute a weighted-luminance B&W conversion (0.30R +
0.59G + 0.11B) with lifted blacks for step 5.

### Built-in styles
- **Classic** — warm, rich midtones; boosted red luminance for skin; olive-shifted
  greens; tamed blues. (Summilux on Portra.)
- **Monochrom** — true B&W, lifted blacks, creamy highlights, subtle cool tint.
- **Contemporary** — cleaner, slightly cooler whites, mild desaturation.

---

## Adding custom LUTs

The built-in looks are generated in code, so no `.cube` files ship with the app.
To use a real one, drop it in `LeicaCam/Resources/LUTs/` (XcodeGen bundles it
automatically) and load it:

```swift
if let url = Bundle.main.url(forResource: "MyLook", withExtension: "cube"),
   let lut = LUTFilter.load(cubeURL: url) {
    let graded = lut.apply(to: ciImage)
}
```

`LUTFilter.load(cubeURL:)` parses the standard Adobe `.cube` 3D format
(`LUT_3D_SIZE` 2–64) and returns `nil` on malformed input. See
`Resources/LUTs/README.md`.

---

## Controls

- **Tap** the viewfinder — focus + metering (yellow reticle, auto-expires 2s).
- **Swipe up/down** on the viewfinder — exposure compensation (−3…+3 EV, ⅓-stop).
- **Style pills** — switch looks; the live preview updates immediately.
- **`#` button** — toggle rule-of-thirds grid.
- **Gear button** — toggle "also save unprocessed original".
- **Shutter** — capture (medium haptic + white flash) → review screen.
- **Review** — press & hold to compare against the original; toggle watermark;
  save (success haptic) or discard.

---

## Known limitations (MVP)

- Camera requires a physical device; the simulator shows UI only.
- Focus-point mapping from view space to device space is a portrait
  approximation (good enough for tap-to-focus, not pixel-exact).
- No shutter **sound** is bundled (haptics only) — drop an audio file into
  `Resources/Sounds/` and play it from `HapticsManager`/a sound manager to add one.
- Single lens (wide angle), portrait orientation only, no manual focus, no RAW/
  ProRAW export, no video, no in-app gallery — all out of scope per the MVP spec.
- The watermark always reports `28mm ƒ/1.4` (wide); wire `WatermarkRenderer.LensKind`
  to the active device if multi-lens support is added.
