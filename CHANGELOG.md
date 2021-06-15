## [1.0.0] - Initial Release, June 15, 2021

Initial release, after testing on a reasonable sample of SVG images
believed to be representative.

## [1.0.1] - Cosmetic Issues, dart:io, June 15, 2021

- Eliminated dependencies on `dart:io`, so that library will work on JS.
  - This did involve an API change, but the old version was on pub.dev
    for maybe an hour, so I'm not considering this a breaking change.
- Ran dartfmt on bin directory
