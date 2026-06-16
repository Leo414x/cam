# LUTs

The three built-in styles use **procedurally generated** 3D LUTs — see
`Processing/LUTFilter.swift` (`makeCube` / `shape`). No `.cube` files are
required to build or run the app.

## Adding a real `.cube` file

1. Drop a `.cube` file (LUT_3D_SIZE 17/33/64) into this folder and make sure it
   is included in the app target (XcodeGen picks up `Resources/` automatically).
2. Load it at runtime:

   ```swift
   if let url = Bundle.main.url(forResource: "MyLook", withExtension: "cube"),
      let lut = LUTFilter.load(cubeURL: url) {
       let graded = lut.apply(to: ciImage)
   }
   ```

3. To make it selectable as a style, add a `LeicaStyle` in `StyleLibrary.swift`.
   You'll want a `.cube`-backed variant of `LUTFilter` — the loader already
   returns a ready `LUTFilter`, so you can store the URL on the style and build
   the filter lazily instead of calling `LUTFilter.procedural(_:)`.

`LUTFilter.load(cubeURL:)` parses the standard Adobe `.cube` text format
(3D only) and returns `nil` on malformed input.
