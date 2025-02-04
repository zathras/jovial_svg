/*
Copyright (c) 2021-2025, William Foote

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

// ignore: comment_references
///
/// This package provides a document object model to allow programmatic
/// modification of an SVG asset.  It can be used for animation/scripting,
/// where the asset is modified then displayed, perhaps many times.
/// This is similar to what some web pages do with JavaScript code
/// modifying an SVG.
///
/// Sample Usage:
/// ```
/// final String svgSrc =
///     '<svg><circle id="foo" cx="5" cy="5" r="5" fill="green"/></svg>';
/// final svg = SvgDOMManager.fromString(svgSrc);
/// final node = svg.dom.idLookup['foo'] as SvgEllipse;
/// node.paint.fillColor = Colors.blue;
/// final ScalableImage si = svg.build();
///    ... display si, perhaps in a ScalableImageWidget ...
/// ```
///
/// A full sample can be found in the GitHub repository in
/// `example/lib/animation.dart`.  Here is an overview of the DOM
/// class structure:
/// <img src="https://raw.githubusercontent.com/zathras/jovial_svg/main/doc/uml/svg_dom.svg" />
///
library;

import 'dart:ui';

import 'package:jovial_svg/src/common_noui.dart';
import 'package:jovial_svg/src/dag.dart';
import 'package:jovial_svg/src/svg_parser.dart';

import 'jovial_svg.dart';
import 'src/svg_graph.dart';

export 'src/svg_graph.dart'
    show
        SvgDOM,
        Style,
        Stylesheet,
        SvgNode,
        SvgInheritableTextAttributes,
        SvgInheritableAttributes,
        SvgInheritableAttributesNode,
        SvgPaint,
        SvgGroup,
        SvgRoot,
        SvgDefs,
        SvgMask,
        SvgUse,
        SvgSymbol,
        SvgPath,
        SvgRect,
        SvgEllipse,
        SvgPoly,
        SvgGradientNode,
        SvgImage,
        SvgTextStyle,
        SvgFontSize,
        SvgFontSizeAbsolute,
        SvgColor,
        SvgValueColor,
        SvgColorReference,
        SvgGradientStop,
        SvgGradientStopStyle,
        SvgGradientColor,
        SvgCoordinate,
        SvgLinearGradientColor,
        SvgRadialGradientColor,
        SvgSweepGradientColor,
        SvgFontWeight,
        SvgText,
        SvgTextSpan,
        SvgTextSpanComponent,
        SvgTextSpanStringComponent;

export 'src/path.dart' show SvgCustomPath;

export 'src/path_noui.dart' show PathParser, PathBuilder, StringPathBuilder;

export 'src/common_noui.dart'
    show
        ParseError,
        SIFillType,
        SIStrokeJoin,
        SIStrokeCap,
        SIBlendMode,
        SIGradientSpreadMethod,
        SITintMode,
        SIDominantBaseline,
        SIFontStyle,
        SITextAnchor,
        SITextDecoration;

export 'src/affine.dart' show Affine, MutableAffine;

///
/// Support for loading an SVG asset, manipulating it, and producing
/// [ScalableImage] instances from the asset's current state.
/// This is the entry point for use of the dom library.
///
class SvgDOMManager {
  SvgDOMManager._new(this.dom);

  ///
  /// The DOM being managed.  You can modify it before calling
  /// [build].
  ///
  final SvgDOM dom;

  ScalableImageDag? _lastDag;
  Map<Object?, Path>? _lastPaths;
  bool _lastCall = false;

  ///
  /// Create a new manager to manage an SVG DOM created from
  /// the XML representation in the stream [input].
  ///
  /// [exportedIDs] specifies a list of node IDs that are to be exported.
  /// Each time [build] is called, the set returned from the new instance's
  /// [ScalableImage.exportedIDs] will be different than from previous
  /// instances.
  ///
  /// If [warnF] is non-null, it will be called if the SVG asset contains
  /// unrecognized tags and/or tag attributes.  If it is null, the default
  /// behavior is to do nothing.
  ///
  static Future<SvgDOMManager> fromStream(final Stream<String> input,
      {List<Pattern> exportedIDs = const [],
      void Function(String)? warnF}) async {
    final warnArg = warnF ?? nullWarn;
    final p = StreamSvgParser(input, exportedIDs, null, warn: warnArg);
    await p.parse();
    return SvgDOMManager._new(p.svg);
  }

  ///
  /// Create a new manager to manage an SVG DOM created from
  /// the XML representation in [input].
  ///
  /// [exportedIDs] specifies a list of node IDs that are to be exported.
  /// Each time [build] is called, the set returned from the new instance's
  /// [ScalableImage.exportedIDs] will be different than from previous
  /// instances.
  ///
  /// If [warnF] is non-null, it will be called if the SVG asset contains
  /// unrecognized tags and/or tag attributes.  If it is null, the default
  /// behavior is to do nothing.
  ///
  static SvgDOMManager fromString(final String input,
      {List<Pattern> exportedIDs = const [], void Function(String)? warnF}) {
    final warnArg = warnF ?? nullWarn;
    final p = StringSvgParser(input, exportedIDs, null, warn: warnArg);
    p.parse();
    return SvgDOMManager._new(p.svg);
  }

  ///
  /// Create a [ScalableImage] from [dom].  The intended usage of this
  /// method is to create a [ScalableImage] after modifications have been
  /// made to [dom], so that it can be displayed.
  /// Later, further modifications can be made, and a new
  /// [ScalableImage] can be produced by calling this method again. That
  /// new [ScalableImage] can replace the old one.  This method produces the
  /// faster DAG (directed acyclic graph) representation of the [ScalableImage],
  /// that is, not the compact representation.
  ///
  /// When a subsequent [ScalableImage] is produced in this way, the new
  /// DAG will share nodes with the last one produced, wherever possible.
  /// Notably, Flutter `Path` objects will be shared wherever possible. This
  /// may allow for more efficient rendering, if those `Path` objects are
  /// cached, e.g. in the GPU hardware.
  ///
  /// If [last] is set true, this is the last time this method may be called
  /// on this instance.
  /// Subsequent invocations will fail with a `StateError`.
  /// However, setting this true makes the build process consume
  /// less memory, and be faster.
  ///
  /// If [warnF] is non-null, it will be called if the SVG asset contains
  /// unrecognized tags and/or tag attributes.  If it is null, the default
  /// behavior is to print nothing.
  ///
  /// [currentColor] sets [ScalableImage.currentColor].
  ///
  ScalableImage build(
      {bool last = false, void Function(String)? warnF, Color? currentColor}) {
    if (_lastCall) {
      throw StateError('build was previously called with last true');
    }
    _lastCall = last;
    final warnArg = warnF ?? nullWarn;
    final SvgDOM svg;
    if (last) {
      svg = dom;
      // The client might have messed up the ID lookup table, and might
      // have introduced instance sharing on attributes that we modify
      // when stylesheets are applied.
      svg.resetIDLookup();
      SvgDOMNotExported.cloneAttributes(svg);
    } else {
      svg = SvgDOMNotExported.clone(dom); // Builds ID lookup
    }
    final b = SIDagBuilder(warn: warnArg, currentColor: currentColor);
    if (_lastDag != null) {
      final lastPaths = _lastPaths!;
      SvgDOMNotExported.visitPaths(dom, (Object pathKey) {
        final Path? p = lastPaths[pathKey];
        if (p != null) {
          b.paths[pathKey] = p;
        }
      });
      ScalableImageDagNotExported.addAllToDagger(_lastDag!, b.dagger);
    }
    SvgDOMNotExported.build(svg, b);
    final si = b.si;
    if (last) {
      _lastDag = null;
      _lastPaths = null;
    } else {
      _lastDag = si;
      _lastPaths = b.paths;
    }
    return si;
  }

  ///
  /// Give a human-readable sketch of the contents of our DOM.  This might
  /// be useful for debugging and/or exploration.
  ///
  @override
  String toString() => '${super.toString()} : $dom';
}
