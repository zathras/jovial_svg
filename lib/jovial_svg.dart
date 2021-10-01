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
// ignore: comment_references
/// This library offers a static [ScalableImage] that can be loaded from:
///
///   *  An SVG file.
///   *  An Android Vector Drawable file
///   *  A more compact and much more efficient `.si` file that was
///      compiled from an SVG or AVD file.
///
///  A robust profile of SVG targeted at static images is supported.  It
///  generally consists of the features that are relevant to static images
///  defined in
///  [SVG Tiny 1.2](https://www.w3.org/TR/2008/REC-SVGTiny12-20081222/),
///  plus commonly-used elements from
///  [SVG 1.1](https://www.w3.org/TR/2011/REC-SVG11-20110816/).  More details
///  about the supported SVG profile can be found in the top-level
///  documentation, or in the
///  [github repo](https://github.com/zathras/jovial_svg)'s README.
///
///  A compact `.si` file can be created with `dart run jovial_svg:svg_to_si`
///  or `dart run jovial_svg:avd_to_si` (after  running `dart pub get`).
///
// ignore: comment_references
///  [ScalableImageWidget] can be used to display a [ScalableImage].
///  The image can be automatically scaled by the widget, and fit into the
///  available area with a `BoxFit` and an `Alignment`.
// ignore: comment_references
///  [ScalableImageWidget]
// ignore: comment_references
///  will, if needed, asynchronously load a [ScalableImage] asset and
///  prepare any embedded pixel-based images.
///
library jovial_svg;

export 'src/exported.dart' show ScalableImage, ImageDisposeBugWorkaround;
export 'src/widget.dart'
    show ScalableImageWidget, ScalableImageSource, ScalableImageCache;
