## [1.1.27] - June 2025
- Work around platform not calling Canvas.save/restore with BoxPainter  (Issue 134)

## [1.1.26] - June 2025
- Implement painting to `Ink` in `ScalableImageWidget` (Issue 124)
- Fix bug in prepare/unprepare logic when widget's state object reused

## [1.1.25] - February 2025
- Avoid the newly deprecated `Color.value`

## [1.1.24] - November 2024
- Fix `exportedIDs` with widget image sources (Issue 118)
- Optimization:  Strip warnF from ScalableImageCache key (Issue 119)
- Remove transitive dependency on pointycastle library

## [1.1.23] - October 2024

- Get rid of buggy dartdoc @category annotations.
- Fix ID lookup with SvgDOM (Issue 113)
- DOM:  Export ValueColor, SvgFontSizeAbsolute (Issue 115)
- Set a color gradient's `stop` attributes from a stylesheet (Issue 117).
- Add a nicer toString() to SvgDOM for debugging/exploration.
- Made node `paint` slight more efficient; added `resetPaint()` method.
- Partial support for SVG text `dominant-baseline` attribute

## [1.1.22] - August 2024

- Fix widget's cache to work when `warnF` is specified (Issue 103)

## [1.1.21] - May 2024

- Add a DOM API for animating/modifying SVG assets (Issues 19, 95)
- Add the ability to see what part of an SVG is
  clicked on -- see `ExportedIDLookup` (Issue 92)
- Allow a list of fonts for SVG text (Issue 91)
- Allow node ID selection from `style` (Issue 93)
- Add a `ScalableImageWidget` method to read from a file (Issue 88)
- Fix attribute handling when masked node is used more than once (Issue 94)

## [1.1.20] - December 2023

- Remove unneeded url_launcher dependency (Issue 87)

## [1.1.19] - November 2023

- Fix bug with stroke-dashoffset (issue 76)

## [1.1.18] - September 2023

- Add switcher to widget for cross-fade effect (issue 70)
- Fix currentColor with transformations (issue 71)

## [1.1.17] - August 2023

- Fix tint rendering (Issue 68)

## [1.1.16] - June 2023

- Fix bug with AVD scaling (Issue 66)
- Add robustness to possible (unverified) Flutter bug(s) in 
  image-related `dispose()` (Issue 62) 

## [1.1.15] - May 2023

- Bump version number of http dependency (issue 59)

## [1.1.14] - April 2023

- Implement `use` tag scaling a `symbol` (issue 54)
- Allow specification of HTTP GET headers

## [1.1.13] - April 2023

- Fix degree/radian confusion in path's arc (issue 51)
- Make the slightly more elegant `ScalableImageCache.addReferenceV2()`

## [1.1.12] - February 2023

- Made `ScalableImageWidget` from an `SISource` more robustly avoid flashing when SI is in cache.
- Added `ifAvailableSync` parameter to `ScalableImageCache.addReference`

## [1.1.11] - February 2023

- Require Dart SDK 2.19 (issue 42)

## [1.1.10] - January 2023

- Add `ScalableImageWidget.isComplex`
- Fix bug in ScalableImageWidget resulting in excessive repaint (issue 37)
- Expose scale/align logic via `ScalingTransform`
- Allow percentage units
- Add `currentColor` parameter to `ScalableImageWidget`

## [1.1.9] - January 2023

- Add missing support for opacity attribute in style tags
- Add support for rgba colors
- Add support for CDATA
- Add support for comments in stylesheets

## [1.1.8] - December 2022

- Add `em` units, and consistently allow units in SVG files
- Suppress warnings about "data-*" attributes in SVG files

## [1.1.7] - December 2022

- For http loading, default to UTF8, allow encoding to be specified.
- Added `example/asset.dart` to show common case of SVG in an asset

## [1.1.6] - September 2022

- Update for Flutter 3.3 release (change in lints)

## [1.1.5] - May 2022

- Update dependencies for Flutter 3.0 release

## [1.1.4] - April 2022

- Support `data:` URLs for SVG and AVD files
- Support loading AVD via http in widget
- Fixed bug with `rgb(x%, x%, x%)` syntax for colors
- Finished adding tests driven by code coverage analysis
- `ScalableImage.toSIBytes()`:  Always write latest file format version
- Handle comma-separated class IDs in stylesheets

## [1.1.3] - April 2022

- implemented `tspan` tag
- implemented `style` tag for inline CSS styles
- Fix `opacity` attribute handling (use `srcOver`)
- Support `mix-blend-mode` attribute
- Implement `clip-rule` attribute
- Implement `text-decoration` attribute
- Made viewBox scaling preserve aspect ratio
- Improved runtime memory efficiency with .si images:  Path sharing
- Ignore XML namespaces (treat "foo:name" like "name").
- Fix skew transform (degrees, not radians).
- Extend API with a function to call when there is a parser warning.
- More robust handling of SVG files with errors

## [1.1.2] - March 2022

- Version number skipped (typo in `pubspec.yaml`).

## [1.1.1] - March 2022

- Added full set of CSS named colors
- Fail more gracefully when `use` and `mask` elements have circular references
- Minor cleanup:  Declare ScalableImage as `@immutable`
- More forgiving `use` tag:  allow "`href`" instead of "`xlink:href`"
- Fix `rrect` arcs when `rx != ry`
- Fix SVG `viewbox` when width/height not set
- Add `symbol` tag
- Implement `clipPath`
- Accept % for gradient stops, and `fx`/`fy` for radial gradients


## [1.1.0] - March 2022

- Implemented masks (SVG 1.1 `mask` element and `mask` attribute)
- Implemented `text-anchor` attribute
- Fixed text outline


## [1.0.8] - January 2022

- Make AVD parsing more forgiving (Issue 13)
- Use width and height attribute in AVD file for scaling (Issue 14)
- Add `ScalableImage.fromAvdHttpUrl` to API for completeness
- Add tiger image to demo


## [1.0.7] - October 30, 2021

- Add ScalableImageCache (issue 6)
- Require Flutter 2.5 / SDK 2.14 (Issue 9)
- Change imageDisposeBugWorkaround default to clean up memory,
  now that Flutter bug is fixed (Issue 9)
- Address issue 7 (relatively harmless race condition).
- Enable persistent cache by exposing write method for compact images
- Add demo of persistent cache in `demo_hive`

## [1.0.6] - June 27, 2021

- Library seems stable, so spinning a release because pub.dev wants
  a trivial dartfmt run, and I suppose this might influence the search
  algorithm.

## [1.0.5] - June 21, 2021

- Make default stop-color black in gradients (thanks, 
  [Jarle](https://github.com/jarlestabell)).
- Add informative documentation about rendering performance.

## [1.0.4] - June 16, 2021

- Add github links for dart.dev listing

## [1.0.3] - June 16, 2021

- update homepage for dart.dev listing

## [1.0.2] - June 16, 2021

- Back off version of args to 2.0.0, to eliminate conflict with 
  `flutter_launcher_icons`

## [1.0.1] - June 15, 2021

- Eliminated dependencies on `dart:io`, so that library will work on JS.
  - This did involve an API change, but the old version was on pub.dev
    for maybe an hour, so I'm not considering this a breaking change.
- Ran dartfmt on bin directory

## [1.0.0] - June 15, 2021

Initial release, after testing on a reasonable sample of SVG images
believed to be representative.

