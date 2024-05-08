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

library jovial_svg.path_noui;

import 'dart:math';

import 'package:meta/meta.dart';

import 'common_noui.dart';

///
/// A builder of a path whose source is a SVG `path` element.  A
/// [PathParser] calls methods on an implementor of [PathBuilder] as
/// it parses the components of an SVG path.
///
/// {@category SVG DOM}
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

  ///
  /// Finish the path.
  ///
  void end();
}

///
/// A builder of a path, including building an oval (which isn't part of
/// SVG's `path` syntax, but is used for the circle and ellipse node types).
///
abstract class EnhancedPathBuilder extends PathBuilder {
  ///
  /// Add an oval (ellipse) that fills the given rectangle.
  ///
  void addOval(RectT rect);
}

///
/// A [PathBuilder] that produces a path string.  This can be used with
/// a [PathParser] if you have a path string that you want to parse, modify,
/// and then reconstitute as a path string.
///
/// Usage:
/// One possible use is to intercept path builder calls, and transform them to
/// something else.  For example, if for some reason you wanted to remove all
/// lineTo commands (`'L'`/`'l'`, or additional coordinates in an `'M'`/`'m'`)
/// from the path of an `SvgPath` node, you could do this:
/// ```
/// class NoLinesPathBuilder extends StringPathBuilder {
///    @override
///    void lineTo(PointT p)  {}
///  }
///
/// void removeLinesFrom(final SvgPath node) {
///   final pb = NoLinesPathBuilder();
///   PathParser(pb, node.pathData).parse();
///   node.pathData = pb.result;
/// }
/// ```
///
/// {@category SVG DOM}
///
class StringPathBuilder extends PathBuilder {
  final _result = StringBuffer();

  String get result => _result.toString();

  @override
  void moveTo(PointT p) {
    _result.write('M ${p.x} ${p.y} ');
  }

  @override
  void close() {
    _result.write('Z ');
  }

  @override
  void lineTo(PointT p) {
    _result.write('L ${p.x} ${p.y} ');
  }

  @override
  void cubicTo(PointT c1, PointT c2, PointT p, bool shorthand) {
    if (shorthand) {
      _result.write('S ');
    } else {
      _result.write('C ${c1.x} ${c1.y} ');
    }
    _result.write('${c2.x} ${c2.y} ${p.x} ${p.y} ');
  }

  @override
  void quadraticBezierTo(PointT control, PointT p, bool shorthand) {
    if (shorthand) {
      _result.write('T ');
    } else {
      _result.write('Q ${control.x} ${control.y} ');
    }
    _result.write('${p.x} ${p.y} ');
  }

  @override
  void arcToPoint(PointT arcEnd,
      {required RadiusT radius,
      required double rotation,
      required bool largeArc,
      required bool clockwise}) {
    _result.write('A ');
    _result.write(radius.x);
    _result.write(' ');
    _result.write(radius.y);
    _result.write(' ');
    _result.write(rotation * 180.0 / pi);
    _result.write(' ');
    _result.write(largeArc ? '1 ' : '0 ');
    _result.write(clockwise ? '1 ' : '0 ');
    _result.write(arcEnd.x);
    _result.write(' ');
    _result.write(arcEnd.y);
    _result.write(' ');
  }

  @override
  void end() {}
}

///
/// Some helpful support for parsing a path.  Paths include some logic
/// for calculating control points for the "shorthand" versions of
/// cubic and quadratic Bézier curves.  They depend on tracking the
/// control point of the last such curve, and tracking the current point.
/// This helper implements that logic.
///
abstract class AbstractPathParser<BT extends PathBuilder> {
  final BT builder;
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
  /// Run a command that adds to the path.  The command's first argument is
  /// [firstValue], but it may take other arguments.  Splitting out the first
  /// argument value like this makes it easier to deal with repeated
  /// commands in a String path.
  ///
  @protected
  void runPathCommand(double firstValue, PointT Function(double) command) {
    _nextQuadControl = null;
    _nextCubicControl = null;
    _currentPoint = command(firstValue);
    _lastQuadControl = _nextQuadControl;
    _lastCubicControl = _nextCubicControl;
  }

  ///
  /// moveTo is special, because it sets the initial point.  It isn't
  /// run through [runPathCommand], like the other commands are.
  ///
  @protected
  void buildMoveTo(PointT c) {
    _currentPoint = c;
    _initialPoint = c;
    builder.moveTo(c);
    _lastQuadControl = null;
    _lastCubicControl = null;
  }

  @protected
  PointT buildCubicBezier(PointT? control1, PointT control2, PointT dest) {
    final shorthand = control1 == null;
    final c1 = control1 ?? _shorthandControl(_lastCubicControl);
    builder.cubicTo(c1, control2, dest, shorthand);
    _nextCubicControl = control2;
    // s. https://www.w3.org/TR/2018/CR-SVG2-20181004/paths.html 9.3.6
    return dest;
  }

  @protected
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
  @protected
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
  @protected
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
/// Parse an SVG Path. The path syntax is specified at at
/// https://www.w3.org/TR/2018/CR-SVG2-20181004/paths.html
///
/// Usage:
/// ```
/// String src = "M 125,75 a100,50 0 0,1 100,50"
/// final PathBuilder builder = ...;
/// PathParser(builder, src).parse();
/// ... do something with whatever builder produces ...
/// ```
///
/// {@category SVG DOM}
///
final class PathParser {
  final RealPathParser _hidden;

  ///
  /// Create a parser to parse [source].  It will call the appropriate methods
  /// on [builder] to build a result.
  ///
  PathParser(PathBuilder builder, String source)
      : _hidden = RealPathParser(builder, source);

  ///
  /// Parse the string.  On error, this throws a [ParseError], but it leaves
  /// the path up to where the error occurred in builder.path.  The error
  /// behavior specified in s. 9.5.4 of
  /// https://www.w3.org/TR/2018/CR-SVG2-20181004/paths.html can be had
  /// by catching the exception, reporting it to the user if appropriate,
  /// and rendering the partial path.
  ///
  void parse() => _hidden.parse();
}

class RealPathParser extends AbstractPathParser<PathBuilder> {
  final BnfLexer _lexer;
  // Is the current command relative?
  bool _relative = false;

  RealPathParser(super.builder, String source) : _lexer = BnfLexer(source);

  static final Map<String, void Function(RealPathParser)> _action = {
    'M': (RealPathParser p) {
      p._relative = false;
      p._moveTo();
    },
    'm': (RealPathParser p) {
      p._relative = true;
      p._moveTo();
    },
    'Z': (RealPathParser p) => p.buildClose(),
    'z': (RealPathParser p) => p.buildClose(),
    'L': (RealPathParser p) {
      p._relative = false;
      p._repeat(p._lineTo);
    },
    'l': (RealPathParser p) {
      p._relative = true;
      p._repeat(p._lineTo);
    },
    'H': (RealPathParser p) {
      p._relative = false;
      p._repeat(p._horizontalLineTo);
    },
    'h': (RealPathParser p) {
      p._relative = true;
      p._repeat(p._horizontalLineTo);
    },
    'V': (RealPathParser p) {
      p._relative = false;
      p._repeat(p._verticalLineTo);
    },
    'v': (RealPathParser p) {
      p._relative = true;
      p._repeat(p._verticalLineTo);
    },
    'C': (RealPathParser p) {
      p._relative = false;
      p._repeat(p._cubicBezier);
    },
    'c': (RealPathParser p) {
      p._relative = true;
      p._repeat(p._cubicBezier);
    },
    'S': (RealPathParser p) {
      p._relative = false;
      p._repeat(p._shorthandCubicBezier);
    },
    's': (RealPathParser p) {
      p._relative = true;
      p._repeat(p._shorthandCubicBezier);
    },
    'Q': (RealPathParser p) {
      p._relative = false;
      p._repeat(p._quadraticBezier);
    },
    'q': (RealPathParser p) {
      p._relative = true;
      p._repeat(p._quadraticBezier);
    },
    'T': (RealPathParser p) {
      p._relative = false;
      p._repeat(p._shorthandQuadraticBezier);
    },
    't': (RealPathParser p) {
      p._relative = true;
      p._repeat(p._shorthandQuadraticBezier);
    },
    'A': (RealPathParser p) {
      p._relative = false;
      p._repeat(p._arcToPoint);
    },
    'a': (RealPathParser p) {
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
        final void Function(RealPathParser)? a = _action[cmd];
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
