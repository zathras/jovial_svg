import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:jovial_svg/jovial_svg.dart';
import 'package:jovial_svg/dom.dart';

///
/// Demonstration of using the DOM-like API to animate an SVG.  This demo
/// also detects a mouse click in the moving rectangle.
///
void main() {
  runApp(const JovialTestApp());
}

const svgString = '''
<svg width="100" height="100" xmlns="http://www.w3.org/2000/svg">
  <style>
   circle {
     fill: green
   }
  </style>
  <circle id="c" cx="25" cy="25" r="20" />
  <rect id="r"  x="10" y="60" width="75" height="10" fill="yellow" />
  <ellipse id="e" cx="40" cy="50" rx="37" ry="25" fill="red" />
</svg>
''';

class JovialTestApp extends StatelessWidget {
  const JovialTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: Scaffold(body: Animated()));
  }
}

class Animated extends StatefulWidget {
  const Animated({super.key});

  @override
  State<Animated> createState() => _AnimatedState();
}

class _AnimatedState extends State<Animated> {
  final svg = SvgDOMManager.fromString(svgString, exportedIDs: ['r']);
  late ScalableImage si;
  late final Timer timer;
  final stopwatch = Stopwatch();
  late final SvgEllipse circle;
  late final SvgRect rect;
  late final SvgEllipse ellipse;
  late final SvgCustomPath custom;
  late final Style circleStyle;
  final lookup = ExportedIDLookup();
  final starRadii = Float64List(17);
  final twinklePeriod = Float64List(17);

  @override
  void initState() {
    print('Initial DOM:  ${svg.dom}');
    final nodes = svg.dom.idLookup;
    circle = nodes['c'] as SvgEllipse;
    rect = nodes['r'] as SvgRect;
    ellipse = nodes['e'] as SvgEllipse;
    circleStyle = svg.dom.stylesheet['circle']![0];

    custom = SvgCustomPath(Path()); // Empty path; updated in update()
    custom.paint.fillColor = SvgColor.value(Colors.cyan.value);
    custom.paint.fillAlpha = 128;
    custom.paint.fillType = SIFillType.nonZero;
    custom.transform = MutableAffine.translation(60, 30);
    final rand = Random();
    for (int i = 0; i < twinklePeriod.length; i++) {
      twinklePeriod[i] = 0.1 + rand.nextDouble() * 0.6;
    }
    svg.dom.root.children.add(custom);

    super.initState();
    timer = Timer.periodic(
        const Duration(milliseconds: 8), (_) => setState(update));
    stopwatch.start();
    update();
  }

  Path makeStar(List<double> radii) {
    final skip = radii.length ~/ 2;
    int angle = 0;
    final points = List.generate(radii.length, (int i) {
      final r = radii[i];
      angle = (angle + skip) % radii.length;
      final theta = angle * 2 * pi / radii.length;
      return Offset(r * sin(theta), -r * cos(theta));
    });
    final star = Path();
    star.addPolygon(points, true);
    return star;
  }

  @override
  void dispose() {
    super.dispose();
    timer.cancel();
    stopwatch.stop();
  }

  void update() {
    double seconds = stopwatch.elapsedTicks / stopwatch.frequency;

    // Animate the ellipse's alpha
    double theta = 2 * pi * seconds / 5;
    ellipse.paint.fillAlpha = (255.9 * 0.5 * (1 + cos(theta))).floor();

    // Move the rectangle in a circle
    theta = 2 * pi * seconds / 4;
    rect.x = 10 + 10 * sin(theta);
    rect.y = 60 + 10 * cos(theta);

    // Rotate the hue of the rectangle
    theta = 360.0 * seconds / 9;
    final c = HSVColor.fromAHSV(1.0, theta % 360.0, 1.0, 1.0);
    rect.paint.fillColor = SvgColor.value(c.toColor().value);

    // Spin the star
    theta = seconds;
    custom.transform = MutableAffine.translation(60, 30)
      ..multiplyBy(MutableAffine.rotation(theta));
    // Make it twinkle by moving the points in and out
    for (int i = 0; i < starRadii.length; i++) {
      starRadii[i] = 30 + 3 * sin(seconds * 2 * pi / twinklePeriod[i]);
    }
    custom.path = makeStar(starRadii);

    // Change the stylesheet for circles.  Otherwise, Leave the circle alone
    if (seconds % 5 > 4) {
      circleStyle.paint.fillColor = SvgColor.value(0xff0000ff);
    } else {
      circleStyle.paint.fillColor = SvgColor.value(0xff00ff00);
    }

    // "Render" svg to a ScalableImage
    si = svg.build();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onTapDown: _handleTapDown,
        child: ScalableImageWidget(
            si: si,
            scale: double.infinity,
            fit: BoxFit.contain,
            lookup: lookup));
  }

  void _handleTapDown(TapDownDetails event) {
    final Set<String> hits = lookup.hits(event.localPosition);
    // ignore: avoid_print
    print('Tap down at ${event.localPosition}:  $hits');
  }
}
