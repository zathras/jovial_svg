import 'package:flutter/material.dart';
import 'package:jovial_svg/jovial_svg.dart';

void main() {
  runApp(const JovialTestApp());
}

const svgStringCircle = '''
<svg version="1.1" width="50" height="50" xmlns="http://www.w3.org/2000/svg">
  <circle cx="25" cy="25" r="20" fill="currentColor" />
</svg>
''';

const svgStringGroup = '''
    <svg version="1.1" width="50" height="50" xmlns="http://www.w3.org/2000/svg">
      <g fill="currentColor" transform="translate(1 1)">
        <circle cx="25" cy="25" r="20" />
      </g>
    </svg>
    ''';

class JovialTestApp extends StatelessWidget {
  const JovialTestApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Stack(children: [
            Row(children: [
              for (final src in [svgStringCircle, svgStringGroup])
                ScalableImageWidget(
                  si: ScalableImage.fromSvgString(src)
                      .modifyCurrentColor(Colors.amber),
                ),
            ]),
          ]),
        ),
      );
}
