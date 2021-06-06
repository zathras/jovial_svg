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
/// Utilities that are common between DAG and Compact
/// scalable image implementations.
///
library jovial_svg.common_noui;

import 'dart:math';
import 'dart:typed_data';

import 'package:quiver/core.dart' as quiver;
import 'package:quiver/collection.dart' as quiver;

import 'affine.dart';
import 'path_noui.dart';

typedef AlignmentT = Point<double>;
typedef PointT = Point<double>;
typedef RadiusT = Point<double>;
typedef RectT = Rectangle<double>;

abstract class SIVisitor<PathDataT, R> {
  R get initial;

  ///
  /// Called first on a traversal, this establishes immutable values that
  /// are canonicalized.
  ///
  R init(R collector, List<SIImageData> im, List<String> strings,
      List<List<double>> floatLists, List<Affine> transforms);

  R path(R collector, PathDataT pathData, SIPaint paint);

  R group(R collector, int? transformIndex);

  R endGroup(R collector);

  R clipPath(R collector, PathDataT pathData);

  R image(R collector, int imageIndex);

  R text(R collector, int xIndex, int yIndex, int textIndex, SITextAttributes a,
      SIPaint paint);
}

abstract class SIBuilder<PathDataT> extends SIVisitor<PathDataT, void> {
  bool get warn;

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
  /// The path data is used to canonicalize paths.  If this path data has
  /// been seen before, this method will return null, and the scalable image
  /// will re-use the previously built, equivalent path.
  ///
  PathBuilder? startPath(SIPaint paint, Object key);
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

  SIImageData.copy(SIImageData other)
      : x = other.x,
        y = other.y,
        width = other.width,
        height = other.height,
        encoded = other.encoded;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    } else if (other is SIImageData) {
      return x == other.x &&
          y == other.y &&
          width == other.width &&
          height == other.height &&
          quiver.listsEqual(encoded, other.encoded);
    } else {
      return false;
    }
  }

  @override
  int get hashCode => quiver.hash4(
      x, y, width, quiver.hash2(height, quiver.hashObjects(encoded)));
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
      required double? strokeWidth,
      required double? strokeMiterLimit,
      required SIStrokeJoin? strokeJoin,
      required SIStrokeCap? strokeCap,
      required SIFillType? fillType,
      required this.strokeDashArray,
      required this.strokeDashOffset})
      : strokeWidth = strokeWidth ?? strokeWidthDefault,
        strokeMiterLimit = strokeMiterLimit ?? strokeMiterLimitDefault,
        strokeJoin = strokeJoin ?? SIStrokeJoin.miter,
        strokeCap = strokeCap ?? SIStrokeCap.square,
        fillType = fillType ?? SIFillType.nonZero;

  static const double strokeMiterLimitDefault = 4;
  static const double strokeWidthDefault = 1;

  SIPaint forText() => SIPaint(
      fillColor: fillColor,
      strokeColor: SIColor.none,
      strokeWidth: null,
      strokeMiterLimit: null,
      strokeJoin: null,
      strokeCap: null,
      fillType: null,
      strokeDashArray: null,
      strokeDashOffset: null);

  @override
  int get hashCode => quiver.hash4(
      quiver.hash2(fillColor, strokeColor),
      quiver.hash4(strokeWidth, strokeMiterLimit, strokeJoin, strokeCap),
      quiver.hash2(fillType, strokeDashOffset),
      quiver.hashObjects(strokeDashArray ?? <double>[]));

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
          quiver.listsEqual(strokeDashArray, other.strokeDashArray) &&
          strokeDashOffset == other.strokeDashOffset;
    } else {
      return false;
    }
  }
}

abstract class SIColor {
  const SIColor();

  static const none = SINoneColor._p();
  static const currentColor = SICurrentColor._p();

  void accept(SIColorVisitor v);
}

class SINoneColor extends SIColor {
  const SINoneColor._p();

  @override
  void accept(SIColorVisitor v) => v.none();
}

class SICurrentColor extends SIColor {
  const SICurrentColor._p();

  @override
  void accept(SIColorVisitor v) => v.current();
}

class SIValueColor extends SIColor {
  final int argb;

  SIValueColor(this.argb);

  @override
  void accept(SIColorVisitor v) => v.value(this);

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

enum SIGradientSpreadMethod { pad, reflect, repeat }

abstract class SIGradientColor extends SIColor {
  final SIGradientSpreadMethod spreadMethod =
      SIGradientSpreadMethod.pad; // @@ TODO
  final List<SIColor> colors;
  final List<double> stops;
  final bool objectBoundingBox;

  SIGradientColor(this.colors, this.stops, this.objectBoundingBox);
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
      required bool objectBoundingBox})
      : super(colors, stops, objectBoundingBox);

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
          quiver.listsEqual(colors, other.colors) &&
          quiver.listsEqual(stops, other.stops) &&
          objectBoundingBox == other.objectBoundingBox;
    } else {
      return false;
    }
  }

  @override
  int get hashCode => quiver.hash4(quiver.hash4(x1, y1, x2, y2),
      quiver.hashObjects(colors), quiver.hashObjects(stops), objectBoundingBox);
}

class SIRadialGradientColor extends SIGradientColor {
  final double cx;
  final double cy;
  final double r;

  SIRadialGradientColor(
      {required this.cx,
      required this.cy,
      required this.r,
      required List<SIColor> colors,
      required List<double> stops,
      required bool objectBoundingBox})
      : super(colors, stops, objectBoundingBox);

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
          quiver.listsEqual(colors, other.colors) &&
          quiver.listsEqual(stops, other.stops) &&
          objectBoundingBox == other.objectBoundingBox;
    } else {
      return false;
    }
  }

  @override
  int get hashCode => quiver.hash4(quiver.hash3(cx, cy, r),
      quiver.hashObjects(colors), quiver.hashObjects(stops), objectBoundingBox);
}

class SIColorVisitor {
  final void Function(SIValueColor c) value;
  final void Function() none;
  final void Function() current;
  final void Function(SILinearGradientColor c) linearGradient;
  final void Function(SIRadialGradientColor c) radialGradient;

  const SIColorVisitor(
      {required this.value,
      required this.none,
      required this.current,
      required this.linearGradient,
      required this.radialGradient});
}

///
/// Mixin for SIBuilder that builds paths from strings
///
mixin SIStringPathMaker {
  void makePath(String pathData, PathBuilder pb, {bool warn = true}) {
    try {
      PathParser(pb, pathData).parse();
    } catch (e) {
      if (warn) {
        print(e);
        // As per the SVG spec, paths shall be parsed up to the first error,
        // and it is recommended that errors be reported to the user if
        // posible.
      }
    }
  }

  String immutableKey(String key) => key;
}

abstract class GenericParser {
  bool get warn;

  /// Tiny s. 11.13.1 requires the sixteen colors from HTML 4.
  static const _namedColors = {
    'currentcolor': 0xff000000,
    'black': 0xff000000,
    'silver': 0xffc0c0c0,
    'gray': 0xff808080,
    'white': 0xffffffff,
    'maroon': 0xff800000,
    'red': 0xffff0000,
    'purple': 0xff800080,
    'fuchsia': 0xffff00ff,
    'green': 0xff008000,
    'lime': 0xff00ff00,
    'olive': 0xff808000,
    'yellow': 0xffffff00,
    'navy': 0xff000080,
    'blue': 0xff0000ff,
    'teal': 0xff008080,
    'aqua': 0xff00ffff
  };

  int getColor(String s) {
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
      throw ParseError('Color is not #rgb #rrggbb or #aarrggbb:  $s');
    }
    if (s.startsWith('rgb') && s.endsWith(')')) {
      final lex = BnfLexer(s.substring(4, s.length - 1));
      final rgb = lex.getList(_colorComponentMatch);
      if (rgb.length != 3) {
        throw ParseError('Invalid rgb() syntax: $s');
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
    throw ParseError('Unrecognized color $s');
  }

  static final _colorComponentMatch = RegExp(r'[0-9]+%?');

  int _getColorComponent(String s) {
    if (s.endsWith('%')) {
      final pc = double.parse(s.substring(0, s.length - 1)).clamp(0, 1);
      return ((256 * pc).ceil() - 1).clamp(0, 255);
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
      throw ParseError('Invalid fill type value:  $s');
    }
    return r;
  }

  static final _floatMatch = RegExp(r'[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?');

  final warnedAbout = {'px', ''};

  double? getFloat(String? s) {
    if (s == null || s == 'inherit') {
      return null;
    }
    final Match? m = _floatMatch.matchAsPrefix(s);
    if (m == null) {
      throw ParseError('Expected float value, saw "$s".');
    } else {
      String postfix = s.substring(m.end).trim();
      final double multiplier;
      if (postfix == '') {
        multiplier = 1.0;
      } else if (postfix == 'cm') {
        multiplier = 96.0 / 2.54;
        // 96 dpi is as good as anything else.  This isn't terribly
        // important - see Tiny 7.11
      } else if (postfix == 'mm') {
        multiplier = 96.0 / 25.4;
      } else if (postfix == 'in') {
        multiplier = 96.0;
      } else {
        multiplier = 1.0;
        if (warn && !warnedAbout.contains(postfix)) {
          warnedAbout.add(postfix);
          print('    (ignoring units "$postfix")');
        }
      }
      return multiplier * double.parse(s.substring(m.start, m.end));
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

  List<double>? getFloatList(String? s) {
    if (s == null) {
      return null;
    } else if (s.toLowerCase() == 'none') {
      return [];
    }
    final lex = BnfLexer(s);
    final r = List<double>.empty(growable: true);
    for (;;) {
      final d = lex.tryNextFloat();
      if (d == null) {
        break;
      }
      r.add(d);
    }
    return r;
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
      segment = '...' + segment.substring(pos - 30);
      pos = 33;
    }
    if (segment.length > 67) {
      segment = segment.substring(0, 64) + '...';
    }
    final String caret = '^'.padLeft(pos + 1);
    throw ParseError(
        '$message at character position $_pos\n$segment\n$caret        ');
  }

  bool get eof => _pos == source.length;

  /// Get the next path command.  It might not be a valid command.
  String nextPathCommand() {
    skipWhitespace();
    if (eof) {
      error('Unexpected EOF');
    }
    // It's just the next character.  No reason to get fancier than
    // this.
    final start = _pos++;
    final r = source.substring(start, _pos);
    return r;
  }

  ///
  /// Return the next string that matches [matcher], or null if there is none.
  ///
  String? tryNextMatch(RegExp matcher) {
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
      return double.parse(sf);
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
class ParseError {
  final String message;

  ParseError(this.message);

  @override
  String toString() => 'PathError($message)';
}

// Note:  The numerical values of this enum are externalized.
enum SIStrokeJoin { miter, round, bevel }

// Note:  The numerical values of this enum are externalized.
enum SIStrokeCap { butt, round, square }

// Note:  The numerical values of this enum are externalized.
enum SIFillType { evenOdd, nonZero }

// NOTE:  The numerical values of this enum are externalized.
//        The default tint mode is srcIn.
enum SITintMode { srcOver, srcIn, srcATop, multiply, screen, add }

enum SIFontStyle { normal, italic }

enum SIFontWeight { w100, w200, w300, w400, w500, w600, w700, w800, w900 }

class SITextAttributes {
  final String fontFamily;
  final SIFontStyle fontStyle;
  final SIFontWeight fontWeight;
  final double fontSize;

  SITextAttributes(
      {required this.fontFamily,
      required this.fontStyle,
      required this.fontWeight,
      required this.fontSize});
}
