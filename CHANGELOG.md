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

## [1.0.7] - in process

- Address issue 7 (relatively harmless race condition).