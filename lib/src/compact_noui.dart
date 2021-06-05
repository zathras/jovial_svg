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


///
/// The generic portion of ScalableImageCompact.  This is separated out with
/// no dependencies on Flutter so that the non-flutter application
/// "dart run jovial_svg:avd_to_si" can work.
///
library jovial_svg.compact_noui;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:quiver/core.dart' as quiver;
import 'package:jovial_misc/io_utils.dart';
import 'affine.dart';
import 'common_noui.dart';
import 'path_noui.dart';

const _DEBUG_COMPACT = false;

class CompactTraverser<R> {
  final SIVisitor<CompactChildData, R> _visitor;
  final ByteBufferDataInputStream _children;
  final FloatBufferInputStream _args;
  final FloatBufferInputStream _transforms;
  final ByteBufferDataInputStream _rewindChildren;
  final FloatBufferInputStream _rewindArgs;
  // Position by path ID
  final Uint32List _pathChildrenSeek;
  final Uint32List _pathArgsSeek;
  int _currPathID = 0;
  final Uint32List _paintChildrenSeek;
  final Uint32List _paintArgsSeek;
  int _currPaintID = 0;
  int _groupDepth = 0;

  CompactTraverser(
      {required Uint8List visiteeChildren,
      required List<double> visiteeArgs,
      required List<double> visiteeTransforms,
      required int visiteeNumPaths,
      required int visiteeNumPaints,
      required SIVisitor<CompactChildData, R> visitor})
      : _visitor = visitor,
        _children = ByteBufferDataInputStream(visiteeChildren, Endian.little),
        _args = FloatBufferInputStream(visiteeArgs),
        _transforms = FloatBufferInputStream(visiteeTransforms),
        _rewindChildren =
            ByteBufferDataInputStream(visiteeChildren, Endian.little),
        _rewindArgs = FloatBufferInputStream(visiteeArgs),
        _pathChildrenSeek = Uint32List(visiteeNumPaths),
        _pathArgsSeek = Uint32List(visiteeNumPaths),
        _paintChildrenSeek = Uint32List(visiteeNumPaints),
        _paintArgsSeek = Uint32List(visiteeNumPaints);

  R traverse(R collector) {
    while (!_children.isEOF()) {
      final code = _children.readUnsignedByte();
      if (code < SIGenericCompactBuilder.PATH_CODE) {
        // it's GROUP_CODE
        assert(SIGenericCompactBuilder.GROUP_CODE & 0x1f == 0);
        collector = group(collector,
            hasTransform: _flag(code, 0), hasTransformNumber: _flag(code, 1));
      } else if (code < SIGenericCompactBuilder.CLIPPATH_CODE) {
        assert(SIGenericCompactBuilder.PATH_CODE & 0x1f == 0);
        // it's PATH_CODE
        collector = path(collector,
            hasPathNumber: _flag(code, 0),
            hasPaintNumber: _flag(code, 1),
            colorTypes: ((code >> 2) & 0x7) + 1);
      } else if (code < SIGenericCompactBuilder.END_GROUP_CODE) {
        assert(SIGenericCompactBuilder.CLIPPATH_CODE & 0x01 == 0);
        // it's CLIPPATH_CODE
        final flags = code - SIGenericCompactBuilder.CLIPPATH_CODE;
        collector = clipPath(collector, hasPathNumber: _flag(flags, 0));
      } else if (code == SIGenericCompactBuilder.END_GROUP_CODE) {
        if (_groupDepth <= 0) {
          throw ParseError('Unexpected END_GROUP_CODE');
        } else {
          collector = _visitor.endGroup(collector);
          return collector;
        }
      } else {
        throw ParseError('Bad code $code');
      }
    }
    assert(_groupDepth == 0, '$_groupDepth');
    assert(_children.isEOF());
    assert(_args.isEOF, '$_args');
    assert(_currPathID == _pathChildrenSeek.length);
    assert(_currPaintID == _paintChildrenSeek.length);
    return collector;
  }

  R group(R collector,
      {required bool hasTransform, required bool hasTransformNumber}) {
    final Affine? transform;
    if (hasTransform) {
      if (hasTransformNumber) {
        final n = _children.readUnsignedInt();
        transform = _transforms.getAffineAt(n);
      } else {
        transform = _transforms.getAffine();
      }
    } else {
      transform = null;
    }
    throw UnimplementedError("@@ TODO:");
    // collector = _visitor.group(collector, transform);
    if (_DEBUG_COMPACT) {
      int currArgSeek = _children.readUnsignedInt() - 100;
      assert(currArgSeek == _args.seek);
      int d = _children.readUnsignedShort();
      assert(d == _groupDepth, '$d == $_groupDepth at ${_children.seek}');
    }
    _groupDepth++;
    collector = traverse(collector); // Traverse our children
    _groupDepth--;
    return collector;
  }

  R path(R collector,
      {required bool hasPathNumber,
      required bool hasPaintNumber,
      required int colorTypes}) {
    final siPaint =
        _getPaint(hasPaintNumber: hasPaintNumber, colorTypes: colorTypes);
    if (_DEBUG_COMPACT) {
      int currArgSeek = _children.readUnsignedInt() - 100;
      assert(currArgSeek == _args.seek, '$currArgSeek, $_args');
    }
    final CompactChildData pathData = _getPathData(hasPathNumber);
    collector = _visitor.path(collector, pathData, siPaint);
    return collector;
  }

  R clipPath(R collector, {required bool hasPathNumber}) {
    final CompactChildData pathData = _getPathData(hasPathNumber);
    collector = _visitor.clipPath(collector, pathData);
    if (_DEBUG_COMPACT) {
      int currArgSeek = _children.readUnsignedInt() - 100;
      assert(currArgSeek == _args.seek);
    }
    return collector;
  }

  SIPaint _getPaint({required bool hasPaintNumber, required int colorTypes}) {
    final fillColorType = SIColorType.values[colorTypes ~/ 3];
    final strokeColorType = SIColorType.values[colorTypes % 3];
    final int flags;
    final int oldChildrenSeek;
    final int oldArgsSeek;
    final ByteBufferDataInputStream children;
    final FloatBufferInputStream args;
    if (hasPaintNumber) {
      final paintNumber = _children.readUnsignedInt();
      oldChildrenSeek = _rewindChildren.seek;
      oldArgsSeek = _rewindChildren.seek;
      _rewindChildren.seek = _paintChildrenSeek[paintNumber];
      _rewindArgs.seek = _paintArgsSeek[paintNumber];
      children = _rewindChildren;
      args = _rewindArgs;
    } else {
      _paintChildrenSeek[_currPaintID] = _children.seek;
      _paintArgsSeek[_currPaintID] = _args.seek;
      _currPaintID++;
      oldChildrenSeek = 0;
      oldArgsSeek = 0;
      children = _children;
      args = _args;
    }
    flags = children.readUnsignedByte();
    final hasStrokeWidth = _flag(flags, 1);
    final hasStrokeMiterLimit = _flag(flags, 2);
    final strokeJoin = SIStrokeJoin.values[(flags >> 3) & 0x3];
    final strokeCap = SIStrokeCap.values[(flags >> 5) & 0x03];
    final fillType = SIFillType.values[(flags >> 7) & 0x01];
    final fillColor =
        (fillColorType == SIColorType.value) ? children.readUnsignedInt() : 0;
    final strokeColor =
        (strokeColorType == SIColorType.value) ? children.readUnsignedInt() : 0;
    final strokeWidth = hasStrokeWidth ? args.get() : null;
    final strokeMiterLimit = hasStrokeMiterLimit ? args.get() : null;
    final r = SIPaint(
        fillColor: fillColor,
        fillColorType: fillColorType,
        strokeColor: strokeColor,
        strokeColorType: strokeColorType,
        strokeWidth: strokeWidth,
        strokeMiterLimit: strokeMiterLimit,
        strokeJoin: strokeJoin,
        strokeCap: strokeCap,
        fillType: fillType);
    if (hasPaintNumber) {
      _rewindChildren.seek = oldChildrenSeek;
      _rewindArgs.seek = oldArgsSeek;
    }
    return r;
  }

  CompactChildData _getPathData(bool hasPathNumber) {
    if (hasPathNumber) {
      final pathNumber = _children.readUnsignedInt();
      _rewindChildren.seek = _pathChildrenSeek[pathNumber];
      _rewindArgs.seek = _pathArgsSeek[pathNumber];
      return CompactChildData(_rewindChildren, _rewindArgs);
    } else {
      _pathChildrenSeek[_currPathID] = _children.seek;
      _pathArgsSeek[_currPathID] = _args.seek;
      _currPathID++;
      return CompactChildData(_children, _args);
    }
  }

  static bool _flag(int v, int bitNumber) => ((v >> bitNumber) & 1) == 1;
}

///
/// A scalable image that's represented by a compact packed binary format
/// that is interpreted when rendering.
///
mixin ScalableImageCompactGeneric<ColorT, BlendModeT> {
  double? get width;
  double? get height;
  Rectangle<double>? viewbox;   // @@ TODO

  bool get bigFloats;
  int get _numPaths;
  int get _numPaints;
  Uint8List get _children;
  List<double> get _args; // Float32List or Float64List
  List<double> get _transforms; // Float32List or Float64List
  ColorT? get tintColor;
  BlendModeT get tintMode;

  int writeToFile(File out) {
    int numWritten = 0;
    if (_DEBUG_COMPACT) {
      throw StateError("Can't write file with _DEBUG_COMPACT turned on.");
    }
    final os = DataOutputSink(out.openWrite(), Endian.big);
    // TODO:  Move constants somewhere more sensible
    os.writeUnsignedInt(0xb0b01e07);
    numWritten += 4;
    //  Bobo-Dioulasso and Léo, Burkina Faso, plus 7 for luck
    const int version = 0;
    // There's plenty of extensibility built into this format, if one were
    // to want to extend it while still reading legacy files.  But the
    // intended usage is to display assets that are bundled with the
    // application, so actually doing anything beyond failing on version #
    // mismatch would probably be overkill, if the format ever does evolve.
    os.writeByte(0); // Word align
    os.writeUnsignedShort(version);
    os.writeByte(SIGenericCompactBuilder._flag(width != null, 0) |
        SIGenericCompactBuilder._flag(height != null, 1) |
        SIGenericCompactBuilder._flag(bigFloats, 2) |
        SIGenericCompactBuilder._flag(tintColor != null, 3));
    numWritten += 4;
    os.writeUnsignedInt(_numPaths);
    os.writeUnsignedInt(_numPaints);
    os.writeUnsignedInt(_args.length);
    os.writeUnsignedInt(_transforms.length);
    numWritten += 16;
    // Note that we're word-aligned here.  Keeping the floats word-aligned
    // might speed things up a bit.
    for (final fa in [_args, _transforms]) {
      if (bigFloats) {
        fa as Float64List;
        os.writeBytes(
            fa.buffer.asUint8List(fa.offsetInBytes, fa.lengthInBytes));
        numWritten += fa.lengthInBytes;
      } else {
        fa as Float32List;
        os.writeBytes(
            fa.buffer.asUint8List(fa.offsetInBytes, fa.lengthInBytes));
        numWritten += fa.lengthInBytes;
      }
    }
    numWritten += _writeFloatIfNotNull(os, width);
    numWritten += _writeFloatIfNotNull(os, height);
    if (tintColor != null) {
      os.writeUnsignedInt(colorValue(tintColor!));
      os.writeByte(blendModeToSI(tintMode).index);
      numWritten += 5;
    }
    // We put this last.  That way, we don't need to store the length.
    os.writeBytes(_children);
    numWritten += _children.lengthInBytes;
    os.close();
    return numWritten;
  }

  int _writeFloatIfNotNull(DataOutputSink os, double? val) {
    if (val != null) {
      if (bigFloats) {
        os.writeDouble(val);
        return 8;
      } else {
        os.writeFloat(val);
        return 4;
      }
    } else {
      return 0;
    }
  }

  int colorValue(ColorT tintColor);

  SITintMode blendModeToSI(BlendModeT b);
}

class ScalableImageCompactNoUI
    with ScalableImageCompactGeneric<int, SITintMode> {
  @override
  final List<double> _args;

  @override
  final List<double> _transforms;

  @override
  final Uint8List _children;

  @override
  final int _numPaths;

  @override
  final int _numPaints;

  @override
  final bool bigFloats;

  @override
  final double? height;

  @override
  final double? width;

  @override
  final int? tintColor;

  @override
  final SITintMode tintMode;

  ScalableImageCompactNoUI(
      this._args,
      this._transforms,
      this._children,
      this._numPaths,
      this._numPaints,
      this.bigFloats,
      this.height,
      this.width,
      this.tintColor,
      this.tintMode);

  @override
  SITintMode blendModeToSI(SITintMode b) => b;

  @override
  int colorValue(int tintColor) => tintColor;
}

class CompactChildData {
  final ByteBufferDataInputStream children;
  final FloatBufferInputStream args;

  CompactChildData(this.children, this.args);

  CompactChildData.copy(CompactChildData other)
      : children = ByteBufferDataInputStream.copy(other.children),
        args = FloatBufferInputStream.copy(other.args);

  @override
  bool operator ==(final Object other) {
    if (identical(this, other)) {
      return true;
    } else if (!(other is CompactChildData)) {
      return false;
    } else {
      final r =
          children.seek == other.children.seek && args.seek == other.args.seek;
      return r;
      // We rely on the underlying buffers always being identical
    }
  }

  @override
  int get hashCode => quiver.hash2(children.seek, args.seek);

  @override
  String toString() => '_CompactPathData(${children.seek}, ${args.seek})';
}

// This is the dual of _CompactPathBuilder
class CompactPathParser extends AbstractPathParser {
  final ByteBufferDataInputStream children;
  final FloatBufferInputStream args;

  CompactPathParser(CompactChildData data, PathBuilder builder)
      : children = data.children,
        args = data.args,
        super(builder);

  void parse() {
    for (;;) {
      final b = children.readUnsignedByte();
      final c1 = (b >> 4) & 0xf;
      final c2 = b & 0xf;
      if (_parseCommand(c1)) {
        assert(c2 == 0, '$c1 $c2 $b  at ${children.seek}');
        break;
      }
      if (_parseCommand(c2)) {
        break;
      }
    }
  }

  // Return true on done
  bool _parseCommand(final int c) {
    switch (_PathCommand.values[c]) {
      case _PathCommand.end:
        buildEnd();
        return true;
      case _PathCommand.moveTo:
        double x = args.get();
        double y = args.get();
        buildMoveTo(PointT(x, y));
        break;
      case _PathCommand.lineTo:
        runPathCommand(args.get(), (double x) {
          double y = args.get();
          final dest = PointT(x, y);
          builder.lineTo(dest);
          return dest;
        });
        break;
      case _PathCommand.cubicTo:
        runPathCommand(args.get(), (double x) {
          final control1 = PointT(x, args.get());
          return _cubicTo(control1, args.get());
        });
        break;
      case _PathCommand.cubicToShorthand:
        runPathCommand(args.get(), (double x) {
          return _cubicTo(null, x);
        });
        break;
      case _PathCommand.quadraticBezierTo:
        runPathCommand(args.get(), (double x) {
          final control = PointT(x, args.get());
          return _quadraticBezierTo(control, args.get());
        });
        break;
      case _PathCommand.quadraticBezierToShorthand:
        runPathCommand(args.get(), (double x) {
          return _quadraticBezierTo(null, x);
        });
        break;
      case _PathCommand.arcToPointCircSmallCCW:
        _arcToPointCirc(false, false);
        break;
      case _PathCommand.arcToPointCircSmallCW:
        _arcToPointCirc(false, true);
        break;
      case _PathCommand.arcToPointCircLargeCCW:
        _arcToPointCirc(true, false);
        break;
      case _PathCommand.arcToPointCircLargeCW:
        _arcToPointCirc(true, true);
        break;
      case _PathCommand.arcToPointEllipseSmallCCW:
        _arcToPointEllipse(false, false);
        break;
      case _PathCommand.arcToPointEllipseSmallCW:
        _arcToPointEllipse(false, true);
        break;
      case _PathCommand.arcToPointEllipseLargeCCW:
        _arcToPointEllipse(true, false);
        break;
      case _PathCommand.arcToPointEllipseLargeCW:
        _arcToPointEllipse(true, true);
        break;
      case _PathCommand.close:
        buildClose();
        break;
    }
    return false;
  }

  PointT _quadraticBezierTo(PointT? control, final double x) {
    final p = PointT(x, args.get());
    return buildQuadraticBezier(control, p);
  }

  PointT _cubicTo(PointT? c1, double x2) {
    final c2 = PointT(x2, args.get());
    final x = args.get();
    final p = PointT(x, args.get());
    return buildCubicBezier(c1, c2, p);
  }

  void _arcToPointCirc(bool largeArc, bool clockwise) {
    runPathCommand(args.get(), (final double radius) {
      final r = RadiusT(radius, radius);
      return _arcToPoint(largeArc, clockwise, r);
    });
  }

  void _arcToPointEllipse(bool largeArc, bool clockwise) {
    runPathCommand(args.get(), (final double x) {
      final r = RadiusT(x, args.get());
      return _arcToPoint(largeArc, clockwise, r);
    });
  }

  PointT _arcToPoint(bool largeArc, bool clockwise, RadiusT r) {
    final x = args.get();
    final arcEnd = PointT(x, args.get());
    final rotation = args.get();
    builder.arcToPoint(arcEnd,
        largeArc: largeArc,
        clockwise: clockwise,
        radius: r,
        rotation: rotation);
    return arcEnd;
  }
}

abstract class SIGenericCompactBuilder<PathDataT> extends SIBuilder<PathDataT> {
  final bool bigFloats;
  final ByteSink childrenSink;
  final DataOutputSink children;
  final FloatSink args;
  final FloatSink transforms;

  @override
  final bool warn;

  bool _done = false;
  double? _width;
  double? _height;
  int? _tintColor;
  SITintMode _tintMode;
  final _pathShare = <Object?, int>{};

  // We share path objects.  This is a significant memory savings.  For example,
  // on the "anglo" card deck, it shrinks the number of floats saved by about
  // a factor of 2.4 (from 116802 to 47944; if storing float64's, that's
  // a savings of over 500K).  We *don't* share intermediate nodes, like
  // the in-memory [ScalableImageDag] does.  That would add significant
  // complexity, and on the anglo test image, it only reduced the float
  // usage by 16%.  The int part (_children) is just over 30K, so any
  // savings there can't be significant either.
  final _transformShare = <Affine, int>{};
  final _paintShare = <SIPaint, int>{};
  int _debugGroupDepth = 0; // Should be optimized away when not used

  SIGenericCompactBuilder(this.bigFloats, this.childrenSink, this.children,
      this.args, this.transforms,
      {required this.warn})
      : _tintMode = SITintMode.srcIn;

  static const GROUP_CODE = 0; // 0..31, with room to spare
  static const PATH_CODE = 32; // 32..63, with room to spare
  static const CLIPPATH_CODE = 144; // 144..145
  static const END_GROUP_CODE = 146;

  bool get done => _done;

  double? get width => _width;

  double? get height => _height;

  int? get tintColor => _tintColor;

  SITintMode get tintMode => _tintMode;

  int get numPaths => _pathShare.length;

  int get numPaints => _paintShare.length;

  @override
  void get initial => null;

  static int _flag(bool v, int bit) => v ? (1 << bit) : 0;

  void _writeFloat(double? v) {
    if (v != null) {
      args.add(v);
    }
  }

  void _writeUnsignedInt(int? v) {
    if (v != null) {
      children.writeUnsignedInt(v);
    }
  }

  void _writeTransform(Affine t) {
    _transformShare[t.toKey] = transforms.length;
    transforms.addTransform(t);
  }

  @override
  void vector({required double? width,
    required double? height,
    required int? tintColor,
    required SITintMode? tintMode}) {
    _width = width;
    _height = height;
    _tintColor = tintColor;
    _tintMode = tintMode ?? _tintMode;
  }

  @override
  void endVector() {
    _done = true;
  }

  @override
  void clipPath(void collector, PathDataT pathData) {
    final int? pathNumber = _pathShare[pathData];
    children.writeByte(CLIPPATH_CODE | _flag(pathNumber != null, 0));
    if (pathNumber != null) {
      _writeUnsignedInt(pathNumber);
    } else {
      final len = _pathShare[immutableKey(pathData)] = _pathShare.length;
      assert(len + 1 == _pathShare.length);
      makePath(pathData, CompactPathBuilder(this), warn: warn);
    }
    if (_DEBUG_COMPACT) {
      children.writeUnsignedInt(args.length + 100);
    }
  }

  @override
  void group(void collector, int? transformNumber) {
    throw UnimplementedError("@@ TODO");
    /*
    int? transformNumber;
    if (transform != null) {
      transformNumber = _transformShare[transform];
    }
    children.writeByte(GROUP_CODE |
    _flag(transform != null, 0) |
    _flag(transformNumber != null, 1));
    if (transformNumber != null) {
      _writeUnsignedInt(transformNumber);
    } else if (transform != null) {
      _writeTransform(transform);
    }
    if (_DEBUG_COMPACT) {
      children.writeUnsignedInt(args.length + 100);
      children.writeUnsignedShort(_debugGroupDepth++);
    }
     */
  }

  @override
  void endGroup(void collector) {
    children.writeByte(END_GROUP_CODE);
    if (_DEBUG_COMPACT) {
      _debugGroupDepth--;
    }
  }

  @override
  void path(void collector, PathDataT pathData, SIPaint siPaint) {
    Object? key = immutableKey(pathData);
    final pb = startPath(siPaint, key);
    if (pb != null) {
      makePath(pathData, pb, warn: false);
      // It might have been pruned; in this case, we need to read the path
      // in to position the streams appropriately.
    }
  }

  @override
  PathBuilder? startPath(SIPaint siPaint, Object? pathKey) {
    final int? pathNumber = _pathShare[pathKey];
    final int? paintNumber = _paintShare[siPaint];
    bool hasStrokeWidth = siPaint.strokeWidth != SIPaint.strokeWidthDefault;
    bool hasStrokeMiterLimit =
        siPaint.strokeWidth != SIPaint.strokeMiterLimitDefault;
    assert(SIColorType.none.index == 0 && SIColorType.values.length == 3);
    final colorTypes =
        siPaint.fillColorType.index * 3 + siPaint.strokeColorType.index - 1;
    if (colorTypes == -1) {
      // both can't be invisible
      assert(false);
      return null;
    }
    assert(colorTypes < 8);
    children.writeByte(PATH_CODE |
    _flag(pathNumber != null, 0) |
    _flag(paintNumber != null, 1) |
    colorTypes << 2);
    if (paintNumber != null) {
      children.writeUnsignedInt(paintNumber);
    } else {
      children.writeByte(_flag(hasStrokeWidth, 1) |
      _flag(hasStrokeMiterLimit, 2) |
      siPaint.strokeJoin.index << 3 |
      siPaint.strokeCap.index << 5 |
      siPaint.fillType.index << 7);
      if (siPaint.fillColorType == SIColorType.value) {
        _writeUnsignedInt(siPaint.fillColor);
      }
      if (siPaint.strokeColorType == SIColorType.value) {
        _writeUnsignedInt(siPaint.strokeColor);
      }
      if (hasStrokeWidth) {
        _writeFloat(siPaint.strokeWidth);
      }
      if (hasStrokeMiterLimit) {
        _writeFloat(siPaint.strokeMiterLimit);
      }
      final len = _paintShare[siPaint] = _paintShare.length;
      assert(len + 1 == _paintShare.length);
    }
    if (_DEBUG_COMPACT) {
      children.writeUnsignedInt(args.length + 100);
    }
    if (pathNumber != null) {
      _writeUnsignedInt(pathNumber);
      return null;
    } else {
      final len = _pathShare[pathKey] = _pathShare.length;
      assert(len + 1 == _pathShare.length);
      return CompactPathBuilder(this);
    }
  }

  void dashedPath(void collector, PathDataT pathData, int dashesIndex,
      SIPaint paint) {
    throw UnimplementedError("@@ TODO");
  }

  void makePath(PathDataT pathData, PathBuilder pb, {bool warn = true});

  @override
  void init(void collector, List<SIImageData> im, List<String> strings,
      List<List<double>> floatLists, List<Affine> transforms) {
    throw UnimplementedError("@@ TODO");
  }

  @override
  void image(void collector, imageNumber) {
    throw UnimplementedError("@@ TODO");
  }

  @override
  void text(void collector, int xIndex, int yIndex, int textIndex, SITextAttributes ta, SIPaint p) {
    throw UnimplementedError("@@ TODO");
  }

  PathDataT immutableKey(PathDataT pathData);
}

class SICompactBuilderNoUI extends SIGenericCompactBuilder<String>
    with SIStringPathMaker {

  ScalableImageCompactNoUI? _si;

  SICompactBuilderNoUI._p(bool bigFloats, ByteSink childrenSink, FloatSink args,
      FloatSink transforms, {required bool warn})
      : super(bigFloats, childrenSink,
            DataOutputSink(childrenSink, Endian.little), args, transforms,
            warn: warn);

  factory SICompactBuilderNoUI({required bool bigFloats, required bool warn}) {
    final cs = ByteSink();
    final a = bigFloats ? Float64Sink() : Float32Sink();
    final t = bigFloats ? Float64Sink() : Float32Sink();
    try {
      return SICompactBuilderNoUI._p(bigFloats, cs, a, t, warn: warn);
    } finally {
      cs.close();
    }
  }

  ScalableImageCompactNoUI get si {
    assert(done);
    if (_si != null) {
      return _si!;
    }
    return _si = ScalableImageCompactNoUI(
        args.toList(),
        transforms.toList(),
        childrenSink.toList(),
        _pathShare.length,
        _paintShare.length,
        bigFloats,
        _height,
        _width,
        _tintColor,
        _tintMode);
  }
}

enum _PathCommand {
  // _PathCommand.index is externalized, and the program logic relies on
  // end.index being 0.
  end,
  moveTo,
  lineTo,
  cubicTo,
  cubicToShorthand,
  quadraticBezierTo,
  quadraticBezierToShorthand,
  arcToPointCircSmallCCW,
  arcToPointCircSmallCW,
  arcToPointCircLargeCCW,
  arcToPointCircLargeCW,
  arcToPointEllipseSmallCCW,
  arcToPointEllipseSmallCW,
  arcToPointEllipseLargeCCW,
  arcToPointEllipseLargeCW,
  close
}

class CompactPathBuilder extends PathBuilder {
  final DataOutputSink _children;
  final FloatSink _args;

  int _currByte = 0;

  CompactPathBuilder(SIGenericCompactBuilder b)
      : _children = b.children,
        _args = b.args {
    assert(_PathCommand.end.index == 0);
    assert(_PathCommand.close.index <= 0xf); // Two in one byte!
  }

  void _flush() {
    assert(_currByte != 0xdeadbeef);
    if (_currByte & 0xf0 != 0) {
      assert(_currByte & 0x0f != 0);
      _children.writeByte(_currByte);
      _currByte = 0;
    } else {
      _currByte <<= 4;
    }
  }

  @override
  void moveTo(PointT p) {
    _flush();
    _currByte |= _PathCommand.moveTo.index;
    _args.add(p.x);
    _args.add(p.y);
  }

  @override
  void lineTo(PointT p) {
    _flush();
    _currByte |= _PathCommand.lineTo.index;
    _args.add(p.x);
    _args.add(p.y);
  }

  @override
  void arcToPoint(PointT arcEnd,
      {required RadiusT radius,
      required double rotation,
      required bool largeArc,
      required bool clockwise}) {
    _flush();
    if (radius.x == radius.y) {
      if (largeArc) {
        if (clockwise) {
          _currByte |= _PathCommand.arcToPointCircLargeCW.index;
        } else {
          _currByte |= _PathCommand.arcToPointCircLargeCCW.index;
        }
      } else {
        if (clockwise) {
          _currByte |= _PathCommand.arcToPointCircSmallCW.index;
        } else {
          _currByte |= _PathCommand.arcToPointCircSmallCCW.index;
        }
      }
      _args.add(radius.x);
    } else {
      if (largeArc) {
        if (clockwise) {
          _currByte |= _PathCommand.arcToPointEllipseLargeCW.index;
        } else {
          _currByte |= _PathCommand.arcToPointEllipseLargeCCW.index;
        }
      } else {
        if (clockwise) {
          _currByte |= _PathCommand.arcToPointEllipseSmallCW.index;
        } else {
          _currByte |= _PathCommand.arcToPointEllipseSmallCCW.index;
        }
      }
      _args.add(radius.x);
      _args.add(radius.y);
    }
    _args.add(arcEnd.x);
    _args.add(arcEnd.y);
    _args.add(rotation);
  }

  @override
  void addOval(RectT rect) {
    throw UnimplementedError("@@ TODO");
  }

  @override
  void cubicTo(PointT c1, PointT c2, PointT p, bool shorthand) {
    _flush();
    if (shorthand) {
      _currByte |= _PathCommand.cubicToShorthand.index;
    } else {
      _currByte |= _PathCommand.cubicTo.index;
      _args.add(c1.x);
      _args.add(c1.y);
    }
    _args.add(c2.x);
    _args.add(c2.y);
    _args.add(p.x);
    _args.add(p.y);
  }

  @override
  void quadraticBezierTo(PointT control, PointT p, bool shorthand) {
    _flush();
    if (shorthand) {
      _currByte |= _PathCommand.quadraticBezierToShorthand.index;
    } else {
      _currByte |= _PathCommand.quadraticBezierTo.index;
      _args.add(control.x);
      _args.add(control.y);
    }
    _args.add(p.x);
    _args.add(p.y);
  }

  @override
  void close() {
    _flush();
    _currByte |= _PathCommand.close.index;
  }

  @override
  void end() {
    _flush();
    assert(_currByte & 0x0f == 0);
    _children.writeByte(_currByte);
    assert(0 != (_currByte = 0xdeadbeef));
  }
}

class ByteSink implements Sink<List<int>> {
  final _builder = BytesBuilder();

  @override
  void add(List<int> data) => _builder.add(data);

  @override
  void close() {}

  int get length => _builder.length;

  // Gives a copy of the bytes
  Uint8List toList() => _builder.toBytes();
}

abstract class FloatSink {
  void add(double data);

  int get length;

  List<double> toList();

  void addTransform(Affine t) {
    final buf = Float64List(6);
    t.copyIntoCompact(buf);
    for (double d in buf) {
      add(d);
    }
  }
}

class Float32Sink extends FloatSink {
  final _builder = BytesBuilder();

  @override
  void add(double data) {
    final d = ByteData(4)..setFloat32(0, data, Endian.little);
    _builder.add(d.buffer.asUint8List(d.offsetInBytes, 4));
  }

  @override
  int get length => _builder.length ~/ 4;

  @override
  List<double> toList() => Float32List.sublistView(_builder.toBytes(), 0);
}

class Float64Sink extends FloatSink {
  final _builder = BytesBuilder();

  @override
  void add(double data) {
    final d = ByteData(8)..setFloat64(0, data, Endian.little);
    _builder.add(d.buffer.asUint8List(d.offsetInBytes, 8));
  }

  @override
  int get length => _builder.length ~/ 8;

  @override
  List<double> toList() => Float64List.sublistView(_builder.toBytes(), 0);
}

class FloatBufferInputStream {
  /// The position within the buffer
  int seek = 0;
  final List<double> _buf;

  FloatBufferInputStream(this._buf);

  FloatBufferInputStream.copy(FloatBufferInputStream other)
      : seek = other.seek,
        _buf = other._buf;

  double get() => _buf[seek++];

  bool get isEOF => seek == _buf.length;

  Affine getAffine() {
    final a = getAffineAt(seek);
    seek += 6;
    return a;
  }

  Affine getAffineAt(int pos) => Affine.fromCompact(_buf, pos);

  @override
  String toString() =>
      'FloatBufferInputStream(seek: $seek, length: ${_buf.length})';
}
