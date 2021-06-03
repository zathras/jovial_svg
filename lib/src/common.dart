/*
Copyright (c) 2021 William Foote

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

///
/// Utilities that are common between DAG and Compact
/// scalable image implementations.
///
library jovial_svg.common;

import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:quiver/core.dart' as quiver;
import 'package:quiver/collection.dart' as quiver;

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

class SIImage extends SIImageData implements SIRenderable {
  int _timesPrepared = 0;
  ui.Image? _decoded;
  ui.Codec? _codec;
  // ui.ImageDescriptor? _descriptor;

  SIImage(SIImageData data) : super.copy(data);

  @override
  PruningBoundary? getBoundary() =>
      PruningBoundary(Rect.fromLTWH(x, y, width.toDouble(), height.toDouble()));

  @override
  SIRenderable? prunedBy(PruningBoundary b, Set<SIRenderable> dagger) {
    final Rect imageB =
        Rect.fromLTWH(x, y, width.toDouble(), height.toDouble());
    final bb = b.getBounds();
    if (imageB.overlaps(bb)) {
      return this;
    } else {
      return null;
    }
  }

  Future<void> prepare() async {
    _timesPrepared++;
    if (_timesPrepared > 1) {
      return;
    }
    assert(_decoded == null);
    final buf = await ui.ImmutableBuffer.fromUint8List(encoded);
    final des = await ui.ImageDescriptor.encoded(buf);
    // It's not documented whether ImageDescriptor takes over ownership of
    // buf, or if we're supposed to call buf.dispose().  After some
    // trial-and-error, it appears that it's the former, that is, we're
    // not supposed to call buf.dispose.  Or, it could be the bug(s) addressed
    // by this:  https://github.com/flutter/engine/pull/26435
    //
    // For now, I'll just refrain from disposing buf.  This area looks to
    // be pretty flaky (as of June 2021), what with ImageDescriptor.dispose()
    // not being implemented.
    //
    // https://github.com/flutter/flutter/issues/83764
    //
    // TODO:  Revisit this when this area of Flutter is less flaky
    final codec = _codec = await des.instantiateCodec();
    final decoded = (await codec.getNextFrame()).image;
    if (_timesPrepared > 0) {
      _decoded = decoded;
      _codec = codec;
      // _descriptor = des;
    } else {
      decoded.dispose();  // Too late!
      codec.dispose();
      // https://github.com/flutter/flutter/issues/83421:
      // _descriptor?.dispose();
      // Further, it's not clear from the documentation if we're *supposed*
      // to call it, given that we dispose the codec.  Once it's implemented,
      // it will be possible to test this.
    }
  }

  void unprepare() {
    if (_timesPrepared <= 0) {
      throw StateError('Attempt to unprepare() and image that was not prepare()d');
    }
    _timesPrepared--;
    if (_timesPrepared == 0) {
      _decoded?.dispose();    // Could be null if prepare() is still running
      _codec?.dispose();
      _decoded = null;
      // https://github.com/flutter/flutter/issues/83421:
      // _descriptor?.dispose();
      // Further, it's not clear from the documentation if we're *supposed*
      // to call it, given that we dispose the codec.
    }
  }

  @override
  void paint(Canvas c, Color currentColor) {
    final im = _decoded;
    if (im != null) {
      final src = Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble());
      final dest = Rect.fromLTWH(x, y, width, height);
      // c.drawImage(im, Offset(x, y), Paint());
      c.drawImageRect(im, src, dest, Paint());
    }
  }

  @override
  bool operator ==(final Object other) {
    if (identical(this, other)) {
      return true;
    } else if (!(other is SIImage)) {
      return false;
    } else {
      return x == other.x &&
          y == other.y &&
          width == other.width &&
          height == other.height &&
          quiver.listsEqual(encoded, other.encoded);
    }
  }

  @override
  int get hashCode => quiver.hash2(
      quiver.hash4(x, y, width, height), quiver.hashObjects(encoded));
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
