/*
Copyright (c) 2021-2022, William Foote

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
/// A [ScalableImage] implemented as a directed acyclic graph of Dart objects.
/// This representation renders fast, but occupies the amount of memory you'd
/// expect with Dart objects.
///
library jovial_svg.dag;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:quiver/core.dart' as quiver;
import 'package:quiver/collection.dart' as quiver;
import 'affine.dart';
import 'common.dart';
import 'common_noui.dart';
import 'exported.dart';
import 'path.dart';
import 'path_noui.dart';

///
/// A Scalable Image that's represented by an in-memory directed
/// acyclic graph.  This is the fastest to render, at the price
/// of memory usage
///
@immutable
class ScalableImageDag extends ScalableImageBase with _SIParentNode {
  @override
  late final List<SIRenderable> _renderables;

  ///
  /// Create an instance with no children, for testing.  This is a private
  /// API:  ScalableImageDag is not an exported type.
  ///
  ScalableImageDag.forTesting(
      {required double? width,
      required double? height,
      required Color? tintColor,
      required BlendMode tintMode,
      required Rect? viewport,
      Color? currentColor,
      required List<SIImage> images})
      : _renderables = const [],
        super(
            width, height, tintColor, tintMode, viewport, images, currentColor);

  ScalableImageDag._withoutRenderables(
      {required double? width,
      required double? height,
      required Color? tintColor,
      required BlendMode tintMode,
      required Rect? viewport,
      Color? currentColor,
      required List<SIImage> images})
      : super(
            width, height, tintColor, tintMode, viewport, images, currentColor);

  ///
  /// Creates a new instance of a blank image.
  ///
  ScalableImageDag.blank()
      : _renderables = [],
        super(null, null, null, BlendMode.srcIn, null, const [], null);

  ScalableImageDag._modified(ScalableImageDag other, this._renderables,
      {required Rect? viewport,
      required List<SIImage> images,
      required Color currentColor,
      required Color? tintColor,
      required BlendMode tintMode})
      : super.modifiedFrom(other,
            viewport: viewport,
            currentColor: currentColor,
            tintColor: tintColor,
            tintMode: tintMode,
            images: images);

  ///
  /// Create a copy of [other], potentially with a new viewport.  The copy
  /// will share most of its data with the original, but the tree of renderable
  /// paths will be pruned to contain only those that intersect the new
  /// viewport.
  ///
  static ScalableImageDag modified(ScalableImageDag other,
      {Rect? viewport,
      required bool prune,
      double pruningTolerance = 0,
      required Color currentColor,
      required Color? tintColor,
      required BlendMode tintMode}) {
    final List<SIImage> images;
    final List<SIRenderable> renderables;
    if (prune && viewport != null) {
      final dagger = <SIRenderable>{};
      final imageSet = <SIImage>{};
      renderables = other._childrenPrunedBy(dagger, imageSet,
          PruningBoundary(viewport.deflate(pruningTolerance)));
      images = imageSet.toList(growable: false);
    } else {
      images = other.images;
      renderables = other._renderables;
    }
    return ScalableImageDag._modified(other, renderables,
        viewport: viewport,
        images: images,
        currentColor: currentColor,
        tintColor: tintColor,
        tintMode: tintMode);
  }

  @override
  ScalableImage withNewViewport(Rect viewport,
      {bool prune = false, double pruningTolerance = 0}) {
    return ScalableImageDag.modified(this,
        viewport: viewport,
        prune: prune,
        pruningTolerance: pruningTolerance,
        currentColor: currentColor,
        tintColor: tintColor,
        tintMode: tintMode);
  }

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
    final context = RenderContext.root(this, currentColor);
    for (final r in _renderables) {
      r.paint(c, context);
    }
  }

  @override
  List<SIRenderable> _childrenPrunedBy(
      Set<SIRenderable> dagger, Set<SIImage> imageSet, PruningBoundary b) {
    // Maximize instance sharing with source SI
    _addAll(_renderables, dagger);
    return super._childrenPrunedBy(dagger, imageSet, b);
  }

  void _addAll(List<SIRenderable> children, Set<SIRenderable> dagger) {
    for (final r in children) {
      dagger.add(r);
      r.addChildren(dagger);
    }
  }

  @override
  ScalableImageDag toDag() => this;

  @override
  Uint8List toSIBytes() {
    throw StateError('Cannot convert non-compact ScalableImage to .si bytes');
    // NOTE:  One reason why this is impossible is because Dart's `Path`
    // object is opaque; it does not let us inspect its contents, so a Dart
    // `Path` cannot be externalized.
  }

  @override
  String debugSizeMessage() {
    final Set<SIRenderable> nodes = <SIRenderable>{};
    for (final r in _renderables) {
      nodes.add(r);
      r.addChildren(nodes);
    }
    return '${nodes.length + 1} nodes';
  }
}

abstract class _SIParentBuilder {
  List<SIRenderable> get _renderables;
  RenderContext get context;
}

abstract class _SIParentNode {
  List<SIRenderable> get _renderables;

  List<SIRenderable> _childrenPrunedBy(
      Set<SIRenderable> dagger, Set<SIImage> imageSet, PruningBoundary b) {
    bool changed = false;
    final copy = List<SIRenderable>.empty(growable: true);
    for (final r in _renderables) {
      final rr = r.prunedBy(dagger, imageSet, b);
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

class SIMasked extends SIRenderable with SIMaskedHelper {
  final SIRenderable mask;
  final SIRenderable child;
  final RenderContext context;
  final Rect? maskBounds;
  final bool usesLuma;

  SIMasked(List<SIRenderable> renderables, this.context, RectT? maskBounds,
      this.usesLuma)
      : mask = renderables[0],
        child = renderables[1],
        maskBounds = convertRectTtoRect(maskBounds) {
    assert(renderables.length == 2);
  }

  SIMasked._modified(
      this.mask, this.child, this.context, this.maskBounds, this.usesLuma);

  @override
  void paint(Canvas c, RenderContext context) {
    Rect? bounds = maskBounds;
    // If they specify a bounds, trust them that it's not too big.  If
    // they didn't...
    if (bounds == null) {
      // Graphics memory is a scarce resource enough resource that it's
      // probably worth the time to calculate the intersection of our
      // childrens' bounds.
      bounds = mask.getBoundary()?.getBounds();
      final childB = child.getBoundary()?.getBounds();
      if (bounds == null) {
        bounds = childB;
      } else if (childB != null) {
        bounds = bounds.intersect(childB);
      }
    }
    startMask(c, bounds);
    mask.paint(c, context);
    if (usesLuma) {
      startLumaMask(c, bounds);
      mask.paint(c, context);
      finishLumaMask(c);
    }
    startChild(c, bounds);
    child.paint(c, context);
    finishMasked(c);
  }

  @override
  PruningBoundary? getBoundary() {
    final mb = mask.getBoundary();
    final cb = child.getBoundary();
    if (mb == null || cb == null) {
      return null;
    }
    final mbb = mb.getBounds();
    final cbb = cb.getBounds();
    // Intersecting the two is hard, but conservatively returning
    // the one with less area is a reasonable heuristic.
    if (mbb.height * mbb.width > cbb.height * cbb.width) {
      return cb;
    } else {
      return mb;
    }
  }

  @override
  SIRenderable? prunedBy(
      Set<SIRenderable> dagger, Set<SIImage> imageSet, PruningBoundary b) {
    final mp = mask.prunedBy(dagger, imageSet, b);
    if (mp == null) {
      return null;
    }
    final cp = child.prunedBy(dagger, imageSet, b);
    if (cp == null) {
      return null;
    }
    final m = SIMasked._modified(mp, cp, context, maskBounds, usesLuma);
    final mg = dagger.lookup(m);
    if (mg != null) {
      assert(mg is SIMasked);
      return mg;
    }
    dagger.add(m);
    return m;
  }

  @override
  void addChildren(Set<SIRenderable> dagger) {
    dagger.add(mask);
    mask.addChildren(dagger);
    dagger.add(child);
    child.addChildren(dagger);
  }

  @override
  bool operator ==(final Object other) {
    if (identical(this, other)) {
      return true;
    } else if (other is! SIMasked) {
      return false;
    } else {
      return context == other.context &&
          mask == other.mask &&
          child == other.child &&
          maskBounds == other.maskBounds;
    }
  }

  @override
  late final int hashCode =
      0xac33fb5e ^ Object.hash(context, mask, child, maskBounds);
}

class SIGroup extends SIRenderable with _SIParentNode, SIGroupHelper {
  @override
  final List<SIRenderable> _renderables;
  final int? groupAlpha;
  final RenderContext context;

  SIGroup(Iterable<SIRenderable> renderables, this.groupAlpha, this.context)
      : _renderables = List.unmodifiable(renderables);

  SIGroup._modified(SIGroup other, this._renderables)
      : context = other.context,
        groupAlpha = other.groupAlpha;

  @override
  List<SIRenderable> _childrenPrunedBy(
      Set<SIRenderable> dagger, Set<SIImage> imageSet, PruningBoundary b) {
    b = context.transformBoundaryFromParent(b);
    return super._childrenPrunedBy(dagger, imageSet, b);
  }

  @override
  PruningBoundary? getBoundary() =>
      context.transformBoundaryFromChildren(super.getBoundary());

  @override
  void paint(Canvas c, RenderContext context) {
    startPaintGroup(c, this.context.transform, groupAlpha);
    for (final r in _renderables) {
      r.paint(c, this.context);
    }
    endPaintGroup(c);
  }

  @override
  SIGroup? prunedBy(
      Set<SIRenderable> dagger, Set<SIImage> imageSet, PruningBoundary b) {
    final rr = _childrenPrunedBy(dagger, imageSet, b);
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
  void addChildren(Set<SIRenderable> dagger) {
    for (final r in _renderables) {
      dagger.add(r);
      r.addChildren(dagger);
    }
  }

  @override
  bool operator ==(final Object other) {
    if (identical(this, other)) {
      return true;
    } else if (other is! SIGroup) {
      return false;
    } else {
      return context == other.context &&
          groupAlpha == other.groupAlpha &&
          quiver.listsEqual(_renderables, other._renderables);
    }
  }

  @override
  late final int hashCode = 0xfddf5e28 ^
      quiver.hash3(
        quiver.hashObjects(_renderables),
        groupAlpha,
        context,
      );
}

class _GroupBuilder implements _SIParentBuilder {
  @override
  final List<SIRenderable> _renderables;
  final int? groupAlpha;
  @override
  final RenderContext context;

  _GroupBuilder(this.context, this.groupAlpha)
      : _renderables = List<SIRenderable>.empty(growable: true);

  SIGroup get group => SIGroup(_renderables, groupAlpha, context);
}

class _MaskedBuilder implements _SIParentBuilder {
  @override
  final List<SIRenderable> _renderables;
  @override
  final RenderContext context;
  final RectT? maskBounds;
  final bool usesLuma;

  _MaskedBuilder(this.context, this.maskBounds, this.usesLuma)
      : _renderables = List<SIRenderable>.empty(growable: true);

  SIRenderable get masked =>
      SIMasked(_renderables, context, maskBounds, usesLuma);
}

///
/// See [PathBuilder] for usage.
///
abstract class SIGenericDagBuilder<PathDataT, IM>
    extends SIBuilder<PathDataT, IM> implements _SIParentBuilder {
  @override
  final _renderables = List<SIRenderable>.empty(growable: true);
  double? _width;
  double? _height;
  int? _tintColor;
  SITintMode? _tintMode;
  final Rect? _viewport;
  @override
  final bool warn;
  final _parentStack = List<_SIParentBuilder>.empty(growable: true);
  ScalableImageDag? _si;
  late final List<SIImage> _images;
  late final List<String> _strings;
  late final List<List<double>> _floatLists;
  final _paths = <Object?, Path>{};
  final Set<Object> _dagger = <Object>{};
  final Color? currentColor;
  @override
  late final RenderContext context;

  SIGenericDagBuilder(this._viewport, this.warn, this.currentColor);

  T _daggerize<T extends Object>(T r) {
    var result = _dagger.lookup(r);
    if (result == null) {
      result = r;
      _dagger.add(result);
    }
    return result as T;
  }

  PathDataT immutableKey(PathDataT key);

  @override
  void get initial {}

  @override
  void path(void collector, PathDataT pathData, SIPaint paint) {
    final p = _daggerize(SIPath(_getPath(pathData), _daggerize(paint)));
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
  PathBuilder? startPath(SIPaint paint, Object key) {
    final p = _paths[key];
    if (p != null) {
      final sip = _daggerize(SIPath(p, paint));
      addRenderable(sip);
      return null;
    }
    return UIPathBuilder(onEnd: (pb) {
      _paths[key] = pb.path;
      final p = _daggerize(SIPath(pb.path, paint));
      addRenderable(p);
    });
  }

  void makePath(PathDataT pathData, PathBuilder pb, {bool warn = true});

  @override
  void init(void collector, List<IM> im, List<String> strings,
      List<List<double>> floatLists) {
    _images = convertImages(im);
    _strings = strings;
    _floatLists = floatLists;
    assert(_si == null);
    final a = _si = ScalableImageDag._withoutRenderables(
        width: _width,
        height: _height,
        viewport: _viewport,
        tintColor: (_tintColor == null) ? null : Color(_tintColor!),
        tintMode: (_tintMode ?? SITintModeMapping.defaultValue).asBlendMode,
        currentColor: currentColor,
        images: _images);
    context = RenderContext.root(a, a.currentColor);
    _parentStack.add(this);
  }

  List<SIImage> convertImages(List<IM> images);

  @override
  void image(void collector, int imageIndex) =>
      addRenderable(_images[imageIndex]);

  @override
  @mustCallSuper
  void text(void collector, int xIndex, int yIndex, int textIndex,
      SITextAttributes a, int? fontFamilyIndex, SIPaint paint) {
    addRenderable(SIText(_strings[textIndex], _floatLists[xIndex],
        _floatLists[yIndex], a, _daggerize(paint)));
  }

  ScalableImageDag get si {
    final r = _si;
    if (r == null) {
      throw ParseError('No vector element');
    } else {
      r._renderables = List.unmodifiable(_renderables);
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
  void group(void collector, Affine? transform, int? groupAlpha) {
    if (transform != null) {
      transform = _daggerize(transform);
    }
    final g = _GroupBuilder(
        RenderContext(_parentStack.last.context, transform: transform),
        groupAlpha);
    _parentStack.add(g);
  }

  @override
  void endGroup(void collector) {
    final gb = _parentStack.last as _GroupBuilder;
    _parentStack.length = _parentStack.length - 1;
    addRenderable(_daggerize(gb.group));
  }

  @override
  void masked(void collector, RectT? maskBounds, bool usesLuma) {
    final mb = _MaskedBuilder(
        RenderContext(_parentStack.last.context), maskBounds, usesLuma);
    _parentStack.add(mb);
  }

  @override
  void maskedChild(void collector) {
    assert(_parentStack.last is _MaskedBuilder);
  }

  @override
  void endMasked(void collector) {
    final mb = _parentStack.last as _MaskedBuilder;
    _parentStack.length = _parentStack.length - 1;
    addRenderable(_daggerize(mb.masked));
  }
}

class SIDagBuilder extends SIGenericDagBuilder<String, SIImageData>
    with SIStringPathMaker {
  SIDagBuilder({required bool warn, Color? currentColor})
      : super(null, warn, currentColor);

  @override
  List<SIImage> convertImages(List<SIImageData> images) =>
      List<SIImage>.generate(images.length, (i) => SIImage(images[i]),
          growable: false);
}
