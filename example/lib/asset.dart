import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jovial_svg/jovial_svg.dart';

///
/// A minimal sample application using `jovial_svg` with an SVG file loaded
/// as an asset. This example shows the recommended way of using the library
/// with fixed assets that are loaded before the UI is created.
///
void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // so we can load assets here
  final tigerSvg =
      await ScalableImage.fromSvgAsset(rootBundle, 'assets/tiger.svg');
  // Note the line in ../pubspec.yaml to include tiger.svg in the app.
  //
  // Note that it's more efficient to convert the SVG file to an SI file,
  // using svg_to_si, and than load that at runtime with
  // `ScalableImage.fromSIAsset(...)`.
  runApp(AssetSample(tigerSvg));
}

class AssetSample extends StatelessWidget {
  final ScalableImage tigerSvg;

  AssetSample(this.tigerSvg, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'SVG Asset Sample', home: ScalableImageWidget(si: tigerSvg));
  }
}
