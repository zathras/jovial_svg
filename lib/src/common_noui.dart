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
/// Utilities that are common between DAG and Compact
/// scalable image implementations.
///
library jovial_svg.common_noui;

import 'dart:math';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'affine.dart';
import 'path_noui.dart';

typedef PointT = Point<double>;
typedef RadiusT = Point<double>;
typedef RectT = Rectangle<double>;

///
/// Visit the elements of a scalable image.  This interface is used to
/// build an SI representation, and to traverse the compact binary format.
/// See ../../doc/internals.html for a discussion of the design.
///
abstract class SIVisitor<PathDataT, IM, R> {
  R get initial;

  ///
  /// Called first on a traversal, this establishes immutable values that
  /// are canonicalized.  floatValueMap may be null, because it is sometimes
  /// provided before init is called.
  ///
  R init(
      R collector,
      List<IM> im,
      List<String> strings,
      List<List<double>> floatLists,
      List<List<String>> stringLists,
      List<double> floatValues,
      CMap<double>? floatValueMap);

  R path(R collector, PathDataT pathData, SIPaint paint);

  R group(R collector, Affine? transform, int? groupAlpha, SIBlendMode blend);

  R endGroup(R collector);

  R clipPath(R collector, PathDataT pathData);

  R masked(R collector, RectT? maskBounds, bool usesLuma);

  R maskedChild(R collector);

  R endMasked(R collector);

  R image(R collector, int imageIndex);

  R legacyText(R collector, int xIndex, int yIndex, int textIndex,
      SITextAttributes a, int? fontFamilyIndex, SIPaint paint);

  R text(R collector);

  R textSpan(
      R collector,
      int dxIndex,
      int dyIndex,
      int textIndex,
      SITextAttributes attributes,
      int? fontFamilyIndex,
      int fontSizeIndex,
      SIPaint paint);

  R textMultiSpanChunk(
      R collector, int dxIndex, int dyIndex, SITextAnchor anchor);

  R textEnd(R collector);

  /// Called with the id of a node, right before the call for the
  /// node's body
  R exportedID(R collector, int idIndex);

  /// Called after the child of the exportedId node
  R endExportedID(R collector);

  /// Check any invariants that should be true at the end of a traversal
  void traversalDone() {}
}

abstract class SIBuilder<PathDataT, IM> extends SIVisitor<PathDataT, IM, void> {
  void Function(String) get warn;

  ///
  /// Called once, at the beginning of reading a file.
  ///
  void vector(
      {required double? width,
      required double? height,
      required int? tintColor,
      required SITintMode? tintMode});

  void endVector();

  ///
  /// The path data or other object in [key] is used to canonicalize paths.
  /// If the path data identified by [key] has been seen before, this method
  /// will return null, and the scalable image will re-use the previously
  /// built, equivalent path.
  ///
  EnhancedPathBuilder? startPath(SIPaint paint, Object key);

  ///
  /// Add a path from an SvgCustomPath.  This is unreachable from a compact
  /// SI.
  ///
  void addPath(Object path, SIPaint paint);
}

class SIImageData {
  final double x;
  final double y;
  final double width;
  final double height;
  final Uint8List encoded;

  SIImageData(
      {required this.x,
      required this.y,
      required this.width,
      required this.height,
      required this.encoded});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    } else if (other is SIImageData) {
      return x == other.x &&
          y == other.y &&
          width == other.width &&
          height == other.height &&
          encoded.equals(other.encoded);
    } else {
      return false;
    }
  }

  @override
  int get hashCode =>
      0x88d32bbf ^ Object.hash(x, y, width, height, Object.hashAll(encoded));
}

class SIPaint {
  final SIColor fillColor;
  final SIColor strokeColor;
  final double strokeWidth;
  final double strokeMiterLimit;
  final SIStrokeJoin strokeJoin;
  final SIStrokeCap strokeCap;
  final SIFillType fillType;
  final List<double>? strokeDashArray;
  final double? strokeDashOffset;

  const SIPaint(
      {required this.fillColor,
      required this.strokeColor,
      required this.strokeWidth,
      required this.strokeMiterLimit,
      required this.strokeJoin,
      required this.strokeCap,
      required this.fillType,
      required this.strokeDashArray,
      required this.strokeDashOffset});

  static const double strokeMiterLimitDefault = 4;
  static const double strokeWidthDefault = 1;

  @override
  int get hashCode =>
      0x5ed55563 ^
      Object.hash(
          fillColor,
          strokeColor,
          strokeWidth,
          strokeMiterLimit,
          strokeJoin,
          strokeCap,
          fillType,
          strokeDashOffset,
          Object.hashAll(strokeDashArray ?? const <double>[]));

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    } else if (other is SIPaint) {
      return fillColor == other.fillColor &&
          strokeColor == other.strokeColor &&
          strokeWidth == other.strokeWidth &&
          strokeMiterLimit == other.strokeMiterLimit &&
          strokeJoin == other.strokeJoin &&
          strokeCap == other.strokeCap &&
          fillType == other.fillType &&
          (const ListEquality<double>())
              .equals(strokeDashArray, other.strokeDashArray) &&
          strokeDashOffset == other.strokeDashOffset;
    } else {
      return false;
    }
  }

  // Can painting with this paint result in a luma value other than
  // pure white?  This is ultimately used for masks -- see
  // SIMaskedHelper.startLumaMask
  bool get canUseLuma =>
      (strokeWidth > 0 && strokeColor.canUseLuma) || fillColor.canUseLuma;
}

@immutable
abstract class SIColor {
  const SIColor();

  static const none = SINoneColor._p();
  static const currentColor = SICurrentColor._p();
  static const white = SIValueColor(0xffffffff);

  void accept(SIColorVisitor v);

  bool get canUseLuma;
}

class SINoneColor extends SIColor {
  const SINoneColor._p();

  @override
  void accept(SIColorVisitor v) => v.none();

  @override
  bool get canUseLuma => false;
}

class SICurrentColor extends SIColor {
  const SICurrentColor._p();

  @override
  void accept(SIColorVisitor v) => v.current();

  @override
  bool get canUseLuma => true;
}

class SIValueColor extends SIColor {
  final int argb;

  const SIValueColor(this.argb);

  @override
  void accept(SIColorVisitor v) => v.value(this);

  @override
  bool get canUseLuma => argb & 0xffffff != 0xffffff;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    } else if (other is SIValueColor) {
      return argb == other.argb;
    } else {
      return false;
    }
  }

  @override
  int get hashCode => argb.hashCode ^ 0x94d38975;

  @override
  String toString() =>
      'SIValueColor(#${argb.toRadixString(16).padLeft(6, "0")})';
}

///
/// Possible spread methods for a color gradient. See
/// https://www.w3.org/TR/2008/REC-SVGTiny12-20081222/painting.html#Gradients .
///
/// {@category SVG DOM}
///
enum SIGradientSpreadMethod { pad, reflect, repeat }

abstract class SIGradientColor extends SIColor {
  final List<SIColor> colors;
  final List<double> stops;
  final bool objectBoundingBox;
  final SIGradientSpreadMethod spreadMethod;
  final Affine? transform;

  SIGradientColor(this.colors, this.stops, this.objectBoundingBox,
      this.spreadMethod, this.transform) {
    assert(colors.length == stops.length);
  }

  @override
  bool get canUseLuma {
    for (final c in colors) {
      if (c.canUseLuma) {
        return true;
      }
    }
    return false;
  }
}

class SILinearGradientColor extends SIGradientColor {
  final double x1;
  final double y1;
  final double x2;
  final double y2;

  SILinearGradientColor(
      {required this.x1,
      required this.y1,
      required this.x2,
      required this.y2,
      required List<SIColor> colors,
      required List<double> stops,
      required bool objectBoundingBox,
      required SIGradientSpreadMethod spreadMethod,
      required Affine? transform})
      : super(colors, stops, objectBoundingBox, spreadMethod, transform);

  @override
  void accept(SIColorVisitor v) => v.linearGradient(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    } else if (other is SILinearGradientColor) {
      return x1 == other.x1 &&
          y1 == other.y1 &&
          x2 == other.x2 &&
          y2 == other.y2 &&
          spreadMethod == other.spreadMethod &&
          transform == other.transform &&
          colors.equals(other.colors) &&
          stops.equals(other.stops) &&
          objectBoundingBox == other.objectBoundingBox;
    } else {
      return false;
    }
  }

  @override
  int get hashCode =>
      0x11830c9f ^
      Object.hash(x1, y1, x2, y2, Object.hashAll(colors), Object.hashAll(stops),
          spreadMethod, transform, objectBoundingBox);
}

class SIRadialGradientColor extends SIGradientColor {
  final double cx;
  final double cy;
  final double fx;
  final double fy;
  final double r;

  SIRadialGradientColor(
      {required this.cx,
      required this.cy,
      required this.fx,
      required this.fy,
      required this.r,
      required List<SIColor> colors,
      required List<double> stops,
      required bool objectBoundingBox,
      required SIGradientSpreadMethod spreadMethod,
      required Affine? transform})
      : super(colors, stops, objectBoundingBox, spreadMethod, transform);

  @override
  void accept(SIColorVisitor v) => v.radialGradient(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    } else if (other is SIRadialGradientColor) {
      return cx == other.cx &&
          cy == other.cy &&
          r == other.r &&
          spreadMethod == other.spreadMethod &&
          transform == other.transform &&
          colors.equals(other.colors) &&
          stops.equals(other.stops) &&
          objectBoundingBox == other.objectBoundingBox;
    } else {
      return false;
    }
  }

  @override
  int get hashCode =>
      0x2b22739d ^
      Object.hash(cx, cy, r, Object.hashAll(colors), Object.hashAll(stops),
          spreadMethod, transform, objectBoundingBox);
}

class SISweepGradientColor extends SIGradientColor {
  final double cx;
  final double cy;
  final double startAngle;
  final double endAngle;

  SISweepGradientColor(
      {required this.cx,
      required this.cy,
      required this.startAngle,
      required this.endAngle,
      required List<SIColor> colors,
      required List<double> stops,
      required bool objectBoundingBox,
      required SIGradientSpreadMethod spreadMethod,
      required Affine? transform})
      : super(colors, stops, objectBoundingBox, spreadMethod, transform);

  @override
  void accept(SIColorVisitor v) => v.sweepGradient(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    } else if (other is SISweepGradientColor) {
      return cx == other.cx &&
          cy == other.cy &&
          startAngle == other.startAngle &&
          endAngle == other.endAngle &&
          spreadMethod == other.spreadMethod &&
          transform == other.transform &&
          colors.equals(other.colors) &&
          stops.equals(other.stops) &&
          objectBoundingBox == other.objectBoundingBox;
    } else {
      return false;
    }
  }

  @override
  int get hashCode =>
      0x5ccb43d2 ^
      Object.hash(cx, cy, startAngle, endAngle, Object.hashAll(colors),
          Object.hashAll(stops), spreadMethod, transform, objectBoundingBox);
}

class SIColorVisitor {
  final void Function(SIValueColor c) value;
  final void Function() none;
  final void Function() current;
  final void Function(SILinearGradientColor c) linearGradient;
  final void Function(SIRadialGradientColor c) radialGradient;
  final void Function(SISweepGradientColor c) sweepGradient;

  const SIColorVisitor(
      {required this.value,
      required this.none,
      required this.current,
      required this.linearGradient,
      required this.radialGradient,
      required this.sweepGradient});
}

///
/// Mixin for SIBuilder that builds paths from strings
///
mixin SIStringPathMaker {
  void makePath(String pathData, EnhancedPathBuilder pb,
      {required void Function(String) warn}) {
    try {
      RealPathParser(pb, pathData).parse();
    } catch (e) {
      warn(e.toString());
      // As per the SVG spec, paths shall be parsed up to the first error,
      // and it is recommended that errors be reported to the user if
      // posible.
    }
  }

  String immutableKey(String key) => key;
}

abstract class GenericParser {
  void Function(String) get warn;

  /// Tiny s. 11.13.1 only requires the sixteen colors from HTML 4, but this
  /// is a more complete list from CSS, since it's easy to do.  Note that
  /// 'currentcolor' gets special handling in svg_parser.dart.
  static const _namedColors = {
    'currentcolor': 0xff000000,
    'aqua': 0xFF00FFFF,
    'black': 0xFF000000,
    'blue': 0xFF0000FF,
    'fuchsia': 0xFFFF00FF,
    'gray': 0xFF808080,
    'grey': 0xFF808080,
    'green': 0xFF008000,
    'lime': 0xFF00FF00,
    'maroon': 0xFF800000,
    'navy': 0xFF000080,
    'olive': 0xFF808000,
    'purple': 0xFF800080,
    'red': 0xFFFF0000,
    'silver': 0xFFC0C0C0,
    'teal': 0xFF008080,
    'white': 0xFFFFFFFF,
    'yellow': 0xFFFFFF00,
    'aliceblue': 0xFFF0F8FF,
    'antiquewhite': 0xFFFAEBD7,
    'aquamarine': 0xFF7FFFD4,
    'azure': 0xFFF0FFFF,
    'beige': 0xFFF5F5DC,
    'bisque': 0xFFFFE4C4,
    'blanchedalmond': 0xFFFFEBCD,
    'blueviolet': 0xFF8A2BE2,
    'brown': 0xFFA52A2A,
    'burlywood': 0xFFDEB887,
    'cadetblue': 0xFF5F9EA0,
    'chartreuse': 0xFF7FFF00,
    'chocolate': 0xFFD2691E,
    'coral': 0xFFFF7F50,
    'cornflowerblue': 0xFF6495ED,
    'cornsilk': 0xFFFFF8DC,
    'crimson': 0xFFDC143C,
    'cyan': 0xFF00FFFF,
    'darkblue': 0xFF00008B,
    'darkcyan': 0xFF008B8B,
    'darkgoldenrod': 0xFFB8860B,
    'darkgray': 0xFFA9A9A9,
    'darkgrey': 0xFFA9A9A9,
    'darkgreen': 0xFF006400,
    'darkkhaki': 0xFFBDB76B,
    'darkmagenta': 0xFF8B008B,
    'darkolivegreen': 0xFF556B2F,
    'darkorange': 0xFFFF8C00,
    'darkorchid': 0xFF9932CC,
    'darkred': 0xFF8B0000,
    'darksalmon': 0xFFE9967A,
    'darkseagreen': 0xFF8FBC8F,
    'darkslateblue': 0xFF483D8B,
    'darkslategray': 0xFF2F4F4F,
    'darkslategrey': 0xFF2F4F4F,
    'darkturquoise': 0xFF00CED1,
    'darkviolet': 0xFF9400D3,
    'deeppink': 0xFFFF1493,
    'deepskyblue': 0xFF00BFFF,
    'dimgray': 0xFF696969,
    'dimgrey': 0xFF696969,
    'dodgerblue': 0xFF1E90FF,
    'firebrick': 0xFFB22222,
    'floralwhite': 0xFFFFFAF0,
    'forestgreen': 0xFF228B22,
    'gainsboro': 0xFFDCDCDC,
    'ghostwhite': 0xFFF8F8FF,
    'gold': 0xFFFFD700,
    'goldenrod': 0xFFDAA520,
    'greenyellow': 0xFFADFF2F,
    'honeydew': 0xFFF0FFF0,
    'hotpink': 0xFFFF69B4,
    'indianred': 0xFFCD5C5C,
    'indigo': 0xFF4B0082,
    'ivory': 0xFFFFFFF0,
    'khaki': 0xFFF0E68C,
    'lavender': 0xFFE6E6FA,
    'lavenderblush': 0xFFFFF0F5,
    'lawngreen': 0xFF7CFC00,
    'lemonchiffon': 0xFFFFFACD,
    'lightblue': 0xFFADD8E6,
    'lightcoral': 0xFFF08080,
    'lightcyan': 0xFFE0FFFF,
    'lightgoldenrodyellow': 0xFFFAFAD2,
    'lightgreen': 0xFF90EE90,
    'lightgrey': 0xFFD3D3D3,
    'lightgray': 0xFFD3D3D3,
    'lightpink': 0xFFFFB6C1,
    'lightsalmon': 0xFFFFA07A,
    'lightseagreen': 0xFF20B2AA,
    'lightskyblue': 0xFF87CEFA,
    'lightslategray': 0xFF778899,
    'lightslategrey': 0xFF778899,
    'lightsteelblue': 0xFFB0C4DE,
    'lightyellow': 0xFFFFFFE0,
    'limegreen': 0xFF32CD32,
    'linen': 0xFFFAF0E6,
    'magenta': 0xFFFF00FF,
    'mediumaquamarine': 0xFF66CDAA,
    'mediumblue': 0xFF0000CD,
    'mediumorchid': 0xFFBA55D3,
    'mediumpurple': 0xFF9370DB,
    'mediumseagreen': 0xFF3CB371,
    'mediumslateblue': 0xFF7B68EE,
    'mediumspringgreen': 0xFF00FA9A,
    'mediumturquoise': 0xFF48D1CC,
    'mediumvioletred': 0xFFC71585,
    'midnightblue': 0xFF191970,
    'mintcream': 0xFFF5FFFA,
    'mistyrose': 0xFFFFE4E1,
    'moccasin': 0xFFFFE4B5,
    'navajowhite': 0xFFFFDEAD,
    'navyblue': 0xFF9FAFDF,
    'oldlace': 0xFFFDF5E6,
    'olivedrab': 0xFF6B8E23,
    'orange': 0xFFFFA500,
    'orangered': 0xFFFF4500,
    'orchid': 0xFFDA70D6,
    'palegoldenrod': 0xFFEEE8AA,
    'palegreen': 0xFF98FB98,
    'paleturquoise': 0xFFAFEEEE,
    'palevioletred': 0xFFDB7093,
    'papayawhip': 0xFFFFEFD5,
    'peachpuff': 0xFFFFDAB9,
    'peru': 0xFFCD853F,
    'pink': 0xFFFFC0CB,
    'plum': 0xFFDDA0DD,
    'powderblue': 0xFFB0E0E6,
    'rosybrown': 0xFFBC8F8F,
    'royalblue': 0xFF4169E1,
    'saddlebrown': 0xFF8B4513,
    'salmon': 0xFFFA8072,
    'sandybrown': 0xFFFA8072,
    'seagreen': 0xFF2E8B57,
    'seashell': 0xFFFFF5EE,
    'sienna': 0xFFA0522D,
    'skyblue': 0xFF87CEEB,
    'slateblue': 0xFF6A5ACD,
    'slategray': 0xFF708090,
    'slategrey': 0xFF708090,
    'snow': 0xFFFFFAFA,
    'springgreen': 0xFF00FF7F,
    'steelblue': 0xFF4682B4,
    'tan': 0xFFD2B48C,
    'thistle': 0xFFD8BFD8,
    'tomato': 0xFFFF6347,
    'turquoise': 0xFF40E0D0,
    'violet': 0xFFEE82EE,
    'wheat': 0xFFF5DEB3,
    'whitesmoke': 0xFFF5F5F5,
    'yellowgreen': 0xFF9ACD33,
  };

  int? getColor(String s) {
    if (s.startsWith('#')) {
      if (s.length == 4) {
        final int v = int.parse(s.substring(1), radix: 16);
        return 0xff000000 |
            ((v & 0xf00) << 12) |
            ((v & 0xf00)) << 8 |
            ((v & 0x0f0) << 8) |
            ((v & 0x0f0) << 4) |
            ((v & 0x00f) << 4) |
            ((v & 0x00f));
      } else if (s.length == 7) {
        return 0xff000000 | int.parse(s.substring(1), radix: 16);
      } else if (s.length == 9) {
        // I don't think SVG/AVD files have this, but it doesn't hurt.
        return int.parse(s.substring(1), radix: 16);
      }
      warn('Color is not #rgb #rrggbb or #aarrggbb:  $s');
      return null;
    }
    if (s.startsWith('rgba') && s.endsWith(')')) {
      final lex = BnfLexer(s.substring(5, s.length - 1));
      final rgb = lex.getList(_colorComponentMatch);
      if (rgb.length != 4) {
        warn('Invalid rgba() syntax: $s');
        return null;
      }
      final int alpha;
      try {
        alpha = (double.parse(rgb[3]) * 255).toInt().clamp(0, 255);
      } catch (e) {
        warn("Bad float value in in color's alpha:  $s");
        return null;
      }
      return alpha << 24 |
          _getColorComponent(rgb[0]) << 16 |
          _getColorComponent(rgb[1]) << 8 |
          _getColorComponent(rgb[2]);
    } else if (s.startsWith('rgb') && s.endsWith(')')) {
      final lex = BnfLexer(s.substring(4, s.length - 1));
      final rgb = lex.getList(_colorComponentMatch);
      if (rgb.length != 3) {
        warn('Invalid rgb() syntax: $s');
        return null;
      }
      return 0xff000000 |
          _getColorComponent(rgb[0]) << 16 |
          _getColorComponent(rgb[1]) << 8 |
          _getColorComponent(rgb[2]);
    }
    final nc = _namedColors[s];
    if (nc != null) {
      return nc;
    }
    warn('Unrecognized color "$s"');
    return 0xFF000000;
  }

  static final _colorComponentMatch = RegExp(r'[0-9.]+%?');

  int _getColorComponent(String s) {
    if (s.endsWith('%')) {
      final pc = double.parse(s.substring(0, s.length - 1)) / 100;
      return ((256 * pc).floor()).clamp(0, 255);
    } else {
      return int.parse(s).clamp(0, 255);
    }
  }

  static final _fillTypeValues = {
    'evenodd': SIFillType.evenOdd,
    'nonzero': SIFillType.nonZero
  };

  SIFillType? getFillType(String? s) {
    if (s == null || s == 'inherit') {
      return null;
    }
    final r = _fillTypeValues[s.toLowerCase().trim()];
    if (r == null) {
      if (s == 'inherit') {
        return null;
      }
      warn('Invalid fill type value:  $s');
    }
    return r;
  }

  final warnedAbout = {'px', ''};

  double? getFloat(String? s, {double Function(double)? percent}) {
    if (s == null || s == 'inherit') {
      return null;
    }
    final lex = BnfLexer(s);
    double? val = lex.tryNextFloat();
    if (val == null) {
      warn('Expected float value, saw "$s".');
      return null;
    } else {
      lex.skipWhitespace();
      String postfix = lex.getRemaining();
      if (postfix == '%' && percent != null) {
        val = percent(val);
      } else if (postfix != '') {
        if (!warnedAbout.contains(postfix)) {
          warnedAbout.add(postfix);
          warn('    (ignoring units "$postfix")');
        }
      }
      return val;
    }
  }

  Rectangle<double>? getViewbox(String? s) {
    if (s == null || s.toLowerCase() == 'none') {
      return null;
    }
    final lex = BnfLexer(s);
    final x = lex.tryNextFloat();
    final y = lex.tryNextFloat();
    final w = lex.tryNextFloat();
    final h = lex.tryNextFloat();
    if (x == null || y == null || w == null || h == null) {
      return null;
    } else {
      return Rectangle(x, y, w, h);
    }
  }

  List<double>? getFloatList(String? s, {double Function(double)? percent}) {
    if (s == null) {
      return null;
    } else if (s.toLowerCase() == 'none') {
      return [];
    }
    final lex = BnfLexer(s);
    final r = List<double>.empty(growable: true);
    for (;;) {
      var d = lex.tryNextFloat();
      if (d == null) {
        break;
      }
      if (percent != null && lex.tryNextMatch('%') != null) {
        d = percent(d);
      }
      r.add(d);
    }
    return r;
  }

  static final _commaSeparation = RegExp(r'\s*,\s*');
  List<String>? getStringList(String? s) {
    if (s == null) {
      return null;
    } else {
      return s.split(_commaSeparation);
    }
  }

  int? getAlpha(String? s) {
    double? opacity = getFloat(s);
    if (opacity == null) {
      return null;
    } else {
      return (opacity.clamp(0, 1) * 255).round();
    }
  }

  static final _strokeJoinValues = {
    'miter': SIStrokeJoin.miter,
    'round': SIStrokeJoin.round,
    'bevel': SIStrokeJoin.bevel,
  };

  SIStrokeJoin? getStrokeJoin(String? s) {
    if (s == null || s == 'inherit') {
      return null;
    }
    final r = _strokeJoinValues[s];
    if (r == null) {
      throw ParseError('Invalid stroke join value:  $s');
    }
    return r;
  }

  static final _strokeCapValues = {
    'butt': SIStrokeCap.butt,
    'round': SIStrokeCap.round,
    'square': SIStrokeCap.square,
  };

  SIStrokeCap? getStrokeCap(String? s) {
    if (s == null || s == 'inherit') {
      return null;
    }
    final r = _strokeCapValues[s];
    if (r == null) {
      throw ParseError('Invalid stroke cap value:  $s');
    }
    return r;
  }
}

///
/// A simple lexer for the Path syntax, and other SVG BNF grammars.  See
/// http://www.w3.org/TR/2008/REC-SVGTiny12-20081222/
///
class BnfLexer {
  final String source;
  int _pos = 0;

  BnfLexer(this.source);

  // Zero or more characters of whitespace, or commas.  This is a little
  // overly permissive, in that it skips stray commas
  static final _wsMatch = RegExp(r'[\s,]*');

  // A flag value
  static final _flagMatch = RegExp(r'(0|1)');

  // A float value:  At least one digit, either before or after the (optional)
  // decimal point.  Note that the EBNF grammar at
  // https://www.w3.org/TR/2018/CR-SVG2-20181004/paths.html
  // section 9.3.9 has issues:  It doesn't mention decimal points at all, or
  // scientific notation.  Both are accepted (at least by Firefox).
  // https://github.com/w3c/svgwg/issues/851
  static final _floatMatch = RegExp(r'[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?');

  ///
  /// Get the next character, and advance.  It's an error if we're at EOF.
  ///
  String getNextChar() {
    if (eof) {
      error('Unexpected EOF');
    }
    final r = source.substring(_pos, _pos + 1);
    _pos++;
    return r;
  }

  // Throw a ParseError with a helpful message, including a pointer
  // to where we are in the source string
  void error(String message) {
    String segment = source;
    int pos = _pos;
    if (pos > 30) {
      segment = '...${segment.substring(pos - 30)}';
      pos = 33;
    }
    if (segment.length > 67) {
      segment = '${segment.substring(0, 64)}...';
    }
    final String caret = '^'.padLeft(pos + 1);
    throw ParseError(
        '$message at character position $_pos\n$segment\n$caret        ');
  }

  bool get eof => _pos == source.length;

  /// Get the next path command.  It might not be a valid command.
  String nextPathCommand() {
    assert(!eof);
    // It's just the next character.  No reason to get fancier than
    // this.
    final start = _pos++;
    final r = source.substring(start, _pos);
    return r;
  }

  ///
  /// Return the next string that matches [matcher], or null if there is none.
  ///
  String? tryNextMatch(Pattern matcher) {
    skipWhitespace();
    final Match? m = matcher.matchAsPrefix(source, _pos);
    if (m == null) {
      return null;
    } else {
      _pos = m.end;
      return source.substring(m.start, m.end);
    }
  }

  ///
  /// Return the next float in the input, or null if there isn't one.
  ///
  double? tryNextFloat() {
    skipWhitespace();
    final sf = tryNextMatch(_floatMatch);
    if (sf == null) {
      return null;
    } else {
      skipWhitespace();
      final double multiplier;
      if (_pos + 2 > source.length) {
        multiplier = 1.0;
      } else {
        final units = source.substring(_pos, _pos + 2).toLowerCase();
        if (units == 'cm') {
          multiplier = 96.0 / 2.54;
          // 96 dpi is as good as anything else.  This isn't terribly
          // important - see Tiny 7.11
          _pos += 2;
        } else if (units == 'mm') {
          multiplier = 96.0 / 25.4;
          _pos += 2;
        } else if (units == 'in') {
          multiplier = 96.0;
          _pos += 2;
        } else if (units == 'em') {
          multiplier = 16.0;
          _pos += 2;
        } else {
          multiplier = 1.0;
        }
      }
      return multiplier * double.parse(sf);
    }
  }

  ///
  /// Return the next float, or fail with a [ParseError] if there isn't one.
  ///
  double nextFloat() {
    final r = tryNextFloat();
    if (r != null) {
      return r;
    } else {
      error('float expected');
      return 0; // not reached
    }
  }

  ///
  /// Return the next flag in the input, or null if there isn't one.
  ///
  bool? tryNextFlag() {
    skipWhitespace();
    final sf = tryNextMatch(_flagMatch);
    if (sf == null) {
      return null;
    } else {
      return sf == '1';
    }
  }

  ///
  /// Return the next path flag, or fail with a ParseError if there isn't one.
  ///
  bool nextFlag() {
    final r = tryNextFlag();
    if (r != null) {
      return r;
    } else {
      error('flag expected');
      return false; // not reached
    }
  }

  List<String> getList(RegExp matcher) {
    final r = List<String>.empty(growable: true);
    for (;;) {
      final val = tryNextMatch(matcher);
      if (val == null) {
        break;
      }
      r.add(val);
    }
    return r;
  }

  List<double> getFloatList() {
    final rs = getList(_floatMatch);
    final r = Float64List(rs.length);
    for (int i = 0; i < rs.length; i++) {
      r[i] = double.parse(rs[i]);
    }
    return r;
  }

  /// Skip whitespace, including commas.  Including commas as whitespace
  /// is a little overly permissive in some places, but harmless.
  void skipWhitespace() {
    final Match? m = _wsMatch.matchAsPrefix(source, _pos);
    if (m != null) {
      _pos = m.end;
    }
  }

  /// Get whatever characters are remaining at the end of the string, without
  /// consuming them.
  String getRemaining() => source.substring(_pos);

  ///
  /// Give the next identifier, that is, the next sequence of letters
  ///
  String? tryNextIdentifier() => tryNextMatch(_idMatch);

  static final _idMatch = RegExp(r'[a-zA-Z]+');

  ///
  /// Get the next parenthesis-enclosed string
  ///
  String getNextFunctionArgs() {
    skipWhitespace();
    final first = getNextChar();
    if (first != '(') {
      throw ParseError('Expected "(", got $first');
    }
    int depth = 1;
    final r = StringBuffer();
    for (;;) {
      final ch = getNextChar();
      if (ch == '(') {
        depth++;
      } else if (ch == ')') {
        depth--;
      }
      if (depth == 0) {
        break;
      }
      r.write(ch);
    }
    return r.toString();
  }
}

///
/// Exception thrown when there is a problem parsing
/// See [PathParser.parse].
///
///
/// {@category SVG DOM}
///
class ParseError {
  final String message;

  ParseError(this.message);

  @override
  String toString() => 'ParseError($message)';
}

///
/// Possible stroke join values for a paint object.  This is analagous
/// to `StrokeJoin` in `dart:ui`.
///
/// {@category SVG DOM}
///
// Note:  The numerical values of this enum are externalized.
enum SIStrokeJoin { miter, round, bevel }

///
/// Possible stroke cap values for a paint object.  This is analagous
/// to `StrokeCap` in `dart:ui`.
///
/// {@category SVG DOM}
///
// Note:  The numerical values of this enum are externalized.
enum SIStrokeCap { butt, round, square }

///
/// Possible fill type values for a paint object.  This is analogous
/// to `PathFillType` in `dart:ui`.
///
/// {@category SVG DOM}
///
// Note:  The numerical values of this enum are externalized.
enum SIFillType { evenOdd, nonZero }

///
/// Possible tint mode values for an asset.  This is a top-level
/// property for an asset that is not present in an SVG; it comes
/// from Android Vector Drawables.  It determines the `dart:ui`
/// `BlendMode` used to apply a tint,
///
/// {@category SVG DOM}
///
// NOTE:  The numerical values of this enum are externalized.
//        The default tint mode is srcIn.  The moded after "add"
//        aren't supported by AVDs, but they can be set on a
//        ScalableImage, because that API operates in terms of
//        blend mode.
enum SITintMode {
  srcOver,
  srcIn,
  srcATop,
  multiply,
  screen,
  add,
  clear,
  color,
  colorBurn,
  colorDodge,
  darken,
  difference,
  dst,
  dstATop,
  dstIn,
  dstOut,
  dstOver,
  exclusion,
  hardLight,
  hue,
  lighten,
  luminosity,
  modulate,
  overlay,
  saturation,
  softLight,
  src,
  srcOut,
  xor
}

///
/// Possible blend mode values used when painting a node.  This
/// is analagous to `BlendMode` in `dart:ui`.
///
/// {@category SVG DOM}
///
enum SIBlendMode {
  normal,
  multiply,
  screen,
  overlay,
  darken,
  lighten,
  colorDodge,
  colorBurn,
  hardLight,
  softLight,
  difference,
  exclusion,
  hue,
  saturation,
  color,
  luminosity
}

///
/// Possible font styles.
///
/// {@category SVG DOM}
///
enum SIFontStyle { normal, italic }

enum SIFontWeight { w100, w200, w300, w400, w500, w600, w700, w800, w900 }

///
/// Text anchor values.  See
/// https://www.w3.org/TR/2008/REC-SVGTiny12-20081222/text.html .
///
/// {@category SVG DOM}
///
enum SITextAnchor { start, middle, end }

///
/// Text anchor values.  See
/// https://www.w3.org/TR/SVG11/text.html .
///
/// {@category SVG DOM}
///
enum SIDominantBaseline {
  auto,
  ideographic,
  alphabetic,
  mathematical,
  central,
  textAfterEdge,
  middle,
  textBeforeEdge,
  hanging
}

///
/// Text decoration values.  See
/// https://www.w3.org/TR/2008/REC-SVGTiny12-20081222/text.html .
///
/// {@category SVG DOM}
///
enum SITextDecoration { none, lineThrough, overline, underline }

class SITextAttributes {
  final List<String>? fontFamily;
  final SITextAnchor textAnchor;
  final SIDominantBaseline dominantBaseline;
  final SIFontStyle fontStyle;
  final SIFontWeight fontWeight;
  final double fontSize;
  final SITextDecoration textDecoration;

  SITextAttributes({
    required this.fontFamily,
    required this.textAnchor,
    required this.fontStyle,
    required this.fontWeight,
    required this.fontSize,
    required this.textDecoration,
    required this.dominantBaseline
  });

  @override
  bool operator ==(final Object other) {
    if (identical(this, other)) {
      return true;
    } else if (other is SITextAttributes) {
      return (const ListEquality<String>())
              .equals(fontFamily, other.fontFamily) &&
          textAnchor == other.textAnchor &&
          dominantBaseline == other.dominantBaseline &&
          fontStyle == other.fontStyle &&
          fontWeight == other.fontWeight &&
          fontSize == other.fontSize &&
          textDecoration == other.textDecoration;
    } else {
      return false;
    }
  }

  @override
  int get hashCode =>
      0xa7cb9e84 ^
      Object.hash(Object.hashAll(fontFamily ?? const []), fontStyle, fontWeight,
      fontSize, textAnchor, textDecoration, dominantBaseline);
}

///
/// The data that is canonicalized when an SVG graph is built.
///
class CanonicalizedData<IM> {
  final images = CMap<IM>();
  final strings = CMap<String>();
  final stringLists = CMap<CList<String>>();

  // Float values, notably used in text nodes
  final floatValues = CMap<double>();

  List<List<String>> getStringLists() =>
      List.unmodifiable(stringLists.toList().map((CList<String> e) => e.list));
}

class CMap<K> {
  final Map<K, int> _map;
  bool _growing;

  CMap([Map<K, int>? map])
      : _map = map ?? {},
        _growing = true;

  int operator [](K key) {
    if (_growing) {
      return _map.putIfAbsent(key, () => _map.length);
    } else {
      final v = _map[key];
      if (v == null) {
        throw StateError('internal error - not growing');
      } else {
        return v;
      }
    }
  }

  int? getIfNotNull(K? key) {
    if (key == null) {
      return null;
    } else {
      return this[key];
    }
  }

  List<K> toList() {
    _growing = false;
    if (_map.isEmpty) {
      return const [];
    }
    K random = _map.entries.first.key;
    final r = List.filled(_map.length, random);
    for (final MapEntry<K, int> e in _map.entries) {
      r[e.value] = e.key;
    }
    return r;
  }
}

///
/// A canonicalizing list, where == tests equivalence of elements.
///
class CList<T> {
  final List<T> list;

  CList(this.list);

  @override
  int get hashCode => Object.hashAll(list);

  @override
  bool operator ==(Object other) {
    if (other is CList<T>) {
      return (const ListEquality<dynamic>()).equals(list, other.list);
    } else {
      return false;
    }
  }
}

///
/// Mark a method as unreachable.  As of this writing, coverage in Flutter
/// is immature and buggy; specifically, marking code as not subject to coverage
/// is broken.  With that said, scattering comments around is pretty ugly, so
/// I'll probably keep this function around after they fix it.  It's harmless,
/// and should be optimized away by tree shaking.
///
// coverage:ignore-start
T unreachable<T>(T result) {
  assert(false);
  return result;
}
// coverate:itnore-end

void defaultWarn(String s) => print(s); // coverage:ignore-line

void nullWarn(String s) {} // coverage:ignore-line
