/*
Copyright (c) 2021-2025, William Foote

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
library;

import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
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
  ScalableImageDag.forTesting({
    required double? width,
    required double? height,
    required Color? tintColor,
    required BlendMode tintMode,
    required Rect? viewport,
    Color? currentColor,
    required List<SIImage> images,
  })  : _renderables = const [],
        super(
          width,
          height,
          tintColor,
          tintMode,
          viewport,
          images,
          currentColor,
        );

  ScalableImageDag._withoutRenderables({
    required double? width,
    required double? height,
    required Color? tintColor,
    required BlendMode tintMode,
    required Rect? viewport,
    Color? currentColor,
    required List<SIImage> images,
  }) : super(
          width,
          height,
          tintColor,
          tintMode,
          viewport,
          images,
          currentColor,
        );

  ///
  /// Creates a new instance of a blank image.
  ///
  ScalableImageDag.blank()
      : _renderables = [],
        super(null, null, null, BlendMode.srcIn, null, const [], null);

  ScalableImageDag._modified(
    ScalableImageDag super.other,
    this._renderables, {
    required super.viewport,
    required super.images,
    required super.currentColor,
    required super.tintColor,
    required super.tintMode,
  }) : super.modifiedFrom();

  ///
  /// Create a copy of [other], potentially with a new viewport.  The copy
  /// will share most of its data with the original, but the tree of renderable
  /// paths will be pruned to contain only those that intersect the new
  /// viewport.
  ///
  static ScalableImageDag modified(
    ScalableImageDag other, {
    Rect? viewport,
    required bool prune,
    double pruningTolerance = 0,
    required Color currentColor,
    required Color? tintColor,
    required BlendMode tintMode,
  }) {
    final List<SIImage> images;
    final List<SIRenderable> renderables;
    if (prune && viewport != null) {
      final dagger = <SIRenderable>{};
      final imageSet = <SIImage>{};
      renderables = other._childrenPrunedBy(
        dagger,
        imageSet,
        PruningBoundary(viewport.deflate(pruningTolerance)),
      );
      images = imageSet.toList(growable: false);
    } else {
      images = other.images;
      renderables = other._renderables;
    }
    return ScalableImageDag._modified(
      other,
      renderables,
      viewport: viewport,
      images: images,
      currentColor: currentColor,
      tintColor: tintColor,
      tintMode: tintMode,
    );
  }

  @override
  ScalableImage withNewViewport(
    Rect viewport, {
    bool prune = false,
    double pruningTolerance = 0,
  }) {
    return ScalableImageDag.modified(
      this,
      viewport: viewport,
      prune: prune,
      pruningTolerance: pruningTolerance,
      currentColor: currentColor,
      tintColor: tintColor,
      tintMode: tintMode,
    );
  }

  @override
  ScalableImage modifyCurrentColor(Color newCurrentColor) {
    return ScalableImageDag.modified(
      this,
      viewport: viewport,
      prune: false,
      pruningTolerance: 0,
      currentColor: newCurrentColor,
      tintColor: tintColor,
      tintMode: tintMode,
    );
  }

  @override
  ScalableImage modifyTint({
    required BlendMode newTintMode,
    required Color? newTintColor,
  }) {
    return ScalableImageDag.modified(
      this,
      viewport: viewport,
      prune: false,
      pruningTolerance: 0,
      currentColor: currentColor,
      tintColor: newTintColor,
      tintMode: newTintMode,
    );
  }

  @override
  void paintChildren(Canvas c, Color currentColor) {
    for (final r in _renderables) {
      r.paint(c, currentColor);
    }
  }

  @override
  List<SIRenderable> _childrenPrunedBy(
    Set<Object> dagger,
    Set<SIImage> imageSet,
    PruningBoundary b,
  ) {
    // Maximize instance sharing with source SI
    _addAll(_renderables, dagger);
    return super._childrenPrunedBy(dagger, imageSet, b);
  }

  void _addAll(List<SIRenderable> children, Set<Object> dagger) {
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
    // NOTE:  This is impossible is because Dart's `Path`
    // object is opaque; it does not let us inspect its contents, so a Dart
    // `Path` cannot be externalized.
  }

  @override
  String debugSizeMessage() {
    final Set<Object> nodes = <SIRenderable>{};
    for (final r in _renderables) {
      nodes.add(r);
      r.addChildren(nodes);
    }
    return '${nodes.length + 1} nodes';
  }

  void privateAssertIsEquivalent(ScalableImageDag other) {
    if (_renderables.length != other._renderables.length) {
      throw StateError('');
    }
    for (int i = 0; i < _renderables.length; i++) {
      _renderables[i].privateAssertIsEquivalent(other._renderables[i]);
    }
    if (width != other.width ||
        height != other.height ||
        tintMode != other.tintMode ||
        tintColor != other.tintColor ||
        currentColor != other.currentColor ||
        viewport != other.viewport) {
      throw StateError('');
    }
  }
}

class ScalableImageDagNotExported {
  static void addAllToDagger(ScalableImageDag si, Set<Object> dagger) {
    si._addAll(si._renderables, dagger);
  }
}

abstract class _SIParentBuilder {
  List<SIRenderable> get _renderables;
}

abstract mixin class _SIParentNode {
  List<SIRenderable> get _renderables;

  List<SIRenderable> _childrenPrunedBy(
    Set<Object> dagger,
    Set<SIImage> imageSet,
    PruningBoundary b,
  ) {
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

  PruningBoundary? getBoundary(
    List<ExportedIDBoundary>? exportedIDs,
    Affine? exportedIDXform,
  ) {
    PruningBoundary? result;
    for (final r in _renderables) {
      final b = r.getBoundary(exportedIDs, exportedIDXform);
      if (result == null) {
        result = b;
      } else if (b != null) {
        result = PruningBoundary(
          result.getBounds().expandToInclude(b.getBounds()),
        );
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
  final Rect? maskBounds;
  final bool usesLuma;

  SIMasked(List<SIRenderable> renderables, RectT? maskBounds, this.usesLuma)
      : mask = renderables[0],
        child = renderables[1],
        maskBounds = convertRectTtoRect(maskBounds) {
    assert(renderables.length == 2);
  }

  SIMasked._modified(this.mask, this.child, this.maskBounds, this.usesLuma);

  @override
  void paint(Canvas c, Color currentColor) {
    Rect? bounds = maskBounds;
    startMask(c, bounds);
    mask.paint(c, currentColor);
    if (usesLuma) {
      startLumaMask(c, bounds);
      mask.paint(c, currentColor);
      finishLumaMask(c);
    }
    startChild(c, bounds);
    child.paint(c, currentColor);
    finishMasked(c);
  }

  @override
  PruningBoundary? getBoundary(
    List<ExportedIDBoundary>? exportedIDs,
    Affine? exportedIDXform,
  ) {
    final mb = mask.getBoundary(exportedIDs, exportedIDXform);
    final cb = child.getBoundary(exportedIDs, exportedIDXform);
    if (mb == null || cb == null) {
      return null;
    }
    final mbb = mb.getBounds();
    final cbb = cb.getBounds();
    final ibb = mbb.intersect(cbb);
    if (ibb.width < 0.0 || ibb.height <= 0.0) {
      return null;
    }
    final mbba = mbb.height * mbb.width;
    final cbba = cbb.height * cbb.width;
    final ibba = ibb.height * ibb.width;

    // Truly intersecting two boundaries is hard.  If the intersection's
    // bounding box is smaller than either of the two bounding boxes, we
    // go with that.  Otherwise, we go with the boundary that has the smaller
    // bounding box.
    if (mbba > cbba) {
      if (cbba <= ibba) {
        return cb;
      }
    } else {
      if (mbba <= ibba) {
        return mb;
      }
    }
    return PruningBoundary(ibb);
  }

  @override
  SIRenderable? prunedBy(
    Set<Object> dagger,
    Set<SIImage> imageSet,
    PruningBoundary b,
  ) {
    final mp = mask.prunedBy(dagger, imageSet, b);
    if (mp == null) {
      return null;
    }
    final cp = child.prunedBy(dagger, imageSet, b);
    if (cp == null) {
      return null;
    }
    final m = SIMasked._modified(mp, cp, maskBounds, usesLuma);
    final mg = dagger.lookup(m);
    if (mg != null) {
      assert(mg is SIMasked);
      return mg as SIMasked;
    }
    dagger.add(m);
    return m;
  }

  @override
  void addChildren(Set<Object> dagger) {
    dagger.add(mask);
    mask.addChildren(dagger);
    dagger.add(child);
    child.addChildren(dagger);
  }

  @override
  void privateAssertIsEquivalent(final SIRenderable other) {
    if (identical(this, other)) {
      return;
    } else if (other is! SIMasked || maskBounds != other.maskBounds) {
      throw StateError('$this  $other');
    } else {
      mask.privateAssertIsEquivalent(other.mask);
      child.privateAssertIsEquivalent(other.child);
    }
  }

  @override
  bool operator ==(final Object other) {
    if (identical(this, other)) {
      return true;
    } else if (other is! SIMasked) {
      return false;
    } else {
      return mask == other.mask &&
          child == other.child &&
          maskBounds == other.maskBounds;
    }
  }

  @override
  late final int hashCode = 0xac33fb5e ^ Object.hash(mask, child, maskBounds);
}

class SIGroup extends SIRenderable with _SIParentNode, SIGroupHelper {
  @override
  final List<SIRenderable> _renderables;
  final int? groupAlpha;
  final BlendMode? blendMode;
  final Affine? transform;

  SIGroup(
    Iterable<SIRenderable> renderables,
    this.groupAlpha,
    this.transform,
    SIBlendMode blendMode,
  )   : _renderables = List.unmodifiable(renderables),
        blendMode = blendMode.asBlendMode;

  SIGroup._modified(SIGroup other, this._renderables)
      : transform = other.transform,
        groupAlpha = other.groupAlpha,
        blendMode = other.blendMode;

  @override
  List<SIRenderable> _childrenPrunedBy(
    Set<Object> dagger,
    Set<SIImage> imageSet,
    PruningBoundary b,
  ) {
    b = Transformer.transformBoundaryFromParent(transform, b)!;
    return super._childrenPrunedBy(dagger, imageSet, b);
  }

  @override
  PruningBoundary? getBoundary(
    List<ExportedIDBoundary>? exportedIDs,
    Affine? exportedIDXform,
  ) {
    if (exportedIDXform != null) {
      final t = transform;
      if (t != null) {
        final nt = exportedIDXform.mutableCopy();
        nt.multiplyBy(t.toMutable);
        exportedIDXform = nt;
      }
    }
    return Transformer.transformBoundaryFromChildren(
      transform,
      super.getBoundary(exportedIDs, exportedIDXform),
    );
  }

  @override
  void paint(Canvas c, Color currentColor) {
    startPaintGroup(c, transform, groupAlpha, blendMode);
    for (final r in _renderables) {
      r.paint(c, currentColor);
    }
    endPaintGroup(c);
  }

  @override
  SIGroup? prunedBy(
    Set<Object> dagger,
    Set<SIImage> imageSet,
    PruningBoundary b,
  ) {
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
  void addChildren(Set<Object> dagger) {
    for (final r in _renderables) {
      dagger.add(r);
      r.addChildren(dagger);
    }
  }

  @override
  void privateAssertIsEquivalent(SIRenderable other) {
    if (identical(this, other)) {
      return;
    } else if (other is! SIGroup ||
        transform != other.transform ||
        groupAlpha != other.groupAlpha ||
        _renderables.length != other._renderables.length) {
      throw StateError('$this $other'); // coverage:ignore-line
    } else {
      for (int i = 0; i < _renderables.length; i++) {
        _renderables[i].privateAssertIsEquivalent(other._renderables[i]);
      }
    }
  }

  @override
  bool operator ==(final Object other) {
    if (identical(this, other)) {
      return true;
    } else if (other is! SIGroup) {
      return false;
    } else {
      return transform == other.transform &&
          groupAlpha == other.groupAlpha &&
          _renderables.equals(other._renderables);
    }
  }

  @override
  late final int hashCode = 0xfddf5e28 ^
      Object.hash(Object.hashAll(_renderables), groupAlpha, transform);
}

class _GroupBuilder implements _SIParentBuilder {
  @override
  final List<SIRenderable> _renderables;
  final int? groupAlpha;
  final SIBlendMode blendMode;
  final Affine? transform;

  _GroupBuilder(this.transform, this.groupAlpha, this.blendMode)
      : _renderables = List<SIRenderable>.empty(growable: true);

  SIGroup get group => SIGroup(_renderables, groupAlpha, transform, blendMode);
}

class SIExportedID extends SIRenderable with _SIParentNode, SIGroupHelper {
  @override
  final List<SIRenderable> _renderables;
  final String id;

  SIExportedID(SIRenderable renderable, this.id)
      : _renderables = List.unmodifiable([renderable]);

  @override
  PruningBoundary? getBoundary(
    List<ExportedIDBoundary>? exportedIDs,
    Affine? exportedIDXform,
  ) {
    final result = _renderables[0].getBoundary(exportedIDs, exportedIDXform);
    if (exportedIDs != null) {
      final b = Transformer.transformBoundaryFromChildren(
        exportedIDXform,
        result,
      );
      if (b != null) {
        exportedIDs.add(ExportedIDBoundary(id, b));
      }
    }
    return result;
  }

  @override
  void paint(Canvas c, Color currentColor) {
    _renderables[0].paint(c, currentColor);
  }

  @override
  SIExportedID? prunedBy(
    Set<Object> dagger,
    Set<SIImage> imageSet,
    PruningBoundary b,
  ) {
    final rr = _childrenPrunedBy(dagger, imageSet, b);
    if (rr.isEmpty) {
      return null;
    }
    if (identical(rr, _renderables)) {
      return this;
    }
    assert(rr.length == 1);
    final result = SIExportedID(rr[0], id);
    final dr = dagger.lookup(result);
    if (dr != null) {
      return dr as SIExportedID;
    }
    dagger.add(result);
    return result;
  }

  @override
  void addChildren(Set<Object> dagger) {
    final r = _renderables[0];
    dagger.add(r);
    r.addChildren(dagger);
  }

  @override
  void privateAssertIsEquivalent(SIRenderable other) {
    if (identical(this, other)) {
      return;
    } else if (other is! SIExportedID ||
        id != other.id ||
        _renderables.length != other._renderables.length) {
      throw StateError('$this $other'); // coverage:ignore-line
    } else {
      _renderables[0].privateAssertIsEquivalent(other._renderables[0]);
    }
  }

  @override
  bool operator ==(final Object other) {
    if (identical(this, other)) {
      return true;
    } else if (other is! SIExportedID) {
      return false;
    } else {
      return id == other.id && _renderables.equals(other._renderables);
    }
  }

  @override
  late final int hashCode = 0x34686816 ^ Object.hash(_renderables[0], id);
}

class _ExportedIdBuilder implements _SIParentBuilder {
  @override
  final List<SIRenderable> _renderables;
  final String id;

  _ExportedIdBuilder(this.id)
      : _renderables = List<SIRenderable>.empty(growable: true);

  SIExportedID? get exportedIdNode {
    if (_renderables.isEmpty) {
      return null;
    }
    assert(_renderables.length == 1);
    return SIExportedID(_renderables[0], id);
  }
}

class _MaskedBuilder implements _SIParentBuilder {
  @override
  final List<SIRenderable> _renderables;
  final RectT? maskBounds;
  final bool usesLuma;

  _MaskedBuilder(this.maskBounds, this.usesLuma)
      : _renderables = List<SIRenderable>.empty(growable: true);

  SIRenderable get masked => SIMasked(_renderables, maskBounds, usesLuma);
}

abstract class SIGenericDagBuilder<PathDataT, IM>
    extends SIBuilder<PathDataT, IM>
    with SITextHelper<void>
    implements _SIParentBuilder {
  @override
  final _renderables = List<SIRenderable>.empty(growable: true);
  double? _width;
  double? _height;
  int? _tintColor;
  SITintMode? _tintMode;
  final Rect? _givenViewport;
  @override
  final void Function(String) warn;
  final _parentStack = List<_SIParentBuilder>.empty(growable: true);
  ScalableImageDag? _si;
  @protected
  late final List<SIImage> images;
  @protected
  @override
  late final List<String> strings;
  @protected
  late final List<List<double>> floatLists;
  @protected
  @override
  late final List<List<String>> stringLists;
  @protected
  @override
  late final List<double> floatValues;
  final paths = <Object?, Path>{};
  final Set<Object> dagger = <Object>{};
  final Color? currentColor;

  SIGenericDagBuilder(this._givenViewport, this.warn, this.currentColor);

  T _daggerize<T extends Object>(T r) {
    var result = dagger.lookup(r);
    if (result == null) {
      result = r;
      dagger.add(result);
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
    final key = immutableKey(pathData);
    final p = paths[key];
    if (p != null) {
      return p;
    }
    final pb = UIPathBuilder();
    makePath(pathData, pb, warn: warn);
    return paths[key] = pb.path;
  }

  @override
  EnhancedPathBuilder? startPath(SIPaint paint, Object key) {
    final p = paths[key];
    if (p != null) {
      final sip = _daggerize(SIPath(p, paint));
      addRenderable(sip);
      return null;
    }
    return UIPathBuilder(
      onEnd: (pb) {
        paths[key] = pb.path;
        final p = _daggerize(SIPath(pb.path, paint));
        addRenderable(p);
      },
    );
  }

  void makePath(
    PathDataT pathData,
    EnhancedPathBuilder pb, {
    required void Function(String) warn,
  });

  @override
  void init(
    void collector,
    List<IM> im,
    List<String> strings,
    List<List<double>> floatLists,
    List<List<String>> stringLists,
    List<double> floatValues,
    CMap<double>? floatValueMap,
  ) {
    images = convertImages(im);
    this.strings = strings;
    this.floatLists = floatLists;
    this.stringLists = stringLists;
    this.floatValues = floatValues;
    assert(_si == null);
    _si = ScalableImageDag._withoutRenderables(
      width: _width,
      height: _height,
      viewport: _givenViewport,
      tintColor: (_tintColor == null) ? null : Color(_tintColor!),
      tintMode: (_tintMode ?? SITintModeMapping.defaultValue).asBlendMode,
      currentColor: currentColor,
      images: images,
    );
    _parentStack.add(this);
  }

  List<SIImage> convertImages(List<IM> images);

  @override
  void image(void collector, int imageIndex) =>
      addRenderable(images[imageIndex]);

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
  void vector({
    required double? width,
    required double? height,
    required int? tintColor,
    required SITintMode? tintMode,
  }) {
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
  void group(
    void collector,
    Affine? transform,
    int? groupAlpha,
    SIBlendMode blend,
  ) {
    if (transform != null) {
      transform = _daggerize(transform);
    }
    final g = _GroupBuilder(transform, groupAlpha, blend);
    _parentStack.add(g);
  }

  @override
  void endGroup(void collector) {
    final gb = _parentStack.last as _GroupBuilder;
    _parentStack.length = _parentStack.length - 1;
    addRenderable(_daggerize(gb.group));
  }

  @override
  void exportedID(void collector, int idIndex) {
    final id = strings[idIndex];
    final b = _ExportedIdBuilder(id);
    _parentStack.add(b);
  }

  @override
  void endExportedID(void collector) {
    final b = _parentStack.last as _ExportedIdBuilder;
    _parentStack.length = _parentStack.length - 1;
    final node = b.exportedIdNode;
    if (node != null) {
      addRenderable(_daggerize(node));
    }
  }

  @override
  void masked(void collector, RectT? maskBounds, bool usesLuma) {
    final mb = _MaskedBuilder(maskBounds, usesLuma);
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

  @override
  @mustCallSuper
  void legacyText(
    void collector,
    int xIndex,
    int yIndex,
    int textIndex,
    SITextAttributes a,
    int? fontFamilyIndex,
    SIPaint paint,
  ) {
    addRenderable(
      SIText.legacy(
        strings[textIndex],
        floatLists[xIndex],
        floatLists[yIndex],
        a,
        _daggerize(paint),
      ),
    );
  }

  @override
  void acceptText(void collector, SIText text) {
    addRenderable(text);
  }
}

class SIDagBuilder extends SIGenericDagBuilder<String, SIImageData>
    with SIStringPathMaker {
  SIDagBuilder({required void Function(String) warn, Color? currentColor})
      : super(null, warn, currentColor);

  @override
  List<SIImage> convertImages(List<SIImageData> images) =>
      List<SIImage>.generate(
        images.length,
        (i) => SIImage(images[i]),
        growable: false,
      );

  @override
  void addPath(Object path, SIPaint paint) {
    final p = _daggerize(SIPath(path as Path, _daggerize(paint)));
    addRenderable(p);
  }
}
