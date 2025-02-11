/*
MIT License

Copyright (c) 2021-2025, William Foote

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
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' show min, max;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

import 'cache.dart';
import 'common_noui.dart';
import 'exported.dart';

///
/// A widget for displaying a [ScalableImage].  The image can be
/// automatically scaled by the widget, and fit into the available area
/// with a `BoxFit` and an `Alignment`.  Where loading is required, a
/// [ScalableImageCache] can be provided.
///
/// Note that rendering a scalable image can be time-consuming if the
/// underlying scene is complex.  Notably, GPU performance can be a
/// bottleneck.  If animations are played over an unchanging [ScalableImage],
/// wrapping the
/// [ScalableImageWidget] in Flutter's `RepaintBoundary`
/// might result in significantly better performance.
///
abstract class ScalableImageWidget extends StatefulWidget {
  ///
  /// Whether the underlying `ScalableImage`'s painting is complex enough
  /// to benefit from caching.  This is forwarded to [CustomPaint] -- see
  /// [CustomPaint.isComplex].
  ///
  final bool isComplex;

  final ExportedIDLookup? _lookup;

  const ScalableImageWidget._p(Key? key, this.isComplex, this._lookup)
      : super(key: key);

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
  /// [background], if provided, will be the background color for a layer under
  /// the SVG asset.  In relatively rare circumstances, this can be needed.
  /// For example, browsers generally render an SVG over a white background,
  /// which affects advanced use of the `mix-blend-mode` attribute applied over
  /// areas without other drawing.
  ///
  /// [isComplex] see [ScalableImageWidget.isComplex]
  ///
  /// [lookup] is used to look up node IDs that were exported in an SVG
  /// asset.  See [ExportedIDLookup].
  ///
  factory ScalableImageWidget(
          {Key? key,
          required ScalableImage si,
          BoxFit fit = BoxFit.contain,
          Alignment alignment = Alignment.center,
          bool clip = true,
          double scale = 1,
          Color? background,
          bool isComplex = false,
          ExportedIDLookup? lookup}) =>
      _SyncSIWidget(
          key, si, fit, alignment, clip, scale, background, isComplex, lookup);

  ///
  /// Create a widget to load and then render a [ScalableImage].  In a
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
  /// [reload] forces the [ScalableImage] to be reloaded, e.g. if a networking
  /// error might have been resolved, or if the asset might have changed.
  ///
  /// [isComplex] see [ScalableImageWidget.isComplex]
  ///
  /// [lookup] is used to look up node IDs that were exported in an SVG
  /// asset.  See [ExportedIDLookup].
  ///
  /// [onLoading] is called to give a widget to show while the asset is being
  /// loaded.  It defaults to a 1x1 SizedBox.
  ///
  /// [onError] is called to give a widget to show if the asset has failed
  /// loading.  It defaults to onLoading.
  ///
  /// [switcher], if set, is called when switching to a new widget (either from
  /// nothing to onLoading, or onLoading to either loaded or onError).  A
  /// reasonable choice is to create an `AnimatedSwitcher`.  See, for example,
  /// `example/lib/cache.dart`.
  ///
  /// [currentColor], if provided, sets the [ScalableImage.currentColor] of
  /// the displayed image, using [ScalableImage.modifyCurrentColor] to create
  /// an appropriate [ScalableImage] instance.
  ///
  /// [background], if provided, will be the background color for a layer under
  /// the SVG asset.  In relatively rare circumstances, this can be needed.
  /// For example, browsers generally render an SVG over a white background,
  /// which affects advanced use of the `mix-blend-mode` attribute applied over
  /// areas without other drawing.
  ///
  /// NOTE:  If no cache is provided, a default of size zero is used.
  /// There is no provision for client code to change the size of this default
  /// cache; this is intentional.  Having a system-wide cache would invite
  /// conflicts in the case where two unrelated modules within a single
  /// application attempted to set a cache size.  This could even result in
  /// a too-large cache retaining large SVG assets, perhaps leading to
  /// memory exhaustion.  Any module or application that wishes
  /// to have a global cache can simply hold one in a static data member,
  /// and provide it as the cache parameter to the widgets it manages.
  ///
  factory ScalableImageWidget.fromSISource(
      {Key? key,
      required ScalableImageSource si,
      BoxFit fit = BoxFit.contain,
      Alignment alignment = Alignment.center,
      bool clip = true,
      double scale = 1,
      Color? currentColor,
      Color? background,
      bool reload = false,
      bool isComplex = false,
      ExportedIDLookup? lookup,
      ScalableImageCache? cache,
      Widget Function(BuildContext)? onLoading,
      Widget Function(BuildContext)? onError,
      Widget Function(BuildContext, Widget child)? switcher}) {
    onLoading ??= _AsyncSIWidget.defaultOnLoading;
    onError ??= onLoading;
    cache = cache ?? defaultCache;
    if (reload) {
      cache.forceReload(si);
    }
    return _AsyncSIWidget(
        key,
        si,
        fit,
        alignment,
        clip,
        scale,
        cache,
        onLoading,
        onError,
        switcher,
        currentColor,
        background,
        isComplex,
        lookup);
  }
}

class _SyncSIWidget extends ScalableImageWidget {
  final ScalableImage _si;
  final BoxFit _fit;
  final Alignment _alignment;
  final bool _clip;
  final double _scale;
  final Color? _background;

  const _SyncSIWidget(
      Key? key,
      this._si,
      this._fit,
      this._alignment,
      this._clip,
      this._scale,
      this._background,
      bool isComplex,
      ExportedIDLookup? lookup)
      : super._p(key, isComplex, lookup);

  @override
  State<StatefulWidget> createState() => _SyncSIWidgetState();
}

class _SyncSIWidgetState extends State<_SyncSIWidget> {
  late _SIPainter _painter;
  late Size _preferredSize;

  static _SIPainter _newPainter(_SyncSIWidget w, bool preparing) => _SIPainter(
      w._si,
      w._fit,
      w._alignment,
      w._clip,
      preparing,
      w._background,
      w._lookup);

  static Size _newSize(_SyncSIWidget w) =>
      Size(w._si.viewport.width * w._scale, w._si.viewport.height * w._scale);

  @override
  void initState() {
    super.initState();
    _painter = _newPainter(widget, true);
    _preferredSize = _newSize(widget);
    _registerWithFuture(widget._si.prepareImages());
  }

  @override
  void didUpdateWidget(_SyncSIWidget old) {
    super.didUpdateWidget(old);
    _painter = _newPainter(widget, _painter._preparing);
    _preferredSize = _newSize(widget);
    if (_painter._preparing) {
      // If images are still loading, we need the callback when it's done.
      _registerWithFuture(widget._si.prepareImages());
      old._si.unprepareImages();
    }
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
  Widget build(BuildContext context) => CustomPaint(
      painter: _painter, size: _preferredSize, isComplex: widget.isComplex);
}

class _SIPainter extends CustomPainter {
  final ScalableImage _si;
  final BoxFit _fit;
  final Alignment _alignment;
  final bool _clip;
  final bool _preparing;
  final Color? _background;
  final ExportedIDLookup? _lookup;

  _SIPainter(this._si, this._fit, this._alignment, this._clip, this._preparing,
      this._background, this._lookup);

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Rect.fromLTWH(0, 0, size.width, size.height);
    if (_clip) {
      canvas.clipRect(bounds);
    }
    final background = _background;
    if (background != null) {
      canvas.drawColor(background, BlendMode.src);
      canvas.saveLayer(bounds, Paint());
      canvas.drawColor(const Color(0x00ffffff), BlendMode.src);
    }
    try {
      final xform = ScalingTransform(
          containerSize: size,
          siViewport: _si.viewport,
          fit: _fit,
          alignment: _alignment);
      final lookup = _lookup;
      if (lookup != null) {
        lookup.lastTransform = xform;
        lookup.si = _si;
      }
      canvas.save();
      try {
        xform.applyToCanvas(canvas);
        _si.paint(canvas);
      } finally {
        canvas.restore();
      }
    } finally {
      if (background != null) {
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_SIPainter oldDelegate) =>
      _preparing != oldDelegate._preparing ||
      _si != oldDelegate._si ||
      _fit != oldDelegate._fit ||
      _alignment.x != oldDelegate._alignment.x ||
      _alignment.y != oldDelegate._alignment.y ||
      _clip != oldDelegate._clip;
}

class _AsyncSIWidget extends ScalableImageWidget {
  final ScalableImageSource _siSource;
  final ScalableImageCache _cache;
  final BoxFit _fit;
  final Alignment _alignment;
  final bool _clip;
  final double _scale;
  final Color? _currentColor;
  final Color? _background;
  final Widget Function(BuildContext) _onLoading;
  final Widget Function(BuildContext) _onError;
  final Widget Function(BuildContext, Widget child)? _switcher;

  const _AsyncSIWidget(
      Key? key,
      this._siSource,
      this._fit,
      this._alignment,
      this._clip,
      this._scale,
      this._cache,
      this._onLoading,
      this._onError,
      this._switcher,
      this._currentColor,
      this._background,
      bool isComplex,
      ExportedIDLookup? lookup)
      : super._p(key, isComplex, lookup);

  @override
  State<StatefulWidget> createState() => _AsyncSIWidgetState();

  static Widget defaultOnLoading(BuildContext c) =>
      const SizedBox(width: 1, height: 1);
}

class _AsyncSIWidgetState extends State<_AsyncSIWidget> {
  static final ScalableImage _error = ScalableImage.blank();
  ScalableImage? _si;

  @override
  void initState() {
    super.initState();
    FutureOr<ScalableImage> si = widget._cache.addReferenceV2(widget._siSource);
    if (si is ScalableImage) {
      _si = si;
    } else {
      _registerWithFuture(widget._siSource, si);
    }
  }

  @override
  void dispose() {
    super.dispose();
    widget._cache.removeReference(widget._siSource);
  }

  @override
  void didUpdateWidget(_AsyncSIWidget old) {
    super.didUpdateWidget(old);
    if (old._siSource != widget._siSource || old._cache != widget._cache) {
      FutureOr<ScalableImage> si =
          widget._cache.addReferenceV2(widget._siSource);
      old._cache.removeReference(old._siSource);
      if (si is ScalableImage) {
        _si = si;
      } else {
        _si = null;
        _registerWithFuture(widget._siSource, si);
      }
    }
  }

  void _registerWithFuture(ScalableImageSource src, Future<ScalableImage> si) {
    unawaited(si.then((ScalableImage a) {
      if (mounted && widget._siSource == src) {
        // If it's not stale, perhaps due to reparenting
        setState(() => _si = a);
      }
    }, onError: (Object err) {
      widget._siSource.warnArg('Error loading:  $err');
      if (mounted && widget._siSource == src) {
        setState(() => _si = _error);
      }
    }));
  }

  @override
  Widget build(BuildContext context) {
    var si = _si;
    final Widget result;
    final lookup = widget._lookup;
    if (lookup != null) {
      lookup.si = si; // Null it out if the SI isn't loaded yet
    }
    if (si == null) {
      result = widget._onLoading(context);
    } else if (identical(si, _error)) {
      result = widget._onError(context);
    } else {
      final cc = widget._currentColor;
      if (cc != null) {
        si = si.modifyCurrentColor(cc);
        // Very cheap, just one instance creation
      }
      result = _SyncSIWidget(
          null,
          si,
          widget._fit,
          widget._alignment,
          widget._clip,
          widget._scale,
          widget._background,
          widget.isComplex,
          widget._lookup);
    }
    final switcher = widget._switcher;
    if (switcher == null) {
      return result;
    } else {
      return switcher(context, result);
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
  /// Get the ScalableImage from this source.  If called multiple times, it is
  /// unspecified if the same [Future] instance is returned or not.  Subclasses
  /// need not override this method.  The default implementation throws a
  /// [StateError].  See [createSI].
  ///
  @Deprecated('Use createSI instead')
  Future<ScalableImage> get si => throw StateError('Use createSI() instead');
  // NOTE:  Any subclasses created prior to 1.0.7 will have overridden this
  // method, because it was abstract.  No code created from 1.0.7 on should
  // call it, so the StateError is OK.

  ///
  /// Create a new future that will return a [ScalableImage] from this
  /// source.  It is normally expected that a new future that returns a new
  /// image will be returned from each call, but this is not a requirement.
  /// This method must be overridden by subclasses.
  ///
  /// NOTE:  Prior to version 1.0.7, this method did not exist.  For backwards
  /// compatibility, a default implementation is provided that calls the
  // ignore: deprecated_member_use_from_same_package
  /// deprecated [si] getter, which was abstract.
  // ignore: deprecated_member_use_from_same_package
  Future<ScalableImage> createSI() => si;

  ///
  /// Flag to tell if warnings should be printed if there is a problem
  /// loading this asset.  For released products, the subclass should have
  /// a mechanism to set this false.  The default version of this getter always
  /// returns true.
  ///
  @Deprecated('Superseded by [warnF]')
  bool get warn => true;

  ///
  /// Function to call to warn if there is a problem
  /// loading this asset.  The default version of this getter always
  /// returns null.  If it is null, the default
  /// behavior is to print warnings.
  ///
  void Function(String)? get warnF => null;

  ///
  /// Give an object that is suitable for storing as the key in a [Map] for
  /// this source.  The returned object must be `==` this (it must compare
  /// as equivalent), and it must have the same `hashCode` as this.  It should
  /// have any extra fields stripped off that might cause large amounts of
  /// object retention.  For example, if [warnF] is retained as a field, it
  /// could be a closure that retains arbitrary state, so it should not be
  /// retained.
  ///
  ScalableImageSource get asKey => this;

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
    // I really mean it :-)
  }

  @internal
  void Function(String) get warnArg =>
      warnF ??
      (warn // ignore: deprecated_member_use_from_same_package
          ? defaultWarn
          : nullWarn);

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
  /// If [warnF] is non-null, it will be called if the AVD asset contains
  /// unrecognized tags and/or tag attributes.  If it is null, the default
  /// behavior is to print warnings.
  ///
  static ScalableImageSource fromAvd(
    AssetBundle bundle,
    String key, {
    bool compact = false,
    bool bigFloats = false,
    @Deprecated("[warn] has been superseded by [warnF].") bool warn = true,
    void Function(String)? warnF,
  }) {
    return _AvdBundleSource(bundle, key,
        compact: compact, bigFloats: bigFloats, warn: warn, warnF: warnF);
  }

  ///
  /// Get a [ScalableImage] by parsing an SVG XML file from
  /// an asset bundle.  In
  /// a production app, it's better to pre-compile the file -- see
  /// [ScalableImageSource.fromSI]
  ///
  /// [currentColor], if set, will set the currentColor value of the
  /// [ScalableImage] instance returned.  Note, however, that if the same
  /// image is used with more than one `currentColor` value, it's best to
  /// not set it here, and instead set it in the widget, e.g. with the
  /// `currentColor` parameter of [ScalableImageWidget.fromSISource].
  /// See also [ScalableImage.currentColor].
  ///
  /// If [compact] is true, the internal representation will occupy
  /// significantly less memory, at the expense of rendering time.  It will
  /// occupy perhaps an order of magnitude less memory, but render perhaps
  /// around 3x slower.  If [bigFloats] is true, the compact representation
  /// will use 8 byte double-precision float values, rather than 4 byte
  /// single-precision values.
  ///
  /// If [warnF] is non-null, it will be called if the AVD asset contains
  /// unrecognized tags and/or tag attributes.  If it is null, the default
  /// behavior is to print warnings.
  ///
  /// [exportedIDs] specifies a list of node IDs that are to be exported.
  /// See [ScalableImage.exportedIDs].
  ///
  static ScalableImageSource fromSvg(AssetBundle bundle, String key,
          {Color? currentColor,
          bool compact = false,
          bool bigFloats = false,
          @Deprecated("[warn] has been superseded by [warnF].")
          bool warn = true,
          void Function(String)? warnF,
          List<Pattern> exportedIDs = const []}) =>
      _SvgBundleSource(bundle, key, currentColor,
          compact: compact,
          bigFloats: bigFloats,
          warn: warn,
          warnF: warnF,
          exportedIDs: exportedIDs);

  ///
  /// Get a [ScalableImage] by parsing an SVG XML file from
  /// a http:, https: or data: URL.
  ///
  /// [currentColor], if set, will set the currentColor value of the
  /// [ScalableImage] instance returned.  Note, however, that if the same
  /// image is used with more than one `currentColor` value, it's best to
  /// not set it here, and instead set it in the widget, e.g. with the
  /// `currentColor` parameter of [ScalableImageWidget.fromSISource].
  /// See also [ScalableImage.currentColor].
  ///
  /// If [compact] is true, the internal representation will occupy
  /// significantly less memory, at the expense of rendering time.  It will
  /// occupy perhaps an order of magnitude less memory, but render perhaps
  /// around 3x slower.  If [bigFloats] is true, the compact representation
  /// will use 8 byte double-precision float values, rather than 4 byte
  /// single-precision values.
  ///
  /// If [warnF] is non-null, it will be called if the SVG asset contains
  /// unrecognized tags and/or tag attributes.  If it is null, the default
  /// behavior is to print warnings.
  ///
  /// [exportedIDs] specifies a list of node IDs that are to be exported.
  /// See [ScalableImage.exportedIDs].
  ///
  /// [defaultEncoding] specifies the character encoding to use if the
  /// content-type header of the HTTP response does not indicate an encoding.
  /// RVC 2916 specifies latin1 for HTTP, but current browser practice defaults
  /// to UTF8.
  ///
  /// [httpHeaders] will be added to the HTTP GET request.
  ///
  static ScalableImageSource fromSvgHttpUrl(Uri url,
          {Color? currentColor,
          bool compact = false,
          bool bigFloats = false,
          @Deprecated("[warn] has been superseded by [warnF].")
          bool warn = true,
          void Function(String)? warnF,
          List<Pattern> exportedIDs = const [],
          Map<String, String>? httpHeaders,
          Encoding defaultEncoding = utf8}) =>
      _SvgHttpSource(
        url,
        currentColor,
        compact: compact,
        bigFloats: bigFloats,
        warn: warn,
        warnF: warnF,
        exportedIDs: exportedIDs,
        defaultEncoding: defaultEncoding,
        httpHeaders: httpHeaders,
      );

  ///
  /// Get a [ScalableImage] by parsing an SVG XML file from
  /// a `File`, from the dart:io library.  `File` isn't available
  /// on Dart Web, so the `File` argument is passed as an object, along
  /// with a a function to read a string from it.
  ///
  /// [file] is an object that can be tested for equivalence against
  /// other arguments passed to this method throughout the lifetime of this
  /// program.
  ///
  /// [fileReader] is a function that delivers the contents of the file as
  /// a string.  This value is _not_ considered when looking for an
  /// already-loaded image in a [ScalableImageCache].
  ///
  /// [currentColor], if set, will set the currentColor value of the
  /// [ScalableImage] instance returned.  Note, however, that if the same
  /// image is used with more than one `currentColor` value, it's best to
  /// not set it here, and instead set it in the widget, e.g. with the
  /// `currentColor` parameter of [ScalableImageWidget.fromSISource].
  /// See also [ScalableImage.currentColor].
  ///
  /// If [compact] is true, the internal representation will occupy
  /// significantly less memory, at the expense of rendering time.  It will
  /// occupy perhaps an order of magnitude less memory, but render perhaps
  /// around 3x slower.  If [bigFloats] is true, the compact representation
  /// will use 8 byte double-precision float values, rather than 4 byte
  /// single-precision values.
  ///
  /// If [warnF] is non-null, it will be called if the SVG asset contains
  /// unrecognized tags and/or tag attributes.  If it is null, the default
  /// behavior is to print warnings.
  ///
  /// [exportedIDs] specifies a list of node IDs that are to be exported.
  /// See [ScalableImage.exportedIDs].
  ///
  /// Usage:
  /// ```
  ///     final file = File(...);
  ///     final source = ScalableImageSource.fromSvgFile(
  ///         file, () => file.readAsString());
  /// ```
  static ScalableImageSource fromSvgFile(
    Object file,
    FutureOr<String> Function() fileReader, {
    Color? currentColor,
    bool compact = false,
    bool bigFloats = false,
    void Function(String)? warnF,
    List<Pattern> exportedIDs = const [],
  }) =>
      _SvgFileSource(file, fileReader,
          currentColor: currentColor,
          compact: compact,
          bigFloats: bigFloats,
          warnF: warnF,
          exportedIDs: exportedIDs);

  ///
  /// Get a [ScalableImage] by parsing an AVD XML file from
  /// a http:, https: or data: URL.
  ///
  /// [currentColor], if set, will set the currentColor value of the
  /// [ScalableImage] instance returned.  Note, however, that if the same
  /// image is used with more than one `currentColor` value, it's best to
  /// not set it here, and instead set it in the widget, e.g. with the
  /// `currentColor` parameter of [ScalableImageWidget.fromSISource].
  /// See also [ScalableImage.currentColor].
  ///
  /// If [compact] is true, the internal representation will occupy
  /// significantly less memory, at the expense of rendering time.  It will
  /// occupy perhaps an order of magnitude less memory, but render perhaps
  /// around 3x slower.  If [bigFloats] is true, the compact representation
  /// will use 8 byte double-precision float values, rather than 4 byte
  /// single-precision values.
  ///
  /// If [warnF] is non-null, it will be called if the AVD asset contains
  /// unrecognized tags and/or tag attributes.  If it is null, the default
  /// behavior is to print warnings.
  ///
  /// [httpHeaders] will be added to the HTTP GET request.
  ///
  /// [defaultEncoding] specifies the character encoding to use if the
  /// content-type header of the HTTP response does not indicate an encoding.
  /// RVC 2916 specifies latin1 for HTTP, but current browser practice defaults
  /// to UTF8.
  ///
  static ScalableImageSource fromAvdHttpUrl(Uri url,
          {Color? currentColor,
          bool compact = false,
          bool bigFloats = false,
          @Deprecated("[warn] has been superseded by [warnF].")
          bool warn = true,
          void Function(String)? warnF,
          Map<String, String>? httpHeaders,
          Encoding defaultEncoding = utf8}) =>
      _AvdHttpSource(url,
          compact: compact,
          bigFloats: bigFloats,
          warn: warn,
          warnF: warnF,
          httpHeaders: httpHeaders,
          defaultEncoding: defaultEncoding);

  ///
  /// Get a [ScalableImage] by reading a pre-compiled `.si` file.
  /// These files can be produced with
  ///  `dart run jovial_svg:svg_to_si` or `dart run jovial_svg:avd_to_si`.
  ///  Pre-compiled files load about an order of magnitude faster.
  ///
  /// [currentColor], if set, will set the currentColor value of the
  /// [ScalableImage] instance returned.  Note, however, that if the same
  /// image is used with more than one `currentColor` value, it's best to
  /// not set it here, and instead set it in the widget, e.g. with the
  /// `currentColor` parameter of [ScalableImageWidget.fromSISource].
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
  @override
  final bool warn;
  @override
  final void Function(String)? warnF;
  _AvdBundleSource(this.bundle, this.key,
      {required this.compact,
      required this.bigFloats,
      required this.warn,
      required this.warnF});

  @override
  Future<ScalableImage> get si => createSI();

  @override
  Future<ScalableImage> createSI() {
    final warnArg = warnF ?? defaultWarn;

    return ScalableImage.fromAvdAsset(bundle, key,
        compact: compact, bigFloats: bigFloats, warnF: warnArg);
  }

  @override
  ScalableImageSource get asKey => warnF == null
      ? this
      : _AvdBundleSource(bundle, key,
          compact: compact, bigFloats: bigFloats, warn: false, warnF: null);

  @override
  bool operator ==(final Object other) {
    if (other is _AvdBundleSource) {
      return bundle == other.bundle &&
          key == other.key &&
          compact == other.compact &&
          bigFloats == other.bigFloats;
    } else {
      return false;
    }
  }

  @override
  int get hashCode => 0x94fadcba ^ Object.hash(bundle, key, compact, bigFloats);
}

class _SvgBundleSource extends ScalableImageSource {
  final AssetBundle bundle;
  final String key;
  final Color? currentColor;
  final bool compact;
  final bool bigFloats;
  final List<Pattern> exportedIDs;
  @override
  final bool warn;
  @override
  final void Function(String)? warnF;

  _SvgBundleSource(this.bundle, this.key, this.currentColor,
      {required this.compact,
      required this.bigFloats,
      required this.warn,
      required this.warnF,
      required this.exportedIDs});

  @override
  Future<ScalableImage> get si => createSI();

  @override
  Future<ScalableImage> createSI() => ScalableImage.fromSvgAsset(bundle, key,
      currentColor: currentColor,
      compact: compact,
      bigFloats: bigFloats,
      warnF: warnArg,
      exportedIDs: exportedIDs);

  @override
  ScalableImageSource get asKey => warnF == null
      ? this
      : _SvgBundleSource(bundle, key, currentColor,
          compact: compact,
          bigFloats: bigFloats,
          exportedIDs: exportedIDs,
          warn: false,
          warnF: null);

  @override
  bool operator ==(final Object other) {
    if (other is _SvgBundleSource) {
      return bundle == other.bundle &&
          key == other.key &&
          currentColor == other.currentColor &&
          compact == other.compact &&
          bigFloats == other.bigFloats &&
          listEquals(exportedIDs, other.exportedIDs);
    } else {
      return false;
    }
  }

  @override
  int get hashCode =>
      0x544f0d11 ^
      Object.hash(bundle, key, currentColor, compact, bigFloats,
          Object.hashAll(exportedIDs));

  @override
  String toString() => '_SVGBundleSource($key $bundle $compact $bigFloats '
      '$currentColor $exportedIDs)';
}

class _SvgHttpSource extends ScalableImageSource {
  final Uri url;
  final Color? currentColor;
  final bool compact;
  final bool bigFloats;
  @override
  final bool warn;
  @override
  final void Function(String)? warnF;
  final List<Pattern> exportedIDs;
  final Encoding defaultEncoding;
  final Map<String, String>? httpHeaders;

  _SvgHttpSource(this.url, this.currentColor,
      {required this.compact,
      required this.bigFloats,
      required this.warn,
      required this.warnF,
      required this.exportedIDs,
      required this.httpHeaders,
      this.defaultEncoding = utf8});

  @override
  Future<ScalableImage> get si => createSI();

  @override
  Future<ScalableImage> createSI() => ScalableImage.fromSvgHttpUrl(url,
      currentColor: currentColor,
      compact: compact,
      bigFloats: bigFloats,
      warnF: warnArg,
      defaultEncoding: defaultEncoding,
      exportedIDs: exportedIDs,
      httpHeaders: httpHeaders);

  @override
  ScalableImageSource get asKey => warnF == null
      ? this
      : _SvgHttpSource(url, currentColor,
          compact: compact,
          bigFloats: bigFloats,
          exportedIDs: exportedIDs,
          httpHeaders: httpHeaders,
          warn: false,
          warnF: null);

  @override
  bool operator ==(final Object other) {
    if (other is _SvgHttpSource) {
      return url == other.url &&
          currentColor == other.currentColor &&
          compact == other.compact &&
          bigFloats == other.bigFloats &&
          mapEquals(httpHeaders, other.httpHeaders) &&
          defaultEncoding == other.defaultEncoding &&
          listEquals(exportedIDs, other.exportedIDs);
    } else {
      return false;
    }
  }

  @override
  int get hashCode =>
      // I just leave out httpHeaders
      0xf7972f9b ^
      Object.hash(url, currentColor, compact, bigFloats, defaultEncoding,
          Object.hashAll(exportedIDs));

  @override
  String toString() => '_SVGHttpSource($url $compact $bigFloats '
      '$currentColor $defaultEncoding $httpHeaders $exportedIDs)';
}

class _SvgFileSource extends ScalableImageSource {
  final Object file;
  final FutureOr<String> Function() fileReader;
  final Color? currentColor;
  final bool compact;
  final bool bigFloats;
  @override
  final void Function(String)? warnF;
  final List<Pattern> exportedIDs;

  _SvgFileSource(this.file, this.fileReader,
      {required this.currentColor,
      required this.compact,
      required this.bigFloats,
      required this.warnF,
      required this.exportedIDs});

  @override
  Future<ScalableImage> get si => createSI();

  @override
  Future<ScalableImage> createSI() async {
    final String src = await fileReader();
    return ScalableImage.fromSvgString(src,
        currentColor: currentColor,
        compact: compact,
        bigFloats: bigFloats,
        exportedIDs: exportedIDs,
        warnF: warnF);
  }

  @override
  ScalableImageSource get asKey => _SvgFileSource(file, _nullFileReader,
      currentColor: currentColor,
      compact: compact,
      bigFloats: bigFloats,
      exportedIDs: exportedIDs,
      warnF: null);

  static String _nullFileReader() => '';

  @override
  bool operator ==(final Object other) {
    if (other is _SvgFileSource) {
      return file == other.file &&
          currentColor == other.currentColor &&
          compact == other.compact &&
          bigFloats == other.bigFloats &&
          listEquals(exportedIDs, other.exportedIDs);
    } else {
      return false;
    }
  }

  @override
  int get hashCode =>
      0xd111d574 ^
      Object.hash(
          file, currentColor, compact, bigFloats, Object.hashAll(exportedIDs));

  @override
  String toString() =>
      '_SVGFileSource($file $compact $bigFloats $currentColor $exportedIDs)';
}

class _AvdHttpSource extends ScalableImageSource {
  final Uri url;
  final bool compact;
  final bool bigFloats;
  @override
  final bool warn;
  @override
  final void Function(String)? warnF;
  final Encoding defaultEncoding;
  final Map<String, String>? httpHeaders;

  _AvdHttpSource(this.url,
      {required this.compact,
      required this.bigFloats,
      required this.warn,
      required this.warnF,
      required this.httpHeaders,
      this.defaultEncoding = utf8});

  @override
  Future<ScalableImage> get si => createSI();

  @override
  Future<ScalableImage> createSI() => ScalableImage.fromAvdHttpUrl(url,
      compact: compact,
      bigFloats: bigFloats,
      warnF: warnArg,
      defaultEncoding: defaultEncoding,
      httpHeaders: httpHeaders);

  @override
  ScalableImageSource get asKey => warnF == null
      ? this
      : _AvdHttpSource(url,
          compact: compact,
          bigFloats: bigFloats,
          defaultEncoding: defaultEncoding,
          httpHeaders: httpHeaders,
          warn: false,
          warnF: null);

  @override
  bool operator ==(final Object other) {
    if (other is _AvdHttpSource) {
      return url == other.url &&
          compact == other.compact &&
          bigFloats == other.bigFloats &&
          defaultEncoding == other.defaultEncoding &&
          mapEquals(httpHeaders, other.httpHeaders);
    } else {
      return false;
    }
  }

  @override
  int get hashCode =>
      // I just leave out httpHeaders
      0x95ccea44 ^ Object.hash(url, compact, bigFloats, defaultEncoding);

  @override
  String toString() =>
      '_AVDHttpSource($url $compact $bigFloats $defaultEncoding, $httpHeaders)';
}

class _SIBundleSource extends ScalableImageSource {
  final AssetBundle bundle;
  final String key;
  final Color? currentColor;

  _SIBundleSource(this.bundle, this.key, this.currentColor);

  @override
  Future<ScalableImage> get si => createSI();

  @override
  Future<ScalableImage> createSI() =>
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
  int get hashCode => 0xf67cd716 ^ Object.hash(bundle, key, currentColor);

  @override
  String toString() => '_SIBundleSource($key $bundle $currentColor)';
}

///
/// A coordinate system transformation to fit a `ScalableImage` into a
/// given container, for a given [BoxFit] and [Alignment].  This class is
/// offered as a convenience for scaling [ScalableImage] instances.  It
/// also helps converting positions as rendered back into the [ScalableImage]'s
/// coordinate, e.g. when mapping a touch event into the original
/// SVG's coordinate space.
///
class ScalingTransform {
  ///
  /// The horizontal scale factor
  ///
  final double scaleX;

  ///
  /// The vertical scale factor
  ///
  final double scaleY;

  ///
  /// The horizontal translation, before scaling is applied.  This does not
  /// include any translation to the SI's viewport's origin.  cf.
  /// [ScalableImage.paint].
  ///
  final double translateX;

  ///
  /// The vertical translation, before scaling is applied.  This does not
  /// include any translation to the SI's viewport's origin.  cf.
  /// [ScalableImage.paint].
  ///
  final double translateY;

  ///
  /// The [ScalableImage.viewport] of the image being transformed.
  ///
  final Rect siViewport;

  const ScalingTransform._p(this.scaleX, this.scaleY, this.translateX,
      this.translateY, this.siViewport);

  static const identity =
      ScalingTransform._p(1, 1, 0, 0, Rect.fromLTRB(0, 0, 1, 1));

  ///
  /// Create a scaling transform to display a [ScalableImage] in a
  /// container of [containerSize] where the [ScalableImage.viewport]'s
  /// value is [siViewport], for the given box [fit] and [alignment].
  ///
  factory ScalingTransform(
      {required Size containerSize,
      required Rect siViewport,
      BoxFit fit = BoxFit.contain,
      Alignment alignment = Alignment.center}) {
    final double sx;
    final double sy;

    switch (fit) {
      case BoxFit.fill:
        sx = containerSize.width / siViewport.width;
        sy = containerSize.height / siViewport.height;
        break;
      case BoxFit.contain:
        sx = sy = min(containerSize.width / siViewport.width,
            containerSize.height / siViewport.height);
        break;
      case BoxFit.cover:
        sx = sy = max(containerSize.width / siViewport.width,
            containerSize.height / siViewport.height);
        break;
      case BoxFit.fitWidth:
        sx = sy = containerSize.width / siViewport.width;
        break;
      case BoxFit.fitHeight:
        sx = sy = containerSize.height / siViewport.height;
        break;
      case BoxFit.none:
        sx = sy = 1;
        break;
      case BoxFit.scaleDown:
        sx = sy = min(
            1,
            min(containerSize.width / siViewport.width,
                containerSize.height / siViewport.height));
        break;
    }
    final extraX = containerSize.width - siViewport.width * sx;
    final extraY = containerSize.height - siViewport.height * sy;
    final tx = (1 + alignment.x) * extraX / 2;
    final ty = (1 + alignment.y) * extraY / 2;
    return ScalingTransform._p(sx, sy, tx, ty, siViewport);
  }

  ///
  /// Apply this transform to the given Canvas, by first translating
  /// and then by scaling.
  ///
  void applyToCanvas(Canvas canvas) {
    canvas.translate(translateX, translateY);
    canvas.scale(scaleX, scaleY);
  }

  ///
  /// Transform a point from the coordinate system of the container into
  /// the [ScalableImage]'s coordinate system.  This method adjusts for
  /// the origin of the SI's viewport.
  ///
  Offset toSICoordinate(final Offset c) => Offset(
      (c.dx - translateX) / scaleX + siViewport.left,
      (c.dy - translateY) / scaleY + siViewport.top);

  ///
  /// Transform a point from the coordinate system of the [ScalableImage] into
  /// the container's coordinate system.  This method adjusts for
  /// the origin of the SI's viewport.
  ///
  Offset toContainerCoordinate(final Offset si) => Offset(
      (si.dx - siViewport.left) * scaleX + translateX,
      (si.dy - siViewport.top) * scaleY + translateY);
}