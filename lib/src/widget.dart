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
/// Internal widget library - exported with jovial_svg
///
library jovial_svg.widget;

import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:pedantic/pedantic.dart';
import 'package:quiver/core.dart' as quiver;

import 'exported.dart';

///
/// A widget for displaying a [ScalableImage].  The image can be
/// automatically scaled by the widget, and fit into the available area
/// with a `BoxFit` and an `Alignment`.
///
/// Note that rendering a scalable image can be time-consuming if the
/// underlying scene is complex.  Notably, GPU performance can be a
/// bottleneck.  If animations are played over an unchanging [ScalableImage],
/// wrapping the
/// [ScalableImageWidget] in Flutter's `RepaintBoundary`
/// might result in significantly better performance.
///
abstract class ScalableImageWidget extends StatefulWidget {
  ScalableImageWidget._p(Key? key) : super(key: key);

  ///
  /// Create a widget to display a pre-loaded [ScalableImage].
  /// This is the preferred constructor, because the widget can display the
  /// SI immediately.  It does, however, place responsibility for any
  /// asynchronous loading on the caller.
  ///
  /// If the [ScalableImage] contains embedded images, it is recommended
  /// that the caller await a call to [ScalableImage.prepareImages()] before
  /// creating the widget.  See also [ScalableImage.unprepareImages()].  If
  /// this is not done, there might be a delay after the widget is created
  /// while the image(s) are decoded.
  ///
  /// [fit] controls how the scalable image is scaled within the widget.  If
  /// fit does not control scaling, then [scale] is used.
  ///
  /// [alignment] sets the alignment of the scalable image within the widget.
  ///
  /// [clip], if true, will cause the widget to enforce the boundaries of
  /// the scalable image.
  ///
  factory ScalableImageWidget(
          {Key? key,
          required ScalableImage si,
          BoxFit fit = BoxFit.contain,
          Alignment alignment = Alignment.center,
          bool clip = true,
          double scale = 1}) =>
      _SyncSIWidget(key, si, fit, alignment, clip, scale);

  ///
  /// Create a widget to load and then render an [ScalableImage].  In a
  /// production application, pre-loading the [ScalableImage] is preferable,
  /// because the asynchronous loading that is necessary with an asynchronous
  /// source might cause a momentary flash.
  ///
  /// [fit] controls how the scalable image is scaled within the widget.  If
  /// fit does not control scaling, then [scale] is used.
  ///
  /// [alignment] sets the alignment of the scalable image within the widget.
  ///
  /// [clip], if true, will cause the widget to enforce the boundaries of
  /// the scalable image.
  ///
  factory ScalableImageWidget.fromSISource(
          {Key? key,
          required ScalableImageSource si,
          BoxFit fit = BoxFit.contain,
          Alignment alignment = Alignment.center,
          bool clip = true,
          double scale = 1}) =>
      _AsyncSIWidget(key, si, fit, alignment, clip, scale);
}

class _SyncSIWidget extends ScalableImageWidget {
  final ScalableImage _si;
  final BoxFit _fit;
  final Alignment _alignment;
  final bool _clip;
  final double _scale;

  _SyncSIWidget(
      Key? key, this._si, this._fit, this._alignment, this._clip, this._scale)
      : super._p(key);

  @override
  State<StatefulWidget> createState() => _SyncSIWidgetState(this);
}

class _SyncSIWidgetState extends State<_SyncSIWidget> {
  _SIPainter _painter;
  Size _size;

  _SyncSIWidgetState(_SyncSIWidget initial)
      : _painter = _newPainter(initial, true),
        _size = _newSize(initial);

  static _SIPainter _newPainter(_SyncSIWidget w, bool preparing) =>
      _SIPainter(w._si, w._fit, w._alignment, w._clip, preparing);

  static Size _newSize(_SyncSIWidget w) =>
      Size(w._si.viewport.width * w._scale, w._si.viewport.height * w._scale);

  @override
  void initState() {
    super.initState();
    _registerWithFuture(widget._si.prepareImages());
  }

  @override
  void didUpdateWidget(_SyncSIWidget old) {
    super.didUpdateWidget(old);
    _painter = _newPainter(widget, true);
    _size = _newSize(widget);
    _registerWithFuture(widget._si.prepareImages());
    old._si.unprepareImages();
  }

  @override
  void dispose() {
    super.dispose();
    widget._si.unprepareImages();
  }

  void _registerWithFuture(final Future<void> f) {
    unawaited(f.then((void _) => setState(() {
          _painter = _newPainter(widget, false);
        })));
  }

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _painter, size: _size);
}

class _SIPainter extends CustomPainter {
  final ScalableImage _si;
  final BoxFit _fit;
  final Alignment _alignment;
  final bool _clip;
  final bool _preparing;

  _SIPainter(this._si, this._fit, this._alignment, this._clip, this._preparing);

  @override
  void paint(Canvas canvas, Size size) {
    if (_clip) {
      canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));
    }
    if (_fit == BoxFit.none && _alignment == Alignment.topLeft) {
      _si.paint(canvas);
      return;
    }
    final vp = _si.viewport;
    if (vp.width <= 0 || vp.height <= 0) {
      return;
    }
    final double sx;
    final double sy;
    switch (_fit) {
      case BoxFit.fill:
        sx = size.width / vp.width;
        sy = size.height / vp.height;
        break;
      case BoxFit.contain:
        sx = sy = min(size.width / vp.width, size.height / vp.height);
        break;
      case BoxFit.cover:
        sx = sy = max(size.width / vp.width, size.height / vp.height);
        break;
      case BoxFit.fitWidth:
        sx = sy = size.width / vp.width;
        break;
      case BoxFit.fitHeight:
        sx = sy = size.height / vp.height;
        break;
      case BoxFit.none:
        sx = sy = 1;
        break;
      case BoxFit.scaleDown:
        sx = sy = min(1, min(size.width / vp.width, size.height / vp.height));
        break;
    }
    final extraX = size.width - vp.width * sx;
    final extraY = size.height - vp.height * sy;
    final tx = (1 + _alignment.x) * extraX / 2;
    final ty = (1 + _alignment.y) * extraY / 2;
    canvas.translate(tx, ty);
    canvas.scale(sx, sy);
    _si.paint(canvas);
  }

  @override
  bool shouldRepaint(_SIPainter oldDelegate) =>
      _preparing != oldDelegate._preparing ||
      _si != oldDelegate._si ||
      _fit != oldDelegate._fit ||
      _alignment != oldDelegate._alignment ||
      _clip != oldDelegate._clip;
}

class _AsyncSIWidget extends ScalableImageWidget {
  final ScalableImageSource _siSource;
  final BoxFit _fit;
  final Alignment _alignment;
  final bool _clip;
  final double _scale;

  _AsyncSIWidget(Key? key, this._siSource, this._fit, this._alignment,
      this._clip, this._scale)
      : super._p(key);

  @override
  State<StatefulWidget> createState() => _AsyncSIWidgetState();
}

class _AsyncSIWidgetState extends State<_AsyncSIWidget> {
  ScalableImage? _si;

  @override
  void initState() {
    super.initState();
    _registerWithFuture(widget._siSource);
  }

  @override
  void didUpdateWidget(_AsyncSIWidget old) {
    super.didUpdateWidget(old);
    if (old._siSource != widget._siSource) {
      _si = null;
      _registerWithFuture(widget._siSource);
    }
  }

  void _registerWithFuture(final ScalableImageSource src) {
    unawaited(src.si.then((ScalableImage a) {
      if (widget._siSource == src) {
        // If it's not stale, perhaps due to reparenting
        setState(() => _si = a);
      }
    }));
  }

  @override
  Widget build(BuildContext context) {
    final si = _si;
    if (si == null) {
      return Container(width: 1, height: 1);
    } else {
      return _SyncSIWidget(null, si, widget._fit, widget._alignment,
          widget._clip, widget._scale);
    }
  }
}

///
/// An asynchronous source of a [ScalableImage].  This is used for asynchronous
/// loading of an SI asset by a [ScalableImageWidget], e.g
/// from an AssetBundle.  This class may be subclassed by clients of this
/// library, e.g. for loading from other network sources.
///
/// If new subclasses are written, attention is drawn to the need to implement
/// `operator ==` and `hashCode`.
///
abstract class ScalableImageSource {
  Future<ScalableImage> get si;

  ///
  /// Compare this source to another.  Subclasses must override this, so that
  /// different instances of equivalent sources give true.  This avoids
  /// unnecessary rebuilding of [ScalableImage] objects.
  ///
  @override
  bool operator ==(Object other) {
    throw StateError('Must be overridden by subclasses');
  }

  ///
  /// Compute the hash code for this source.  Subclasses must override this,
  /// so that different instances of equivalent sources give the same hash
  /// code.  This will avoid unnecessary rebuilding of [ScalableImage]
  /// objects.
  ///
  @override
  int get hashCode {
    throw StateError('Must be overridden by subclasses');
  }

  ///
  /// Get a [ScalableImage] by parsing an Android Vector Drawable XML file from
  /// an asset bundle.  In
  /// a production app, it's better to pre-compile the file -- see
  /// [ScalableImageSource.fromSI]
  ///
  /// If [compact] is true, the internal representation will occupy
  /// significantly less memory, at the expense of rendering time.  It will
  /// occupy perhaps an order of magnitude less memory, but render perhaps
  /// around 3x slower.  If [bigFloats] is true, the compact representation
  /// will use 8 byte double-precision float values, rather than 4 byte
  /// single-precision values.
  ///
  /// If [warn] is true, warnings will be printed if the AVD asset contains
  /// unrecognized tags and/or tag attributes.
  ///
  static ScalableImageSource fromAvd(AssetBundle bundle, String key,
          {bool compact = false, bool bigFloats = false, bool warn = true}) =>
      _AvdBundleSource(bundle, key,
          compact: compact, bigFloats: bigFloats, warn: warn);

  ///
  /// Get a [ScalableImage] by parsing an SVG XML file from
  /// an asset bundle.  In
  /// a production app, it's better to pre-compile the file -- see
  /// [ScalableImageSource.fromSI]
  ///
  /// If [compact] is true, the internal representation will occupy
  /// significantly less memory, at the expense of rendering time.  It will
  /// occupy perhaps an order of magnitude less memory, but render perhaps
  /// around 3x slower.  If [bigFloats] is true, the compact representation
  /// will use 8 byte double-precision float values, rather than 4 byte
  /// single-precision values.
  ///
  /// If [warn] is true, warnings will be printed if the AVD asset contains
  /// unrecognized tags and/or tag attributes.
  ///
  /// See also [ScalableImage.currentColor].
  ///
  static ScalableImageSource fromSvg(AssetBundle bundle, String key,
          {Color? currentColor,
          bool compact = false,
          bool bigFloats = false,
          bool warn = true}) =>
      _SvgBundleSource(bundle, key, currentColor,
          compact: compact, bigFloats: bigFloats, warn: warn);

  ///
  /// Get a [ScalableImage] by parsing an SVG XML file from
  /// a http: or https: URL.
  ///
  /// If [compact] is true, the internal representation will occupy
  /// significantly less memory, at the expense of rendering time.  It will
  /// occupy perhaps an order of magnitude less memory, but render perhaps
  /// around 3x slower.  If [bigFloats] is true, the compact representation
  /// will use 8 byte double-precision float values, rather than 4 byte
  /// single-precision values.
  ///
  /// If [warn] is true, warnings will be printed if the AVD asset contains
  /// unrecognized tags and/or tag attributes.
  ///
  /// See also [ScalableImage.currentColor].
  ///
  static ScalableImageSource fromSvgHttpUrl(Uri url,
          {Color? currentColor,
          bool compact = false,
          bool bigFloats = false,
          bool warn = true}) =>
      _SvgHttpSource(url, currentColor,
          compact: compact, bigFloats: bigFloats, warn: warn);

  ///
  /// Get a [ScalableImage] by reading a pre-compiled `.si` file.
  /// These files can be produced with
  ///  `dart run jovial_svg:svg_to_si` or `dart run jovial_svg:avd_to_si`.
  ///  Pre-compiled files load about an order of magnitude faster.
  ///
  /// See also [ScalableImage.currentColor].
  ///

  static ScalableImageSource fromSI(AssetBundle bundle, String key,
          {Color? currentColor}) =>
      _SIBundleSource(bundle, key, currentColor);
}

class _AvdBundleSource extends ScalableImageSource {
  final AssetBundle bundle;
  final String key;
  final bool compact;
  final bool bigFloats;
  final bool warn;

  _AvdBundleSource(this.bundle, this.key,
      {required this.compact, required this.bigFloats, required this.warn});

  @override
  Future<ScalableImage> get si => ScalableImage.fromAvdAsset(bundle, key,
      compact: compact, bigFloats: bigFloats, warn: warn);

  @override
  bool operator ==(final Object other) {
    if (other is _AvdBundleSource) {
      return bundle == other.bundle &&
          key == other.key &&
          compact == other.compact &&
          bigFloats == other.bigFloats &&
          warn == other.warn;
    } else {
      return false;
    }
  }

  @override
  int get hashCode =>
      0x94fadcba ^
      quiver.hash4(bundle, key, compact, quiver.hash2(bigFloats, warn));
}

class _SvgBundleSource extends ScalableImageSource {
  final AssetBundle bundle;
  final String key;
  final Color? currentColor;
  final bool compact;
  final bool bigFloats;
  final bool warn;

  _SvgBundleSource(this.bundle, this.key, this.currentColor,
      {required this.compact, required this.bigFloats, required this.warn});

  @override
  Future<ScalableImage> get si => ScalableImage.fromSvgAsset(bundle, key,
      currentColor: currentColor,
      compact: compact,
      bigFloats: bigFloats,
      warn: warn);

  @override
  bool operator ==(final Object other) {
    if (other is _SvgBundleSource) {
      return bundle == other.bundle &&
          key == other.key &&
          currentColor == other.currentColor &&
          compact == other.compact &&
          bigFloats == other.bigFloats &&
          warn == other.warn;
    } else {
      return false;
    }
  }

  @override
  int get hashCode =>
      0x544f0d11 ^
      quiver.hash4(
          bundle, key, currentColor, quiver.hash3(compact, bigFloats, warn));
}

class _SvgHttpSource extends ScalableImageSource {
  final Uri url;
  final Color? currentColor;
  final bool compact;
  final bool bigFloats;
  final bool warn;

  _SvgHttpSource(this.url, this.currentColor,
      {required this.compact, required this.bigFloats, required this.warn});

  @override
  Future<ScalableImage> get si {
    return ScalableImage.fromSvgHttpUrl(url,
        currentColor: currentColor,
        compact: compact,
        bigFloats: bigFloats,
        warn: warn);
  }

  @override
  bool operator ==(final Object other) {
    if (other is _SvgHttpSource) {
      return url == other.url &&
          currentColor == other.currentColor &&
          compact == other.compact &&
          bigFloats == other.bigFloats &&
          warn == other.warn;
    } else {
      return false;
    }
  }

  @override
  int get hashCode =>
      0xf7972f9b ^
      quiver.hash4(url, currentColor, compact, quiver.hash2(bigFloats, warn));
}

class _SIBundleSource extends ScalableImageSource {
  final AssetBundle bundle;
  final String key;
  final Color? currentColor;

  _SIBundleSource(this.bundle, this.key, this.currentColor);

  @override
  Future<ScalableImage> get si =>
      ScalableImage.fromSIAsset(bundle, key, currentColor: currentColor);

  @override
  bool operator ==(final Object other) {
    if (other is _SIBundleSource) {
      return bundle == other.bundle &&
          key == other.key &&
          currentColor == other.currentColor;
    } else {
      return false;
    }
  }

  @override
  int get hashCode => 0xf67cd716 ^ quiver.hash3(bundle, key, currentColor);
}
