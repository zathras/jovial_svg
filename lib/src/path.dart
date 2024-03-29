/*
Copyright (c) 2021-2024, William Foote

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:

  * Redistributions of source code must retain the above copyright notice,
    this list of conditions and the following disclaimer.
  * Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in the
    documentation and/or other materials provided with the distribution.
  * Neither the name of the copyright holder nor the names of its
    contributors may be used to endorse or promote products derived
    from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER(S) AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.
*/

library jovial_svg.path;

import 'dart:ui';
import 'path_noui.dart';
import 'common_noui.dart';
import 'dart:math' show pi;

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
          rotation: rotation * 180 / pi,
          largeArc: largeArc,
          clockwise: clockwise);

  @override
  void addOval(RectT rect) {
    path.addOval(Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height));
  }

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
