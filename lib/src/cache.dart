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

import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

import 'exported.dart';
import 'widget.dart';


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
@internal
final defaultCache = ScalableImageCache(size: 0);

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
/// If different caching semantics are desired, user code can implement
/// [ScalableImageCache]; [ScalableImageWidget] does not use any of its
/// private members.  See also the `demo_hive` application to see how
/// [ScalableImageSource] can be extended to load from a persistent cache.
///
/// Sample usage (see `example/lib/cache.dart` for the full program):
///
/// ```
/// class _HomePageState extends State<HomePage> {
///  ScalableImageCache _svgCache = ScalableImageCache(size: 70);
///  ...
///  @override
///  Widget build(BuildContext context) {
///    return ...
///              ScalableImageWidget.fromSISource(
///                  cache: _svgCache,
///                  scale: 1000,
///                  si: ScalableImageSource.fromSvgHttpUrl(widget.svgs[index]),
///                  ...),
///     ...;
///   }
/// }
/// ```
///
class ScalableImageCache {
  final _canonicalized = <ScalableImageSource, _CacheEntry>{};

  int _size;

  // List of unreferenced ScalableImageSource instances, stored as a
  // doubly-linked list with a dummy head node.  The most recently
  // used is _lruList._lessRecent, and the least recently used is
  // _lruList._moreRecent.
  final _lruList = _CacheEntry._null();

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
  /// Returns a Future for the scalable image.
  ///
  /// Application code where cache is present should use the returned
  /// future, and not use [ScalableImageSource.createSI] directly.
  ///
  /// This method calls [addReferenceV2].
  ///
  /// [src]  The source of the scalable image
  /// [ifAvailableSync]  An optional function that is called synchronously if
  /// the `ScalableImage` is available in the cache.  (Added in version
  /// 1.1.12)
  @Deprecated('Use addReferenceV2 instead')
  Future<ScalableImage> addReference(ScalableImageSource src,
      {ScalableImage Function(ScalableImage)? ifAvailableSync}) {
    final result = addReferenceV2(src);
    if (result is Future<ScalableImage>) {
      return result;
    } else {
      if (ifAvailableSync != null) {
        ifAvailableSync(result);
      }
      return Future.value(result);
    }
  }

  ///
  /// Called when a [ScalableImageSource] is referenced,
  /// e.g. in a stateful widget's [State] object's `initState` method.
  /// Returns a Future for the scalable image.
  ///
  /// Application code where a cache is present should use the returned
  /// value, and not use [ScalableImageSource.createSI] directly.
  ///
  /// [src]  The source of the scalable image
  FutureOr<ScalableImage> addReferenceV2(ScalableImageSource src) {
    _CacheEntry? e = _canonicalized[src];
    if (e == null) {
      e = _CacheEntry(src, src.createSI());
      final k = src.asKey;
      assert(k == src);
      _canonicalized[k] = e;
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
      // Very unexpected; I think this would be a bug in Map.
      throw ArgumentError('Found key $found that is != search: $key');
    }
    if (key.hashCode != found.hashCode) {
      throw ArgumentError('Key $key hash ${key.hashCode} is == existing key '
          '$found, hash ${found.hashCode}');
    }
  }

  ///
  /// Called when a source is dereferenced, e.g. by a stateful widget's
  /// [State] object being disposed.  Throws an exception if there had been
  /// no matching call to [addReferenceV2] for this source.
  ///
  void removeReference(ScalableImageSource src) {
    _CacheEntry? e = _canonicalized[src];
    if (e == null) {
      throw ArgumentError.value(src, 'Not in cache', 'src');
    } else if (e._refCount <= 0) {
      throw ArgumentError.value(src, 'Extra attempt to removeReference', 'src');
    }
    assert(e._lessRecent == null);
    assert(e._moreRecent == null);
    e._refCount--;
    if (e._refCount == 0) {
      _addToLRU(e);
    }
  }

  ///
  /// If the image referenced by src is in the cache, force it to be
  /// reloaded the next time it is used.
  ///
  void forceReload(ScalableImageSource src) {
    final _CacheEntry? old = _canonicalized.remove(src);
    if (old == null) {
      return;
    }
    final e = _CacheEntry(src, src.createSI());
    final k = src.asKey;
    assert(k == src);
    _canonicalized[k] = e;
    if (old._refCount > 0) {
      e._refCount = old._refCount;
      assert(old._lessRecent == null && old._moreRecent == null);
    } else {
      e._lessRecent = old._lessRecent;
      e._moreRecent = old._moreRecent;
      assert(e._lessRecent!._moreRecent == old);
      e._lessRecent!._moreRecent = e;
      assert(e._moreRecent!._lessRecent == old);
      e._moreRecent!._lessRecent = e;
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
    } else {
      _removeFromCanonicalized(e);
    }
  }

  void _trimLRU() {
    while (_lruList._lessRecent != _lruList && _canonicalized.length > _size) {
      // While lruList isn't empty, and we're over our capacity
      final victim = _lruList._moreRecent!; // That's the least recently used
      assert(victim != _lruList);
      _removeFromCanonicalized(victim);
      victim._moreRecent!._lessRecent = victim._lessRecent;
      victim._lessRecent!._moreRecent = victim._moreRecent;
    }
  }

  void _removeFromCanonicalized(_CacheEntry victim) {
    final _CacheEntry? removed = _canonicalized.remove(victim._siSrc);
    assert(identical(removed, victim));
    assert(victim._refCount == 0);
  }
}

// An entry in the cache, which might be held on the LRU list.  The LRU list
// is doubly-linked and wraps around to a dummy head node.
//
// Flutter's LinkedListEntry<T> didn't quite fit, and it's not like a
// doubly-linked list is hard, anyway.
class _CacheEntry {
  final ScalableImageSource? _siSrc;
  FutureOr<ScalableImage>? _si;
  int _refCount = 0;
  _CacheEntry? _moreRecent;
  _CacheEntry? _lessRecent;
  // Invariant:  If refCount is 0, _moreRecent and _lessRecent are non-null
  // Invariant:  If _moreRecent is null, refCount > 0
  // Invariant:  If _lessRecent is null, refCount > 0

  _CacheEntry(ScalableImageSource this._siSrc, Future<ScalableImage> this._si) {
    unawaited(_replaceFuture());
  }

  _CacheEntry._null()
      : _siSrc = null,
        _si = null;

  Future<void> _replaceFuture() async {
    try {
      _si = await _si!;
    } catch (e) {
      // Ignore -- leave the Future instance in the cache; it has the
      // error, ready and waiting for anyone who awaits.
    }
  }
}

///
/// Used to look up what part of a [ScalableImage] is
/// clicked on within a [ScalableImageWidget].
///
/// An SVG node can have a name in its `id` attribute.  When an SVG is read,
/// or converted to an SI, these ID values can be marked as exported.  This can
/// be done by listing the IDs, or by using a regular expression.  For example,
/// to build an SI where all ID values are exported, you can specify
/// `-x '.*'` to `svg_to_si`.  Each exported ID does add some overhead, so
/// in production, it's best to only export the ones you need.
///
/// A [ScalableImageWidget] can have an [ExportedIDLookup] instance associated
/// with it.  This can be used, for example, to determine which node(s) are
/// under a mouse click (or other tap event).
///
/// Usage:
/// ```
/// class _GlorpState extends State<GlorpWidget> {
///     final ExportedIDLookup _idLookup = ExportedIDLookup();
///     ...
///     @override
///     Widget build() => ...
///         GestureDetector(
///           onTapDown: _handleTapDown,
///           child: ScalableImageWidget(
///             ...
///             lookup: _idLookup))
///       ...;
///
///   void _handleTapDown(TapDownDetails event) {
///     final Set<String> hits = _idLookup.hits(event.localPosition);
///     print('Tap down at ${event.localPosition}:  $hits');
///   }
/// }
/// ```
///
/// See `example/lib/animation.dart` and `demo/lib/main.dart` for
/// more complete examples.
///
class ExportedIDLookup {
  @internal
  ScalableImage? si;
  @internal
  ScalingTransform? lastTransform;

  ///
  /// Get the exported IDs from the underlying [ScalableImage] instance, if
  /// it has been loaded.  The [ExportedID]s will be in the coordinate system
  /// of the [ScalableImage].  See also [scalingTransform].
  ///
  Set<ExportedID> get exportedIDs => si?.exportedIDs ?? const {};

  ///
  /// Get the [ScalingTransform] needed to convert coordinates between the
  /// coordinate system of the [ScalableImage]'s [exportedIDs] and the
  /// containing [ScalableImageWidget].
  ///
  ScalingTransform get scalingTransform =>
      lastTransform ?? ScalingTransform.identity;

  ///
  /// Return the set of node IDs whose bounding rectangles contain [p].
  ///
  Set<String> hits(Offset p) {
    final Set<String> result = {};
    p = scalingTransform.toSICoordinate(p);
    for (final e in exportedIDs) {
      if (e.boundingRect.contains(p)) {
        result.add(e.id);
      }
    }
    return result;
  }
}
