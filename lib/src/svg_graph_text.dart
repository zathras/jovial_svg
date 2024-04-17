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

class SvgText extends SvgInheritableAttributesNode {
  SvgTextSpan root = SvgTextSpan('text');
  final void Function(String) warn;

  late final List<SvgTextChunk> flattened = _flatten();

  SvgText(this.warn) {
    root.x = root.y = const [0.0];
  }

  @override
  String get tagName => root.tagName; // which is 'text'

  List<double>? get x => root.x;
  set x(List<double>? v) => root.x = v;
  List<double>? get y => root.y;
  set y(List<double>? v) => root.y = v;

  @override
  SvgPaint get paint => root.paint;
  @override
  SvgTextStyle get textStyle => root.textStyle;
  @override
  set textStyle(SvgTextStyle v) => root.textStyle = v;
  @override
  String get styleClass => root.styleClass;
  @override
  set styleClass(String v) => root.styleClass = v;

  @override
  void applyStylesheet(Stylesheet stylesheet, void Function(String) warn) {
    super.applyStylesheet(stylesheet, warn);
    root.applyStylesheetToChildren(stylesheet, warn);
  }

  @override
  SvgNode? resolve(Map<String, SvgNode> idLookup, SvgPaint ancestor,
      void Function(String) warn, SvgNodeReferrers referrers) {
    // Even invisible text can influence layout, so we don't try to optimize
    // it away.
    return resolveMask(idLookup, ancestor, warn, referrers);
  }

  ///
  /// This flattens out the text span components, but it doesn't cascade
  /// the text attributes or the paints.  That happens later, in build().
  ///
  List<SvgTextChunk> _flatten() {
    root.trimRight();
    List<SvgTextChunk> children = [];
    root._flattenInto(children, _FlattenContext.empty(), warn);
    return children;
  }

  @override
  bool canUseLuma(Map<String, SvgNode> idLookup, SvgPaint ancestor) {
    for (final chunk in flattened) {
      for (final span in chunk.spans) {
        final cascaded = span.paint.cascade(ancestor, idLookup, (_) {});
        final p = cascaded.toSIPaint();
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
    for (final chunk in flattened) {
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
  bool build(
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
    for (final chunk in flattened) {
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

class SvgTextSpan extends SvgInheritableTextAttributes
    with _SvgTextAttributeFields
    implements SvgTextSpanComponent {
  List<double>? x;
  List<double>? y;
  List<double>? dx;
  List<double>? dy;
  List<SvgTextSpanComponent> parts = [];
  @override
  final String tagName;
  @override
  String? get id => null;

  SvgTextSpan(this.tagName);

  void appendToPart(String added) {
    parts.add(SvgTextSpanStringComponent(this, added));
  }

  void appendPart(SvgTextSpanComponent part) => parts.add(part);

  @override
  bool trimRight() {
    for (int i = parts.length - 1; i >= 0; i--) {
      if (parts[i].trimRight()) {
        return true;
      }
    }
    return false;
  }

  @override
  void applyStylesheet(Stylesheet stylesheet, void Function(String) warn) {
    super.applyStylesheet(stylesheet, warn);
    applyStylesheetToChildren(stylesheet, warn);
  }

  void applyStylesheetToChildren(
      Stylesheet stylesheet, void Function(String) warn) {
    for (final p in parts) {
      p.applyStylesheet(stylesheet, warn);
    }
  }

  @override
  void _flattenInto(List<SvgTextChunk> children, _FlattenContext fc,
      void Function(String) warn) {
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

  _FlattenContext(
      _FlattenContext ancestor, SvgTextSpan span, void Function(String) warn)
      : x = _FCNumberSource.createOr(span.x, ancestor.x),
        y = _FCNumberSource.createOr(span.y, ancestor.y),
        dx = _FCNumberSource.createOr(span.dx, ancestor.dx),
        dy = _FCNumberSource.createOr(span.dy, ancestor.dy),
        ta = span.textStyle.cascade(ancestor.ta),
        paint = span.paint.cascade(ancestor.paint, null, warn);

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

abstract class SvgTextSpanComponent {
  bool trimRight();

  void _flattenInto(List<SvgTextChunk> children, _FlattenContext fc,
      void Function(String) warn);

  void applyStylesheet(Stylesheet stylesheet, void Function(String) warn);
}

class SvgTextSpanStringComponent extends SvgTextSpanComponent {
  final SvgTextSpan parent;
  String text;

  SvgTextSpanStringComponent(this.parent, this.text) {
    assert(text != '');
  }

  @override
  void applyStylesheet(Stylesheet stylesheet, void Function(String) warn) {}

  @override
  bool trimRight() {
    text = text.trimRight();
    return true;
  }

  @override
  void _flattenInto(List<SvgTextChunk> children, _FlattenContext fc,
      void Function(String) warn) {
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
        final chunk = SvgTextChunk(x, y);
        chunk.spans.add(SvgFlatSpan(dx, dy, fc.ta, fc.paint, ch));
        children.add(chunk);
      } else {
        final SvgTextChunk chunk = children.last;
        dy = dy + y - chunk.y;
        final lastSpan = chunk.spans.last;
        if (dx == 0 &&
            dy == lastSpan.dy &&
            fc.ta == lastSpan.attributes &&
            fc.paint == lastSpan.paint) {
          lastSpan.text.write(ch);
        } else {
          chunk.spans.add(SvgFlatSpan(dx, dy, fc.ta, fc.paint, ch));
        }
      }
    }
  }
}

class SvgTextChunk {
  final double x;
  final double y;
  final List<SvgFlatSpan> spans = [];
  SITextAnchor? _anchor;

  SvgTextChunk(this.x, this.y);

  SITextAnchor getAnchor(SvgTextStyle ancestor) {
    assert(spans.length > 1);
    final a = _anchor;
    if (a != null) {
      return a;
    }
    final r = _anchor = spans.first.attributes.cascade(ancestor).textAnchor!;
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

class SvgFlatSpan {
  final double dx;
  final double dy;
  final SvgTextStyle attributes;
  final SvgPaint paint;
  final StringBuffer text;

  SvgFlatSpan(this.dx, this.dy, this.attributes, this.paint, String initialText)
      : text = StringBuffer(initialText);

  void build(
      double x,
      double y,
      SIBuilder<String, SIImageData> builder,
      CanonicalizedData<SIImageData> canon,
      Map<String, SvgNode> idLookup,
      SvgPaint ancestor,
      SvgTextStyle ta) {
    ta = attributes.cascade(ta);
    final cascaded = paint.cascade(ancestor, idLookup, builder.warn);
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
    final fontSizeIndex = canon.floatValues[ta.fontSize.toSI()];
    builder.textSpan(null, dxIndex, dyIndex, textIndex, ta.toSITextAttributes(),
        fontFamilyIndex, fontSizeIndex, cascaded.toSIPaint());
  }

  RectT getBounds(double x, double y, SvgTextStyle ancestor) {
    // We make a rough approximation, since font metrics aren't available
    // to us here.  This is good enough in the rare case of user space
    // gradients withing an SVG asset with unspecified width/height
    // and renderBox.
    const heightScale = 1.2;
    const widthScale = 0.6;
    final cascaded = attributes.cascade(ancestor);
    final size = cascaded.fontSize.toSI();
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
