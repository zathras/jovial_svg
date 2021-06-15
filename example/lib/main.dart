import 'package:flutter/material.dart';
import 'package:jovial_svg/jovial_svg.dart';

void main() {
  runApp(MinimalSample());
}

///
/// A minimal sample application using `jovial_svg`.  This example lets
/// [ScalableImageWidget] handle the asynchronous loading, which is resonable
/// for a prototype.
///
class MinimalSample extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'SVG Minimal Sample',
        home: ScalableImageWidget.fromSISource(
            si: ScalableImageSource.fromSvgHttpUrl(
                Uri.parse('https://jovial.com/images/jupiter.svg'))));
  }
}
