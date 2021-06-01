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

library jovial_svg.dag;

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
      Color? currentColor})
      : _renderables = List<SIRenderable>.empty(growable: true),
        super(width, height, tintColor, tintMode, viewport, currentColor);

  ///
  /// Create a copy of [other], potentially with a new viewport.  The copy
  /// will share most of its data with the original, but the tree of renderable
  /// paths will be pruned to contain only those that intersect the new
  /// viewport.
  ///
  ScalableImageDag.modified(ScalableImageDag other,
      {Rect? viewport, required bool prune, double pruningTolerance = 0})
      : _renderables = (!prune || viewport == null)
            ? other._renderables
            : other._childrenPrunedBy(
                PruningBoundary(viewport.deflate(pruningTolerance)), {}),
        super.modified(other, viewport: viewport);

  @override
  ScalableImage withNewViewport(Rect viewport,
          {bool prune = false, double pruningTolerance = 0}) =>
      ScalableImageDag.modified(this,
          viewport: viewport, prune: prune, pruningTolerance: pruningTolerance);

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
  final Rect? _viewport;
  @override
  final bool warn;
  final _parentStack = List<_SIParentBuilder>.empty(growable: true);
  ScalableImageDag? _si;
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
    final a = _si = ScalableImageDag(
        width: width,
        height: height,
        viewport: _viewport,
        tintColor: (tintColor == null) ? null : Color(tintColor),
        tintMode: (tintMode ?? SITintModeMapping.defaultValue).asBlendMode,
        currentColor: currentColor);
    _parentStack.add(a);
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
