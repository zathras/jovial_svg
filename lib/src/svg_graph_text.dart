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

part of 'svg_graph.dart';

//
// Support for SVG's (insanely complicated) text node is split out into this
// file, because it's freakin' big.  Be sure to look at `text.uml` or
// `text.svg` for a picture of the structure.  In short:
//
//  *  SvgParser creates an SvgText, which consists of a SvgTextSpan
//     instance, with a tree of nodes of
//     SvgTextSpanComponent (SvgTextSpan / SvtTextSpanStringComponent)
//  *  This is "flattened" into a list of SvgTextChunk instances, each
//     of which has a list of SvgFlatSpan instances
//  *  This is used to build an SIText, which consists of SITextChunk /
//     SIMultiSpanChunk / SITextSpan.
//
// A lot of the complexity comes from SVG's rather unique notion of having a
// coordinate be either a single value or a list.

///
/// An SVG `text` node.  See
/// https://www.w3.org/TR/2008/REC-SVGTiny12-20081222/text.html .
///
/// {@category SVG DOM}
///
class SvgText extends SvgInheritableAttributesNode {
  ///
  /// The top-level span containing all of the text content.
  ///
  SvgTextSpan root = SvgTextSpan('text');

  final _WarnT _warn;

  late final List<_SvgTextChunk> _flattened = _flatten();

  ///
  /// Create a new text mode.
  ///
  /// [warn], if present, will be called if any warnings are generated while
  /// processing the text element in the production of a `ScalableImage`.
  ///
  SvgText({void Function(String)? warn})
      : _warn = warn ?? nullWarn,
        super._p() {
    root.x = root.y = const [0.0];
  }

  SvgText._cloned(SvgText super.other)
      : root = other.root._clone(null),
        _warn = other._warn,
        super._cloned();

  @override
  SvgText _clone() => SvgText._cloned(this);

  @override
  void _cloneAttributes() {
    super._cloneAttributes();
    root._cloneAttributes();
  }

  @override
  String get tagName => root.tagName; // which is 'text'

  ///
  /// [SvgTextSpan.x] from [root]
  ///
  List<double>? get x => root.x;
  set x(List<double>? v) => root.x = v;

  ///
  /// [SvgTextSpan.y] from [root]
  ///
  List<double>? get y => root.y;
  set y(List<double>? v) => root.y = v;

  ///
  /// [SvgTextSpan.paint] from [root] - see
  ///
  @override
  SvgPaint get paint => root.paint;
  @override
  set paint(SvgPaint v) => root.paint = v;

  ///
  /// [SvgTextSpan.textStyle] from [root]
  ///
  @override
  SvgTextStyle get textStyle => root.textStyle;
  @override
  set textStyle(SvgTextStyle v) => root.textStyle = v;

  ///
  /// [SvgTextSpan.styleClass] from [root]
  ///
  @override
  String get styleClass => root.styleClass;
  @override
  set styleClass(String v) => root.styleClass = v;

  @override
  void _applyStylesheet(_FastStylesheet stylesheet, _WarnT warn) {
    super._applyStylesheet(stylesheet, warn);
    root._applyStylesheetToChildren(stylesheet, warn);
  }

  @override
  SvgNode? _resolve(
      _ResolveContext ctx, SvgPaint ancestor, _SvgNodeReferrers referrers) {
    // Even invisible text can influence layout, so we don't try to optimize
    // it away.
    return _resolveMask(ctx, ancestor, referrers);
  }

  ///
  /// This flattens out the text span components, but it doesn't cascade
  /// the text attributes or the paints.  That happens later, in build().
  ///
  List<_SvgTextChunk> _flatten() {
    root._trimRight();
    List<_SvgTextChunk> children = [];
    root._flattenInto(children, _FlattenContext.empty(), _warn);
    return children;
  }

  @override
  bool _canUseLuma(Map<String, SvgNode> idLookup, SvgPaint ancestor) {
    for (final chunk in _flattened) {
      for (final span in chunk.spans) {
        final cascaded = span.paint._cascade(ancestor, idLookup, (_) {});
        final p = cascaded._toSIPaint();
        if (p.canUseLuma) {
          return true;
        }
      }
    }
    return false;
  }

  @override
  RectT? _getUntransformedBounds(SvgTextStyle ta) {
    RectT? result;
    for (final chunk in _flattened) {
      final RectT r = chunk.getBounds(ta);
      if (result == null) {
        result = r;
      } else {
        result = result.boundingBox(r);
      }
    }
    return result;
  }

  @override
  bool _build(
      SIBuilder<String, SIImageData> builder,
      CanonicalizedData<SIImageData> canon,
      Map<String, SvgNode> idLookup,
      SvgPaint ancestor,
      SvgTextStyle ta,
      {bool blendHandledByParent = false}) {
    if (!display) {
      return false;
    }
    final blend = blendHandledByParent
        ? SIBlendMode.normal
        : (blendMode ?? SIBlendMode.normal);
    final needGroup =
        transform != null || groupAlpha != null || blend != SIBlendMode.normal;
    if (exportedID != null) {
      builder.exportedID(null, canon.strings[exportedID!]);
    }
    if (needGroup) {
      builder.group(null, transform, groupAlpha, blend);
    }
    builder.text(null);
    for (final chunk in _flattened) {
      // Our SvgText node's paint and text attributes have already been
      // cascaded into our children.
      chunk.build(builder, canon, idLookup, ancestor, ta);
    }
    builder.textEnd(null);
    if (needGroup) {
      builder.endGroup(null);
    }
    if (exportedID != null) {
      builder.endExportedID(null);
    }
    return true;
  }
}

///
/// An SVG `tspan`.  See
/// https://www.w3.org/TR/2008/REC-SVGTiny12-20081222/text.html .
///
/// {@category SVG DOM}
///
class SvgTextSpan extends SvgInheritableTextAttributes
    implements SvgTextSpanComponent {
  List<double>? x;
  List<double>? y;
  List<double>? dx;
  List<double>? dy;
  List<SvgTextSpanComponent> parts = [];
  @override
  final String tagName;

  SvgTextSpan(this.tagName) : super._p();

  SvgTextSpan._cloned(SvgTextSpan other)
      : x = other.x,
        y = other.y,
        dx = other.dx,
        dy = other.dy,
        tagName = other.tagName,
        super._cloned(other) {
    parts.addAll(other.parts.map((p) => p._clone(this)));
  }

  @override
  void _cloneAttributes() {
    super._cloneAttributes();
    for (final p in parts) {
      p._cloneAttributes();
    }
  }

  // We inherit an applyStyle implementation that assumes we're a node,
  // so we need to stub this out.  Styles applied by node ID will be
  // inherited by our enclosing SvgText, which forwards its style
  // information to its root span.
  @override
  String? get _idForApplyStyle => null;

  @override
  SvgTextSpan _clone(SvgTextSpan? parent) => SvgTextSpan._cloned(this);

  void appendToPart(String added) {
    parts.add(SvgTextSpanStringComponent(this, added));
  }

  void appendPart(SvgTextSpanComponent part) => parts.add(part);

  @override
  bool _trimRight() {
    for (int i = parts.length - 1; i >= 0; i--) {
      if (parts[i]._trimRight()) {
        return true;
      }
    }
    return false;
  }

  @override
  void _applyStylesheet(_FastStylesheet stylesheet, _WarnT warn) {
    super._applyStylesheet(stylesheet, warn);
    _applyStylesheetToChildren(stylesheet, warn);
  }

  void _applyStylesheetToChildren(_FastStylesheet stylesheet, _WarnT warn) {
    for (final p in parts) {
      p._applyStylesheet(stylesheet, warn);
    }
  }

  @override
  void _flattenInto(
      List<_SvgTextChunk> children, _FlattenContext fc, _WarnT warn) {
    // We cascade the paint and text attributes within the text tag's subtree,
    // since we're destroying that structure.
    fc = _FlattenContext(fc, this, warn);
    for (final p in parts) {
      p._flattenInto(children, fc, warn);
    }
  }
}

class _FlattenContext {
  final _FCNumberSource x;
  final _FCNumberSource y;
  final _FCNumberSource dx;
  final _FCNumberSource dy;
  final SvgTextStyle ta;
  final SvgPaint paint;

  _FlattenContext(_FlattenContext ancestor, SvgTextSpan span, _WarnT warn)
      : x = _FCNumberSource.createOr(span.x, ancestor.x),
        y = _FCNumberSource.createOr(span.y, ancestor.y),
        dx = _FCNumberSource.createOr(span.dx, ancestor.dx),
        dy = _FCNumberSource.createOr(span.dy, ancestor.dy),
        ta = span.textStyle._cascade(ancestor.ta),
        paint = span.paint._cascade(ancestor.paint, null, warn);

  _FlattenContext.empty()
      : x = _FCNumberSource.root(),
        y = _FCNumberSource.root(),
        dx = _FCNumberSource.root(),
        dy = _FCNumberSource.root(),
        ta = SvgTextStyle.empty(),
        paint = SvgPaint.empty();

  double? pull(_FCNumberSource s) {
    assert(s == x || s == y || s == dx || s == dy);
    final v = s.pullNext();
    if (v != null) {
      s.last.value = v;
    }
    return v;
  }

  double pullOrLast(_FCNumberSource s) => pull(s) ?? s.last.value;
}

class _FCNumberSource {
  final List<double>? numbers; // Only null at root of tree
  int _pos = 0;
  _FCLastValue last;
  _FCNumberSource? ancestor;

  _FCNumberSource._p(this.numbers, this.ancestor, this.last);

  factory _FCNumberSource.createOr(
      List<double>? numbers, _FCNumberSource ancestor) {
    if (numbers != null && numbers.isNotEmpty) {
      return _FCNumberSource._p(numbers, ancestor, ancestor.last);
    } else {
      return ancestor;
    }
  }

  _FCNumberSource.root()
      : numbers = null,
        ancestor = null,
        last = _FCLastValue();

  double? pullNext() {
    final double? av = ancestor?.pullNext();
    final n = numbers;
    final double? v;
    if (n == null) {
      v = null;
    } else {
      v = (_pos >= n.length) ? null : n[_pos++];
    }
    return v ?? av;
  }
}

class _FCLastValue {
  double value = 0;
}

///
/// A component of an SVG `tspan`.  See
/// https://www.w3.org/TR/2008/REC-SVGTiny12-20081222/text.html .
///
/// {@category SVG DOM}
///
sealed class SvgTextSpanComponent {
  SvgTextSpanComponent._p();

  SvgTextSpanComponent _clone(SvgTextSpan? parent);

  void _cloneAttributes();

  bool _trimRight();

  void _flattenInto(
      List<_SvgTextChunk> children, _FlattenContext fc, _WarnT warn);

  void _applyStylesheet(_FastStylesheet stylesheet, _WarnT warn);
}

///
/// A string run within an SVG `text`.  See
/// https://www.w3.org/TR/2008/REC-SVGTiny12-20081222/text.html .
///
/// {@category SVG DOM}
///
class SvgTextSpanStringComponent extends SvgTextSpanComponent {
  final SvgTextSpan parent;
  String text;

  SvgTextSpanStringComponent(this.parent, this.text) : super._p();

  @override
  SvgTextSpanStringComponent _clone(SvgTextSpan? parent) =>
      SvgTextSpanStringComponent(parent!, text);

  @override
  void _applyStylesheet(_FastStylesheet stylesheet, _WarnT warn) {}

  @override
  void _cloneAttributes() {
    // We don't need to clone text.  It is mutable, but we don't mutate
    // it when generating a ScalableImage.
  }

  @override
  bool _trimRight() {
    text = text.trimRight();
    return true;
  }

  @override
  void _flattenInto(
      List<_SvgTextChunk> children, _FlattenContext fc, _WarnT warn) {
    for (int i = 0; i < text.length; i++) {
      double? x = fc.pull(fc.x);
      double y = fc.pullOrLast(fc.y);
      double dx = fc.pullOrLast(fc.dx);
      double dy = fc.pullOrLast(fc.dy);
      if (x == null && children.isEmpty) {
        x = 0;
      }
      final ch = text.substring(i, i + 1);
      if (x != null) {
        // New chunk
        final chunk = _SvgTextChunk(x, y);
        chunk.spans.add(_SvgFlatSpan(dx, dy, fc.ta, fc.paint, ch));
        children.add(chunk);
      } else {
        final _SvgTextChunk chunk = children.last;
        dy = dy + y - chunk.y;
        final lastSpan = chunk.spans.last;
        if (dx == 0 &&
            dy == lastSpan.dy &&
            fc.ta == lastSpan.attributes &&
            fc.paint == lastSpan.paint) {
          lastSpan.text.write(ch);
        } else {
          chunk.spans.add(_SvgFlatSpan(dx, dy, fc.ta, fc.paint, ch));
        }
      }
    }
  }
}

class _SvgTextChunk {
  final double x;
  final double y;
  final List<_SvgFlatSpan> spans = [];
  SITextAnchor? _anchor;

  _SvgTextChunk(this.x, this.y);

  SITextAnchor getAnchor(SvgTextStyle ancestor) {
    assert(spans.length > 1);
    final a = _anchor;
    if (a != null) {
      return a;
    }
    final r = _anchor = spans.first.attributes._cascade(ancestor).textAnchor!;
    for (final span in spans) {
      span.attributes.textAnchor = SITextAnchor.start;
    }
    return r;
  }

  void build(
      SIBuilder<String, SIImageData> builder,
      CanonicalizedData<SIImageData> canon,
      Map<String, SvgNode> idLookup,
      SvgPaint paint,
      SvgTextStyle ta) {
    assert(spans.isNotEmpty);
    if (spans.length == 1) {
      spans.first.build(x, y, builder, canon, idLookup, paint, ta);
    } else {
      final anchor = getAnchor(ta);
      final xIndex = canon.floatValues[x];
      final yIndex = canon.floatValues[y];
      builder.textMultiSpanChunk(null, xIndex, yIndex, anchor);
      for (final span in spans) {
        assert(span.attributes.textAnchor == SITextAnchor.start);
        span.build(0, 0, builder, canon, idLookup, paint, ta);
      }
      builder.textEnd(null);
    }
  }

  RectT getBounds(SvgTextStyle ancestor) {
    if (spans.length == 1) {
      return spans.first.getBounds(x, y, ancestor);
    }
    final anchor = getAnchor(ancestor);
    RectT r = spans.first.getBounds(x, y, ancestor);
    for (int i = 1; i < spans.length; i++) {
      final span = spans[i];
      r = r.boundingBox(span.getBounds(x, y, ancestor));
    }
    final double dx;
    switch (anchor) {
      case SITextAnchor.start:
        dx = 0;
        break;
      case SITextAnchor.middle:
        dx = -r.width / 2;
        break;
      case SITextAnchor.end:
        dx = -r.width;
        break;
    }
    if (dx == 0) {
      return r;
    } else {
      return RectT(r.left + dx, r.top, r.width, r.height);
    }
  }
}

class _SvgFlatSpan {
  final double dx;
  final double dy;
  final SvgTextStyle attributes;
  final SvgPaint paint;
  final StringBuffer text;

  _SvgFlatSpan(
      this.dx, this.dy, this.attributes, this.paint, String initialText)
      : text = StringBuffer(initialText);

  void build(
      double x,
      double y,
      SIBuilder<String, SIImageData> builder,
      CanonicalizedData<SIImageData> canon,
      Map<String, SvgNode> idLookup,
      SvgPaint ancestor,
      SvgTextStyle ta) {
    ta = attributes._cascade(ta);
    final cascaded = paint._cascade(ancestor, idLookup, builder.warn);
    final int? fontFamilyIndex;
    if (ta.fontFamily == null) {
      fontFamilyIndex = null;
    } else {
      for (final String s in ta.fontFamily!) {
        canon.strings[s];
      }
      fontFamilyIndex = canon.stringLists.getIfNotNull(CList(ta.fontFamily!));
    }
    final textIndex = canon.strings[text.toString()];
    final dxIndex = canon.floatValues[x + dx];
    final dyIndex = canon.floatValues[y + dy];
    final fontSizeIndex = canon.floatValues[ta.fontSize._toSI()];
    builder.textSpan(
        null,
        dxIndex,
        dyIndex,
        textIndex,
        ta._toSITextAttributes(),
        fontFamilyIndex,
        fontSizeIndex,
        cascaded._toSIPaint());
  }

  RectT getBounds(double x, double y, SvgTextStyle ancestor) {
    // We make a rough approximation, since font metrics aren't available
    // to us here.  This is good enough in the rare case of user space
    // gradients withing an SVG asset with unspecified width/height
    // and renderBox.
    const heightScale = 1.2;
    const widthScale = 0.6;
    final cascaded = attributes._cascade(ancestor);
    final size = cascaded.fontSize._toSI();
    final height = size * heightScale;
    final width = text.length * size * widthScale;
    x += dx;
    y += dy;
    switch (cascaded.textAnchor!) {
      case SITextAnchor.start:
        // Do nothing
        break;
      case SITextAnchor.middle:
        x -= width / 2;
        break;
      case SITextAnchor.end:
        x -= width;
        break;
    }
    return RectT(x, y, width, height);
  }
}
