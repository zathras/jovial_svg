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
/// Memory-efficient version of ScalableImage, at the expense of rendering
/// time.  This representation rendered about 3x slower in some informal
/// tests, but occupies perhaps an order of magnitude less memory.
///
library jovial_svg.compact;

import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:jovial_misc/io_utils.dart';
import 'affine.dart';
import 'dag.dart';
import 'common.dart';
import 'common_noui.dart';
import 'compact_noui.dart';
import 'path_noui.dart';
import '../jovial_svg.dart';
import 'path.dart';

///
/// A Scalable Image that's represented by a compact packed binary format
/// that is interpreted when rendering.
///
class ScalableImageCompact extends ScalableImage
    with ScalableImageCompactGeneric<Color, BlendMode, SIImage> {
  @override
  final bool bigFloats;
  final int _numPaths;
  final int _numPaints;
  final List<String> _strings;
  final List<List<double>> _floatLists;
  final Uint8List _children;
  final List<double> _args; // Float32List or Float64List
  final List<double> _transforms; // Float32List or Float64List

  ScalableImageCompact._p(
      {required this.bigFloats,
      required double? width,
      required double? height,
      required Color? tintColor,
      required BlendMode tintMode,
      required Color? currentColor,
      required int numPaths,
      required int numPaints,
      required List<SIImage> images,
      required List<String> strings,
      required List<List<double>> floatLists,
      required Uint8List children,
      required List<double> args,
      required List<double> transforms,
      required Rect? viewport})
      : _numPaths = numPaths,
        _numPaints = numPaints,
        _strings = strings,
        _floatLists = floatLists,
        _children = children,
        _args = args,
        _transforms = transforms,
        super(width, height, tintColor, tintMode, viewport, images,
            currentColor) {
    // @@ TODO remove:
    print('   ${args.length} floats, ${_transforms.length ~/ 6} transforms');
  }

  @override
  ScalableImageCompact withNewViewport(Rect viewport,
      {bool prune = false, double pruningTolerance = 0}) {
    if (prune) {
      final v = _PruningVisitor(this, viewport, pruningTolerance);
      accept(v);
      return v.si;
    } else {
      return ScalableImageCompact._p(
          bigFloats: bigFloats,
          width: width,
          height: height,
          tintColor: tintColor,
          tintMode: tintMode,
          currentColor: currentColor,
          numPaths: _numPaths,
          numPaints: _numPaints,
          strings: _strings,
          floatLists: _floatLists,
          images: images,
          children: _children,
          args: _args,
          transforms: _transforms,
          viewport: viewport);
    }
  }

  @override
  ScalableImage modifyCurrentColor(Color newCurrentColor) {
    return ScalableImageCompact._p(
        bigFloats: bigFloats,
        width: width,
        height: height,
        tintColor: tintColor,
        tintMode: tintMode,
        currentColor: newCurrentColor,
        numPaths: _numPaths,
        numPaints: _numPaints,
        strings: _strings,
        floatLists: _floatLists,
        images: images,
        children: _children,
        args: _args,
        transforms: _transforms,
        viewport: viewport);
  }

  @override
  ScalableImage modifyTint(
      {required BlendMode newTintMode, required Color? newTintColor}) {
    return ScalableImageCompact._p(
        bigFloats: bigFloats,
        width: width,
        height: height,
        tintColor: newTintColor,
        tintMode: newTintMode,
        currentColor: currentColor,
        numPaths: _numPaths,
        numPaints: _numPaints,
        strings: _strings,
        floatLists: _floatLists,
        images: images,
        children: _children,
        args: _args,
        transforms: _transforms,
        viewport: viewport);
  }

  @override
  void paintChildren(Canvas c, Color currentColor) =>
      accept(_PaintingVisitor(c, currentColor));

  @override
  PruningBoundary? getBoundary() => accept(_BoundaryVisitor());

  R accept<R>(SIVisitor<CompactChildData, SIImage, R> visitor) {
    final t = CompactTraverser<R, SIImage>(
        bigFloats: bigFloats,
        strings: _strings,
        floatLists: _floatLists,
        images: images,
        visiteeChildren: _children,
        visiteeArgs: _args,
        visiteeTransforms: _transforms,
        visiteeNumPaths: _numPaths,
        visiteeNumPaints: _numPaints,
        visitor: visitor);
    R r = t.traverse(visitor.initial);
    return r;
  }

  @override
  ScalableImageDag toDag() {
    final b = SIDagBuilderFromCompact(viewport,
        warn: false, currentColor: currentColor);
    b.vector(
        width: width,
        height: height,
        tintColor: tintColor?.value,
        tintMode: SITintModeMapping.fromBlendMode(tintMode));
    accept(b);
    b.endVector();
    return b.si;
  }

  @override
  SITintMode blendModeToSI(BlendMode b) => SITintModeMapping.fromBlendMode(b);

  @override
  int colorValue(Color c) => c.value;

  static ScalableImageCompact fromByteData(ByteData data,
          {Color? currentColor}) =>
      fromBytes(
          Uint8List.view(data.buffer, data.offsetInBytes, data.lengthInBytes),
          currentColor: currentColor);

  static ScalableImageCompact fromBytes(Uint8List data, {Color? currentColor}) {
    final dis = ByteBufferDataInputStream(data, Endian.big);
    final magic = dis.readUnsignedInt();
    if (magic != 0xb0b01e07) {
      throw ParseError('Bad magic number:  0x${magic.toRadixString(16)}');
    }
    dis.readByte();
    final version = dis.readUnsignedShort();
    if (version != 0) {
      throw ParseError('Unsupported version $version');
    }
    final int flags = dis.readUnsignedByte();
    final hasWidth = _flag(flags, 0);
    final hasHeight = _flag(flags, 1);
    final bigFloats = _flag(flags, 2);
    final hasTintColor = _flag(flags, 3);
    final numPaths = dis.readUnsignedInt();
    final numPaints = dis.readUnsignedInt();
    final argsLen = dis.readUnsignedInt();
    final xformsLen = dis.readUnsignedInt();
    final List<double> args = _floatList(dis, bigFloats, argsLen);
    final List<double> transforms = _floatList(dis, bigFloats, xformsLen);
    final width = _readFloat(dis, bigFloats, hasWidth);
    final height = _readFloat(dis, bigFloats, hasHeight);
    final int? tintColor;
    final int tintMode;
    if (hasTintColor) {
      tintColor = dis.readUnsignedInt();
      tintMode = dis.readUnsignedByte();
    } else {
      tintMode = SITintModeMapping.defaultValue.index;
      tintColor = null;
    }
    final children = dis.remainingCopy();
    throw "@@ TODO";
    final initData = Uint8List(0);
    /*
    return ScalableImageCompact._p(
        bigFloats: bigFloats,
        width: width,
        height: height,
        tintColor: tintColor == null ? null : Color(tintColor),
        tintMode: SITintMode.values[tintMode].asBlendMode,
        currentColor: currentColor,
        numPaths: numPaths,
        numPaints: numPaints,
        initData: initData,
        children: children,
        args: args,
        transforms: transforms,
        viewport: null);
     */
  }

  static bool _flag(int byte, int bitNumber) => (byte & (1 << bitNumber)) != 0;

  static List<double> _floatList(
      ByteBufferDataInputStream dis, bool bigFloats, int length) {
    if (bigFloats) {
      Uint8List bytes = dis.readBytes(length * 8);
      ByteData bd = bytes.buffer.asByteData(bytes.offsetInBytes, length * 8);
      final r = Float64List(length);
      for (int i = 0; i < length; i++) {
        r[i] = bd.getFloat64(8 * i, Endian.little);
      }
      return r;
    } else {
      Uint8List bytes = dis.readBytes(length * 4);
      ByteData bd = bytes.buffer.asByteData(bytes.offsetInBytes, length * 4);
      final r = Float32List(length);
      for (int i = 0; i < length; i++) {
        r[i] = bd.getFloat32(4 * i, Endian.little);
      }
      return r;
    }
  }

  static double? _readFloat(
      ByteBufferDataInputStream dis, bool bigFloats, bool notNull) {
    if (notNull) {
      if (bigFloats) {
        return dis.readDouble();
      } else {
        return dis.readFloat();
      }
    } else {
      return null;
    }
  }
}

///
/// Helper for visitors of compact scalable images.  This class adds
/// the creation of renderable SI objects.
///
abstract class _CompactVisitor<R>
    with SIGroupHelper
    implements SIVisitor<CompactChildData, SIImage, R> {
  late final List<String> _strings;
  late final List<List<double>> _floatLists;
  late final List<SIImage> _images;

  @override
  R init(R collector, List<SIImage> images, List<String> strings,
      List<List<double>> floatLists) {
    _images = images;
    _strings = strings;
    _floatLists = floatLists;
    return collector;
  }

  @override
  R path(R collector, CompactChildData pathData, SIPaint paint) {
    final pb = UIPathBuilder();
    CompactPathParser(pathData, pb).parse();
    final p = SIPath(pb.path, paint);
    return siPath(collector, p);
  }

  R siPath(R collector, SIPath p);

  @override
  R clipPath(R collector, CompactChildData pathData) {
    final pb = UIPathBuilder();
    CompactPathParser(pathData, pb).parse();
    final p = SIClipPath(pb.path);
    return siClipPath(collector, p);
  }

  R siClipPath(R collector, SIClipPath path);

  @override
  R text(R collector, int xIndex, int yIndex, int textIndex,
      SITextAttributes ta, int? fontFamilyIndex, SIPaint p) {
    return siText(
        collector,
        SIText(_strings[textIndex], _floatLists[xIndex], _floatLists[yIndex],
            ta, p),
        xIndex,
        yIndex);
  }

  R siText(R collector, SIText text, int xIndex, int yIndex);
}

class _PaintingVisitor extends _CompactVisitor<void> {
  final Canvas canvas;
  final Color currentColor;

  _PaintingVisitor(this.canvas, this.currentColor);

  @override
  void get initial => null;

  @override
  void group(void collector, Affine? transform) =>
      startPaintGroup(canvas, transform);

  @override
  void endGroup(void collector) => endPaintGroup(canvas);

  @override
  void siPath(void collector, SIPath path) => path.paint(canvas, currentColor);

  @override
  void siClipPath(void collector, SIClipPath path) =>
      path.paint(canvas, currentColor);

  @override
  void image(void collector, int imageIndex) =>
      _images[imageIndex].paint(canvas, currentColor);

  @override
  void siText(void collector, SIText text, int xIndex, int yIndex) =>
      text.paint(canvas, currentColor);
}

class _PruningVisitor extends _CompactVisitor<PruningBoundary> {
  final PruningBoundary _boundary;
  final _groupStack = List<_PruningEntry>.empty(growable: true);
  final _PruningBuilder builder;
  ScalableImageCompact? _si;
  CompactChildData? _lastPathData;
  final _theCanon = CanonicalizedData<SIImage>();

  _PruningVisitor(ScalableImageCompact si, Rect viewport, double tolerance)
      : _boundary = PruningBoundary(viewport.deflate(tolerance)),
        builder = _PruningBuilder(
            si.bigFloats,
            ByteSink(),
            (si.bigFloats) ? Float64Sink() : Float32Sink(),
            (si.bigFloats) ? Float64Sink() : Float32Sink(),
            viewport,
            currentColor: si.currentColor,
            warn: false) {
    builder.vector(
        width: viewport.width,
        height: viewport.height,
        tintColor: si.tintColor?.value,
        tintMode: SITintModeMapping.fromBlendMode(si.tintMode));
  }

  @override
  PruningBoundary get initial => _boundary;

  ScalableImageCompact get si {
    final r = _si;
    if (r != null) {
      return r;
    } else {
      builder.endVector();
      builder.setCanon(_theCanon);
      return _si = builder.si;
    }
  }

  @override
  PruningBoundary group(PruningBoundary boundary, Affine? transform) {
    final parent = _groupStack.isEmpty ? null : _groupStack.last;
    _groupStack.add(_PruningEntry(boundary, parent, this, transform));
    return transformBoundaryFromParent(boundary, transform);
  }

  @override
  PruningBoundary endGroup(PruningBoundary boundary) {
    final us = _groupStack.last;
    _groupStack.length = _groupStack.length - 1;
    us.endGroupIfNeeded();
    return us.boundary;
  }

  @override
  PruningBoundary path(
      PruningBoundary boundary, CompactChildData pathData, SIPaint siPaint) {
    assert(_lastPathData == null);
    _lastPathData = CompactChildData.copy(pathData);
    return super.path(boundary, pathData, siPaint);
  }

  @override
  PruningBoundary siPath(PruningBoundary boundary, SIPath path) {
    assert(_lastPathData != null);
    if (path.prunedBy({}, {}, boundary) != null) {
      if (_groupStack.isNotEmpty) {
        _groupStack.last.generateGroupIfNeeded();
      }
      builder.path(null, _lastPathData!, path.siPaint);
    }
    _lastPathData = null;
    return boundary;
  }

  @override
  PruningBoundary clipPath(
      PruningBoundary boundary, CompactChildData pathData) {
    assert(_lastPathData == null);
    _lastPathData = CompactChildData.copy(pathData);
    return super.clipPath(boundary, pathData);
  }

  @override
  PruningBoundary siClipPath(PruningBoundary boundary, SIClipPath cp) {
    assert(_lastPathData != null);
    if (cp.prunedBy({}, {}, boundary) != null) {
      if (_groupStack.isNotEmpty) {
        _groupStack.last.generateGroupIfNeeded();
      }
      builder.clipPath(null, _lastPathData!);
    }
    _lastPathData = null;
    return boundary;
  }

  @override
  PruningBoundary image(PruningBoundary boundary, int imageIndex) {
    final SIImage image = _images[imageIndex];
    if (image.prunedBy({}, {}, boundary) != null) {
      if (_groupStack.isNotEmpty) {
        _groupStack.last.generateGroupIfNeeded();
      }
      int i = _theCanon.getIndex(_theCanon.images, image)!;
      builder.image(null, i);
    }
    return boundary;
  }

  @override
  PruningBoundary siText(
      PruningBoundary boundary, SIText text, int xIndex, int yIndex) {
    if (text.prunedBy({}, {}, boundary) != null) {
      if (_groupStack.isNotEmpty) {
        _groupStack.last.generateGroupIfNeeded();
      }
      final c = _theCanon;
      xIndex = c.getIndex(c.floatLists, _floatLists[xIndex])!;
      yIndex = c.getIndex(c.floatLists, _floatLists[yIndex])!;
      int textIndex = c.getIndex(c.strings, text.text)!;
      SITextAttributes ta = text.attributes;
      int fontFamilyIndex = c.getIndex(c.strings, ta.fontFamily)!;
      SIPaint p = text.siPaint;
      builder.text(null, xIndex, yIndex, textIndex, ta, fontFamilyIndex, p);
    }
    return boundary;
  }
}

class _PruningBuilder extends SIGenericCompactBuilder<CompactChildData, SIImage>
    with _SICompactPathBuilder {
  final Rect viewport;
  final Color? currentColor;

  @override
  void get initial => null;

  _PruningBuilder(bool bigFloats, ByteSink childrenSink, FloatSink args,
      FloatSink transforms, this.viewport,
      {required bool warn, required this.currentColor})
      : super(bigFloats, childrenSink,
            DataOutputSink(childrenSink, Endian.little), args, transforms,
            warn: warn);

  @override
  void init(void collector, List<SIImage> images, List<String> strings,
      List<List<double>> floatLists) {
    // This is a little tricky.  When pruning, we collect the canonicalized
    // data on the fly, and only provide it to our supertype at the end,
    // right before building the SI, so we need to discard this data here, which
    // comes from the graph being pruned.
  }

  ///
  /// Set the canonicalized data.  This can be done right before
  /// calling `si`.
  ///
  void setCanon(CanonicalizedData<SIImage> canon) {
    super.init(null, canon.toList(canon.images), canon.toList(canon.strings),
        canon.toList(canon.floatLists));
  }

  ScalableImageCompact get si {
    assert(done);
    return ScalableImageCompact._p(
        bigFloats: bigFloats,
        width: width,
        height: height,
        tintColor: (tintColor == null) ? null : Color(tintColor!),
        tintMode: tintMode.asBlendMode,
        currentColor: currentColor,
        numPaths: numPaths,
        numPaints: numPaints,
        strings: strings,
        floatLists: floatLists,
        images: images,
        children: childrenSink.toList(),
        args: args.toList(),
        transforms: transforms.toList(),
        viewport: viewport);
  }
}

class _PruningEntry {
  final PruningBoundary boundary;
  final _PruningEntry? parent;
  final _PruningVisitor visitor;
  Affine? transform;

  bool generated = false;

  _PruningEntry(this.boundary, this.parent, this.visitor, this.transform);

  void generateGroupIfNeeded() {
    if (generated) {
      return;
    }
    parent?.generateGroupIfNeeded();
    visitor.builder.group(null, transform);
    generated = true;
  }

  void endGroupIfNeeded() {
    if (generated) {
      visitor.builder.endGroup(null);
    }
  }
}

class _BoundaryVisitor extends _CompactVisitor<PruningBoundary?> {
  PruningBoundary? boundary;
  final groupStack = List<_BoundaryEntry>.empty(growable: true);

  _BoundaryVisitor();

  @override
  PruningBoundary? get initial => null;

  @override
  PruningBoundary? group(PruningBoundary? initial, Affine? transform) {
    groupStack.add(_BoundaryEntry(initial, transform));
    return null;
  }

  @override
  PruningBoundary? endGroup(PruningBoundary? children) {
    _BoundaryEntry us = groupStack.last;
    groupStack.length = groupStack.length - 1;

    return combine(
        us.initial, us.transformBoundaryFromChildren(children, us.transform));
  }

  @override
  PruningBoundary? siPath(PruningBoundary? initial, SIPath path) {
    return combine(initial, path.getBoundary());
  }

  @override
  PruningBoundary? siClipPath(PruningBoundary? initial, SIClipPath cp) {
    return combine(initial, cp.getBoundary());
  }

  PruningBoundary? combine(PruningBoundary? a, PruningBoundary? b) {
    if (a == null) {
      return b;
    } else if (b == null) {
      return a;
    } else {
      return PruningBoundary(a.getBounds().expandToInclude(b.getBounds()));
      // See comment in _SIParentNode.getBoundary();
    }
  }

  @override
  PruningBoundary? image(PruningBoundary? collector, int imageIndex) {
    return combine(boundary, _images[imageIndex].getBoundary());
  }

  @override
  PruningBoundary? siText(
      PruningBoundary? boundary, SIText text, int xIndex, int yIndex) {
    return combine(boundary, text.getBoundary());
  }
}

class _BoundaryEntry with SIGroupHelper {
  final PruningBoundary? initial;
  final Affine? transform;

  _BoundaryEntry(this.initial, this.transform);
}

mixin _SICompactPathBuilder {
  void makePath(CompactChildData pathData, PathBuilder pb, {bool warn = true}) {
    try {
      CompactPathParser(pathData, pb).parse();
    } catch (e) {
      if (warn) {
        print(e);
        // As per the SVG spec, paths shall be parsed up to the first error,
        // and it is recommended that errors be reported to the user if
        // posible.
      }
    }
  }

  CompactChildData immutableKey(CompactChildData key) =>
      CompactChildData.copy(key);
}

class SIDagBuilderFromCompact
    extends SIGenericDagBuilder<CompactChildData, SIImage>
    with _SICompactPathBuilder {
  SIDagBuilderFromCompact(Rect? viewport,
      {required bool warn, Color? currentColor})
      : super(viewport, warn, currentColor);

  @override
  List<SIImage> convertImages(List<SIImage> images) => images;
}

abstract class _SICompactBuilder<PathDataT extends Object>
    extends SIGenericCompactBuilder<PathDataT, SIImageData> {
  _SICompactBuilder(
      bool bigFloats,
      ByteSink childrenSink,
      DataOutputSink children,
      FloatSink args,
      FloatSink transforms,
      this.viewport,
      {required bool warn,
      this.currentColor})
      : super(bigFloats, childrenSink, children, args, transforms, warn: warn);

  final Color? currentColor;
  final Rect? viewport;

  ScalableImageCompact get si {
    assert(done);
    return ScalableImageCompact._p(
        bigFloats: bigFloats,
        width: width,
        height: height,
        tintColor: (tintColor == null) ? null : Color(tintColor!),
        tintMode: tintMode.asBlendMode,
        currentColor: currentColor,
        numPaths: numPaths,
        numPaints: numPaints,
        strings: strings,
        floatLists: floatLists,
        images:
            List<SIImage>.generate(images.length, (i) => SIImage(images[i])),
        children: childrenSink.toList(),
        args: args.toList(),
        transforms: transforms.toList(),
        viewport: viewport);
  }
}

class SICompactBuilder extends SIGenericCompactBuilder<String, SIImageData>
    with SIStringPathMaker {
  final Color? currentColor;

  SICompactBuilder._p(bool bigFloats, ByteSink childrenSink, FloatSink args,
      FloatSink transforms, {required bool warn, this.currentColor})
      : super(bigFloats, childrenSink,
            DataOutputSink(childrenSink, Endian.little), args, transforms,
            warn: warn);

  @override
  void get initial => null;

  factory SICompactBuilder(
      {required bool bigFloats, required bool warn, Color? currentColor}) {
    final cs = ByteSink();
    final a = bigFloats ? Float64Sink() : Float32Sink();
    final t = bigFloats ? Float64Sink() : Float32Sink();
    try {
      return SICompactBuilder._p(bigFloats, cs, a, t,
          warn: warn, currentColor: currentColor);
    } finally {
      cs.close();
    }
  }

  ScalableImageCompact get si {
    assert(done);
    return ScalableImageCompact._p(
        bigFloats: bigFloats,
        width: width,
        height: height,
        tintColor: (tintColor == null) ? null : Color(tintColor!),
        tintMode: tintMode.asBlendMode,
        currentColor: currentColor,
        numPaths: numPaths,
        numPaints: numPaints,
        strings: strings,
        floatLists: floatLists,
        images:
            List<SIImage>.generate(images.length, (i) => SIImage(images[i])),
        children: childrenSink.toList(),
        args: args.toList(),
        transforms: transforms.toList(),
        viewport: null);
  }
}
