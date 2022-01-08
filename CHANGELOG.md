## [1.0.0] - Initial Release, June 15, 2021

Initial release, after testing on a reasonable sample of SVG images
believed to be representative.

## [1.0.1] - Cosmetic Issues, dart:io, June 15, 2021

- Eliminated dependencies on `dart:io`, so that library will work on JS.
  - This did involve an API change, but the old version was on pub.dev
    for maybe an hour, so I'm not considering this a breaking change.
- Ran dartfmt on bin directory

## [1.0.2] - resolve dependency conflict, June 16, 2021

- Back off version of args to 2.0.0, to eliminate conflict with 
  `flutter_launcher_icons`

## [1.0.3] - update homepage for dart.dev listing, June 16, 2021

## [1.0.4] - Add github links for dart.dev listing, June 16, 2021

## [1.0.5] - June 21, 2021

- Make default stop-color black in gradients (thanks, 
  [Jarle](https://github.com/jarlestabell)).
- Add informative documentation about rendering performance.

## [1.0.6] - June 27, 2021

- Library seems stable, so spinning a release because pub.dev wants
  a trivial dartfmt run, and I suppose this might influence the search
  algorithm.

## [1.0.7] - October 30, 2021

- Add ScalableImageCache (issue 6)
- Require Flutter 2.5 / SDK 2.14 (Issue 9)
- Change imageDisposeBugWorkaround default to clean up memory,
  now that Flutter bug is fixed (Issue 9)
- Address issue 7 (relatively harmless race condition).
- Enable persistent cache by exposing write method for compact images
- Add demo of persistent cache in `demo_hive`

## [1.0.8] - January 2022

- Make AVD parsing more forgiving (Issue 13)
- Use width and height attribute in AVD file for scaling (Issue 14)
- Add `ScalableImage.fromAvdHttpUrl` to API for completeness
