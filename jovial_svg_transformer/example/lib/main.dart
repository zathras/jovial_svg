import 'package:flutter/material.dart';
import 'package:jovial_svg/jovial_svg.dart';

void main() {
  runApp(const MinimalSample());
}

///
/// A minimal sample application using `jovial_svg_transformer` during the
/// build to convert an SVG into an SI binary file.  Note that the SI file
/// retains the ".svg" extension - that's an artifact of the way Google does
/// transformers.
///
/// The more interesting part of this example is the pubspec.yaml.
///
///
class MinimalSample extends StatelessWidget {
  const MinimalSample({super.key});

  @override
  Widget build(BuildContext context) {
    final ab = DefaultAssetBundle.of(context);
    return MaterialApp(
        title: 'SVG Minimal Sample',
        home: ScalableImageWidget.fromSISource(
            si: ScalableImageSource.fromSI(ab, 'assets/tiger.svg')));
  }
}
