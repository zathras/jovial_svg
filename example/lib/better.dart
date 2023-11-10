import 'package:flutter/material.dart';
import 'package:jovial_svg/jovial_svg.dart';

void main() async {
  final si = await ScalableImage.fromSvgHttpUrl(
      Uri.parse('https://jovial.com/images/jupiter.svg'));
  runApp(AssetsPreLoaded(si));
}

///
/// A sample application using `jovial_svg`.  This example shows how to do
/// the asynchronous part before the widget tree is built, so as to avoid
/// changes on the screen.
///
class AssetsPreLoaded extends StatelessWidget {
  final ScalableImage icon;

  const AssetsPreLoaded(this.icon, {super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'SVG Minimal Sample', home: ScalableImageWidget(si: icon));
  }
}
