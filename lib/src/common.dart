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

import '../jovial_svg.dart';
import 'affine.dart';
import 'common_noui.dart';

abstract class SIRenderable {
  void paint(Canvas c, Color currentColor);

  bool _wouldPaint(SIColor c) {
    bool hasWork = true;
    c.accept(SIColorVisitor(
        value: (SIValueColor c) {},
        current: () {},
        none: () => hasWork = false,
        linearGradient: (SILinearGradientColor c) {},
        radialGradient: (SIRadialGradientColor c) {},
        sweepGradient: (SISweepGradientColor c) {}));
    return hasWork;
  }

  SIRenderable? prunedBy(
      Set<SIRenderable> dagger, Set<SIImage> imageSet, PruningBoundary b);

  PruningBoundary? getBoundary();

  void _setLinearGradient(
      Color current, Paint p, SILinearGradientColor g, Float64List? xform) {
    p.shader = ui.Gradient.linear(Offset(g.x1, g.y1), Offset(g.x2, g.y2),
        _gradientColors(current, g), g.stops, g.spreadMethod.toTileMode, xform);
  }

  void _setRadialGradient(
      Color current, Paint p, SIRadialGradientColor g, Float64List? xform) {
    p.shader = ui.Gradient.radial(Offset(g.cx, g.cy), g.r,
        _gradientColors(current, g), g.stops, g.spreadMethod.toTileMode, xform);
  }

  void _setSweepGradient(
      Color current, Paint p, SISweepGradientColor g, Float64List? xform) {
    p.shader = ui.Gradient.sweep(
        Offset(g.cx, g.cy),
        _gradientColors(current, g),
        g.stops,
        g.spreadMethod.toTileMode,
        g.startAngle,
        g.endAngle,
        xform);
  }

  List<Color> _gradientColors(Color current, SIGradientColor g) {
    Color cc = current;
    final v = SIColorVisitor(
      value: (SIValueColor c) => cc = Color(c.argb),
      none: () {
        assert(false);
      },
      current: () => cc = current,
      linearGradient: (_) {
        assert(false);
      },
      radialGradient: (_) {
        assert(false);
      },
      sweepGradient: (_) {
        assert(false);
      },
    );
    final r = List<Color>.generate(g.colors.length, (i) {
      g.colors[i].accept(v);
      return cc;
    }, growable: false);
    return r;
  }

  Float64List? _gradientXform(SIGradientColor c, Rect bounds) {
    final transform = c.transform;
    if (c.objectBoundingBox) {
      final a = MutableAffine.translation(bounds.left, bounds.top);
      a.multiplyBy(MutableAffine.scale(bounds.width, bounds.height));
      if (transform != null) {
        a.multiplyBy(transform.toMutable);
      }
      return a.forCanvas;
    } else if (transform != null) {
      return c.transform!.forCanvas;
    } else {
      return null;
    }
  }
}

extension SIGradientSpreadMethodMapping on SIGradientSpreadMethod {
  TileMode get toTileMode {
    switch (this) {
      case SIGradientSpreadMethod.pad:
        return TileMode.clamp;
      case SIGradientSpreadMethod.reflect:
        return TileMode.mirror;
      case SIGradientSpreadMethod.repeat:
        return TileMode.repeated;
    }
  }
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

extension SIFontWeightMapping on SIFontWeight {
  FontWeight get asFontWeight {
    switch (this) {
      case SIFontWeight.w100:
        return FontWeight.w100;
      case SIFontWeight.w200:
        return FontWeight.w200;
      case SIFontWeight.w300:
        return FontWeight.w300;
      case SIFontWeight.w400:
        return FontWeight.w400;
      case SIFontWeight.w500:
        return FontWeight.w500;
      case SIFontWeight.w600:
        return FontWeight.w600;
      case SIFontWeight.w700:
        return FontWeight.w700;
      case SIFontWeight.w800:
        return FontWeight.w800;
      case SIFontWeight.w900:
        return FontWeight.w900;
    }
  }
}

extension SIFontStyleMapping on SIFontStyle {
  FontStyle get asFontStyle {
    switch (this) {
      case SIFontStyle.normal:
        return FontStyle.normal;
      case SIFontStyle.italic:
        return FontStyle.italic;
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
  SIRenderable? prunedBy(
      Set<SIRenderable> dagger, Set<SIImage> imageSet, PruningBoundary b) {
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

  bool _setPaint(SIColor si, Color currentColor) {
    bool hasWork = true;
    _paint.shader = null;
    si.accept(SIColorVisitor(
        value: (SIValueColor c) => _paint.color = Color(c.argb),
        current: () => _paint.color = currentColor,
        none: () => hasWork = false,
        linearGradient: (SILinearGradientColor c) => _setLinearGradient(
            currentColor, _paint, c, _gradientXform(c, getBounds())),
        radialGradient: (SIRadialGradientColor c) => _setRadialGradient(
            currentColor, _paint, c, _gradientXform(c, getBounds())),
        sweepGradient: (SISweepGradientColor c) => _setSweepGradient(
            currentColor, _paint, c, _gradientXform(c, getBounds()))));
    return hasWork;
  }

  @override
  void paint(Canvas c, Color currentColor) {
    if (_setPaint(siPaint.fillColor, currentColor)) {
      _paint.style = PaintingStyle.fill;
      path.fillType = siPaint.fillType.asPathFillType;
      c.drawPath(path, _paint);
    }
    if (_setPaint(siPaint.strokeColor, currentColor)) {
      _paint.style = PaintingStyle.stroke;
      _paint.strokeWidth = siPaint.strokeWidth;
      _paint.strokeCap = siPaint.strokeCap.asStrokeCap;
      _paint.strokeJoin = siPaint.strokeJoin.asStrokeJoin;
      _paint.strokeMiterLimit = siPaint.strokeMiterLimit;
      final List<double>? sda = siPaint.strokeDashArray;
      if (sda == null || sda.length < 1) {
        c.drawPath(path, _paint);
        return;
      }
      final len = sda.reduce((a, b) => a + b);
      if (len <= 0.0) {
        c.drawPath(path, _paint);
        return;
      }
      for (final contour in path.computeMetrics()) {
        double offset = (siPaint.strokeDashOffset ?? 0.0) % len;
        int sdaI = 0;
        bool penDown = true;
        double start = 0.0;
        for (;;) {
          final thisDash = sda[sdaI] - offset;
          if (thisDash <= 0.0) {
            offset -= sda[sdaI++];
            sdaI %= sda.length;
            penDown = !penDown;
          } else if (start + thisDash >= contour.length) {
            // done w/ contour
            final p = contour.extractPath(start, contour.length);
            if (penDown) {
              c.drawPath(p, _paint);
            }
            break; // out of for(;;) loop
          } else {
            final end = start + thisDash;
            final p = contour.extractPath(start, end);
            if (penDown) {
              c.drawPath(p, _paint);
            }
            start = end;
            sdaI++;
            sdaI %= sda.length;
            penDown = !penDown;
          }
        }
      }
    }
  }

  @override
  SIRenderable? prunedBy(
      Set<SIRenderable> dagger, Set<SIImage> imageSet, PruningBoundary b) {
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
    if (_wouldPaint(siPaint.strokeColor)) {
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

class SIImage extends SIRenderable {
  int _timesPrepared = 0;
  final SIImageData _data;
  ui.Image? _decoded;
  ui.Codec? _codec;
  ui.ImmutableBuffer? _buf;
  ui.ImageDescriptor? _descriptor;

  SIImage(this._data);

  bool get _disposeBuf =>
      ScalableImage.imageDisposeBugWorkaround ==
          ImageDisposeBugWorkaround.disposeBoth ||
      ScalableImage.imageDisposeBugWorkaround ==
          ImageDisposeBugWorkaround.disposeImmutableBuffer;

  bool get _disposeDescriptor =>
      ScalableImage.imageDisposeBugWorkaround ==
          ImageDisposeBugWorkaround.disposeBoth ||
          ScalableImage.imageDisposeBugWorkaround ==
              ImageDisposeBugWorkaround.disposeImageDescriptor;

  double get x => _data.x;
  double get y => _data.y;
  double get width => _data.width;
  double get height => _data.height;
  Uint8List get encoded => _data.encoded;
  SIImageData get data => _data;

  @override
  PruningBoundary? getBoundary() =>
      PruningBoundary(Rect.fromLTWH(x, y, width.toDouble(), height.toDouble()));

  @override
  SIRenderable? prunedBy(
      Set<SIRenderable> dagger, Set<SIImage> imageSet, PruningBoundary b) {
    final Rect imageB =
        Rect.fromLTWH(x, y, width.toDouble(), height.toDouble());
    final bb = b.getBounds();
    if (imageB.overlaps(bb)) {
      imageSet.add(this);
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
    final codec = _codec = await des.instantiateCodec();
    final decoded = (await codec.getNextFrame()).image;
    if (_timesPrepared > 0) {
      _decoded = decoded;
      _codec = codec;
      // see [ImageDisposeBugWorkaround].
      if (_disposeDescriptor) {
        _descriptor = des;
      }
      if (_disposeBuf) {
        _buf = buf;
      }
    } else {
      decoded.dispose(); // Too late!
      codec.dispose();
      // https://github.com/flutter/flutter/issues/83421:
      if (_disposeDescriptor) {
        des.dispose();
      }
      if (_disposeBuf) {
        buf.dispose();
      }
    }
  }

  void unprepare() {
    if (_timesPrepared <= 0) {
      throw StateError(
          'Attempt to unprepare() and image that was not prepare()d');
    }
    _timesPrepared--;
    if (_timesPrepared == 0) {
      _decoded?.dispose(); // Could be null if prepare() is still running
      _codec?.dispose();
      _descriptor?.dispose();
      _buf?.dispose();
      _decoded = null;
      _codec = null;
      _descriptor = null;
      _buf = null;
    }
  }

  @override
  void paint(Canvas c, Color currentColor) {
    final im = _decoded;
    if (im != null) {
      final src =
          Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble());
      final dest = Rect.fromLTWH(x, y, width, height);
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

class SIText extends SIRenderable {
  final String text;
  final List<double> _x;
  final List<double> _y;
  final SITextAttributes attributes;
  final SIPaint siPaint;

  SIText(this.text, this._x, this._y, this.attributes, this.siPaint);

  @override
  bool operator ==(final Object other) {
    if (identical(this, other)) {
      return true;
    } else if (!(other is SIText)) {
      return false;
    } else {
      return quiver.listsEqual(_x, other._x) &&
          quiver.listsEqual(_y, other._y) &&
          text == other.text &&
          attributes == other.attributes &&
          siPaint == other.siPaint;
    }
  }

  @override
  int get hashCode => quiver.hash4(quiver.hashObjects(_x),
      quiver.hashObjects(_y), text, quiver.hash2(attributes, siPaint));

  @override
  PruningBoundary? getBoundary() => PruningBoundary(getTextBounds());

  @override
  SIRenderable? prunedBy(
      Set<SIRenderable> dagger, Set<SIImage> imageSet, PruningBoundary b) {
    Rect textB = getTextBounds();
    final bb = b.getBounds();
    if (textB.overlaps(bb)) {
      return this;
    } else {
      return null;
    }
  }

  Rect getTextBounds() {
    Rect result = Rect.fromLTRB(_x[0], _y[0], 1, 1);
    _forEachPainter(Colors.black, Paint(),
        (double left, double top, TextPainter tp) {
      result =
          result.expandToInclude(Rect.fromLTWH(left, top, tp.width, tp.height));
    });
    return result;
  }

  Paint? _getPaint(SIColor c, Color currentColor) {
    Paint? r;
    c.accept(SIColorVisitor(
        value: (SIValueColor c) {
          final p = r = Paint();
          p.color = Color(c.argb);
        },
        current: () => r = Paint()..color = currentColor,
        none: () {},
        linearGradient: (SILinearGradientColor c) {
          final p = r = Paint();
          _setLinearGradient(
              currentColor, p, c, _gradientXform(c, getTextBounds()));
        },
        radialGradient: (SIRadialGradientColor c) {
          final p = r = Paint();
          _setRadialGradient(
              currentColor, p, c, _gradientXform(c, getTextBounds()));
        },
        sweepGradient: (SISweepGradientColor c) {
          final p = r = Paint();
          _setSweepGradient(
              currentColor, p, c, _gradientXform(c, getTextBounds()));
        }));
    return r;
  }

  @override
  void paint(ui.Canvas c, ui.Color currentColor) {
    final Paint? foreground = _getPaint(siPaint.fillColor, currentColor);
    if (foreground == null) {
      return;
    }
    _forEachPainter(currentColor, foreground,
        (double left, double top, TextPainter tp) {
      tp.paint(c, Offset(left, top));
    });
  }

  void _forEachPainter(ui.Color currentColor, ui.Paint foreground,
      void Function(double left, double top, TextPainter p) thingToDo) {
    // It's tempting to try to do all this work once, in the constructor,
    // but we need currColor for the text style.  This node can be reused,
    // so we can't guarantee that's a constant.  Fortunately, text performance
    // isn't a big part of SVG rendering performance most fo the time.
    final len = min(min(_x.length, _y.length), text.length);
    final fam = (attributes.fontFamily == '') ? null : attributes.fontFamily;
    final sz = attributes.fontSize;
    final FontStyle style = attributes.fontStyle.asFontStyle;
    final FontWeight weight = attributes.fontWeight.asFontWeight;
    for (int i = 0; i < len; i++) {
      final String s;
      if (i == len - 1) {
        s = text.substring(i, text.length);
      } else {
        s = text.substring(i, i + 1);
      }
      final span = TextSpan(
          style: TextStyle(
              foreground: foreground,
              fontFamily: fam,
              fontSize: sz,
              fontStyle: style,
              fontWeight: weight),
          text: s);
      final tp = TextPainter(text: span, textDirection: TextDirection.ltr);
      tp.layout();
      final dy = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
      thingToDo(_x[i], _y[i] - dy, tp);
    }
  }
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
