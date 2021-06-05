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

library jovial_svg.svg_graph;

import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';

import 'package:quiver/core.dart' as quiver;
import 'package:quiver/collection.dart' as quiver;

import 'affine.dart';
import 'common_noui.dart';
import 'path_noui.dart';

class SvgParseGraph {
  final idLookup = <String, SvgNode>{};
  final SvgGroup root;
  final double? width;
  final double? height;

  SvgParseGraph(this.root, this.width, this.height);

  void build(SIBuilder<String> builder) {
    final rootPaint = SvgPaint.initial();
    final rootTA = SvgTextAttributes.initial();
    SvgGroup? newRoot = root.reduce(idLookup, rootPaint, builder.warn);
    builder.vector(
        width: width,
        height: height,
        tintColor: null,
        tintMode: null);
    final theCanon = SvgCanonicalizedData();
    newRoot?.collectCanon(theCanon);
    builder.init(
        null,
        theCanon.toList(theCanon.images),
        theCanon.toList(theCanon.strings),
        theCanon.toList(theCanon.floatLists),
        theCanon.toList(theCanon.transforms));
    newRoot?.build(builder, theCanon, rootPaint, rootTA);
    builder.endVector();
  }
}

class SvgCanonicalizedData {
  final Map<SIImageData, int> images = {};
  final Map<String, int> strings = {};
  final Map<List<double>, int> floatLists = HashMap(
      equals: (List<double> k1, List<double> k2) => quiver.listsEqual(k1, k2),
      hashCode: (List<double> k) => quiver.hashObjects(k));
  final Map<Affine, int> transforms = {};

  int? getIndex<T extends Object>(Map<T, int> map, T? value) {
    if (value == null) {
      return null;
    }
    final len = map.length;
    return map.putIfAbsent(value, () => len);
  }

  List<T> toList<T>(Map<T, int> map) {
    if (map.length == 0) {
      return List<T>.empty();
    }
    T random = map.entries.first.key;
    final r = List<T>.filled(map.length, random);
    for (final MapEntry<T, int> e in map.entries) {
      r[e.value] = e.key;
    }
    return r;
  }
}

abstract class SvgNode {
  SvgNode? reduce(Map<String, SvgNode> idLookup, SvgPaint ancestor, bool warn);

  void build(SIBuilder<String> builder, SvgCanonicalizedData canon,
      SvgPaint ancestor, SvgTextAttributes ta);

  void collectCanon(SvgCanonicalizedData canon);
}

abstract class SvgInheritableAttributes {
  MutableAffine? transform;
  int? transformIndex;
  SvgPaint paint = SvgPaint.empty();
  SvgTextAttributes textAttributes = SvgTextAttributes.empty();

  bool _isInvisible(SvgPaint paint) =>
      (paint.strokeAlpha == 0 || paint.strokeColor == SvgColor.none) &&
      (paint.fillAlpha == 0 || paint.fillColor == SvgColor.none);

  SvgPaint cascadePaint(SvgPaint ancestor) {
    return SvgPaint(
        currentColor: paint.currentColor.orInherit(ancestor.currentColor),
        fillColor: paint.fillColor.orInherit(ancestor.fillColor),
        fillAlpha: paint.fillAlpha ?? ancestor.fillAlpha,
        strokeColor: paint.strokeColor.orInherit(ancestor.strokeColor),
        strokeAlpha: paint.strokeAlpha ?? ancestor.strokeAlpha,
        strokeWidth: paint.strokeWidth ?? ancestor.strokeWidth,
        strokeMiterLimit: paint.strokeMiterLimit ?? ancestor.strokeMiterLimit,
        strokeJoin: paint.strokeJoin ?? ancestor.strokeJoin,
        strokeCap: paint.strokeCap ?? ancestor.strokeCap,
        fillType: paint.fillType ?? ancestor.fillType);
  }

  SvgTextAttributes cascadeText(SvgTextAttributes ancestor) {
    return SvgTextAttributes(
        fontSize: textAttributes.fontSize.orInherit(ancestor.fontSize),
        fontFamily: textAttributes.fontFamily ?? ancestor.fontFamily,
        fontWeight: textAttributes.fontWeight.orInherit(ancestor.fontWeight),
        fontStyle: textAttributes.fontStyle ?? ancestor.fontStyle);
  }
}

class SvgPaint {
  SvgColor currentColor;
  SvgColor fillColor;
  int? fillAlpha;
  SvgColor strokeColor;
  int? strokeAlpha;
  double? strokeWidth;
  double? strokeMiterLimit;
  SIStrokeJoin? strokeJoin;
  SIStrokeCap? strokeCap;
  SIFillType? fillType;

  SvgPaint(
      {required this.currentColor,
      required this.fillColor,
      required this.fillAlpha,
      required this.strokeColor,
      required this.strokeAlpha,
      required this.strokeWidth,
      required this.strokeMiterLimit,
      required this.strokeJoin,
      required this.strokeCap,
      required this.fillType});

  SvgPaint.empty()
      : fillColor = SvgColor.inherit,
        strokeColor = SvgColor.inherit,
        currentColor = SvgColor.inherit;

  factory SvgPaint.initial() => SvgPaint(
      currentColor: SvgColor.currentColor, // Inherit from SVG container
      fillColor: SvgColor.value(0xff000000),
      fillAlpha: 0xff,
      strokeColor: SvgColor.none,
      strokeAlpha: 0xff,
      strokeWidth: 1,
      strokeMiterLimit: 4,
      strokeJoin: SIStrokeJoin.miter,
      strokeCap: SIStrokeCap.butt,
      fillType: SIFillType.nonZero);

  @override
  int get hashCode => quiver.hash4(
      fillColor,
      fillAlpha,
      quiver.hash4(strokeColor, strokeAlpha, strokeWidth, strokeMiterLimit),
      quiver.hash4(currentColor, strokeJoin, strokeCap, fillType));

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    } else if (other is SvgPaint) {
      return currentColor == other.currentColor &&
          fillColor == other.fillColor &&
          fillAlpha == other.fillAlpha &&
          strokeColor == other.strokeColor &&
          strokeAlpha == other.strokeAlpha &&
          strokeWidth == other.strokeWidth &&
          strokeMiterLimit == other.strokeMiterLimit &&
          strokeJoin == other.strokeJoin &&
          fillType == other.fillType;
    } else {
      return false;
    }
  }

  SIPaint toSIPaint() {
    return SIPaint(
        fillColor: fillColor.toSIColor(fillAlpha, currentColor),
        fillColorType: fillColor.toSIColorType(currentColor),
        strokeColor: strokeColor.toSIColor(strokeAlpha, currentColor),
        strokeColorType: strokeColor.toSIColorType(currentColor),
        strokeWidth: strokeWidth,
        strokeMiterLimit: strokeMiterLimit,
        strokeJoin: strokeJoin,
        strokeCap: strokeCap,
        fillType: fillType);
  }
}

class SvgGroup extends SvgInheritableAttributes implements SvgNode {
  var children = List<SvgNode>.empty(growable: true);

  SvgGroup();

  SvgGroup.withTransform(MutableAffine transform) {
    this.transform = transform;
  }

  @override
  SvgGroup? reduce(
      Map<String, SvgNode> idLookup, SvgPaint ancestor, bool warn) {
    if (transform?.determinant() == 0.0) {
      return null;
    }
    SvgPaint curr = cascadePaint(ancestor);
    final newC = List<SvgNode>.empty(growable: true);
    for (SvgNode n in children) {
      final nn = n.reduce(idLookup, curr, warn);
      if (nn != null) {
        newC.add(nn);
      }
    }
    children = newC;
    if (children.isEmpty) {
      return null;
    } else {
      return this;
    }
  }

  @override
  void build(SIBuilder<String> builder, SvgCanonicalizedData canon,
      SvgPaint ancestor, SvgTextAttributes ta) {
    SvgPaint curr = cascadePaint(ancestor);
    final currTA = cascadeText(ta);
    builder.group(null, transformIndex);
    for (final c in children) {
      c.build(builder, canon, curr, currTA);
    }
    builder.endGroup(null);
  }

  @override
  void collectCanon(SvgCanonicalizedData canon) {
    transformIndex = canon.getIndex(canon.transforms, transform);
    for (final ch in children) {
      ch.collectCanon(canon);
    }
  }
}

class SvgDefs extends SvgGroup {
  @override
  SvgGroup? reduce(
          Map<String, SvgNode> idLookup, SvgPaint ancestor, bool warn) =>
      null;

  @override
  void build(SIBuilder<String> builder, SvgCanonicalizedData canon,
      SvgPaint ancestor, SvgTextAttributes ta) {
    assert(false);
  }
}

class SvgUse extends SvgInheritableAttributes implements SvgNode {
  String childID;

  SvgUse(this.childID);

  @override
  SvgNode? reduce(Map<String, SvgNode> idLookup, SvgPaint ancestor, bool warn) {
    if (transform?.determinant() == 0.0) {
      return null;
    }
    SvgNode? n = idLookup[childID];
    if (n == null) {
      print('    <use> references nonexistent $childID');
      return null;
    }
    SvgPaint curr = cascadePaint(ancestor);
    n = n.reduce(idLookup, curr, warn);
    if (n == null) {
      return null;
    }
    if (transform == null && curr == ancestor) {
      return n;
    }
    final g = SvgGroup();
    g.paint = paint;
    g.transform = transform;
    g.children.add(n);
    return g;
  }

  @override
  void collectCanon(SvgCanonicalizedData canon) {
    assert(false);
  }

  @override
  void build(SIBuilder<String> builder, SvgCanonicalizedData canon,
      SvgPaint ancestor, SvgTextAttributes ta) {
    assert(false);
  }
}

abstract class SvgPathMaker extends SvgInheritableAttributes
    implements SvgNode {
  @override
  void collectCanon(SvgCanonicalizedData canon) {
    transformIndex = canon.getIndex(canon.transforms, transform);
  }

  @override
  void build(SIBuilder<String> builder, SvgCanonicalizedData canon,
      SvgPaint ancestor, SvgTextAttributes ta) {
    SvgPaint curr = cascadePaint(ancestor);
    if (transformIndex != null) {
      builder.group(null, transformIndex);
      makePath(builder, curr.toSIPaint());
      builder.endGroup(null);
    } else {
      makePath(builder, curr.toSIPaint());
    }
  }

  void makePath(SIBuilder<String> builder, SIPaint curr);
}

class SvgPath extends SvgPathMaker {
  final String pathData;

  SvgPath(this.pathData);

  @override
  SvgPath? reduce(Map<String, SvgNode> idLookup, SvgPaint ancestor, bool warn) {
    SvgPaint curr = cascadePaint(ancestor);
    if (pathData == '' || _isInvisible(curr)) {
      return null;
    } else {
      return this;
    }
  }

  @override
  void makePath(SIBuilder<String> builder, SIPaint curr) {
    print('@@ path, ${curr.fillColor.toRadixString(16)}');
    builder.path(null, pathData, curr);
  }
}

class SvgRect extends SvgPathMaker {
  final double x;
  final double y;
  final double width;
  final double height;
  final double rx;
  final double ry;

  SvgRect(this.x, this.y, this.width, this.height, this.rx, this.ry);

  @override
  SvgRect? reduce(Map<String, SvgNode> idLookup, SvgPaint ancestor, bool warn) {
    SvgPaint curr = cascadePaint(ancestor);
    if (width <= 0 || height <= 0 || _isInvisible(curr)) {
      return null;
    } else {
      return this;
    }
  }

  @override
  void makePath(SIBuilder<String> builder, SIPaint curr) {
    PathBuilder? pb = builder.startPath(curr, this);
    if (pb == null) {
      return;
    }
    if (rx <= 0 || ry <= 0) {
      pb.moveTo(PointT(x, y));
      pb.lineTo(PointT(x + width, y));
      pb.lineTo(PointT(x + width, y + height));
      pb.lineTo(PointT(x, y + height));
      pb.close();
    } else {
      final r = RadiusT(rx, ry);
      pb.moveTo(PointT(x + rx, y));
      pb.lineTo(PointT(x + width - rx, y));
      pb.arcToPoint(PointT(x + width, y + ry),
          radius: r, rotation: 90, largeArc: false, clockwise: true);
      pb.lineTo(PointT(x + width, y + height - ry));
      pb.arcToPoint(PointT(x + width - rx, y + height),
          radius: r, rotation: 90, largeArc: false, clockwise: true);
      pb.lineTo(PointT(x + rx, y + height));
      pb.arcToPoint(PointT(x, y + height - ry),
          radius: r, rotation: 90, largeArc: false, clockwise: true);
      pb.lineTo(PointT(x, y + ry));
      pb.arcToPoint(PointT(x + rx, y),
          radius: r, rotation: 90, largeArc: false, clockwise: true);
      pb.close();
    }
    pb.end();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    } else if (other is SvgRect) {
      return x == other.x &&
          y == other.y &&
          width == other.width &&
          height == other.height &&
          rx == other.rx &&
          ry == other.ry;
    } else {
      return false;
    }
  }

  @override
  int get hashCode => quiver.hash3(quiver.hash4(x, y, width, height), rx, ry);
}

class SvgEllipse extends SvgPathMaker {
  final double cx;
  final double cy;
  final double rx;
  final double ry;

  SvgEllipse(this.cx, this.cy, this.rx, this.ry);

  @override
  SvgEllipse? reduce(
      Map<String, SvgNode> idLookup, SvgPaint ancestor, bool warn) {
    SvgPaint curr = cascadePaint(ancestor);
    if (rx <= 0 || ry <= 0 || _isInvisible(curr)) {
      return null;
    } else {
      return this;
    }
  }

  @override
  void makePath(SIBuilder<String> builder, SIPaint curr) {
    PathBuilder? pb = builder.startPath(curr, this);
    if (pb == null) {
      return;
    }
    pb.addOval(RectT(cx-rx, cy-ry, 2*rx, 2*ry));
    pb.end();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    } else if (other is SvgEllipse) {
      return cx == other.cx &&
          cy == other.cy &&
          rx == other.rx &&
          ry == other.ry;
    } else {
      return false;
    }
  }

  @override
  int get hashCode => quiver.hash4(cx, cy, rx, ry);
}

class SvgPoly extends SvgPathMaker {
  final bool close; // true makes it a polygon; false a polyline
  final List<Point<double>> points;

  SvgPoly(this.close, this.points);

  @override
  SvgPoly? reduce(Map<String, SvgNode> idLookup, SvgPaint ancestor, bool warn) {
    SvgPaint curr = cascadePaint(ancestor);
    if (points.length < 2 || _isInvisible(curr)) {
      return null;
    } else {
      return this;
    }
  }

  @override
  void makePath(SIBuilder<String> builder, SIPaint curr) {
    PathBuilder? pb = builder.startPath(curr, this);
    if (pb == null) {
      return;
    }
    pb.moveTo(points[0]);
    for (int i = 1; i < points.length; i++) {
      pb.lineTo(points[i]);
    }
    if (close) {
      pb.close();
    }
    pb.end();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    } else if (other is SvgPoly) {
      return close == other.close && quiver.listsEqual(points, other.points);
    } else {
      return false;
    }
  }

  @override
  int get hashCode => quiver.hash2(close, quiver.hashObjects(points));
}

class SvgImage extends SvgInheritableAttributes implements SvgNode {
  AlignmentT? alignment;
  Uint8List imageData = _emptyData;
  double x = 0;
  double y = 0;
  double width = 0;
  double height = 0;
  int _imageNumber = -1;

  SvgImage();

  static final Uint8List _emptyData = Uint8List(0);

  @override
  void collectCanon(SvgCanonicalizedData canon) {
    final sid = SIImageData(
        x: x, y: y, width: width, height: height, encoded: imageData);
    _imageNumber = canon.getIndex(canon.images, sid)!;
    transformIndex = canon.getIndex(canon.transforms, transform);
  }

  @override
  void build(SIBuilder<String> builder, SvgCanonicalizedData canon,
      SvgPaint ancestor, SvgTextAttributes ta) {
    assert(_imageNumber > -1);
    if (transformIndex != null) {
      builder.group(null, transformIndex);
      builder.image(null, _imageNumber);
      builder.endGroup(null);
    } else {
      builder.image(null, _imageNumber);
    }
  }

  @override
  SvgNode? reduce(Map<String, SvgNode> idLookup, SvgPaint ancestor, bool warn) {
    if (width <= 0 || height <= 0) {
      return null;
    }
    return this;
  }
}

class SvgText extends SvgInheritableAttributes implements SvgNode {
  String text = '';
  List<double> x = const [0.0];
  List<double> y = const [0.0];
  int xIndex = -1;
  int yIndex = -1;
  int textIndex = -1;

  SvgText();

  @override
  void build(SIBuilder<String> builder, SvgCanonicalizedData canon,
      SvgPaint ancestor, SvgTextAttributes ta) {
    final currPaint = cascadePaint(ancestor).toSIPaint();
    final currTA = cascadeText(ta).toSITextAttributes();
    if (transformIndex != null) {
      builder.group(null, transformIndex);
      builder.text(null, xIndex, yIndex, textIndex, currTA, currPaint);
      builder.endGroup(null);
    } else {
      builder.text(null, xIndex, yIndex, textIndex, currTA, currPaint);
    }
  }

  @override
  SvgNode? reduce(Map<String, SvgNode> idLookup, SvgPaint ancestor, bool warn) {
    final currPaint = cascadePaint(ancestor);
    if (text == '' ||
        currPaint.fillAlpha == 0 ||
        currPaint.fillColor == SvgColor.none) {
      return null;
    }
    return this;
  }

  @override
  void collectCanon(SvgCanonicalizedData canon) {
    transformIndex = canon.getIndex(canon.transforms, transform);
    xIndex = canon.getIndex(canon.floatLists, x)!;
    yIndex = canon.getIndex(canon.floatLists, y)!;
    textIndex = canon.getIndex(canon.strings, text)!;
  }
}

class SvgTextAttributes {
  String? fontFamily;
  SIFontStyle? fontStyle;
  SvgFontWeight fontWeight = SvgFontWeight.inherit;
  SvgFontSize fontSize = SvgFontSize.inherit;

  SvgTextAttributes.empty();
  SvgTextAttributes(
      {required this.fontFamily,
      required this.fontStyle,
      required this.fontWeight,
      required this.fontSize});

  SvgTextAttributes.initial()
      : fontFamily = '',
        fontStyle = SIFontStyle.normal,
        fontWeight = SvgFontWeight.w400,
        fontSize = SvgFontSize.medium;

  SITextAttributes toSITextAttributes() => SITextAttributes(
      fontFamily: fontFamily!,
      fontStyle: fontStyle!,
      fontWeight: fontWeight.toSI(),
      fontSize: fontSize.toSI());
}

///
/// Font size as SVG knows it.
///
abstract class SvgFontSize {
  const SvgFontSize();

  factory SvgFontSize.absolute(double size) => _SvgFontSizeAbsolute(size);

  static const SvgFontSize inherit = _SvgFontSizeInherit();

  static const SvgFontSize larger = _SvgFontSizeRelative(1.2);

  static const SvgFontSize smaller = _SvgFontSizeRelative(1 / 1.2);

  static const double _med = 12;
  static const SvgFontSize medium = _SvgFontSizeAbsolute(_med);

  static const SvgFontSize small = _SvgFontSizeAbsolute(_med / 1.2);
  static const SvgFontSize x_small = _SvgFontSizeAbsolute(_med / (1.2 * 1.2));
  static const SvgFontSize xx_small =
      _SvgFontSizeAbsolute(_med / (1.2 * 1.2 * 1.2));

  static const SvgFontSize large = _SvgFontSizeAbsolute(_med * 1.2);
  static const SvgFontSize x_large = _SvgFontSizeAbsolute(_med * 1.2 * 1.2);
  static const SvgFontSize xx_large =
      _SvgFontSizeAbsolute(_med * 1.2 * 1.2 * 1.2);

  SvgFontSize orInherit(SvgFontSize ancestor);

  double toSI() {
    assert(false);
    return 12.0;
  }
}

class _SvgFontSizeAbsolute extends SvgFontSize {
  final double size;

  const _SvgFontSizeAbsolute(this.size);

  @override
  SvgFontSize orInherit(SvgFontSize ancestor) => this;

  @override
  double toSI() => size;
}

class _SvgFontSizeRelative extends SvgFontSize {
  final double scale;

  const _SvgFontSizeRelative(this.scale);

  @override
  SvgFontSize orInherit(SvgFontSize ancestor) {
    if (ancestor is _SvgFontSizeAbsolute) {
      return _SvgFontSizeAbsolute(ancestor.size * scale);
    } else {
      assert(false);
      return SvgFontSize.medium;
    }
  }
}

class _SvgFontSizeInherit extends SvgFontSize {
  const _SvgFontSizeInherit();

  @override
  SvgFontSize orInherit(SvgFontSize ancestor) {
    if (ancestor == SvgFontSize.inherit) {
      assert(false);
      return SvgFontSize.medium;
    } else {
      return ancestor;
    }
  }
}

///
/// Color as SVG knows it, plus alpha in the high-order byte (in case we
/// encounter an SVG file with an (invalid) eight-character hex value).
///
abstract class SvgColor {
  const SvgColor();

  ///
  /// Create a normal, explicit color from an 0xaarrggbb value.
  ///
  factory SvgColor.value(int value) => _SvgColorValue(value);

  ///
  /// Create the "inherit" color, which means "inherit from parent"
  ///
  static const SvgColor inherit = _SvgColorInherit._p();

  ///
  /// The "none" color, which means "do not paint"
  ///
  static const SvgColor none = _SvgColorNone._p();

  ///
  /// Create the "currentColor" color, which means "paint with the color given
  /// to the ScalableImage's parent".
  ///
  static const SvgColor currentColor = _SvgColorCurrentColor._p();

  SvgColor orInherit(SvgColor ancestor) => this;

  int toSIColor(int? alpha, SvgColor cascadedCurrentColor);

  SIColorType toSIColorType(SvgColor cascadedCurrentColor);
}

class _SvgColorValue extends SvgColor {
  final int _value;
  const _SvgColorValue(this._value);

  @override
  int toSIColor(int? alpha, SvgColor cascadedCurrentColor) {
    if (alpha == null) {
      return _value;
    } else {
      return (_value & 0xffffff) | (alpha << 24);
    }
  }

  @override
  SIColorType toSIColorType(SvgColor cascadedCurrentColor) => SIColorType.value;
}

class _SvgColorInherit extends SvgColor {
  const _SvgColorInherit._p();

  @override
  SvgColor orInherit(SvgColor ancestor) => ancestor;

  @override
  SIColorType toSIColorType(SvgColor cascadedCurrentColor) =>
      throw StateError('Internal error: color inheritance');

  @override
  int toSIColor(int? alpha, SvgColor cascadedCurrentColor) =>
      throw StateError('Internal error: color inheritance');
}

class _SvgColorNone extends SvgColor {
  const _SvgColorNone._p();

  @override
  SIColorType toSIColorType(SvgColor cascadedCurrentColor) => SIColorType.none;

  @override
  int toSIColor(int? alpha, SvgColor cascadedCurrentColor) => 0;
}

class _SvgColorCurrentColor extends SvgColor {
  const _SvgColorCurrentColor._p();

  @override
  SIColorType toSIColorType(SvgColor cascadedCurrentColor) {
    if (cascadedCurrentColor == SvgColor.currentColor) {
      return SIColorType.currentColor;
    } else {
      return cascadedCurrentColor.toSIColorType(const _SvgColorValue(0));
    }
  }

  @override
  int toSIColor(int? alpha, SvgColor cascadedCurrentColor) =>
      cascadedCurrentColor.toSIColor(alpha, const _SvgColorValue(0));
}

abstract class SvgFontWeight {

  const SvgFontWeight();

  static const SvgFontWeight w100 = _SvgFontWeightAbsolute(SIFontWeight.w100);
  static const SvgFontWeight w200 = _SvgFontWeightAbsolute(SIFontWeight.w200);
  static const SvgFontWeight w300 = _SvgFontWeightAbsolute(SIFontWeight.w300);
  static const SvgFontWeight w400 = _SvgFontWeightAbsolute(SIFontWeight.w400);
  static const SvgFontWeight w500 = _SvgFontWeightAbsolute(SIFontWeight.w500);
  static const SvgFontWeight w600 = _SvgFontWeightAbsolute(SIFontWeight.w600);
  static const SvgFontWeight w700 = _SvgFontWeightAbsolute(SIFontWeight.w700);
  static const SvgFontWeight w800 = _SvgFontWeightAbsolute(SIFontWeight.w800);
  static const SvgFontWeight w900 = _SvgFontWeightAbsolute(SIFontWeight.w900);
  static const SvgFontWeight bolder = _SvgFontWeightBolder();
  static const SvgFontWeight lighter = _SvgFontWeightLighter();
  static const SvgFontWeight inherit = _SvgFontWeightInherit();

  SvgFontWeight orInherit(SvgFontWeight ancestor);
  SIFontWeight toSI();
}

class _SvgFontWeightAbsolute extends SvgFontWeight {
  final SIFontWeight weight;
  const _SvgFontWeightAbsolute(this.weight);

  @override
  SvgFontWeight orInherit(SvgFontWeight ancestor) => this;

  @override
  SIFontWeight toSI() => weight;
}

class _SvgFontWeightBolder extends SvgFontWeight {
  const _SvgFontWeightBolder();

  @override
  SvgFontWeight orInherit(SvgFontWeight ancestor) {
    int i = ancestor.toSI().index;
    return _SvgFontWeightAbsolute(SIFontWeight.values[min(i+1, SIFontWeight.values.length - 1)]);
  }

  @override
  SIFontWeight toSI() {
    assert(false);
    return SIFontWeight.w400;
  }
}

class _SvgFontWeightLighter extends SvgFontWeight {
  const _SvgFontWeightLighter();

  @override
  SvgFontWeight orInherit(SvgFontWeight ancestor) {
    int i = ancestor.toSI().index;
    return _SvgFontWeightAbsolute(SIFontWeight.values[max(i-1, 0)]);
  }

  @override
  SIFontWeight toSI() {
    assert(false);
    return SIFontWeight.w400;
  }
}

class _SvgFontWeightInherit extends SvgFontWeight {
  const _SvgFontWeightInherit();

  @override
  SvgFontWeight orInherit(SvgFontWeight ancestor) => ancestor;

  @override
  SIFontWeight toSI() {
    assert(false);
    return SIFontWeight.w400;
  }
}
