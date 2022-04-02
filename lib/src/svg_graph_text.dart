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

part of 'svg_graph.dart';

//
// Support for SVG's (insanely complicated) text node is split out into this
// file, because it's freakin' big.  Be sure to look at `text.uml` or
// `text.svg` for a picture of the structure.  In short:
//
//  *  SvgParser creates an SvgText, which consists of nodes of
//     SvgTextSpanComponent / SvgTextSpan / SvtTextSpanStringComponent
//  *  This is "flattened" into a list of SvgTextChunk / SvgMultiSpanChunk
//     / SvgSingleSpanChunk instances
//  *  This is used to build an SIText, which consists of SITextChunk /
//  *  SIMultiSpanChunk / SITextSpan.
//
// A lot of the complexity comes from SVG's rather unique notion of having a
// coordinate be either a single value or a list.

class SvgText extends SvgInheritableAttributesNode {
  List<SvgTextSpan> stack = [SvgTextSpan('text')];
  bool _trimLeft = true;

  late final List<SvgTextChunk> flattened = _flatten();

  static final _whitespace = RegExp(r'\s+');

  SvgText() {
    final root = stack.first;
    root.x = root.y = const [0.0];
  }

  @override
  String get tagName => 'text';

  List<double>? get x => stack.first.x;
  set x(List<double>? v) => stack.first.x = v;
  List<double>? get y => stack.first.y;
  set y(List<double>? v) => stack.first.y = v;

  @override
  SvgPaint get paint => stack.first.paint;

  @override
  SvgTextAttributes get textAttributes => stack.first.textAttributes;

  @override
  set textAttributes(SvgTextAttributes v) => stack.first.textAttributes = v;

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

  @override
  void applyStylesheet(Stylesheet stylesheet) {
    // No call of super.applyStylesheet, because our attributes are on root,
    // which has a tagName of 'text'.
    assert(stack.length == 1);
    final SvgTextSpan root = stack.first;
    root.applyStylesheet(stylesheet);
  }

  @override
  SvgNode? resolve(Map<String, SvgNode> idLookup, SvgPaint ancestor, bool warn,
      _Referrers referrers) {
    // Even invisible text can influence layout, so we don't try to optimize
    // it away.
    return resolveMask(idLookup, ancestor, warn, referrers);
  }

  ///
  /// This flattens out the text span components, but it doesn't cascade
  /// the text attributes or the paints.  That happens later, in build().
  ///
  List<SvgTextChunk> _flatten() {
    assert(stack.length == 1);
    stack.first.trimRight();
    List<SvgTextChunk> children = [];
    final SvgTextSpan root = stack.first;
    root.flattenInto(children, _FlattenContext.empty());
    return children;
  }

  @override
  bool canUseLuma(Map<String, SvgNode> idLookup, SvgPaint ancestor,
      void Function(String) warn) {
    for (final chunk in flattened) {
      for (final span in chunk.spans) {
        final cascaded = span.paint.cascade(ancestor, idLookup);
        final p = cascaded.toSIPaint(warn);
        if (p.canUseLuma) {
          return true;
        }
      }
    }
    return false;
  }

  @override
  RectT? _getUntransformedBounds(SvgTextAttributes ta) {
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
  bool build(SIBuilder<String, SIImageData> builder, CanonicalizedData canon,
      Map<String, SvgNode> idLookup, SvgPaint ancestor, SvgTextAttributes ta,
      {bool blendHandledByParent = false}) {
    assert(stack.length == 1);
    if (!display) {
      return false;
    }
    final blend = blendHandledByParent
        ? SIBlendMode.normal
        : (blendMode ?? SIBlendMode.normal);
    final needGroup =
        transform != null || groupAlpha != null || blend != SIBlendMode.normal;
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
    return true;
  }
}

class SvgTextSpan extends SvgTextNodeAttributes
    implements SvgTextSpanComponent {
  @override
  List<double>? x;
  @override
  List<double>? y;
  List<SvgTextSpanComponent> parts = [];
  @override
  final String tagName;

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
  void applyStylesheet(Stylesheet stylesheet) {
    super.applyStylesheet(stylesheet);
    for (final p in parts) {
      p.applyStylesheet(stylesheet);
    }
  }

  @override
  void flattenInto(List<SvgTextChunk> children, _FlattenContext fc) {
    // We cascade the paint and text attributes within the text tag's subtree,
    // since we're destroying that structure.
    fc = _FlattenContext(fc, this);
    for (final p in parts) {
      p.flattenInto(children, fc);
    }
  }
}

class _FlattenContext {
  final _FCNumberSource x;
  final _FCNumberSource y;
  final _FCNumberSource dx;
  final _FCNumberSource dy;
  final SvgTextAttributes ta;
  final SvgPaint paint;

  _FlattenContext(_FlattenContext ancestor, SvgTextSpan span)
      : x = _FCNumberSource.createOr(span.x, ancestor.x),
        y = _FCNumberSource.createOr(span.y, ancestor.y),
        dx = _FCNumberSource.createOr(span.dx, ancestor.dx),
        dy = _FCNumberSource.createOr(span.dy, ancestor.dy),
        ta = span.textAttributes.cascade(ancestor.ta),
        paint = span.paint.cascade(ancestor.paint, null);

  _FlattenContext.empty()
      : x = _FCNumberSource.root(),
        y = _FCNumberSource.root(),
        dx = _FCNumberSource.root(),
        dy = _FCNumberSource.root(),
        ta = SvgTextAttributes.empty(),
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

  void flattenInto(List<SvgTextChunk> children, _FlattenContext fc);

  void applyStylesheet(Stylesheet stylesheet);
}

class SvgTextSpanStringComponent extends SvgTextSpanComponent {
  final SvgTextSpan parent;
  String text;

  SvgTextSpanStringComponent(this.parent, this.text) {
    assert(text != '');
  }

  @override
  void applyStylesheet(Stylesheet stylesheet) {}

  @override
  bool trimRight() {
    text = text.trimRight();
    return true;
  }

  @override
  void flattenInto(List<SvgTextChunk> children, _FlattenContext fc) {
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

  SITextAnchor getAnchor(SvgTextAttributes ancestor) {
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

  void build(SIBuilder<String, SIImageData> builder, CanonicalizedData canon,
      Map<String, SvgNode> idLookup, SvgPaint paint, SvgTextAttributes ta) {
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

  RectT getBounds(SvgTextAttributes ancestor) {
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
  final SvgTextAttributes attributes;
  final SvgPaint paint;
  final StringBuffer text;

  SvgFlatSpan(this.dx, this.dy, this.attributes, this.paint, String initialText)
      : text = StringBuffer(initialText);

  void build(
      double x,
      double y,
      SIBuilder<String, SIImageData> builder,
      CanonicalizedData canon,
      Map<String, SvgNode> idLookup,
      SvgPaint ancestor,
      SvgTextAttributes ta) {
    ta = attributes.cascade(ta);
    final cascaded = paint.cascade(ancestor, idLookup);
    final int? fontFamilyIndex;
    if (ta.fontFamily == '') {
      fontFamilyIndex = null;
    } else {
      fontFamilyIndex = canon.strings.getIfNotNull(ta.fontFamily);
    }
    final textIndex = canon.strings[text.toString()];
    final dxIndex = canon.floatValues[x + dx];
    final dyIndex = canon.floatValues[y + dy];
    final fontSizeIndex = canon.floatValues[ta.fontSize.toSI()];
    builder.textSpan(
        null,
        dxIndex,
        dyIndex,
        textIndex,
        ta.toSITextAttributes(),
        fontFamilyIndex,
        fontSizeIndex,
        cascaded.toSIPaint(builder.printWarning));
  }

  RectT getBounds(double x, double y, SvgTextAttributes ancestor) {
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
