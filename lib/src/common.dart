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

///
/// Utilities that are common between DAG and Compact
/// scalable image implementations.
///
library jovial_svg.common;

import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:quiver/core.dart' as quiver;

import 'affine.dart';
import 'common_noui.dart';

abstract class SIRenderable {
  void paint(Canvas c, Color currentColor);

  SIRenderable? prunedBy(PruningBoundary b, Set<SIRenderable> dagger);

  PruningBoundary? getBoundary();
}

extension SIStrokeJoinMapping on SIStrokeJoin {
  static SIStrokeJoin fromStrokeJoin(StrokeJoin j) {
    switch (j) {
      case StrokeJoin.miter:
        return SIStrokeJoin.miter;
      case StrokeJoin.round:
        return SIStrokeJoin.round;
      case StrokeJoin.bevel:
        return SIStrokeJoin.bevel;
    }
  }

  StrokeJoin get asStrokeJoin {
    switch (this) {
      case SIStrokeJoin.miter:
        return StrokeJoin.miter;
      case SIStrokeJoin.round:
        return StrokeJoin.round;
      case SIStrokeJoin.bevel:
        return StrokeJoin.bevel;
    }
  }
}

extension SIStrokeCapMapping on SIStrokeCap {
  static SIStrokeCap fromStrokeCap(StrokeCap strokeCap) {
    switch (strokeCap) {
      case StrokeCap.butt:
        return SIStrokeCap.butt;
      case StrokeCap.round:
        return SIStrokeCap.round;
      case StrokeCap.square:
        return SIStrokeCap.square;
    }
  }

  StrokeCap get asStrokeCap {
    switch (this) {
      case SIStrokeCap.butt:
        return StrokeCap.butt;
      case SIStrokeCap.round:
        return StrokeCap.round;
      case SIStrokeCap.square:
        return StrokeCap.square;
    }
  }
}

extension SIFillTypeMapping on SIFillType {
  static SIFillType fromFillType(PathFillType t) {
    switch (t) {
      case PathFillType.evenOdd:
        return SIFillType.evenOdd;
      case PathFillType.nonZero:
        return SIFillType.nonZero;
    }
  }

  PathFillType get asPathFillType {
    switch (this) {
      case SIFillType.evenOdd:
        return PathFillType.evenOdd;
      case SIFillType.nonZero:
        return PathFillType.nonZero;
    }
  }
}

extension SITintModeMapping on SITintMode {
  static const SITintMode defaultValue = SITintMode.srcIn;

  static SITintMode fromBlendMode(BlendMode m) {
    switch (m) {
      case BlendMode.srcOver:
        return SITintMode.srcOver;
      case BlendMode.srcIn:
        return SITintMode.srcIn;
      case BlendMode.srcATop:
        return SITintMode.srcATop;
      case BlendMode.multiply:
        return SITintMode.multiply;
      case BlendMode.screen:
        return SITintMode.screen;
      case BlendMode.plus:
        return SITintMode.add;
      default:
        assert(false);
        return SITintMode.srcIn;
    }
  }

  BlendMode get asBlendMode {
    switch (this) {
      case SITintMode.srcOver:
        return BlendMode.srcOver;
      case SITintMode.srcIn:
        return BlendMode.srcIn;
      case SITintMode.srcATop:
        return BlendMode.srcATop;
      case SITintMode.multiply:
        return BlendMode.multiply;
      case SITintMode.screen:
        return BlendMode.screen;
      case SITintMode.add:
        return BlendMode.plus;
    }
  }
}

///
/// A Mixin for operations on a Group
///
mixin SIGroupHelper {
  void startPaintGroup(Canvas c, Affine? transform) {
    c.save();
    if (transform != null) {
      c.transform(transform.forCanvas);
    }
  }

  void endPaintGroup(Canvas c) {
    c.restore();
  }

  PruningBoundary? transformBoundaryFromChildren(
      PruningBoundary? b, Affine? transform) {
    if (b != null && transform != null) {
      return b.transformed(transform);
    } else {
      return b;
    }
  }

  PruningBoundary transformBoundaryFromParent(
      PruningBoundary b, Affine? transform) {
    if (transform != null) {
      final reverseXform = transform.mutableCopy()..invert();
      return b.transformed(reverseXform);
    } else {
      return b;
    }
  }
}

class SIClipPath extends SIRenderable {
  final Path path;

  SIClipPath(this.path);

  @override
  void paint(Canvas c, Color currentColor) {
    c.clipPath(path);
  }

  @override
  SIRenderable? prunedBy(PruningBoundary b, Set<SIRenderable> dagger) {
    Rect pathB = path.getBounds();
    final bb = b.getBounds();
    if (pathB.overlaps(bb)) {
      return this;
    } else {
      return null;
    }
  }

  @override
  PruningBoundary? getBoundary() => PruningBoundary(path.getBounds());

  @override
  bool operator ==(final Object other) {
    if (identical(this, other)) {
      return true;
    } else if (!(other is SIClipPath)) {
      return false;
    } else {
      return path == other.path;
    }
  }

  @override
  int get hashCode => path.hashCode ^ 0x1f9a3eed;
}

class SIPath extends SIRenderable {
  final Path path;
  final SIPaint siPaint;

  static final Paint _paint = Paint();

  SIPath(this.path, this.siPaint);

  @override
  void paint(Canvas c, Color currentColor) {
    if (siPaint.fillColorType != SIColorType.none) {
      _paint.color = (siPaint.fillColorType == SIColorType.value)
          ? Color(siPaint.fillColor)
          : currentColor;
      _paint.style = PaintingStyle.fill;
      path.fillType = siPaint.fillType.asPathFillType;
      c.drawPath(path, _paint);
    }
    if (siPaint.strokeColorType != SIColorType.none) {
      _paint.color = (siPaint.strokeColorType == SIColorType.value)
          ? Color(siPaint.strokeColor)
          : currentColor;
      _paint.style = PaintingStyle.stroke;
      _paint.strokeWidth = siPaint.strokeWidth;
      _paint.strokeCap = siPaint.strokeCap.asStrokeCap;
      _paint.strokeJoin = siPaint.strokeJoin.asStrokeJoin;
      _paint.strokeMiterLimit = siPaint.strokeMiterLimit;
      c.drawPath(path, _paint);
    }
  }

  @override
  SIRenderable? prunedBy(PruningBoundary b, Set<SIRenderable> dagger) {
    final Rect pathB = getBounds();
    final bb = b.getBounds();
    if (pathB.overlaps(bb)) {
      return this;
    } else {
      return null;
    }
  }

  Rect getBounds() {
    Rect pathB = path.getBounds();
    if (siPaint.strokeColorType != SIColorType.none) {
      final sw = siPaint.strokeWidth;
      pathB = Rect.fromLTWH(pathB.left - sw / 2, pathB.top - sw / 2,
          pathB.width + sw, pathB.height + sw);
    }
    return pathB;
  }

  @override
  PruningBoundary? getBoundary() {
    return PruningBoundary(getBounds());
  }

  @override
  bool operator ==(final Object other) {
    if (identical(this, other)) {
      return true;
    } else if (!(other is SIPath)) {
      return false;
    } else {
      return path == other.path && siPaint == other.siPaint;
    }
  }

  @override
  int get hashCode => quiver.hash2(path, siPaint);
}

///
/// A boundary for pruning child nodes when changing a viewport.  It's
/// a bounding rectangle that can be rotated.
///
class PruningBoundary {
  final Point<double> a;
  final Point<double> b;
  final Point<double> c;
  final Point<double> d;

  PruningBoundary(Rect vp)
      : a = Point(vp.left, vp.top),
        b = Point(vp.width + vp.left, vp.top),
        c = Point(vp.width + vp.left, vp.height + vp.top),
        d = Point(vp.left, vp.height + vp.top);

  PruningBoundary._p(this.a, this.b, this.c, this.d);

  Rect getBounds() => Rect.fromLTRB(
      min(min(a.x, b.x), min(c.x, d.x)),
      min(min(a.y, b.y), min(c.y, d.y)),
      max(max(a.x, b.x), max(c.x, d.x)),
      max(max(a.y, b.y), max(c.y, d.y)));

  @override
  String toString() => '_Boundary($a $b $c $d)';

  static Point<double> _tp(Point<double> p, Affine x) => x.transformed(p);

  PruningBoundary transformed(Affine x) =>
      PruningBoundary._p(_tp(a, x), _tp(b, x), _tp(c, x), _tp(d, x));
}
