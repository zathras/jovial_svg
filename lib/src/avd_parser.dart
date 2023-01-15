/*
Copyright (c) 2021-2022, William Foote

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
/// Android Vector Drawable parser
///
library jovial_svg.avd.parser;

import 'dart:math';

import 'package:xml/xml_events.dart';
import 'dart:async';
import 'affine.dart';
import 'common_noui.dart';
import 'svg_graph.dart';

///
/// Parse an Android Vector Drawable XML file.  The file format is
/// somewhat informally specified at
/// https://developer.android.com/guide/topics/graphics/vector-drawable-resources
/// and https://developer.android.com/reference/android/graphics/drawable/VectorDrawable
///
abstract class AvdParser extends GenericParser {
  final SIBuilder<String, SIImageData> _avdBuilder;
  late final SvgParseGraph avd;

  SvgPath? _currPath;
  // Initially, we didn't produce an intermediate graph for AVD files.
  // SvgParseGraph came later.  Wanting to share floats (e.g. for gradients)
  // requires an intermediate graph, so we just re-use the more general
  // one initially written for SVG files.

  AvdParser(this._avdBuilder);

  final _parentStack = List<SvgGroup>.empty(growable: true);
  final _tagStack = List<String>.empty(growable: true);
  SvgGradientColor? _currGradient;
  List<SvgGradientStop>? _defaultGradientStops;
  bool? _inFillColor; // else stroke
  bool _vectorStarted = false;
  bool _done = false;

  @override
  Function(String) get warn => _avdBuilder.warn;

  void _startTag(XmlStartElementEvent evt) {
    if (_done) {
      throw ParseError('Extraneous tag after </vector>:  $evt');
    }
    if (evt.name == 'vector') {
      if (_vectorStarted) {
        throw ParseError('Nested vector tag $evt');
      } else {
        _vectorStarted = true;
        _done = evt.isSelfClosing;
      }
      _parseVector(evt.attributes);
      if (_done) {
        avd.build(_avdBuilder);
      }
    } else if (!_vectorStarted) {
      throw ParseError('Expected <vector>, got $evt');
    } else if (evt.name == 'group') {
      if (_tagStack.isNotEmpty && _tagStack.last != 'group') {
        throw ParseError(
            'group only valid at top level, or inside another group:  $evt');
      }
      _parseGroup(evt.attributes);
      if (evt.isSelfClosing) {
        _parentStack.length--;
      } else {
        _tagStack.add('group');
      }
    } else if (evt.name == 'path') {
      _parsePath(evt.attributes);
      if (evt.isSelfClosing) {
        _currPath = null;
      } else {
        _tagStack.add('path');
      }
    } else if (evt.name == 'clip-path') {
      if (_tagStack.isNotEmpty && _tagStack.last != 'group') {
        throw ParseError(
            'clip-path only valid at top level or inside a group:  $evt');
      }
      _parseClipPath(evt.attributes);
      if (!evt.isSelfClosing) {
        _tagStack.add('path');
      }
    } else if (evt.name == 'aapt:attr') {
      _parseAaptAttr(evt.attributes);
      if (!evt.isSelfClosing) {
        _tagStack.add('aapt:attr');
      }
    } else if (evt.name == 'gradient') {
      if (_currGradient != null) {
        throw ParseError('Nested gradients?!?');
      }
      final g = _parseGradient(evt.attributes);
      final p = _currPath;
      if (p == null) {
        throw ParseError('Gradient outside a path?!?');
      }
      if (_inFillColor == false) {
        p.paint.strokeColor = g;
      } else {
        p.paint.fillColor = g;
      }
      if (evt.isSelfClosing) {
        _finishGradient(g);
      } else {
        _tagStack.add('gradient');
        _currGradient = g;
      }
    } else if (evt.name == 'item') {
      _parseItem(evt.attributes);
      if (!evt.isSelfClosing) {
        _tagStack.add('item');
      }
    } else {
      _tagStack.add(evt.name);
      warn('Unexpected tag inside vector:  $evt');
    }
  }

  void _endTag(XmlEndElementEvent evt) {
    if (_done) {
      throw ParseError('Unexpected end tag after vector:  $evt');
    } else if (evt.name == 'vector') {
      if (_tagStack.isNotEmpty) {
        throw ParseError('Expected </vector>, got </${evt.name}');
      }
      _done = true;
      avd.build(_avdBuilder);
    } else if (_tagStack.isEmpty) {
      throw ParseError('Unexpected end tag $evt');
    } else if (_tagStack.last != evt.name) {
      throw ParseError('Expected </${_tagStack.last}>, got $evt');
    } else {
      if (evt.name == 'path') {
        _currPath = null;
      } else if (evt.name == 'gradient') {
        assert(_currGradient != null);
        _finishGradient(_currGradient!);
        _currGradient = null;
      } else if (evt.name == 'group') {
        _parentStack.length--;
      }
      _tagStack.removeLast();
    }
  }

  void _parseVector(List<XmlEventAttribute> attrs) {
    double? width;
    double? height;
    double? scaledWidth;
    double? scaledHeight;
    int? tintColor;
    SITintMode? tintMode;

    for (final a in attrs) {
      if (a.name == 'andoird:autoMirrored' || a.name == 'android:alpha') {
        warn('   (ignoring ${a.name} ${a.value}.)');
        // These parameters control how an AVD interacts with other graphical
        // elements, and they would require rendering the AVD to its own
        // layer.  If this kind of effect is desired, it's best to do it
        // externally, with the SI just serving as a scalable image that can
        // be used by the surrounding program.
      } else if (a.name == 'android:name') {
        // don't care
      } else if (a.name == 'android:width') {
        scaledWidth = getFloat(a.value);
      } else if (a.name == 'android:height') {
        scaledHeight = getFloat(a.value);
      } else if (a.name == 'android:viewportWidth') {
        width = getFloat(a.value);
        // The width of the part of the AVD that contains drawing of interest.
        // This maps to the ScalableImage's width, and not to  its viewport.
        // A ScalableImage's viewport is something that's set programmatically,
        // to present a part of the underlying AVD.
      } else if (a.name == 'android:viewportHeight') {
        height = getFloat(a.value);
        // The height of the part of the AVD that contains drawing of interest.
      } else if (a.name == 'android:tint') {
        tintColor = getColor(a.value.trim().toLowerCase());
      } else if (a.name == 'android:tintMode') {
        tintMode = _getTintMode(a.value);
      }
    }
    final root = SvgRoot();
    if (scaledWidth != null || scaledHeight != null) {
      if (width == null || height == null) {
        // If the viewportWidth and/or viewportHeight attribute aren't
        // specified, we'd have to calculate the viewport to figure it out.
        // That can't be done here, since it requires calculating the
        // bounding rectangle of the paths, which is of course a Flutter API.
        // The parser has to work in the avd_to_si tool -- indeed, that's
        // the preferred usage -- and Flutter isn't available in a command-line
        // Dart tool.
        //
        // Maybe viewportWidth and viewportHeight are required?  They ought to
        // be, but I don't know if this is specified.  In any case, emitting
        // a warning that describes the reason for not scaling is a pretty
        // reasonable behavior in this edge case of an edge case.
        //
        // We *could* try calculating the bounding rectangle of all the points
        // in the path, and add in 2x the line width, if there were ever a
        // need to handle the (rare? illegal?) case where the viewportWidth
        // and viewportHeight attributes aren't specified.
        warn('    Unable to scale to width/height:  '
            'Need viewportWidth/viewportHeight.');
        // Fall through
      } else {
        scaledWidth ??= width;
        scaledHeight ??= height;
        if (scaledWidth == width && scaledHeight == height) {
          // Do nothing:  Fall through to the normal, unscaled case
        } else {
          // We should scale.  See issue 14.
          root.transform =
              MutableAffine.scale(scaledWidth / width, scaledHeight / height);
        }
      }
    }
    avd = SvgParseGraph(root, width, height, tintColor, tintMode);
    _parentStack.add(avd.root);
  }

  void _parseGroup(List<XmlEventAttribute> attrs) {
    double? rotation;
    double? pivotX;
    double? pivotY;
    double? scaleX;
    double? scaleY;
    double? translateX;
    double? translateY;

    for (final a in attrs) {
      if (a.name == 'android:name') {
        // don't care
      } else if (a.name == 'android:rotation') {
        final deg = getFloat(a.value);
        if (deg != null) {
          rotation = deg * pi / 180;
        }
      } else if (a.name == 'android:pivotX') {
        pivotX = getFloat(a.value);
      } else if (a.name == 'android:pivotY') {
        pivotY = getFloat(a.value);
      } else if (a.name == 'android:scaleX') {
        scaleX = getFloat(a.value);
      } else if (a.name == 'android:scaleY') {
        scaleY = getFloat(a.value);
      } else if (a.name == 'android:translateX') {
        translateX = getFloat(a.value);
      } else if (a.name == 'android:translateY') {
        translateY = getFloat(a.value);
      } else {
        warn('    Ignoring unexpected attribute ${a.name}');
      }
    }
    final transform = MutableAffine.identity();
    if (translateX != null ||
        translateY != null ||
        pivotX != null ||
        pivotY != null) {
      transform.multiplyBy(MutableAffine.translation(
          (translateX ?? 0) + (pivotX ?? 0),
          (translateY ?? 0) + (pivotY ?? 0)));
    }
    if (rotation != null) {
      transform.multiplyBy(MutableAffine.rotation(rotation));
    }
    if (scaleX != null || scaleY != null) {
      transform.multiplyBy(MutableAffine.scale(scaleX ?? 1, scaleY ?? 1));
    }
    if (pivotX != null || pivotY != null) {
      transform.multiplyBy(
          MutableAffine.translation(-(pivotX ?? 0), -(pivotY ?? 0)));
    }
    // https://developer.android.com/reference/android/graphics/drawable/VectorDrawable
    // says the pivot and translate are "in viewport space," which means the
    // coordinate space before any operations are done in this group.  It does
    // not mean the viewport of the top-level tree, if we have a parent group
    // that did transformations on the way down.

    final g = SvgGroup();
    if (!transform.isIdentity()) {
      g.transform = transform;
    }
    _parentStack.last.children.add(g);
    _parentStack.add(g);
  }

  void _parsePath(List<XmlEventAttribute> attrs) {
    SvgColor fill = SvgColor.none;
    SvgColor stroke = SvgColor.none;
    double? strokeWidth;
    int? strokeAlpha;
    int? fillAlpha;
    double? strokeMiterLimit;
    SIStrokeJoin? strokeJoin;
    SIStrokeCap? strokeCap;
    SIFillType? fillType;
    String? pathData;

    final dups = _DuplicateChecker();

    for (final a in attrs) {
      dups.check(a.name);
      if (a.name == 'android:name') {
        // don't care
      } else if (a.name == 'android:pathData') {
        pathData = a.value;
      } else if (a.name == 'android:fillColor') {
        final color = getColor(a.value.trim().toLowerCase());
        if (color != null) {
          fill = SvgColor.value(color);
        }
      } else if (a.name == 'android:strokeColor') {
        final color = getColor(a.value.trim().toLowerCase());
        if (color != null) {
          stroke = SvgColor.value(color);
        }
      } else if (a.name == 'android:strokeWidth') {
        strokeWidth = getFloat(a.value);
      } else if (a.name == 'android:strokeAlpha') {
        strokeAlpha = getAlpha(a.value);
      } else if (a.name == 'android:fillAlpha') {
        fillAlpha = getAlpha(a.value);
      } else if (a.name == 'android:strokeLineCap') {
        strokeCap = getStrokeCap(a.value);
      } else if (a.name == 'android:strokeLineJoin') {
        strokeJoin = getStrokeJoin(a.value);
      } else if (a.name == 'android:strokeMiterLimit') {
        strokeMiterLimit = getFloat(a.value);
      } else if (a.name == 'android:fillType') {
        try {
          fillType = getFillType(a.value);
        } catch (err) {
          warn('    Ignoring invalid fillType ${a.value}');
        }
      } else if (a.name == 'android:trimPathStart' ||
          a.name == 'android:trimPathEnd' ||
          a.name == 'android:trimPathOffset') {
        if (!warnedAbout.contains('android:trimPath')) {
          warnedAbout.add('android:trimPath');
          warn('    (ignoring animation attributes android:trimPathXXX)');
          // trimPathXXX are used for animation.  They're not useful here,
          // and supporting them would mean deferring path building to the
          // end.  They're not all that well-specified -
          // https://developer.android.com/reference/android/graphics/drawable/VectorDrawable
          // is less than clear about trimPathOffset, but according to
          // https://www.androiddesignpatterns.com/2016/11/introduction-to-icon-animation-techniques.html,
          // trimPathOffset actually makes the start and end wrap around (so
          // the part that's trimmed is in the middle).  It would be nice if
          // the (quasi-)normative spec language actually specified this!
          //
          // But complaining aside, if these animation parameters have initial
          // values in the static AVD, probably the best thing to do most of
          // the time is to include the whole path anyway.  It's certainly
          // a reasonable thing to do.
        }
      } else {
        warn('    Ignoring unexpected attribute ${a.name}');
      }
    }
    if (pathData == null) {
      warn('    Path with no android:pathData - ignored');
      return;
    }
    final path = SvgPath(pathData);
    path.paint.fillColor = fill;
    path.paint.fillAlpha = fillAlpha;
    path.paint.fillType = fillType;
    path.paint.strokeColor = stroke;
    path.paint.strokeWidth = strokeWidth;
    path.paint.strokeAlpha = strokeAlpha;
    path.paint.strokeMiterLimit = strokeMiterLimit;
    path.paint.strokeJoin = strokeJoin;
    path.paint.strokeCap = strokeCap;
    _parentStack.last.children.add(path);
    _currPath = path;
  }

  void _parseClipPath(List<XmlEventAttribute> attrs) {
    String? pathData;
    final dups = _DuplicateChecker();
    for (final a in attrs) {
      dups.check(a.name);
      if (a.name == 'android:name') {
        // don't care
      } else if (a.name == 'android:pathData') {
        pathData = a.value;
      } else {
        warn('    Ignoring unexpected attribute ${a.name}');
      }
    }
    if (pathData == null) {
      warn('    clip path with no android:pathData - ignored');
    } else {
      final clip = AvdClipPath(pathData);
      _parentStack.last.children.add(clip);
    }
  }

  static final _tintModeValues = {
    'src_over': SITintMode.srcOver,
    'src_in': SITintMode.srcIn,
    'src_atop': SITintMode.srcATop,
    'multiply': SITintMode.multiply,
    'screen': SITintMode.screen,
    'add': SITintMode.add
  };

  SITintMode _getTintMode(String s) {
    final r = _tintModeValues[s];
    if (r == null) {
      throw ParseError('Invalid tint mode:  $s');
    }
    return r;
  }

  void _parseAaptAttr(List<XmlEventAttribute> attrs) {
    final dups = _DuplicateChecker();
    for (final a in attrs) {
      dups.check(a.name);
      if (a.name == 'name') {
        if (a.value == 'android:fillColor') {
          _inFillColor = true;
        } else if (a.value == 'android:strokeColor') {
          _inFillColor = false;
        } else {
          warn('    Ignoring unexpected android:name ${a.value}');
        }
      } else {
        warn('    Ignoring unexpected attribute ${a.name}');
      }
    }
  }

  SvgGradientColor _parseGradient(List<XmlEventAttribute> attrs) {
    bool? inFillColor = _inFillColor;
    String type = 'linear';
    int? startColor;
    int? centerColor;
    int? endColor;
    double? startX;
    double? startY;
    double? endX;
    double? endY;
    double? centerX;
    double? centerY;
    double? radius;
    var spreadMethod = SIGradientSpreadMethod.pad;
    if (inFillColor == null) {
      throw ParseError('Missing aapt:attr name');
    }
    final dups = _DuplicateChecker();
    for (final a in attrs) {
      dups.check(a.name);
      if (a.name == 'android:type') {
        type = a.value;
      } else if (a.name == 'android:startColor') {
        startColor = getColor(a.value);
      } else if (a.name == 'android:centerColor') {
        centerColor = getColor(a.value);
      } else if (a.name == 'android:endColor') {
        endColor = getColor(a.value);
      } else if (a.name == 'android:startX') {
        startX = getFloat(a.value);
      } else if (a.name == 'android:startY') {
        startY = getFloat(a.value);
      } else if (a.name == 'android:endX') {
        endX = getFloat(a.value);
      } else if (a.name == 'android:endY') {
        endY = getFloat(a.value);
      } else if (a.name == 'android:centerX') {
        centerX = getFloat(a.value);
      } else if (a.name == 'android:centerY') {
        centerY = getFloat(a.value);
      } else if (a.name == 'android:gradientRadius') {
        radius = getFloat(a.value);
      } else if (a.name == 'android:tileMode') {
        final s = a.value.toLowerCase();
        if (s == 'repeat') {
          spreadMethod = SIGradientSpreadMethod.repeat;
        } else if (s == 'mirror') {
          spreadMethod = SIGradientSpreadMethod.reflect;
        } else {
          if (s != 'clamp') {
            warn('    Unrecognized gradient tile mode:  $s');
          }
          spreadMethod = SIGradientSpreadMethod.pad;
        }
      } else {
        warn('    Unrecognized gradient attribute  ${a.name}');
      }
    }
    final stops =
        _defaultGradientStops = List<SvgGradientStop>.empty(growable: true);
    if (startColor != null) {
      stops.add(SvgGradientStop(0.0, SvgColor.value(startColor), 0xff));
    }
    if (centerColor != null) {
      stops.add(SvgGradientStop(0.5, SvgColor.value(centerColor), 0xff));
    }
    if (endColor != null) {
      stops.add(SvgGradientStop(1.0, SvgColor.value(endColor), 0xff));
    }
    if (type == 'linear' &&
        startX != null &&
        startY != null &&
        endX != null &&
        endY != null) {
      return SvgLinearGradientColor(
          x1: SvgCoordinate.value(startX),
          y1: SvgCoordinate.value(startY),
          x2: SvgCoordinate.value(endX),
          y2: SvgCoordinate.value(endY),
          objectBoundingBox: false,
          transform: null,
          spreadMethod: spreadMethod);
    } else if (centerX != null && centerY != null) {
      if (type == 'radial' && radius != null) {
        return SvgRadialGradientColor(
            cx: SvgCoordinate.value(centerX),
            cy: SvgCoordinate.value(centerY),
            fx: SvgCoordinate.value(centerX),
            fy: SvgCoordinate.value(centerY),
            r: SvgCoordinate.value(radius),
            objectBoundingBox: false,
            transform: null,
            spreadMethod: spreadMethod);
      } else if (type == 'sweep') {
        return SvgSweepGradientColor(
            cx: centerX,
            cy: centerY,
            startAngle: null,
            endAngle: null,
            objectBoundingBox: false,
            transform: null,
            spreadMethod: spreadMethod);
      }
    }
    throw ParseError('invalid gradient');
  }

  void _parseItem(List<XmlEventAttribute> attrs) {
    final dups = _DuplicateChecker();
    int? color;
    double? offset;
    for (final a in attrs) {
      dups.check(a.name);
      if (a.name == 'android:color') {
        color = getColor(a.value);
      } else if (a.name == 'android:offset') {
        offset = getFloat(a.value);
      } else {
        warn('    Ignoring unexpected attribute ${a.name}');
      }
    }
    if (color == null) {
      throw ParseError('Missing stop color');
    } else if (offset == null) {
      throw ParseError('Missing stop offset');
    }
    _currGradient!
        .addStop(SvgGradientStop(offset, SvgColor.value(color), 0xff));
  }

  void _finishGradient(SvgGradientColor g) {
    final stops = _defaultGradientStops;
    if (stops != null && g.stops == null) {
      g.stops = stops;
    }
    _defaultGradientStops = null;
  }
}

class AvdClipPath extends SvgNode {
  final String pathData;

  AvdClipPath(this.pathData);

  @override
  SIBlendMode get blendMode => SIBlendMode.normal; // coverage:ignore-line

  @override
  void applyStylesheet(Stylesheet stylesheet,
      void Function(String) warn) {} // coverage:ignore-line

  @override
  bool build(
      SIBuilder<String, SIImageData> builder,
      CanonicalizedData<SIImageData> canon,
      Map<String, SvgNode> idLookup,
      SvgPaint ancestor,
      SvgTextAttributes ta,
      {bool blendHandledByParent = false}) {
    builder.clipPath(null, pathData);
    return true;
  }

  @override
  bool canUseLuma(Map<String, SvgNode> idLookup, SvgPaint ancestor) =>
      false; // coverage:ignore-line

  @override
  SvgNode? resolve(Map<String, SvgNode> idLookup, SvgPaint ancestor,
          void Function(String) warn, referrers) =>
      this;
}

class _AvdParserEventHandler with XmlEventVisitor {
  final AvdParser parser;

  _AvdParserEventHandler(this.parser);

  @override
  void visitStartElementEvent(XmlStartElementEvent e) => parser._startTag(e);

  @override
  void visitEndElementEvent(XmlEndElementEvent e) => parser._endTag(e);

  @override
  void visitCDATAEvent(XmlCDATAEvent event) {} // coverage:ignore-line

  @override
  void visitCommentEvent(XmlCommentEvent event) {} // coverage:ignore-line

  @override
  void visitDeclarationEvent(
      XmlDeclarationEvent event) {} // coverage:ignore-line

  @override
  void visitDoctypeEvent(XmlDoctypeEvent event) {} // coverage:ignore-line

  @override
  void visitProcessingEvent(XmlProcessingEvent event) {}

  @override
  void visitTextEvent(XmlTextEvent event) {}
}

class StreamAvdParser extends AvdParser {
  final Stream<String> _input;

  StreamAvdParser(this._input, SIBuilder<String, SIImageData> builder)
      : super(builder);

  /// Throws a [ParseError] or other exception in case of error.
  Future<void> parse() {
    final handler = _AvdParserEventHandler(this);
    return _input.toXmlEvents().forEach((el) {
      for (final e in el) {
        handler.visit(e);
      }
    });
  }
}

class StringAvdParser extends AvdParser {
  final String _input;

  StringAvdParser(this._input, SIBuilder<String, SIImageData> builder)
      : super(builder);

  /// Throws a [ParseError] or other exception in case of error.
  void parse() {
    final handler = _AvdParserEventHandler(this);
    for (XmlEvent e in parseEvents(_input)) {
      e.accept(handler);
    }
  }
}

class _DuplicateChecker {
  final _seen = <String>{};

  void check(String name) {
    if (!_seen.add(name)) {
      throw ParseError('Duplicate attribute $name');
    }
  }
}
