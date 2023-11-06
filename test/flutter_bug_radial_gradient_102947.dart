// Code for https://github.com/flutter/flutter/issues/102947

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart' as material;
import 'dart:ui';

void main() async {
  final recorder = PictureRecorder();
  final Canvas c = Canvas(recorder);
  final Paint p = Paint();
  final xform = Float64List.fromList([
    86.80000129342079,
    0.0,
    0.0,
    0.0,
    0.0,
    94.5,
    0.0,
    0.0,
    0.0,
    0.0,
    1.0,
    0.0,
    60.0,
    224.310302734375,
    0.0,
    1.0
  ]);
  p.shader = Gradient.radial(
      const Offset(2.5, 0.33),
      0.8,
      [
        const Color(0xffff0000),
        const Color(0xff00ff00),
        const Color(0xff0000ff),
        const Color(0xffff00ff)
      ],
      [0.0, 0.3, 0.7, 0.9],
      TileMode.mirror,
      xform,
      const Offset(2.55, 0.4));
  final span = material.TextSpan(
      style: material.TextStyle(foreground: p, fontSize: 200),
      text: 'Woodstock!');
  final tp = material.TextPainter(text: span, textDirection: TextDirection.ltr);
  tp.layout();
  tp.paint(c, const Offset(10, 150));

  final Picture pict = recorder.endRecording();
  final Image rendered = await pict.toImage(600, 400);
  final bd = await rendered.toByteData(format: ImageByteFormat.png);
  final bytes = Uint8List.fromList(bd!.buffer.asUint8List());
  File('flutter_bug.png').writeAsBytesSync(bytes);
  print('Wrote ${bytes.length} to flutter_bug.png');
}
