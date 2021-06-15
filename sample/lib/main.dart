import 'package:flutter/material.dart';
import 'package:jovial_svg/jovial_svg.dart';

void main() {
  runApp(MinimalSample());
}

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
