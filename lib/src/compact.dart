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

/// Memory-efficient version of ScalableImage
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
    with ScalableImageCompactGeneric<Color, BlendMode> {
  @override
  final bool bigFloats;
  final int _numPaths;
  final int _numPaints;
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
      required Uint8List children,
      required List<double> args,
      required List<double> transforms,
      required Rect? viewport})
      : _numPaths = numPaths,
        _numPaints = numPaints,
        _children = children,
        _args = args,
        _transforms = transforms,
        super(width, height, tintColor, tintMode, viewport, <SIImage>[], currentColor) {
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

  R accept<R>(SIVisitor<CompactChildData, R> visitor) {
    final t = CompactTraverser<R>(
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
    b.images(null, <SIImageData>[]);  // @@ TODO
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
    return ScalableImageCompact._p(
        bigFloats: bigFloats,
        width: width,
        height: height,
        tintColor: tintColor == null ? null : Color(tintColor),
        tintMode: SITintMode.values[tintMode].asBlendMode,
        currentColor: currentColor,
        numPaths: numPaths,
        numPaints: numPaints,
        children: children,
        args: args,
        transforms: transforms,
        viewport: null);
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
/// the creation of renderable SIPath objects.
///
abstract class _CompactVisitor<R>
    with SIGroupHelper
    implements SIVisitor<CompactChildData, R> {
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
  void siPath(void collector, SIPath path) {
    path.paint(canvas, currentColor);
  }

  @override
  void siClipPath(void collector, SIClipPath path) {
    path.paint(canvas, currentColor);
  }

  @override
  void images(void collector, List<SIImageData> im) {
    throw UnimplementedError("@@ TODO");
  }

  @override
  void image(void collector, int imageNumber) {
    throw UnimplementedError("@@ TODO");
  }
}

class _PruningVisitor extends _CompactVisitor<PruningBoundary> {
  final PruningBoundary _boundary;
  final _groupStack = List<_PruningEntry>.empty(growable: true);
  final _PruningBuilder builder;
  ScalableImageCompact? _si;
  CompactChildData? _lastPathData;

  _PruningVisitor(ScalableImageCompact si, Rect viewport, double tolerance)
      : _boundary = PruningBoundary(viewport.deflate(tolerance)),
        builder = _PruningBuilder(
            si.bigFloats,
            ByteSink(),
            (si.bigFloats) ? Float64Sink() : Float32Sink(),
            (si.bigFloats) ? Float64Sink() : Float32Sink(),
            viewport,
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
    if (path.prunedBy(boundary, const {}) != null) {
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
    if (cp.prunedBy(boundary, const {}) != null) {
      if (_groupStack.isNotEmpty) {
        _groupStack.last.generateGroupIfNeeded();
      }
      builder.clipPath(null, _lastPathData!);
    }
    _lastPathData = null;
    return boundary;
  }

  @override
  PruningBoundary images(PruningBoundary collector, List<SIImageData> im) {
    throw UnimplementedError("@@ TODO");
  }

  @override
  PruningBoundary image(PruningBoundary collector, int imageNumber) {
    // TODO: implement image
    throw UnimplementedError("@@ TODO");
  }
}

class _PruningBuilder extends _SICompactBuilder<CompactChildData>
    with _SICompactPathBuilder {
  @override
  void get initial => null;

  _PruningBuilder(bool bigFloats, ByteSink childrenSink, FloatSink args,
      FloatSink transforms, Rect viewport, {required bool warn})
      : super(
            bigFloats,
            childrenSink,
            DataOutputSink(childrenSink, Endian.little),
            args,
            transforms,
            viewport,
            warn: warn);
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
  PruningBoundary? images(PruningBoundary? collector, List<SIImageData> im) {
    throw UnimplementedError("@@ TODO");
  }

  @override
  PruningBoundary? image(PruningBoundary? collector, int imageNumber) {
    throw UnimplementedError("@@ TODO");
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

class SIDagBuilderFromCompact extends SIGenericDagBuilder<CompactChildData>
    with _SICompactPathBuilder {
  SIDagBuilderFromCompact(Rect? viewport,
      {required bool warn, Color? currentColor})
      : super(viewport, warn, currentColor);
}

abstract class _SICompactBuilder<PathDataT extends Object>
    extends SIGenericCompactBuilder<PathDataT> {
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
        children: childrenSink.toList(),
        args: args.toList(),
        transforms: transforms.toList(),
        viewport: viewport);
  }
}

class SICompactBuilder extends _SICompactBuilder<String>
    with SIStringPathMaker {
  SICompactBuilder._p(bool bigFloats, ByteSink childrenSink, FloatSink args,
      FloatSink transforms, {required bool warn, Color? currentColor})
      : super(bigFloats, childrenSink,
            DataOutputSink(childrenSink, Endian.little), args, transforms, null,
            warn: warn, currentColor: currentColor);

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
}
