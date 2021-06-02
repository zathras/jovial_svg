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

library jovial_svg.widget;

import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:pedantic/pedantic.dart';
import 'package:quiver/core.dart' as quiver;

import 'jovial_svg.dart';

abstract class ScalableImageWidget extends StatefulWidget {
  ScalableImageWidget._p(Key? key) : super(key: key);

  ///
  /// Create a lightweight widget to display a pre-loaded [ScalableImage].
  ///
  /// If the [ScalableImage] contains embedded images, it is recommended
  /// that the caller await a call to [ScalableImage.prepareImages()] before
  /// creating the widget.  See also [ScalableImage.unprepareImages()].  If
  /// this is not done, there might be a delay after the widget is created
  /// while the image(s) are decoded.
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
  /// Create a widget to load and then render an [ScalableImage].  In a production
  /// application, pre-loading te [ScalableImage] is preferable, because the
  /// asynchronous loading might cause a momentary flash.
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
  final _SIPainter _painter;
  final Size _size;
  final ScalableImage _si;

  _SyncSIWidget(Key? key, ScalableImage si, BoxFit fit, Alignment alignment,
      bool clip, double scale)
      : _painter = _SIPainter(si, fit, alignment, clip),
        _size = Size(si.viewport.width * scale, si.viewport.height * scale),
        _si = si,
        super._p(key);

  @override
  State<StatefulWidget> createState() => _SyncSIWidgetState();
}

class _SyncSIWidgetState extends State<_SyncSIWidget> {

  _SyncSIWidgetState();

  @override
  void initState() {
    super.initState();
    _registerWithFuture(widget._si.prepareImages());
  }

  @override
  void didUpdateWidget(_SyncSIWidget old) {
    _registerWithFuture(widget._si.prepareImages());
    old._si.unprepareImages();
  }

  @override
  void dispose() {
    super.dispose();
    widget._si.unprepareImages();
  }

  void _registerWithFuture(final Future<void> f) {
    unawaited(f.then((void _) => setState(() {})));
  }

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: widget._painter, size: widget._size);
}

class _SIPainter extends CustomPainter {
  final ScalableImage _si;
  final BoxFit _fit;
  final Alignment _alignment;
  final bool _clip;

  _SIPainter(this._si, this._fit, this._alignment, this._clip);

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
    canvas.translate(
        (1 + _alignment.x) * extraX / 2, (1 + _alignment.y) * extraY / 2);
    canvas.scale(sx, sy);
    _si.paint(canvas);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
  // We are immutable, and we never change parent
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
/// An asynchronous source of an [ScalableImage]
///
abstract class ScalableImageSource {
  Future<ScalableImage> get si;

  ///
  /// Compare this source to another.  Subclasses must override this, so that
  /// different instances equivalent sources give true.  This will avoid
  /// unnecessary rebuilding of [ScalableImage] objects.
  ///
  @override
  bool operator ==(Object other);

  @override
  int get hashCode;

  ///
  /// Get an [ScalableImage] by parsing an Android Vector Drawable XML file.  In
  /// a production app, it's better to pre-compile the file -- see
  /// [ScalableImageSource.fromSI]
  ///
  static ScalableImageSource fromAvd(AssetBundle bundle, String key) =>
      _AvdBundleSource(bundle, key);

  static ScalableImageSource fromSvg(AssetBundle bundle, String key,
          {Color? currentColor}) =>
      _SvgBundleSource(bundle, key, currentColor);

  static ScalableImageSource fromSI(AssetBundle bundle, String key,
          {Color? currentColor}) =>
      _SIBundleSource(bundle, key, currentColor);
}

class _AvdBundleSource extends ScalableImageSource {
  final AssetBundle bundle;
  final String key;

  _AvdBundleSource(this.bundle, this.key);

  @override
  Future<ScalableImage> get si => ScalableImage.fromAvdAsset(bundle, key);

  @override
  bool operator ==(final Object other) {
    if (other is _AvdBundleSource) {
      return bundle == other.bundle && key == other.key;
    } else {
      return false;
    }
  }

  @override
  int get hashCode => quiver.hash2(bundle.hashCode, key.hashCode);
}

class _SvgBundleSource extends ScalableImageSource {
  final AssetBundle bundle;
  final String key;
  final Color? currentColor;

  _SvgBundleSource(this.bundle, this.key, this.currentColor);

  @override
  Future<ScalableImage> get si =>
      ScalableImage.fromSvgAsset(bundle, key, currentColor: currentColor);

  @override
  bool operator ==(final Object other) {
    if (other is _SvgBundleSource) {
      return bundle == other.bundle &&
          key == other.key &&
          currentColor == other.currentColor;
    } else {
      return false;
    }
  }

  @override
  int get hashCode => quiver.hash3(bundle, key, currentColor);
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
  int get hashCode => quiver.hash3(bundle, key, currentColor);
}
