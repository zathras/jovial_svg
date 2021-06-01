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

part of jovial_svg.svg_parser;

class SvgParseGraph extends SvgTransformer {
  final double? width;
  final double? height;

  final idLookup = <String, SvgNode>{};
  final SvgGroup root;

  SvgParseGraph(this.width, this.height, this.root);

  void build(SIBuilder<String> builder) {
    final rootPaint = SvgPaint.initial();
    SvgGroup? newRoot = root.reduce(idLookup, rootPaint);
    builder.vector(
        width: width, height: height, tintColor: null, tintMode: null);
    newRoot?.build(builder, rootPaint);
    builder.endVector();
  }
}

abstract class SvgNode {
  SvgNode? reduce(Map<String, SvgNode> idLookup, SvgPaint ancestor);

  void build(SIBuilder<String> builder, SvgPaint ancestor);
}

abstract class SvgParentNode extends SvgNode {
  List<SvgNode> get children;
}

abstract class SvgTransformer {
  MutableAffine? transform;
  SvgPaint paint = SvgPaint.empty();

  SvgPaint cascadePaint(SvgPaint ancestor) {
    return SvgPaint(
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
}

class SvgPaint {
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
      {required this.fillColor,
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
        strokeColor = SvgColor.inherit;

  factory SvgPaint.initial() => SvgPaint(
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
      quiver.hash3(strokeJoin, strokeCap, fillType));

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    } else if (other is SvgPaint) {
      return fillColor == other.fillColor &&
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

  SIPaint toSIPaint() => SIPaint(
      fillColor: fillColor.toSIColor(fillAlpha),
      fillColorType: fillColor.siColorType,
      strokeColor: strokeColor.toSIColor(strokeAlpha),
      strokeColorType: strokeColor.siColorType,
      strokeWidth: strokeWidth,
      strokeMiterLimit: strokeMiterLimit,
      strokeJoin: strokeJoin,
      strokeCap: strokeCap,
      fillType: fillType);
}

class SvgGroup extends SvgTransformer implements SvgParentNode {
  @override
  var children = List<SvgNode>.empty(growable: true);

  SvgGroup();

  @override
  SvgGroup? reduce(Map<String, SvgNode> idLookup, SvgPaint ancestor) {
    if (transform?.determinant() == 0.0) {
      return null;
    }
    SvgPaint curr = cascadePaint(ancestor);
    final newC = List<SvgNode>.empty(growable: true);
    for (SvgNode n in children) {
      final nn = n.reduce(idLookup, curr);
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
  void build(SIBuilder<String> builder, SvgPaint ancestor) {
    SvgPaint curr = cascadePaint(ancestor);
    builder.group(null, transform);
    for (final c in children) {
      c.build(builder, curr);
    }
    builder.endGroup(null);
  }
}

class SvgUse extends SvgTransformer implements SvgNode {
  String childID;

  SvgUse(this.childID);

  @override
  SvgNode? reduce(Map<String, SvgNode> idLookup, SvgPaint ancestor) {
    if (transform?.determinant() == 0.0) {
      return null;
    }
    SvgNode? n = idLookup[childID];
    if (n == null) {
      print('Warning: <use> references nonexistent $childID');
      return null;
    }
    SvgPaint curr = cascadePaint(ancestor);
    n = n.reduce(idLookup, curr);
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
  void build(SIBuilder<String> builder, SvgPaint ancestor) {
    assert(false);
  }
}

abstract class SvgPathMaker extends SvgTransformer implements SvgNode {
  bool _isInvisible(SvgPaint paint) =>
      (paint.strokeAlpha == 0 || paint.strokeColor == SvgColor.none) &&
      (paint.fillAlpha == 0 || paint.fillColor == SvgColor.none);

  @override
  void build(SIBuilder<String> builder, SvgPaint ancestor) {
    SvgPaint curr = cascadePaint(ancestor);
    if (transform != null) {
      builder.group(null, transform);
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
  SvgPath? reduce(Map<String, SvgNode> idLookup, SvgPaint ancestor) {
    SvgPaint curr = cascadePaint(ancestor);
    if (pathData == '' || _isInvisible(curr)) {
      return null;
    } else {
      return this;
    }
  }

  @override
  void makePath(SIBuilder<String> builder, SIPaint curr) {
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
  SvgRect? reduce(Map<String, SvgNode> idLookup, SvgPaint ancestor) {
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
  SvgEllipse? reduce(Map<String, SvgNode> idLookup, SvgPaint ancestor) {
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
    final start = PointT(cx - rx, cy - ry);
    pb.moveTo(start);
    pb.arcToPoint(start,
        radius: RadiusT(rx, ry),
        rotation: 360,
        largeArc: true,
        clockwise: true);
    pb.close();
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
  SvgPoly? reduce(Map<String, SvgNode> idLookup, SvgPaint ancestor) {
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

  SvgColor orInherit(SvgColor ancestor) {
    assert(!(ancestor is _SvgColorInherit));
    return this;
  }

  int toSIColor(int? alpha) {
    return 0;
  }

  SIColorType get siColorType;
}

class _SvgColorValue extends SvgColor {
  final int _value;
  _SvgColorValue(this._value);

  @override
  int toSIColor(int? alpha) {
    if (alpha == null) {
      return _value;
    } else {
      return (_value & 0xffffff) | (alpha << 24);
    }
  }

  @override
  SIColorType get siColorType => SIColorType.value;
}

class _SvgColorInherit extends SvgColor {
  const _SvgColorInherit._p();

  @override
  SvgColor orInherit(SvgColor ancestor) {
    assert(!(ancestor is _SvgColorInherit));
    return ancestor;
  }

  @override
  SIColorType get siColorType =>
      throw StateError('Internal error: color inheritance');
}

class _SvgColorNone extends SvgColor {
  const _SvgColorNone._p();

  @override
  SIColorType get siColorType => SIColorType.none;
}

class _SvgColorCurrentColor extends SvgColor {
  const _SvgColorCurrentColor._p();

  @override
  SIColorType get siColorType => SIColorType.currentColor;
}
