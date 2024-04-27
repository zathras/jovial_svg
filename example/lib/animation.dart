import 'dart:async';
import 'dart:math';

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
  <circle id="c" cx="25" cy="25" r="20" fill="green" />
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
  final lookup = ExportedIDLookup();

  @override
  void initState() {
    final lookup = svg.dom.idLookup;
    circle = lookup['c'] as SvgEllipse;
    rect = lookup['r'] as SvgRect;
    ellipse = lookup['e'] as SvgEllipse;
    super.initState();
    timer = Timer.periodic(
        const Duration(milliseconds: 8), (_) => setState(update));
    stopwatch.start();
    update();
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

    // Leave the circle alone

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
    print('Tap down at ${event.localPosition}:  $hits');
  }
}
