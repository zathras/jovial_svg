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

library jovial_svg.path_noui;

import 'dart:math';

import 'common_noui.dart';

///
/// A builder of a path.
///
abstract class PathBuilder {
  ///
  /// Add a moveTo to the path
  ///
  void moveTo(PointT p);

  ///
  /// Add a close to the path
  ///
  void close();

  ///
  /// Add a lineTo to the path
  ///
  void lineTo(PointT p);

  ///
  /// Add a cubicTo to the path
  ///
  void cubicTo(PointT c1, PointT c2, PointT p, bool shorthand);

  ///
  /// Add a quadraticBezierTo to the path
  ///
  void quadraticBezierTo(PointT control, PointT p, bool shorthand);

  ///
  /// Add an arc.  `rotation` in radians, as is (sorta offhandedly) documented
  /// for Flutter's Path.
  ///
  void arcToPoint(PointT arcEnd,
      {required RadiusT radius,
      required double rotation,
      required bool largeArc,
      required bool clockwise});

  void addOval(RectT rect);

  ///
  /// Finish the path.
  ///
  void end();
}

///
/// Some helpful support for parsing a path.  Paths include some logic
/// for calculating control points for the "shorthand" versions of
/// cubic and quadratic Bézier curves.  They depend on tracking the
/// control point of the last such curve, and tracking the current point.
/// This helper implements that logic.
///
abstract class AbstractPathParser {
  final PathBuilder builder;
  PointT _initialPoint;
  // https://www.w3.org/TR/SVG/ s. 9.3.1
  PointT? _lastCubicControl;
  // https://www.w3.org/TR/SVG/ s. 9.3.6
  PointT? _nextCubicControl;
  PointT? _lastQuadControl;
  PointT? _nextQuadControl;
  PointT _currentPoint;

  AbstractPathParser(this.builder)
      : _initialPoint = const PointT(0, 0),
        _currentPoint = const PointT(0, 0);

  ///
  /// Run a command that adds to the path.  The commands first argument is
  /// [firstValue], but it may take other arguments.  Splitting out the first
  /// argument value like this makes it easier to deal with repeated
  /// commands in a String path.
  ///
  void runPathCommand(double firstValue, PointT Function(double) command) {
    _nextQuadControl = null;
    _nextCubicControl = null;
    _currentPoint = command(firstValue);
    _lastQuadControl = _nextQuadControl;
    _lastCubicControl = _nextCubicControl;
  }

  ///
  /// moveTo is special, because it sets the initial point.  It isn't
  /// run through runPathCommand, like the other commands are.
  ///
  void buildMoveTo(PointT c) {
    _currentPoint = c;
    _initialPoint = c;
    builder.moveTo(c);
    _lastQuadControl = null;
    _lastCubicControl = null;
  }

  PointT buildCubicBezier(PointT? control1, PointT control2, PointT dest) {
    final shorthand = control1 == null;
    final c1 = control1 ?? _shorthandControl(_lastCubicControl);
    builder.cubicTo(c1, control2, dest, shorthand);
    _nextCubicControl = control2;
    // s. https://www.w3.org/TR/2018/CR-SVG2-20181004/paths.html 9.3.6
    return dest;
  }

  PointT buildQuadraticBezier(PointT? control, PointT dest) {
    final shorthand = control == null;
    final c = control ?? _shorthandControl(_lastQuadControl);
    builder.quadraticBezierTo(c, dest, shorthand);
    _nextQuadControl = control;
    // s. https://www.w3.org/TR/2018/CR-SVG2-20181004/paths.html 9.3.6
    return dest;
  }

  ///
  /// buildClose() is not run through runCommand.  It can't be, since it
  /// takes no argument.
  ///
  void buildClose() {
    builder.close();
    _currentPoint = _initialPoint;
    _lastQuadControl = null;
    _lastCubicControl = null;
  }

  ///
  /// buildEnd() (which is for the end of the path) is not run through
  /// runCommand.  It can't be, since it takes no argument.
  ///
  void buildEnd() {
    builder.end();
  }

  PointT _shorthandControl(PointT? lastControl) {
    if (lastControl == null) {
      // "assume the first control point is coincident with the current point."
      // No assumption required; the code makes it so!
      return _currentPoint;
    } else {
      // Reflection of the second control point of the previous command
      // relative to the current point
      // control = cp + (control - lastControl)
      return _currentPoint - (lastControl - _currentPoint);
    }
  }
}

///
/// Parse an SVG Path. See the specification at
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
class PathParser extends AbstractPathParser {
  final BnfLexer _lexer;
  // Is the current command relative?
  bool _relative = false;

  PathParser(PathBuilder builder, String source)
      : _lexer = BnfLexer(source),
        super(builder);

  static final Map<String, void Function(PathParser)> _action = {
    'M': (PathParser p) {
      p._relative = false;
      p._moveTo();
    },
    'm': (PathParser p) {
      p._relative = true;
      p._moveTo();
    },
    'Z': (PathParser p) => p.buildClose(),
    'z': (PathParser p) => p.buildClose(),
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
      builder.end();
      return;
    }
    try {
      _lexer.skipWhitespace();
      while (!_lexer.eof) {
        String cmd = _lexer.nextPathCommand();
        final void Function(PathParser)? a = _action[cmd];
        if (a == null) {
          _lexer.error('Unrecognized command "$cmd"');
        } else {
          a(this);
        }
        _lexer.skipWhitespace();
      }
    } finally {
      buildEnd();
    }
  }

  void _repeat(PointT Function(double) command, [bool first = true]) {
    double? v = first ? _lexer.nextFloat() : _lexer.tryNextFloat();
    while (v != null) {
      runPathCommand(v, command);
      v = _lexer.tryNextFloat();
    }
  }

  void _moveTo() {
    final double x = _lexer.nextFloat();
    final double y = _lexer.nextFloat();
    final c = _coord(x, y);
    buildMoveTo(c);
    // https://www.w3.org/TR/2018/CR-SVG2-20181004/paths.html s. 9.3.3:
    // Additional "moves" are actually lines
    _repeat(_lineTo, false);
  }

  PointT _lineTo(double x) {
    double y = _lexer.nextFloat();
    PointT p = _coord(x, y);
    builder.lineTo(p);
    return p;
  }

  PointT _horizontalLineTo(double x) {
    if (_relative) {
      x += _currentPoint.x;
    }
    PointT p = PointT(x, _currentPoint.y);
    builder.lineTo(p);
    return p;
  }

  PointT _verticalLineTo(double y) {
    if (_relative) {
      y += _currentPoint.y;
    }
    PointT p = PointT(_currentPoint.x, y);
    builder.lineTo(p);
    return p;
  }

  PointT _cubicBezier(double x1) {
    PointT controlPoint = _coord(x1, _lexer.nextFloat());
    return _finishCubicBezier(controlPoint, _lexer.nextFloat());
  }

  PointT _shorthandCubicBezier(double x2) {
    return _finishCubicBezier(null, x2);
  }

  PointT _finishCubicBezier(PointT? control1, double x2) {
    PointT control2 = _coord(x2, _lexer.nextFloat());
    final x = _lexer.nextFloat();
    final y = _lexer.nextFloat();
    PointT dest = _coord(x, y);
    return buildCubicBezier(control1, control2, dest);
  }

  PointT _quadraticBezier(double x1) {
    PointT controlPoint = _coord(x1, _lexer.nextFloat());
    return _finishQuadraticBezier(controlPoint, _lexer.nextFloat());
  }

  PointT _shorthandQuadraticBezier(double x2) {
    return _finishQuadraticBezier(null, x2);
  }

  PointT _finishQuadraticBezier(PointT? control, double x) {
    final y = _lexer.nextFloat();
    PointT dest = _coord(x, y);
    return buildQuadraticBezier(control, dest);
  }

  PointT _arcToPoint(double rx) {
    final RadiusT r = RadiusT(rx.abs(), _lexer.nextFloat().abs());
    // s. 9.5.1:  "... rx ... ry ... the absolute value is used ..."
    final double rotation = _lexer.nextFloat() * pi / 180.0;
    final bool largeArc = _lexer.nextFlag();
    final bool sweepFlag = _lexer.nextFlag();
    final double x = _lexer.nextFloat();
    final double y = _lexer.nextFloat();
    PointT dest = _coord(x, y);
    builder.arcToPoint(dest,
        radius: r,
        rotation: rotation,
        largeArc: largeArc,
        clockwise: sweepFlag);
    return dest;
  }

  // make a coordinate
  PointT _coord(double x, double y) {
    if (_relative) {
      return PointT(_currentPoint.x + x, _currentPoint.y + y);
    } else {
      return PointT(x, y);
    }
  }
}
