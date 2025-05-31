import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jovial_svg/jovial_svg.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final tigerSvg =
      await ScalableImage.fromSvgAsset(rootBundle, 'assets/tiger.svg');
  runApp(InkSample(tigerSvg));
}

class InkSample extends StatelessWidget {
  final ScalableImage tigerSvg;

  const InkSample(this.tigerSvg, {super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SVG Ink Sample',
      home: Material(
        color: Colors.pink,
        child: InkWell(
          onTap: () {},
          splashColor: Colors.lightBlue.withValues(alpha: 0.4),
          child: Center(
            child: SizedBox.square(
              dimension: 300,
              child: ScalableImageWidget(si: tigerSvg, useInk: true),
            ),
          ),
        ),
      ),
    );
  }
}
