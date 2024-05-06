/*
Copyright (c) 2021-2024, William Foote

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
  @override
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
  final List<List<String>> stringLists;
  @override
  final List<double> floatValues;
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
      required this.stringLists,
      required this.floatValues,
      required this.children,
      required this.args,
      required this.transforms,
      required Rect? givenViewport})
      : super(width, height, tintColor, tintMode, givenViewport, images,
            currentColor);

  @override
  ScalableImageCompact withNewViewport(Rect viewport,
      {bool prune = false, double pruningTolerance = 0}) {
    if (prune) {
      final boundary = PruningBoundary(viewport.deflate(pruningTolerance));
      final v = _PruningVisitor(
          this, viewport.width, viewport.height, viewport, boundary);
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
          stringLists: stringLists,
          floatValues: floatValues,
          images: images,
          children: children,
          args: args,
          transforms: transforms,
          givenViewport: viewport);
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
        stringLists: stringLists,
        floatValues: floatValues,
        images: images,
        children: children,
        args: args,
        transforms: transforms,
        givenViewport: viewport);
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
        stringLists: stringLists,
        floatValues: floatValues,
        images: images,
        children: children,
        args: args,
        transforms: transforms,
        givenViewport: viewport);
  }

  @override
  void paintChildren(Canvas c, Color currentColor) {
    final v = _PaintingVisitor(c, _RenderContext.root(currentColor));
    final CompactTraverser<void, SIImage> t = makeTraverser<void>(v);
    v.traverser = t;
    t.traverse(v.initial);
  }

  @override
  int? get currentColorARGB =>
      currentColor == ScalableImageBase.defaultCurrentColor
          ? null
          : currentColor.value;

  @override
  RectT? get givenViewportNoUI => convertRectToRectT(givenViewport);

  @override
  PruningBoundary? getBoundary(
      List<ExportedIDBoundary>? exportedIDs, Affine? exportedIDXform) {
    if (exportedIDs == null) {
      return accept(_BoundaryVisitor());
    } else {
      return accept(_ExportedIDVisitor(exportedIDs, exportedIDXform!));
    }
  }

  R accept<R>(SIVisitor<CompactChildData, SIImage, R> visitor) =>
      makeTraverser(visitor).traverse(visitor.initial);

  CompactTraverser<R, SIImage> makeTraverser<R>(
          SIVisitor<CompactChildData, SIImage, R> visitor) =>
      CompactTraverser<R, SIImage>(
          fileVersion: fileVersion,
          bigFloats: bigFloats,
          strings: strings,
          floatLists: floatLists,
          stringLists:
              (fileVersion <= 9) ? LegacyStringLists(strings) : stringLists,
          floatValues: floatValues,
          images: images,
          visiteeChildren: children,
          visiteeArgs: args,
          visiteeTransforms: transforms,
          visiteeNumPaths: numPaths,
          visiteeNumPaints: numPaints,
          visitor: visitor);

  @override
  ScalableImageDag toDag() {
    final b = SIDagBuilderFromCompact(givenViewport,
        warn: _noWarn, currentColor: currentColor);
    b.vector(
        width: width,
        height: height,
        tintColor: tintColor?.value,
        tintMode: SITintModeMapping.fromBlendMode(tintMode));
    accept(b);
    b.endVector();
    b.traversalDone();
    return b.si;
  }

  @override
  int writeToFile(DataOutputSink out) {
    if (fileVersion == ScalableImageCompactGeneric.latestFileVersion) {
      return super.writeToFile(out);
    } else {
      final v = _PruningVisitor(this, width, height, givenViewport, null);
      accept(v);
      return v.si.writeToFile(out);
    }
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
        version > ScalableImageCompactGeneric.latestFileVersion) {
      throw ParseError('Unsupported version $version');
    }
    final int flags = dis.readUnsignedByte();
    final hasWidth = _flag(flags, 0);
    final hasHeight = _flag(flags, 1);
    final bigFloats = _flag(flags, 2);
    final hasTintColor = _flag(flags, 3);
    final hasCurrentColor = version > 8 && _flag(flags, 4);
    final hasGivenViewport = version > 8 && _flag(flags, 5);
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
    Rect? givenViewport;
    if (hasCurrentColor) {
      final fromBytes = dis.readUnsignedInt();
      currentColor ??= Color(fromBytes);
    }
    if (hasGivenViewport) {
      givenViewport = Rect.fromLTWH(
          _readFloat(dis, bigFloats, true)!,
          _readFloat(dis, bigFloats, true)!,
          _readFloat(dis, bigFloats, true)!,
          _readFloat(dis, bigFloats, true)!);
    }
    final strings = List<String>.generate(
        _readSmallishInt(dis),
        (_) => (const Utf8Decoder(allowMalformed: true))
            .convert(dis.readBytesImmutable(_readSmallishInt(dis))),
        growable: false);
    final List<List<String>> stringLists;
    if (version <= 9) {
      stringLists = const [];
    } else {
      stringLists = List<List<String>>.generate(
          _readSmallishInt(dis),
          (_) => List<String>.generate(
              _readSmallishInt(dis), (_) => strings[_readSmallishInt(dis)],
              growable: false),
          growable: false);
    }
    final floatLists = List<List<double>>.generate(_readSmallishInt(dis),
        (_) => _floatList(dis, bigFloats, _readSmallishInt(dis), Endian.big),
        growable: false);
    final List<double> floatValues = version < 7
        ? const []
        : _floatList(dis, bigFloats, _readSmallishInt(dis), Endian.big);
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
        stringLists: stringLists,
        floatValues: floatValues,
        images: List<SIImage>.generate(images.length, (i) => SIImage(images[i]),
            growable: false),
        children: children,
        args: args,
        transforms: transforms,
        givenViewport: givenViewport);
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

class _RenderContext {
  final _RenderContext? parent;
  final Color currentColor;
  final Affine? transform;

  _RenderContext(_RenderContext this.parent,
      {Color? currentColor, this.transform})
      : currentColor = currentColor ?? parent.currentColor;

  _RenderContext.root(this.currentColor)
      : parent = null,
        transform = null;

  PruningBoundary? transformBoundaryFromChildren(PruningBoundary? b) =>
      Transformer.transformBoundaryFromChildren(transform, b);

  PruningBoundary? transformBoundaryFromParent(PruningBoundary? b) =>
      Transformer.transformBoundaryFromParent(transform, b);
}

///
/// Helper for visitors of compact scalable images.  This class adds
/// the creation of renderable SI objects.
///
abstract class _CompactVisitor<R>
    implements SIVisitor<CompactChildData, SIImage, R> {
  @protected
  late final List<String> strings;
  @protected
  late final List<List<double>> floatLists;
  @protected
  late final List<List<String>> stringLists;
  @protected
  late final List<double> floatValues;
  @protected
  late final List<SIImage> images;
  _RenderContext _context;
  _RenderContext get context => _context;

  _CompactVisitor(this._context);

  @override
  R init(
      R collector,
      List<SIImage> images,
      List<String> strings,
      List<List<double>> floatLists,
      List<List<String>> stringLists,
      List<double> floatValues,
      CMap<double>? floatValueMap) {
    this.images = images;
    this.strings = strings;
    this.floatLists = floatLists;
    this.stringLists = stringLists;
    this.floatValues = floatValues;
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
    return acceptText(
        collector,
        SIText.legacy(
            strings[textIndex], floatLists[xIndex], floatLists[yIndex], ta, p));
  }

  R acceptText(R collector, SIText text);

  void pushContext(_RenderContext c) {
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
  void traversalDone() {
    assert(_context.parent == null);
  }
}

class _PaintingVisitor extends _CompactVisitor<void>
    with SIGroupHelper, SIMaskedHelper, SITextHelper<void> {
  final Canvas canvas;
  List<_MaskStackEntry>? _maskStack;
  late final CompactTraverserBase<void, SIImage,
      SIVisitor<CompactChildData, SIImage, void>> traverser;

  _PaintingVisitor(this.canvas, _RenderContext context) : super(context);

  @override
  void get initial {}

  @override
  void group(
      void collector, Affine? transform, int? groupAlpha, SIBlendMode blend) {
    startPaintGroup(canvas, transform, groupAlpha, blend.asBlendMode);
    pushContext(_RenderContext(context, transform: transform));
  }

  @override
  void endGroup(void collector) {
    endPaintGroup(canvas);
    popContext();
  }

  @override
  void siPath(void collector, SIPath path) =>
      path.paint(canvas, context.currentColor);

  @override
  void siClipPath(void collector, SIClipPath path) =>
      path.paint(canvas, context.currentColor);

  @override
  void image(void collector, int imageIndex) =>
      images[imageIndex].paint(canvas, context.currentColor);

  @override
  void acceptText(void collector, SIText text) =>
      text.paint(canvas, context.currentColor);

  @override
  void masked(void collector, RectT? maskBounds, bool usesLuma) {
    Rect? r = convertRectTtoRect(maskBounds);
    final s = (_maskStack ??= List.empty(growable: true));
    final _LumaTraverser? lumaTraverser;
    if (usesLuma) {
      _LumaTraverser? parentT;
      for (int i = s.length - 1; parentT == null && i >= 0; i--) {
        if (s[i].lumaTraverser?.active == true) {
          parentT = s[i].lumaTraverser;
        }
      }
      lumaTraverser = _LumaTraverser(parentT ?? traverser, this);
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
        _LumaTraverser? parentT;
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
  void endExportedID(void collector) {}

  @override
  void exportedID(void collector, int idIndex) {}
}

class _MaskStackEntry {
  final Rect? bounds;
  final _LumaTraverser? lumaTraverser;

  _MaskStackEntry(this.bounds, this.lumaTraverser);
}

///
/// For masked, we sometimes need to traverse the mask twice, once for
/// alpha and once for luma.  This clone traverser lets us do that.
///
class _LumaTraverser
    extends CompactTraverserBase<void, SIImage, _PaintingVisitor> {
  final int _startGroupDepth;
  bool active = false;
  int assertEndPosition = -1;

  _LumaTraverser(super.parent, super.visitor)
      : _startGroupDepth = parent.groupDepth,
        super.clone();

  void traverseLuma() {
    active = true;
    traverseGroup(null);
    active = false;
  }

  @override
  void maskedChild(void collector) {
    if (groupDepth == _startGroupDepth) {
      assert(assertEndPosition == currentPosition);
      endTraversalEarly();
      return collector;
    } else {
      return super.maskedChild(collector);
    }
  }
}

class _PruningVisitor extends _CompactVisitor<PruningBoundary?>
    with SITextHelper<PruningBoundary?> {
  final PruningBoundary? _boundary;
  final _parentStack = List<_PruningEntry>.empty(growable: true);
  final _PruningBuilder builder;
  ScalableImageCompact? _si;
  CompactChildData? _lastPathData;
  final _theCanon = CanonicalizedData<SIImage>();

  _PruningVisitor(ScalableImageCompact si, double? width, double? height,
      Rect? givenViewport, this._boundary)
      : builder = _PruningBuilder(
            si.bigFloats,
            ByteSink(),
            (si.bigFloats) ? Float64Sink() : Float32Sink(),
            (si.bigFloats) ? Float64Sink() : Float32Sink(),
            givenViewport,
            currentColor: si.currentColor,
            warn: _noWarn),
        super(_RenderContext.root(Colors.black)) {
    builder.initFloatValueMap(_theCanon.floatValues);
    builder.vector(
        width: width,
        height: height,
        tintColor: si.tintColor?.value,
        tintMode: SITintModeMapping.fromBlendMode(si.tintMode));
  }

  @override
  PruningBoundary? get initial => _boundary;

  ScalableImageCompact get si {
    final r = _si;
    if (r != null) {
      return r;
    } else {
      builder.endVector();
      builder.traversalDone();
      builder.setCanon(_theCanon);
      return _si = builder.si;
    }
  }

  @override
  PruningBoundary? group(PruningBoundary? boundary, Affine? transform,
      int? groupAlpha, SIBlendMode blend) {
    final parent = _parentStack.isEmpty ? null : _parentStack.last;
    _parentStack.add(_GroupPruningEntry(
        boundary, parent, this, transform, groupAlpha, blend));
    pushContext(_RenderContext(context, transform: transform));
    return context.transformBoundaryFromParent(boundary);
  }

  @override
  PruningBoundary? endGroup(PruningBoundary? boundary) {
    final us = _parentStack.last as _GroupPruningEntry;
    _parentStack.length--;
    us.endGroupIfNeeded();
    popContext();
    return us.boundary;
  }

  @override
  PruningBoundary? exportedID(PruningBoundary? boundary, int idIndex) {
    final parent = _parentStack.isEmpty ? null : _parentStack.last;
    _parentStack
        .add(_ExportedIdPruningEntry(boundary, parent, this, strings[idIndex]));
    return boundary;
  }

  @override
  PruningBoundary? endExportedID(PruningBoundary? boundary) {
    final us = _parentStack.last as _ExportedIdPruningEntry;
    _parentStack.length--;
    us.endExportedIdIfNeeded();
    return us.boundary;
  }

  @override
  PruningBoundary? masked(
      PruningBoundary? boundary, RectT? maskBounds, bool usesLuma) {
    final parent = _parentStack.isEmpty ? null : _parentStack.last;
    _parentStack
        .add(_MaskedPruningEntry(boundary, parent, this, maskBounds, usesLuma));
    pushContext(_RenderContext(context));
    return context.transformBoundaryFromParent(boundary);
  }

  @override
  PruningBoundary? maskedChild(PruningBoundary? boundary) {
    // We've traversed the mask, and now we're starting to traverse
    // the child.
    final us = _parentStack.last as _MaskedPruningEntry;
    us.setMaskDone();

    assert(boundary?.getBounds() ==
        context.transformBoundaryFromParent(us.boundary)?.getBounds());
    return boundary;
  }

  @override
  PruningBoundary? endMasked(PruningBoundary? collector) {
    final us = _parentStack.last as _MaskedPruningEntry;
    _parentStack.length--;
    us.endMaskedIfNeeded();
    popContext();
    return us.boundary;
  }

  @override
  PruningBoundary? path(
      PruningBoundary? boundary, CompactChildData pathData, SIPaint siPaint) {
    assert(_lastPathData == null);
    _lastPathData = CompactChildData.copy(pathData);
    return super.path(boundary, pathData, siPaint);
  }

  @override
  PruningBoundary? siPath(PruningBoundary? boundary, SIPath path) {
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
  PruningBoundary? clipPath(
      PruningBoundary? boundary, CompactChildData pathData) {
    assert(_lastPathData == null);
    _lastPathData = CompactChildData.copy(pathData);
    return super.clipPath(boundary, pathData);
  }

  @override
  PruningBoundary? siClipPath(PruningBoundary? boundary, SIClipPath cp) {
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
  PruningBoundary? image(PruningBoundary? boundary, int imageIndex) {
    final SIImage image = images[imageIndex];
    if (image.prunedBy({}, {}, boundary) != null) {
      if (_parentStack.isNotEmpty) {
        _parentStack.last.generateParentIfNeeded();
      }
      int i = _theCanon.images[image];
      builder.image(null, i);
    }
    return boundary;
  }

  @override
  PruningBoundary? acceptText(PruningBoundary? boundary, SIText text) {
    if (text.prunedBy({}, {}, boundary) != null) {
      if (_parentStack.isNotEmpty) {
        _parentStack.last.generateParentIfNeeded();
      }
      builder.text(null);
      for (final chunk in text.chunks) {
        chunk.build(_theCanon, builder);
      }
      builder.textEnd(null);
    }
    return boundary;
  }
}

class _PruningBuilder extends SIGenericCompactBuilder<CompactChildData, SIImage>
    with _SICompactPathBuilder {
  final Rect? givenViewport;
  final Color? currentColor;

  _PruningBuilder(bool bigFloats, ByteSink childrenSink, FloatSink args,
      FloatSink transforms, this.givenViewport,
      {required void Function(String) warn, required this.currentColor})
      : super(bigFloats, childrenSink,
            DataOutputSink(childrenSink, Endian.little), args, transforms,
            warn: warn);

  @override
  void init(
      void collector,
      List<SIImage> images,
      List<String> strings,
      List<List<double>> floatLists,
      List<List<String>> stringLists,
      List<double> floatValues,
      CMap<double>? floatValueMap) {
    // This is a little tricky.  When pruning, we collect the canonicalized
    // data on the fly, and only provide it to our supertype at the end,
    // right before building the SI.  For this reason, we need to discard
    // this data here.  It comes from the graph being pruned, not the one
    // being produced, so we don't care about it.
  }

  ///
  /// Set the canonicalized data.  This can be done right before
  /// calling `si`.  It's used for pruning.
  ///
  void setCanon(CanonicalizedData<SIImage> canon) {
    super.init(null, canon.images.toList(), canon.strings.toList(), const [],
        canon.getStringLists(), canon.floatValues.toList(), null);
    // Note that floatValueMap gets set before the traversal, by a call to
    // initFloatValueMap() in the _PruningVisitor constructor.
  }

  ScalableImageCompact get si {
    assert(done);
    return ScalableImageCompact._p(
        fileVersion: ScalableImageCompactGeneric.latestFileVersion,
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
        stringLists: stringLists,
        floatValues: floatValues,
        images: images,
        children: childrenSink.toList(),
        args: args.toList(),
        transforms: transforms.toList(),
        givenViewport: givenViewport);
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
  final PruningBoundary? boundary;
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

class _ExportedIdPruningEntry extends _PruningEntry {
  final PruningBoundary? boundary;
  final _PruningVisitor visitor;
  final String id;

  _ExportedIdPruningEntry(
      this.boundary, _PruningEntry? parent, this.visitor, this.id)
      : super(parent);

  @override
  void generateParent() {
    visitor.builder.exportedID(null, visitor._theCanon.strings[id]);
  }

  void endExportedIdIfNeeded() {
    if (generated) {
      visitor.builder.endExportedID(null);
    }
  }
}

class _MaskedPruningEntry extends _PruningEntry {
  final PruningBoundary? boundary;
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

class _BoundaryVisitor extends _CompactVisitor<PruningBoundary?>
    with SITextHelper<PruningBoundary?> {
  final _boundaryStack = List<PruningBoundary?>.empty(growable: true);

  _BoundaryVisitor() : super(_RenderContext.root(Colors.black));

  @override
  PruningBoundary? get initial => null;

  @override
  PruningBoundary? group(PruningBoundary? start, Affine? transform,
      int? groupAlpha, SIBlendMode blend) {
    pushContext(_RenderContext(context, transform: transform));
    _boundaryStack.add(start);
    return null;
  }

  @override
  PruningBoundary? endGroup(PruningBoundary? children) {
    PruningBoundary? us = _boundaryStack.last;
    _boundaryStack.length--;
    _RenderContext ctx = context;
    popContext();
    return combine(us, ctx.transformBoundaryFromChildren(children));
  }

  @override
  PruningBoundary? exportedID(PruningBoundary? start, int idIndex) {
    _boundaryStack.add(start);
    return null;
  }

  @override
  PruningBoundary? endExportedID(PruningBoundary? children) {
    PruningBoundary? us = _boundaryStack.last;
    _boundaryStack.length--;
    return combine(us, children);
  }

  @override
  PruningBoundary? masked(
      PruningBoundary? start, RectT? maskBoundary, bool usesLuma) {
    pushContext(_RenderContext(context));
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
    _RenderContext ctx = context;
    popContext();
    child = ctx.transformBoundaryFromChildren(child);
    PruningBoundary? mask = _boundaryStack.last;
    _boundaryStack.length--;
    PruningBoundary? us = _boundaryStack.last;
    _boundaryStack.length--;

    if (mask == null || child == null) {
      return us;
    }

    final mbb = mask.getBounds();
    final cbb = child.getBounds();
    final ibb = mbb.intersect(cbb);
    if (ibb.width < 0.0 || ibb.height <= 0.0) {
      return us;
    }
    final mbba = mbb.height * mbb.width;
    final cbba = cbb.height * cbb.width;
    final ibba = ibb.height * ibb.width;

    PruningBoundary? other;
    // Truly intersecting two boundaries is hard.  If the intersection's
    // bounding box is smaller than either of the two bounding boxes, we
    // go with that.  Otherwise, we go with the boundary that has the smaller
    // bounding box.
    if (mbba > cbba) {
      if (cbba <= ibba) {
        other = child;
      }
    } else {
      if (mbba <= ibba) {
        other = mask;
      }
    }
    other ??= PruningBoundary(ibb);
    return combine(us, other);
  }

  @override
  PruningBoundary? siPath(PruningBoundary? initial, SIPath path) {
    return combine(initial, path.getBoundary(null, null));
  }

  @override
  PruningBoundary? siClipPath(PruningBoundary? initial, SIClipPath cp) {
    return combine(initial, cp.getBoundary(null, null));
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
    return combine(collector, images[imageIndex].getBoundary(null, null));
  }

  @override
  PruningBoundary? acceptText(PruningBoundary? boundary, SIText text) =>
      combine(boundary, text.getBoundary(null, null));
}

class _ExportedIDVisitor extends _BoundaryVisitor {
  final List<ExportedIDBoundary> result;
  _ExportedIDContext eContext;

  _ExportedIDVisitor(this.result, Affine xform)
      : eContext = _ExportedIDContext(null, null, xform);

  @override
  PruningBoundary? exportedID(PruningBoundary? start, int idIndex) {
    eContext = _ExportedIDContext(eContext, strings[idIndex], eContext.xform);
    return super.exportedID(start, idIndex);
  }

  @override
  PruningBoundary? endExportedID(PruningBoundary? children) {
    final String id = eContext.id!;
    eContext = eContext.parent!;
    final b =
        Transformer.transformBoundaryFromChildren(eContext.xform, children);
    if (b != null) {
      result.add(ExportedIDBoundary(id, b));
    }
    return super.endExportedID(children);
  }

  @override
  PruningBoundary? group(PruningBoundary? start, Affine? transform,
      int? groupAlpha, SIBlendMode blend) {
    final Affine xform;
    if (transform == null) {
      xform = eContext.xform;
    } else {
      final nt = eContext.xform.mutableCopy();
      nt.multiplyBy(transform.toMutable);
      xform = nt;
    }
    eContext = _ExportedIDContext(eContext, null, xform);
    return super.group(start, transform, groupAlpha, blend);
  }

  @override
  PruningBoundary? endGroup(PruningBoundary? children) {
    eContext = eContext.parent!;
    return super.endGroup(children);
  }

  @override
  void traversalDone() {
    super.traversalDone();
    assert(eContext.parent == null);
  }
}

class _ExportedIDContext {
  final _ExportedIDContext? parent;
  final String? id;
  final Affine xform;

  _ExportedIDContext(this.parent, this.id, this.xform);
}

mixin _SICompactPathBuilder {
  void makePath(CompactChildData pathData, EnhancedPathBuilder pb,
      {required void Function(String) warn}) {
    CompactPathParser(pathData, pb).parse();
  }

  CompactChildData immutableKey(CompactChildData key) =>
      CompactChildData.copy(key);
}

class SIDagBuilderFromCompact
    extends SIGenericDagBuilder<CompactChildData, SIImage>
    with _SICompactPathBuilder {
  SIDagBuilderFromCompact(Rect? givenViewport,
      {required void Function(String) warn, Color? currentColor})
      : super(givenViewport, warn, currentColor);

  @override
  List<SIImage> convertImages(List<SIImage> images) => images;

  @override
  void addPath(Object path, SIPaint paint) => unreachable(null);
}

class SICompactBuilder extends SIGenericCompactBuilder<String, SIImageData>
    with SIStringPathMaker {
  final Color? currentColor;

  SICompactBuilder._p(bool bigFloats, ByteSink childrenSink, FloatSink args,
      FloatSink transforms,
      {required void Function(String) warn, this.currentColor})
      : super(bigFloats, childrenSink,
            DataOutputSink(childrenSink, Endian.little), args, transforms,
            warn: warn);

  factory SICompactBuilder(
      {required bool bigFloats,
      required void Function(String) warn,
      Color? currentColor}) {
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
        fileVersion: ScalableImageCompactGeneric.latestFileVersion,
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
        stringLists: stringLists,
        floatValues: floatValues,
        images: List<SIImage>.generate(images.length, (i) => SIImage(images[i]),
            growable: false),
        children: childrenSink.toList(),
        args: args.toList(),
        transforms: transforms.toList(),
        givenViewport: null);
  }
}

void _noWarn(String msg) {}
