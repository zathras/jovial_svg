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
  """);
  runApp(MinimalSample(si));
}

///
/// A minimal application demonstrating SVG's currentColor feature.
///
class MinimalSample extends StatefulWidget {

  final ScalableImage initial;

  const MinimalSample(this.initial, {Key? key}) :
        super(key: key);

  @override
  State<MinimalSample> createState() => _MinimalSampleState();
}

class _MinimalSampleState extends State<MinimalSample> {
  Color currentColor = Colors.green;
  late ScalableImage current;
  final rand = Random();

  @override
  initState() {
    super.initState();
    current = widget.initial.modifyCurrentColor(currentColor);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'SVG currentColor Sample',
        home: Column(children: [
            ScalableImageWidget(si: current),
          ElevatedButton(
            onPressed: () {
              setState(() {
                currentColor = Color(rand.nextInt(0xffffff) | 0xff000000);
                current = widget.initial.modifyCurrentColor(currentColor);
              });
            },
            child: const Text('Change currentColor')
          ),
        ]));
  }
}
