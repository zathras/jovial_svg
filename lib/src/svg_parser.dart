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
/// SVG 1.1/Tiny 1.2 parser - it seems the de-facto standard for static
/// SVG images is the intersection of SVG 1.1 and Tiny 1.2, more or less.
/// This implementation will use that as a starting point.
/// cf. https://github.com/w3c/svgwg/issues/199
///
/// Significantly, unlike Tiny, we *do* support the "style=" attribute as an
/// alternative to proper attributes, so as to accept a greater range of
/// SVG 1.1 documents.  We do not support the rest of CSS, however.
///
/// Not implemented:
///    * stroke-dasharray, stroke-dashoffset attributes (cf. Tiny 11.4)
///    * non-scaling stroke (not in SVG 1.1; cf. Tiny 11.5)
///    * Constrained transformations (not in SVG 1.1; cf. Tiny 7.7)
library jovial_svg.svg_parser;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:xml/xml_events.dart';
import 'affine.dart';
import 'common_noui.dart';
import 'svg_graph.dart';

abstract class SvgParser extends GenericParser {
  @override
  final bool warn;
  final SIBuilder<String, SIImageData> _builder;
  String? _currTag;

  final tagsIgnored = <String>{};
  final attributesIgnored = <String>{};

  final _parentStack = List<SvgGroup>.empty(growable: true);

  SvgText? _currentText;
  SvgGradientNode? _currentGradient;

  ///
  /// The result of parsing.  For SVG files we need to generate an intermediate
  /// parse graph so that references can be resolved. See [SvgParseGraph.build].
  ///
  SvgParseGraph? svg;

  SvgParser(this.warn, this._builder);

  void buildResult() {
    final result = svg;
    if (result == null) {
      throw ParseError('No <svg> tag');
    }
    result.build(_builder);
  }

  void _startTag(XmlStartElementEvent evt) {
    try {
      _currTag = evt.name;
      if (evt.name == 'svg') {
        if (svg != null) {
          throw ParseError('Second <svg> tag in file');
        }
        _processSvg(_toMap(evt.attributes));
        if (evt.isSelfClosing) {
          _parentStack.length = _parentStack.length - 1;
        }
      } else if (_parentStack.isEmpty) {
        if (warn) {
          print('    Ignoring ${evt.name} outside of <svg></svg>');
        }
      } else if (evt.name == 'g') {
        _processGroup(_toMap(evt.attributes));
        if (evt.isSelfClosing) {
          _parentStack.length = _parentStack.length - 1;
        }
      } else if (evt.name == 'defs') {
        _processDefs(_toMap(evt.attributes));
        if (evt.isSelfClosing) {
          _parentStack.length = _parentStack.length - 1;
        }
      } else if (evt.name == 'symbol') {
        _processSymbol(_toMap(evt.attributes));
        if (evt.isSelfClosing) {
          _parentStack.length -= 2;
        }
      } else if (evt.name == 'mask') {
        _processMask(_toMap(evt.attributes));
        if (evt.isSelfClosing) {
          _parentStack.length = _parentStack.length - 1;
        }
      } else if (evt.name == 'clipPath') {
        _processClipPath(_toMap(evt.attributes));
        if (evt.isSelfClosing) {
          _parentStack.length = _parentStack.length - 1;
        }
      } else if (evt.name == 'path') {
        _processPath(_toMap(evt.attributes));
      } else if (evt.name == 'rect') {
        _processRect(_toMap(evt.attributes));
      } else if (evt.name == 'circle') {
        _processCircle(_toMap(evt.attributes));
      } else if (evt.name == 'ellipse') {
        _processEllipse(_toMap(evt.attributes));
      } else if (evt.name == 'line') {
        _processLine(_toMap(evt.attributes));
      } else if (evt.name == 'polyline') {
        _processPoly(false, _toMap(evt.attributes));
      } else if (evt.name == 'polygon') {
        _processPoly(true, _toMap(evt.attributes));
      } else if (evt.name == 'image') {
        _processImage(_toMap(evt.attributes));
      } else if (evt.name == 'text') {
        _currentText = _processText(_toMap(evt.attributes));
        if (evt.isSelfClosing) {
          _currentText = null;
        }
      } else if (evt.name == 'linearGradient') {
        _currentGradient = _processLinearGradient(_toMap(evt.attributes));
        if (evt.isSelfClosing) {
          _currentGradient = null;
        }
      } else if (evt.name == 'radialGradient') {
        _currentGradient = _processRadialGradient(_toMap(evt.attributes));
        if (evt.isSelfClosing) {
          _currentGradient = null;
        }
      } else if (evt.name == 'stop') {
        _processStop(_toMap(evt.attributes));
      } else if (evt.name == 'use') {
        _processUse(_toMap(evt.attributes));
      } else if (warn && tagsIgnored.add(evt.name)) {
        print('    Ignoring ${evt.name} tag(s)');
      }
    } finally {
      _currTag = null;
    }
  }

  void _textEvent(XmlTextEvent e) {
    _currentText?.appendText(e.text);
  }

  void _endTag(XmlEndElementEvent evt) {
    if (_parentStack.isNotEmpty &&
        (evt.name == 'svg' ||
            evt.name == 'g' ||
            evt.name == 'defs' ||
            evt.name == 'mask' ||
            evt.name == 'clipPath')) {
      _parentStack.length = _parentStack.length - 1;
    } else if (evt.name == 'symbol') {
      _parentStack.length -= 2;
    } else if (evt.name == 'text') {
      _currentText = null;
    } else if (evt.name == 'linearGradient' || evt.name == 'radialGradient') {
      _currentGradient = null;
    }
  }

  void _processSvg(Map<String, String> attrs) {
    attrs.remove('xmlns');
    attrs.remove('xmlns:xlink');
    attrs.remove('version');
    attrs.remove('id');
    double? width = getFloat(attrs.remove('width'));
    double? height = getFloat(attrs.remove('height'));
    final Rectangle<double>? viewbox = getViewbox(attrs.remove('viewbox'));
    final SvgGroup root;
    if (viewbox == null) {
      root = SvgGroup();
    } else {
      final transform = MutableAffine.identity();
      if (width != null && height != null) {
        transform.multiplyBy(MutableAffine.scale(
            width / viewbox.width, height / viewbox.height));
      } else {
        width ??= viewbox.width;
        height ??= viewbox.height;
      }
      transform
          .multiplyBy(MutableAffine.translation(-viewbox.left, -viewbox.top));
      if (transform.isIdentity()) {
        root = SvgGroup();
      } else {
        root = SvgGroup()..transform = transform;
      }
    }
    _processInheritable(root, attrs);
    _warnUnusedAttributes(attrs);
    final r = svg = SvgParseGraph(root, width, height);
    _parentStack.add(r.root);
  }

  void _processGroup(Map<String, String> attrs) {
    final group = SvgGroup();
    _processId(group, attrs);
    _processInheritable(group, attrs);
    _warnUnusedAttributes(attrs);
    _parentStack.last.children.add(group);
    _parentStack.add(group);
  }

  void _processDefs(Map<String, String> attrs) {
    final group = SvgDefs();
    _processId(group, attrs);
    _processInheritable(group, attrs);
    _warnUnusedAttributes(attrs);
    _parentStack.last.children.add(group);
    _parentStack.add(group);
  }

  void _processSymbol(Map<String, String> attrs) {
    double? width = getFloat(attrs.remove('width'));
    double? height = getFloat(attrs.remove('height'));
    final Rectangle<double>? viewbox = getViewbox(attrs.remove('viewbox'));
    _processDefs({});
    _processGroup(attrs);
    SvgGroup us = _parentStack.last;
    if (viewbox == null) {
      return;
    }
    final transform = us.transform ?? MutableAffine.identity();
    if (width != null && height != null) {
      transform.multiplyBy(
          MutableAffine.scale(width / viewbox.width, height / viewbox.height));
    }
    transform
        .multiplyBy(MutableAffine.translation(-viewbox.left, -viewbox.top));
    if (transform.isIdentity()) {
      us.transform = null;
    } else {
      us.transform = transform;
    }
  }

  void _processMask(Map<String, String> attrs) {
    final mask = SvgMask();
    _processId(mask, attrs);
    _processInheritable(mask, attrs);
    final x = getFloat(attrs.remove('x'));
    final y = getFloat(attrs.remove('y'));
    final width = getFloat(attrs.remove('width'));
    final height = getFloat(attrs.remove('height'));
    final bool userSpace = attrs.remove('maskunits') == 'userSpaceOnUse';
    // This defaults to 'objectBoundingBox'
    if (x != null && y != null && width != null && height != null) {
      if (userSpace) {
        mask.bufferBounds = Rectangle(x, y, width, height);
      } else if (warn) {
        print('    objectBoundingBox maskUnits unsupported in $_currTag');
      }
    }
    _warnUnusedAttributes(attrs);
    _parentStack.last.children.add(mask);
    _parentStack.add(mask);
  }

  void _processClipPath(Map<String, String> attrs) {
    final mask = SvgMask();
    _processId(mask, attrs);
    _processInheritable(mask, attrs);
    _warnUnusedAttributes(attrs);
    mask.paint.inClipPath = true;
    _parentStack.last.children.add(mask);
    _parentStack.add(mask);
  }

  void _processPath(Map<String, String> attrs) {
    final d = attrs.remove('d') ?? '';
    final path = SvgPath(d);
    _processId(path, attrs);
    _processInheritable(path, attrs);
    _warnUnusedAttributes(attrs);
    _parentStack.last.children.add(path);
  }

  void _processRect(Map<String, String> attrs) {
    final double x = getFloat(attrs.remove('x')) ?? 0;
    final double y = getFloat(attrs.remove('y')) ?? 0;
    final double width = getFloat(attrs.remove('width')) ?? 0;
    final double height = getFloat(attrs.remove('height')) ?? 0;
    double? rx = getFloat(attrs.remove('rx'));
    double? ry = getFloat(attrs.remove('ry')) ?? rx;
    rx ??= ry;
    if (rx == null) {
      assert(ry == null);
      rx = ry = 0;
    }
    ry!;
    if (rx < 0) {
      rx = ry;
    } else if (ry < 0) {
      ry = rx;
    }
    rx = min(rx, width / 2);
    ry = min(ry, width / 2);
    final rect = SvgRect(x, y, width, height, rx, ry);
    _processId(rect, attrs);
    _processInheritable(rect, attrs);
    _warnUnusedAttributes(attrs);
    _parentStack.last.children.add(rect);
  }

  void _processCircle(Map<String, String> attrs) {
    final double cx = getFloat(attrs.remove('cx')) ?? 0;
    final double cy = getFloat(attrs.remove('cy')) ?? 0;
    final double r = getFloat(attrs.remove('r')) ?? 0;
    final e = SvgEllipse(cx, cy, r, r);
    _processId(e, attrs);
    _processInheritable(e, attrs);
    _warnUnusedAttributes(attrs);
    _parentStack.last.children.add(e);
  }

  void _processEllipse(Map<String, String> attrs) {
    final double cx = getFloat(attrs.remove('cx')) ?? 0;
    final double cy = getFloat(attrs.remove('cy')) ?? 0;
    final double rx = getFloat(attrs.remove('rx')) ?? 0;
    final double ry = getFloat(attrs.remove('ry')) ?? 0;
    final e = SvgEllipse(cx, cy, rx, ry);
    _processId(e, attrs);
    _processInheritable(e, attrs);
    _warnUnusedAttributes(attrs);
    _parentStack.last.children.add(e);
  }

  void _processLine(Map<String, String> attrs) {
    final double x1 = getFloat(attrs.remove('x1')) ?? 0;
    final double y1 = getFloat(attrs.remove('y1')) ?? 0;
    final double x2 = getFloat(attrs.remove('x2')) ?? 0;
    final double y2 = getFloat(attrs.remove('y2')) ?? 0;
    final line = SvgPoly(false, [Point(x1, y1), Point(x2, y2)]);
    _processId(line, attrs);
    _processInheritable(line, attrs);
    _warnUnusedAttributes(attrs);
    _parentStack.last.children.add(line);
  }

  void _processPoly(bool close, Map<String, String> attrs) {
    final str = attrs.remove('points') ?? '';
    final lex = BnfLexer(str);
    final pts = lex.getFloatList();
    if (!lex.eof) {
      throw ParseError('Unexpected characters at end of points:  $str');
    }
    if (pts.length % 2 != 0) {
      throw ParseError('Odd number of points to polyline or polygon');
    }
    final points = List<Point<double>>.empty(growable: true);
    for (int i = 0; i < pts.length; i += 2) {
      points.add(Point(pts[i], pts[i + 1]));
    }
    final line = SvgPoly(close, points);
    _processId(line, attrs);
    _processInheritable(line, attrs);
    _warnUnusedAttributes(attrs);
    _parentStack.last.children.add(line);
  }

  static final _whitespace = RegExp(r'\s+');

  void _processImage(Map<String, String> attrs) {
    final image = SvgImage();
    image.x = getFloat(attrs.remove('x')) ?? image.x;
    image.y = getFloat(attrs.remove('y')) ?? image.y;
    image.width = getFloat(attrs.remove('width')) ?? image.width;
    image.height = getFloat(attrs.remove('height')) ?? image.height;
    String? data = attrs.remove('xlink:href');
    if (data != null) {
      // Remove spaces, newlines, etc.
      final uri = Uri.parse(data.replaceAll(_whitespace, ''));
      final uData = uri.data;
      if (uData == null) {
        throw ParseError('Invalid data: URI:  $data');
      } else {
        image.imageData = uData.contentAsBytes();
      }
    }
    _processId(image, attrs);
    _processInheritable(image, attrs);
    _warnUnusedAttributes(attrs);
    _parentStack.last.children.add(image);
  }

  SvgText _processText(Map<String, String> attrs) {
    final n = SvgText();
    n.x = getFloatList(attrs.remove('x')) ?? n.x;
    n.y = getFloatList(attrs.remove('y')) ?? n.y;
    _processId(n, attrs);
    _processInheritable(n, attrs);
    _warnUnusedAttributes(attrs);
    _parentStack.last.children.add(n);
    return n;
  }

  SvgCoordinate? _getCoordinate(String? attr) {
    bool isPercent = false;
    double? val = getFloat(attr, percent: (v) {
      isPercent = true;
      return v;
    });
    if (val == null) {
      return null;
    } else if (isPercent) {
      return SvgCoordinate.percent(val);
    } else {
      return SvgCoordinate.value(val);
    }
  }

  SvgGradientNode _processLinearGradient(Map<String, String> attrs) {
    final String? parentID = _getHref(attrs);
    final x1 = _getCoordinate(attrs.remove('x1'));
    final x2 = _getCoordinate(attrs.remove('x2'));
    final y1 = _getCoordinate(attrs.remove('y1'));
    final y2 = _getCoordinate(attrs.remove('y2'));
    final sgu = attrs.remove('gradientunits');
    final bool? objectBoundingBox =
        (sgu == null) ? null : sgu != 'userSpaceOnUse';
    final MutableAffine? transform =
        getTransform(null, attrs.remove('gradienttransform'));
    final spreadMethod = getSpreadMethod(attrs.remove('spreadmethod'));
    final n = SvgGradientNode(
        parentID,
        SvgLinearGradientColor(
            x1: x1,
            x2: x2,
            y1: y1,
            y2: y2,
            objectBoundingBox: objectBoundingBox,
            transform: transform,
            spreadMethod: spreadMethod));
    _processId(n, attrs);
    _warnUnusedAttributes(attrs);
    _parentStack.last.children.add(n);
    return n;
  }

  static double _percentOK(double val) => val / 100;

  SvgGradientNode _processRadialGradient(Map<String, String> attrs) {
    final String? parentID = _getHref(attrs);
    final cx = _getCoordinate(attrs.remove('cx'));
    final cy = _getCoordinate(attrs.remove('cy'));
    final fx = _getCoordinate(attrs.remove('fx'));
    final fy = _getCoordinate(attrs.remove('fy'));
    final r = _getCoordinate(attrs.remove('r'));
    final sgu = attrs.remove('gradientunits');
    final bool? objectBoundingBox =
        (sgu == null) ? null : sgu != 'userSpaceOnUse';
    final MutableAffine? transform =
        getTransform(null, attrs.remove('gradienttransform'));
    final spreadMethod = getSpreadMethod(attrs.remove('spreadmethod'));
    final n = SvgGradientNode(
        parentID,
        SvgRadialGradientColor(
            cx: cx,
            cy: cy,
            fx: fx,
            fy: fy,
            r: r,
            objectBoundingBox: objectBoundingBox,
            transform: transform,
            spreadMethod: spreadMethod));
    _processId(n, attrs);
    _warnUnusedAttributes(attrs);
    _parentStack.last.children.add(n);
    return n;
  }

  SIGradientSpreadMethod? getSpreadMethod(String? s) {
    if (s == null) {
      return null;
    } else if (s == 'reflect') {
      return SIGradientSpreadMethod.reflect;
    } else if (s == 'repeat') {
      return SIGradientSpreadMethod.repeat;
    } else {
      return SIGradientSpreadMethod.pad;
    }
  }

  void _processStop(Map<String, String> attrs) {
    final g = _currentGradient;
    if (g == null) {
      throw ParseError('<stop> outside of gradient');
    }

    //default stop-color is 'black'. Ref https://developer.mozilla.org/en-US/docs/Web/SVG/Attribute/stop-color
    final SvgColor color =
        getSvgColor(attrs.remove('stop-color')?.trim() ?? 'black');
    if (color != SvgColor.inherit &&
        color != SvgColor.currentColor &&
        color is! SvgValueColor) {
      throw ParseError('Illegal color value for gradient stop:  $color');
    }
    int alpha = getAlpha(attrs.remove('stop-opacity')) ?? 0xff;
    double offset =
        (getFloat(attrs.remove('offset'), percent: _percentOK) ?? 0.0)
            .clamp(0.0, 1.0);
    if (g.gradient.stops?.isNotEmpty == true) {
      final minOffset = g.gradient.stops!.last.offset;
      offset = max(offset, minOffset);
    }
    g.gradient.addStop(SvgGradientStop(offset, color, alpha));
  }

  void _processUse(Map<String, String> attrs) {
    final href = _getHref(attrs);
    final use = SvgUse(href);
    _processId(use, attrs);
    _processInheritable(use, attrs);
    final x = getFloat(attrs.remove('x'));
    final y = getFloat(attrs.remove('y'));
    attrs.remove('width'); // Meaningless, but harmless
    attrs.remove('height'); // Meaningless, but harmless
    if (x != null || y != null) {
      final xform = use.transform;
      final translate = MutableAffine.translation(x ?? 0, y ?? 0);
      if (xform == null) {
        use.transform = translate;
      } else {
        xform.multiplyBy(translate);
      }
    }
    _warnUnusedAttributes(attrs);
    _parentStack.last.children.add(use);
  }

  String? _getHref(Map<String, String> attrs) {
    final href = attrs.remove('xlink:href') ?? attrs.remove('href');
    // Just 'href' is wrong, but browsers seem to buy it
    if (href == null) {
      return href;
    }
    if (!href.startsWith('#')) {
      throw ParseError('xlink:href does not start with "#"');
    }
    return href.substring(1);
  }

  void _processId(SvgNode n, Map<String, String> attrs) {
    final id = attrs.remove('id') ?? attrs.remove('xml:id');
    if (id != null) {
      svg!.idLookup[id] = n;
    }
  }

  void _processInheritable(
      SvgInheritableAttributes node, Map<String, String> attrs) {
    node.display = attrs.remove('display') != 'none';
    final SvgPaint p = node.paint;
    p.currentColor = getSvgColor(attrs.remove('color')?.trim());
    p.fillColor = getSvgColor(attrs.remove('fill')?.trim());
    p.fillAlpha = getAlpha(attrs.remove('fill-opacity'));
    p.fillType = getFillType(attrs.remove('fill-rule'));
    p.clipFillType = getFillType(attrs.remove('clip-rule'));
    String? mask = attrs.remove('mask') ?? attrs.remove('clip-path');
    if (mask != null) {
      if (mask.startsWith('url(') && mask.endsWith(')')) {
        mask = mask.substring(4, mask.length - 1).trim();
        if (mask.startsWith('#')) {
          mask = mask.substring(1).trim();
        }
      }
    }
    p.mask = mask;
    String? visibility = attrs.remove('visibility');
    if (visibility != null) {
      p.hidden = visibility == 'hidden' || visibility == 'collapse';
    }
    p.strokeColor = getSvgColor(attrs.remove('stroke')?.trim());
    p.strokeAlpha = getAlpha(attrs.remove('stroke-opacity'));
    p.strokeWidth = getFloat(attrs.remove('stroke-width'));
    p.strokeCap = getStrokeCap(attrs.remove('stroke-linecap'));
    p.strokeJoin = getStrokeJoin(attrs.remove('stroke-linejoin'));
    p.strokeMiterLimit = getFloat(attrs.remove('stroke-miterlimit'));
    p.strokeDashArray = getFloatList(attrs.remove('stroke-dasharray'));
    p.strokeDashOffset = getFloat(attrs.remove('stroke-dashoffset'));
    node.groupAlpha = getAlpha(attrs.remove('opacity'));
    if (node.groupAlpha == 0xff) {
      node.groupAlpha = null;
    }
    final SvgTextAttributes t = node.textAttributes;
    t.fontFamily = attrs.remove('font-family');

    String? attr = attrs.remove('font-style')?.toLowerCase();
    if (attr == null || attr == 'inherit') {
      // Let it stay at null
    } else {
      const vals = {
        'normal': SIFontStyle.normal,
        'italic': SIFontStyle.italic,
        'oblique': SIFontStyle.italic,
      };
      final v = vals[attr];
      if (v != null) {
        t.fontStyle = v;
      } else if (warn) {
        print('    Ignoring invalid fontStyle "$attr"');
      }
    }

    attr = attrs.remove('font-weight')?.toLowerCase();
    if (attr == null || attr == 'inherit') {
      // Let it stay at inherit
    } else {
      const vals = {
        'normal': SvgFontWeight.w400,
        'bold': SvgFontWeight.w700,
        '100': SvgFontWeight.w100,
        '200': SvgFontWeight.w200,
        '300': SvgFontWeight.w300,
        '400': SvgFontWeight.w400,
        '500': SvgFontWeight.w500,
        '600': SvgFontWeight.w600,
        '700': SvgFontWeight.w700,
        '800': SvgFontWeight.w800,
        '900': SvgFontWeight.w900,
        'bolder': SvgFontWeight.bolder,
        'lighter': SvgFontWeight.lighter,
      };
      final v = vals[attr];
      if (v != null) {
        t.fontWeight = v;
      } else if (warn) {
        print('    Ignoring invalid fontStyle "$attr"');
      }
    }

    attr = attrs.remove('font-size')?.toLowerCase();
    if (attr == null || attr == 'inherit') {
      // Let it stay at inherit
    } else {
      const vals = {
        'xx-small': SvgFontSize.xx_small,
        'x-small': SvgFontSize.x_small,
        'small': SvgFontSize.small,
        'medium': SvgFontSize.medium,
        'large': SvgFontSize.large,
        'x-large': SvgFontSize.x_large,
        'xx-large': SvgFontSize.xx_large,
        'larger': SvgFontSize.larger,
        'smaller': SvgFontSize.smaller,
      };
      final v = vals[attr];
      if (v != null) {
        t.fontSize = v;
      } else {
        double? d = getFloat(attr);
        if (d != null) {
          t.fontSize = SvgFontSize.absolute(d);
        } else if (warn) {
          print('    Ignoring invalid fontStyle "$attr"');
        }
      }
    }

    attr = attrs.remove('text-anchor')?.toLowerCase();
    if (attr == null || attr == 'inherit') {
      // Let it stay at null
    } else {
      const vals = {
        'start': SITextAnchor.start,
        'middle': SITextAnchor.middle,
        'end': SITextAnchor.end
      };
      final v = vals[attr];
      if (v != null) {
        t.textAnchor = v;
      } else if (warn) {
        print('    Ignoring invalid fontStyle "$attr"');
      }
    }

    attr = attrs.remove('text-decoration');
    if (attr == null || attr == 'inherit') {
      // Let it stay at null
    } else {
      const vals = {
        'none': SITextDecoration.none,
        'underline': SITextDecoration.underline,
        'overline': SITextDecoration.overline,
        'line-through': SITextDecoration.lineThrough,
      };
      final v = vals[attr];
      if (v != null) {
        t.textDecoration = v;
      } else if (warn) {
        print('    Ignoring invalid textDecoration "$attr"');
      }
    }

    node.transform = getTransform(node.transform, attrs.remove('transform'));

    attr = attrs.remove('mix-blend-mode');
    {
      const vals = {
        null: SIBlendMode.normal,
        'inherit': SIBlendMode.normal,
        'normal': SIBlendMode.normal,
        'multiply': SIBlendMode.multiply,
        'screen': SIBlendMode.screen,
        'overlay': SIBlendMode.overlay,
        'darken': SIBlendMode.darken,
        'lighten': SIBlendMode.lighten,
        'color-dodge': SIBlendMode.colorDodge,
        'color-burn': SIBlendMode.colorBurn,
        'hard-light': SIBlendMode.hardLight,
        'soft-light': SIBlendMode.softLight,
        'difference': SIBlendMode.difference,
        'exclusion': SIBlendMode.exclusion,
        'hue': SIBlendMode.hue,
        'saturation': SIBlendMode.saturation,
        'color': SIBlendMode.color,
        'luminosity': SIBlendMode.luminosity
      };
      final v = vals[attr];
      if (v != null) {
        node.blendMode = v;
      } else if (warn) {
        print('    Ignoring invalid mix-blend-mode "$attr"');
      }
    }
  }

  MutableAffine? getTransform(MutableAffine? initial, String? s) {
    if (s == null) {
      return initial;
    }
    final result = initial ?? MutableAffine.identity();
    final lexer = BnfLexer(s.toLowerCase());
    for (;;) {
      final t = lexer.tryNextIdentifier();
      if (t == null) {
        break;
      }
      final args = getTransformArgs(lexer.getNextFunctionArgs());
      if (t == 'matrix') {
        if (args.length == 6) {
          result.multiplyBy(MutableAffine.cssTransform(args));
          continue;
        }
      } else if (t == 'translate') {
        if (args.length == 1) {
          result.multiplyBy(MutableAffine.translation(args[0], 0));
          continue;
        } else if (args.length == 2) {
          result.multiplyBy(MutableAffine.translation(args[0], args[1]));
          continue;
        }
      } else if (t == 'scale') {
        if (args.length == 1) {
          result.multiplyBy(MutableAffine.scale(args[0], args[0]));
          continue;
        } else if (args.length == 2) {
          result.multiplyBy(MutableAffine.scale(args[0], args[1]));
          continue;
        }
      } else if (t == 'rotate') {
        if (args.length == 1 || args.length == 3) {
          if (args.length == 3) {
            result.multiplyBy(MutableAffine.translation(args[1], args[2]));
          }
          result.multiplyBy(MutableAffine.rotation(args[0] * pi / 180));
          if (args.length == 3) {
            result.multiplyBy(MutableAffine.translation(-args[1], -args[2]));
          }
          continue;
        }
      } else if (t == 'skewx') {
        if (args.length == 1) {
          result.multiplyBy(MutableAffine.skewX(args[0]));
          continue;
        }
      } else if (t == 'skewy') {
        if (args.length == 1) {
          result.multiplyBy(MutableAffine.skewY(args[0]));
          continue;
        }
      }
      throw ParseError('Unrecognized transform $t');
    }
    if (!lexer.eof) {
      throw ParseError('Unexpected characters at end of transfrom $s');
    }
    if (result.isIdentity()) {
      return null;
    } else {
      return result;
    }
  }

  List<double> getTransformArgs(String s) {
    final lex = BnfLexer(s);
    final result = lex.getFloatList();
    if (!lex.eof) {
      throw ParseError('Unrecognized text at end of transform args:  $s');
    }
    return result;
  }

  void _warnUnusedAttributes(Map<String, String> attrs) {
    for (final a in attrs.keys) {
      if (warn && attributesIgnored.add('$_currTag:$a')) {
        print('    Ignoring $a attribute(s) in $_currTag');
      }
    }
  }

  ///
  /// Convert attrs to a map, and also interpret the style attribute's content
  /// as attributes, that get added to the map.  The style attribute isn't
  /// part of Tiny, but its use is common.
  ///
  Map<String, String> _toMap(Iterable<XmlEventAttribute> attrs) {
    final map = HashMap<String, String>();
    for (final a in attrs) {
      map[a.name.toLowerCase()] = a.value;
    }
    final style = map.remove('style');
    if (style != null) {
      for (String el in style.split(';')) {
        el = el.trim();
        if (el == '') {
          continue;
        }
        int pos = el.indexOf(':');
        if (pos == -1) {
          throw ParseError('Syntax error in style attribute "$style"');
        }
        final key = el.substring(0, pos).trim();
        if (map.containsKey(key)) {
          if (warn) {
            print('    Ignoring duplicate style attribute $key');
          }
        } else {
          map[key] = el.substring(pos + 1).trim();
        }
      }
    }
    return map;
  }

  SvgColor getSvgColor(String? s) {
    final lc = s?.toLowerCase();
    if (s == null || lc == null || lc == 'inherit') {
      return SvgColor.inherit;
    } else if (lc == 'none') {
      return SvgColor.none;
    } else if (lc == 'currentcolor') {
      return SvgColor.currentColor;
    } else if (s.startsWith('url(') && s.endsWith(')')) {
      s = s.substring(5, s.length - 1).trim();
      return SvgColor.reference(s);
    } else {
      return SvgColor.value(super.getColor(lc));
    }
  }
}

class _SvgParserEventHandler with XmlEventVisitor {
  final SvgParser parser;

  _SvgParserEventHandler(this.parser);

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
  void visitTextEvent(XmlTextEvent event) => parser._textEvent(event);
}

class StreamSvgParser extends SvgParser {
  final Stream<String> _input;

  StreamSvgParser(this._input, SIBuilder<String, SIImageData> builder,
      {bool warn = true})
      : super(warn, builder);

  static StreamSvgParser fromByteStream(
          Stream<List<int>> input, SIBuilder<String, SIImageData> builder) =>
      StreamSvgParser(input.transform(utf8.decoder), builder);

  /// Throws a [ParseError] or other exception in case of error.
  Future<void> parse() async {
    final handler = _SvgParserEventHandler(this);
    await _input.toXmlEvents().forEach((el) {
      for (final e in el) {
        handler.visit(e);
      }
    });
    buildResult();
  }
}

class StringSvgParser extends SvgParser {
  final String _input;

  StringSvgParser(this._input, SIBuilder<String, SIImageData> builder,
      {bool warn = true})
      : super(warn, builder);

  /// Throws a [ParseError] or other exception in case of error.
  void parse() {
    final handler = _SvgParserEventHandler(this);
    for (XmlEvent e in parseEvents(_input)) {
      e.accept(handler);
    }
    buildResult();
  }
}
