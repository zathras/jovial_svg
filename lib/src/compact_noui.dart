// ignore_for_file: constant_identifier_names

/*
MIT License

Copyright (c) 2021-2024, William Foote

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

import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:jovial_misc/io_utils.dart';
import 'affine.dart';
import 'common_noui.dart';
import 'path_noui.dart';

///
/// A CompactTraverser reads the data produced by an [SIGenericCompactBuilder],
/// traversing the represented graph.
///
abstract class CompactTraverserBase<R, IM,
    VT extends SIVisitor<CompactChildData, IM, R>> {
  final int fileVersion; // See [ScalableImageCompactGeneric.latestFileVersion]
  final bool bigFloats;
  @protected
  final VT visitor;
  final List<String> _strings;
  final List<List<double>> _floatLists;
  final List<List<String>> _stringLists;
  final List<double> _floatValues;
  final List<IM> _images;
  final ByteBufferDataInputStream _children;
  final FloatBufferInputStream _args;
  final FloatBufferInputStream _transforms;
  final ByteBufferDataInputStream _rewindChildren;
  final FloatBufferInputStream _rewindArgs;
  // Position by path ID
  final Uint32List _pathChildrenSeek;
  final Uint32List _pathArgsSeek;
  int _currPathID;
  final Uint32List _paintChildrenSeek;
  final Uint32List _paintArgsSeek;
  final Uint32List _paintTransformsSeek;
  int _currPaintID;
  @protected
  int groupDepth;

  @protected
  CompactTraverserBase.clone(
      CompactTraverserBase<R, IM, SIVisitor<CompactChildData, IM, R>> other,
      this.visitor)
      : fileVersion = other.fileVersion,
        bigFloats = other.bigFloats,
        _strings = other._strings,
        _stringLists = other._stringLists,
        _floatLists = other._floatLists,
        _floatValues = other._floatValues,
        _images = other._images,
        _children = ByteBufferDataInputStream.copy(other._children),
        _args = FloatBufferInputStream.copy(other._args),
        _transforms = FloatBufferInputStream.copy(other._transforms),
        _rewindChildren = ByteBufferDataInputStream.copy(other._rewindChildren),
        _rewindArgs = FloatBufferInputStream.copy(other._rewindArgs),
        _pathChildrenSeek = Uint32List.fromList(other._pathChildrenSeek),
        _pathArgsSeek = Uint32List.fromList(other._pathArgsSeek),
        _currPathID = other._currPathID,
        _paintChildrenSeek = Uint32List.fromList(other._paintChildrenSeek),
        _paintArgsSeek = Uint32List.fromList(other._paintArgsSeek),
        _paintTransformsSeek = Uint32List.fromList(other._paintTransformsSeek),
        _currPaintID = other._currPaintID,
        groupDepth = other.groupDepth;

  CompactTraverserBase(
      {required this.fileVersion,
      required this.bigFloats,
      required Uint8List visiteeChildren,
      required List<double> visiteeArgs,
      required List<double> visiteeTransforms,
      required int visiteeNumPaths,
      required int visiteeNumPaints,
      required this.visitor,
      required List<String> strings,
      required List<List<String>> stringLists,
      required List<List<double>> floatLists,
      required List<double> floatValues,
      required List<IM> images})
      : _strings = strings,
        _stringLists =
            (fileVersion <= 9) ? LegacyStringLists(strings) : stringLists,
        _floatLists = floatLists,
        _floatValues = floatValues,
        _images = images,
        _children = ByteBufferDataInputStream(visiteeChildren, Endian.little),
        _args = FloatBufferInputStream(visiteeArgs),
        _transforms = FloatBufferInputStream(visiteeTransforms),
        _rewindChildren =
            ByteBufferDataInputStream(visiteeChildren, Endian.little),
        _rewindArgs = FloatBufferInputStream(visiteeArgs),
        _pathChildrenSeek = Uint32List(visiteeNumPaths),
        _pathArgsSeek = Uint32List(visiteeNumPaths),
        _paintChildrenSeek = Uint32List(visiteeNumPaints),
        _paintArgsSeek = Uint32List(visiteeNumPaints),
        _paintTransformsSeek = Uint32List(visiteeNumPaints),
        _currPathID = 0,
        _currPaintID = 0,
        groupDepth = 0;

  R traverse(R collector) {
    collector = visitor.init(collector, _images, _strings, _floatLists,
        _stringLists, _floatValues, null);
    final r = traverseGroup(collector);
    visitor.traversalDone();
    closeStreams();
    return r;
  }

  @protected
  void closeStreams() {
    _children.close();
    _args.close();
    _transforms.close();
    _rewindChildren.close();
    _rewindArgs.close();
    _currPathID = _pathChildrenSeek.length;
    _currPaintID = _paintChildrenSeek.length;
  }

  R traverseGroup(R collector) {
    while (!_children.isEOF()) {
      final code = _children.readUnsignedByte();
      if (code < SIGenericCompactBuilder.LEGACY_TEXT_CODE) {
        // It's PATH_CODE
        collector = path(collector,
            hasPathNumber: _flag(code, 0),
            hasPaintNumber: _flag(code, 1),
            fillColorType: (code >> 2) & 0x3,
            strokeColorType: (code >> 4) & 0x3);
      } else if (code < SIGenericCompactBuilder.GROUP_CODE) {
        // it's LEGACY_TEXT_CODE
        assert(SIGenericCompactBuilder.LEGACY_TEXT_CODE & 0x3f == 0);
        collector = legacyText(collector,
            hasPaintNumber: _flag(code, 0),
            hasFontFamilyIndex: _flag(code, 1),
            fillColorType: (code >> 2) & 0x3,
            strokeColorType: (code >> 4) & 0x3);
      } else if (code < SIGenericCompactBuilder.CLIPPATH_CODE) {
        // it's GROUP_CODE
        assert(SIGenericCompactBuilder.GROUP_CODE & 0x7 == 0);
        collector = group(collector,
            blendMode: SIBlendMode.normal,
            hasTransform: _flag(code, 0),
            hasTransformNumber: _flag(code, 1),
            hasGroupAlpha: _flag(code, 2));
      } else if (code < SIGenericCompactBuilder.IMAGE_CODE) {
        // it's CLIPPATH_CODE
        assert(SIGenericCompactBuilder.CLIPPATH_CODE & 0x1 == 0);
        collector = clipPath(collector, hasPathNumber: _flag(code, 0));
      } else if (code < SIGenericCompactBuilder.END_GROUP_CODE) {
        // it's IMAGE_CODE
        collector = image(collector);
      } else if (code == SIGenericCompactBuilder.END_GROUP_CODE) {
        if (groupDepth <= 0) {
          throw ParseError('Unexpected END_GROUP_CODE'); // coverage:ignore-line
        } else {
          collector = visitor.endGroup(collector);
          return collector;
        }
      } else if (code == SIGenericCompactBuilder.MASKED_CHILD_CODE) {
        collector = maskedChild(collector);
      } else if (code == SIGenericCompactBuilder.END_MASKED_CODE) {
        if (groupDepth <= 0) {
          throw ParseError(
              'Unexpected END_MASKED_CODE'); // coverage:ignore-line
        } else {
          return visitor.endMasked(collector);
        }
      } else if (code < SIGenericCompactBuilder.MASKED_CODE_NO_LUMA + 2) {
        assert(code & 0xfe == SIGenericCompactBuilder.MASKED_CODE ||
            code & 0xfe == SIGenericCompactBuilder.MASKED_CODE_NO_LUMA);
        // MASKED_CODE is split in two for backwards compatibility with
        // jovial_svg 1.1.0-rc1 through 3
        assert(SIGenericCompactBuilder.MASKED_CODE & 0x1 == 0);
        assert(SIGenericCompactBuilder.MASKED_CODE_NO_LUMA & 0x1 == 0);

        final RectT? maskBounds;
        if (_flag(code, 0)) {
          maskBounds =
              RectT(_args.get(), _args.get(), _args.get(), _args.get());
        } else {
          maskBounds = null;
        }
        final bool usesLuma =
            code & 0xfe == SIGenericCompactBuilder.MASKED_CODE;
        collector = masked(collector, maskBounds, usesLuma);
      } else if (code == SIGenericCompactBuilder.EXTENDED_GROUP_CODE) {
        int stuff = _children.readByte();
        final blendMode = SIBlendMode.values[stuff & 0xf];
        collector = group(collector,
            blendMode: blendMode,
            hasTransform: _flag(stuff, 4),
            hasTransformNumber: _flag(stuff, 5),
            hasGroupAlpha: _flag(stuff, 6));
      } else if (code == SIGenericCompactBuilder.TEXT_CODE) {
        collector = text(collector);
      } else if (code == SIGenericCompactBuilder.TEXT_SPAN_CODE) {
        collector = textSpan(collector);
      } else if (code == SIGenericCompactBuilder.TEXT_MULTI_CODE) {
        collector = textMulti(collector);
      } else if (code == SIGenericCompactBuilder.TEXT_END_CODE) {
        collector = textEnd(collector);
      } else if (code == SIGenericCompactBuilder.EXPORTED_ID_CODE) {
        collector = exportedId(collector);
      } else if (code == SIGenericCompactBuilder.END_EXPORTED_ID_CODE) {
        collector = endExportedId(collector);
      } else {
        throw ParseError('Bad code $code');
      }
    }
    assert(groupDepth == 0, '$groupDepth');
    assert(_children.isEOF());
    assert(_args.isEOF, '$_args');
    assert(_currPathID == _pathChildrenSeek.length);
    assert(_currPaintID == _paintChildrenSeek.length);
    return collector;
  }

  Affine? _getTransform(bool hasTransform, bool hasTransformNumber,
      ByteBufferDataInputStream children) {
    if (hasTransformNumber) {
      assert(hasTransform);
      return _transforms.getAffineAt(_readSmallishInt(children) * 6);
    } else if (hasTransform) {
      return _transforms.getAffine();
    } else {
      return null;
    }
  }

  R masked(R collector, RectT? maskBounds, bool usesLuma) {
    collector = visitor.masked(collector, maskBounds, usesLuma);
    groupDepth++;
    collector = traverseGroup(collector);
    groupDepth--;
    return collector;
  }

  R maskedChild(R collector) => visitor.maskedChild(collector);

  R group(R collector,
      {required SIBlendMode blendMode,
      required bool hasTransform,
      required bool hasTransformNumber,
      required bool hasGroupAlpha}) {
    final Affine? transform =
        _getTransform(hasTransform, hasTransformNumber, _children);
    final int? groupAlpha = hasGroupAlpha ? _children.readUnsignedByte() : null;
    collector = visitor.group(collector, transform, groupAlpha, blendMode);
    groupDepth++;
    collector = traverseGroup(collector); // Traverse our children
    groupDepth--;
    return collector;
  }

  R path(R collector,
      {required bool hasPathNumber,
      required bool hasPaintNumber,
      required int fillColorType,
      required int strokeColorType}) {
    final siPaint = _getPaint(
        hasPaintNumber: hasPaintNumber,
        fillColorType: fillColorType,
        strokeColorType: strokeColorType);
    final CompactChildData pathData = _getPathData(hasPathNumber);
    return visitor.path(collector, pathData, siPaint);
  }

  R legacyText(R collector,
      {required bool hasPaintNumber,
      required bool hasFontFamilyIndex,
      required int fillColorType,
      required int strokeColorType}) {
    final p = _getPaint(
        hasPaintNumber: hasPaintNumber,
        fillColorType: fillColorType,
        strokeColorType: strokeColorType);
    final xi = _readSmallishInt(_children);
    final yi = _readSmallishInt(_children);
    final textIndex = _readSmallishInt(_children);
    final ffi = hasFontFamilyIndex ? _readSmallishInt(_children) : null;
    final byte = _children.readUnsignedByte();
    final style = SIFontStyle.values[byte & 0x1];
    final weight = SIFontWeight.values[(byte >> 1) & 0xf];
    final anchor = (fileVersion < 2)
        ? SITextAnchor.start
        : SITextAnchor.values[(byte >> 5) & 0x03];
    const dominantBaseline = SIDominantBaseline.auto; // Just default value
    final SITextDecoration decoration;
    if (fileVersion < 6) {
      decoration = SITextDecoration.none;
    } else {
      final byte = _children.readUnsignedByte();
      decoration = SITextDecoration.values[byte & 0x03];
    }

    final fontSize = _args.get();
    final ta = SITextAttributes(
        fontFamily: (ffi == null) ? null : _stringLists[ffi],
        fontStyle: style,
        textAnchor: anchor,
        dominantBaseline: dominantBaseline,
        fontSize: fontSize,
        fontWeight: weight,
        textDecoration: decoration);
    return visitor.legacyText(collector, xi, yi, textIndex, ta, ffi, p);
  }

  R text(R collector) {
    return visitor.text(collector);
  }

  R textSpan(R collector) {
    final int dxIndex = _readSmallishInt(_children);
    final int dyIndex = _readSmallishInt(_children);
    final int textIndex = _readSmallishInt(_children);

    int byte = _children.readUnsignedByte();
    final style = SIFontStyle.values[byte & 0x1];
    final weight = SIFontWeight.values[(byte >> 1) & 0xf];
    final anchor = SITextAnchor.values[(byte >> 5) & 0x03];
    const dominantBaseline = SIDominantBaseline.auto; // Just default value
    byte = _children.readUnsignedByte();
    final ffi = _flag(byte, 1) ? _readSmallishInt(_children) : null;
    final fontSizeIndex = _readSmallishInt(_children);
    final SITextDecoration decoration =
        SITextDecoration.values[(byte >> 2) & 0x03];
    final paint = _getPaint(
        hasPaintNumber: _flag(byte, 0),
        fillColorType: (byte >> 4) & 0x03,
        strokeColorType: (byte >> 6) & 0x03);
    final List<String>? fontFamily;
    if (ffi == null) {
      fontFamily = null;
    } else {
      fontFamily = _stringLists[ffi];
    }
    final ta = SITextAttributes(
        fontFamily: fontFamily,
        fontStyle: style,
        textAnchor: anchor,
        dominantBaseline: dominantBaseline,
        fontSize: _floatValues[fontSizeIndex],
        fontWeight: weight,
        textDecoration: decoration);
    return visitor.textSpan(
        collector, dxIndex, dyIndex, textIndex, ta, ffi, fontSizeIndex, paint);
  }

  R textMulti(R collector) {
    final anchor = SITextAnchor.values[_children.readUnsignedByte()];
    final dxIndex = _readSmallishInt(_children);
    final dyIndex = _readSmallishInt(_children);
    return visitor.textMultiSpanChunk(collector, dxIndex, dyIndex, anchor);
  }

  R textEnd(R collector) {
    return visitor.textEnd(collector);
  }

  R exportedId(R collector) {
    final idIndex = _readSmallishInt(_children);
    return visitor.exportedID(collector, idIndex);
  }

  R endExportedId(R collector) {
    return visitor.endExportedID(collector);
  }

  R image(R collector) {
    return visitor.image(collector, _readSmallishInt(_children));
  }

  R clipPath(R collector, {required bool hasPathNumber}) {
    final CompactChildData pathData = _getPathData(hasPathNumber);
    collector = visitor.clipPath(collector, pathData);
    return collector;
  }

  SIPaint _getPaint(
      {required bool hasPaintNumber,
      required int fillColorType,
      required int strokeColorType}) {
    final int flags;
    final int oldChildrenSeek;
    final int oldArgsSeek;
    final int oldTransformsSeek;
    final ByteBufferDataInputStream children;
    final FloatBufferInputStream args;
    if (hasPaintNumber) {
      final paintNumber = _readSmallishInt(_children);
      oldChildrenSeek = _rewindChildren.seek;
      oldArgsSeek = _rewindChildren.seek;
      oldTransformsSeek = _transforms.seek;
      _rewindChildren.seek = _paintChildrenSeek[paintNumber];
      _rewindArgs.seek = _paintArgsSeek[paintNumber];
      _transforms.seek = _paintTransformsSeek[paintNumber];
      children = _rewindChildren;
      args = _rewindArgs;
    } else {
      _paintChildrenSeek[_currPaintID] = _children.seek;
      _paintArgsSeek[_currPaintID] = _args.seek;
      _paintTransformsSeek[_currPaintID] = _transforms.seek;
      _currPaintID++;
      oldChildrenSeek = 0;
      oldArgsSeek = 0;
      oldTransformsSeek = 0;
      children = _children;
      args = _args;
    }
    flags = children.readUnsignedByte();
    final hasStrokeWidth = _flag(flags, 0);
    final hasStrokeMiterLimit = _flag(flags, 1);
    final strokeJoin = SIStrokeJoin.values[(flags >> 2) & 0x3];
    final strokeCap = SIStrokeCap.values[(flags >> 4) & 0x03];
    final fillType = SIFillType.values[(flags >> 6) & 0x01];
    final hasStrokeDashArray = _flag(flags, 7);
    final hasStrokeDashOffset =
        hasStrokeDashArray ? _flag(children.readUnsignedByte(), 0) : false;
    final fillColor = _readColor(fillColorType, children, args);
    final strokeColor = _readColor(strokeColorType, children, args);
    final strokeWidth = hasStrokeWidth ? args.get() : null;
    final strokeMiterLimit = hasStrokeMiterLimit ? args.get() : null;
    final strokeDashArray = hasStrokeDashArray
        ? List<double>.generate(_readSmallishInt(children), (_) => args.get(),
            growable: false)
        : null;
    final strokeDashOffset = hasStrokeDashOffset ? args.get() : null;
    final r = SIPaint(
        fillColor: fillColor,
        strokeColor: strokeColor,
        strokeWidth: strokeWidth ?? SIPaint.strokeWidthDefault,
        strokeMiterLimit: strokeMiterLimit ?? SIPaint.strokeMiterLimitDefault,
        strokeJoin: strokeJoin,
        strokeCap: strokeCap,
        fillType: fillType,
        strokeDashArray: strokeDashArray,
        strokeDashOffset: strokeDashOffset);
    if (hasPaintNumber) {
      _transforms.seek = oldTransformsSeek;
      _rewindChildren.seek = oldChildrenSeek;
      _rewindArgs.seek = oldArgsSeek;
    }
    return r;
  }

  SIColor _readColor(int colorType, ByteBufferDataInputStream children,
      FloatBufferInputStream args) {
    if (colorType == 0) {
      return SIValueColor(children.readUnsignedInt());
    } else if (colorType == 1) {
      return SIColor.none;
    } else if (colorType == 2) {
      return SIColor.currentColor;
    } else {
      assert(colorType == 3);
      final flags = children.readUnsignedByte();
      final gType = (flags & 0x3);
      bool objectBoundingBox = _flag(flags, 2);
      final sm = SIGradientSpreadMethod.values[(flags >> 3) & 0x3];
      bool hasTransform = _flag(flags, 5);
      bool hasTransformNumber = _flag(flags, 6);
      final Affine? transform =
          _getTransform(hasTransform, hasTransformNumber, children);
      final len = _readSmallishInt(children);
      final stops = List<double>.generate(
          len, (_) => _readSharedFloat(children, args),
          growable: false);
      final colors = List<SIColor>.generate(len, (_) {
        final ct = children.readUnsignedByte();
        assert(ct != 3);
        return _readColor(ct, children, args);
      }, growable: false);
      if (gType == 0) {
        final x1 = _readSharedFloat(children, args);
        final y1 = _readSharedFloat(children, args);
        final x2 = _readSharedFloat(children, args);
        final y2 = _readSharedFloat(children, args);
        return SILinearGradientColor(
            x1: x1,
            y1: y1,
            x2: x2,
            y2: y2,
            objectBoundingBox: objectBoundingBox,
            spreadMethod: sm,
            transform: transform,
            stops: stops,
            colors: colors);
      } else if (gType == 1) {
        final cx = _readSharedFloat(children, args);
        final cy = _readSharedFloat(children, args);
        final double fx;
        final double fy;
        if (fileVersion <= 3) {
          fx = cx;
          fy = cy;
        } else {
          fx = _readSharedFloat(children, args);
          fy = _readSharedFloat(children, args);
        }
        final r = _readSharedFloat(children, args);
        return SIRadialGradientColor(
            cx: cx,
            cy: cy,
            fx: fx,
            fy: fy,
            r: r,
            objectBoundingBox: objectBoundingBox,
            spreadMethod: sm,
            transform: transform,
            stops: stops,
            colors: colors);
      } else {
        assert(gType == 2);
        final cx = _readSharedFloat(children, args);
        final cy = _readSharedFloat(children, args);
        final startAngle = _readSharedFloat(children, args);
        final endAngle = _readSharedFloat(children, args);
        return SISweepGradientColor(
            cx: cx,
            cy: cy,
            startAngle: startAngle,
            endAngle: endAngle,
            objectBoundingBox: objectBoundingBox,
            spreadMethod: sm,
            transform: transform,
            stops: stops,
            colors: colors);
      }
    }
  }

  double _readSharedFloat(
      ByteBufferDataInputStream children, FloatBufferInputStream args) {
    if (fileVersion >= 7) {
      return _floatValues[_readSmallishInt(children)];
    } else {
      return args.get();
    }
  }

  CompactChildData _getPathData(bool hasPathNumber) {
    if (hasPathNumber) {
      final pathNumber = _readSmallishInt(_children);
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

  @protected
  void endTraversalEarly() {
    closeStreams();
    groupDepth = 0;
  }

  int get currentPosition => _children.seek;

  static bool _flag(int v, int bitNumber) => ((v >> bitNumber) & 1) == 1;
}

class LegacyStringLists extends ListBase<List<String>> {
  final List<String> _strings;
  final List<List<String>?> _stringLists;

  LegacyStringLists(List<String> strings)
      : _strings = strings,
        _stringLists =
            List<List<String>?>.filled(strings.length, null, growable: false);

  @override
  int get length => _strings.length;
  @override
  set length(int v) => throw Exception('Immutable list');

  @override
  List<String> operator [](int i) {
    List<String>? result = _stringLists[i];
    if (result != null) {
      return result;
    }
    return _stringLists[i] = List.unmodifiable([_strings[i]]);
  }

  @override
  void operator []=(int index, List<String> value) {
    throw Exception('Immutable list');
  }

  @override
  String toString() => 'LegacyStringLists($_strings)';
}

class CompactTraverser<R, IM>
    extends CompactTraverserBase<R, IM, SIVisitor<CompactChildData, IM, R>> {
  CompactTraverser(
      {required super.fileVersion,
      required super.bigFloats,
      required super.visiteeChildren,
      required super.visiteeArgs,
      required super.visiteeTransforms,
      required super.visiteeNumPaths,
      required super.visiteeNumPaints,
      required super.visitor,
      required super.strings,
      required super.stringLists,
      required super.floatLists,
      required super.floatValues,
      required super.images});
}

///
/// A scalable image that's represented by a compact packed binary format
/// that is interpreted when rendering.
///
mixin ScalableImageCompactGeneric<ColorT, BlendModeT, IM> {
  double? get width;
  double? get height;

  bool get bigFloats;
  @protected
  int get numPaths;
  @protected
  int get numPaints;
  @protected
  List<String> get strings;
  @protected
  List<List<double>> get floatLists;
  @protected
  List<List<String>> get stringLists;
  @protected
  List<double> get floatValues;
  @protected
  List<IM> get images;
  @protected
  Uint8List get children;
  @protected
  List<double> get args; // Float32List or Float64List
  @protected
  List<double> get transforms; // Float32List or Float64List
  ColorT? get tintColor;
  BlendModeT get tintMode;
  int get fileVersion;
  int? get currentColorARGB;
  RectT? get givenViewportNoUI;

  ///
  /// The magic number for a .si file, which is written big-endian
  /// (because I'm not o monster).  Named for Bobo-Dioulasso and
  /// Léo, Burkina Faso, plus 7 for luck.
  ///
  static const int magicNumber = 0xb0b01e07;

  ///
  /// File versions:
  ///    0 = not released
  ///    1 = jovial_svg version 1.0.0, June 2021
  ///    2 = jovial_svg version 1.1.0, March 2022
  ///    3 = jovial_svg version 1.1.0 (later release candidate), March 2022
  ///    4 - jovial_svg version 1.1.1.rc-3, March 2022
  ///    5 - jovial_svg version 1.1.3, April 2022
  ///    6 - jovial_svg version 1.1.3, April 2022 (text decoration)
  ///    7 - jovial_svg version 1.1.3, April 2022 (tspan)
  ///    8 - jovial_svg version 1.1.4, April 2022 (expanded tint mode)
  ///    9 - jovial_svg version 1.1.4, April 2022 (givenViewport, currentColor)
  ///    10 - jovial_svg version 1.1.21, March 2024 (font-family as list,
  ///         exported node IDs)
  static const int latestFileVersion = 11;

  ///
  /// Write the compact representation out, and close [out].
  ///
  int writeToFile(DataOutputSink out) {
    assert(fileVersion == latestFileVersion);
    int numWritten = 0;
    out.writeUnsignedInt(magicNumber);
    numWritten += 4;
    // There's plenty of extensibility built into this format, if one were
    // to want to extend it while still reading legacy files.  But the
    // intended usage is to display assets that are bundled with the
    // application, so actually doing anything beyond failing on version #
    // mismatch would probably be overkill, if the format ever does
    // significantly evolve, beyond adding features.
    out.writeByte(0); // Word align
    out.writeUnsignedShort(fileVersion); // Might not be the latest!
    out.writeByte(_flag(width != null, 0) |
        _flag(height != null, 1) |
        _flag(bigFloats, 2) |
        _flag(tintColor != null, 3) |
        _flag(currentColorARGB != null, 4) |
        _flag(givenViewportNoUI != null, 5));
    numWritten += 4;
    out.writeUnsignedInt(numPaths);
    out.writeUnsignedInt(numPaints);
    out.writeUnsignedInt(args.length);
    out.writeUnsignedInt(transforms.length);
    numWritten += 16;
    // Note that we're word-aligned here.  Keeping the floats word-aligned
    // might speed things up a bit.
    for (final fa in [args, transforms]) {
      if (bigFloats) {
        fa as Float64List;
        out.writeBytes(
            fa.buffer.asUint8List(fa.offsetInBytes, fa.lengthInBytes));
        numWritten += fa.lengthInBytes;
      } else {
        fa as Float32List;
        out.writeBytes(
            fa.buffer.asUint8List(fa.offsetInBytes, fa.lengthInBytes));
        numWritten += fa.lengthInBytes;
      }
    }
    numWritten += _writeFloatIfNotNull(out, width);
    numWritten += _writeFloatIfNotNull(out, height);
    final tc = tintColor;
    if (tc != null) {
      out.writeUnsignedInt(colorValue(tc));
      out.writeByte(blendModeToSI(tintMode).index);
      numWritten += 5;
    }
    {
      final cc = currentColorARGB;
      final gv = givenViewportNoUI;
      if (cc != null) {
        numWritten += 4;
        out.writeUnsignedInt(cc);
      }
      if (gv != null) {
        numWritten += _writeFloatIfNotNull(out, gv.left);
        numWritten += _writeFloatIfNotNull(out, gv.top);
        numWritten += _writeFloatIfNotNull(out, gv.width);
        numWritten += _writeFloatIfNotNull(out, gv.height);
      }
    }

    numWritten += _writeSmallishInt(out, strings.length);
    for (final s in strings) {
      final Uint8List x = (const Utf8Encoder()).convert(s);
      numWritten += _writeSmallishInt(out, x.length);
      out.writeBytes(x);
      numWritten += x.length;
    }

    numWritten += _writeSmallishInt(out, stringLists.length);
    if (stringLists.isNotEmpty) {
      final Map<String, int> stringIndex = {
        for (final item in strings.indexed) item.$2: item.$1
      };
      for (final sl in stringLists) {
        numWritten += _writeSmallishInt(out, sl.length);
        for (final s in sl) {
          numWritten += _writeSmallishInt(out, stringIndex[s]!);
        }
      }
    }

    numWritten += _writeSmallishInt(out, floatLists.length);
    for (final fl in floatLists) {
      numWritten += _writeSmallishInt(out, fl.length); // coverage:ignore-line
      // This is a remnant from the legacy text format
      for (final f in fl) {
        // coverage:ignore-line
        numWritten += _writeFloatIfNotNull(out, f); // coverage:ignore-line
      }
    }

    numWritten += _writeSmallishInt(out, floatValues.length);
    for (final f in floatValues) {
      numWritten += _writeFloatIfNotNull(out, f);
    }

    numWritten += _writeSmallishInt(out, images.length);
    for (final IM i in images) {
      final id = getImageData(i);
      numWritten += _writeFloatIfNotNull(out, id.x);
      numWritten += _writeFloatIfNotNull(out, id.y);
      numWritten += _writeFloatIfNotNull(out, id.width);
      numWritten += _writeFloatIfNotNull(out, id.height);
      numWritten += _writeSmallishInt(out, id.encoded.length);
      out.writeBytes(id.encoded);
      numWritten += id.encoded.length;
    }

    // This is last, so we don't need to store the length.
    out.writeBytes(children);
    numWritten += children.lengthInBytes;
    out.close();
    return numWritten;
  }

  SIImageData getImageData(IM image);

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

  ///
  /// Efficiently read an int value that's expected to be small most of
  /// the time.
  ///
  static int readSmallishInt(ByteBufferDataInputStream str) =>
      _readSmallishInt(str);
}

class ScalableImageCompactNoUI
    with ScalableImageCompactGeneric<int, SITintMode, SIImageData> {
  // Our fileVersion is always the latest, because we were just created
  // from scratch.
  @override
  int get fileVersion => ScalableImageCompactGeneric.latestFileVersion;

  @override
  final List<String> strings;

  @override
  final List<List<double>> floatLists;

  @override
  final List<List<String>> stringLists;

  @override
  final List<double> floatValues;

  @override
  final List<SIImageData> images;

  @override
  final List<double> args;

  @override
  final List<double> transforms;

  @override
  final Uint8List children;

  @override
  final int numPaths;

  @override
  final int numPaints;

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

  @override
  int? get currentColorARGB => null;

  // givenViewport is the one programmatically given to a ScalableImage
  // after it has been created.
  @override
  RectT? get givenViewportNoUI => null;

  ScalableImageCompactNoUI(
      this.strings,
      this.stringLists,
      this.floatLists,
      this.floatValues,
      this.images,
      this.args,
      this.transforms,
      this.children,
      this.numPaths,
      this.numPaints,
      this.bigFloats,
      this.height,
      this.width,
      this.tintColor,
      this.tintMode);

  @override
  SITintMode blendModeToSI(SITintMode b) => b;

  @override
  int colorValue(int tintColor) => tintColor;

  @override
  SIImageData getImageData(SIImageData image) => image;
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
    } else if (other is! CompactChildData) {
      return false;
    } else {
      final r =
          children.seek == other.children.seek && args.seek == other.args.seek;
      return r;
      // We rely on the underlying buffers always being identical
    }
  }

  @override
  int get hashCode => 0x4f707180 ^ Object.hash(children.seek, args.seek);

  @override
  String toString() => '_CompactPathData(${children.seek}, ${args.seek})';
}

// This is the dual of _CompactPathBuilder
class CompactPathParser extends AbstractPathParser<EnhancedPathBuilder> {
  final ByteBufferDataInputStream children;
  final FloatBufferInputStream args;
  bool _nextNybble = false;

  CompactPathParser(CompactChildData data, super.builder)
      : children = data.children,
        args = data.args;

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
  bool _parseCommand(int c) {
    if (_nextNybble) {
      c += 14;
      _nextNybble = false;
    } else if (c == 15) {
      _nextNybble = true;
      return false;
    }
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
      case _PathCommand.close:
        buildClose();
        break;
      case _PathCommand.circle:
        _ellipse(true);
        break;
      case _PathCommand.ellipse:
        _ellipse(false);
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

  void _ellipse(bool isCircle) {
    final left = args.get();
    final top = args.get();
    final width = args.get();
    final height = isCircle ? width : args.get();
    builder.addOval(RectT(left, top, width, height));
    // We don't need to do the runPathCommand() because an ellipse/circle
    // is always a stand-alone path.
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

class ColorWriter {
  final DataOutputSink children;
  final int? Function(Affine) _writeTransform;
  final void Function(double) _writeSharedFloat;

  ColorWriter(this.children, this._writeTransform, this._writeSharedFloat);

  void writeColor(SIColor c) {
    void writeGradientStart(int type, SIGradientColor c) {
      int? transformNumber;
      final transform = c.transform;
      if (transform != null) {
        transformNumber = _writeTransform(transform);
      }
      children.writeByte(type |
          _flag(c.objectBoundingBox, 2) |
          ((c.spreadMethod.index) << 3) |
          _flag(transform != null, 5) |
          _flag(transformNumber != null, 6));
      if (transformNumber != null) {
        _writeSmallishInt(children, transformNumber);
      }
      _writeSmallishInt(children, c.colors.length);
      for (int i = 0; i < c.colors.length; i++) {
        _writeSharedFloat(c.stops[i]);
      }
      for (int i = 0; i < c.colors.length; i++) {
        children.writeByte(_getColorType(c.colors[i]));
        writeColor(c.colors[i]);
      }
    }

    c.accept(SIColorVisitor(
        value: (SIValueColor c) => children.writeUnsignedInt(c.argb),
        none: () {},
        current: () {},
        linearGradient: (SILinearGradientColor c) {
          writeGradientStart(0, c);
          _writeSharedFloat(c.x1);
          _writeSharedFloat(c.y1);
          _writeSharedFloat(c.x2);
          _writeSharedFloat(c.y2);
        },
        radialGradient: (SIRadialGradientColor c) {
          writeGradientStart(1, c);
          _writeSharedFloat(c.cx);
          _writeSharedFloat(c.cy);
          _writeSharedFloat(c.fx);
          _writeSharedFloat(c.fy);
          _writeSharedFloat(c.r);
        },
        sweepGradient: (SISweepGradientColor c) {
          writeGradientStart(2, c);
          _writeSharedFloat(c.cx);
          _writeSharedFloat(c.cy);
          _writeSharedFloat(c.startAngle);
          _writeSharedFloat(c.endAngle);
        }));
  }

  void close() => children.close();
}

///
/// Build the binary structures read by a [CompactTraverser] and written out
/// to a `.si` file.
///
abstract class SIGenericCompactBuilder<PathDataT, IM>
    extends SIBuilder<PathDataT, IM> {
  final bool bigFloats;
  final ByteSink childrenSink;
  final DataOutputSink children;
  final FloatSink args;
  final FloatSink transforms;
  ColorWriter? _colorWriter;
  ColorWriter get colorWriter =>
      _colorWriter ?? ColorWriter(children, _writeTransform, _writeSharedFloat);

  @override
  final void Function(String) warn;

  bool _done = false;
  double? _width;
  double? _height;
  int? _tintColor;
  SITintMode _tintMode;
  final _pathShare = <Object?, int>{};
  // We share path objects.  This is a significant memory savings.  For example,
  // on the "anglo" card deck, it shrinks the number of floats by about
  // a factor of 2.4 (from 116802 to 47944; if storing float64's, that's
  // a savings of over 500K).  We *don't* share intermediate nodes, like
  // the in-memory [ScalableImageDag] does.  That would add significant
  // complexity, and on the anglo test image, it only reduced the float
  // usage by 16%.  The int part (_children) is just over 30K, so any
  // savings there can't be significant either.

  final _transformShare = <Affine, int>{};
  final _paintShare = <SIPaint, int>{};
  late final List<String> strings;
  late final List<List<double>> floatLists;
  late final List<List<String>> stringLists;
  late final List<double> floatValues;
  late final CMap<double> _floatValueMap;
  late final List<IM> images;

  SIGenericCompactBuilder(this.bigFloats, this.childrenSink, this.children,
      this.args, this.transforms,
      {required this.warn})
      : _tintMode = SITintMode.srcIn;

  static const PATH_CODE = 0; // 0..63 (6 bits)
  static const LEGACY_TEXT_CODE = 64; // 64..127 (6 bits)
  static const GROUP_CODE = 128; // 128..135 (3 bits)
  static const CLIPPATH_CODE = 136; // 136, 137
  static const IMAGE_CODE = 138;
  static const END_GROUP_CODE = 139;
  static const MASKED_CODE = 140;
  static const MASKED_CHILD_CODE = 142;
  static const END_MASKED_CODE = 143;
  static const MASKED_CODE_NO_LUMA = 144; // 144, 145
  static const EXTENDED_GROUP_CODE = 146; // Like GROUP but with a blend mode
  static const TEXT_CODE = 147;
  static const TEXT_SPAN_CODE = 148;
  static const TEXT_MULTI_CODE = 149;
  static const TEXT_END_CODE = 150;
  static const EXPORTED_ID_CODE = 151;
  static const END_EXPORTED_ID_CODE = 152;

  bool get done => _done;

  double? get width => _width;

  double? get height => _height;

  int? get tintColor => _tintColor;

  SITintMode get tintMode => _tintMode;

  int get numPaths => _pathShare.length;

  int get numPaints => _paintShare.length;

  @override
  void get initial {}

  void _writeFloat(double? v) {
    if (v != null) {
      args.add(v);
    }
  }

  void _writeSharedFloat(double v) =>
      _writeSmallishInt(children, _floatValueMap[v]);

  int? _writeTransform(Affine t) {
    final int len = _transformShare.length;
    int i = _transformShare.putIfAbsent(t.toKey, () => len);
    if (i == len) {
      transforms.addTransform(t);
      return null;
    } else {
      return i;
    }
  }

  @override
  void vector(
      {required double? width,
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

  ///
  /// Called at the beginning, when init() isn't called until the end.
  ///
  void initFloatValueMap(CMap<double> floatValueMap) {
    _floatValueMap = floatValueMap;
  }

  @override
  void init(
      void collector,
      List<IM> im,
      List<String> strings,
      List<List<double>> floatLists,
      List<List<String>> stringLists,
      List<double> floatValues,
      CMap<double>? floatValueMap) {
    images = im;
    this.strings = strings;
    this.floatLists = floatLists;
    this.stringLists = stringLists;
    this.floatValues = floatValues;
    if (floatValueMap != null) {
      _floatValueMap = floatValueMap;
    }
  }

  @override
  void clipPath(void collector, PathDataT pathData) {
    final int? pathNumber = _pathShare[pathData];
    children.writeByte(CLIPPATH_CODE | _flag(pathNumber != null, 0));
    if (pathNumber != null) {
      _writeSmallishInt(children, pathNumber);
    } else {
      final len = _pathShare[immutableKey(pathData)] = _pathShare.length;
      assert(len + 1 == _pathShare.length);
      makePath(pathData, CompactPathBuilder(this), warn: warn);
    }
  }

  @override
  void group(
      void collector, Affine? transform, int? groupAlpha, SIBlendMode blend) {
    int? transformNumber;
    if (transform != null) {
      transformNumber = _writeTransform(transform);
    }
    if (blend == SIBlendMode.normal) {
      children.writeByte(GROUP_CODE |
          _flag(transform != null, 0) |
          _flag(transformNumber != null, 1) |
          _flag(groupAlpha != null, 2));
    } else {
      children.writeByte(EXTENDED_GROUP_CODE);
      children.writeByte(blend.index |
          _flag(transform != null, 4) |
          _flag(transformNumber != null, 5) |
          _flag(groupAlpha != null, 6));
    }
    if (transformNumber != null) {
      _writeSmallishInt(children, transformNumber);
    }
    if (groupAlpha != null) {
      children.writeByte(groupAlpha);
    }
  }

  @override
  void endGroup(void collector) {
    children.writeByte(END_GROUP_CODE);
  }

  @override
  void path(void collector, PathDataT pathData, SIPaint paint) {
    Object? key = immutableKey(pathData);
    final pb = startPath(paint, key);
    if (pb != null) {
      makePath(pathData, pb, warn: (_) {});
    }
  }

  @override
  void image(void collector, int imageIndex) {
    children.writeByte(IMAGE_CODE);
    _writeSmallishInt(children, imageIndex);
  }

  @override
  void legacyText(void collector, int xIndex, int yIndex, int textIndex,
      SITextAttributes a, int? fontFamilyIndex, SIPaint paint) {
    final int? paintNumber = _paintShare[paint];
    children.writeByte(LEGACY_TEXT_CODE |
        _flag(paintNumber != null, 0) |
        _flag(fontFamilyIndex != null, 1) |
        (_getColorType(paint.fillColor) << 2) |
        (_getColorType(paint.strokeColor) << 4));
    if (paintNumber != null) {
      _writeSmallishInt(children, paintNumber);
    } else {
      _writePaint(paint);
    }
    _writeSmallishInt(children, xIndex);
    _writeSmallishInt(children, yIndex);
    _writeSmallishInt(children, textIndex);
    if (fontFamilyIndex != null) {
      _writeSmallishInt(children, fontFamilyIndex);
    }
    children.writeByte(a.fontStyle.index |
        (a.fontWeight.index << 1) |
        (a.textAnchor.index << 5));
    children.writeByte(a.textDecoration.index);
    _writeFloat(a.fontSize);
  }

  @override
  void text(void collector) {
    children.writeByte(TEXT_CODE);
  }

  @override
  void textMultiSpanChunk(
      void collector, int dxIndex, int dyIndex, SITextAnchor anchor) {
    children.writeByte(TEXT_MULTI_CODE);
    children.writeByte(anchor.index);
    _writeSmallishInt(children, dxIndex);
    _writeSmallishInt(children, dyIndex);
  }

  @override
  void textSpan(
      void collector,
      int dxIndex,
      int dyIndex,
      int textIndex,
      SITextAttributes attributes,
      int? fontFamilyIndex,
      int fontSizeIndex,
      SIPaint paint) {
    children.writeByte(TEXT_SPAN_CODE);
    _writeSmallishInt(children, dxIndex);
    _writeSmallishInt(children, dyIndex);
    _writeSmallishInt(children, textIndex);
    final int? paintNumber = _paintShare[paint];

    children.writeByte(attributes.fontStyle.index |
        (attributes.fontWeight.index << 1) |
        (attributes.textAnchor.index << 5));

    children.writeByte(_flag(paintNumber != null, 0) |
        _flag(fontFamilyIndex != null, 1) |
        attributes.textDecoration.index << 2 |
        (_getColorType(paint.fillColor) << 4) |
        (_getColorType(paint.strokeColor) << 6));

    if (fontFamilyIndex != null) {
      _writeSmallishInt(children, fontFamilyIndex);
    }
    _writeSmallishInt(children, fontSizeIndex);
    if (paintNumber != null) {
      _writeSmallishInt(children, paintNumber);
    } else {
      _writePaint(paint);
    }
  }

  @override
  void textEnd(void collector) {
    children.writeByte(TEXT_END_CODE);
  }

  @override
  void exportedID(void collector, int idIndex) {
    children.writeByte(EXPORTED_ID_CODE);
    _writeSmallishInt(children, idIndex);
  }

  @override
  void endExportedID(void collector) {
    children.writeByte(END_EXPORTED_ID_CODE);
  }

  void _writePaint(SIPaint p) {
    bool hasStrokeWidth = p.strokeWidth != SIPaint.strokeWidthDefault;
    bool hasStrokeMiterLimit = p.strokeWidth != SIPaint.strokeMiterLimitDefault;
    final strokeDashArray = p.strokeDashArray;
    final strokeDashOffset = p.strokeDashOffset;
    children.writeByte(_flag(hasStrokeWidth, 0) |
        _flag(hasStrokeMiterLimit, 1) |
        p.strokeJoin.index << 2 |
        p.strokeCap.index << 4 |
        p.fillType.index << 6 |
        _flag(strokeDashArray != null, 7));
    if (strokeDashArray != null) {
      children.writeByte(_flag(strokeDashOffset != null, 0));
    }
    colorWriter.writeColor(p.fillColor);
    colorWriter.writeColor(p.strokeColor);
    if (hasStrokeWidth) {
      _writeFloat(p.strokeWidth);
    }
    if (hasStrokeMiterLimit) {
      _writeFloat(p.strokeMiterLimit);
    }
    if (strokeDashArray != null) {
      _writeSmallishInt(children, strokeDashArray.length);
      for (final f in strokeDashArray) {
        _writeFloat(f);
      }
      if (strokeDashOffset != null) {
        _writeFloat(strokeDashOffset);
      }
    }
    final len = _paintShare[p] = _paintShare.length;
    assert(len + 1 == _paintShare.length);
  }

  @override
  EnhancedPathBuilder? startPath(SIPaint paint, Object? key) {
    final int? pathNumber = _pathShare[key];
    final int? paintNumber = _paintShare[paint];
    children.writeByte(PATH_CODE |
        _flag(pathNumber != null, 0) |
        _flag(paintNumber != null, 1) |
        (_getColorType(paint.fillColor) << 2) |
        (_getColorType(paint.strokeColor) << 4));
    if (paintNumber != null) {
      _writeSmallishInt(children, paintNumber);
    } else {
      _writePaint(paint);
    }
    if (pathNumber != null) {
      _writeSmallishInt(children, pathNumber);
      return null;
    } else {
      final len = _pathShare[key] = _pathShare.length;
      assert(len + 1 == _pathShare.length);
      return CompactPathBuilder(this);
    }
  }

  void makePath(PathDataT pathData, EnhancedPathBuilder pb,
      {required void Function(String) warn});

  PathDataT immutableKey(PathDataT pathData);

  @override
  void masked(void collector, RectT? maskBounds, bool usesLuma) {
    if (usesLuma) {
      children.writeByte(MASKED_CODE | _flag(maskBounds != null, 0));
    } else {
      children.writeByte(MASKED_CODE_NO_LUMA | _flag(maskBounds != null, 0));
    }
    if (maskBounds != null) {
      _writeFloat(maskBounds.left);
      _writeFloat(maskBounds.top);
      _writeFloat(maskBounds.width);
      _writeFloat(maskBounds.height);
    }
  }

  @override
  void maskedChild(void collector) {
    children.writeByte(MASKED_CHILD_CODE);
  }

  @override
  void endMasked(void collector) {
    children.writeByte(END_MASKED_CODE);
  }

  @override
  @mustCallSuper
  void traversalDone() {
    super.traversalDone();
    _colorWriter?.close();
  }

  @override
  void addPath(Object path, SIPaint paint) => unreachable(null);
}

class SICompactBuilderNoUI extends SIGenericCompactBuilder<String, SIImageData>
    with SIStringPathMaker {
  ScalableImageCompactNoUI? _si;

  SICompactBuilderNoUI._p(bool bigFloats, ByteSink childrenSink, FloatSink args,
      FloatSink transforms, {required void Function(String) warn})
      : super(bigFloats, childrenSink,
            DataOutputSink(childrenSink, Endian.little), args, transforms,
            warn: warn);

  factory SICompactBuilderNoUI(
      {required bool bigFloats, required void Function(String) warn}) {
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
        strings,
        stringLists,
        floatLists,
        floatValues,
        images,
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
  close,
  circle,
  ellipse,
  arcToPointCircSmallCCW,
  arcToPointCircSmallCW,
  arcToPointCircLargeCCW,
  arcToPointCircLargeCW,
  arcToPointEllipseSmallCCW,
  arcToPointEllipseSmallCW,
  arcToPointEllipseLargeCCW,
  arcToPointEllipseLargeCW
}

class CompactPathBuilder<PathDataT, IM> extends EnhancedPathBuilder {
  final DataOutputSink _children;
  final FloatSink _args;

  int _currByte = 0;

  CompactPathBuilder(SIGenericCompactBuilder<PathDataT, IM> b)
      : _children = b.children,
        _args = b.args {
    assert(_PathCommand.end.index == 0);
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

  void _send(_PathCommand c) {
    _flush();
    final i = c.index;
    if (i < 15) {
      _currByte |= i;
    } else {
      _currByte |= 15;
      _flush();
      _currByte |= (i - 14);
    }
  }

  @override
  void moveTo(PointT p) {
    _send(_PathCommand.moveTo);
    _args.add(p.x);
    _args.add(p.y);
  }

  @override
  void lineTo(PointT p) {
    _send(_PathCommand.lineTo);
    _args.add(p.x);
    _args.add(p.y);
  }

  @override
  void arcToPoint(PointT arcEnd,
      {required RadiusT radius,
      required double rotation,
      required bool largeArc,
      required bool clockwise}) {
    if (radius.x == radius.y) {
      if (largeArc) {
        if (clockwise) {
          _send(_PathCommand.arcToPointCircLargeCW);
        } else {
          _send(_PathCommand.arcToPointCircLargeCCW);
        }
      } else {
        if (clockwise) {
          _send(_PathCommand.arcToPointCircSmallCW);
        } else {
          _send(_PathCommand.arcToPointCircSmallCCW);
        }
      }
      _args.add(radius.x);
    } else {
      if (largeArc) {
        if (clockwise) {
          _send(_PathCommand.arcToPointEllipseLargeCW);
        } else {
          _send(_PathCommand.arcToPointEllipseLargeCCW);
        }
      } else {
        if (clockwise) {
          _send(_PathCommand.arcToPointEllipseSmallCW);
        } else {
          _send(_PathCommand.arcToPointEllipseSmallCCW);
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
    _args.add(rect.left);
    _args.add(rect.top);
    _args.add(rect.width);
    if (rect.width == rect.height) {
      _send(_PathCommand.circle);
    } else {
      _send(_PathCommand.ellipse);
      _args.add(rect.height);
    }
  }

  @override
  void cubicTo(PointT c1, PointT c2, PointT p, bool shorthand) {
    if (shorthand) {
      _send(_PathCommand.cubicToShorthand);
    } else {
      _send(_PathCommand.cubicTo);
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
    if (shorthand) {
      _send(_PathCommand.quadraticBezierToShorthand);
    } else {
      _send(_PathCommand.quadraticBezierTo);
      _args.add(control.x);
      _args.add(control.y);
    }
    _args.add(p.x);
    _args.add(p.y);
  }

  @override
  void close() {
    _send(_PathCommand.close);
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
  int seek;
  final List<double> _buf;

  FloatBufferInputStream(this._buf) : seek = 0;

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

  void close() => seek = _buf.length;
}

int _readSmallishInt(ByteBufferDataInputStream str) {
  int r = str.readUnsignedByte();
  if (r < 0xfe) {
    return r;
  } else if (r < 0xff) {
    return str.readUnsignedShort();
  } else {
    return str.readUnsignedInt(); // coverage:ignore-line
  }
}

///
/// Returns number of bytes written
///
int _writeSmallishInt(DataOutputSink out, int v) {
  if (v < 0xfe) {
    out.writeByte(v);
    return 1;
  } else if (v < 0xffff) {
    out.writeByte(0xfe);
    out.writeUnsignedShort(v);
    return 3;
  } else {
    out.writeByte(0xff); // coverage:ignore-line
    out.writeUnsignedInt(v); // coverage:ignore-line
    return 5;
  }
}

int _flag(bool v, int bit) => v ? (1 << bit) : 0;

int _getColorType(SIColor c) {
  int r = -1;
  c.accept(SIColorVisitor(
      value: (_) => r = 0,
      none: () => r = 1,
      current: () => r = 2,
      linearGradient: (_) => r = 3,
      radialGradient: (_) => r = 3,
      sweepGradient: (_) => r = 3));
  assert(r != -1);
  return r;
}
