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
/// Memory-efficient version of ScalableImage, at the expense of rendering
/// time.  This representation rendered about 3x slower in some informal
/// tests, but occupies perhaps an order of magnitude less memory.
///
library jovial_svg.compact;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:jovial_misc/io_utils.dart';
import 'affine.dart';
import 'dag.dart';
import 'common.dart';
import 'common_noui.dart';
import 'compact_noui.dart';
import 'exported.dart';
import 'path_noui.dart';
import 'path.dart';

///
/// A Scalable Image that's represented by a compact packed binary format
/// that is interpreted when rendering.
///
@immutable
class ScalableImageCompact extends ScalableImageBase
    with ScalableImageCompactGeneric<Color, BlendMode, SIImage> {
  final int fileVersion;
  @override
  final bool bigFloats;
  @override
  final int numPaths;
  @override
  final int numPaints;
  @override
  final List<String> strings;
  @override
  final List<List<double>> floatLists;
  @override
  final Uint8List children;
  @override
  final List<double> args; // Float32List or Float64List
  @override
  final List<double> transforms; // Float32List or Float64List

  ScalableImageCompact._p(
      {required this.fileVersion,
      required this.bigFloats,
      required double? width,
      required double? height,
      required Color? tintColor,
      required BlendMode tintMode,
      required Color? currentColor,
      required this.numPaths,
      required this.numPaints,
      required List<SIImage> images,
      required this.strings,
      required this.floatLists,
      required this.children,
      required this.args,
      required this.transforms,
      required Rect? viewport})
      : super(
            width, height, tintColor, tintMode, viewport, images, currentColor);

  @override
  ScalableImageCompact withNewViewport(Rect viewport,
      {bool prune = false, double pruningTolerance = 0}) {
    if (prune) {
      final v = _PruningVisitor(this, viewport, pruningTolerance);
      accept(v);
      return v.si;
    } else {
      return ScalableImageCompact._p(
          fileVersion: fileVersion,
          bigFloats: bigFloats,
          width: width,
          height: height,
          tintColor: tintColor,
          tintMode: tintMode,
          currentColor: currentColor,
          numPaths: numPaths,
          numPaints: numPaints,
          strings: strings,
          floatLists: floatLists,
          images: images,
          children: children,
          args: args,
          transforms: transforms,
          viewport: viewport);
    }
  }

  @override
  ScalableImage modifyCurrentColor(Color newCurrentColor) {
    return ScalableImageCompact._p(
        fileVersion: fileVersion,
        bigFloats: bigFloats,
        width: width,
        height: height,
        tintColor: tintColor,
        tintMode: tintMode,
        currentColor: newCurrentColor,
        numPaths: numPaths,
        numPaints: numPaints,
        strings: strings,
        floatLists: floatLists,
        images: images,
        children: children,
        args: args,
        transforms: transforms,
        viewport: viewport);
  }

  @override
  ScalableImage modifyTint(
      {required BlendMode newTintMode, required Color? newTintColor}) {
    return ScalableImageCompact._p(
        fileVersion: fileVersion,
        bigFloats: bigFloats,
        width: width,
        height: height,
        tintColor: newTintColor,
        tintMode: newTintMode,
        currentColor: currentColor,
        numPaths: numPaths,
        numPaints: numPaints,
        strings: strings,
        floatLists: floatLists,
        images: images,
        children: children,
        args: args,
        transforms: transforms,
        viewport: viewport);
  }

  @override
  void paintChildren(Canvas c, Color currentColor) {
    final v = _PaintingVisitor(c, RenderContext.root(this, currentColor));
    final CompactTraverser<void, SIImage> t = makeTraverser<void>(v);
    v.traverser = t;
    t.traverse(v.initial);
  }

  @override
  PruningBoundary? getBoundary() => accept(_BoundaryVisitor(this));

  R accept<R>(SIVisitor<CompactChildData, SIImage, R> visitor) =>
      makeTraverser(visitor).traverse(visitor.initial);

  CompactTraverser<R, SIImage> makeTraverser<R>(
          SIVisitor<CompactChildData, SIImage, R> visitor) =>
      CompactTraverser<R, SIImage>(
          fileVersion: fileVersion,
          bigFloats: bigFloats,
          strings: strings,
          floatLists: floatLists,
          images: images,
          visiteeChildren: children,
          visiteeArgs: args,
          visiteeTransforms: transforms,
          visiteeNumPaths: numPaths,
          visiteeNumPaints: numPaints,
          visitor: visitor);

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
  int colorValue(Color tintColor) => tintColor.value;

  static ScalableImageCompact fromByteData(ByteData data,
          {Color? currentColor}) =>
      fromBytes(
          Uint8List.view(data.buffer, data.offsetInBytes, data.lengthInBytes),
          currentColor: currentColor);

  static ScalableImageCompact fromBytes(Uint8List data, {Color? currentColor}) {
    final dis = ByteBufferDataInputStream(data, Endian.big);
    final magic = dis.readUnsignedInt();
    if (magic != ScalableImageCompactGeneric.magicNumber) {
      throw ParseError('Bad magic number:  0x${magic.toRadixString(16)}');
    }
    dis.readByte();
    final version = dis.readUnsignedShort();
    if (version < 1 ||
        version > ScalableImageCompactGeneric.fileVersionNumber) {
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
    final strings = List<String>.generate(
        _readSmallishInt(dis),
        (_) => (const Utf8Decoder(allowMalformed: true))
            .convert(dis.readBytesImmutable(_readSmallishInt(dis))),
        growable: false);
    final floatLists = List<List<double>>.generate(_readSmallishInt(dis),
        (_) => _floatList(dis, bigFloats, _readSmallishInt(dis), Endian.big),
        growable: false);
    final images = List<SIImageData>.generate(_readSmallishInt(dis), (_) {
      final x = _readFloat(dis, bigFloats, true)!;
      final y = _readFloat(dis, bigFloats, true)!;
      final w = _readFloat(dis, bigFloats, true)!;
      final h = _readFloat(dis, bigFloats, true)!;
      final encoded = dis.readBytes(_readSmallishInt(dis));
      return SIImageData(x: x, y: y, width: w, height: h, encoded: encoded);
    }, growable: false);
    final children = dis.remainingCopy();
    return ScalableImageCompact._p(
        fileVersion: version,
        bigFloats: bigFloats,
        width: width,
        height: height,
        tintColor: tintColor == null ? null : Color(tintColor),
        tintMode: SITintMode.values[tintMode].asBlendMode,
        currentColor: currentColor,
        numPaths: numPaths,
        numPaints: numPaints,
        strings: strings,
        floatLists: floatLists,
        images: List<SIImage>.generate(images.length, (i) => SIImage(images[i]),
            growable: false),
        children: children,
        args: args,
        transforms: transforms,
        viewport: null);
  }

  @override
  SIImageData getImageData(SIImage image) => image.data;

  static bool _flag(int byte, int bitNumber) => (byte & (1 << bitNumber)) != 0;

  static List<double> _floatList(
      ByteBufferDataInputStream dis, bool bigFloats, int length,
      [Endian endian = Endian.little]) {
    if (bigFloats) {
      Uint8List bytes = dis.readBytes(length * 8);
      ByteData bd = bytes.buffer.asByteData(bytes.offsetInBytes, length * 8);
      final r = Float64List(length);
      for (int i = 0; i < length; i++) {
        r[i] = bd.getFloat64(8 * i, endian);
      }
      return r;
    } else {
      Uint8List bytes = dis.readBytes(length * 4);
      ByteData bd = bytes.buffer.asByteData(bytes.offsetInBytes, length * 4);
      final r = Float32List(length);
      for (int i = 0; i < length; i++) {
        r[i] = bd.getFloat32(4 * i, endian);
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

  static int _readSmallishInt(ByteBufferDataInputStream str) =>
      ScalableImageCompactGeneric.readSmallishInt(str);

  @override
  Uint8List toSIBytes() {
    final sink = ByteSink();
    final os = DataOutputSink(sink, Endian.big);
    writeToFile(os);
    os.close();
    sink.close();
    // DataOutputSink closes sink(), but Google's analyzer misses that.
    // Calling close multiple times like this is documented as being
    // harmless.
    return sink.toList();
  }

  @override
  String debugSizeMessage() {
    return '${toSIBytes().length} bytes';
  }
}

///
/// Helper for visitors of compact scalable images.  This class adds
/// the creation of renderable SI objects.
///
abstract class _CompactVisitor<R>
    implements SIVisitor<CompactChildData, SIImage, R> {
  late final List<String> _strings;
  late final List<List<double>> _floatLists;
  late final List<SIImage> _images;
  RenderContext _context;
  RenderContext get context => _context;

  _CompactVisitor(this._context);

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
  R legacyText(R collector, int xIndex, int yIndex, int textIndex,
      SITextAttributes ta, int? fontFamilyIndex, SIPaint p) {
    return siText(
        collector,
        SIText.legacy(_strings[textIndex], _floatLists[xIndex],
            _floatLists[yIndex], ta, p),
        xIndex,
        yIndex);
  }

  R siText(R collector, SIText text, int xIndex, int yIndex);

  void pushContext(RenderContext c) {
    assert(c.parent == _context);
    _context = c;
  }

  void popContext() {
    final c = _context.parent;
    if (c == null) {
      throw StateError('More pops than pushes');
    }
    _context = c;
  }

  @override
  void assertDone() {
    assert(_context.parent == null);
  }
}

class _PaintingVisitor extends _CompactVisitor<void>
    with SIGroupHelper, SIMaskedHelper {
  final Canvas canvas;
  List<_MaskStackEntry>? _maskStack;
  late final CompactTraverserBase<void, SIImage,
      SIVisitor<CompactChildData, SIImage, void>> traverser;

  _PaintingVisitor(this.canvas, RenderContext context) : super(context);

  @override
  void get initial {}

  @override
  void group(
      void collector, Affine? transform, int? groupAlpha, SIBlendMode blend) {
    startPaintGroup(canvas, transform, groupAlpha, blend.asBlendMode);
    pushContext(RenderContext(context, transform: transform));
  }

  @override
  void endGroup(void collector) {
    endPaintGroup(canvas);
    popContext();
  }

  @override
  void siPath(void collector, SIPath path) => path.paint(canvas, context);

  @override
  void siClipPath(void collector, SIClipPath path) =>
      path.paint(canvas, context);

  @override
  void image(void collector, int imageIndex) =>
      _images[imageIndex].paint(canvas, context);

  @override
  void siText(void collector, SIText text, int xIndex, int yIndex) =>
      text.paint(canvas, context);

  @override
  void masked(void collector, RectT? maskBounds, bool usesLuma) {
    Rect? r = convertRectTtoRect(maskBounds);
    final s = (_maskStack ??= List.empty(growable: true));
    final LumaTraverser? lumaTraverser;
    if (usesLuma) {
      LumaTraverser? parentT;
      for (int i = s.length - 1; parentT == null && i >= 0; i--) {
        if (s[i].lumaTraverser?.active == true) {
          parentT = s[i].lumaTraverser;
        }
      }
      lumaTraverser = LumaTraverser(parentT ?? traverser, this);
    } else {
      lumaTraverser = null;
    }
    s.add(_MaskStackEntry(r, lumaTraverser));
    startMask(canvas, r);
  }

  @override
  void maskedChild(void collector) {
    final mse = _maskStack!.last;
    final lt = mse.lumaTraverser;
    if (lt != null) {
      startLumaMask(canvas, mse.bounds);
      assert(() {
        LumaTraverser? parentT;
        final s = _maskStack!;
        for (int i = s.length - 1; parentT == null && i >= 0; i--) {
          if (s[i].lumaTraverser?.active == true) {
            parentT = s[i].lumaTraverser;
          }
        }
        lt.assertEndPosition = (parentT ?? traverser).currentPosition;
        return true;
      }());
      lt.traverseLuma();
      finishLumaMask(canvas);
    }
    _maskStack!.length--;
    startChild(canvas, mse.bounds);
  }

  @override
  void endMasked(void collector) {
    finishMasked(canvas);
  }

  @override
  PruningBoundary? getBoundary() => null;
  // We don't know our boundary (unlike the DAG implementation), so
  // we're a little less efficient.
}

class _MaskStackEntry {
  final Rect? bounds;
  final LumaTraverser? lumaTraverser;

  _MaskStackEntry(this.bounds, this.lumaTraverser);
}

///
/// For masked, we sometimes need to traverse the mask twice, once for
/// alpha and once for luma.  This clone traverser lets us do that.
///
class LumaTraverser
    extends CompactTraverserBase<void, SIImage, _PaintingVisitor> {
  final int _startGroupDepth;
  bool active = false;
  int assertEndPosition = -1;

  LumaTraverser(
      CompactTraverserBase<void, SIImage,
              SIVisitor<CompactChildData, SIImage, void>>
          parent,
      _PaintingVisitor visitor)
      : _startGroupDepth = parent.groupDepth,
        super.clone(parent, visitor);

  void traverseLuma() {
    active = true;
    traverseGroup(null);
    active = false;
  }

  @override
  void maskedChild(void collector) {
    if (groupDepth == _startGroupDepth) {
      assert(assertEndPosition == currentPosition,
          '$assertEndPosition != $currentPosition');
      endTraversalEarly();
      return collector;
    } else {
      return super.maskedChild(collector);
    }
  }
}

class _PruningVisitor extends _CompactVisitor<PruningBoundary> {
  final PruningBoundary _boundary;
  final _parentStack = List<_PruningEntry>.empty(growable: true);
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
            warn: false),
        super(RenderContext.root(si, Colors.black)) {
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
  PruningBoundary group(PruningBoundary boundary, Affine? transform,
      int? groupAlpha, SIBlendMode blend) {
    final parent = _parentStack.isEmpty ? null : _parentStack.last;
    _parentStack.add(_GroupPruningEntry(
        boundary, parent, this, transform, groupAlpha, blend));
    pushContext(RenderContext(context, transform: transform));
    return context.transformBoundaryFromParent(boundary);
  }

  @override
  PruningBoundary endGroup(PruningBoundary boundary) {
    final us = _parentStack.last as _GroupPruningEntry;
    _parentStack.length = _parentStack.length - 1;
    us.endGroupIfNeeded();
    popContext();
    return us.boundary;
  }

  @override
  PruningBoundary masked(
      PruningBoundary boundary, RectT? maskBounds, bool usesLuma) {
    final parent = _parentStack.isEmpty ? null : _parentStack.last;
    _parentStack
        .add(_MaskedPruningEntry(boundary, parent, this, maskBounds, usesLuma));
    pushContext(RenderContext(context));
    return context.transformBoundaryFromParent(boundary);
  }

  @override
  PruningBoundary maskedChild(PruningBoundary boundary) {
    // We've traversed the mask, and now we're starting to traverse
    // the child.
    final us = _parentStack.last as _MaskedPruningEntry;
    us.setMaskDone();

    assert(boundary.getBounds() ==
        context.transformBoundaryFromParent(us.boundary).getBounds());
    return boundary;
  }

  @override
  PruningBoundary endMasked(PruningBoundary collector) {
    final us = _parentStack.last as _MaskedPruningEntry;
    _parentStack.length = _parentStack.length - 1;
    us.endMaskedIfNeeded();
    popContext();
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
      if (_parentStack.isNotEmpty) {
        _parentStack.last.generateParentIfNeeded();
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
      if (_parentStack.isNotEmpty) {
        _parentStack.last.generateParentIfNeeded();
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
      if (_parentStack.isNotEmpty) {
        _parentStack.last.generateParentIfNeeded();
      }
      int i = _theCanon.getIndex(_theCanon.images, image)!;
      builder.image(null, i);
    }
    return boundary;
  }

  @override
  PruningBoundary siText(
      PruningBoundary boundary, SIText text, int xIndex, int yIndex) {
    throw "@@ TODO";
    /*
    if (text.prunedBy({}, {}, boundary) != null) {
      if (_parentStack.isNotEmpty) {
        _parentStack.last.generateParentIfNeeded();
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

     */
    return boundary;
  }
}

class _PruningBuilder extends SIGenericCompactBuilder<CompactChildData, SIImage>
    with _SICompactPathBuilder {
  final Rect viewport;
  final Color? currentColor;

  @override
  void get initial {}

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
        fileVersion: ScalableImageCompactGeneric.fileVersionNumber,
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

abstract class _PruningEntry {
  final _PruningEntry? parent;
  bool generated = false;

  _PruningEntry(this.parent);

  void generateParentIfNeeded() {
    if (generated) {
      return;
    }
    parent?.generateParentIfNeeded();
    generateParent();
    generated = true;
  }

  @protected
  void generateParent();
}

class _GroupPruningEntry extends _PruningEntry {
  final PruningBoundary boundary;
  final _PruningVisitor visitor;
  final Affine? transform;
  final int? groupAlpha;
  final SIBlendMode blendMode;

  _GroupPruningEntry(this.boundary, _PruningEntry? parent, this.visitor,
      this.transform, this.groupAlpha, this.blendMode)
      : super(parent);

  @override
  void generateParent() {
    visitor.builder.group(null, transform, groupAlpha, blendMode);
  }

  void endGroupIfNeeded() {
    if (generated) {
      visitor.builder.endGroup(null);
    }
  }
}

class _MaskedPruningEntry extends _PruningEntry {
  final PruningBoundary boundary;
  final _PruningVisitor visitor;
  final RectT? maskBounds;
  final bool usesLuma;

  bool _maskDone = false;
  bool childGenerated = false;

  _MaskedPruningEntry(this.boundary, _PruningEntry? parent, this.visitor,
      this.maskBounds, this.usesLuma)
      : super(parent);

  bool get maskDone => _maskDone;
  void setMaskDone() {
    if (!_maskDone) {
      _maskDone = true;
      if (generated) {
        visitor.builder.maskedChild(null);
      }
    }
  }

  @override
  void generateParentIfNeeded() {
    if (maskDone) {
      childGenerated = true;
    }
    super.generateParentIfNeeded();
  }

  @override
  void generateParent() {
    visitor.builder.masked(null, maskBounds, usesLuma);
    if (maskDone) {
      // Rare, but perhaps possible:  The mask got entirely pruned away, but the
      // child didn't, so we make an empty group for the mask.
      visitor.builder.group(null, null, null, SIBlendMode.normal);
      visitor.builder.endGroup(null);
      visitor.builder.maskedChild(null);
    }
  }

  void endMaskedIfNeeded() {
    if (!generated) {
      return;
    }
    assert(maskDone);
    if (!childGenerated) {
      // Rare, but perhaps possible:  The child got entirely pruned away, but
      // the mask didn't, so we make an empty group for the child.
      visitor.builder.group(null, null, null, SIBlendMode.normal);
      visitor.builder.endGroup(null);
    }
    visitor.builder.endMasked(null);
  }
}

class _BoundaryVisitor extends _CompactVisitor<PruningBoundary?> {
  PruningBoundary? boundary;

  final _boundaryStack = List<PruningBoundary?>.empty(growable: true);

  _BoundaryVisitor(ScalableImageCompact si)
      : super(RenderContext.root(si, Colors.black));

  @override
  PruningBoundary? get initial => null;

  @override
  PruningBoundary? group(PruningBoundary? start, Affine? transform,
      int? groupAlpha, SIBlendMode blend) {
    pushContext(RenderContext(context, transform: transform));
    _boundaryStack.add(start);
    return null;
  }

  @override
  PruningBoundary? endGroup(PruningBoundary? children) {
    PruningBoundary? us = _boundaryStack.last;
    _boundaryStack.length = _boundaryStack.length - 1;
    RenderContext ctx = context;
    popContext();
    return combine(us, ctx.transformBoundaryFromChildren(children));
  }

  @override
  PruningBoundary? masked(
      PruningBoundary? start, RectT? maskBoundary, bool usesLuma) {
    pushContext(RenderContext(context));
    _boundaryStack.add(start);
    return null;
  }

  @override
  PruningBoundary? maskedChild(PruningBoundary? mask) {
    _boundaryStack.add(context.transformBoundaryFromChildren(mask));
    return null;
  }

  @override
  PruningBoundary? endMasked(PruningBoundary? child) {
    RenderContext ctx = context;
    popContext();
    child = ctx.transformBoundaryFromChildren(child);
    PruningBoundary? mask = _boundaryStack.last;
    _boundaryStack.length--;
    PruningBoundary? us = _boundaryStack.last;
    _boundaryStack.length = _boundaryStack.length - 1;

    if (mask == null || child == null) {
      return us;
    }

    final mbb = mask.getBounds();
    final cbb = child.getBounds();
    final PruningBoundary other;
    // Intersecting the two is hard, but conservatively returning
    // the one with less area is a reasonable heuristic.
    if (mbb.height * mbb.width > cbb.height * cbb.width) {
      other = child;
    } else {
      other = mask;
    }
    return combine(us, other);
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

mixin _SICompactPathBuilder {
  void makePath(CompactChildData pathData, PathBuilder pb, {bool warn = true}) {
    try {
      CompactPathParser(pathData, pb).parse();
    } catch (e) {
      if (warn) {
        print(e);
        // As per the SVG spec, paths shall be parsed up to the first error,
        // and it is recommended that errors be reported to the user if
        // possible.
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

class SICompactBuilder extends SIGenericCompactBuilder<String, SIImageData>
    with SIStringPathMaker {
  final Color? currentColor;

  SICompactBuilder._p(bool bigFloats, ByteSink childrenSink, FloatSink args,
      FloatSink transforms, {required bool warn, this.currentColor})
      : super(bigFloats, childrenSink,
            DataOutputSink(childrenSink, Endian.little), args, transforms,
            warn: warn);

  @override
  void get initial {}

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
        fileVersion: ScalableImageCompactGeneric.fileVersionNumber,
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
        images: List<SIImage>.generate(images.length, (i) => SIImage(images[i]),
            growable: false),
        children: childrenSink.toList(),
        args: args.toList(),
        transforms: transforms.toList(),
        viewport: null);
  }
}
