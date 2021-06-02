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
/// Utilities that are common between DAG and Compact
/// scalable image implementations.
///
library jovial_svg.common_noui;

import 'dart:math';
import 'dart:typed_data';

import 'package:quiver/core.dart' as quiver;

import 'affine.dart';
import 'path_noui.dart';

typedef AlignmentT = Point<double>;
typedef PointT = Point<double>;
typedef RadiusT = Point<double>;
typedef ViewboxT = Rectangle<double>;

abstract class SIVisitor<PathDataT, R> {
  R get initial;

  R path(R collector, PathDataT pathData, SIPaint paint);

  R group(R collector, Affine? transform);

  R endGroup(R collector);

  R clipPath(R collector, PathDataT pathData);

  R images(R collector, List<SIImageData> im);

  R image(R collector, int imageNumber);
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
}

class SIPaint {
  final int fillColor;
  final SIColorType fillColorType;
  final int strokeColor;
  final SIColorType strokeColorType;
  final double strokeWidth;
  final double strokeMiterLimit;
  final SIStrokeJoin strokeJoin;
  final SIStrokeCap strokeCap;
  final SIFillType fillType;

  const SIPaint(
      {required this.fillColor,
      required this.fillColorType,
      required this.strokeColor,
      required this.strokeColorType,
      required double? strokeWidth,
      required double? strokeMiterLimit,
      required SIStrokeJoin? strokeJoin,
      required SIStrokeCap? strokeCap,
      required SIFillType? fillType})
      : strokeWidth = strokeWidth ?? strokeWidthDefault,
        strokeMiterLimit = strokeMiterLimit ?? strokeMiterLimitDefault,
        strokeJoin = strokeJoin ?? SIStrokeJoin.miter,
        strokeCap = strokeCap ?? SIStrokeCap.square,
        fillType = fillType ?? SIFillType.nonZero;

  static const double strokeMiterLimitDefault = 4;
  static const double strokeWidthDefault = 1;

  @override
  int get hashCode => quiver.hash4(fillColor, strokeColor, strokeWidth,
      quiver.hash4(strokeMiterLimit, strokeJoin, strokeCap, fillType));

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
          fillType == other.fillType;
    } else {
      return false;
    }
  }
}

enum SIColorType { none, currentColor, value }

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
    'red': 0xffffffff,
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
      final lex = BnfLexer(s.substring(3, s.length - 1));
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
      if (warn && !warnedAbout.contains(postfix)) {
        warnedAbout.add(postfix);
        print('    (ignoring units "$postfix")');
      }
      return double.parse(s.substring(m.start, m.end));
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

  // Throw a PathError with a helpful message, including a pointer
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

enum SIFontStyle { inherit, normal, italic, oblique }

enum SIFontWeight {
  inherit,
  w100,
  w200,
  w300,
  w400,
  w500,
  w600,
  w700,
  w800,
  w900,
  bolder,
  lighter
}
