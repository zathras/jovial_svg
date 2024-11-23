# An asset transformer for jovial_svg

This package is an asset transformer for 
[`jovial_svg`](https://pub.dev/packages/jovial_svg).  It transforms
an SVG or Android Vector Drawable asset into a more efficient binary
format that can be read by the `jovial_svg` library.

Here is the full set of supported arguments:
```
dart run jovial_svg_transformer [options] --input <name> --output <name>
    -h, --[no-]help     show help message
    -b, --[no-]big      Use 64 bit double-precision floats, instead of 32.
    -q, --[no-]quiet    Quiet:  Suppress warnings.
    -x, --exportx       Export:  Export the SVG node IDs matched by the
                        given regular expression.  Multiple values may be
                        specified.
```

Using floats instead of doubles is likely a bit faster, and makes
the files images smaller in memory at runtime.  For most files,
floats offer more than enough precision.

Here's a sample pubspec to show how to use this in a project:
```
name: example
description: "Example of using an asset transformer"
publish_to: 'none'

version: 1.0.0+1

environment:
  sdk: '>=3.4.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  jovial_svg: ^1.1.24

dev_dependencies:
  flutter_test:
    sdk: flutter
  jovial_svg_transformer: ^1.0.2
  flutter_lints: ^3.0.0

flutter:
  uses-material-design: true

  assets:
    - path: assets/tiger.svg
      transformers:
        - package: jovial_svg_transformer
```
