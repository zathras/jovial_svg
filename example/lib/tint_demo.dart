import 'package:flutter/material.dart';
import 'package:jovial_svg/jovial_svg.dart';

void main() {
  runApp(const JovialTestApp());
}

const svgString = '''
<svg version="1.1" width="50" height="50" xmlns="http://www.w3.org/2000/svg">
  <circle cx="25" cy="25" r="20" fill="green" />
</svg>
''';

class JovialTestApp extends StatelessWidget {
  const JovialTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    final image = ScalableImage.fromSvgString(svgString);
    return MaterialApp(
      home: Scaffold(
        body: Stack(children: [
            Container(color: Colors.yellowAccent),
            Row(children: [
              ScalableImageWidget(si: image),
              ScalableImageWidget(
                  si: image.modifyTint(
                      newTintMode: BlendMode.srcIn, newTintColor: Colors.red)),
            ]),
        ]),
      ),
    );
  }
}

