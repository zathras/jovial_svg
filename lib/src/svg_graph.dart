// ignore_for_file: constant_identifier_names

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

library jovial_svg.svg_graph;

import 'dart:math';
import 'dart:typed_data';

import 'package:quiver/core.dart' as quiver;
import 'package:quiver/collection.dart' as quiver;

import 'affine.dart';
import 'common_noui.dart';
import 'path_noui.dart';

///
/// The graph structure we get when parsing an SVG XML file.  This graph
/// is used to build a `ScalableImage` via an [SIBuilder].
///
/// If, someday, there is a desire to support some kind of DOM that lets
/// flutter code modify the parse graph, an API could be wrapped around this
/// structure.  It wouldn't be unreasonable to add a `paint(Canvas)` method
/// here, on the parse graph, to support the programmatic manipulation of the
/// parse tree.
///
class SvgParseGraph {
  final idLookup = <String, SvgNode>{};
  final SvgGroup root;
  final double? width;
  final double? height;

  SvgParseGraph(this.root, this.width, this.height);

  void build(SIBuilder<String, SIImageData> builder) {
    final rootPaint = SvgPaint.initial();
    final rootTA = SvgTextAttributes.initial();
    SvgNode? newRoot =
        root.resolve(idLookup, rootPaint, builder.warn, _Referrers(null));
    builder.vector(
        width: width, height: height, tintColor: null, tintMode: null);
    final theCanon = CanonicalizedData<SIImageData>();
    newRoot?.collectCanon(theCanon);
    builder.init(
        null,
        theCanon.toList(theCanon.images),
        theCanon.toList(theCanon.strings),
        theCanon.toList(theCanon.floatLists));
    newRoot?.build(builder, theCanon, idLookup, rootPaint, rootTA);
    builder.endVector();
  }
}

abstract class SvgNode {
  SvgNode? resolve(Map<String, SvgNode> idLookup, SvgPaint ancestor, bool warn,
      _Referrers referrers);

  bool build(SIBuilder<String, SIImageData> builder, CanonicalizedData canon,
      Map<String, SvgNode> idLookup, SvgPaint ancestor, SvgTextAttributes ta);

  void collectCanon(CanonicalizedData<SIImageData> canon);

  ///
  /// If this node is in a mask, is it possible it might use the luma
  /// channel?  cf. SIMaskHelper.startLumaMask().
  ///
  bool canUseLuma(Map<String, SvgNode> idLookup, SvgPaint ancestor);
}

///
/// Things that refer to a node, like a group.
/// This is used to catch reference loops.
///
class _Referrers {
  final SvgNode? referrer;
  final _Referrers? parent;

  _Referrers(this.referrer, [this.parent]);

  bool contains(SvgNode n) {
    _Referrers? s = this;
    while (s != null) {
      if (identical(s.referrer, n)) {
        return true;
      }
      s = s.parent;
    }
    return false;
  }
}

abstract class SvgInheritableAttributes implements SvgNode {
  MutableAffine? transform;
  SvgPaint paint = SvgPaint.empty();
  SvgTextAttributes textAttributes = SvgTextAttributes.empty();
  int? groupAlpha; // Doesn't inherit; instead, a group is created

  bool _isInvisible(SvgPaint paint) =>
      (paint.strokeAlpha == 0 || paint.strokeColor == SvgColor.none) &&
      (paint.fillAlpha == 0 || paint.fillColor == SvgColor.none);

  SvgPaint cascadePaint(SvgPaint ancestor, Map<String, SvgNode> ids) {
    return SvgPaint(
        currentColor: paint.currentColor.orInherit(ancestor.currentColor, ids),
        fillColor: paint.fillColor.orInherit(ancestor.fillColor, ids),
        fillAlpha: paint.fillAlpha ?? ancestor.fillAlpha,
        strokeColor: paint.strokeColor.orInherit(ancestor.strokeColor, ids),
        strokeAlpha: paint.strokeAlpha ?? ancestor.strokeAlpha,
        strokeWidth: paint.strokeWidth ?? ancestor.strokeWidth,
        strokeMiterLimit: paint.strokeMiterLimit ?? ancestor.strokeMiterLimit,
        strokeJoin: paint.strokeJoin ?? ancestor.strokeJoin,
        strokeCap: paint.strokeCap ?? ancestor.strokeCap,
        fillType: paint.fillType ?? ancestor.fillType,
        strokeDashArray: paint.strokeDashArray ?? ancestor.strokeDashArray,
        strokeDashOffset: paint.strokeDashOffset ?? ancestor.strokeDashOffset,
        mask: null); // Mask is not inherited
  }

  SvgTextAttributes cascadeText(SvgTextAttributes ancestor) {
    return SvgTextAttributes(
        fontSize: textAttributes.fontSize.orInherit(ancestor.fontSize),
        fontFamily: textAttributes.fontFamily ?? ancestor.fontFamily,
        textAnchor: textAttributes.textAnchor ?? ancestor.textAnchor,
        fontWeight: textAttributes.fontWeight.orInherit(ancestor.fontWeight),
        fontStyle: textAttributes.fontStyle ?? ancestor.fontStyle);
  }

  SvgNode resolveMask(Map<String, SvgNode> idLookup, SvgPaint ancestor,
      bool warn, _Referrers referrers) {
    if (paint.mask != null) {
      SvgNode? n = idLookup[paint.mask];
      if (n is SvgMask) {
        if (referrers.contains(n)) {
          if (warn) {
            print('    Ignoring mask that refers to itself.');
          }
        } else {
          return SvgMasked(this, n);
        }
      } else if (warn) {
        print('    $this references nonexistent mask ${paint.mask}');
      }
    }
    return this;
  }
}

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
  List<double>? strokeDashArray; // [] for "none"
  double? strokeDashOffset;
  String? mask;

  SvgPaint(
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
      required this.strokeDashArray,
      required this.strokeDashOffset,
      required this.mask});

  SvgPaint.empty()
      : fillColor = SvgColor.inherit,
        strokeColor = SvgColor.inherit,
        currentColor = SvgColor.inherit;

  factory SvgPaint.initial() => SvgPaint(
      currentColor: SvgColor.currentColor, // Inherit from SVG container
      fillColor: const SvgValueColor(0xff000000),
      fillAlpha: 0xff,
      strokeColor: SvgColor.none,
      strokeAlpha: 0xff,
      strokeWidth: 1,
      strokeMiterLimit: 4,
      strokeJoin: SIStrokeJoin.miter,
      strokeCap: SIStrokeCap.butt,
      fillType: SIFillType.nonZero,
      strokeDashArray: null,
      strokeDashOffset: null,
      mask: null);

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
          mask,
          strokeJoin,
          strokeCap,
          fillType,
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
          strokeJoin == other.strokeJoin &&
          strokeCap == other.strokeCap &&
          fillType == other.fillType &&
          quiver.listsEqual(strokeDashArray, other.strokeDashArray) &&
          strokeDashOffset == other.strokeDashOffset;
    } else {
      return false;
    }
  }

  SIPaint toSIPaint() {
    return SIPaint(
        fillColor: fillColor.toSIColor(fillAlpha, currentColor),
        strokeColor: strokeColor.toSIColor(strokeAlpha, currentColor),
        strokeWidth: strokeWidth,
        strokeMiterLimit: strokeMiterLimit,
        strokeJoin: strokeJoin,
        strokeCap: strokeCap,
        fillType: fillType,
        strokeDashArray: strokeDashArray,
        strokeDashOffset: strokeDashOffset);
  }
}

class SvgGroup extends SvgInheritableAttributes implements SvgNode {
  var children = List<SvgNode>.empty(growable: true);

  SvgGroup();

  @override
  SvgNode? resolve(Map<String, SvgNode> idLookup, SvgPaint ancestor, bool warn,
      _Referrers referrers) {
    final cascaded = cascadePaint(ancestor, idLookup);
    final newC = List<SvgNode>.empty(growable: true);
    referrers = _Referrers(this, referrers);
    for (SvgNode n in children) {
      final nn = n.resolve(idLookup, cascaded, warn, referrers);
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
      return resolveMask(idLookup, ancestor, warn, referrers);
    }
  }

  @override
  bool build(SIBuilder<String, SIImageData> builder, CanonicalizedData canon,
      Map<String, SvgNode> idLookup, SvgPaint ancestor, SvgTextAttributes ta) {
    final currTA = cascadeText(ta);
    final cascaded = cascadePaint(ancestor, idLookup);
    if (transform == null && groupAlpha == null && children.length == 1) {
      return children[0].build(builder, canon, idLookup, cascaded, currTA);
    } else {
      builder.group(null, transform, groupAlpha);
      for (final c in children) {
        c.build(builder, canon, idLookup, cascaded, currTA);
      }
      builder.endGroup(null);
      return true;
    }
  }

  @override
  void collectCanon(CanonicalizedData<SIImageData> canon) {
    canon.getIndex(canon.strings, textAttributes.fontFamily);
    for (final ch in children) {
      ch.collectCanon(canon);
    }
  }

  @override
  bool canUseLuma(Map<String, SvgNode> idLookup, SvgPaint ancestor) {
    final cascaded = cascadePaint(ancestor, idLookup);
    for (final ch in children) {
      if (ch.canUseLuma(idLookup, cascaded)) {
        return true;
      }
    }
    return false;
  }
}

class SvgDefs extends SvgGroup {
  SvgDefs() : super();

  @override
  SvgGroup? resolve(Map<String, SvgNode> idLookup, SvgPaint ancestor, bool warn,
      _Referrers referrers) {
    super.resolve(idLookup, ancestor, warn, referrers);
    return null;
  }

  @override
  bool build(SIBuilder<String, SIImageData> builder, CanonicalizedData canon,
      Map<String, SvgNode> idLookup, SvgPaint ancestor, SvgTextAttributes ta) {
    assert(false);
    return false;
  }
}

///
/// The mask itself, from a <mask> tag in the source file
///
class SvgMask extends SvgGroup {
  Rectangle<double>? bufferBounds;

  @override
  SvgGroup? resolve(Map<String, SvgNode> idLookup, SvgPaint ancestor, bool warn,
      _Referrers referrers) {
    if (referrers.contains(this)) {
      if (warn) {
        print('    Ignoring mask contained by itself.');
      }
      return null;
    } else {
      super.resolve(idLookup, ancestor, warn, _Referrers(this, referrers));
      return null;
    }
  }
}

class SvgClipPath extends SvgMask {
  @override
  SvgGroup? resolve(Map<String, SvgNode> idLookup, SvgPaint ancestor, bool warn,
      _Referrers referrers) {
    final result = super.resolve(idLookup, ancestor, warn, referrers);
    for (final c in children) {
      if (c is SvgInheritableAttributes) {
        // A bit of a hack:  We stomp on the paint attributes.  See
        // SVG 1.1, s. 14.3.5
        c.paint = SvgPaint(
            currentColor: SvgColor.currentColor, // Inherit from SVG container
            fillColor: SvgColor.white,
            fillAlpha: 255,
            strokeColor: SvgColor.none,
            strokeAlpha: 255,
            strokeWidth: 0,
            strokeMiterLimit: 4,
            strokeJoin: SIStrokeJoin.miter,
            strokeCap: SIStrokeCap.butt,
            fillType: SIFillType.nonZero,
            strokeDashArray: null,
            strokeDashOffset: null,
            mask: null);
      }
    }
    return result;
  }
}

///
/// A parent node for a node with a mask attribute.
///
class SvgMasked extends SvgNode {
  final SvgNode child;
  SvgMask mask;

  SvgMasked(this.child, this.mask);

  @override
  bool build(SIBuilder<String, SIImageData> builder, CanonicalizedData canon,
      Map<String, SvgNode> idLookup, SvgPaint ancestor, SvgTextAttributes ta) {
    bool canUseLuma = mask.canUseLuma(idLookup, ancestor);
    builder.masked(null, mask.bufferBounds, canUseLuma);
    bool built = mask.build(builder, canon, idLookup, ancestor, ta);
    if (!built) {
      builder.group(null, null, null);
      builder.endGroup(null);
    }
    builder.maskedChild(null);
    built = child.build(builder, canon, idLookup, ancestor, ta);
    if (!built) {
      builder.group(null, null, null);
      builder.endGroup(null);
    }
    builder.endMasked(null);
    return true;
  }

  @override
  void collectCanon(CanonicalizedData<SIImageData> canon) {
    mask.collectCanon(canon);
    child.collectCanon(canon);
  }

  @override
  SvgNode? resolve(Map<String, SvgNode> idLookup, SvgPaint ancestor, bool warn,
      _Referrers referrers) {
    assert(false); // We're added during resolve
    return null;
  }

  @override
  bool canUseLuma(Map<String, SvgNode> idLookup, SvgPaint ancestor) =>
      child.canUseLuma(idLookup, ancestor);
  // The mask can only change the alpha channel.
}

class SvgUse extends SvgInheritableAttributes implements SvgNode {
  String? childID;

  SvgUse(this.childID);

  @override
  SvgNode? resolve(Map<String, SvgNode> idLookup, SvgPaint ancestor, bool warn,
      _Referrers referrers) {
    if (childID == null) {
      if (warn) {
        print('    <use> has no xlink:href');
      }
      return null;
    }
    SvgNode? n = idLookup[childID];
    if (n == null) {
      if (warn) {
        print('    <use> references nonexistent $childID');
      }
      return null;
    } else if (referrers.contains(n)) {
      if (warn) {
        print('    Ignoring <use> that refers to itself.');
      }
      return null;
    }
    final cascaded = cascadePaint(ancestor, idLookup);
    n = n.resolve(idLookup, cascaded, warn, referrers);
    if (n == null || transform?.determinant() == 0.0) {
      return null;
    }
    final g = SvgGroup();
    g.groupAlpha = groupAlpha;
    g.paint = paint;
    g.transform = transform;
    g.children.add(n);
    return g.resolveMask(idLookup, ancestor, warn, referrers);
  }

  @override
  void collectCanon(CanonicalizedData<SIImageData> canon) {
    assert(false);
  }

  @override
  bool build(SIBuilder<String, SIImageData> builder, CanonicalizedData canon,
      Map<String, SvgNode> idLookup, SvgPaint ancestor, SvgTextAttributes ta) {
    assert(false);
    return false;
  }

  @override
  bool canUseLuma(Map<String, SvgNode> idLookup, SvgPaint ancestor) {
    assert(false); // Should be called after resolve
    return true;
  }
}

abstract class SvgPathMaker extends SvgInheritableAttributes
    implements SvgNode {
  @override
  void collectCanon(CanonicalizedData<SIImageData> canon) {}

  @override
  bool build(SIBuilder<String, SIImageData> builder, CanonicalizedData canon,
      Map<String, SvgNode> idLookup, SvgPaint ancestor, SvgTextAttributes ta) {
    final cascaded = cascadePaint(ancestor, idLookup);
    if (transform != null || groupAlpha != null) {
      builder.group(null, transform, groupAlpha);
      makePath(builder, cascaded);
      builder.endGroup(null);
      return true;
    } else {
      return makePath(builder, cascaded);
    }
  }

  /// Returns true if a path node is emitted
  bool makePath(SIBuilder<String, SIImageData> builder, SvgPaint cascaded);

  @override
  bool canUseLuma(Map<String, SvgNode> idLookup, SvgPaint ancestor) {
    final cascaded = cascadePaint(ancestor, idLookup);
    final p = cascaded.toSIPaint();
    return p.canUseLuma;
  }
}

class SvgPath extends SvgPathMaker {
  final String pathData;

  SvgPath(this.pathData);

  @override
  SvgNode? resolve(Map<String, SvgNode> idLookup, SvgPaint ancestor, bool warn,
      _Referrers referrers) {
    if (pathData == '') {
      return null;
    } else {
      return resolveMask(idLookup, ancestor, warn, referrers);
    }
  }

  @override
  bool makePath(SIBuilder<String, SIImageData> builder, SvgPaint cascaded) {
    if (_isInvisible(cascaded)) {
      return false;
    } else {
      builder.path(null, pathData, cascaded.toSIPaint());
      return true;
    }
  }
}

class SvgRect extends SvgPathMaker {
  final double x;
  final double y;
  final double width;
  final double height;
  final double rx;
  final double ry;

  SvgRect(this.x, this.y, this.width, this.height, this.rx, this.ry);

  @override
  SvgNode? resolve(Map<String, SvgNode> idLookup, SvgPaint ancestor, bool warn,
      _Referrers referrers) {
    if (width <= 0 || height <= 0) {
      return null;
    } else {
      return resolveMask(idLookup, ancestor, warn, referrers);
    }
  }

  @override
  bool makePath(SIBuilder<String, SIImageData> builder, SvgPaint cascaded) {
    if (_isInvisible(cascaded)) {
      return false;
    }
    SIPaint curr = cascaded.toSIPaint();
    PathBuilder? pb = builder.startPath(curr, this);
    if (pb == null) {
      return true;
    }
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
    return true;
  }

  @override
  bool operator ==(Object other) {
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
  int get hashCode =>
      0x04acdf77 ^ quiver.hash3(quiver.hash4(x, y, width, height), rx, ry);
}

class SvgEllipse extends SvgPathMaker {
  final double cx;
  final double cy;
  final double rx;
  final double ry;

  SvgEllipse(this.cx, this.cy, this.rx, this.ry);

  @override
  SvgNode? resolve(Map<String, SvgNode> idLookup, SvgPaint ancestor, bool warn,
      _Referrers referrers) {
    if (rx <= 0 || ry <= 0) {
      return null;
    } else {
      return resolveMask(idLookup, ancestor, warn, referrers);
    }
  }

  @override
  bool makePath(SIBuilder<String, SIImageData> builder, SvgPaint cascaded) {
    if (_isInvisible(cascaded)) {
      return false;
    }
    SIPaint curr = cascaded.toSIPaint();
    PathBuilder? pb = builder.startPath(curr, this);
    if (pb == null) {
      return true;
    }
    pb.addOval(RectT(cx - rx, cy - ry, 2 * rx, 2 * ry));
    pb.end();
    return true;
  }

  @override
  bool operator ==(Object other) {
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
  int get hashCode => 0x795d8ece ^ quiver.hash4(cx, cy, rx, ry);
}

class SvgPoly extends SvgPathMaker {
  final bool close; // true makes it a polygon; false a polyline
  final List<Point<double>> points;

  SvgPoly(this.close, this.points);

  @override
  SvgNode? resolve(Map<String, SvgNode> idLookup, SvgPaint ancestor, bool warn,
      _Referrers referrers) {
    if (points.length < 2) {
      return null;
    } else {
      return resolveMask(idLookup, ancestor, warn, referrers);
    }
  }

  @override
  bool makePath(SIBuilder<String, SIImageData> builder, SvgPaint cascaded) {
    if (_isInvisible(cascaded)) {
      return false;
    }
    SIPaint curr = cascaded.toSIPaint();
    PathBuilder? pb = builder.startPath(curr, this);
    if (pb == null) {
      return true;
    }
    pb.moveTo(points[0]);
    for (int i = 1; i < points.length; i++) {
      pb.lineTo(points[i]);
    }
    if (close) {
      pb.close();
    }
    pb.end();
    return true;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    } else if (other is SvgPoly) {
      return close == other.close && quiver.listsEqual(points, other.points);
    } else {
      return false;
    }
  }

  @override
  int get hashCode =>
      0xf4e007c0 ^ quiver.hash2(close, quiver.hashObjects(points));
}

class SvgGradientNode implements SvgNode {
  final SvgGradientColor gradient;
  final String? parentID;

  SvgGradientNode(this.parentID, this.gradient);

  @override
  SvgNode? resolve(Map<String, SvgNode> idLookup, SvgPaint ancestor, bool warn,
      _Referrers referrers) {
    final pid = parentID;
    if (pid != null) {
      var parent = idLookup[pid];
      var pLoop = parent;
      while (pLoop is SvgGradientNode) {
        if (identical(pLoop, this)) {
          if (warn) {
            print('    Gradient references itself:  $pid');
          }
          pLoop = null;
          parent = null;
        } else {
          final ppid = pLoop.parentID;
          if (ppid == null) {
            pLoop = null;
          } else {
            pLoop = idLookup[ppid];
          }
        }
      }
      if (parent is SvgGradientNode) {
        gradient.parent = parent.gradient;
      } else {
        if (warn) {
          print('    Gradient references non-existent gradient $pid');
        }
      }
    }
    // Our underlying gradient gets incorporated into SIPaint, so no reason to
    // keep the node around
    return null;
  }

  @override
  bool build(SIBuilder<String, SIImageData> builder, CanonicalizedData canon,
      Map<String, SvgNode> idLookup, SvgPaint ancestor, SvgTextAttributes ta) {
    // Do nothing - gradients are included in SIPaint
    return false;
  }

  @override
  bool canUseLuma(Map<String, SvgNode> idLookup, SvgPaint ancestor) {
    return false; // Because this node doesn't directly do any rendering
  }

  @override
  void collectCanon(CanonicalizedData<SIImageData> canon) {}
}

class SvgImage extends SvgInheritableAttributes implements SvgNode {
  AlignmentT? alignment;
  Uint8List imageData = _emptyData;
  double x = 0;
  double y = 0;
  double width = 0;
  double height = 0;
  int _imageNumber = -1;

  SvgImage();

  static final Uint8List _emptyData = Uint8List(0);

  @override
  void collectCanon(CanonicalizedData<SIImageData> canon) {
    final sid = SIImageData(
        x: x, y: y, width: width, height: height, encoded: imageData);
    _imageNumber = canon.getIndex(canon.images, sid)!;
  }

  @override
  SvgNode? resolve(Map<String, SvgNode> idLookup, SvgPaint ancestor, bool warn,
      _Referrers referrers) {
    if (width <= 0 || height <= 0) {
      return null;
    }
    return resolveMask(idLookup, ancestor, warn, referrers);
  }

  @override
  bool build(SIBuilder<String, SIImageData> builder, CanonicalizedData canon,
      Map<String, SvgNode> idLookup, SvgPaint ancestor, SvgTextAttributes ta) {
    assert(_imageNumber > -1);
    if (transform != null || groupAlpha != null) {
      builder.group(null, transform, groupAlpha);
      builder.image(null, _imageNumber);
      builder.endGroup(null);
    } else {
      builder.image(null, _imageNumber);
    }
    return true;
  }

  @override
  bool canUseLuma(Map<String, SvgNode> idLookup, SvgPaint ancestor) {
    return true;
  }
}

class SvgText extends SvgInheritableAttributes implements SvgNode {
  String text = '';
  List<double> x = const [0.0];
  List<double> y = const [0.0];
  int xIndex = -1;
  int yIndex = -1;
  int textIndex = -1;

  SvgText();

  @override
  SvgNode? resolve(Map<String, SvgNode> idLookup, SvgPaint ancestor, bool warn,
      _Referrers referrers) {
    if (text == '') {
      return null;
    } else {
      return resolveMask(idLookup, ancestor, warn, referrers);
    }
  }

  @override
  bool build(SIBuilder<String, SIImageData> builder, CanonicalizedData canon,
      Map<String, SvgNode> idLookup, SvgPaint ancestor, SvgTextAttributes ta) {
    final cascaded = cascadePaint(ancestor, idLookup);
    if (cascaded.fillAlpha == 0 || cascaded.fillColor == SvgColor.none) {
      if (cascaded.strokeAlpha == 0 ||
          cascaded.strokeColor == SvgColor.none ||
          cascaded.strokeWidth == 0) {
        return false;
      }
    }
    final currPaint = cascaded.toSIPaint().forText();
    final currTA = cascadeText(ta).toSITextAttributes();
    final int? fontFamilyIndex;
    if (currTA.fontFamily == '') {
      fontFamilyIndex = null;
    } else {
      fontFamilyIndex = canon.strings[currTA.fontFamily];
      assert(fontFamilyIndex != null);
    }
    if (transform != null || groupAlpha != null) {
      builder.group(null, transform, groupAlpha);
      builder.text(
          null, xIndex, yIndex, textIndex, currTA, fontFamilyIndex, currPaint);
      builder.endGroup(null);
    } else {
      builder.text(
          null, xIndex, yIndex, textIndex, currTA, fontFamilyIndex, currPaint);
    }
    return true;
  }

  @override
  void collectCanon(CanonicalizedData canon) {
    xIndex = canon.getIndex(canon.floatLists, x)!;
    yIndex = canon.getIndex(canon.floatLists, y)!;
    textIndex = canon.getIndex(canon.strings, text)!;
    canon.getIndex(canon.strings, textAttributes.fontFamily);
  }

  @override
  bool canUseLuma(Map<String, SvgNode> idLookup, SvgPaint ancestor) {
    final cascaded = cascadePaint(ancestor, idLookup);
    final p = cascaded.toSIPaint().forText();
    return p.canUseLuma;
  }
}

class SvgTextAttributes {
  String? fontFamily;
  SIFontStyle? fontStyle;
  SITextAnchor? textAnchor;
  SvgFontWeight fontWeight = SvgFontWeight.inherit;
  SvgFontSize fontSize = SvgFontSize.inherit;

  SvgTextAttributes.empty();
  SvgTextAttributes(
      {required this.fontFamily,
      required this.fontStyle,
      required this.textAnchor,
      required this.fontWeight,
      required this.fontSize});

  SvgTextAttributes.initial()
      : fontFamily = '',
        textAnchor = SITextAnchor.start,
        fontStyle = SIFontStyle.normal,
        fontWeight = SvgFontWeight.w400,
        fontSize = SvgFontSize.medium;

  SITextAttributes toSITextAttributes() => SITextAttributes(
      fontFamily: fontFamily!,
      textAnchor: textAnchor!,
      fontStyle: fontStyle!,
      fontWeight: fontWeight.toSI(),
      fontSize: fontSize.toSI());
}

///
/// Font size as SVG knows it.
///
abstract class SvgFontSize {
  const SvgFontSize();

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

  SvgFontSize orInherit(SvgFontSize ancestor);

  double toSI() {
    assert(false);
    return 12.0;
  }
}

class _SvgFontSizeAbsolute extends SvgFontSize {
  final double size;

  const _SvgFontSizeAbsolute(this.size);

  @override
  SvgFontSize orInherit(SvgFontSize ancestor) => this;

  @override
  double toSI() => size;
}

class _SvgFontSizeRelative extends SvgFontSize {
  final double scale;

  const _SvgFontSizeRelative(this.scale);

  @override
  SvgFontSize orInherit(SvgFontSize ancestor) {
    if (ancestor is _SvgFontSizeAbsolute) {
      return _SvgFontSizeAbsolute(ancestor.size * scale);
    } else {
      assert(false);
      return SvgFontSize.medium;
    }
  }
}

class _SvgFontSizeInherit extends SvgFontSize {
  const _SvgFontSizeInherit();

  @override
  SvgFontSize orInherit(SvgFontSize ancestor) {
    if (ancestor == SvgFontSize.inherit) {
      assert(false);
      return SvgFontSize.medium;
    } else {
      return ancestor;
    }
  }
}

///
/// Color as SVG knows it, plus alpha in the high-order byte (in case we
/// encounter an SVG file with an (invalid) eight-character hex value).
///
abstract class SvgColor {
  const SvgColor();

  ///
  /// Create a normal, explicit color from an 0xaarrggbb value.
  ///
  factory SvgColor.value(int value) => SvgValueColor(value);

  ///
  /// Create the "inherit" color, which means "inherit from parent"
  ///
  static const SvgColor inherit = _SvgInheritColor._p();

  ///
  /// The "none" color, which means "do not paint"
  ///
  static const SvgColor none = _SvgNoneColor._p();

  ///
  /// Create the "currentColor" color, which means "paint with the color given
  /// to the ScalableImage's parent".
  ///
  static const SvgColor currentColor = _SvgCurrentColor._p();

  static const SvgColor white = SvgValueColor(0xffffffff);

  SvgColor orInherit(SvgColor ancestor, Map<String, SvgNode> ids) => this;

  SIColor toSIColor(int? alpha, SvgColor cascadedCurrentColor);

  static SvgColor reference(String id) => _SvgColorReference(id);
}

class SvgValueColor extends SvgColor {
  final int _value;
  const SvgValueColor(this._value);

  @override
  SIColor toSIColor(int? alpha, SvgColor cascadedCurrentColor) {
    if (alpha == null) {
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
  SvgColor orInherit(SvgColor ancestor, Map<String, SvgNode> ids) => ancestor;

  @override
  SIColor toSIColor(int? alpha, SvgColor cascadedCurrentColor) =>
      throw StateError('Internal error: color inheritance');
}

class _SvgNoneColor extends SvgColor {
  const _SvgNoneColor._p();

  @override
  SIColor toSIColor(int? alpha, SvgColor cascadedCurrentColor) => SIColor.none;
}

class _SvgCurrentColor extends SvgColor {
  const _SvgCurrentColor._p();

  @override
  SIColor toSIColor(int? alpha, SvgColor cascadedCurrentColor) {
    if (cascadedCurrentColor is _SvgCurrentColor) {
      return SIColor.currentColor;
    } else {
      return cascadedCurrentColor.toSIColor(alpha, const SvgValueColor(0));
    }
  }
}

class _SvgColorReference extends SvgColor {
  final String id;

  _SvgColorReference(this.id);

  @override
  SvgColor orInherit(SvgColor ancestor, Map<String, SvgNode> ids) {
    final n = ids[id];
    if (n is! SvgGradientNode) {
      throw ParseError('Gradient $id not found');
    }
    return n.gradient;
  }

  @override
  SIColor toSIColor(int? alpha, SvgColor cascadedCurrentColor) =>
      throw StateError('Internal error: color inheritance');
}

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

abstract class SvgGradientColor extends SvgColor {
  final bool? objectBoundingBox;
  List<SvgGradientStop>? stops;
  Affine? transform;
  SvgGradientColor? parent;
  final SIGradientSpreadMethod? spreadMethod;

  SvgGradientColor(this.objectBoundingBox, this.transform, this.spreadMethod);

  // Resolving getters:

  bool get objectBoundingBoxR =>
      objectBoundingBox ?? parent?.objectBoundingBoxR ?? true;

  List<SvgGradientStop> get stopsR => stops ?? parent?.stopsR ?? [];

  Affine? get transformR => transform ?? parent?.transformR;

  SIGradientSpreadMethod get spreadMethodR =>
      spreadMethod ?? parent?.spreadMethodR ?? SIGradientSpreadMethod.pad;

  void addStop(SvgGradientStop s) {
    final sl = stops ??= List<SvgGradientStop>.empty(growable: true);
    sl.add(s);
  }
}

class SvgLinearGradientColor extends SvgGradientColor {
  final double? x1;
  final double? y1;
  final double? x2;
  final double? y2;

  SvgLinearGradientColor? get linearParent {
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
      : super(objectBoundingBox, transform, spreadMethod);

  // Resolving getters:

  double get x1R => x1 ?? linearParent?.x1R ?? 0.0;
  double get y1R => y1 ?? linearParent?.y1R ?? 0.0;
  double get x2R => x2 ?? linearParent?.x2R ?? 1.0;
  double get y2R => y2 ?? linearParent?.y2R ?? 0.0;

  @override
  SIColor toSIColor(int? alpha, SvgColor cascadedCurrentColor) {
    final stops = stopsR;
    final offsets = List<double>.generate(stops.length, (i) => stops[i].offset,
        growable: false);
    final colors = List<SIColor>.generate(stops.length,
        (i) => stops[i].color.toSIColor(stops[i].alpha, cascadedCurrentColor),
        growable: false);
    return SILinearGradientColor(
        x1: x1R,
        y1: y1R,
        x2: x2R,
        y2: y2R,
        colors: colors,
        stops: offsets,
        objectBoundingBox: objectBoundingBoxR,
        spreadMethod: spreadMethodR,
        transform: transformR);
  }
}

class SvgRadialGradientColor extends SvgGradientColor {
  final double? cx; // default 0.5
  final double? cy; // default 0.5
  final double? fx;
  final double? fy;
  final double? r; // default 0.5

  SvgRadialGradientColor? get radialParent {
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
      : super(objectBoundingBox, transform, spreadMethod);

  // Resolving getters:

  double get cxR => cx ?? radialParent?.cxR ?? 0.5;
  double get cyR => cy ?? radialParent?.cyR ?? 0.5;
  double? get fxR => fx ?? radialParent?.fxR;
  double? get fyR => fy ?? radialParent?.fyR;
  double get rR => r ?? radialParent?.rR ?? 0.5;

  @override
  SIColor toSIColor(int? alpha, SvgColor cascadedCurrentColor) {
    final stops = stopsR;
    final offsets = List<double>.generate(stops.length, (i) => stops[i].offset,
        growable: false);
    final colors = List<SIColor>.generate(stops.length,
        (i) => stops[i].color.toSIColor(stops[i].alpha, cascadedCurrentColor),
        growable: false);
    return SIRadialGradientColor(
        cx: cxR,
        cy: cyR,
        fx: fxR ?? cxR,
        fy: fyR ?? cyR,
        r: rR,
        colors: colors,
        stops: offsets,
        objectBoundingBox: objectBoundingBoxR,
        spreadMethod: spreadMethodR,
        transform: transformR);
  }
}

class SvgSweepGradientColor extends SvgGradientColor {
  final double? cx; // default 0.5
  final double? cy; // default 0.5
  final double? startAngle;
  final double? endAngle;

  SvgSweepGradientColor? get sweepParent {
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
      : super(objectBoundingBox, transform, spreadMethod);

  // Resolving getters:

  double get cxR => cx ?? sweepParent?.cxR ?? 0.5;
  double get cyR => cy ?? sweepParent?.cyR ?? 0.5;
  double get startAngleR => startAngle ?? sweepParent?.startAngleR ?? 0.0;
  double get endAngleR => endAngle ?? sweepParent?.endAngleR ?? 2 * pi;

  @override
  SIColor toSIColor(int? alpha, SvgColor cascadedCurrentColor) {
    final stops = stopsR;
    final offsets = List<double>.generate(stops.length, (i) => stops[i].offset,
        growable: false);
    final colors = List<SIColor>.generate(stops.length,
        (i) => stops[i].color.toSIColor(stops[i].alpha, cascadedCurrentColor),
        growable: false);
    return SISweepGradientColor(
        cx: cxR,
        cy: cyR,
        startAngle: startAngleR,
        endAngle: endAngleR,
        colors: colors,
        stops: offsets,
        objectBoundingBox: objectBoundingBoxR,
        spreadMethod: spreadMethodR,
        transform: transformR);
  }
}

abstract class SvgFontWeight {
  const SvgFontWeight();

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

  SvgFontWeight orInherit(SvgFontWeight ancestor);
  SIFontWeight toSI();
}

class _SvgFontWeightAbsolute extends SvgFontWeight {
  final SIFontWeight weight;
  const _SvgFontWeightAbsolute(this.weight);

  @override
  SvgFontWeight orInherit(SvgFontWeight ancestor) => this;

  @override
  SIFontWeight toSI() => weight;
}

class _SvgFontWeightBolder extends SvgFontWeight {
  const _SvgFontWeightBolder();

  @override
  SvgFontWeight orInherit(SvgFontWeight ancestor) {
    int i = ancestor.toSI().index;
    return _SvgFontWeightAbsolute(
        SIFontWeight.values[min(i + 1, SIFontWeight.values.length - 1)]);
  }

  @override
  SIFontWeight toSI() {
    assert(false);
    return SIFontWeight.w400;
  }
}

class _SvgFontWeightLighter extends SvgFontWeight {
  const _SvgFontWeightLighter();

  @override
  SvgFontWeight orInherit(SvgFontWeight ancestor) {
    int i = ancestor.toSI().index;
    return _SvgFontWeightAbsolute(SIFontWeight.values[max(i - 1, 0)]);
  }

  @override
  SIFontWeight toSI() {
    assert(false);
    return SIFontWeight.w400;
  }
}

class _SvgFontWeightInherit extends SvgFontWeight {
  const _SvgFontWeightInherit();

  @override
  SvgFontWeight orInherit(SvgFontWeight ancestor) => ancestor;

  @override
  SIFontWeight toSI() {
    assert(false);
    return SIFontWeight.w400;
  }
}
