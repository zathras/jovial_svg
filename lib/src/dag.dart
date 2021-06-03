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
/// A [ScalingImage] implemented as a directed acyclic graph of Dart objects.
/// This representation renders fast, but occupies the amount of memory you'd
/// expect with Dart objects.
///
library jovial_svg.dag;

import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:quiver/core.dart' as quiver;
import 'package:quiver/collection.dart' as quiver;
import 'affine.dart';
import 'common.dart';
import 'common_noui.dart';
import '../jovial_svg.dart';
import 'path.dart';
import 'path_noui.dart';

///
/// A Scalable Image that's represented by an in-memory directed
/// acyclic graph.  This is the fastest to render, at the price
/// of memory usage
///
class ScalableImageDag extends ScalableImage
    with _SIParentNode
    implements _SIParentBuilder {
  @override
  final List<SIRenderable> _renderables;

  ScalableImageDag(
      {required double? width,
      required double? height,
      required Color? tintColor,
      required BlendMode tintMode,
      required Rect? viewport,
      Color? currentColor,
      required List<SIImage> images})
      : _renderables = List<SIRenderable>.empty(growable: true),
        super(width, height, tintColor, tintMode, viewport, images, currentColor);

  ///
  /// Create a copy of [other], potentially with a new viewport.  The copy
  /// will share most of its data with the original, but the tree of renderable
  /// paths will be pruned to contain only those that intersect the new
  /// viewport.
  ///
  ScalableImageDag.modified(ScalableImageDag other,
      {Rect? viewport,
      required bool prune,
      double pruningTolerance = 0,
      required Color currentColor,
      required Color? tintColor,
      required BlendMode tintMode})
      : _renderables = (!prune || viewport == null)
            ? other._renderables
            : other._childrenPrunedBy(
                PruningBoundary(viewport.deflate(pruningTolerance)), {}),
        super.modifiedFrom(other,
            viewport: viewport,
            currentColor: currentColor,
            tintColor: tintColor,
            tintMode: tintMode);

  @override
  ScalableImage withNewViewport(Rect viewport,
          {bool prune = false, double pruningTolerance = 0}) =>
      ScalableImageDag.modified(this,
          viewport: viewport,
          prune: prune,
          pruningTolerance: pruningTolerance,
          currentColor: currentColor,
          tintColor: tintColor,
          tintMode: tintMode);

  @override
  ScalableImage modifyCurrentColor(Color newCurrentColor) {
    return ScalableImageDag.modified(this,
        viewport: viewport,
        prune: false,
        pruningTolerance: 0,
        currentColor: newCurrentColor,
        tintColor: tintColor,
        tintMode: tintMode);
  }

  @override
  ScalableImage modifyTint(
      {required BlendMode newTintMode, required Color? newTintColor}) {
    return ScalableImageDag.modified(this,
        viewport: viewport,
        prune: false,
        pruningTolerance: 0,
        currentColor: currentColor,
        tintColor: newTintColor,
        tintMode: newTintMode);
  }

  @override
  void paintChildren(Canvas c, Color currentColor) {
    for (final r in _renderables) {
      r.paint(c, currentColor);
    }
  }

  @override
  List<SIRenderable> _childrenPrunedBy(
      PruningBoundary b, Set<SIRenderable> dagger) {
    _addAll(_renderables, dagger);
    return super._childrenPrunedBy(b, dagger);
  }

  void _addAll(List<SIRenderable> children, Set<SIRenderable> dagger) {
    for (final r in children) {
      dagger.add(r);
      if (r is SIGroup) {
        _addAll(r._renderables, dagger);
      }
    }
  }

  @override
  ScalableImageDag toDag() => this;
}

abstract class _SIParentBuilder {
  List<SIRenderable> get _renderables;
}

abstract class _SIParentNode {
  List<SIRenderable> get _renderables;

  List<SIRenderable> _childrenPrunedBy(
      PruningBoundary b, Set<SIRenderable> dagger) {
    bool changed = false;
    final copy = List<SIRenderable>.empty(growable: true);
    for (final r in _renderables) {
      final rr = r.prunedBy(b, dagger);
      if (rr == null) {
        changed = true;
      } else {
        changed = changed || !identical(rr, r);
        copy.add(rr);
      }
    }
    if (changed) {
      return List.unmodifiable(copy);
    } else {
      return _renderables;
    }
  }

  PruningBoundary? getBoundary() {
    PruningBoundary? result;
    for (final r in _renderables) {
      final b = r.getBoundary();
      if (result == null) {
        result = b;
      } else if (b != null) {
        result =
            PruningBoundary(result.getBounds().expandToInclude(b.getBounds()));
        // This is simple, fast, and good enough for our purposes.  Given
        // that the rectangles might be tilted relative to each other,
        // the minimum pruning polygon isn't necessarily a rectangle.  If we
        // wanted to settle for some sort of minimum rectangle, something like
        // https://www.geometrictools.com/Documentation/MinimumAreaRectangle.pdf
        // might be in order.  But here, we're really just determining a
        // default bounding rectangle for a [ScalableImage], so we do something
        // reasonable if the original XML didn't have a width and height,
        // or a viewportWidth and viewportHeight.
      }
    }
    return result;
  }
}

class SIGroup extends SIRenderable with _SIParentNode, SIGroupHelper {
  @override
  final List<SIRenderable> _renderables;
  final Affine? transform;
  int? _hashCode;

  SIGroup(this.transform, Iterable<SIRenderable> renderables)
      : _renderables = List.unmodifiable(renderables);

  SIGroup._modified(SIGroup other, this._renderables)
      : transform = other.transform;

  @override
  List<SIRenderable> _childrenPrunedBy(
      PruningBoundary b, Set<SIRenderable> dagger) {
    b = transformBoundaryFromParent(b, transform);
    return super._childrenPrunedBy(b, dagger);
  }

  @override
  PruningBoundary? getBoundary() =>
      transformBoundaryFromChildren(super.getBoundary(), transform);

  @override
  void paint(Canvas c, Color currentColor) {
    startPaintGroup(c, transform);
    for (final r in _renderables) {
      r.paint(c, currentColor);
    }
    endPaintGroup(c);
  }

  @override
  SIGroup? prunedBy(PruningBoundary b, Set<SIRenderable> dagger) {
    final rr = _childrenPrunedBy(b, dagger);
    if (rr.isEmpty) {
      return null;
    }
    if (identical(rr, _renderables)) {
      return this;
    }
    final g = SIGroup._modified(this, List.unmodifiable(rr));
    final dg = dagger.lookup(g);
    if (dg != null) {
      return dg as SIGroup;
    }
    dagger.add(g);
    return g;
  }

  @override
  bool operator ==(final Object other) {
    if (identical(this, other)) {
      return true;
    } else if (!(other is SIGroup)) {
      return false;
    } else {
      return transform == other.transform &&
          quiver.listsEqual(_renderables, other._renderables);
    }
  }

  bool _hashing = false;
  @override
  int get hashCode {
    if (_hashCode == null) {
      assert(!_hashing);
      _hashing = true;
      _hashCode = quiver.hash2(
        quiver.hashObjects(_renderables),
        transform.hashCode,
      );
      _hashing = false;
    }
    return _hashCode!;
  }
}

class _GroupBuilder implements _SIParentBuilder {
  @override
  final List<SIRenderable> _renderables;
  final Affine? transform;

  _GroupBuilder(this.transform)
      : _renderables = List<SIRenderable>.empty(growable: true);

  SIGroup get group => SIGroup(transform, _renderables);
}

///
/// See [PathBuilder] for usage.
///
abstract class SIGenericDagBuilder<PathDataT> extends SIBuilder<PathDataT> {
  double? _width;
  double? _height;
  int? _tintColor;
  SITintMode? _tintMode;
  final Rect? _viewport;
  @override
  final bool warn;
  final _parentStack = List<_SIParentBuilder>.empty(growable: true);
  ScalableImageDag? _si;
  List<SIImage>? _images;
  final _paths = <Object?, Path>{};
  final Set<SIRenderable> _dagger = <SIRenderable>{};
  final Color? currentColor;

  SIGenericDagBuilder(this._viewport, this.warn, this.currentColor);

  T _daggerize<T extends SIRenderable>(T r) {
    var result = _dagger.lookup(r);
    if (result == null) {
      result = r;
      _dagger.add(result);
    }
    return result as T;
  }

  PathDataT immutableKey(PathDataT key);

  @override
  void get initial => null;

  @override
  void path(void collector, PathDataT pathData, SIPaint siPaint) {
    final p = _daggerize(SIPath(_getPath(pathData), siPaint));
    addRenderable(p);
  }

  @override
  void clipPath(void collector, PathDataT pathData) {
    addRenderable(_daggerize(SIClipPath(_getPath(pathData))));
  }

  Path _getPath(PathDataT pathData) {
    final p = _paths[pathData];
    if (p != null) {
      return p;
    }
    final pb = UIPathBuilder();
    makePath(pathData, pb, warn: warn);
    return _paths[immutableKey(pathData)] = pb.path;
  }

  @override
  PathBuilder? startPath(SIPaint siPaint, Object key) {
    final p = _paths[key];
    if (p != null) {
      final sip = _daggerize(SIPath(p, siPaint));
      addRenderable(sip);
      return null;
    }
    return UIPathBuilder(onEnd: (pb) {
      _paths[key] = pb.path;
      final p = _daggerize(SIPath(pb.path, siPaint));
      addRenderable(p);
    });
  }

  void makePath(PathDataT pathData, PathBuilder pb, {bool warn = true});

  @override
  void images(void collector, List<SIImageData> im) {
    assert(_images == null);
    _images = List<SIImage>.generate(im.length, (i) => SIImage(im[i]));
    assert (_si == null);
    final a = _si = ScalableImageDag(
        width: _width,
        height: _height,
        viewport: _viewport,
        tintColor: (_tintColor == null) ? null : Color(_tintColor!),
        tintMode: (_tintMode ?? SITintModeMapping.defaultValue).asBlendMode,
        currentColor: currentColor,
        images: _images!);
    _parentStack.add(a);
  }

  @override
  void image(void collector, int imageNumber) =>
      addRenderable(_images![imageNumber]);

  ScalableImageDag get si {
    final r = _si;
    if (r == null) {
      throw ParseError('No vector element');
    } else {
      return r;
    }
  }

  @override
  void vector(
      {required double? width,
      required double? height,
      required int? tintColor,
      required SITintMode? tintMode}) {
    assert(_si == null);
    _width = width;
    _height = height;
    _tintColor = tintColor;
    _tintMode = tintMode;
  }

  @override
  void endVector() {
    _parentStack.length = _parentStack.length - 1;
    assert(_parentStack.isEmpty);
  }

  void addRenderable(SIRenderable p) {
    _parentStack.last._renderables.add(p);
  }

  @override
  void group(void collector, Affine? transform) {
    final g = _GroupBuilder(transform);
    _parentStack.add(g);
  }

  @override
  void endGroup(void collector) {
    final gb = _parentStack.last as _GroupBuilder;
    _parentStack.length = _parentStack.length - 1;
    addRenderable(_daggerize(gb.group));
  }
}

class SIDagBuilder extends SIGenericDagBuilder<String> with SIStringPathMaker {
  SIDagBuilder({required bool warn, Color? currentColor})
      : super(null, warn, currentColor);
}
