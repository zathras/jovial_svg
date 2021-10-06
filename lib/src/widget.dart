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

import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
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
  const ScalableImageWidget._p(Key? key) : super(key: key);

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
  /// production application, pre-loading the [ScalableImage] and using
  /// the default constructor is usually preferable, because the
  /// asynchronous loading that is necessary with an asynchronous
  /// source might cause a momentary flash.  If the widget is frequently
  /// rebuilt, it is generally recommended to provide a [cache] with an
  /// appropriate lifetime and size.
  ///
  /// For a discussion of caching and potential reloading, see
  /// https://github.com/zathras/jovial_svg/issues/10.
  ///
  /// [fit] controls how the scalable image is scaled within the widget.  If
  /// fit does not control scaling, then [scale] is used.
  ///
  /// [alignment] sets the alignment of the scalable image within the widget.
  ///
  /// [clip], if true, will cause the widget to enforce the boundaries of
  /// the scalable image.
  ///
  /// [cache] can used to share [ScalableImage] instances, and avoid excessive
  /// reloading.  If null, a default cache that retains no unreferenced
  /// images is used.
  ///
  factory ScalableImageWidget.fromSISource(
          {Key? key,
          required ScalableImageSource si,
          BoxFit fit = BoxFit.contain,
          Alignment alignment = Alignment.center,
          bool clip = true,
          double scale = 1,
          ScalableImageCache? cache}) =>
      _AsyncSIWidget(key, si, fit, alignment, clip, scale,
          cache ?? ScalableImageCache._defaultCache);
}

class _SyncSIWidget extends ScalableImageWidget {
  final ScalableImage _si;
  final BoxFit _fit;
  final Alignment _alignment;
  final bool _clip;
  final double _scale;

  const _SyncSIWidget(
      Key? key, this._si, this._fit, this._alignment, this._clip, this._scale)
      : super._p(key);

  @override
  State<StatefulWidget> createState() => _SyncSIWidgetState();
}

class _SyncSIWidgetState extends State<_SyncSIWidget> {
  late _SIPainter _painter;
  late Size _size;

  static _SIPainter _newPainter(_SyncSIWidget w, bool preparing) =>
      _SIPainter(w._si, w._fit, w._alignment, w._clip, preparing);

  static Size _newSize(_SyncSIWidget w) =>
      Size(w._si.viewport.width * w._scale, w._si.viewport.height * w._scale);

  @override
  void initState() {
    super.initState();
    _painter = _newPainter(widget, true);
    _size = _newSize(widget);
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
    unawaited(f.then((void _) {
      if (mounted) {
        setState(() {
          _painter = _newPainter(widget, false);
        });
      }
    }));
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
  final ScalableImageCache _cache;

  const _AsyncSIWidget(Key? key, this._siSource, this._fit, this._alignment,
      this._clip, this._scale, this._cache)
      : super._p(key);

  @override
  State<StatefulWidget> createState() => _AsyncSIWidgetState();
}

class _AsyncSIWidgetState extends State<_AsyncSIWidget> {
  ScalableImage? _si;

  @override
  void initState() {
    super.initState();
    Future<ScalableImage> si = widget._cache.addReference(widget._siSource);
    _registerWithFuture(widget._siSource, si);
  }

  @override
  void dispose() {
    super.dispose();
    widget._cache.removeReference(widget._siSource);
  }

  @override
  void didUpdateWidget(_AsyncSIWidget old) {
    super.didUpdateWidget(old);
    if (old._siSource != widget._siSource) {
      widget._cache.removeReference(old._siSource);
      Future<ScalableImage> si = widget._cache.addReference(widget._siSource);
      _si = null;
      _registerWithFuture(widget._siSource, si);
    }
  }

  void _registerWithFuture(ScalableImageSource src, Future<ScalableImage> si) {
    unawaited(si.then((ScalableImage a) {
      if (mounted && widget._siSource == src) {
        // If it's not stale, perhaps due to reparenting
        setState(() => _si = a);
      }
    }));
  }

  @override
  Widget build(BuildContext context) {
    final si = _si;
    if (si == null) {
      return const SizedBox(width: 1, height: 1);
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
  ///
  /// Get the ScalableImage from this source.  If called multiple times, this
  /// method should return the same [Future] instance.
  ///
  /// NOTE:  For backwards compatibility reasons, callers should not rely on
  /// getting the same future for subsequent calls, because
  /// this requirement was not documented in earlier versions of this library.
  /// However, all implementers of [ScalableImageSource] in the `jovial_svg`
  /// library do return the same instance, which can be helpful for instance
  /// sharing between image caches.
  ///
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
  Future<ScalableImage>? _si;

  _AvdBundleSource(this.bundle, this.key,
      {required this.compact, required this.bigFloats, required this.warn});

  @override
  Future<ScalableImage> get si =>
      _si ??
      (_si = ScalableImage.fromAvdAsset(bundle, key,
          compact: compact, bigFloats: bigFloats, warn: warn));

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
  Future<ScalableImage>? _si;

  _SvgBundleSource(this.bundle, this.key, this.currentColor,
      {required this.compact, required this.bigFloats, required this.warn});

  @override
  Future<ScalableImage> get si =>
      _si ??
      (_si = ScalableImage.fromSvgAsset(bundle, key,
          currentColor: currentColor,
          compact: compact,
          bigFloats: bigFloats,
          warn: warn));

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

  @override
  String toString() =>
      '_SVGBundleSource($key $bundle $compact $bigFloats $warn $currentColor)';
}

class _SvgHttpSource extends ScalableImageSource {
  final Uri url;
  final Color? currentColor;
  final bool compact;
  final bool bigFloats;
  final bool warn;
  Future<ScalableImage>? _si;

  _SvgHttpSource(this.url, this.currentColor,
      {required this.compact, required this.bigFloats, required this.warn});

  @override
  Future<ScalableImage> get si =>
      _si ??
      (_si = ScalableImage.fromSvgHttpUrl(url,
          currentColor: currentColor,
          compact: compact,
          bigFloats: bigFloats,
          warn: warn));

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

  @override
  String toString() =>
      '_SVGHttpSource($url $compact $bigFloats $warn $currentColor)';

}

class _SIBundleSource extends ScalableImageSource {
  final AssetBundle bundle;
  final String key;
  final Color? currentColor;
  Future<ScalableImage>? _si;

  _SIBundleSource(this.bundle, this.key, this.currentColor);

  @override
  Future<ScalableImage> get si =>
      _si ??
      (_si =
          ScalableImage.fromSIAsset(bundle, key, currentColor: currentColor));

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

  @override
  String toString() =>
      '_SIBundleSource($key $bundle $currentColor)';
}

// An entry in the cache, which might be held on the LRU list.  The LRU list
// is doubly-linked and wraps around to a dummy head node.
//
// Flutter's LinkedListEntry<T> didn't quite fit, and it's not like a
// doubly-linked list is hard, anyway.
class _CacheEntry {
  ScalableImageSource? _siSrc;
  Future<ScalableImage>? _si;
  int _refCount = 0;
  _CacheEntry? _moreRecent;
  _CacheEntry? _lessRecent;
  // Invariant:  If refCount is 0, _moreRecent and _lessRecent are non-null
  // Invariant:  If _moreRecent is non-null, refCount > 0
  // Invariant:  If _lessRecent is non-null, refCount > 0
}

///
/// An LRU cache of [ScalableImage] futures derived from [ScalableImageSource]
/// instances.  A cache with a non-zero size could make
/// sense, for example,  as part of the state of a
/// stateful widget that builds entries on demand, and that uses
/// [ScalableImageWidget.fromSISource] to asynchronously load scalable images.
/// See, for example, `cache.dart` in the `example` directory.
///
/// For a discussion of caching and potential reloading, see
/// https://github.com/zathras/jovial_svg/issues/10.
///
class ScalableImageCache {
  final _canonicalized = <ScalableImageSource, _CacheEntry>{};

  int _size;

  // List of unreferenced ScalableImageSource instances, stored as a
  // doubly-linked list with a dummy head node.  The most recently
  // used is _lruList._lessRecent, and the least recently used is
  // _lruList._moreRecent.
  final _lruList = _CacheEntry();

  ///
  /// Create an image cache that holds up to [size] image sources.
  /// A [ScalableImageCache] will always keep referenced [ScalableImageSource]
  /// instances, even if this exceeds the cache size.  In this case, no
  /// unreferenced images would be kept.
  ///
  ScalableImageCache({int size = 0}) : _size = size {
    _lruList._lessRecent = _lruList;
    _lruList._moreRecent = _lruList;
  }

  ///
  /// A default cache.  By default, this cache holds zero unreferenced
  /// image sources.
  ///
  /// This isn't exposed.  On balance, the extremely slight chance of slightly
  /// more convenient instance-sharing isn't worth the slight chance that
  /// someone might think it's OK to change the size to something bigger
  /// than zero, and thereby potentially cause other modules to consume
  /// memory with large, retained assets.
  ///
  static final _defaultCache = ScalableImageCache(size: 0);

  ///
  /// The size of the cache.  If the cache holds unreferenced images, the total
  /// number of images will be held to this size.
  ///
  int get size => _size;
  set size(int val) {
    if (val < 0) {
      throw ArgumentError.value(val, 'cache size');
    }
    _size = size;
    _trimLRU();
  }

  ///
  /// Called when a [ScalableImageSource] is referenced,
  /// e.g. in a stateful widget's [State] object's `initState` method.
  /// Returns a Future for the scalable image.  Always
  /// returns the same Future as previously returned if the given source is
  /// in the cache.
  ///
  /// Application code should use the returned future, and not use
  /// [ScalableImageSource.si] directly.
  ///
  Future<ScalableImage> addReference(ScalableImageSource src) {
    _CacheEntry? e = _canonicalized[src];
    if (e == null) {
      e = _CacheEntry();
      e._siSrc = src;
      e._si = src.si;
      _canonicalized[src] = e;
    } else {
      _verifyCorrectHash(src, e._siSrc!);
      if (e._lessRecent != null) {
        // Now it's referenced, so we take it off the LRU list.
        assert(e._refCount == 0);
        e._lessRecent!._moreRecent = e._moreRecent;
        e._moreRecent!._lessRecent = e._lessRecent;
        e._lessRecent = e._moreRecent = null;
      } else {
        assert(e._refCount > 0);
      }
    }
    e._refCount++;
    return e._si!;
  }

  void _verifyCorrectHash(ScalableImageSource key, ScalableImageSource found) {
    if (key != found) {
      // Very unexpected; I think this would require a bug in Map.
      throw ArgumentError('Found key $found that is != search: $key');
    }
    if (key.hashCode != found.hashCode) {
      throw ArgumentError('Key $key hash ${key.hashCode} is == existing key '
          '$found, hash ${found.hashCode}');
    }
  }

  ///
  /// Called when a source is derereferenced,
  /// e.g. by a stateful widget's [State] object being disposed.
  ///
  void removeReference(ScalableImageSource src) {
    _CacheEntry? e = _canonicalized[src];
    if (e == null) {
      throw ArgumentError.value(src, 'ScalableImageSource',
          'Expected value not in cache:  suspected bad hashCode');
    }
    assert(e._refCount > 0);
    assert(e._lessRecent == null);
    assert(e._moreRecent == null);
    e._refCount--;
    if (e._refCount == 0) {
      _addToLRU(e);
    }
  }

  void _addToLRU(_CacheEntry e) {
    assert(e._moreRecent == null);
    if (_size > 0) {
      // e is now the most recent.  _lruList.lessRecent points to the
      // most recent, and _lruList.moreRecent points to the least recent.
      // Remember, the list wraps around at the dummy head node.
      e._moreRecent = _lruList;
      e._lessRecent = _lruList._lessRecent;
      _lruList._lessRecent!._moreRecent = e;
      _lruList._lessRecent = e;

      _trimLRU();
    }
  }

  void _trimLRU() {
    while (_lruList._lessRecent != _lruList && _canonicalized.length > _size) {
      // While lruList isn't empty, and we're over our capacity
      final victim = _lruList._moreRecent!; // That's the least recently used
      assert(victim != _lruList);
      final _CacheEntry? removed = _canonicalized.remove(victim._siSrc);
      assert(identical(removed, victim));
      assert(victim._refCount == 0);
      victim._moreRecent!._lessRecent = victim._lessRecent;
      victim._lessRecent!._moreRecent = victim._moreRecent;
    }
  }
}
