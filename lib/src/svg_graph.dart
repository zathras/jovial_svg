// ignore_for_file: constant_identifier_names

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

library jovial_svg.svg_graph;

import 'dart:math';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:jovial_misc/io_utils.dart';
import 'package:meta/meta.dart';

import 'affine.dart';
import 'common_noui.dart';
import 'compact_noui.dart';
import 'path_noui.dart';

part 'svg_graph_text.dart';

///
/// A document object model representing an asset that can be turned into
/// a `ScalableImage`.  Normally this is obtained by parsing an
/// SVG XML file (or, internally, by parsing an Android AVD XML file).
/// See also `SVGDomManager`.
///
/// {@category SVG DOM}
///
class SvgDOM {
  Map<String, SvgNode>? _idLookup;

  ///
  /// The root node of the DOM.
  ///
  final SvgRoot root;

  ///
  /// The stylesheet that will be applied when a `ScalableImage` is
  /// created.  See
  /// https://www.w3.org/TR/2011/REC-SVG11-20110816/styling.html#StylingWithCSS .
  ///
  Stylesheet stylesheet;
  double? width;
  double? height;

  ///
  /// The RGB value of a tint that can be applied to the asset.  This
  /// is not present in SVG; it comes from the Android Vector Drawable
  /// format.
  ///
  int? tintColor; // For AVD

  ///
  /// The drawing mode to be used when appying a tint.
  /// See [tintColor].
  ///
  SITintMode? tintMode; // For AVD

  bool _resolved = false;

  SvgDOM(this.root, this.stylesheet, this.width, this.height, this.tintColor,
      this.tintMode);

  ///
  /// A table used to look up nodes by their string ID.  Note that this table
  /// is _not_ rebuilt automatically if the [SvgDOM] is modified
  /// programmatically.  See [resetIDLookup].
  ///
  Map<String, SvgNode> get idLookup {
    var r = _idLookup;
    if (r == null) {
      _idLookup = r = {};
      root._addIDs(r);
    }
    return r;
  }

  ///
  /// Determine the bounds, for use in user space calculations (e.g.
  /// potentially for gradients).  This must not be accessed before
  /// `build`, but it may be called during the build process.
  ///
  /// If a viewbox or a width/height are
  /// given in the asset, this is well-defined.  If not, we use a
  /// reasonably accurate estimate of a bounding rectangle.  The SVG spec
  /// speaks of this bounding rectangle not taking into account stroke widths,
  /// so we don't, but our estimate of font metrics is (ahem) approximate.
  /// Most SVG assets should at least provide a width/height; for those that
  /// don't, our bounding box gives a reasonable estimate.
  ///
  late final RectT _userSpaceBounds = _calculateBounds();

  RectT _calculateBounds() {
    assert(_resolved);
    final w = width;
    final h = height;
    // w and h come from width/height on the SVG asset, or, if not given,
    // from the viewBox attribute's width/height.
    if (w != null && h != null) {
      final t = root.transform;
      if (t != null) {
        final b =
            _SvgBoundary(const RectT(0, 0, 1, 1)).transformed(t).getBounds();
        return RectT(0, 0, w / b.width, h / b.height);
      } else {
        return RectT(0, 0, w, h);
      }
    }
    final b = root._getUserSpaceBoundary(SvgTextStyle._initial());
    if (b == null) {
      // e.g. because this SVG is just an empty group
      return const Rectangle(0.0, 0.0, 100.0, 100.0);
    } else {
      return b.getBounds();
    }
  }

  void _build(SIBuilder<String, SIImageData> builder) {
    if (stylesheet.isNotEmpty) {
      root._applyStylesheet(stylesheet, builder.warn);
    }
    RectT userSpace() => _userSpaceBounds;
    final rootPaint = SvgPaint._root(userSpace);
    final rootTA = SvgTextStyle._initial();
    SvgNode? newRoot = root._resolve(_ResolveContext(idLookup, builder.warn),
        rootPaint, _SvgNodeReferrers(this));
    _resolved = true;
    builder.vector(
        width: width, height: height, tintColor: tintColor, tintMode: tintMode);

    // Collect canonicalized data by doing a build dry run.  We skip the
    // paths and other stuff that doesn't generate canonicalized data, so
    // this is quite fast.
    final theCanon = CanonicalizedData<SIImageData>();
    final cb = _CollectCanonBuilder(theCanon);
    cb.init(cb.initial, const [], const [], const [], const [], const [], null);
    cb.vector(
        width: width, height: height, tintColor: tintColor, tintMode: tintMode);
    newRoot?._build(cb, theCanon, idLookup, rootPaint, rootTA);
    cb.endVector();
    cb.traversalDone();

    // Now we can do the real building run.
    builder.init(
        null,
        theCanon.images.toList(),
        theCanon.strings.toList(),
        const [], // float lists aren't canonicalized; they're marginal
        theCanon.getStringLists(),
        theCanon.floatValues.toList(),
        theCanon.floatValues);
    newRoot?._build(builder, theCanon, idLookup, rootPaint, rootTA);
    builder.endVector();
    builder.traversalDone();
  }

  ///
  /// Reset the [idLookup] table.  If it is subsequently accessed,
  /// it will be rebuilt automatically, in an O(n) operation on the number
  /// of nodes in the DOM.
  ///
  /// Client code can change the DOM,
  /// adding or removing nodes, or changing the `id` values of nodes.
  /// The lookup table is __not__ automatically reset when this
  /// happens.  After one or more such modifications, client code
  /// should call this method if it plans to subsequently look up
  /// nodes by name.
  ///
  void resetIDLookup() {
    _idLookup = null;
  }

  ///
  /// Make a clone of this parse graph.  This is useful if you want to
  /// build (and display) a ScalableImage from th is parse graph, then
  /// make some changes, and display the result.  Building a ScalableImage
  /// from a parse graph is a destructive operation - it can only be done
  /// once per `SvgParseGraph` instance.  By cloning the parse graph each time,
  /// you keep an un-built version around.
  ///
  /// Throws [StateError] if this [SvgDOM] has been built.
  SvgDOM _clone() {
    if (_resolved) {
      throw StateError('Parse graph has already been built');
    }
    final r =
        SvgDOM(root._clone(), stylesheet, width, height, tintColor, tintMode);
    return r;
  }

  void _visitPaths(void Function(Object pathKey) f) => root._visitPaths(f);

  void _cloneAttributes() => root._cloneAttributes();
}

class _CollectCanonBuilder implements SIBuilder<String, SIImageData> {
  final CanonicalizedData<SIImageData> canon;
  ColorWriter? _colorWriter;
  ColorWriter get colorWriter =>
      _colorWriter ??
      (_colorWriter = ColorWriter(
          DataOutputSink(_NullSink()), (_) => null, _collectSharedFloat));

  _CollectCanonBuilder(this.canon);

  void collectPaint(SIPaint paint) {
    colorWriter.writeColor(paint.fillColor);
    colorWriter.writeColor(paint.strokeColor);
  }

  void _collectSharedFloat(double value) => canon.floatValues[value];

  @override
  void init(
      void collector,
      List<SIImageData> im,
      List<String> strings,
      List<List<double>> floatLists,
      List<List<String>> stringLists,
      List<double> floatValues,
      CMap<double>? floatValueMap) {}

  @override
  void vector(
      {required double? width,
      required double? height,
      required int? tintColor,
      required SITintMode? tintMode}) {}

  @override
  void endVector() {}

  @override
  void group(
      void collector, Affine? transform, int? groupAlpha, SIBlendMode blend) {}

  @override
  void endGroup(void collector) {}

  @override
  void path(void collector, String pathData, SIPaint paint) =>
      collectPaint(paint);

  @override
  EnhancedPathBuilder? startPath(SIPaint paint, Object key) {
    collectPaint(paint);
    return null;
  }

  @override
  void clipPath(void collector, String pathData) {}

  @override
  void masked(void collector, RectT? maskBounds, bool usesLuma) {}

  @override
  void maskedChild(void collector) {}

  @override
  void endMasked(void collector) {}

  @override
  void image(void collector, int imageIndex) {}

  @override
  void legacyText(void collector, int xIndex, int yIndex, int textIndex,
      SITextAttributes a, int? fontFamilyIndex, SIPaint paint) {
    // No collectAttributes() because the legacy format doesn't use
    // canonicalized data for that.
    collectPaint(paint); // coverage:ignore-line
  }

  @override
  void text(void collector) {}

  @override
  void textMultiSpanChunk(
      void collector, int dxIndex, int dyIndex, SITextAnchor anchor) {}

  @override
  void textSpan(
      void collector,
      int dxIndex,
      int dyIndex,
      int textIndex,
      SITextAttributes attributes,
      int? fontFamilyIndex,
      int fontSizeIndex,
      SIPaint paint) {
    collectPaint(paint);
  }

  @override
  void textEnd(void collector) {}

  @override
  void exportedID(void collector, int idIndex) {}

  @override
  void endExportedID(void collector) {}

  @mustCallSuper
  @override
  void traversalDone() {
    _colorWriter?.close();
  }

  @override
  void get initial {} // coverage:ignore-line

  @override
  void addPath(Object path, SIPaint paint) {}

  @override
  void Function(String) get warn => (_) {};
}

///
/// An entry in the list of styles for a given element type or node ID in a
/// [Stylesheet].
///
/// {@category SVG DOM}
///
class Style extends SvgInheritableAttributes {
  Style() : super._p();

  // We inherit an applyStyle implementation that's unreachable, so we need to
  // stub this out.
  @override
  String? get _idForApplyStyle => null;

  void _applyText(
      SvgInheritableTextAttributes node, void Function(String) warn) {
    // NOTE:  Don't try to optimize by using node._paint or node._textStyle.
    // That wouldn't work with SvgText, and besides, any memory allocated
    // here would be short-lived.
    node.paint._takeFrom(this, warn);
    node.textStyle._takeFrom(this);
  }

  void _apply(SvgInheritableAttributes node, void Function(String) warn) {
    _applyText(node, warn);
    final st = transform;
    if (st != null) {
      final nt = node.transform;
      if (nt == null) {
        node.transform = st.mutableCopy();
      } else {
        nt.multiplyBy(st);
      }
    }
    // NOTE:  SVG's transform isn't the same as CSS's.  SVG's is almost
    // certainly simpler, but there may be other differences.  The line above
    // assumes they're the same.  Depending on how different they are, for full
    // support it might even be necessary to treat them as different things.
    // For example, the origin for SVG's transforms is 0,0; maybe CSS does
    // something different?

    node.blendMode = node.blendMode ?? blendMode;
    node.groupAlpha = node.groupAlpha ?? groupAlpha;
  }

  @override
  String get tagName => 'style'; // coverage:ignore-line
  // Not used
}

///
/// A stylesheet is a map from a tagName or a node ID to a list of [Style]
/// instances.  A tagName
/// is like "tspan" or "", and an ID starts with "#".  The
/// [Style] instances will be in the order they were encountered in the
/// SVG source file.
///
/// {@category SVG DOM}
///
typedef Stylesheet = Map<String, List<Style>>;

///
/// Common supertype for all nodes in an SVG DOM graph.
///
/// {@category SVG DOM}
///
sealed class SvgNode {
  SvgNode._p();

  void _applyStylesheet(Stylesheet stylesheet, void Function(String) warn);

  void _cloneAttributes();

  SvgNode? _resolve(
      _ResolveContext ctx, SvgPaint ancestor, _SvgNodeReferrers referrers);

  bool _build(
      SIBuilder<String, SIImageData> builder,
      CanonicalizedData<SIImageData> canon,
      Map<String, SvgNode> idLookup,
      SvgPaint ancestor,
      SvgTextStyle ta,
      {bool blendHandledByParent = false});

  ///
  /// If this node is in a mask, is it possible it might use the luma
  /// channel?  cf. SIMaskHelper.startLumaMask().
  ///
  bool _canUseLuma(Map<String, SvgNode> idLookup, SvgPaint ancestor);

  ///
  /// The blend mode to use when painting this node.
  ///
  SIBlendMode? get blendMode;

  _SvgBoundary? _getUserSpaceBoundary(SvgTextStyle ta);

  ///
  /// The ID value used to look up this node.  See also
  /// [SvgDOM.resetIDLookup].
  ///
  String? id;

  ///
  /// Is the ID exported?  Exported IDs are specified when reading
  /// an SVG; only nodes with exported IDs will have corresponding
  /// `ExportedID` values.
  ///
  bool idIsExported = false;

  ///
  /// Get the exported ID value, or null.
  ///
  String? get exportedID => idIsExported ? id : null;

  ///
  /// Make a copy of this node, if it has state that changes
  /// during the build process.
  ///
  SvgNode _clone();

  void _visitPaths(void Function(Object pathKey) f) {}

  @mustCallSuper
  void _addIDs(Map<String, SvgNode> idLookup) {
    final i = id;
    if (i != null) {
      idLookup[i] = this;
    }
  }
}

class _NullSink<T> implements Sink<T> {
  @override
  void add(T data) {}

  @override
  void close() {}
}

//
// Things that refer to a node, like a group.
// This is used to catch reference loops.
//
class _SvgNodeReferrers {
  final Object? referrer;
  final _SvgNodeReferrers? parent;

  _SvgNodeReferrers(this.referrer, [this.parent]);

  bool contains(SvgNode n) {
    _SvgNodeReferrers? s = this;
    while (s != null) {
      if (identical(s.referrer, n)) {
        return true;
      }
      s = s.parent;
    }
    return false;
  }
}

///
/// Attributes of an SVG element that are inherited from an ancestor
/// node, and that are also present in an [SvgTextSpan] within
/// an SVG `text` element..
///
/// {@category SVG DOM}
///
abstract class SvgInheritableTextAttributes {
  ///
  /// The paint parameters to use when rendering a node.
  ///
  SvgPaint get paint => _paint = (_paint ?? SvgPaint.empty());
  set paint(SvgPaint v) => _paint = v;
  SvgPaint? _paint;

  ///
  /// The text styling information to use when rendering a node
  ///
  SvgTextStyle get textStyle =>
      _textStyle = (_textStyle ?? SvgTextStyle.empty());
  set textStyle(SvgTextStyle v) => _textStyle = v;
  SvgTextStyle? _textStyle;

  ///
  /// The [Stylesheet] `class` value for CSS [Style] instances to be applied
  /// to this node.
  ///
  String styleClass;

  SvgInheritableTextAttributes._p() : styleClass = '';

  SvgInheritableTextAttributes._withPaint(SvgPaint paint)
      : _paint = paint,
        styleClass = '';

  SvgInheritableTextAttributes._cloned(SvgInheritableTextAttributes other)
      : _paint = other._paint?._clone(),
        _textStyle = other._textStyle?._clone(),
        styleClass = other.styleClass;

  @mustCallSuper
  void _cloneAttributes() {
    _paint = _paint?._clone();
    _textStyle = _textStyle?._clone();
  }

  ///
  /// The tag name of this node, to be used when matching CSS [Style]
  /// instances.
  ///
  String get tagName;
  // WARNING:  Any fields added here need to be shadowed in SvgText,
  // to redirect to the first text span.

  String? get _idForApplyStyle;

  bool _isInvisible(SvgPaint cascaded) {
    return cascaded.hidden == true ||
        ((cascaded.strokeAlpha == 0 || cascaded.strokeColor == SvgColor.none) &&
            (cascaded.fillAlpha == 0 || cascaded.fillColor == SvgColor.none) &&
            !cascaded.inClipPath);
  }

  static final _whitespace = RegExp(r'\s+');

  @mustCallSuper
  void _applyStylesheet(Stylesheet stylesheet, void Function(String) warn) {
    final ourClasses = styleClass.trim().split(_whitespace).toSet();
    if (ourClasses.isNotEmpty) {
      for (final tag in [tagName, '']) {
        final List<Style>? styles = stylesheet[tag];
        if (styles != null) {
          for (int i = styles.length - 1; i >= 0; i--) {
            final s = styles[i];
            if (ourClasses.contains(s.styleClass)) {
              _takeFrom(s, warn);
            }
          }
        }
      }
    }
    void applyStyles(List<Style>? styles) {
      if (styles != null) {
        for (int i = styles.length - 1; i >= 0; i--) {
          final s = styles[i];
          if (s.styleClass == '') {
            _takeFrom(s, warn);
          }
        }
      }
    }

    applyStyles(stylesheet[tagName]);

    if (_idForApplyStyle != null) {
      applyStyles(stylesheet['#$_idForApplyStyle']);
    }
  }

  @protected
  void _takeFrom(Style s, void Function(String) warn) {
    s._applyText(this, warn);
  }
}

///
/// Attributes of an SVG element that are inherited from an ancestor
/// node.  These attributes are also present in [Style] instances.
///
/// {@category SVG DOM}
///
abstract class SvgInheritableAttributes extends SvgInheritableTextAttributes {
  ///
  /// Transformation(s) to apply to a node, in matrix form.
  ///
  MutableAffine? transform;

  ///
  /// Is this element displayed?
  ///
  bool display = true;

  ///
  /// An alpha value to apply when painting a node and its descendants.
  ///
  int? groupAlpha; // Doesn't inherit; instead, a group is created

  ///
  /// The blend mode to use when painting a node.
  ///
  SIBlendMode? blendMode;
  // Doesn't inherit; instead, a group is created

  SvgInheritableAttributes._p() : super._p();

  SvgInheritableAttributes._withPaint(super.paint) : super._withPaint();

  SvgInheritableAttributes._cloned(SvgInheritableAttributes super.other)
      : transform = other.transform?.mutableCopy(),
        display = other.display,
        groupAlpha = other.groupAlpha,
        blendMode = other.blendMode,
        super._cloned();

  @override
  @mustCallSuper
  void _cloneAttributes() {
    super._cloneAttributes();
    transform = transform?.mutableCopy();
  }

  @override
  void _takeFrom(Style s, void Function(String) warn) {
    s._apply(this, warn);
  }
}

///
/// Common supertype of nodes that can contain the attributes that are inherited
/// by children.
///
/// {@category SVG DOM}
///
abstract class SvgInheritableAttributesNode extends SvgInheritableAttributes
    implements SvgNode {
  @override
  String? id;

  @override
  bool idIsExported = false;

  @override
  String? get exportedID => idIsExported ? id : null;

  SvgInheritableAttributesNode._p() : super._p();

  SvgInheritableAttributesNode._withPaint(super.paint) : super._withPaint();

  SvgInheritableAttributesNode._cloned(SvgInheritableAttributesNode super.other)
      : id = other.id,
        idIsExported = other.idIsExported,
        super._cloned();

  @override
  String? get _idForApplyStyle => id;

  @override
  void _visitPaths(void Function(Object pathKey) f) {}

  @mustCallSuper
  @override
  void _addIDs(Map<String, SvgNode> idLookup) {
    final i = id;
    if (i != null) {
      idLookup[i] = this;
    }
  }

  @override
  bool _isInvisible(SvgPaint cascaded) =>
      !display || super._isInvisible(cascaded);

  @override
  _SvgBoundary? _getUserSpaceBoundary(SvgTextStyle ta) {
    RectT? bounds = _getUntransformedBounds(ta);
    if (bounds == null) {
      return null;
    } else {
      final b = _SvgBoundary(bounds);
      final t = transform;
      if (t == null) {
        return b;
      } else {
        return b.transformed(t);
      }
    }
  }

  @protected
  RectT? _getUntransformedBounds(SvgTextStyle ta);

  SvgNode _resolveMask(
      _ResolveContext ctx, SvgPaint ancestor, _SvgNodeReferrers referrers) {
    if (paint.mask != null) {
      SvgNode? n = ctx.generatedFor[this];
      if (n != null) {
        return n;
      }
      n = ctx.idLookup[paint.mask];
      if (n is SvgMask) {
        if (referrers.contains(n)) {
          ctx.warn('    Ignoring mask that refers to itself.');
        } else {
          final masked = _SvgMasked(this, n);
          bool hasNonMaskAttributesExceptPaint = transform != null ||
              (_textStyle != null && textStyle != SvgTextStyle.empty()) ||
              groupAlpha != null ||
              (blendMode ?? SIBlendMode.normal) != SIBlendMode.normal;
          if (hasNonMaskAttributesExceptPaint) {
            final g = SvgGroup();
            g.transform = transform;
            transform = null;
            g._textStyle = _textStyle;
            _textStyle = null;
            g.groupAlpha = groupAlpha;
            groupAlpha = null;
            g.blendMode = blendMode;
            blendMode = SIBlendMode.normal;
            g.children.add(masked);
            ctx.generatedFor[this] = g;
            return g;
          } else {
            ctx.generatedFor[this] = masked;
            return masked;
          }
        }
      } else {
        ctx.warn('    $tagName references nonexistent mask ${paint.mask}');
      }
    }
    return this;
  }
}

///
/// Parameters used to control the painting of an SVG
/// node.  See
/// https://www.w3.org/TR/2008/REC-SVGTiny12-20081222/painting.html .
///
/// {@category SVG DOM}
///
class SvgPaint {
  SvgColor currentColor;
  SvgColor fillColor;
  int? fillAlpha;
  SvgColor strokeColor;
  int? strokeAlpha;
  double? strokeWidth;
  double? strokeMiterLimit;
  SIStrokeJoin? strokeJoin;
  SIStrokeCap? strokeCap;
  SIFillType? fillType;
  SIFillType? clipFillType;
  bool inClipPath;
  List<double>? strokeDashArray; // [] for "none"
  double? strokeDashOffset;
  bool? hidden;
  String? mask; // Not inherited
  final RectT Function() _userSpace; // only inherited (from root)

  SvgPaint._filled(
      {required this.currentColor,
      required this.fillColor,
      required this.fillAlpha,
      required this.strokeColor,
      required this.strokeAlpha,
      required this.strokeWidth,
      required this.strokeMiterLimit,
      required this.strokeJoin,
      required this.strokeCap,
      required this.fillType,
      required this.clipFillType,
      required this.inClipPath,
      required this.strokeDashArray,
      required this.strokeDashOffset,
      required this.hidden,
      required this.mask,
      required Rectangle<double> Function() userSpace})
      : _userSpace = userSpace;

  SvgPaint.empty()
      : fillColor = SvgColor.inherit,
        strokeColor = SvgColor.inherit,
        currentColor = SvgColor.inherit,
        inClipPath = false,
        _userSpace = _dummy;

  SvgPaint._root(this._userSpace)
      : fillColor = const SvgValueColor(0xff000000),
        currentColor = SvgColor.currentColor, // Inherit from SVG container
        strokeColor = SvgColor.none,
        inClipPath = false;

  SvgPaint _clone() {
    assert(_userSpace == _dummy);
    return SvgPaint._filled(
        currentColor: currentColor,
        fillColor: fillColor,
        fillAlpha: fillAlpha,
        strokeColor: strokeColor,
        strokeAlpha: strokeAlpha,
        strokeWidth: strokeWidth,
        strokeMiterLimit: strokeMiterLimit,
        strokeJoin: strokeJoin,
        strokeCap: strokeCap,
        fillType: fillType,
        clipFillType: clipFillType,
        inClipPath: inClipPath,
        strokeDashArray: strokeDashArray,
        strokeDashOffset: strokeDashOffset,
        hidden: hidden,
        mask: mask,
        userSpace: _userSpace);
  }

  static RectT _dummy() => const RectT(0, 0, 0, 0);

  SvgPaint _cascade(SvgPaint ancestor, Map<String, SvgNode>? idLookup,
      void Function(String) warn) {
    return SvgPaint._filled(
        currentColor:
            currentColor._orInherit(ancestor.currentColor, idLookup, warn),
        fillColor: fillColor._orInherit(ancestor.fillColor, idLookup, warn),
        fillAlpha: fillAlpha ?? ancestor.fillAlpha,
        strokeColor:
            strokeColor._orInherit(ancestor.strokeColor, idLookup, warn),
        strokeAlpha: strokeAlpha ?? ancestor.strokeAlpha,
        strokeWidth: strokeWidth ?? ancestor.strokeWidth,
        strokeMiterLimit: strokeMiterLimit ?? ancestor.strokeMiterLimit,
        strokeJoin: strokeJoin ?? ancestor.strokeJoin,
        strokeCap: strokeCap ?? ancestor.strokeCap,
        fillType: fillType ?? ancestor.fillType,
        clipFillType: clipFillType ?? ancestor.clipFillType,
        inClipPath: inClipPath || ancestor.inClipPath,
        strokeDashArray: strokeDashArray ?? ancestor.strokeDashArray,
        strokeDashOffset: strokeDashOffset ?? ancestor.strokeDashOffset,
        mask: null, // Mask is not inherited
        hidden: hidden ?? ancestor.hidden,
        userSpace: ancestor._userSpace); // userSpace is inherited from root
  }

  void _takeFrom(Style style, void Function(String) warn) {
    currentColor =
        currentColor._orInherit(style.paint.currentColor, null, warn);
    fillColor = fillColor._orInherit(style.paint.fillColor, null, warn);
    fillAlpha = fillAlpha ?? style.paint.fillAlpha;
    strokeColor = strokeColor._orInherit(style.paint.strokeColor, null, warn);
    strokeAlpha = strokeAlpha ?? style.paint.strokeAlpha;
    strokeWidth = strokeWidth ?? style.paint.strokeWidth;
    strokeMiterLimit = strokeMiterLimit ?? style.paint.strokeMiterLimit;
    strokeJoin = strokeJoin ?? style.paint.strokeJoin;
    strokeCap = strokeCap ?? style.paint.strokeCap;
    fillType = fillType ?? style.paint.fillType;
    clipFillType = clipFillType ?? style.paint.clipFillType;
    inClipPath = inClipPath || style.paint.inClipPath;
    strokeDashArray = strokeDashArray ?? style.paint.strokeDashArray;
    strokeDashOffset = strokeDashOffset ?? style.paint.strokeDashOffset;
    hidden = hidden ?? style.paint.hidden;
    mask = mask ?? style.paint.mask;
  }

  @override
  int get hashCode =>
      0x5390dc64 ^
      Object.hash(
          fillColor,
          fillAlpha,
          strokeColor,
          strokeAlpha,
          strokeWidth,
          strokeMiterLimit,
          currentColor,
          hidden,
          mask,
          strokeJoin,
          strokeCap,
          fillType,
          clipFillType,
          inClipPath,
          strokeDashOffset,
          Object.hashAll(strokeDashArray ?? const []));

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    } else if (other is SvgPaint) {
      return currentColor == other.currentColor &&
          fillColor == other.fillColor &&
          fillAlpha == other.fillAlpha &&
          strokeColor == other.strokeColor &&
          strokeAlpha == other.strokeAlpha &&
          strokeWidth == other.strokeWidth &&
          strokeMiterLimit == other.strokeMiterLimit &&
          currentColor == other.currentColor &&
          mask == other.mask &&
          hidden == other.hidden &&
          strokeJoin == other.strokeJoin &&
          strokeCap == other.strokeCap &&
          fillType == other.fillType &&
          clipFillType == other.clipFillType &&
          inClipPath == other.inClipPath &&
          (const ListEquality<double>())
              .equals(strokeDashArray, other.strokeDashArray) &&
          strokeDashOffset == other.strokeDashOffset;
    } else {
      return false;
    }
  }

  SIPaint _toSIPaint() {
    if (hidden == true) {
      // Hidden nodes should be optimized away
      return unreachable(SIPaint(
          fillColor: SIColor.none,
          strokeColor: SIColor.none,
          strokeWidth: 0,
          strokeMiterLimit: 4,
          strokeJoin: SIStrokeJoin.miter,
          strokeCap: SIStrokeCap.butt,
          fillType: fillType ?? SIFillType.nonZero,
          strokeDashArray: null,
          strokeDashOffset: null));
    } else if (inClipPath) {
      // See SVG 1.1, s. 14.3.5
      return SIPaint(
          fillColor: SIColor.white,
          strokeColor: SIColor.none,
          strokeWidth: 0,
          strokeMiterLimit: 4,
          strokeJoin: SIStrokeJoin.miter,
          strokeCap: SIStrokeCap.butt,
          fillType: clipFillType ?? SIFillType.nonZero,
          strokeDashArray: null,
          strokeDashOffset: null);
    } else {
      // After cascading, fillAlpha and strokeAlpha cannot be null.
      return SIPaint(
          fillColor:
              fillColor._toSIColor(fillAlpha ?? 0xff, currentColor, _userSpace),
          strokeColor: strokeColor._toSIColor(
              strokeAlpha ?? 0xff, currentColor, _userSpace),
          strokeWidth: strokeWidth ?? 1,
          strokeMiterLimit: strokeMiterLimit ?? 4,
          strokeJoin: strokeJoin ?? SIStrokeJoin.miter,
          strokeCap: strokeCap ?? SIStrokeCap.butt,
          fillType: fillType ?? SIFillType.nonZero,
          strokeDashArray: strokeDashArray,
          strokeDashOffset: strokeDashArray == null ? null : strokeDashOffset);
    }
  }
}

///
/// An SVG `g` node.  See
/// https://www.w3.org/TR/2008/REC-SVGTiny12-20081222/struct.html#Groups .
///
/// {@category SVG DOM}
///
class SvgGroup extends SvgInheritableAttributesNode {
  var children = List<SvgNode>.empty(growable: true);
  @protected
  bool get _multipleNodesOK => false;

  SvgGroup({SvgPaint? paint}) : super._withPaint(paint ?? SvgPaint.empty());

  SvgGroup._cloned(SvgGroup super.other)
      : children = List.from(other.children.map((n) => n._clone())),
        super._cloned();

  @override
  SvgGroup _clone() => SvgGroup._cloned(this);

  @override
  @mustCallSuper
  void _cloneAttributes() {
    super._cloneAttributes();
    for (final c in children) {
      c._cloneAttributes();
    }
  }

  @override
  void _visitPaths(void Function(Object pathKey) f) {
    for (final c in children) {
      c._visitPaths(f);
    }
  }

  @override
  String get tagName => 'g';

  @override
  void _applyStylesheet(Stylesheet stylesheet, void Function(String) warn) {
    super._applyStylesheet(stylesheet, warn);
    for (final c in children) {
      c._applyStylesheet(stylesheet, warn);
    }
  }

  @override
  SvgNode? _resolve(
      _ResolveContext ctx, SvgPaint ancestor, _SvgNodeReferrers referrers) {
    final cascaded = _paint == null
        ? ancestor
        : paint._cascade(ancestor, ctx.idLookup, ctx.warn);
    final newC = List<SvgNode>.empty(growable: true);
    referrers = _SvgNodeReferrers(this, referrers);
    for (SvgNode n in children) {
      final nn = n._resolve(ctx, cascaded, referrers);
      if (nn != null) {
        newC.add(nn);
      }
    }
    children = newC;
    if (children.isEmpty) {
      return null;
    } else if (transform?.determinant() == 0.0) {
      return null;
    } else {
      return _resolveMask(ctx, ancestor, referrers);
    }
  }

  @override
  RectT? _getUntransformedBounds(SvgTextStyle ta) {
    final currTA = _textStyle == null ? ta : textStyle._cascade(ta);
    RectT? curr;
    for (final ch in children) {
      final boundary = ch._getUserSpaceBoundary(currTA);
      if (boundary != null) {
        final b = boundary.getBounds();
        if (curr == null) {
          curr = b;
        } else {
          curr = curr.boundingBox(b);
        }
      }
    }
    return curr;
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
    final currTA = _textStyle == null ? ta : textStyle._cascade(ta);
    final cascaded = _paint == null
        ? ancestor
        : paint._cascade(ancestor, idLookup, builder.warn);
    if (transform == null &&
        groupAlpha == null &&
        blend == SIBlendMode.normal &&
        (children.length == 1 || _multipleNodesOK) &&
        exportedID == null) {
      bool r = false;
      for (final c in children) {
        r = c._build(builder, canon, idLookup, cascaded, currTA) || r;
      }
      return r;
    } else {
      if (exportedID != null) {
        builder.exportedID(null, canon.strings[exportedID!]);
      }
      builder.group(null, transform, groupAlpha, blend);
      for (final c in children) {
        c._build(builder, canon, idLookup, cascaded, currTA);
      }
      builder.endGroup(null);
      if (exportedID != null) {
        builder.endExportedID(null);
      }
      return true;
    }
  }

  @override
  bool _canUseLuma(Map<String, SvgNode> idLookup, SvgPaint ancestor) {
    final cascaded =
        _paint == null ? ancestor : paint._cascade(ancestor, idLookup, (_) {});
    for (final ch in children) {
      if (ch._canUseLuma(idLookup, cascaded)) {
        return true;
      }
    }
    return false;
  }
}

///
/// The root node of an `SvgDOM`.
///
/// {@category SVG DOM}
///
class SvgRoot extends SvgGroup {
  SvgRoot();

  SvgRoot._cloned(SvgRoot super.other) : super._cloned();

  @override
  bool get _multipleNodesOK => true;

  @override
  String get tagName => 'svg';

  @override
  SvgRoot _clone() => SvgRoot._cloned(this);
}

///
/// An SVG definitions node.  See
/// https://www.w3.org/TR/2008/REC-SVGTiny12-20081222/struct.html#DefsElement .
///
/// {@category SVG DOM}
///
class SvgDefs extends SvgGroup {
  @override
  final String tagName;

  SvgDefs(this.tagName) : super();

  SvgDefs._cloned(SvgDefs super.other)
      : tagName = other.tagName,
        super._cloned();

  @override
  SvgDefs _clone() => SvgDefs._cloned(this);

  @override
  SvgNode? _resolve(
      _ResolveContext ctx, SvgPaint ancestor, _SvgNodeReferrers referrers) {
    super._resolve(ctx, ancestor, referrers);
    return null;
  }

  @override
  bool _build(
      SIBuilder<String, SIImageData> builder,
      CanonicalizedData<SIImageData> canon,
      Map<String, SvgNode> idLookup,
      SvgPaint ancestor,
      SvgTextStyle ta,
      {bool blendHandledByParent = false}) {
    return unreachable(false);
  }

  @override
  RectT? _getUntransformedBounds(SvgTextStyle ta) => unreachable(null);
}

///
/// An SVG `mask`.  See
/// https://www.w3.org/TR/2011/REC-SVG11-20110816/masking.html#MaskElement .
///
/// {@category SVG DOM}
///
class SvgMask extends SvgGroup {
  SvgMask();

  SvgMask._cloned(SvgMask super.other)
      : bufferBounds = other.bufferBounds,
        super._cloned();

  @override
  SvgMask _clone() => SvgMask._cloned(this);

  RectT? bufferBounds;

  @override
  SvgNode? _resolve(
      _ResolveContext ctx, SvgPaint ancestor, _SvgNodeReferrers referrers) {
    super._resolve(ctx, ancestor, _SvgNodeReferrers(this, referrers));
    return null;
  }
}

///
/// A parent node for a node with a mask attribute.
///
class _SvgMasked extends SvgNode {
  final SvgNode child;
  SvgMask mask;

  _SvgMasked(this.child, this.mask) : super._p() {
    id = child.id;
    idIsExported = child.idIsExported;
    child.id = null;
    child.idIsExported = false;
  }

  @override
  _SvgMasked _clone() => unreachable(this);
  // Clone can only happen before resolve, so there can't be any masked
  // nodes.

  @override
  void _cloneAttributes() => unreachable(null);

  @override
  void _applyStylesheet(Stylesheet stylesheet, void Function(String) warn) {
    assert(false);
    // Do nothing - stylesheets are applied before Masked are created.
  }

  @override
  _SvgBoundary? _getUserSpaceBoundary(SvgTextStyle ta) {
    final m = mask._getUserSpaceBoundary(ta);
    if (m == null) {
      return m;
    }
    final c = child._getUserSpaceBoundary(ta);
    if (c == null) {
      return c;
    }
    final i = c.getBounds().intersection(m.getBounds());
    if (i == null) {
      return null;
    } else {
      return _SvgBoundary(i);
    }
  }

  @override
  bool _build(
      SIBuilder<String, SIImageData> builder,
      CanonicalizedData<SIImageData> canon,
      Map<String, SvgNode> idLookup,
      SvgPaint ancestor,
      SvgTextStyle ta,
      {bool blendHandledByParent = false}) {
    final blend = blendHandledByParent
        ? SIBlendMode.normal
        : (blendMode ?? SIBlendMode.normal);
    assert(blend == SIBlendMode.normal);
    // Blend is handled by a parent group inserted above us in resolveMask().
    bool canUseLuma = mask._canUseLuma(idLookup, ancestor);
    if (exportedID != null) {
      builder.exportedID(null, canon.strings[exportedID!]);
    }
    builder.masked(null, mask.bufferBounds, canUseLuma);
    bool built = mask._build(builder, canon, idLookup, ancestor, ta);
    if (!built) {
      builder.group(null, null, null, SIBlendMode.normal);
      builder.endGroup(null);
    }
    builder.maskedChild(null);
    built = child._build(builder, canon, idLookup, ancestor, ta,
        blendHandledByParent: true);
    if (!built) {
      builder.group(null, null, null, SIBlendMode.normal);
      builder.endGroup(null);
    }
    builder.endMasked(null);
    if (exportedID != null) {
      builder.endExportedID(null);
    }
    return true;
  }

  @override
  SvgNode? _resolve(
      _ResolveContext ctx, SvgPaint ancestor, _SvgNodeReferrers referrers) {
    // We're added during resolve, so this is unreachable
    return unreachable(null);
  }

  @override
  void _visitPaths(void Function(Object pathKey) f) => unreachable(null);

  @override
  void _addIDs(Map<String, SvgNode> idLookup) {
    super._addIDs(idLookup);
    unreachable(null);
  }

  @override
  bool _canUseLuma(Map<String, SvgNode> idLookup, SvgPaint ancestor) =>
      child._canUseLuma(idLookup, ancestor);
  // The mask can only change the alpha channel.

  @override
  SIBlendMode? get blendMode => child.blendMode;
}

///
/// An SVG `use`.  See
/// https://www.w3.org/TR/2011/REC-SVG11-20110816/struct.html#UseElement .
///
/// {@category SVG DOM}
///
class SvgUse extends SvgInheritableAttributesNode {
  ///
  /// The [id] of the node we refer to
  ///
  String? childID;

  double? width;
  double? height;

  SvgUse(this.childID) : super._p();

  SvgUse._cloned(SvgUse super.other)
      : childID = other.childID,
        width = other.width,
        height = other.height,
        super._cloned() {
    // We might modify the transform during resolve, so we copy it here.
    transform = transform?.mutableCopy();
  }

  @override
  SvgUse _clone() => SvgUse._cloned(this);

  @override
  String get tagName => 'use';

  @override
  SvgNode? _resolve(
      _ResolveContext ctx, SvgPaint ancestor, _SvgNodeReferrers referrers) {
    if (childID == null) {
      ctx.warn('    <use> has no href');
      return null;
    }
    SvgNode? n = ctx.idLookup[childID];
    if (n == null) {
      ctx.warn('    <use> references nonexistent $childID');
      return null;
    } else if (referrers.contains(n)) {
      ctx.warn('    Ignoring <use> that refers to itself.');
      return null;
    }
    final cascaded = _paint == null
        ? ancestor
        : paint._cascade(ancestor, ctx.idLookup, ctx.warn);
    n = n._resolve(ctx, cascaded, referrers);
    if (n == null || transform?.determinant() == 0.0) {
      return null;
    }
    if (n is SvgSymbol && width != null && height != null) {
      // We need to scale our child, as specified in
      // https://www.w3.org/TR/2011/REC-SVG11-20110816/single-page.html#struct-UseElement
      // section 5.6, and https://github.com/zathras/jovial_svg/issues/54
      final double sx;
      final double sy;
      Rectangle<double>? symbolViewbox;
      if (n.height == null || n.width == null) {
        symbolViewbox =
            n.viewbox ?? n._getUntransformedBounds(SvgTextStyle.empty());
      }
      final w = width;
      if (w == null) {
        sx = 1;
      } else {
        final symbolWidth = n.width ?? symbolViewbox?.width;
        if (symbolWidth == null) {
          sx = 1;
        } else {
          sx = w / symbolWidth;
        }
      }
      final h = height;
      if (h == null) {
        sy = 1;
      } else {
        final symbolHeight = n.height ?? symbolViewbox?.height;
        if (symbolHeight == null) {
          sy = 1;
        } else {
          sy = h / symbolHeight;
        }
      }
      if (sx != 1 || sy != 1) {
        final t = MutableAffine.scale(sx, sy);
        if (transform == null) {
          transform = t;
        } else {
          // This is safe, because we only resove once, and on clone we copy
          // transform.
          transform!.multiplyBy(t);
        }
      }
    }
    final g = SvgGroup(paint: paint);
    g.groupAlpha = groupAlpha;
    g.transform = transform;
    g.children.add(n);
    return g._resolveMask(ctx, ancestor, referrers);
  }

  @override
  RectT? _getUntransformedBounds(SvgTextStyle ta) => unreachable(null);

  @override
  bool _build(
          SIBuilder<String, SIImageData> builder,
          CanonicalizedData<SIImageData> canon,
          Map<String, SvgNode> idLookup,
          SvgPaint ancestor,
          SvgTextStyle ta,
          {bool blendHandledByParent = false}) =>
      unreachable(false);

  @override
  bool _canUseLuma(Map<String, SvgNode> idLookup, SvgPaint ancestor) =>
      unreachable(true); // Called after resolve, so we can't get here
}

///
/// An SVG `symbol`.  See
/// https://www.w3.org/TR/2011/REC-SVG11-20110816/struct.html#SymbolElement .
///
/// {@category SVG DOM}
///
class SvgSymbol extends SvgGroup {
  SvgSymbol();

  SvgSymbol._cloned(SvgSymbol super.other)
      : viewbox = other.viewbox,
        width = other.width,
        height = other.height,
        super._cloned();

  @override
  SvgSymbol _clone() => SvgSymbol._cloned(this);

  Rectangle<double>? viewbox;
  double? width;
  double? height;
}

///
/// Common supertype of all nodes that make SVG paths.
///
/// {@category SVG DOM}
///
abstract class SvgPathMaker extends SvgInheritableAttributesNode {
  SvgPathMaker() : super._p();

  SvgPathMaker._cloned(SvgPathMaker super.other) : super._cloned();

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
    final cascaded = _paint == null
        ? ancestor
        : paint._cascade(ancestor, idLookup, builder.warn);
    if (cascaded.hidden == true) {
      return false;
    }
    if (transform != null ||
        groupAlpha != null ||
        blend != SIBlendMode.normal) {
      builder.group(null, transform, groupAlpha, blend);
      _makePath(builder, canon, cascaded);
      builder.endGroup(null);
      return true;
    } else {
      return _makePath(builder, canon, cascaded);
    }
  }

  /// Returns true if a path node is emitted
  bool _makePath(SIBuilder<String, SIImageData> builder,
      CanonicalizedData<SIImageData> canon, SvgPaint cascaded);

  @override
  bool _canUseLuma(Map<String, SvgNode> idLookup, SvgPaint ancestor) {
    final cascaded =
        _paint == null ? ancestor : paint._cascade(ancestor, idLookup, (_) {});
    final p = cascaded._toSIPaint();
    return p.canUseLuma;
  }

  int get _pathKeyHash;

  bool _pathKeyEquals(SvgPathMaker other);
}

///
/// A key to use to determine if two path maker instances will generate
/// the same path.  As a special case, this isn't used by `SvgPath`, because
/// the string path data is adequate in th is case.
///
class _PathKey {
  final SvgPathMaker node;

  _PathKey(this.node);
  @override
  bool operator ==(Object other) {
    if (other is _PathKey) {
      return node._pathKeyEquals(other.node);
    } else {
      return false;
    }
  }

  @override
  int get hashCode => node._pathKeyHash;
}

///
/// An SVG `path`.  See
/// https://www.w3.org/TR/2008/REC-SVGTiny12-20081222/paths.html#PathElement .
///
/// {@category SVG DOM}
///
class SvgPath extends SvgPathMaker {
  ///
  /// The path commands.  The syntax is specified at at
  /// https://www.w3.org/TR/2018/CR-SVG2-20181004/paths.html
  ///
  /// See [StringPathBuilder] for one tool that can be used to modify the
  /// path data.
  ///
  String pathData;

  SvgPath(this.pathData);

  SvgPath._cloned(SvgPath super.other)
      : pathData = other.pathData,
        super._cloned();

  @override
  SvgPath _clone() => SvgPath._cloned(this);

  @override
  String get tagName => 'path';

  @override
  SvgNode? _resolve(
      _ResolveContext ctx, SvgPaint ancestor, _SvgNodeReferrers referrers) {
    if (pathData == '') {
      return null;
    } else {
      return _resolveMask(ctx, ancestor, referrers);
    }
  }

  @override
  RectT? _getUntransformedBounds(SvgTextStyle ta) {
    if (pathData == '') {
      return null;
    }
    final builder = _SvgPathBoundsBuilder();
    RealPathParser(builder, pathData).parse();
    return builder.bounds;
  }

  @override
  bool _makePath(SIBuilder<String, SIImageData> builder,
      CanonicalizedData<SIImageData> canon, SvgPaint cascaded) {
    if (_isInvisible(cascaded)) {
      return false;
    }
    if (exportedID != null) {
      builder.exportedID(null, canon.strings[exportedID!]);
    }
    builder.path(null, pathData, cascaded._toSIPaint());
    if (exportedID != null) {
      builder.endExportedID(null);
    }
    return true;
  }

  @override
  void _visitPaths(void Function(Object pathKey) f) => f(pathData);

  @override
  bool _pathKeyEquals(SvgPathMaker other) => unreachable(false);
  // We use pathData as our path key

  @override
  int get _pathKeyHash => unreachable(0);
  // We use pathData as our path key
}

class _SvgPathBoundsBuilder implements EnhancedPathBuilder {
  RectT? bounds;

  void _addToBounds(RectT rect) {
    final b = bounds;
    if (b == null) {
      bounds = rect;
    } else {
      bounds = b.boundingBox(rect);
    }
  }

  @override
  void addOval(RectT rect) => unreachable(_addToBounds(rect));

  @override
  void arcToPoint(PointT arcEnd,
          {required RadiusT radius,
          required double rotation,
          required bool largeArc,
          required bool clockwise}) =>
      _addToBounds(RectT.fromPoints(arcEnd, arcEnd));

  @override
  void close() {}

  @override
  void cubicTo(PointT c1, PointT c2, PointT p, bool shorthand) => _addToBounds(
      RectT.fromPoints(c1, c2).boundingBox(RectT.fromPoints(p, p)));

  @override
  void end() {}

  @override
  void lineTo(PointT p) => _addToBounds(RectT.fromPoints(p, p));

  @override
  void moveTo(PointT p) => _addToBounds(RectT.fromPoints(p, p));

  @override
  void quadraticBezierTo(PointT control, PointT p, bool shorthand) =>
      _addToBounds(RectT.fromPoints(control, p));
}

// Not exported.  We make hidden methods public here so they can be
// overridden in a package where Flutter's Path can be visible.
abstract class SvgCustomPathAbstract extends SvgPathMaker {
  SvgCustomPathAbstract();
  SvgCustomPathAbstract.copy(SvgCustomPathAbstract super.other)
      : super._cloned();

  @override
  SvgCustomPathAbstract _clone() => clone();
  SvgCustomPathAbstract clone();

  @override
  SvgNode? _resolve(
      _ResolveContext ctx, SvgPaint ancestor, _SvgNodeReferrers referrers) {
    return _resolveMask(ctx, ancestor, referrers);
  }

  @override
  RectT? _getUntransformedBounds(SvgTextStyle ta) => getUntransformedBounds(ta);
  RectT? getUntransformedBounds(SvgTextStyle ta);

  @override
  bool _makePath(SIBuilder<String, SIImageData> builder,
      CanonicalizedData<SIImageData> canon, SvgPaint cascaded) {
    if (_isInvisible(cascaded)) {
      return false;
    }
    if (exportedID != null) {
      builder.exportedID(null, canon.strings[exportedID!]);
    }
    addPathNode(builder, cascaded._toSIPaint());
    if (exportedID != null) {
      builder.endExportedID(null);
    }
    return true;
  }

  void addPathNode(SIBuilder<String, SIImageData> builder, SIPaint cascaded);

  @override
  void _visitPaths(void Function(Object pathKey) f) => visitPaths(f);
  void visitPaths(void Function(Object pathKey) f);

  @override
  bool _pathKeyEquals(SvgPathMaker other) => unreachable(false);
  // We the path itself as our path key

  @override
  int get _pathKeyHash => unreachable(0);
  // We use the path itself as our path key
}

///
/// An SVG `rect` element.  See
/// https://www.w3.org/TR/2008/REC-SVGTiny12-20081222/shapes.html#RectElement .
///
/// {@category SVG DOM}
///
class SvgRect extends SvgPathMaker {
  double x;
  double y;
  double width;
  double height;
  double rx;
  double ry;

  SvgRect(this.x, this.y, this.width, this.height, this.rx, this.ry);

  SvgRect._cloned(SvgRect super.other)
      : x = other.x,
        y = other.y,
        width = other.width,
        height = other.height,
        rx = other.rx,
        ry = other.ry,
        super._cloned();

  @override
  SvgRect _clone() => SvgRect._cloned(this);

  @override
  String get tagName => 'rect';

  @override
  SvgNode? _resolve(
      _ResolveContext ctx, SvgPaint ancestor, _SvgNodeReferrers referrers) {
    if (width <= 0 || height <= 0) {
      return null;
    } else {
      return _resolveMask(ctx, ancestor, referrers);
    }
  }

  @override
  RectT? _getUntransformedBounds(SvgTextStyle ta) =>
      Rectangle(x, y, width, height);

  @override
  bool _makePath(SIBuilder<String, SIImageData> builder,
      CanonicalizedData<SIImageData> canon, SvgPaint cascaded) {
    if (_isInvisible(cascaded)) {
      return false;
    }
    SIPaint curr = cascaded._toSIPaint();
    if (exportedID != null) {
      builder.exportedID(null, canon.strings[exportedID!]);
    }
    EnhancedPathBuilder? pb = builder.startPath(curr, _PathKey(this));
    if (pb != null) {
      if (rx <= 0 || ry <= 0) {
        pb.moveTo(PointT(x, y));
        pb.lineTo(PointT(x + width, y));
        pb.lineTo(PointT(x + width, y + height));
        pb.lineTo(PointT(x, y + height));
        pb.close();
      } else {
        final r = RadiusT(rx, ry);
        pb.moveTo(PointT(x + rx, y));
        pb.lineTo(PointT(x + width - rx, y));
        pb.arcToPoint(PointT(x + width, y + ry),
            radius: r, rotation: 0, largeArc: false, clockwise: true);
        pb.lineTo(PointT(x + width, y + height - ry));
        pb.arcToPoint(PointT(x + width - rx, y + height),
            radius: r, rotation: 0, largeArc: false, clockwise: true);
        pb.lineTo(PointT(x + rx, y + height));
        pb.arcToPoint(PointT(x, y + height - ry),
            radius: r, rotation: 0, largeArc: false, clockwise: true);
        pb.lineTo(PointT(x, y + ry));
        pb.arcToPoint(PointT(x + rx, y),
            radius: r, rotation: 0, largeArc: false, clockwise: true);
        pb.close();
      }
      pb.end();
    }
    if (exportedID != null) {
      builder.endExportedID(null);
    }
    return true;
  }

  @override
  void _visitPaths(void Function(Object pathKey) f) => f(_PathKey(this));

  @override
  bool _pathKeyEquals(SvgPathMaker other) {
    if (identical(this, other)) {
      return true;
    } else if (other is SvgRect) {
      return x == other.x &&
          y == other.y &&
          width == other.width &&
          height == other.height &&
          rx == other.rx &&
          ry == other.ry;
    } else {
      return false;
    }
  }

  @override
  int get _pathKeyHash => 0x04acdf77 ^ Object.hash(x, y, width, height, rx, ry);
}

///
/// An SVG ellipse or circle.  See
/// https://www.w3.org/TR/2008/REC-SVGTiny12-20081222/shapes.html#EllipseElement and
/// https://www.w3.org/TR/2008/REC-SVGTiny12-20081222/shapes.html#CircleElement .
///
/// {@category SVG DOM}
///
class SvgEllipse extends SvgPathMaker {
  /// x coordinate of the center
  double cx;

  /// y coordinate of the center
  double cy;

  /// x radius
  double rx;

  /// y radius
  double ry;

  @override
  final String tagName;

  SvgEllipse(this.tagName, this.cx, this.cy, this.rx, this.ry);

  SvgEllipse._cloned(SvgEllipse super.other)
      : cx = other.cx,
        cy = other.cy,
        rx = other.rx,
        ry = other.ry,
        tagName = other.tagName,
        super._cloned();

  @override
  SvgEllipse _clone() => SvgEllipse._cloned(this);

  @override
  SvgNode? _resolve(
      _ResolveContext ctx, SvgPaint ancestor, _SvgNodeReferrers referrers) {
    if (rx <= 0 || ry <= 0) {
      return null;
    } else {
      return _resolveMask(ctx, ancestor, referrers);
    }
  }

  @override
  RectT? _getUntransformedBounds(SvgTextStyle ta) =>
      Rectangle(cx - rx, cy - ry, 2 * rx, 2 * ry);

  @override
  bool _makePath(SIBuilder<String, SIImageData> builder,
      CanonicalizedData<SIImageData> canon, SvgPaint cascaded) {
    if (_isInvisible(cascaded)) {
      return false;
    }
    SIPaint curr = cascaded._toSIPaint();
    if (exportedID != null) {
      builder.exportedID(null, canon.strings[exportedID!]);
    }
    EnhancedPathBuilder? pb = builder.startPath(curr, _PathKey(this));
    if (pb != null) {
      pb.addOval(RectT(cx - rx, cy - ry, 2 * rx, 2 * ry));
      pb.end();
    }
    if (exportedID != null) {
      builder.endExportedID(null);
    }
    return true;
  }

  @override
  void _visitPaths(void Function(Object pathKey) f) => f(_PathKey(this));

  @override
  bool _pathKeyEquals(SvgPathMaker other) {
    if (identical(this, other)) {
      return true;
    } else if (other is SvgEllipse) {
      return cx == other.cx &&
          cy == other.cy &&
          rx == other.rx &&
          ry == other.ry;
    } else {
      return false;
    }
  }

  @override
  int get _pathKeyHash => 0x795d8ece ^ Object.hash(cx, cy, rx, ry);
}

///
/// An SVG `line`, `polyline` or `polygon`.  See
/// https://www.w3.org/TR/2008/REC-SVGTiny12-20081222/shapes.html#LineElement ,
/// https://www.w3.org/TR/2008/REC-SVGTiny12-20081222/shapes.html#PolylineElement , or
/// https://www.w3.org/TR/2008/REC-SVGTiny12-20081222/shapes.html#PolygonElement .
///
/// {@category SVG DOM}
///
class SvgPoly extends SvgPathMaker {
  /// true makes it a polygon; false a polyline
  bool close;
  List<Point<double>> points;
  @override
  final String tagName;

  SvgPoly(this.tagName, this.close, this.points);

  SvgPoly._cloned(SvgPoly super.other)
      : close = other.close,
        points = other.points,
        tagName = other.tagName,
        super._cloned();

  @override
  SvgPoly _clone() => SvgPoly._cloned(this);

  @override
  SvgNode? _resolve(
      _ResolveContext ctx, SvgPaint ancestor, _SvgNodeReferrers referrers) {
    if (points.length < 2) {
      return null;
    } else {
      return _resolveMask(ctx, ancestor, referrers);
    }
  }

  @override
  RectT? _getUntransformedBounds(SvgTextStyle ta) {
    RectT? curr;
    for (final p in points) {
      if (curr == null) {
        curr = Rectangle.fromPoints(p, p);
      } else if (!curr.containsPoint(p)) {
        curr = curr.boundingBox(Rectangle.fromPoints(p, p));
      }
    }
    return curr;
  }

  @override
  bool _makePath(SIBuilder<String, SIImageData> builder,
      CanonicalizedData<SIImageData> canon, SvgPaint cascaded) {
    if (_isInvisible(cascaded)) {
      return false;
    }
    SIPaint curr = cascaded._toSIPaint();
    if (exportedID != null) {
      builder.exportedID(null, canon.strings[exportedID!]);
    }
    EnhancedPathBuilder? pb = builder.startPath(curr, _PathKey(this));
    if (pb != null) {
      pb.moveTo(points[0]);
      for (int i = 1; i < points.length; i++) {
        pb.lineTo(points[i]);
      }
      if (close) {
        pb.close();
      }
      pb.end();
    }
    if (exportedID != null) {
      builder.endExportedID(null);
    }
    return true;
  }

  @override
  void _visitPaths(void Function(Object pathKey) f) => f(this);

  @override
  bool _pathKeyEquals(SvgPathMaker other) {
    if (identical(this, other)) {
      return true;
    } else if (other is SvgPoly) {
      return close == other.close && points.equals(other.points);
    } else {
      return false;
    }
  }

  @override
  int get _pathKeyHash =>
      0xf4e007c0 ^ Object.hash(close, Object.hashAll(points));
}

///
/// A node in an SVG asset that defines an
/// [SvgGradientColor].  See
/// https://www.w3.org/TR/2008/REC-SVGTiny12-20081222/painting.html#Gradients .
///
/// {@category SVG DOM}
///
class SvgGradientNode implements SvgNode {
  SvgGradientColor gradient;
  String? parentID;

  @override
  String? id;

  @override
  bool idIsExported = false;

  @override
  String? get exportedID => idIsExported ? id : null;

  SvgGradientNode(this.parentID, this.gradient);

  @override
  SvgGradientNode _clone() {
    final r = SvgGradientNode(parentID, gradient);
    r.id = id;
    r.idIsExported = idIsExported;
    return r;
  }

  @override
  void _cloneAttributes() {
    // We don't need to clone gradient.  It is mutable, but we don't mutate
    // it when generating a ScalableImage.
  }

  @override
  void _visitPaths(void Function(Object pathKey) f) {}

  @override
  @mustCallSuper
  void _addIDs(Map<String, SvgNode> idLookup) {
    final i = id;
    if (i != null) {
      idLookup[i] = this;
    }
  }

  @override
  void _applyStylesheet(Stylesheet stylesheet, void Function(String) warn) {}

  @override
  SvgNode? _resolve(
      _ResolveContext ctx, SvgPaint ancestor, _SvgNodeReferrers referrers) {
    final pid = parentID;
    if (pid != null) {
      var parent = ctx.idLookup[pid];
      var pLoop = parent;
      while (pLoop is SvgGradientNode) {
        if (identical(pLoop, this)) {
          ctx.warn('    Gradient references itself:  $pid');
          pLoop = null;
          parent = null;
        } else {
          final ppid = pLoop.parentID;
          if (ppid == null) {
            pLoop = null;
          } else {
            pLoop = ctx.idLookup[ppid];
          }
        }
      }
      if (parent is SvgGradientNode) {
        gradient.parent = parent.gradient;
      } else {
        ctx.warn('    Gradient references non-existent gradient $pid');
      }
    }
    // Our underlying gradient gets incorporated into SIPaint, so no reason to
    // keep the node around
    return null;
  }

  @override
  _SvgBoundary? _getUserSpaceBoundary(SvgTextStyle ta) => unreachable(null);

  @override
  bool _build(
          SIBuilder<String, SIImageData> builder,
          CanonicalizedData<SIImageData> canon,
          Map<String, SvgNode> idLookup,
          SvgPaint ancestor,
          SvgTextStyle ta,
          {bool blendHandledByParent = false}) =>
      unreachable(false);

  @override
  bool _canUseLuma(Map<String, SvgNode> idLookup, SvgPaint ancestor) =>
      unreachable(false);

  ///
  /// Return null; a gradient is not rendered, so it cannot blend.
  ///
  @override
  SIBlendMode? get blendMode => null;
}

///
/// An SVG `image`.  See
/// https://www.w3.org/TR/2011/REC-SVG11-20110816/struct.html#ImageElement .
///
/// {@category SVG DOM}
///
class SvgImage extends SvgInheritableAttributesNode {
  Uint8List imageData = _emptyData;
  double x = 0;
  double y = 0;
  double width = 0;
  double height = 0;

  SvgImage() : super._p();

  SvgImage._cloned(SvgImage super.other)
      : imageData = other.imageData,
        x = other.x,
        y = other.y,
        width = other.width,
        height = other.height,
        super._cloned();

  @override
  SvgImage _clone() => SvgImage._cloned(this);

  @override
  String get tagName => 'image';

  static final Uint8List _emptyData = Uint8List(0);

  @override
  SvgNode? _resolve(
      _ResolveContext ctx, SvgPaint ancestor, _SvgNodeReferrers referrers) {
    if (width <= 0 || height <= 0) {
      return null;
    }
    return _resolveMask(ctx, ancestor, referrers);
  }

  @override
  RectT? _getUntransformedBounds(SvgTextStyle ta) =>
      Rectangle(x, y, width, height);

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
    final sid = SIImageData(
        x: x, y: y, width: width, height: height, encoded: imageData);
    int imageNumber = canon.images[sid];
    final cascaded = _paint == null
        ? ancestor
        : paint._cascade(ancestor, idLookup, builder.warn);
    if (cascaded.hidden == true) {
      return false;
    }
    if (exportedID != null) {
      builder.exportedID(null, canon.strings[exportedID!]);
    }
    if (transform != null ||
        groupAlpha != null ||
        blend != SIBlendMode.normal) {
      builder.group(null, transform, groupAlpha, blend);
      builder.image(null, imageNumber);
      builder.endGroup(null);
    } else {
      builder.image(null, imageNumber);
    }
    if (exportedID != null) {
      builder.endExportedID(null);
    }
    return true;
  }

  @override
  bool _canUseLuma(Map<String, SvgNode> idLookup, SvgPaint ancestor) {
    return true;
  }
}

///
/// Text styling information for an SVG asset.  See
/// https://www.w3.org/TR/2008/REC-SVGTiny12-20081222/text.html#FontPropertiesUsedBySVG .
///
/// {@category SVG DOM}
///
class SvgTextStyle {
  List<String>? fontFamily; // Null is not the same as [] due to cascading
  SIFontStyle? fontStyle;
  SITextAnchor? textAnchor;
  SIDominantBaseline? dominantBaseline;
  SITextDecoration? textDecoration;
  SvgFontWeight fontWeight = SvgFontWeight.inherit;
  SvgFontSize fontSize = SvgFontSize.inherit;

  SvgTextStyle.empty();

  SvgTextStyle._p(
      {required this.fontFamily,
      required this.fontStyle,
      required this.textAnchor,
      required this.dominantBaseline,
      required this.fontWeight,
      required this.fontSize,
      required this.textDecoration});

  SvgTextStyle._initial()
      : fontFamily = null,
        textAnchor = SITextAnchor.start,
        dominantBaseline = SIDominantBaseline.auto,
        fontStyle = SIFontStyle.normal,
        fontWeight = SvgFontWeight.w400,
        fontSize = SvgFontSize.medium,
        textDecoration = SITextDecoration.none;

  SvgTextStyle? _clone() => SvgTextStyle._p(
      fontFamily: fontFamily,
      fontStyle: fontStyle,
      textAnchor: textAnchor,
      dominantBaseline: dominantBaseline,
      fontWeight: fontWeight,
      fontSize: fontSize,
      textDecoration: textDecoration);

  SvgTextStyle _cascade(SvgTextStyle ancestor) {
    return SvgTextStyle._p(
        fontSize: fontSize._orInherit(ancestor.fontSize),
        fontFamily: fontFamily ?? ancestor.fontFamily,
        textAnchor: textAnchor ?? ancestor.textAnchor,
        dominantBaseline: dominantBaseline ?? ancestor.dominantBaseline,
        textDecoration: textDecoration ?? ancestor.textDecoration,
        fontWeight: fontWeight._orInherit(ancestor.fontWeight),
        fontStyle: fontStyle ?? ancestor.fontStyle);
  }

  void _takeFrom(Style style) {
    fontSize = fontSize._orInherit(style.textStyle.fontSize);
    fontFamily = fontFamily ?? style.textStyle.fontFamily;
    textAnchor = textAnchor ?? style.textStyle.textAnchor;
    dominantBaseline = dominantBaseline ?? style.textStyle.dominantBaseline;
    textDecoration = textDecoration ?? style.textStyle.textDecoration;
    fontWeight = fontWeight._orInherit(style.textStyle.fontWeight);
    fontStyle = fontStyle ?? style.textStyle.fontStyle;
  }

  SITextAttributes _toSITextAttributes() => SITextAttributes(
      fontFamily: fontFamily,
      textAnchor: textAnchor!,
      dominantBaseline: dominantBaseline!,
      textDecoration: textDecoration!,
      fontStyle: fontStyle!,
      fontWeight: fontWeight._toSI(),
      fontSize: fontSize._toSI());

  @override
  int get hashCode =>
      0x0ba469d9 ^
      Object.hash(Object.hashAll(fontFamily ?? const []), fontStyle, textAnchor,
          dominantBaseline, textDecoration, fontWeight, fontSize);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    } else if (other is SvgTextStyle) {
      return (const ListEquality<String>())
              .equals(fontFamily, other.fontFamily) &&
          fontStyle == other.fontStyle &&
          textAnchor == other.textAnchor &&
          dominantBaseline == other.dominantBaseline &&
          textDecoration == other.textDecoration &&
          fontWeight == other.fontWeight &&
          fontSize == other.fontSize;
    } else {
      return false;
    }
  }
}

///
/// Font size for SVG text.  See
/// https://www.w3.org/TR/2008/REC-SVGTiny12-20081222/text.html#FontPropertiesUsedBySVG .
///
/// {@category SVG DOM}
///
abstract class SvgFontSize {
  const SvgFontSize._p();

  ///
  /// Create an absolute font size.
  ///
  factory SvgFontSize.absolute(double size) => _SvgFontSizeAbsolute(size);

  static const SvgFontSize inherit = _SvgFontSizeInherit();

  static const SvgFontSize larger = _SvgFontSizeRelative(1.2);

  static const SvgFontSize smaller = _SvgFontSizeRelative(1 / 1.2);

  static const double _med = 12;
  static const SvgFontSize medium = _SvgFontSizeAbsolute(_med);

  static const SvgFontSize small = _SvgFontSizeAbsolute(_med / 1.2);
  static const SvgFontSize x_small = _SvgFontSizeAbsolute(_med / (1.2 * 1.2));
  static const SvgFontSize xx_small =
      _SvgFontSizeAbsolute(_med / (1.2 * 1.2 * 1.2));

  static const SvgFontSize large = _SvgFontSizeAbsolute(_med * 1.2);
  static const SvgFontSize x_large = _SvgFontSizeAbsolute(_med * 1.2 * 1.2);
  static const SvgFontSize xx_large =
      _SvgFontSizeAbsolute(_med * 1.2 * 1.2 * 1.2);

  SvgFontSize _orInherit(SvgFontSize ancestor);

  double _toSI();
}

class _SvgFontSizeAbsolute extends SvgFontSize {
  final double size;

  const _SvgFontSizeAbsolute(this.size) : super._p();

  @override
  SvgFontSize _orInherit(SvgFontSize ancestor) => this;

  @override
  double _toSI() => size;
}

class _SvgFontSizeRelative extends SvgFontSize {
  final double scale;

  const _SvgFontSizeRelative(this.scale) : super._p();

  @override
  SvgFontSize _orInherit(SvgFontSize ancestor) =>
      _SvgFontSizeRelativeDeferred(scale, ancestor);

  @override
  double _toSI() => unreachable(12);
}

class _SvgFontSizeRelativeDeferred extends SvgFontSize {
  final double scale;
  SvgFontSize _ancestor;

  _SvgFontSizeRelativeDeferred(this.scale, this._ancestor) : super._p();

  @override
  SvgFontSize _orInherit(SvgFontSize ancestor) {
    _ancestor = _ancestor._orInherit(ancestor);
    return this;
  }

  @override
  double _toSI() {
    return scale * _ancestor._toSI();
  }
}

class _SvgFontSizeInherit extends SvgFontSize {
  const _SvgFontSizeInherit() : super._p();

  @override
  SvgFontSize _orInherit(SvgFontSize ancestor) => ancestor;

  @override
  double _toSI() => unreachable(12);
}

///
/// Color as SVG knows it, plus alpha in the high-order byte (in case we
/// encounter an SVG file with an (invalid) eight-character hex value).
///
/// {@category SVG DOM}
///
abstract class SvgColor {
  const SvgColor();

  ///
  /// Create a normal, explicit color from an 0xaarrggbb value.
  ///
  factory SvgColor.value(int value) => SvgValueColor(value);

  ///
  /// The "inherit" color, which means "inherit from parent"
  ///
  static const SvgColor inherit = _SvgInheritColor._p();

  ///
  /// The "none" color, which means "do not paint"
  ///
  static const SvgColor none = _SvgNoneColor._p();

  ///
  /// The "currentColor" color, which means "paint with the color given
  /// to the ScalableImage's parent".
  ///
  static const SvgColor currentColor = _SvgCurrentColor._p();

  static const SvgColor white = SvgValueColor(0xffffffff);
  static const SvgColor transparent = SvgValueColor(0x00ffffff);

  SvgColor _orInherit(SvgColor ancestor, Map<String, SvgNode>? idLookup,
          void Function(String) warn) =>
      this;

  SIColor _toSIColor(
      int alpha, SvgColor cascadedCurrentColor, RectT Function() userSpace);

  ///
  /// Create a reference to a gradient
  ///
  static SvgColor reference(String id) => _SvgColorReference(id);
}

class SvgValueColor extends SvgColor {
  final int _value;
  const SvgValueColor(this._value);

  @override
  SIColor _toSIColor(
      int alpha, SvgColor cascadedCurrentColor, RectT Function() userSpace) {
    if (alpha == 0xff) {
      return SIValueColor(_value);
    } else {
      return SIValueColor((_value & 0xffffff) | (alpha << 24));
    }
  }

  @override
  String toString() =>
      'SvgValueColor(#${_value.toRadixString(16).padLeft(6, "0")})';
}

class _SvgInheritColor extends SvgColor {
  const _SvgInheritColor._p();

  @override
  SvgColor _orInherit(SvgColor ancestor, Map<String, SvgNode>? idLookup,
          void Function(String) warn) =>
      ancestor;

  @override
  SIColor _toSIColor(int? alpha, SvgColor cascadedCurrentColor,
          RectT Function() userSpace) =>
      throw StateError('Internal error: color inheritance');
}

class _SvgNoneColor extends SvgColor {
  const _SvgNoneColor._p();

  @override
  SIColor _toSIColor(int? alpha, SvgColor cascadedCurrentColor,
          RectT Function() userSpace) =>
      SIColor.none;
}

class _SvgCurrentColor extends SvgColor {
  const _SvgCurrentColor._p();

  @override
  SIColor _toSIColor(
      int alpha, SvgColor cascadedCurrentColor, RectT Function() userSpace) {
    if (cascadedCurrentColor is _SvgCurrentColor) {
      return SIColor.currentColor;
    } else {
      return cascadedCurrentColor._toSIColor(
          alpha, const SvgValueColor(0), userSpace);
    }
  }
}

class _SvgColorReference extends SvgColor {
  final String id;

  _SvgColorReference(this.id);

  @override
  SvgColor _orInherit(SvgColor ancestor, Map<String, SvgNode>? idLookup,
      void Function(String) warn) {
    if (idLookup == null) {
      return this; // We'll resolve it later
    } else {
      final n = idLookup[id];
      if (n is! SvgGradientNode) {
        warn('Gradient $id not found');
        return SvgColor.transparent;
      }
      return n.gradient;
    }
  }

  @override
  SIColor _toSIColor(int alpha, SvgColor cascadedCurrentColor,
          RectT Function() userSpace) =>
      throw StateError('Internal error: color inheritance');
}

///
/// And SVG gradient stop.  See
/// https://www.w3.org/TR/2008/REC-SVGTiny12-20081222/painting.html#Gradients .
///
/// {@category SVG DOM}
///
class SvgGradientStop {
  final double offset;
  final SvgColor color; // But not a gradient!
  final int alpha;

  SvgGradientStop(this.offset, this.color, this.alpha) {
    if (color is SvgGradientColor) {
      throw StateError('Internal error:  Gradient stop cannot be gradient');
    }
  }
}

///
/// A gradient color.  See
/// https://www.w3.org/TR/2008/REC-SVGTiny12-20081222/painting.html#Gradients .
///
/// {@category SVG DOM}
///
sealed class SvgGradientColor extends SvgColor {
  final bool? objectBoundingBox;
  List<SvgGradientStop>? stops;
  Affine? transform;
  SvgGradientColor? parent;
  SIGradientSpreadMethod? spreadMethod;

  SvgGradientColor._p(
      this.objectBoundingBox, this.transform, this.spreadMethod);

  // Resolving getters:

  bool get _objectBoundingBoxR =>
      objectBoundingBox ?? parent?._objectBoundingBoxR ?? true;

  List<SvgGradientStop> get _stopsR => stops ?? parent?._stopsR ?? [];

  Affine? get _transformR => transform ?? parent?._transformR;

  SIGradientSpreadMethod get _spreadMethodR =>
      spreadMethod ?? parent?._spreadMethodR ?? SIGradientSpreadMethod.pad;

  void addStop(SvgGradientStop s) {
    final sl = stops ??= List<SvgGradientStop>.empty(growable: true);
    sl.add(s);
  }
}

///
/// A coordinate in a gradient color.  A coordinate can be a pixel value
/// or a percentage.
///
/// {@category SVG DOM}
///
class SvgCoordinate {
  final double _value;

  ///
  /// Is this a percentage coordinate?
  ///
  final bool isPercent;

  ///
  /// Create a value coordinate.
  ///
  SvgCoordinate.value(this._value) : isPercent = false;

  ///
  /// Create a percentage coordinage, where an argument of 50 will represent
  /// 50%, etc.
  ///
  SvgCoordinate.percent(this._value) : isPercent = true;

  ///
  /// The value of this coordinate, or for a percentage, a number representing
  /// the percentage (0.5 for 50%, etc.)
  ///
  double get value => isPercent ? (_value / 100) : _value;
}

///
/// An SVG linear gradient.  See
/// https://www.w3.org/TR/2008/REC-SVGTiny12-20081222/painting.html#Gradients
///
/// {@category SVG DOM}
///
class SvgLinearGradientColor extends SvgGradientColor {
  SvgCoordinate? x1;
  SvgCoordinate? y1;
  SvgCoordinate? x2;
  SvgCoordinate? y2;

  SvgLinearGradientColor? get _linearParent {
    final p = parent;
    if (p is SvgLinearGradientColor) {
      return p;
    } else {
      return null;
    }
  }

  SvgLinearGradientColor(
      {required this.x1,
      required this.y1,
      required this.x2, // default 1
      required this.y2, // default 0
      required bool? objectBoundingBox, // default true
      required Affine? transform,
      required SIGradientSpreadMethod? spreadMethod})
      : super._p(objectBoundingBox, transform, spreadMethod);

  // Resolving getters:

  SvgCoordinate get _x1R =>
      x1 ?? _linearParent?._x1R ?? SvgCoordinate.value(0.0);
  SvgCoordinate get _y1R =>
      y1 ?? _linearParent?._y1R ?? SvgCoordinate.value(0.0);
  SvgCoordinate get _x2R =>
      x2 ?? _linearParent?._x2R ?? SvgCoordinate.value(1.0);
  SvgCoordinate get _y2R =>
      y2 ?? _linearParent?._y2R ?? SvgCoordinate.value(0.0);

  @override
  SIColor _toSIColor(
      int alpha, SvgColor cascadedCurrentColor, RectT Function() userSpace) {
    final stops = _stopsR;
    final offsets = List<double>.generate(stops.length, (i) => stops[i].offset,
        growable: false);
    final colors = List<SIColor>.generate(
        stops.length,
        (i) => stops[i]
            .color
            ._toSIColor(stops[i].alpha, cascadedCurrentColor, userSpace),
        growable: false);
    final obb = _objectBoundingBoxR;
    late final RectT us = userSpace();
    double toDoubleX(SvgCoordinate c) {
      if (obb || !c.isPercent) {
        return c.value;
      } else {
        return us.left + us.width * c.value;
      }
    }

    double toDoubleY(SvgCoordinate c) {
      if (obb || !c.isPercent) {
        return c.value;
      } else {
        return us.top + us.height * c.value;
      }
    }

    return SILinearGradientColor(
        x1: toDoubleX(_x1R),
        y1: toDoubleY(_y1R),
        x2: toDoubleX(_x2R),
        y2: toDoubleY(_y2R),
        colors: colors,
        stops: offsets,
        objectBoundingBox: obb,
        spreadMethod: _spreadMethodR,
        transform: _transformR);
  }
}

///
/// An SVG radial gradient.  See
/// https://www.w3.org/TR/2008/REC-SVGTiny12-20081222/painting.html#Gradients .
///
/// {@category SVG DOM}
///
class SvgRadialGradientColor extends SvgGradientColor {
  final SvgCoordinate? cx; // default 0.5
  final SvgCoordinate? cy; // default 0.5
  final SvgCoordinate? fx;
  final SvgCoordinate? fy;
  final SvgCoordinate? r; // default 0.5

  SvgRadialGradientColor? get _radialParent {
    final p = parent;
    if (p is SvgRadialGradientColor) {
      return p;
    } else {
      return null;
    }
  }

  SvgRadialGradientColor(
      {required this.cx,
      required this.cy,
      required this.fx,
      required this.fy,
      required this.r,
      required bool? objectBoundingBox,
      required Affine? transform,
      required SIGradientSpreadMethod? spreadMethod})
      : super._p(objectBoundingBox, transform, spreadMethod);

  // Resolving getters:

  SvgCoordinate get _cxR =>
      cx ?? _radialParent?._cxR ?? SvgCoordinate.value(0.5);
  SvgCoordinate get _cyR =>
      cy ?? _radialParent?._cyR ?? SvgCoordinate.value(0.5);
  SvgCoordinate? get _fxR => fx ?? _radialParent?._fxR;
  SvgCoordinate? get _fyR => fy ?? _radialParent?._fyR;
  SvgCoordinate get _rR => r ?? _radialParent?._rR ?? SvgCoordinate.value(0.5);

  @override
  SIColor _toSIColor(
      int alpha, SvgColor cascadedCurrentColor, RectT Function() userSpace) {
    final stops = _stopsR;
    final offsets = List<double>.generate(stops.length, (i) => stops[i].offset,
        growable: false);
    final colors = List<SIColor>.generate(
        stops.length,
        (i) => stops[i]
            .color
            ._toSIColor(stops[i].alpha, cascadedCurrentColor, userSpace),
        growable: false);
    final obb = _objectBoundingBoxR;
    late final RectT us = userSpace();
    double toDoubleX(SvgCoordinate c) {
      if (obb || !c.isPercent) {
        return c.value;
      } else {
        return us.left + us.width * c.value;
      }
    }

    double toDoubleY(SvgCoordinate c) {
      if (obb || !c.isPercent) {
        return c.value;
      } else {
        return us.top + us.height * c.value;
      }
    }

    final rr = _rR;
    final double r;
    if (!obb && rr.isPercent) {
      final uw = us.width;
      final uh = us.height;
      r = rr.value * sqrt(uw * uw + uh + uh);
    } else {
      r = rr.value;
    }
    return SIRadialGradientColor(
        cx: toDoubleX(_cxR),
        cy: toDoubleY(_cyR),
        fx: toDoubleX(_fxR ?? _cxR),
        fy: toDoubleY(_fyR ?? _cyR),
        r: r,
        colors: colors,
        stops: offsets,
        objectBoundingBox: obb,
        spreadMethod: _spreadMethodR,
        transform: _transformR);
  }
}

///
/// An SVG sweep gradient.  See
/// https://www.w3.org/TR/2008/REC-SVGTiny12-20081222/painting.html#Gradients .
///
/// {@category SVG DOM}
///
class SvgSweepGradientColor extends SvgGradientColor {
  final double? cx; // default 0.5
  final double? cy; // default 0.5
  final double? startAngle;
  final double? endAngle;

  SvgSweepGradientColor? get _sweepParent {
    final p = parent;
    if (p is SvgSweepGradientColor) {
      return p;
    } else {
      return null;
    }
  }

  SvgSweepGradientColor(
      {required this.cx,
      required this.cy,
      required this.startAngle,
      required this.endAngle,
      required bool? objectBoundingBox,
      required Affine? transform,
      required SIGradientSpreadMethod? spreadMethod})
      : super._p(objectBoundingBox, transform, spreadMethod);

  // Resolving getters:

  double get _cxR => cx ?? _sweepParent?._cxR ?? 0.5;
  double get _cyR => cy ?? _sweepParent?._cyR ?? 0.5;
  double get _startAngleR => startAngle ?? _sweepParent?._startAngleR ?? 0.0;
  double get _endAngleR => endAngle ?? _sweepParent?._endAngleR ?? 2 * pi;

  @override
  SIColor _toSIColor(
      int alpha, SvgColor cascadedCurrentColor, RectT Function() userSpace) {
    final stops = _stopsR;
    final offsets = List<double>.generate(stops.length, (i) => stops[i].offset,
        growable: false);
    final colors = List<SIColor>.generate(
        stops.length,
        (i) => stops[i]
            .color
            ._toSIColor(stops[i].alpha, cascadedCurrentColor, userSpace),
        growable: false);
    return SISweepGradientColor(
        cx: _cxR,
        cy: _cyR,
        startAngle: _startAngleR,
        endAngle: _endAngleR,
        colors: colors,
        stops: offsets,
        objectBoundingBox: _objectBoundingBoxR,
        spreadMethod: _spreadMethodR,
        transform: _transformR);
  }
}

///
/// The value of an SVG font weight attribute.
/// See https://www.w3.org/TR/2008/REC-SVGTiny12-20081222/text.html#FontWeightProperty .
///
/// {@category SVG DOM}
///
abstract class SvgFontWeight {
  const SvgFontWeight._p();

  static const SvgFontWeight w100 = _SvgFontWeightAbsolute(SIFontWeight.w100);
  static const SvgFontWeight w200 = _SvgFontWeightAbsolute(SIFontWeight.w200);
  static const SvgFontWeight w300 = _SvgFontWeightAbsolute(SIFontWeight.w300);
  static const SvgFontWeight w400 = _SvgFontWeightAbsolute(SIFontWeight.w400);
  static const SvgFontWeight w500 = _SvgFontWeightAbsolute(SIFontWeight.w500);
  static const SvgFontWeight w600 = _SvgFontWeightAbsolute(SIFontWeight.w600);
  static const SvgFontWeight w700 = _SvgFontWeightAbsolute(SIFontWeight.w700);
  static const SvgFontWeight w800 = _SvgFontWeightAbsolute(SIFontWeight.w800);
  static const SvgFontWeight w900 = _SvgFontWeightAbsolute(SIFontWeight.w900);
  static const SvgFontWeight bolder = _SvgFontWeightBolder();
  static const SvgFontWeight lighter = _SvgFontWeightLighter();
  static const SvgFontWeight inherit = _SvgFontWeightInherit();

  SvgFontWeight _orInherit(SvgFontWeight ancestor);
  SIFontWeight _toSI();
}

class _SvgFontWeightAbsolute extends SvgFontWeight {
  final SIFontWeight weight;
  const _SvgFontWeightAbsolute(this.weight) : super._p();

  @override
  SvgFontWeight _orInherit(SvgFontWeight ancestor) => this;

  @override
  SIFontWeight _toSI() => weight;
}

class _SvgFontWeightBolder extends SvgFontWeight {
  const _SvgFontWeightBolder() : super._p();

  @override
  SvgFontWeight _orInherit(SvgFontWeight ancestor) =>
      _SvgFontWeightDelta(1, ancestor);

  @override
  SIFontWeight _toSI() {
    assert(false); // coverage:ignore-line
    return SIFontWeight.w400; // coverage:ignore-line
  }
}

class _SvgFontWeightLighter extends SvgFontWeight {
  const _SvgFontWeightLighter() : super._p();

  @override
  SvgFontWeight _orInherit(SvgFontWeight ancestor) =>
      _SvgFontWeightDelta(-1, ancestor);

  @override
  SIFontWeight _toSI() {
    assert(false); // coverage:ignore-line
    return SIFontWeight.w400; // coverage:ignore-line
  }
}

class _SvgFontWeightDelta extends SvgFontWeight {
  final int delta;
  SvgFontWeight _ancestor;

  _SvgFontWeightDelta(this.delta, this._ancestor) : super._p();

  @override
  SvgFontWeight _orInherit(SvgFontWeight ancestor) {
    _ancestor = _ancestor._orInherit(ancestor);
    return this;
  }

  @override
  SIFontWeight _toSI() {
    final i = _ancestor._toSI().index + delta;
    return SIFontWeight.values[max(0, min(i, SIFontWeight.values.length - 1))];
  }
}

class _SvgFontWeightInherit extends SvgFontWeight {
  const _SvgFontWeightInherit() : super._p();

  @override
  SvgFontWeight _orInherit(SvgFontWeight ancestor) => ancestor;

  @override
  SIFontWeight _toSI() {
    assert(false); // coverage:ignore-line
    return SIFontWeight.w400; // coverage:ignore-line
  }
}

class AvdClipPath extends SvgNode {
  final String pathData;

  AvdClipPath(this.pathData) : super._p();

  @override
  SIBlendMode get blendMode => SIBlendMode.normal; // coverage:ignore-line

  @override
  void _applyStylesheet(Stylesheet stylesheet,
      void Function(String) warn) {} // coverage:ignore-line

  @override
  void _cloneAttributes() {}

  @override
  bool _build(
      SIBuilder<String, SIImageData> builder,
      CanonicalizedData<SIImageData> canon,
      Map<String, SvgNode> idLookup,
      SvgPaint ancestor,
      SvgTextStyle ta,
      {bool blendHandledByParent = false}) {
    builder.clipPath(null, pathData);
    return true;
  }

  @override
  bool _canUseLuma(Map<String, SvgNode> idLookup, SvgPaint ancestor) =>
      false; // coverage:ignore-line

  @override
  SvgNode? _resolve(_ResolveContext ctx, SvgPaint ancestor,
          _SvgNodeReferrers referrers) =>
      this;

  @override
  SvgNode _clone() => unreachable(this);

  @override
  _SvgBoundary? _getUserSpaceBoundary(SvgTextStyle ta) => null;
}

///
/// A boundary for calculating the user space.  A bit like PruningBounds, but
/// not using dependent on Flutter.
///
@immutable
class _SvgBoundary {
  final Point<double> a;
  final Point<double> b;
  final Point<double> c;
  final Point<double> d;

  _SvgBoundary(RectT rect)
      : a = Point(rect.left, rect.top),
        b = Point(rect.left + rect.width, rect.top),
        c = Point(rect.left + rect.width, rect.top + rect.height),
        d = Point(rect.left, rect.top + rect.height);

  const _SvgBoundary._p(this.a, this.b, this.c, this.d);

  RectT getBounds() {
    double left = min(min(a.x, b.x), min(c.x, d.x));
    double top = min(min(a.y, b.y), min(c.y, d.y));
    double right = max(max(a.x, b.x), max(c.x, d.x));
    double bottom = max(max(a.y, b.y), max(c.y, d.y));
    return Rectangle(left, top, right - left, bottom - top);
  }

  @override
  String toString() => '_SvgBoundary($a $b $c $d)'; // coverage:ignore-line

  static Point<double> _tp(Point<double> p, Affine x) => x.transformed(p);

  _SvgBoundary transformed(Affine x) =>
      _SvgBoundary._p(_tp(a, x), _tp(b, x), _tp(c, x), _tp(d, x));
}

class SvgDOMNotExported {
  static void build(SvgDOM svg, SIBuilder<String, SIImageData> builder) =>
      svg._build(builder);

  static void setIDLookup(SvgDOM svg, Map<String, SvgNode> idLookup) {
    assert(svg._idLookup == null);
    svg._idLookup = Map.unmodifiable(idLookup);
  }

  static SvgDOM clone(SvgDOM svg) => svg._clone();

  static void visitPaths(SvgDOM dom, void Function(Object pathKey) f) =>
      dom._visitPaths(f);

  static void cloneAttributes(SvgDOM svg) => svg._cloneAttributes();
}

@immutable
class _ResolveContext {
  final Map<String, SvgNode> idLookup;
  final void Function(String) warn;
  final Map<SvgNode, SvgNode> generatedFor = Map.identity();

  _ResolveContext(this.idLookup, this.warn);
}

/// Private APIs that are unreachable, or for debugging (like toString()).
/// Since coverage:ignore-line doesn't
/// work, we do this to avoid wasting time with false positives on the coverage
/// report.  Obviously, this gets optimized away as part of Dart's tree shaking.
final svgGraphUnreachablePrivate = [
  () => _CollectCanonBuilder(CanonicalizedData<SIImageData>()).legacyText(
      null,
      0,
      0,
      0,
      SvgTextStyle._initial()._toSITextAttributes(),
      null,
      SvgPaint._root(SvgPaint._dummy)._toSIPaint()),
  () => _SvgBoundary(const RectT(0, 0, 0, 0)).toString(),
  () => const _SvgFontWeightInherit()._toSI(),
  () => const _SvgFontWeightLighter()._toSI(),
  () => const _SvgFontWeightBolder()._toSI(),
  () => _SvgColorReference('')._toSIColor(0, SvgColor.white, SvgPaint._dummy),
  () => SvgColor.inherit._toSIColor(0, SvgColor.white, SvgPaint._dummy),
  () => SvgColor.white.toString(),
  () => _SvgFontSizeRelativeDeferred(1, SvgFontSize.absolute(0))._toSI(),
  () => const _SvgFontSizeRelative(1)._toSI(),
  () => SvgUse(null)._getUntransformedBounds(SvgTextStyle._initial()),
  () => _testCallBuild(SvgUse(null)),
  () => SvgUse(null)._getUntransformedBounds(SvgTextStyle._initial()),
  () => SvgUse(null)._canUseLuma({}, SvgPaint.empty()),
  () => _testCallBuild(SvgDefs('')),
  () => SvgDefs('')._getUntransformedBounds(SvgTextStyle._initial()),
  () => _SvgMasked(SvgDefs(''), SvgMask())._applyStylesheet({}, (_) {}),
  () => _SvgMasked(SvgDefs(''), SvgMask())._resolve(
      _ResolveContext(const {}, (_) {}),
      SvgPaint.empty(),
      _SvgNodeReferrers(null)),
  () => (SvgPaint.empty()..hidden = true)._toSIPaint(),
  () => const _SvgFontSizeRelative(1)._toSI(),
  () => const _SvgFontSizeInherit()._toSI(),
  () => SvgGradientNode('', _testGradientColor)
      ._getUserSpaceBoundary(SvgTextStyle._initial()),
  () => _testCallBuild(SvgGradientNode('', _testGradientColor)),
  () => SvgGradientNode('', _testGradientColor)
      ._canUseLuma(const {}, SvgPaint.empty()),
  () => SvgGradientNode('', _testGradientColor).blendMode,
  () => _SvgPathBoundsBuilder().addOval(const RectT(0, 0, 0, 0)),
];
void _testCallBuild(SvgNode n) => n._build(
    _CollectCanonBuilder(CanonicalizedData<SIImageData>()),
    CanonicalizedData<SIImageData>(),
    const {},
    SvgPaint.empty(),
    SvgTextStyle._initial());
final _testGradientColor = SvgRadialGradientColor(
    cx: null,
    cy: null,
    fx: null,
    fy: null,
    r: null,
    objectBoundingBox: null,
    transform: null,
    spreadMethod: null);
