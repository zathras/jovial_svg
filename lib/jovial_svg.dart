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

library jovial_svg;

import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'src/avd_parser.dart';
import 'src/common.dart';
import 'src/compact.dart';
import 'src/dag.dart';
import 'src/svg_parser.dart';

abstract class ScalableImage {
  final double? width;
  final double? height;
  Rect? _viewport;
  final BlendMode tintMode;
  final Color? tintColor;

  ///
  /// The currentColor value, as defined by
  /// [Tiny s. 11.2](https://www.w3.org/TR/2008/REC-SVGTiny12-20081222/painting.html#SpecifyingPaint).
  /// This is a color value in an SVG document for elements whose color is
  /// controlled by the SVG's container.
  ///
  final Color currentColor; // cf. Tiny s. 11.2

  @protected
  ScalableImage(this.width, this.height, this.tintColor, this.tintMode,
      this._viewport, Color? currentColor)
      : currentColor = currentColor ?? Colors.black;

  @protected
  ScalableImage.modified(ScalableImage other,
      {Rect? viewport, Color? currentColor})
      : width = viewport?.width ?? other.width,
        height = viewport?.height ?? other.height,
        _viewport = _newViewport(viewport, other._viewport),
        tintMode = other.tintMode,
        tintColor = other.tintColor,
        currentColor = currentColor ?? other.currentColor;

  static Rect? _newViewport(Rect? incoming, Rect? old) {
    if (incoming == null) {
      return old;
    } else {
      return incoming;
    }
  }

  /// Give the viewport for this scalable image.  By default, it's determined
  /// by the parameters in the original asset, but see also
  /// [ScalableImage.withNewViewport]
  Rect get viewport {
    if (_viewport != null) {
      return _viewport!;
    }
    double? w = width;
    double? h = height;
    if (w != null && h != null) {
      return _viewport = Rect.fromLTWH(0, 0, w, h);
    }
    return getBoundary()?.getBounds() ?? Rect.zero;
  }

  PruningBoundary? getBoundary();

  ///
  /// Return a copy of this SI with a different viewport.
  /// The bulk of the data is shared between the original and the copy.
  /// If prune is true, it attempts to prune paths that are outside of
  /// the new viewport.
  ///
  /// Pruning is an expensive operation.  There might be edge cases where
  /// it is overly aggressive:  It assumes that the rendered path is completely
  /// contained within the bounding box given by Flutter's Path.boundingBox,
  /// plus any applicable strokeWidth.
  ///
  /// The pruning tolerance allows you to prune away paths that are
  /// just slightly within the new viewport.  A positive sub-pixel
  /// tolerance might reduce the size of the new image with no
  /// visual impact.
  ScalableImage withNewViewport(Rect viewport,
      {bool prune = true, double pruningTolerance = 0});

  ///
  /// Returns this SI as an in-memory directed acyclic graph of nodes.
  /// As compared to a compact scalable image, the DAG representation can
  /// be expected to render somewhat faster, at a significant cost in
  /// memory.  In informal measurements, the DAG representation rendered
  /// about 3x faster.  Building a graph structure out of Dart objects might
  /// increase memory usage by an order of magnitude.
  ///
  /// If this image is already a DAG, this method just returns it.
  ///
  ScalableImage toDag();

  ///
  /// Load a compact image from a .si file.  The result can be converted
  /// into an in-memory graph structure that renders faster by calling
  /// [ScalableImage.toDag].
  ///
  static Future<ScalableImage> fromSIAsset(AssetBundle b, String key,
      {bool compact = false, Color? currentColor}) async {
    final ByteData data = await b.load(key);
    final c =
        ScalableImageCompact.fromByteData(data, currentColor: currentColor);
    if (compact) {
      return c;
    } else {
      return c.toDag();
    }
  }

  ///
  ///  Create an image from the contents of a .si file in a ByteData.
  ///  The result can be converted into an in-memory graph structure that
  ///  renders faster by calling [ScalableImage.toDag].
  ///
  static ScalableImage fromSIBytes(Uint8List bytes,
      {bool compact = false, Color? currentColor}) {
    final r = ScalableImageCompact.fromBytes(bytes, currentColor: currentColor);
    if (compact) {
      return r;
    } else {
      return r.toDag();
    }
  }

  ///
  /// Parse an SVG XML string to an in-memory scalable image
  ///
  static ScalableImage fromSvgString(String src,
      {bool compact = false,
      bool bigFloats = true,
      bool warn = true,
      Color? currentColor}) {
    if (compact) {
      final b = SICompactBuilder(
          warn: warn, currentColor: currentColor, bigFloats: bigFloats);
      StringSvgParser(src, b).parse();
      return b.si;
    } else {
      final b = SIDagBuilder(warn: warn, currentColor: currentColor);
      StringSvgParser(src, b).parse();
      return b.si;
    }
  }

  ///
  /// Load a string asset containing an SVG
  /// from [b] and parse it into an in-memory scalable image.
  ///
  static Future<ScalableImage> fromSvgAsset(AssetBundle b, String key,
      {bool compact = false,
      bool bigFloats = true,
      bool warn = true,
      Color? currentColor}) async {
    final String src = await b.loadString(key, cache: false);
    return fromSvgString(src,
        compact: compact,
        bigFloats: bigFloats,
        warn: warn,
        currentColor: currentColor);
  }

  ///
  /// Parse an Android Vector Drawable XML string to an in-memory scalable image
  ///
  static ScalableImage fromAvdString(String src,
      {bool compact = false, bool bigFloats = true, bool warn = true}) {
    if (compact) {
      final b = SICompactBuilder(warn: warn, bigFloats: bigFloats);
      StringAvdParser(src, b).parse();
      return b.si;
    } else {
      final b = SIDagBuilder(warn: warn);
      StringAvdParser(src, b).parse();
      return b.si;
    }
  }

  ///
  /// Load a string asset containing an Android Vector Drawable in XML format
  /// from [b] and parse it into an in-memory scalable image.
  ///
  static Future<ScalableImage> fromAvdAsset(AssetBundle b, String key,
      {bool compact = false, bool bigFloats = true, bool warn = true}) async {
    final src = await b.loadString(key, cache: false);
    return fromAvdString(src,
        compact: compact, bigFloats: bigFloats, warn: warn);
  }

  void paint(Canvas c) {
    Rect vp = viewport;
    c.translate(-vp.left, -vp.top);
    c.clipRect(vp);
    paintChildren(c, currentColor);
    final tc = tintColor;
    if (tc != null) {
      c.drawColor(tc, tintMode);
    }
  }

  @protected
  void paintChildren(Canvas c, Color currentColor);
}
