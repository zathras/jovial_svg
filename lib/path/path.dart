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
/// Library for dealing with SVG paths:  parsing, rendering, and an efficient
/// binary format for externalization.  The binary format is also a reasonably
/// compact, fast way of holding a path in memory for rendering.
library path;

import 'dart:math';

///
/// A builder of a path.  This abstract class does not depend on Flutter, so it
/// can be extended to create a Flutter UI Path object, or it can be used to
/// create a binary file in a pure dart program.
///
abstract class PathBuilder<OffsetT, RadiusT> {
  ///
  /// Create a new [OffsetT] object.
  ///
  OffsetT newOffset(double x, double y);

  ///
  /// Return a new offset that is `a + b`
  ///
  OffsetT addOffsets(OffsetT a, OffsetT b);

  ///
  /// Return a new offset that is `a - b`
  ///
  OffsetT subtractOffsets(OffsetT a, OffsetT b);

  ///
  /// Get the y value from `OffsetT`
  ///
  double getY(OffsetT p);

  ///
  /// Get the x value from `OffsetT`
  ///
  double getX(OffsetT p);

  ///
  /// Create a new `RadiusT` object for an elliptical radius
  ///
  RadiusT newRadius(double x, double y);

  ///
  /// Add a moveTo to the path
  ///
  void moveTo(OffsetT p);

  ///
  /// Add a close to the path
  ///
  void close();

  ///
  /// Add a lineTo to the path
  ///
  void lineTo(OffsetT p);

  ///
  /// Add a cubicTo to the path
  ///
  void cubicTo(OffsetT c1, OffsetT c2, OffsetT p);

  ///
  /// Add a quadraticBezierTo to the path
  ///
  void quadraticBezierTo(OffsetT control, OffsetT p);

  ///
  /// Add an arc.  `rotation` in radians, as is (sorta offhandedly) documented
  /// for Flutter's Path.
  ///
  void arcToPoint(OffsetT arcEnd,
      {required RadiusT radius,
      required double rotation,
      required bool largeArc,
      required bool clockwise});
}

///
/// A simple lexer for the Path syntax.  See
/// https://www.w3.org/TR/2018/CR-SVG2-20181004/paths.html
///
class _Lexer {
  final String source;
  int _pos = 0;

  _Lexer(this.source);

  // Set true to see the tokens go by.
  static const bool _debug = false;

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
  static final _floatMatch = RegExp(r'[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?');

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
    final String caret = '^'.padLeft(pos+1);
    throw PathError(
        '$message at character position $_pos\n$segment\n$caret        ');
  }

  bool get eof => _pos == source.length;

  /// Get the next command.  It might not be a valid command.
  String nextCommand() {
    _skipWhitespace();
    if (eof) {
      error('Unexpected EOF');
    }
    // It's just the next character.  No reason to get fancier than
    // this.
    final start = _pos++;
    final r = source.substring(start, _pos);
    if (_debug) {
      print('Command "$r"');
    }
    return r;
  }

  ///
  /// Return the next float in the input, or null if there isn't one.
  ///
  double? tryNextFloat() {
    _skipWhitespace();
    final Match? m = _floatMatch.matchAsPrefix(source, _pos);
    if (m == null) {
      return null;
    } else {
      _pos = m.end;
      final r = double.parse(source.substring(m.start, m.end));
      if (_debug) {
        print('  float "$r"');
      }
      return r;
    }
  }

  ///
  /// Return the next float, or fail with a ParseError if there isn't one.
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
    _skipWhitespace();
    final Match? m = _flagMatch.matchAsPrefix(source, _pos);
    if (m == null) {
      return null;
    } else {
      _pos = m.end;
      final r = source.substring(m.start, m.end) == '1';
      if (_debug) {
        print('  flag "$r"');
      }
      return r;
    }
  }

  ///
  /// Return the next flag, or fail with a ParseError if there isn't one.
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

  // Skip whitespace, including commas.  Including commas as whitespace
  // is a little overly permissive, but harmless.
  void _skipWhitespace() {
    final Match? m = _wsMatch.matchAsPrefix(source, _pos);
    if (m != null) {
      _pos = m.end;
    }
  }
}

///
/// Parse an SVG Path. See the specifiation at
/// https://www.w3.org/TR/2018/CR-SVG2-20181004/paths.html
///
/// Usage:
/// ```
/// String src = "M 125,75 a100,50 0 0,1 100,50"
/// final builder = UIPathBuilder();
/// PathParser(builder, src).parse();
/// Path p = builder.path;
/// ... render p on a Canvas...
/// ```
class PathParser<OffsetT, RadiusT> {
  PathBuilder<OffsetT, RadiusT> builder;
  _Lexer _lexer;
  // Is the current command relative?
  bool _relative = false;
  OffsetT _currentPoint;
  OffsetT _initialPoint;
  // https://www.w3.org/TR/2018/CR-SVG2-20181004/paths.html s. 9.3.1
  OffsetT? _lastCubicControl;
  // https://www.w3.org/TR/2018/CR-SVG2-20181004/paths.html s. 9.3.6
  OffsetT? _nextCubicControl;
  OffsetT? _lastQuadControl;
  OffsetT? _nextQuadControl;

  PathParser(this.builder, String source)
      : _lexer = _Lexer(source),
        _currentPoint = builder.newOffset(0, 0),
        _initialPoint = builder.newOffset(0, 0);

  static Map<String, void Function(PathParser)> _action = {
    'M': (PathParser p) {
      p._relative = false;
      p._moveTo();
    },
    'm': (PathParser p) {
      p._relative = true;
      p._moveTo();
    },
    'Z': (PathParser p) => p._close(),
    'z': (PathParser p) => p._close(),
    'L': (PathParser p) {
      p._relative = false;
      p._repeat(p._lineTo);
    },
    'l': (PathParser p) {
      p._relative = true;
      p._repeat(p._lineTo);
    },
    'H': (PathParser p) {
      p._relative = false;
      p._repeat(p._horizontalLineTo);
    },
    'h': (PathParser p) {
      p._relative = true;
      p._repeat(p._horizontalLineTo);
    },
    'V': (PathParser p) {
      p._relative = false;
      p._repeat(p._verticalLineTo);
    },
    'v': (PathParser p) {
      p._relative = true;
      p._repeat(p._verticalLineTo);
    },
    'C': (PathParser p) {
      p._relative = false;
      p._repeat(p._cubicBezier);
    },
    'c': (PathParser p) {
      p._relative = true;
      p._repeat(p._cubicBezier);
    },
    'S': (PathParser p) {
      p._relative = false;
      p._repeat(p._shorthandCubicBezier);
    },
    's': (PathParser p) {
      p._relative = true;
      p._repeat(p._shorthandCubicBezier);
    },
    'Q': (PathParser p) {
      p._relative = false;
      p._repeat(p._quadraticBezier);
    },
    'q': (PathParser p) {
      p._relative = true;
      p._repeat(p._quadraticBezier);
    },
    'T': (PathParser p) {
      p._relative = false;
      p._repeat(p._shorthandQuadraticBezier);
    },
    't': (PathParser p) {
      p._relative = true;
      p._repeat(p._shorthandQuadraticBezier);
    },
    'A': (PathParser p) {
      p._relative = false;
      p._repeat(p._arcToPoint);
    },
    'a': (PathParser p) {
      p._relative = true;
      p._repeat(p._arcToPoint);
    },
  };

  ///
  /// Parse the string.  On error, this throws a [ParseError], but it leaves
  /// the path up to where the error occurred in builder.path.  The error
  /// behavior specified in s. 9.5.4 of
  /// https://www.w3.org/TR/2018/CR-SVG2-20181004/paths.html can be had
  /// by catching the exception, reporting it to the user if appropriate,
  /// and rendering the partial path.
  ///
  void parse() {
    if (_lexer.source == 'none') {
      // https://www.w3.org/TR/2018/CR-SVG2-20181004/paths.html s. 9.3.9
      return;
    }
    while (!_lexer.eof) {
      String cmd = _lexer.nextCommand();
      final void Function(PathParser)? a = _action[cmd];
      if (a == null) {
        _lexer.error('Unrecognized command "$cmd"');
      } else {
        _nextQuadControl = null;
        _nextCubicControl = null;
        a(this);
        _lastQuadControl = _nextQuadControl;
        _lastCubicControl = _nextCubicControl;
      }
    }
  }

  void _repeat(OffsetT Function(double) command, [bool first = true]) {
    double? v = first ? _lexer.nextFloat() : _lexer.tryNextFloat();
    while (v != null) {
      _currentPoint = command(v);
      v = _lexer.tryNextFloat();
    }
  }

  void _moveTo() {
    final double x = _lexer.nextFloat();
    final double y = _lexer.nextFloat();
    final c = _coord(x, y);
    _currentPoint = c;
    _initialPoint = c;
    builder.moveTo(c);
    // https://www.w3.org/TR/2018/CR-SVG2-20181004/paths.html s. 9.3.3:
    // Additional "moves" are actually lines
    _repeat(_lineTo, false);
  }

  OffsetT _lineTo(double x) {
    double y = _lexer.nextFloat();
    OffsetT p = _coord(x, y);
    builder.lineTo(p);
    return p;
  }

  OffsetT _horizontalLineTo(double x) {
    if (_relative) {
      x += builder.getX(_currentPoint);
    }
    OffsetT p = builder.newOffset(x, builder.getY(_currentPoint));
    builder.lineTo(p);
    return p;
  }

  OffsetT _verticalLineTo(double y) {
    if (_relative) {
      y += builder.getY(_currentPoint);
    }
    OffsetT p = builder.newOffset(builder.getX(_currentPoint), y);
    builder.lineTo(p);
    return p;
  }

  OffsetT _cubicBezier(double x1) {
    OffsetT controlPoint = _coord(x1, _lexer.nextFloat());
    return _finishCubicBezier(controlPoint, _lexer.nextFloat());
  }

  OffsetT _shorthandCubicBezier(double x2) {
    final OffsetT control = _shorthandControl(_lastCubicControl);
    return _finishCubicBezier(control, x2);
  }

  OffsetT _finishCubicBezier(OffsetT control1, double x2) {
    OffsetT control2 = _coord(x2, _lexer.nextFloat());
    final x = _lexer.nextFloat();
    final y = _lexer.nextFloat();
    OffsetT dest = _coord(x, y);
    builder.cubicTo(control1, control2, dest);
    _nextCubicControl = control2;
    // s. https://www.w3.org/TR/2018/CR-SVG2-20181004/paths.html 9.3.6
    return dest;
  }

  OffsetT _quadraticBezier(double x1) {
    OffsetT controlPoint = _coord(x1, _lexer.nextFloat());
    return _finishQuadraticBezier(controlPoint, _lexer.nextFloat());
  }

  OffsetT _shorthandQuadraticBezier(double x2) {
    final OffsetT control = _shorthandControl(_lastQuadControl);
    return _finishQuadraticBezier(control, _lexer.nextFloat());
  }

  OffsetT _finishQuadraticBezier(OffsetT control, double x) {
    final y = _lexer.nextFloat();
    OffsetT dest = _coord(x, y);
    builder.quadraticBezierTo(control, dest);
    _nextQuadControl = control;
    // s. https://www.w3.org/TR/2018/CR-SVG2-20181004/paths.html 9.3.6
    return dest;
  }

  OffsetT _arcToPoint(double rx) {
    final RadiusT r = builder.newRadius(rx.abs(), _lexer.nextFloat().abs());
    // s. 9.5.1:  "... rx ... ry ... the absolute value is used ..."
    final double rotation = _lexer.nextFloat() * pi / 180.0;
    final bool largeArc = _lexer.nextFlag();
    final bool sweepFlag = _lexer.nextFlag();
    final double x = _lexer.nextFloat();
    final double y = _lexer.nextFloat();
    OffsetT dest = _coord(x, y);
    builder.arcToPoint(dest,
        radius: r,
        rotation: rotation,
        largeArc: largeArc,
        clockwise: sweepFlag);
    return dest;
  }

  _close() {
    builder.close();
    _currentPoint = _initialPoint;
  }

  OffsetT _shorthandControl(OffsetT? lastControl) {
    if (lastControl == null) {
      // "assume the first control point is coincident with the current point."
      // No assumption required; the code makes it so!
      return _currentPoint;
    } else {
      // Reflection of the second control point of the previous command
      // relative to the current point
      // control = cp + (control - lastControl)
      return builder.addOffsets(
          _currentPoint, builder.subtractOffsets(lastControl, _currentPoint));
    }
  }

  // make a coordinate
  OffsetT _coord(double x, double y) {
    if (_relative) {
      return builder.addOffsets(_currentPoint, builder.newOffset(x, y));
    } else {
      return builder.newOffset(x, y);
    }
  }
}

///
/// Exception thrown when there is a problem parsing a path.
/// See [PathParser.parse].
///
class PathError {
  final String message;

  PathError(this.message);

  @override
  String toString() => 'PathError($message)';
}
