library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'cache.dart';
import 'exported.dart';
import 'widget.dart';

///
/// A widget for displaying a [ScalableImage] on in an [Ink].  This can
/// be used to display an SVG on top of a [Material] while allowing
/// other layers to be drawn.  An example of this is a [MaterialButton]'s
/// splash effect.
///
/// The image can be automatically scaled by the widget, and fit into the
/// available area with a `BoxFit` and an `Alignment`.  Where loading is
/// required, a [ScalableImageCache] can be provided.
///
/// Note that rendering a scalable image can be time-consuming if the
/// underlying scene is complex.  Notably, GPU performance can be a
/// bottleneck.  If animations are played over an unchanging [ScalableImage],
/// wrapping the [ScalableImageInk] in Flutter's `RepaintBoundary`
/// might result in significantly better performance.
///
abstract class ScalableImageInk extends StatefulWidget {
  ///
  /// Whether the underlying `ScalableImage`'s painting is complex enough
  /// to benefit from caching.  This is forwarded to [CustomPaint] -- see
  /// [CustomPaint.isComplex].
  ///
  final bool isComplex;

  final ExportedIDLookup? _lookup;

  const ScalableImageInk._p(Key? key, this.isComplex, this._lookup)
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
  /// [fit] controls how the scalable image is scaled within the widget.
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
  /// [isComplex] see [ScalableImageInk.isComplex]
  ///
  /// [lookup] is used to look up node IDs that were exported in an SVG
  /// asset.  See [ExportedIDLookup].
  ///
  factory ScalableImageInk(
          {Key? key,
          required ScalableImage si,
          BoxFit fit = BoxFit.contain,
          Alignment alignment = Alignment.center,
          bool clip = true,
          Color? background,
          bool isComplex = false,
          ExportedIDLookup? lookup}) =>
      _SyncSIInk(
          key, si, fit, alignment, clip, background, isComplex, lookup);

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
  /// [fit] controls how the scalable image is scaled within the widget.
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
  factory ScalableImageInk.fromSISource({
    Key? key,
    required ScalableImageSource si,
    BoxFit fit = BoxFit.contain,
    Alignment alignment = Alignment.center,
    bool clip = true,
    Color? currentColor,
    Color? background,
    bool reload = false,
    bool isComplex = false,
    ExportedIDLookup? lookup,
    ScalableImageCache? cache,
    Widget Function(BuildContext)? onLoading,
    Widget Function(BuildContext)? onError,
    Widget Function(BuildContext, Widget child)? switcher
  }) {
    onLoading ??= _AsyncSIInk.defaultOnLoading;
    onError ??= onLoading;
    cache = cache ?? defaultCache;
    if (reload) {
      cache.forceReload(si);
    }
    return _AsyncSIInk(
        key,
        si,
        fit,
        alignment,
        clip,
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

class _AsyncSIInk extends ScalableImageInk {
  final ScalableImageSource _siSource;
  final ScalableImageCache _cache;
  final BoxFit _fit;
  final Alignment _alignment;
  final bool _clip;
  // final double _scale;
  final Color? _currentColor;
  final Color? _background;

  final Widget Function(BuildContext) _onLoading;
  final Widget Function(BuildContext) _onError;
  final Widget Function(BuildContext, Widget child)? _switcher;

  const _AsyncSIInk(
      Key? key,
      this._siSource,
      this._fit,
      this._alignment,
      this._clip,
      // this._scale,
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
  State<StatefulWidget> createState() => _AsyncSIInkState();

  static Widget defaultOnLoading(BuildContext c) =>
      const SizedBox(width: 1, height: 1);
}

class _AsyncSIInkState extends State<_AsyncSIInk> {
  static final ScalableImage _error = ScalableImage.blank();
  ScalableImage? _si;

  @override
  void initState() {
    super.initState();
    final si = widget._cache.addReferenceV2(widget._siSource);
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
  void didUpdateWidget(covariant _AsyncSIInk old) {
    super.didUpdateWidget(old);
    if (old._siSource != widget._siSource || old._cache != widget._cache) {
      final si = widget._cache.addReferenceV2(widget._siSource);
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
      result = _SyncSIInk(null, si, widget._fit, widget._alignment, widget._clip, widget._background, widget.isComplex, widget._lookup);
    }
    final switcher = widget._switcher;
    if (switcher == null) {
      return result;
    } else {
      return switcher(context, result);
    }
  }
}

class _SyncSIInk extends ScalableImageInk {
  final ScalableImage _si;
  final BoxFit _fit;
  final Alignment _alignment;
  final bool _clip;
  final Color? _background;

  const _SyncSIInk(
    Key? key,
    this._si,
    this._fit,
    this._alignment,
    this._clip,
    this._background,
    bool isComplex,
    ExportedIDLookup? lookup,
  ) : super._p(key, isComplex, lookup);

  @override
  State<StatefulWidget> createState() => _SyncSIInkState();
}

class _SyncSIInkState extends State<_SyncSIInk> {
  @override
  Widget build(BuildContext context) {
    return Ink(
      decoration: _SIDecoration(widget._si, widget._fit, widget._alignment,
          widget._clip, widget._background, widget._lookup),
    );
  }
}

// This could theoretically be exposed to be used as a general decoration
// usable in a Container for example, however a lot of the functionality for
// this would require additional work and as such has not been attempted.
class _SIDecoration extends Decoration {
  final ScalableImage _si;
  final BoxFit _fit;
  final Alignment _alignment;
  final bool _clip;
  final Color? _background;
  final ExportedIDLookup? _lookup;

  const _SIDecoration(this._si, this._fit, this._alignment, this._clip,
      this._background, this._lookup);

  @factory
  @override
  BoxPainter createBoxPainter([covariant VoidCallback? onChanged]) {
    _si.prepareImages().then((v) => onChanged?.call());
    return _SIBoxPainter(
      onChanged,
      _si,
      _fit,
      _alignment,
      _clip,
      _background,
      _lookup,
    );
  }
}

class _SIBoxPainter extends BoxPainter {
  final ScalableImage _si;
  final BoxFit _fit;
  final Alignment _alignment;
  final bool _clip;
  final Color? _background;
  final ExportedIDLookup? _lookup;

  const _SIBoxPainter(
    super.onChanged,
    this._si,
    this._fit,
    this._alignment,
    this._clip,
    this._background,
    this._lookup,
  );

  @override
  void dispose() {
    super.dispose();
    _si.unprepareImages();
  }

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    assert(configuration.size != null);
    final size = configuration.size!;
    final bounds = offset & size;
    final background = _background;
    final xform = ScalingTransform(
      containerSize: size,
      siViewport: _si.viewport,
      fit: _fit,
      alignment: _alignment,
    );
    final lookup = _lookup;
    if (lookup != null) {
      lookup.lastTransform = xform;
      lookup.si = _si;
    }

    canvas.save();
    try {
      if (_clip) {
        canvas.clipRect(bounds);
      }
      if (background != null) {
        canvas.drawColor(background, BlendMode.src);
        canvas.saveLayer(bounds, Paint());
        canvas.drawColor(const Color(0x00ffffff), BlendMode.src);
      }
      try {
        canvas.translate(offset.dx, offset.dy);
        xform.applyToCanvas(canvas);
        _si.paint(canvas);
      } finally {}
    } finally {
      canvas.restore();
      if (background != null) {
        canvas.restore();
      }
    }
  }
}
