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

///
/// Utilities that are common between DAG and Compact
/// scalable image implementations.
///
library jovial_svg.common;

import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../jovial_svg.dart';
import 'affine.dart';
import 'common_noui.dart';
import 'exported.dart' show ExportedIDBoundary;

Rect? convertRectTtoRect(RectT? r) {
  if (r == null) {
    return null;
  } else {
    return Rect.fromLTWH(r.left, r.top, r.width, r.height);
  }
}

RectT? convertRectToRectT(Rect? r) {
  if (r == null) {
    return null;
  } else {
    return RectT(r.left, r.top, r.width, r.height);
  }
}

///
/// Base class for a renderable node.  Note that, though it is
/// `@immutable`, an image node isn't immutable, due to the need to
/// load images asynchronously.  Dart's `@immutable` is, uh, partial,
/// but there is some value to the declaration.
///
@immutable
abstract class SIRenderable {
  void paint(Canvas c, Color currentColor);

  bool _wouldPaint(SIColor c) => c is! SINoneColor;

  SIRenderable? prunedBy(
      Set<Object> dagger, Set<SIImage> imageSet, PruningBoundary b);

  ///
  /// Get the pruning boundary, if this renderable renders something.  A text
  /// node with no text is an example that doesn't render anything.
  ///
  /// If the arguments are non-null, also collect the exported IDs and their
  /// boundaries.
  ///
  PruningBoundary? getBoundary(
      List<ExportedIDBoundary>? exportedIDs, Affine? exportedIDXform);

  void _setLinearGradient(Paint p, SILinearGradientColor g, Float64List? xform,
      Color currentColor) {
    p.shader = ui.Gradient.linear(
        Offset(g.x1, g.y1),
        Offset(g.x2, g.y2),
        _gradientColors(currentColor, g),
        g.stops,
        g.spreadMethod.toTileMode,
        xform);
  }

  void _setRadialGradient(Paint p, SIRadialGradientColor g, Float64List? xform,
      Color currentColor) {
    p.shader = ui.Gradient.radial(
        Offset(g.cx, g.cy),
        g.r,
        _gradientColors(currentColor, g),
        g.stops,
        g.spreadMethod.toTileMode,
        xform,
        Offset(g.fx, g.fy));
  }

  void _setSweepGradient(
      Paint p, SISweepGradientColor g, Float64List? xform, Color currentColor) {
    p.shader = ui.Gradient.sweep(
        Offset(g.cx, g.cy),
        _gradientColors(currentColor, g),
        g.stops,
        g.spreadMethod.toTileMode,
        g.startAngle,
        g.endAngle,
        xform);
  }

  // The colors within a gradient, fed to a Flutter shader.
  List<Color> _gradientColors(Color current, SIGradientColor g) {
    final r = List<Color>.generate(g.colors.length, (i) {
      final c = g.colors[i];
      if (c is SIValueColor) {
        return Color(c.argb);
      }
      assert(c is SICurrentColor, 'Gradient as gradient stop?!?');
      return current;
    }, growable: false);
    return r;
  }

  Float64List? _gradientXform(
      SIGradientColor c, Rect Function() boundsF, Color currentColor) {
    final transform = c.transform;
    if (c.objectBoundingBox) {
      final bounds = boundsF();
      final a = MutableAffine.translation(bounds.left, bounds.top);
      a.multiplyBy(MutableAffine.scale(bounds.width, bounds.height));
      if (transform != null) {
        a.multiplyBy(transform.toMutable);
      }
      return a.forCanvas;
    } else if (transform != null) {
      return transform.forCanvas;
    } else {
      return null;
    }
  }

  void addChildren(Set<Object> dagger);

  void privateAssertIsEquivalent(SIRenderable other) {
    if (this != other) {
      throw StateError('$this  $other');
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
      case BlendMode.clear:
        return SITintMode.clear;
      case BlendMode.color:
        return SITintMode.color;
      case BlendMode.colorBurn:
        return SITintMode.colorBurn;
      case BlendMode.colorDodge:
        return SITintMode.colorDodge;
      case BlendMode.darken:
        return SITintMode.darken;
      case BlendMode.difference:
        return SITintMode.difference;
      case BlendMode.dst:
        return SITintMode.dst;
      case BlendMode.dstATop:
        return SITintMode.dstATop;
      case BlendMode.dstIn:
        return SITintMode.dstIn;
      case BlendMode.dstOut:
        return SITintMode.dstOut;
      case BlendMode.dstOver:
        return SITintMode.dstOver;
      case BlendMode.exclusion:
        return SITintMode.exclusion;
      case BlendMode.hardLight:
        return SITintMode.hardLight;
      case BlendMode.hue:
        return SITintMode.hue;
      case BlendMode.lighten:
        return SITintMode.lighten;
      case BlendMode.luminosity:
        return SITintMode.luminosity;
      case BlendMode.modulate:
        return SITintMode.modulate;
      case BlendMode.overlay:
        return SITintMode.overlay;
      case BlendMode.saturation:
        return SITintMode.saturation;
      case BlendMode.softLight:
        return SITintMode.softLight;
      case BlendMode.src:
        return SITintMode.src;
      case BlendMode.srcOut:
        return SITintMode.srcOut;
      case BlendMode.xor:
        return SITintMode.xor;
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
      case SITintMode.clear:
        return BlendMode.clear;
      case SITintMode.color:
        return BlendMode.color;
      case SITintMode.colorBurn:
        return BlendMode.colorBurn;
      case SITintMode.colorDodge:
        return BlendMode.colorDodge;
      case SITintMode.darken:
        return BlendMode.darken;
      case SITintMode.difference:
        return BlendMode.difference;
      case SITintMode.dst:
        return BlendMode.dst;
      case SITintMode.dstATop:
        return BlendMode.dstATop;
      case SITintMode.dstIn:
        return BlendMode.dstIn;
      case SITintMode.dstOut:
        return BlendMode.dstOut;
      case SITintMode.dstOver:
        return BlendMode.dstOver;
      case SITintMode.exclusion:
        return BlendMode.exclusion;
      case SITintMode.hardLight:
        return BlendMode.hardLight;
      case SITintMode.hue:
        return BlendMode.hue;
      case SITintMode.lighten:
        return BlendMode.lighten;
      case SITintMode.luminosity:
        return BlendMode.luminosity;
      case SITintMode.modulate:
        return BlendMode.modulate;
      case SITintMode.overlay:
        return BlendMode.overlay;
      case SITintMode.saturation:
        return BlendMode.saturation;
      case SITintMode.softLight:
        return BlendMode.softLight;
      case SITintMode.src:
        return BlendMode.src;
      case SITintMode.srcOut:
        return BlendMode.srcOut;
      case SITintMode.xor:
        return BlendMode.xor;
    }
  }
}

extension SIBlendModeMapping on SIBlendMode {
  BlendMode? get asBlendMode {
    switch (this) {
      case SIBlendMode.normal:
        return null;
      case SIBlendMode.multiply:
        return BlendMode.multiply;
      case SIBlendMode.screen:
        return BlendMode.screen;
      case SIBlendMode.overlay:
        return BlendMode.overlay;
      case SIBlendMode.darken:
        return BlendMode.darken;
      case SIBlendMode.lighten:
        return BlendMode.lighten;
      case SIBlendMode.colorDodge:
        return BlendMode.colorDodge;
      case SIBlendMode.colorBurn:
        return BlendMode.colorBurn;
      case SIBlendMode.hardLight:
        return BlendMode.hardLight;
      case SIBlendMode.softLight:
        return BlendMode.softLight;
      case SIBlendMode.difference:
        return BlendMode.difference;
      case SIBlendMode.exclusion:
        return BlendMode.exclusion;
      case SIBlendMode.hue:
        return BlendMode.hue;
      case SIBlendMode.saturation:
        return BlendMode.saturation;
      case SIBlendMode.color:
        return BlendMode.color;
      case SIBlendMode.luminosity:
        return BlendMode.luminosity;
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

extension SITextDecorationMapping on SITextDecoration {
  TextDecoration get asTextDecoration {
    switch (this) {
      case SITextDecoration.none:
        return TextDecoration.none;
      case SITextDecoration.lineThrough:
        return TextDecoration.lineThrough;
      case SITextDecoration.overline:
        return TextDecoration.overline;
      case SITextDecoration.underline:
        return TextDecoration.underline;
    }
  }
}

///
/// A Mixin for operations on a Group
///
mixin SIGroupHelper {
  final List<bool> _blendModeStack = [];

  void startPaintGroup(
      Canvas c, Affine? transform, int? groupAlpha, BlendMode? blendMode) {
    if (blendMode != null) {
      _blendModeStack.add(true);
      c.saveLayer(null, Paint()..blendMode = blendMode);
    } else {
      _blendModeStack.add(false);
    }
    if (groupAlpha == null || groupAlpha == 0xff) {
      c.save();
    } else {
      c.saveLayer(
          null,
          Paint()
            ..blendMode = BlendMode.srcOver
            ..color = Color.fromARGB(groupAlpha, 0xff, 0xff, 0xff));
    }
    if (transform != null) {
      c.transform(transform.forCanvas);
    }
  }

  void endPaintGroup(Canvas c) {
    if (_blendModeStack.last) {
      c.restore();
    }
    _blendModeStack.length--;
    c.restore();
  }
}

///
/// A Mixin for the Mask operations
///
mixin SIMaskedHelper {
  ///
  /// Start the (alpha) mask, which is painted first
  ///
  void startMask(Canvas c, Rect? bounds) {
    c.saveLayer(bounds, Paint());
    c.save();
  }

  ///
  /// Start the luma mask, which is optionally painted after the alpha
  /// mask.
  ///
  /// This is a frustrating part of SVG.  Masks in SVG 1.1 mask by the
  /// alpha channel, MULTIPLIED BY the luminance.  I know of no way I (at
  /// least in Flutter) to tell if the mask layer uses alpha, luma, or
  /// both, so we're forced to render the mask twice and composite them.
  ///
  /// As an optimization, we can detect Mask graphs that can't possibly
  /// use luma, and avoid the second mask rendering in that case.  See
  /// SvgNode.canUseLuma().
  ///
  void startLumaMask(Canvas c, Rect? bounds) {
    c.restore();
    c.save();
    // A color filter to set the luma component to ffffff, and the
    // alpha value to the pixel's old luma value.
    const f = ColorFilter.matrix([
      ...[0, 0, 0, 0, 1],
      ...[0, 0, 0, 0, 1],
      ...[0, 0, 0, 0, 1],
      ...[0.2126, 0.7152, 0.0722, 0, 0]
    ]);
    c.saveLayer(
        bounds,
        Paint()
          ..colorFilter = f
          ..blendMode = BlendMode.srcIn);
  }

  ///
  /// Start the luma mask, which is optionally painted after the alpha
  /// mask.
  ///
  void finishLumaMask(Canvas c) {
    c.restore();
  }

  ///
  /// Start the child, which is painted after the mask
  ///
  void startChild(Canvas c, Rect? bounds) {
    c.restore();
    c.saveLayer(bounds, Paint()..blendMode = BlendMode.srcIn);
  }

  ///
  /// Finish painting the Masked element
  ///
  void finishMasked(Canvas c) {
    c.restore();
    c.restore();
  }
}

class SITextBuilder<R> {
  final SITextBuilder<R>? parent;
  final double _dx;
  final double _dy;
  final SITextAnchor _anchor;
  final List<SITextSpan> _spans = [];
  final List<SITextChunk> _chunks = [];

  SITextBuilder(
      [this.parent,
      this._dx = 0,
      this._dy = 0,
      this._anchor = SITextAnchor.start]);

  SITextBuilder<R>? multiSpanChunk(double dx, double dy, SITextAnchor anchor) {
    return SITextBuilder(this, dx, dy, anchor);
  }

  SITextBuilder<R>? span(double dx, double dy, String text,
      SITextAttributes attributes, SIPaint paint) {
    final s = SITextSpan(text, dx, dy, attributes, paint);
    if (parent == null) {
      _chunks.add(s);
    } else {
      _spans.add(s);
    }
    return this;
  }

  R end(R collector, SITextHelper<R> customer) {
    final p = parent;
    if (p != null) {
      assert(_chunks.isEmpty);
      p._chunks.add(SIMultiSpanChunk(_dx, _dy, _anchor, _spans));
      return collector;
    } else {
      assert(_spans.isEmpty);
      return customer.acceptText(collector, SIText(List.unmodifiable(_chunks)));
    }
  }
}

///
/// A mixin for customers of SITextBuilder
///
mixin SITextHelper<R> {
  SITextBuilder<R>? _textBuilder;

  List<double> get floatValues;
  List<String> get strings;
  List<List<String>> get stringLists;

  R text(R collector) {
    assert(_textBuilder == null);
    _textBuilder = SITextBuilder();
    return collector;
  }

  R textMultiSpanChunk(
      R collector, int dxIndex, int dyIndex, SITextAnchor anchor) {
    assert(_textBuilder != null);
    _textBuilder = _textBuilder?.multiSpanChunk(
        floatValues[dxIndex], floatValues[dyIndex], anchor);
    return collector;
  }

  R textSpan(
      R collector,
      int dxIndex,
      int dyIndex,
      int textIndex,
      SITextAttributes attributes,
      int? fontFamilyIndex,
      int fontSizeIndex,
      SIPaint paint) {
    assert(_textBuilder != null);
    assert((fontFamilyIndex == null && attributes.fontFamily == null) ||
        (fontFamilyIndex != null) &&
            (const ListEquality<String>())
                .equals(stringLists[fontFamilyIndex], attributes.fontFamily));
    assert(floatValues[fontSizeIndex] == attributes.fontSize);
    _textBuilder = _textBuilder?.span(floatValues[dxIndex],
        floatValues[dyIndex], strings[textIndex], attributes, paint);
    return collector;
  }

  R textEnd(R collector) {
    final tb = _textBuilder;
    assert(tb != null);
    if (tb == null) {
      return collector;
    }
    _textBuilder = tb.parent;
    return tb.end(collector, this);
  }

  R acceptText(R collector, SIText text);
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
          Set<Object> dagger, Set<SIImage> imageSet, PruningBoundary? b) =>
      this;

  @override
  PruningBoundary? getBoundary(
          List<ExportedIDBoundary>? exportedIDs, Affine? exportedIDXform) =>
      PruningBoundary(path.getBounds());

  @override
  void addChildren(Set<Object> dagger) {}

  @override
  bool operator ==(final Object other) {
    if (identical(this, other)) {
      return true;
    } else if (other is! SIClipPath) {
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

  SIPath(this.path, this.siPaint);

  bool _setPaint(Paint paint, SIColor si, Color currentColor) {
    bool hasWork = true;
    paint.shader = null;
    late final bounds = getBounds();
    Rect boundsF() => bounds;
    si.accept(SIColorVisitor(
        value: (SIValueColor c) => paint.color = Color(c.argb),
        current: () => paint.color = currentColor,
        none: () => hasWork = false,
        linearGradient: (SILinearGradientColor c) => _setLinearGradient(
            paint, c, _gradientXform(c, boundsF, currentColor), currentColor),
        radialGradient: (SIRadialGradientColor c) => _setRadialGradient(
            paint, c, _gradientXform(c, boundsF, currentColor), currentColor),
        sweepGradient: (SISweepGradientColor c) => _setSweepGradient(
            paint, c, _gradientXform(c, boundsF, currentColor), currentColor)));
    return hasWork;
  }

  @override
  void paint(Canvas c, Color currentColor) {
    final paint = Paint();
    if (_setPaint(paint, siPaint.fillColor, currentColor)) {
      paint.style = PaintingStyle.fill;
      path.fillType = siPaint.fillType.asPathFillType;
      c.drawPath(path, paint);
    }
    if (_setPaint(paint, siPaint.strokeColor, currentColor)) {
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = siPaint.strokeWidth;
      paint.strokeCap = siPaint.strokeCap.asStrokeCap;
      paint.strokeJoin = siPaint.strokeJoin.asStrokeJoin;
      paint.strokeMiterLimit = siPaint.strokeMiterLimit;
      final List<double>? sda = siPaint.strokeDashArray;
      if (sda == null || sda.isEmpty) {
        c.drawPath(path, paint);
        return;
      }
      final len = sda.reduce((a, b) => a + b);
      if (len <= 0.0) {
        c.drawPath(path, paint);
        return;
      }
      // We should only have one contour.  A contour is made up of connected
      // curves and segments; a new contour is started with a moveTo.  SIPath
      // only has a moveTo at the start.  We still iterate through the list,
      // for a bit of robustness in case this ever changes.  If it does, the
      // penUp/penDown logic should arguably re-start for each contour, since
      // contours are not connected.
      for (final contour in path.computeMetrics()) {
        double offset = (siPaint.strokeDashOffset ?? 0.0) % len;
        int sdaI = 0;
        bool penDown = true;
        double start = 0.0;
        for (;;) {
          final thisDash = sda[sdaI] - offset;
          if (thisDash < 0.0) {
            offset -= sda[sdaI++];
            sdaI %= sda.length;
            penDown = !penDown;
          } else if (start + thisDash >= contour.length) {
            offset = 0;
            // done w/ contour
            final p = contour.extractPath(start, contour.length);
            if (penDown) {
              c.drawPath(p, paint);
            }
            break; // out of for(;;) loop
          } else {
            offset = 0;
            final end = start + thisDash;
            final p = contour.extractPath(start, end);
            if (penDown) {
              c.drawPath(p, paint);
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
      Set<Object> dagger, Set<SIImage> imageSet, PruningBoundary? b) {
    if (b == null) {
      return this;
    }
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
  PruningBoundary? getBoundary(
      List<ExportedIDBoundary>? exportedIDs, Affine? exportedIDXform) {
    return PruningBoundary(getBounds());
  }

  @override
  void addChildren(Set<Object> dagger) {}

  @override
  void privateAssertIsEquivalent(SIRenderable other) {
    if (identical(this, other)) {
      return;
    } else if (other is! SIPath) {
      throw StateError('$this $other');
    } else if (siPaint == other.siPaint) {
      return;
    } else {
      // Path is basically opaque; no good way to check it.
      throw StateError('$this $other');
    }
  }

  @override
  bool operator ==(final Object other) {
    if (identical(this, other)) {
      return true;
    } else if (other is! SIPath) {
      return false;
    } else {
      return path == other.path && siPaint == other.siPaint;
    }
  }

  @override
  int get hashCode => 0xa8f8de16 ^ Object.hash(path, siPaint);
}

class SIImage extends SIRenderable {
  late final loader = _ImageLoader(this);
  final SIImageData _data;

  SIImage(this._data);

  double get x => _data.x;
  double get y => _data.y;
  double get width => _data.width;
  double get height => _data.height;
  Uint8List get encoded => _data.encoded;
  SIImageData get data => _data;

  @override
  PruningBoundary? getBoundary(
          List<ExportedIDBoundary>? exportedIDs, Affine? exportedIDXform) =>
      PruningBoundary(Rect.fromLTWH(x, y, width.toDouble(), height.toDouble()));

  @override
  SIRenderable? prunedBy(
      Set<Object> dagger, Set<SIImage> imageSet, PruningBoundary? b) {
    if (b == null) {
      imageSet.add(this);
      return this;
    }
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

  Future<void> prepare() => loader.prepare();

  void unprepare() => loader.unprepare();

  @override
  void paint(Canvas c, Color currentColor) => loader.paint(c);

  @override
  void addChildren(Set<Object> dagger) {}

  @override
  bool operator ==(final Object other) {
    if (identical(this, other)) {
      return true;
    } else if (other is! SIImage) {
      return false;
    } else {
      return x == other.x &&
          y == other.y &&
          width == other.width &&
          height == other.height &&
          encoded.equals(other.encoded);
    }
  }

  @override
  int get hashCode =>
      0xc36c5d4e ^ Object.hash(x, y, width, height, Object.hashAll(encoded));
}

class _ImageLoader {
  final SIImage source;
  int _timesPrepared = 0;
  ui.Image? _decoded;
  ui.Codec? _codec;
  ui.ImmutableBuffer? _buf;
  ui.ImageDescriptor? _descriptor;

  _ImageLoader(this.source);

  bool get _disposeBuf =>
      ScalableImage.imageDisposeBugWorkaround ==
          ImageDisposeBugWorkaround.silentlyIgnoreErrors ||
      ScalableImage.imageDisposeBugWorkaround ==
          ImageDisposeBugWorkaround.disposeBoth ||
      ScalableImage.imageDisposeBugWorkaround ==
          ImageDisposeBugWorkaround.disposeImmutableBuffer;

  bool get _disposeDescriptor =>
      ScalableImage.imageDisposeBugWorkaround ==
          ImageDisposeBugWorkaround.silentlyIgnoreErrors ||
      ScalableImage.imageDisposeBugWorkaround ==
          ImageDisposeBugWorkaround.disposeBoth ||
      ScalableImage.imageDisposeBugWorkaround ==
          ImageDisposeBugWorkaround.disposeImageDescriptor;

  // https://github.com/zathras/jovial_svg/issues/62
  static void callDispose(void Function() f) {
    try {
      f();
    } catch (e, st) {
      if (ScalableImage.imageDisposeBugWorkaround !=
          ImageDisposeBugWorkaround.silentlyIgnoreErrors) {
        debugPrint(
            'WARNING:  Bug detected in Flutter image-related dispose() call.');
        debugPrint('    Ignoring $e');
        debugPrint('    This warning can be silenced with '
            'ScalableImage.imageDisposeBugWorkaround.');
        debugPrint('    See  https://github.com/zathras/jovial_svg/issues/62');
        debugPrint('    Stack trace: $st');
      }
    }
  }

  Future<void> prepare() async {
    _timesPrepared++;
    if (_timesPrepared > 1) {
      return;
    }
    assert(_decoded == null);
    final buf = await ui.ImmutableBuffer.fromUint8List(source.encoded);
    ui.ImageDescriptor? des;
    ui.Codec? codec;
    ui.Image? decoded;
    try {
      des = await ui.ImageDescriptor.encoded(buf);
      codec = _codec = await des.instantiateCodec();
      decoded = (await codec.getNextFrame()).image;
    } catch (e) {
      callDispose(() => codec?.dispose());
      callDispose(() => decoded?.dispose());
      callDispose(() => buf.dispose());
      return;
    }
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
      // It was too late when the image came in.
      final decodedCopy = decoded; // Known to be not null
      callDispose(() => decodedCopy.dispose());
      final codecCopy = codec;
      callDispose(() => codecCopy.dispose());
      // https://github.com/flutter/flutter/issues/83421:
      final desCopy = des;
      if (_disposeDescriptor) {
        callDispose(() => desCopy.dispose());
      }
      if (_disposeBuf) {
        callDispose(() => buf.dispose());
      }
    }
  }

  void unprepare() {
    if (_timesPrepared <= 0) {
      throw StateError(
          'Attempt to unprepare() an image that was not prepare()d');
    }
    _timesPrepared--;
    if (_timesPrepared == 0) {
      callDispose(() =>
          _decoded?.dispose()); // Could be null if prepare() is still running
      callDispose(() => _codec?.dispose());
      callDispose(() => _descriptor?.dispose());
      callDispose(() => _buf?.dispose());
      _decoded = null;
      _codec = null;
      _descriptor = null;
      _buf = null;
    }
  }

  void paint(Canvas c) {
    final im = _decoded;
    if (im != null) {
      final src =
          Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble());
      final dest =
          Rect.fromLTWH(source.x, source.y, source.width, source.height);
      c.drawImageRect(im, src, dest, Paint());
    }
  }
}

class SIText extends SIRenderable {
  final List<SITextChunk> chunks;

  SIText(this.chunks);

  factory SIText.legacy(String text, List<double> x, List<double> y,
      SITextAttributes attributes, SIPaint siPaint) {
    final chunks = <SITextChunk>[];
    final len = min(min(x.length, y.length), text.length);
    for (int i = 0; i < len; i++) {
      final String s;
      if (i == len - 1) {
        s = text.substring(i, text.length);
      } else {
        s = text.substring(i, i + 1);
      }
      chunks.add(SITextSpan(s, x[i], y[i], attributes, siPaint));
    }
    return SIText(List.unmodifiable(chunks));
  }

  @override
  PruningBoundary? getBoundary(
          List<ExportedIDBoundary>? exportedIDs, Affine? exportedIDXform) =>
      chunks.isEmpty ? null : PruningBoundary(_bounds);

  @override
  SIRenderable? prunedBy(
      Set<Object> dagger, Set<SIImage> imageSet, PruningBoundary? b) {
    if (chunks.isEmpty) {
      return null;
    }
    if (b == null) {
      return this;
    }
    Rect textB = _bounds;
    final bb = b.getBounds();
    if (textB.overlaps(bb)) {
      return this;
    } else {
      return null;
    }
  }

  late final Rect _bounds = () {
    Rect result = chunks[0]._bounds;
    for (int i = 0; i < chunks.length; i++) {
      result = result.expandToInclude(chunks[i]._bounds);
    }
    return result;
  }();

  @override
  void paint(ui.Canvas c, Color currentColor) {
    for (final chunk in chunks) {
      chunk.paint(this, c, currentColor);
    }
  }

  @override
  void addChildren(Set<Object> dagger) {}

  @override
  bool operator ==(final Object other) {
    if (identical(this, other)) {
      return true;
    } else if (other is! SIText) {
      return false;
    } else {
      return chunks.equals(other.chunks);
    }
  }

  @override
  int get hashCode => 0x238cbb88 ^ Object.hashAll(chunks);
}

abstract class SITextChunk {
  final double dx;
  final double dy;

  SITextChunk(this.dx, this.dy);

  void paint(SIText parent, ui.Canvas c, Color currentColor);

  Rect get _bounds;

  void build<PathDataT>(
      CanonicalizedData<SIImage> canon, SIBuilder<PathDataT, SIImage> builder);
}

class SITextSpan extends SITextChunk {
  final String text;
  final SITextAttributes attributes;
  final SIPaint siPaint;

  SITextSpan(this.text, double dx, double dy, this.attributes, this.siPaint)
      : super(dx, dy);

  @override
  late final Rect _bounds = () {
    late final Rect result;
    _doWithPainter(
        Colors.black, Paint(), attributes.textDecoration.asTextDecoration,
        (double left, double top, TextPainter tp) {
      result = Rect.fromLTWH(left, top, tp.width, tp.height);
    });
    return result;
  }();

  @override
  void build<PathDataT>(
      CanonicalizedData<SIImage> canon, SIBuilder<PathDataT, SIImage> builder) {
    final int? fontFamilyIndex;
    if (attributes.fontFamily == null) {
      fontFamilyIndex = null;
    } else {
      for (final String s in attributes.fontFamily!) {
        canon.strings[s];
      }
      fontFamilyIndex =
          canon.stringLists.getIfNotNull(CList(attributes.fontFamily!));
    }
    final textIndex = canon.strings[text];
    final dxIndex = canon.floatValues[dx];
    final dyIndex = canon.floatValues[dy];
    final fontSizeIndex = canon.floatValues[attributes.fontSize];
    builder.textSpan(null, dxIndex, dyIndex, textIndex, attributes,
        fontFamilyIndex, fontSizeIndex, siPaint);
  }

  Paint? _getPaint(SIText parent, SIColor c, Color currentColor) {
    Rect boundsF() => parent._bounds;
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
          parent._setLinearGradient(p, c,
              parent._gradientXform(c, boundsF, currentColor), currentColor);
        },
        radialGradient: (SIRadialGradientColor c) {
          final p = r = Paint();
          parent._setRadialGradient(p, c,
              parent._gradientXform(c, boundsF, currentColor), currentColor);
        },
        sweepGradient: (SISweepGradientColor c) {
          final p = r = Paint();
          parent._setSweepGradient(p, c,
              parent._gradientXform(c, boundsF, currentColor), currentColor);
        }));
    return r;
  }

  @override
  void paint(SIText parent, ui.Canvas c, Color currentColor) {
    final TextDecoration decoration =
        attributes.textDecoration.asTextDecoration;
    final decorated = decoration != TextDecoration.none;
    Paint? foreground = _getPaint(parent, siPaint.fillColor, currentColor);
    if (foreground != null) {
      if (decorated && siPaint.fillColor is! SIValueColor) {
        c.saveLayer(_bounds, Paint());
        final white = Paint()..color = Colors.white;
        _doWithPainter(currentColor, white, decoration,
            (double left, double top, TextPainter tp) {
          tp.paint(c, Offset(left, top));
        });
        c.saveLayer(_bounds, Paint()..blendMode = BlendMode.srcIn);
        c.drawRect(_bounds, foreground);
        c.restore();
        c.restore();
      } else {
        _doWithPainter(currentColor, foreground, decoration,
            (double left, double top, TextPainter tp) {
          tp.paint(c, Offset(left, top));
        });
      }
    }
    Paint? strokeP = _getPaint(parent, siPaint.strokeColor, currentColor);
    if (strokeP != null) {
      if (decorated &&
          foreground == null &&
          siPaint.strokeColor is! SIValueColor) {
        c.saveLayer(_bounds, Paint());
        final white = Paint()
          ..color = Colors.white
          ..strokeWidth = siPaint.strokeWidth
          ..style = PaintingStyle.stroke;
        _doWithPainter(currentColor, white, decoration,
            (double left, double top, TextPainter tp) {
          tp.paint(c, Offset(left, top));
        });
        c.saveLayer(_bounds, Paint()..blendMode = BlendMode.srcIn);
        c.drawRect(_bounds, strokeP);
        c.restore();
        c.restore();
      } else {
        strokeP.strokeWidth = siPaint.strokeWidth;
        strokeP.style = PaintingStyle.stroke;
        final decoration2 =
            foreground == null ? decoration : TextDecoration.none;
        _doWithPainter(currentColor, strokeP, decoration2,
            (double left, double top, TextPainter tp) {
          tp.paint(c, Offset(left, top));
        });
      }
    }
  }

  void _doWithPainter(
      ui.Color currentColor,
      ui.Paint foreground,
      TextDecoration decoration,
      void Function(double left, double top, TextPainter p) thingToDo) {
    // It's tempting to try to do all this work once, in the constructor,
    // but we need currColor for the text style.  This node can be reused,
    // so we can't guarantee that's a constant.  Fortunately, text performance
    // isn't a big part of SVG rendering performance most of the time.
    final sz = attributes.fontSize;
    final FontStyle style = attributes.fontStyle.asFontStyle;
    final FontWeight weight = attributes.fontWeight.asFontWeight;
    List<String>? ff = attributes.fontFamily;
    final span = TextSpan(
        style: TextStyle(
            foreground: foreground,
            fontFamily: null,
            fontFamilyFallback: ff,
            fontSize: sz,
            fontStyle: style,
            fontWeight: weight,
            decoration: decoration,
            decorationColor: foreground.color),
        text: text);
    // We could support the decoration-color attribute, but neither Firefox
    // nor Chrome do (in March 2022), so I'd consider that extreme
    // gold-plating.
    final tp = TextPainter(text: span, textDirection: TextDirection.ltr);
    tp.layout();
    
    final double anchorDx;
    switch (attributes.textAnchor) {
      case SITextAnchor.start:
        anchorDx = 0;
        break;
      case SITextAnchor.middle:
        anchorDx = -tp.width / 2;
        break;
      case SITextAnchor.end:
        anchorDx = -tp.width;
        break;
    }

    final double baseDy;
    switch (attributes.dominantBaseline) {
      case SIDominantBaseline.auto:
      case SIDominantBaseline.alphabetic:
      case SIDominantBaseline.textBeforeEdge:
        baseDy = -tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
        break;
      case SIDominantBaseline.middle:
      case SIDominantBaseline.central:
        baseDy = -tp.computeDistanceToActualBaseline(TextBaseline.alphabetic) / 2;
        break;
      case SIDominantBaseline.hanging:
      case SIDominantBaseline.textAfterEdge:
        baseDy = 0;
        break;
      case SIDominantBaseline.ideographic:
      case SIDominantBaseline.mathematical:
        baseDy = -tp.computeDistanceToActualBaseline(TextBaseline.ideographic);
        break;
    }

    thingToDo(dx + anchorDx, dy + baseDy, tp);
  }

  @override
  bool operator ==(final Object other) {
    if (identical(this, other)) {
      return true;
    } else if (other is! SITextSpan) {
      return false;
    } else {
      return dx == other.dx &&
          dy == other.dy &&
          text == other.text &&
          attributes == other.attributes &&
          siPaint == other.siPaint;
    }
  }

  @override
  int get hashCode => Object.hash(dx, dy, text, attributes, siPaint);
}

///
/// A "text chunk," in SVG, is a set of text with an absolute position.
/// The children of this node's x and y values are deltas from their
/// "natural" postion, and the textAnchor of our children must be `start`.
/// Instances of this class must have at least one child [SITextSpan].
///
class SIMultiSpanChunk extends SITextChunk {
  final SITextAnchor textAnchor;
  final List<SITextSpan> spans;

  SIMultiSpanChunk(super.dx, super.dy, this.textAnchor, this.spans) {
    assert(spans.isNotEmpty);
    for (final s in spans) {
      assert(s.attributes.textAnchor == SITextAnchor.start);
    }
  }

  @override
  ui.Rect get _bounds {
    ui.Rect result = spans[0]._bounds;
    double right = result.right;
    for (int i = 0; i < spans.length; i++) {
      ui.Rect b = spans[i]._bounds;
      b = Rect.fromLTWH(b.left + right, b.top, b.width, b.height);
      result = result.expandToInclude(b);
      right = result.right;
    }
    switch (textAnchor) {
      case SITextAnchor.start:
        return ui.Rect.fromLTWH(
            dx + result.left, dy + result.top, result.width, result.height);
      case SITextAnchor.middle:
        return ui.Rect.fromLTWH(dx + result.left - right / 2, dy + result.top,
            result.width, result.height);
      case SITextAnchor.end:
        return ui.Rect.fromLTWH(dx + result.left - right, dy + result.top,
            result.width, result.height);
    }
  }

  double _getWidth() {
    double w = 0;
    for (final span in spans) {
      final b = span._bounds;
      w += b.width;
    }
    return w;
  }

  @override
  void build<PathDataT>(
      CanonicalizedData<SIImage> canon, SIBuilder<PathDataT, SIImage> builder) {
    final xIndex = canon.floatValues[dx];
    final yIndex = canon.floatValues[dy];
    builder.textMultiSpanChunk(null, xIndex, yIndex, textAnchor);
    for (final span in spans) {
      assert(span.attributes.textAnchor == SITextAnchor.start);
      span.build(canon, builder);
    }
    builder.textEnd(null);
  }

  @override
  void paint(SIText parent, ui.Canvas c, Color currentColor) {
    c.save();
    switch (textAnchor) {
      case SITextAnchor.start:
        c.translate(dx, dy);
        break;
      case SITextAnchor.middle:
        c.translate(dx - _getWidth() / 2, dy);
        break;
      case SITextAnchor.end:
        c.translate(dx - _getWidth(), dy);
        break;
    }
    for (final span in spans) {
      span.paint(parent, c, currentColor);
      c.translate(span._bounds.width, 0);
    }
    c.restore();
  }

  @override
  bool operator ==(final Object other) {
    if (identical(this, other)) {
      return true;
    } else if (other is! SIMultiSpanChunk) {
      return false;
    } else {
      return dx == other.dx && dy == other.dy && spans.equals(other.spans);
    }
  }

  @override
  int get hashCode => Object.hash(dx, dy, Object.hashAll(spans));
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

  static Point<double> _tp(Point<double> p, Affine x) => x.transformed(p);

  PruningBoundary transformed(Affine x) =>
      PruningBoundary._p(_tp(a, x), _tp(b, x), _tp(c, x), _tp(d, x));
}

class Transformer {
  static PruningBoundary? transformBoundaryFromChildren(
      Affine? transform, PruningBoundary? b) {
    if (b != null && transform != null) {
      return b.transformed(transform);
    } else {
      return b;
    }
  }

  static PruningBoundary? transformBoundaryFromParent(
      Affine? transform, PruningBoundary? b) {
    if (b == null) {
      return b;
    }
    if (transform != null) {
      final reverseXform = transform.mutableCopy()..invert();
      return b.transformed(reverseXform);
    } else {
      return b;
    }
  }
}
