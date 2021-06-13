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

abstract class ScalableImage extends _PackageInitializer {
  final double? width;
  final double? height;
  Rect? _viewport;
  final BlendMode tintMode;
  final Color? tintColor;

  ///
  /// The images within this [ScalableImage].
  ///
  @protected
  final List<SIImage> images;

  ///
  /// The currentColor value, as defined by
  /// [Tiny s. 11.2](https://www.w3.org/TR/2008/REC-SVGTiny12-20081222/painting.html#SpecifyingPaint).
  /// This is a color value in an SVG document for elements whose color is
  /// controlled by the SVG's container.
  ///
  final Color currentColor;

  @protected
  ScalableImage(this.width, this.height, this.tintColor, this.tintMode,
      this._viewport, this.images, Color? currentColor)
      : currentColor = currentColor ?? Colors.black;

  @protected
  ScalableImage.modifiedFrom(ScalableImage other,
      {required Rect? viewport,
      required Color currentColor,
      required Color? tintColor,
      required BlendMode tintMode,
      List<SIImage>? images})
      : width = viewport?.width ?? other.width,
        height = viewport?.height ?? other.height,
        _viewport = _newViewport(viewport, other._viewport),
        tintMode = tintMode,
        tintColor = tintColor,
        images = images ?? other.images,
        currentColor = currentColor {
    print("@@@@ images from ${other.images.length} to ${this.images.length}");
  }

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
      {bool prune = false, double pruningTolerance = 0});

  ///
  /// Return a new ScalableImage like this one, with tint modified.
  ///
  ScalableImage modifyTint(
      {required BlendMode newTintMode, required Color? newTintColor});

  ///
  /// Return a new ScalableImage like this one, with currentColor
  /// modified.
  ///
  ScalableImage modifyCurrentColor(Color newCurrentColor);

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
  /// Create an image from a `.si` file in an asset bundle.
  /// Loading a `.si` file is considerably faster than parsing an SVG
  /// or AVD file - about 30x faster in informal measurements.  A `.si`
  /// file can be created with `dart run jovial_svg:svg_to_si` or
  /// `dart run jovial_svg:avd_to_si`.
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
  /// Create an image from the contents of a .si file in a ByteData.
  /// Loading a `.si` file is considerably faster than parsing an SVG
  /// or AVD file - about 30x faster in informal measurements.  A `.si`
  /// file can be created with `dart run jovial_svg:svg_to_si` or
  /// `dart run jovial_svg:avd_to_si`.
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
  /// Parse an SVG XML string to a scalable image
  ///
  static ScalableImage fromSvgString(String src,
      {bool compact = false,
      bool bigFloats = false,
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
  /// from [b] and parse it into a scalable image.
  ///
  static Future<ScalableImage> fromSvgAsset(AssetBundle b, String key,
      {bool compact = false,
      bool bigFloats = false,
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
  /// Read a stream containing an SVG
  /// and parse it into a scalable image.
  ///
  static Future<ScalableImage> fromSvgStream(Stream<String> stream,
      {bool compact = false, bool bigFloats = false, bool warn = true}) async {
    if (compact) {
      final b = SICompactBuilder(warn: warn, bigFloats: bigFloats);
      await StreamSvgParser(stream, b).parse();
      return b.si;
    } else {
      final b = SIDagBuilder(warn: warn);
      await StreamSvgParser(stream, b).parse();
      return b.si;
    }
  }

  ///
  /// Parse an Android Vector Drawable XML string to a scalable image.
  ///
  static ScalableImage fromAvdString(String src,
      {bool compact = false, bool bigFloats = false, bool warn = true}) {
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
  /// from [b] and parse it into a scalable image.
  ///
  static Future<ScalableImage> fromAvdAsset(AssetBundle b, String key,
      {bool compact = false, bool bigFloats = false, bool warn = true}) async {
    final src = await b.loadString(key, cache: false);
    return fromAvdString(src,
        compact: compact, bigFloats: bigFloats, warn: warn);
  }

  ///
  /// Read a stream containing an Android Vector Drawable in XML format
  /// and parse it into a scalable image.
  ///
  static Future<ScalableImage> fromAvdStream(Stream<String> stream,
      {bool compact = false, bool bigFloats = false, bool warn = true}) async {
    if (compact) {
      final b = SICompactBuilder(warn: warn, bigFloats: bigFloats);
      await StreamAvdParser(stream, b).parse();
      return b.si;
    } else {
      final b = SIDagBuilder(warn: warn);
      await StreamAvdParser(stream, b).parse();
      return b.si;
    }
  }

  ///
  /// Prepare any images in the ScalableImage, by decoding them.  If this is
  /// not done, images will be invisible (unless a different ScalableImage that
  /// has been prepared shares the image instances, as could happen with
  /// viewport setting.).  This method may be called multiple
  /// times on the same ScalingImage.  Each call to prepareImages() must be
  /// balanced with a call to `unprepareImages()` to release the image
  /// resources -- see `Image.dispose()` in the Flutter library.
  ///
  Future<void> prepareImages() async {
    // Start preparing them all, with no await, so that the prepare count
    // is immediately incremented.
    final waiting = List<Future<void>>.generate(
        images.length, (i) => images[i].prepare());
    for (final w in waiting) {
      await w;
    }
  }

  ///
  /// Undo the effects of [prepareImages], releasing resources.
  ///
  void unprepareImages() {
    for (final im in images) {
      im.unprepare();
    }
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

class _PackageInitializer {
  static bool _first = true;
  static const _licenseText = '''
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
POSSIBILITY OF SUCH DAMAGE.''';
  _PackageInitializer() {
    if (_first) {
      _first = false;
      LicenseRegistry.addLicense(_getLicense);
    }
  }

  static Stream<LicenseEntry> _getLicense() async* {
    yield LicenseEntryWithLineBreaks(['jovial_svg'], _licenseText);
  }
}
