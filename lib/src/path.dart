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
/// Library for dealing with SVG paths:  parsing, rendering, and an efficient
/// binary format for externalization.  The binary format is also a reasonably
/// compact, fast way of holding a path in memory for rendering.
library jovial_svg.path;

import 'dart:ui';
import 'path_noui.dart';

///
/// Buidler of a Flutter UI path.  See [PathBuilder] for usage.
///
class UIPathBuilder implements PathBuilder {
  final void Function(UIPathBuilder)? _onEnd;

  UIPathBuilder({void Function(UIPathBuilder)? onEnd}) : _onEnd = onEnd;

  ///
  /// The path that is built, or is being built.
  ///
  final path = Path();

  @override
  void arcToPoint(PointT arcEnd,
          {required RadiusT radius,
          required double rotation,
          required bool largeArc,
          required bool clockwise}) =>
      path.arcToPoint(newOffset(arcEnd),
          radius: newRadius(radius),
          rotation: rotation,
          largeArc: largeArc,
          clockwise: clockwise);

  @override
  void close() => path.close();

  @override
  void cubicTo(PointT c1, PointT c2, PointT p, bool shorthand) {
    path.cubicTo(c1.x, c1.y, c2.x, c2.y, p.x, p.y);
  }

  @override
  void lineTo(PointT p) => path.lineTo(p.x, p.y);

  @override
  void moveTo(PointT p) => path.moveTo(p.x, p.y);

  @override
  void quadraticBezierTo(PointT control, PointT p, bool shorthand) =>
      path.quadraticBezierTo(control.x, control.y, p.x, p.y);

  @override
  void end() {
    final f = _onEnd;
    if (f != null) {
      f(this);
    }
  }

  Offset newOffset(PointT o) => Offset(o.x, o.y);

  Radius newRadius(RadiusT r) => Radius.elliptical(r.x, r.y);
}
