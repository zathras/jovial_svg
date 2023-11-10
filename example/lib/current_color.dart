import 'dart:math';

import 'package:flutter/material.dart';
import 'package:jovial_svg/jovial_svg.dart';

void main() {
  final ScalableImage si = ScalableImage.fromSvgString("""
    <svg width="410px" height="210px" xmlns="http://www.w3.org/2000/svg">
    <rect width="400" height="200" x="5" y="5" fill="aqua" stroke-width="4"
        stroke="#ff0000"/>
    <circle cx="205" cy="105" r="45" fill="currentColor" />
    </svg>
  """, currentColor: Colors.amber);
  runApp(MinimalSample(si));
}

///
/// A minimal application demonstrating SVG's currentColor feature.
///
class MinimalSample extends StatelessWidget {
  final ScalableImage si;

  const MinimalSample(this.si, {super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'SVG scale/translate sample', home: Scaffold(body: Body(si)));
  }
}

class Body extends StatefulWidget {
  final ScalableImage initial;

  const Body(this.initial, {super.key});

  @override
  State<Body> createState() => _BodyState();
}

class _BodyState extends State<Body> {
  ScalableImage current = ScalableImage.blank();
  final rand = Random();

  _BodyState();

  @override
  initState() {
    super.initState();
    current = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      ScalableImageWidget(si: current),
      ElevatedButton(
          onPressed: () {
            setState(() {
              final currentColor = Color(rand.nextInt(0xffffff) | 0xff000000);
              current = current.modifyCurrentColor(currentColor);
            });
          },
          child: const Text('Change currentColor')),
    ]);
  }
}
