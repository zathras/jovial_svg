/*
MIT License

Copyright (c) 2021 William Foote

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
 */

/// Binding of the `path` library to the Flutter UI package.
library path.ui;

import 'dart:ui';

import 'path.dart';

import 'dart:ui' as ui;


///
/// Buidler of a Flutter UI path.  See [PathBuilder] for usage.
///
class UIPathBuilder implements PathBuilder<Offset, Radius> {

  ///
  /// The path that is built, or is being built.
  ///
  final path = ui.Path();

  @override
  Offset newOffset(double x, double y) => Offset(x, y);

  @override
  Radius newRadius(double x, double y) => Radius.elliptical(x, y);

  @override
  void arcToPoint(Offset arcEnd,
          {required Radius radius,
          required double rotation,
          required bool largeArc,
          required bool clockwise}) =>
      path.arcToPoint(arcEnd,
          radius: radius,
          rotation: rotation,
          largeArc: largeArc,
          clockwise: clockwise);

  @override
  void close() => path.close();

  @override
  void cubicTo(Offset c1, Offset c2, Offset p) =>
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p.dx, p.dy);

  @override
  void lineTo(Offset p) => path.lineTo(p.dx, p.dy);

  @override
  void moveTo(Offset p) => path.moveTo(p.dx, p.dy);

  @override
  void quadraticBezierTo(Offset control, Offset p) =>
      path.quadraticBezierTo(control.dx, control.dy, p.dx, p.dy);

  @override
  Offset addOffsets(Offset a, Offset b) => a + b;

  @override
  Offset subtractOffsets(Offset a, Offset b) => a - b;

  @override
  double getX(Offset p) => p.dx;

  @override
  double getY(Offset p) => p.dy;
}
