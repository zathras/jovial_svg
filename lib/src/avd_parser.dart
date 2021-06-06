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
/// Android Vector Drawable parser
///
library jovial_svg.avd.parser;

import 'dart:convert';
import 'dart:math';

import 'package:xml/xml_events.dart';
import 'dart:async';
import 'affine.dart';
import 'common_noui.dart';

///
/// Parse an Android Vector Drawable XML file.  The file format is
/// somewhat informally specified at
/// https://developer.android.com/guide/topics/graphics/vector-drawable-resources
/// and https://developer.android.com/reference/android/graphics/drawable/VectorDrawable
///
abstract class AvdParser extends GenericParser {
  final SIBuilder builder;

  AvdParser(this.builder);

  final _tagStack = List<String>.empty(growable: true);
  bool _vectorStarted = false;
  bool _done = false;

  @override
  bool get warn => builder.warn;

  void _startTag(XmlStartElementEvent evt) {
    // TODO:  Gradients
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
        builder.endVector();
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
        builder.endGroup(null);
      } else {
        _tagStack.add('group');
      }
    } else if (evt.name == 'path') {
      _parsePath(evt.attributes);
      if (!evt.isSelfClosing) {
        _tagStack.add('path');
      }
    } else if (evt.name == 'clip-path') {
      if (_tagStack.isEmpty || _tagStack.last != 'group') {
        throw ParseError('clip-path only valid inside a group:  $evt');
      }
      _parseClipPath(evt.attributes);
      if (!evt.isSelfClosing) {
        _tagStack.add('path');
      }
    } else {
      throw ParseError('Unexpected tag inside vector:  $evt');
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
      builder.endVector();
    } else if (_tagStack.isEmpty) {
      throw ParseError('Unexpected end tag $evt');
    } else if (_tagStack.last != evt.name) {
      throw ParseError('Expected </${_tagStack.last}>, got $evt');
    } else {
      if (evt.name == 'group') {
        builder.endGroup(null);
      }
      _tagStack.removeLast();
    }
  }

  void _parseVector(List<XmlEventAttribute> attrs) {
    double? width;
    double? height;
    int? tintColor;
    SITintMode? tintMode;

    for (final a in attrs) {
      if (a.name == 'andoird:autoMirrored' || a.name == 'android:alpha') {
        if (warn) {
          print('   (ignoring ${a.name} ${a.value}.)');
        }
        // These parameters control how an AVD interacts with other graphical
        // elements, and they would require rendering the AVD to its own
        // layer.  If this kind of effect is desired, it's best to do it
        // externally, with the SI just serving as a scalable image that can
        // be used by the surrounding program.
      } else if (a.name == 'android:name') {
        // don't care
      } else if (a.name == 'android:width') {
        width = getFloat(a.value);
      } else if (a.name == 'android:height') {
        height = getFloat(a.value);
      } else if (a.name == 'android:viewportWidth') {
        width ??= getFloat(a.value);
      } else if (a.name == 'android:viewportHeight') {
        height ??= getFloat(a.value);
      } else if (a.name == 'android:tint') {
        tintColor = getColor(a.value.trim().toLowerCase());
      } else if (a.name == 'android:tintMode') {
        tintMode = _getTintMode(a.value);
      }
    }
    builder.vector(
        width: width, height: height, tintColor: tintColor, tintMode: tintMode);
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
        throw ParseError('Unexpected attribute $a');
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

    throw UnimplementedError("@@ TODO");
    // builder.group(null, (transform.isIdentity()) ? null : transform);
  }

  void _parsePath(List<XmlEventAttribute> attrs) {
    int? fillColor;
    int? strokeColor;
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
        fillColor = getColor(a.value.trim().toLowerCase());
      } else if (a.name == 'android:strokeColor') {
        strokeColor = getColor(a.value.trim().toLowerCase());
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
        fillType = getFillType(a.value);
      } else if (a.name == 'android:trimPathStart' ||
          a.name == 'android:trimPathEnd' ||
          a.name == 'android:trimPathOffset') {
        if (warn && !warnedAbout.contains('android:trimPath')) {
          warnedAbout.add('android:trimPath');
          print('    (ignoring animation attributes android:trimPathXXX)');
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
        throw ParseError('Unexpected attribute $a');
      }
    }
    if (pathData == null) {
      if (warn) {
        print('    Path with no android:pathData - ignored');
      }
    } else {
      if (strokeAlpha != null && strokeColor != null) {
        strokeColor = (strokeColor & 0xffffff) | (strokeAlpha << 24);
      }
      if (fillAlpha != null && fillColor != null) {
        fillColor = (fillColor & 0xffffff) | (fillAlpha << 24);
      }
      if (fillColor != null || strokeColor != null) {
        builder.path(
            null,
            pathData,
            SIPaint(
                fillColor: (fillColor == null)
                    ? SIColor.none
                    : SIValueColor(fillColor),
                strokeColor: (strokeColor == null)
                    ? SIColor.none
                    : SIValueColor(strokeColor),
                strokeWidth: strokeWidth,
                strokeMiterLimit: strokeMiterLimit,
                strokeJoin: strokeJoin,
                strokeCap: strokeCap,
                fillType: fillType,
                strokeDashArray: null,
                strokeDashOffset: null));
      }
    }
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
        throw ParseError('Unexpected attribute $a');
      }
      if (pathData == null) {
        if (warn) {
          print('    clip path with no android:pathData - ignored');
        }
      } else {
        builder.clipPath(null, pathData);
      }
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
}

class _AvdParserEventHandler with XmlEventVisitor {
  final AvdParser parser;

  _AvdParserEventHandler(this.parser);

  @override
  void visitStartElementEvent(XmlStartElementEvent e) => parser._startTag(e);

  @override
  void visitEndElementEvent(XmlEndElementEvent e) => parser._endTag(e);

  @override
  void visitCDATAEvent(XmlCDATAEvent event) {}

  @override
  void visitCommentEvent(XmlCommentEvent event) {}

  @override
  void visitDeclarationEvent(XmlDeclarationEvent event) {}

  @override
  void visitDoctypeEvent(XmlDoctypeEvent event) {}

  @override
  void visitProcessingEvent(XmlProcessingEvent event) {}

  @override
  void visitTextEvent(XmlTextEvent event) {}
}

class StreamAvdParser extends AvdParser {
  final Stream<String> _input;

  StreamAvdParser(this._input, SIBuilder builder) : super(builder);

  static StreamAvdParser fromByteStream(
          Stream<List<int>> input, SIBuilder builder) =>
      StreamAvdParser(input.transform(utf8.decoder), builder);

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

  StringAvdParser(this._input, SIBuilder builder) : super(builder);

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
