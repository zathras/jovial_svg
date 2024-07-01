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
import 'dart:math';
import 'dart:typed_data';

import 'package:xml/xml_events.dart';
import 'affine.dart';
import 'common_noui.dart';
import 'svg_graph.dart';

abstract class SvgParser extends GenericParser {
  @override
  final void Function(String) warn;
  final List<Pattern> exportedIDs;
  final SIBuilder<String, SIImageData>? _builder;
  String? _currTag;

  final tagsIgnored = <String>{};
  final attributesIgnored = <String>{};

  final List<SvgGroup> _parentStack = [];
  final List<_TagEntry> _tagStack = [];

  // Size of our viewbox, for measurements with percentage units.  This isn't
  // adjusted for transforms -- Tiny doesn't mention anything about doing such
  // transforms.  cf. Tiny s. 7.10.  100x100 is just a default to use if the
  // SVG doesn't specify a viewport or a width/height.
  double _widthForPercentages = 100;
  double _heightForPercentages = 100;

  _TextBuilder? _currentText;
  StringBuffer? _currentStyle; // Within a style tag
  SvgGradientNode? _currentGradient;

  ///
  /// The result of parsing.  For SVG files we need to generate an intermediate
  /// parse graph so that references can be resolved. See `SvgParseGraph._build`.
  ///
  late final SvgDOM svg;
  late final Map<String, SvgNode> idLookup;
  bool _svgTagSeen = false;

  /// Stylesheet.  Key is element type, or ID.  ID starts with '#'.
  /// See style.uml in doc/uml.
  final Stylesheet _stylesheet = {};

  SvgParser(this.warn, this.exportedIDs, this._builder);

  void buildResult() {
    SvgDOMNotExported.setIDLookup(svg, idLookup);
    if (!_svgTagSeen) {
      throw ParseError('No <svg> tag');
    }
    final b = _builder;
    if (b != null) {
      SvgDOMNotExported.build(svg, b);
    }
  }

  void _startTag(XmlStartElementEvent evt) {
    final String evtName = evt.localName;
    _tagStack.add(_TagEntry(_parentStack.length, evtName));
    try {
      _currTag = evtName;
      if (evtName == 'svg') {
        if (_svgTagSeen) {
          throw ParseError('Second <svg> tag in file');
        }
        _processSvg(_toMap(evt.attributes));
      } else if (_parentStack.isEmpty) {
        warn('    Ignoring $evtName outside of <svg></svg>');
      } else if (evtName == 'g') {
        _processGroup(_toMap(evt.attributes));
      } else if (evtName == 'defs') {
        _processDefs(_toMap(evt.attributes), 'defs');
      } else if (evtName == 'symbol') {
        _processSymbol(_toMap(evt.attributes));
      } else if (evtName == 'mask') {
        _processMask(_toMap(evt.attributes));
      } else if (evtName == 'clipPath') {
        _processClipPath(_toMap(evt.attributes));
      } else if (evtName == 'path') {
        _processPath(_toMap(evt.attributes));
      } else if (evtName == 'rect') {
        _processRect(_toMap(evt.attributes));
      } else if (evtName == 'circle') {
        _processCircle(_toMap(evt.attributes));
      } else if (evtName == 'ellipse') {
        _processEllipse(_toMap(evt.attributes));
      } else if (evtName == 'line') {
        _processLine(_toMap(evt.attributes));
      } else if (evtName == 'polyline') {
        _processPoly('polyline', false, _toMap(evt.attributes));
      } else if (evtName == 'polygon') {
        _processPoly('polygon', true, _toMap(evt.attributes));
      } else if (evtName == 'image') {
        _processImage(_toMap(evt.attributes));
      } else if (evtName == 'text') {
        _currentText = _processText(_toMap(evt.attributes));
        if (evt.isSelfClosing) {
          _currentText = null;
        }
      } else if (evtName == 'tspan') {
        final span = _currentText?.startSpan();
        if (span != null) {
          _processTextSpan(span, _toMap(evt.attributes));
        } else {
          warn('Ignoring stray tspan tag');
        }
        if (evt.isSelfClosing) {
          _currentText?.endSpan();
        }
      } else if (evtName == 'style') {
        if (!evt.isSelfClosing) {
          _currentStyle = StringBuffer();
        }
      } else if (evtName == 'linearGradient') {
        _currentGradient = _processLinearGradient(_toMap(evt.attributes));
        if (evt.isSelfClosing) {
          _currentGradient = null;
        }
      } else if (evtName == 'radialGradient') {
        _currentGradient = _processRadialGradient(_toMap(evt.attributes));
        if (evt.isSelfClosing) {
          _currentGradient = null;
        }
      } else if (evtName == 'stop') {
        _processStop(_toMap(evt.attributes));
      } else if (evtName == 'use') {
        _processUse(_toMap(evt.attributes));
      } else if (tagsIgnored.add(evtName)) {
        warn('    Ignoring $evtName tag(s)');
      }
    } catch (e) {
      warn(e.toString());
    } finally {
      if (evt.isSelfClosing) {
        _parentStack.length = _tagStack.last.parentPos;
        _tagStack.length--;
      }
      _currTag = null;
    }
  }

  void _textEvent(String text) {
    _currentText?.appendText(text);
    _currentStyle?.write(text);
  }

  void _endTag(XmlEndElementEvent evt) {
    final evtName = evt.localName;
    bool found = false;
    for (int i = _tagStack.length - 1; i >= 0; i--) {
      final tse = _tagStack[i];
      if (tse.tag == evtName) {
        found = true;
        _parentStack.length = tse.parentPos;
        _tagStack.length = i;
        break;
      }
      warn('Expected </${tse.tag}>, saw </$evtName>');
    }
    if (!found) {
      warn('</$evtName> with no corresponding start tag');
      return;
    }
    if (evtName == 'text') {
      _currentText = null;
    } else if (evtName == 'style' && _currentStyle != null) {
      _processStyle(_currentStyle.toString());
      _currentStyle = null;
    } else if (evtName == 'tspan') {
      _currentText?.endSpan();
    } else if (evtName == 'linearGradient' || evtName == 'radialGradient') {
      _currentGradient = null;
    }
  }

  void _processSvg(Map<String, String> attrs) {
    attrs.remove('xmlns');
    attrs.remove('xlink');
    attrs.remove('version');
    attrs.remove('id');
    double? width = getFloat(attrs.remove('width'));
    double? height = getFloat(attrs.remove('height'));
    final Rectangle<double>? viewbox = getViewbox(attrs.remove('viewbox'));
    final SvgRoot root;
    if (viewbox == null) {
      _widthForPercentages = width ?? _widthForPercentages;
      _heightForPercentages = height ?? _heightForPercentages;
      root = SvgRoot();
    } else {
      _widthForPercentages = viewbox.width;
      _heightForPercentages = viewbox.height;
      final transform = MutableAffine.identity();
      if (width != null && height != null) {
        final sx = width / viewbox.width;
        final sy = height / viewbox.height;
        if (sx < sy) {
          final dy = (height - height * sx / sy) / 2;
          transform.multiplyBy(MutableAffine.translation(0, dy));
          transform.multiplyBy(MutableAffine.scale(sx, sx));
        } else if (sx > sy) {
          final dx = (width - width * sy / sx) / 2;
          transform.multiplyBy(MutableAffine.translation(dx, 0));
          transform.multiplyBy(MutableAffine.scale(sy, sy));
        } else {
          transform.multiplyBy(MutableAffine.scale(sx, sy));
        }
      } else {
        width ??= viewbox.width;
        height ??= viewbox.height;
      }
      transform
          .multiplyBy(MutableAffine.translation(-viewbox.left, -viewbox.top));
      if (transform.isIdentity()) {
        root = SvgRoot();
      } else {
        root = SvgRoot()..transform = transform;
      }
    }
    _processInheritable(root, attrs);
    _warnUnusedAttributes(attrs);
    final r = svg = SvgDOM(root, _stylesheet, width, height, null, null);
    idLookup = {};
    _svgTagSeen = true;
    _parentStack.add(r.root);
  }

  void _processGroup(Map<String, String> attrs, [SvgGroup? group]) {
    group ??= SvgGroup();
    _processId(group, attrs);
    _processInheritable(group, attrs);
    _warnUnusedAttributes(attrs);
    _parentStack.last.children.add(group);
    _parentStack.add(group);
  }

  void _processDefs(Map<String, String> attrs, String tagName) {
    final group = SvgDefs(tagName);
    _processId(group, attrs);
    _processInheritable(group, attrs);
    _warnUnusedAttributes(attrs);
    _parentStack.last.children.add(group);
    _parentStack.add(group);
  }

  void _processSymbol(Map<String, String> attrs) {
    final us = SvgSymbol();
    final width =
        us.width = getFloat(attrs.remove('width'), percent: _widthPercent);
    final height =
        us.height = getFloat(attrs.remove('height'), percent: _heightPercent);
    final viewbox = us.viewbox = getViewbox(attrs.remove('viewbox'));
    _processDefs({}, 'symbol');
    _processGroup(attrs, us);
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
    final x = getFloat(attrs.remove('x'), percent: _widthPercent);
    final y = getFloat(attrs.remove('y'), percent: _heightPercent);
    final width = getFloat(attrs.remove('width'), percent: _widthPercent);
    final height = getFloat(attrs.remove('height'), percent: _heightPercent);
    final bool userSpace = attrs.remove('maskunits') == 'userSpaceOnUse';
    // This defaults to 'objectBoundingBox'
    if (x != null && y != null && width != null && height != null) {
      if (userSpace) {
        mask.bufferBounds = Rectangle(x, y, width, height);
      } else {
        warn('    objectBoundingBox maskUnits unsupported in $_currTag');
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
    final double x = getFloat(attrs.remove('x'), percent: _widthPercent) ?? 0;
    final double y = getFloat(attrs.remove('y'), percent: _heightPercent) ?? 0;
    final double width =
        getFloat(attrs.remove('width'), percent: _widthPercent) ?? 0;
    final double height =
        getFloat(attrs.remove('height'), percent: _heightPercent) ?? 0;
    double? rx = getFloat(attrs.remove('rx'), percent: _widthPercent);
    double? ry = getFloat(attrs.remove('ry'), percent: _heightPercent) ?? rx;
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
    final double cx = getFloat(attrs.remove('cx'), percent: _widthPercent) ?? 0;
    final double cy =
        getFloat(attrs.remove('cy'), percent: _heightPercent) ?? 0;
    final double r = getFloat(attrs.remove('r'), percent: _minPercent) ?? 0;
    final e = SvgEllipse('circle', cx, cy, r, r);
    _processId(e, attrs);
    _processInheritable(e, attrs);
    _warnUnusedAttributes(attrs);
    _parentStack.last.children.add(e);
  }

  void _processEllipse(Map<String, String> attrs) {
    final double cx = getFloat(attrs.remove('cx'), percent: _widthPercent) ?? 0;
    final double cy =
        getFloat(attrs.remove('cy'), percent: _heightPercent) ?? 0;
    final double rx = getFloat(attrs.remove('rx'), percent: _widthPercent) ?? 0;
    final double ry =
        getFloat(attrs.remove('ry'), percent: _heightPercent) ?? 0;
    final e = SvgEllipse('ellipse', cx, cy, rx, ry);
    _processId(e, attrs);
    _processInheritable(e, attrs);
    _warnUnusedAttributes(attrs);
    _parentStack.last.children.add(e);
  }

  void _processLine(Map<String, String> attrs) {
    final double x1 = getFloat(attrs.remove('x1'), percent: _widthPercent) ?? 0;
    final double y1 =
        getFloat(attrs.remove('y1'), percent: _heightPercent) ?? 0;
    final double x2 = getFloat(attrs.remove('x2'), percent: _widthPercent) ?? 0;
    final double y2 =
        getFloat(attrs.remove('y2'), percent: _heightPercent) ?? 0;
    final line = SvgPoly('line', false, [Point(x1, y1), Point(x2, y2)]);
    _processId(line, attrs);
    _processInheritable(line, attrs);
    _warnUnusedAttributes(attrs);
    _parentStack.last.children.add(line);
  }

  void _processPoly(String tagName, bool close, Map<String, String> attrs) {
    final str = attrs.remove('points') ?? '';
    final lex = BnfLexer(str);
    final pts = lex.getFloatList();
    // Units aren't allowed here - cf. Tiny 9.7.1
    if (!lex.eof) {
      warn('Unexpected characters at end of points:  $str');
    }
    if (pts.length % 2 != 0) {
      warn('Odd number of points to polyline or polygon');
    }
    final points = List<Point<double>>.empty(growable: true);
    for (int i = 0; i < pts.length - 1; i += 2) {
      points.add(Point(pts[i], pts[i + 1]));
    }
    final line = SvgPoly(tagName, close, points);
    _processId(line, attrs);
    _processInheritable(line, attrs);
    _warnUnusedAttributes(attrs);
    _parentStack.last.children.add(line);
  }

  static final _whitespace = RegExp(r'\s+');

  void _processImage(Map<String, String> attrs) {
    final image = SvgImage();
    image.x = getFloat(attrs.remove('x'), percent: _widthPercent) ?? image.x;
    image.y = getFloat(attrs.remove('y'), percent: _heightPercent) ?? image.y;
    image.width =
        getFloat(attrs.remove('width'), percent: _widthPercent) ?? image.width;
    image.height = getFloat(attrs.remove('height'), percent: _heightPercent) ??
        image.height;
    String? data = attrs.remove('href');
    if (data != null) {
      // Remove spaces, newlines, etc.
      final uri = Uri.parse(data.replaceAll(_whitespace, ''));
      Uint8List? uData;
      uData = uri.data?.contentAsBytes();
      if (uData == null || uData.isEmpty) {
        warn('Invalid data: URI in image:  $data');
        return;
      } else {
        image.imageData = uData;
      }
    }
    _processId(image, attrs);
    _processInheritable(image, attrs);
    _warnUnusedAttributes(attrs);
    _parentStack.last.children.add(image);
  }

  _TextBuilder _processText(Map<String, String> attrs) {
    final n = SvgText(warn: warn);
    n.x = getFloatList(attrs.remove('x'), percent: _widthPercent) ?? n.x;
    n.y = getFloatList(attrs.remove('y'), percent: _heightPercent) ?? n.y;
    _processId(n, attrs);
    _processInheritable(n, attrs);
    _warnUnusedAttributes(attrs);
    _parentStack.last.children.add(n);
    return _TextBuilder(n);
  }

  void _processTextSpan(SvgTextSpan span, Map<String, String> attrs) {
    span.dx = getFloatList(attrs.remove('dx'), percent: _widthPercent);
    span.dy = getFloatList(attrs.remove('dy'), percent: _heightPercent);
    span.x = getFloatList(attrs.remove('x'), percent: _widthPercent);
    span.y = getFloatList(attrs.remove('y'), percent: _heightPercent);
    _processInheritableText(span, attrs);
    _warnUnusedAttributes(attrs);
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
      warn('Illegal color value for gradient stop:  $color');
      return;
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
    final x = getFloat(attrs.remove('x'), percent: _widthPercent);
    final y = getFloat(attrs.remove('y'), percent: _heightPercent);
    use.width = getFloat(attrs.remove('width'), percent: _widthPercent);
    use.height = getFloat(attrs.remove('height'), percent: _heightPercent);
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
    final href = attrs.remove('href');
    if (href == null) {
      return href;
    }
    if (!href.startsWith('#')) {
      warn('href does not start with "#"');
      return null;
    }
    return href.substring(1);
  }

  void _processId(SvgNode n, Map<String, String> attrs) {
    final id = n.id = attrs.remove('id');
    if (id != null) {
      idLookup[id] = n;
      pattern:
      for (final Pattern e in exportedIDs) {
        for (final Match m in e.allMatches(id)) {
          if (id == m[0]) {
            n.idIsExported = true;
            break pattern;
          }
        }
      }
    }
  }

  void _processInheritableText(
      SvgInheritableTextAttributes node, Map<String, String> attrs) {
    final sc = attrs.remove('class');
    if (sc != null) {
      node.styleClass = sc;
    }
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
    p.strokeWidth =
        getFloat(attrs.remove('stroke-width'), percent: _minPercent);
    p.strokeCap = getStrokeCap(attrs.remove('stroke-linecap'));
    p.strokeJoin = getStrokeJoin(attrs.remove('stroke-linejoin'));
    p.strokeMiterLimit = getFloat(attrs.remove('stroke-miterlimit'));
    p.strokeDashArray = getFloatList(attrs.remove('stroke-dasharray'));
    p.strokeDashOffset = getFloat(attrs.remove('stroke-dashoffset'));
    final SvgTextStyle t = node.textStyle;
    t.fontFamily = getStringList(attrs.remove('font-family'));

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
      } else {
        warn('    Ignoring invalid font-style "$attr"');
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
      } else {
        warn('    Ignoring invalid font-weight "$attr"');
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
        } else {
          warn('    Ignoring invalid font-size "$attr"');
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
      } else {
        warn('    Ignoring invalid text-anchor "$attr"');
      }
    }

    attr = attrs.remove('dominant-baseline')?.toLowerCase();
    if (attr == null || attr == 'inherit') {
      // Let it stay at null
    } else {
      const vals = {
        'middle': SIDominantBaseline.middle,
        'central': SIDominantBaseline.central,
        'hanging': SIDominantBaseline.hanging,
        'auto': SIDominantBaseline.auto,
        'alphabetic': SIDominantBaseline.alphabetic,
        'ideographic': SIDominantBaseline.ideographic,
        'mathematical': SIDominantBaseline.mathematical,
        'text-after-edge': SIDominantBaseline.textAfterEdge,
        'text-before-edge': SIDominantBaseline.textBeforeEdge,
      };
      final v = vals[attr];
      if (v != null) {
        t.dominantBaseline = v;
      } else {
        warn('    Ignoring invalid dominant-baseline "$attr"');
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
      } else {
        warn('    Ignoring invalid textDecoration "$attr"');
      }
    }
  }

  void _processInheritable(
      SvgInheritableAttributes node, Map<String, String> attrs) {
    _processInheritableText(node, attrs);
    node.display = attrs.remove('display') != 'none';
    node.groupAlpha = getAlpha(attrs.remove('opacity'));
    if (node.groupAlpha == 0xff) {
      node.groupAlpha = null;
    }
    node.transform = getTransform(node.transform, attrs.remove('transform'));

    String? attr = attrs.remove('mix-blend-mode');
    {
      const vals = {
        null: null,
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
      } else if (attr != null) {
        warn('    Ignoring invalid mix-blend-mode "$attr"');
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
      final List<double> args;
      try {
        args = getTransformArgs(lexer.getNextFunctionArgs());
      } catch (e) {
        warn(e.toString());
        continue;
      }
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
          result.multiplyBy(MutableAffine.skewX(args[0] * pi / 180));
          continue;
        }
      } else if (t == 'skewy') {
        if (args.length == 1) {
          result.multiplyBy(MutableAffine.skewY(args[0] * pi / 180));
          continue;
        }
      }
      warn('    Unrecognized transform $t');
    }
    if (!lexer.eof) {
      warn('    Unexpected characters at end of transform:  "$s"');
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
      warn('    Unrecognized text at end of transform args:  "$s"');
    }
    return result;
  }

  void _warnUnusedAttributes(Map<String, String> attrs) {
    for (final a in attrs.keys) {
      if (!a.startsWith('data-') && attributesIgnored.add('$_currTag:$a')) {
        warn('    Ignoring $a attribute(s) in $_currTag');
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
      map[a.localName.toLowerCase()] = a.value;
    }
    final style = map.remove('style');
    if (style != null) {
      _parseStyle(style, map);
    }
    return map;
  }

  void _parseStyle(String style, Map<String, String> map) {
    for (String el in style.split(';')) {
      el = el.trim();
      if (el == '') {
        continue;
      }
      int pos = el.indexOf(':');
      if (pos == -1) {
        warn('Syntax error in style attribute "$style"');
        continue;
      }
      final key = el.substring(0, pos).trim();
      if (map.containsKey(key)) {
        warn('    Ignoring duplicate style attribute $key');
      } else {
        map[key] = el.substring(pos + 1).trim();
      }
    }
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
      final color = super.getColor(lc);
      if (color != null) {
        return SvgColor.value(color);
      } else {
        return SvgColor.none;
      }
    }
  }

  static final _whitespaceOrNothing = RegExp(r'\s*');
  static final _idToBrace = RegExp(r'[^{]+');
  static final _consumeToBrace = RegExp(r'[^{]*');
  static final _consumeToRBrace = RegExp(r'[^}]*');

  void _processStyle(String string) {
    // First, strip out comments
    for (;;) {
      int pos = string.indexOf('/*');
      if (pos == -1) {
        break;
      }
      int end = string.indexOf('*/', pos + 2);
      if (end == -1) {
        string = '';
        break;
      }
      string = string.substring(0, pos) + string.substring(end + 2);
    }
    // Now parse the stylesheet
    int pos = _whitespaceOrNothing.matchAsPrefix(string, 0)?.end ?? 0;
    int lastPos;
    while (pos < string.length) {
      lastPos = pos;
      final idMatch = _idToBrace.matchAsPrefix(string, pos);
      pos = idMatch?.end ?? pos;
      pos = _consumeToBrace.matchAsPrefix(string, pos)?.end ?? pos;
      if (pos < string.length) {
        pos++;
      }
      pos = _whitespaceOrNothing.matchAsPrefix(string, pos)?.end ?? pos;
      final contentM = _consumeToRBrace.matchAsPrefix(string, pos);
      pos = contentM?.end ?? pos;
      if (pos < string.length) {
        pos++;
      }
      pos = _whitespaceOrNothing.matchAsPrefix(string, pos)?.end ?? pos;
      if (idMatch != null && contentM != null) {
        final ids = string.substring(idMatch.start, idMatch.end);
        final content = string.substring(contentM.start, contentM.end);
        for (String id in ids.split(',')) {
          id = id.trim();
          final String element;
          final String styleClass;
          final dp = id.indexOf('.');
          if (dp == -1) {
            element = id;
            styleClass = '';
          } else {
            element = id.substring(0, dp);
            styleClass = id.substring(dp + 1);
          }
          final s = Style();
          _stylesheet.putIfAbsent(element, () => []).add(s);
          Map<String, String> attrs = {};
          _parseStyle(content, attrs);
          _processInheritable(s, attrs);
          s.styleClass = styleClass;
          // Unlike a node, our styleClass doesn't come from the
          // parser.  A badly formed CSS entry could try to set an attribute
          // called 'class,' so we set styleClass last.
        }
      }
      assert(lastPos != pos);
      pos = (lastPos == pos) ? pos++ : pos; // Cowardice is good
    }
  }

  double _widthPercent(double val) => (val / 100) * _widthForPercentages;
  double _heightPercent(double val) => (val / 100) * _heightForPercentages;
  double _minPercent(double val) =>
      (val / 100) * (min(_heightForPercentages, _widthForPercentages));
}

class _TextBuilder {
  final SvgText node;
  final List<SvgTextSpan> stack;
  bool _trimLeft = true;

  static final _whitespace = RegExp(r'\s+');

  _TextBuilder(this.node) : stack = [node.root];

  void appendText(String added) {
    added = added.replaceAll(_whitespace, ' ');
    if (_trimLeft) {
      added = added.trimLeft();
    }
    if (added == '') {
      return;
    }
    _trimLeft = added.endsWith(' ');
    stack.last.appendToPart(added);
  }

  SvgTextSpan startSpan() {
    final s = SvgTextSpan('tspan');
    stack.last.appendPart(s);
    stack.add(s);
    return s;
  }

  void endSpan() {
    if (stack.length > 1) {
      stack.removeLast();
    }
  }
}

class _TagEntry {
  final int parentPos;
  final String tag;
  _TagEntry(this.parentPos, this.tag);
}

class _SvgParserEventHandler with XmlEventVisitor {
  final SvgParser parser;

  _SvgParserEventHandler(this.parser);

  @override
  void visitStartElementEvent(XmlStartElementEvent e) => parser._startTag(e);

  @override
  void visitEndElementEvent(XmlEndElementEvent e) => parser._endTag(e);

  @override
  void visitCDATAEvent(XmlCDATAEvent event) => parser._textEvent(event.value);

  @override
  void visitCommentEvent(XmlCommentEvent event) {}

  @override
  void visitDeclarationEvent(XmlDeclarationEvent event) {}

  @override
  void visitDoctypeEvent(XmlDoctypeEvent event) {}

  @override
  void visitProcessingEvent(XmlProcessingEvent event) {}

  @override
  void visitTextEvent(XmlTextEvent event) => parser._textEvent(event.value);
}

class StreamSvgParser extends SvgParser {
  final Stream<String> _input;

  StreamSvgParser(this._input, List<Pattern> exportedIDs,
      SIBuilder<String, SIImageData>? builder,
      {required void Function(String) warn})
      : super(warn, exportedIDs, builder);

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

  StringSvgParser(this._input, List<Pattern> exportedIDs,
      SIBuilder<String, SIImageData>? builder,
      {required void Function(String) warn})
      : super(warn, exportedIDs, builder);

  void parse() {
    final handler = _SvgParserEventHandler(this);
    for (XmlEvent e in parseEvents(_input)) {
      e.accept(handler);
    }
    buildResult();
  }
}
