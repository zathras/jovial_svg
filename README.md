# jovial_svg 

Robust, efficient rendering of SVG static images, supporting a well-defined 
profile of SVG and an efficient binary storage format.  Very fast load times 
result from using this binary format -- loading a pre-compiled binary file 
is usually an order of magnitude faster than parsing an XML SVG file.  Observed
speedups for loading larger SVG files range from 5x to 20x.

The supported SVG profile
includes the parts of 
[SVG Tiny 1.2](https://www.w3.org/TR/2008/REC-SVGTiny12-20081222/)
that are applicable to static images, plus a healthy subset of
[SVG 1.1](https://www.w3.org/TR/2011/REC-SVG11-20110816/).  In-line 
Cascading style sheets (CSS) are supported, via the `<style>` tag.
In addition to SVG, [Android Vector Drawable](https://developer.android.com/guide/topics/graphics/vector-drawable-resources) files
are supported.  A widget for displaying these scalable images is provided.

The library is [published to `pub.dev`](https://pub.dev/packages/jovial_svg),
where you can also find the
[dartdocs](https://pub.dev/documentation/jovial_svg/latest/jovial_svg/jovial_svg-library.html).
It's used for the jupiter icon in
[JRPN](https://jrpn.jovial.com), and for the cards in
[Jovial Aisleriot](https://aisleriot.jovial.com/).

<img width="100%" src="https://raw.githubusercontent.com/zathras/jovial_svg/main/doc/images/demo_mask.png">

## Getting Started

An SVG can be parsed into a `ScalableImage` and displayed in a
`ScalableImageWidget` like this:
```
MaterialApp(
  title: 'SVG Minimal Sample',
  home: ScalableImageWidget.fromSISource(
      si: ScalableImageSource.fromSvgHttpUrl(
          Uri.parse('https://jovial.com/images/jupiter.svg'))));
```
It's generally preferable to pre-load an instance of `ScalableImage`, as
discussed below.

[Sample applicatons](https://github.com/zathras/jovial_svg/tree/main/example) 
are available.  The 
[asset sample](https://github.com/zathras/jovial_svg/blob/main/example/lib/asset.dart)
shows the common case of a static SVG asset bundled with the application.
The 
[cache sample](https://github.com/zathras/jovial_svg/blob/main/example/lib/cache.dart) 
might be of interest if `ScalableImageWidget` is used in a widget that is
frequently rebuilt (e.g. because it's used in an animation), or if SVGs 
are to be loaded over the network.  There's 
also an example of extending `jovial_svg` with a 
[persistent cache](https://github.com/zathras/jovial_svg/tree/main/demo_hive).

Parsing an XML file isn't terribly efficient, and it's generally better to
do any loading before building a widget tree.  This package 
includes tools to make its use more efficient in both of these aspects.  

### Quick Loading Binary Format

The `svg_to_si` program compiles an SVG file into a much more efficient 
binary representation, suitable for inclusion in an asset bundle.  The
`avd_to_si` program converts an Android Vector Drawable file.  <em>Converting
to an si file speeds runtime loading by an order of magnitude.</em>  You can
activate the conversion programs with `dart pub global activate jovial_svg`,
or you can run them from your project directory like this:

```
dart run jovial_svg:svg_to_si path/to/SVG_Logo.svg --out output/dir
```

### Rendering Performance

Rendering a complex asset can be a time-consuming operation,
particularly in terms of GPU load.  Flutter's
[`RepaintBoundary`](https://api.flutter.dev/flutter/widgets/RepaintBoundary-class.html)
can work well to avoid re-rendering a complex `ScalableImage` asset.  This
is discussed in the `ScalableImageWidget` documentation.

### Pre-loading Scalable Images

For optimal performance, you can pre-load a `ScalableImage` using various 
static methods defined on the class.  You can also proactively load
and decode any image assets contained within the `ScalableImage`.  Once
ready, your `ScalableImage` can be used synchronously with 
`ScalableImageWidget`, or directly with a Flutter `CustomPaint`.

Avoiding reloading is, of course, especially important if a
`ScalableImage` is displayed as part of an animation, or if it is loaded
over the network.  `ScalableImageWidget` does, however, have an option for 
the widget to handle loading and the the asynchronous operations, for 
convenience and/or quick prototyping.  Using a `ScalableImageCache` with
`ScalableImageWidget` can be a good way to avoid reloading, without the need
to directly manage `ScalableImage` instances as part of your application's
state.

## Demo Program

To try out the library, see the 
[demo program](https://github.com/zathras/jovial_svg/tree/main/demo).  It's 
mostly intended to be run on the desktop, though it will run fine on other
platforms.  It lets you cycle through a series of test
images, including several taken from an open-source card game
([Aisleriot](https://wiki.gnome.org/Apps/Aisleriot)).  The demo also lets
you paste the URL to an SVG asset into the program; it then loads and renders
it.

<img width="80%" src="https://raw.githubusercontent.com/zathras/jovial_svg/main/doc/images/demo_screen_shot.png">

## Supported SVG Profile

Most features of SVG 1.1 that are applicable to static SVG documents are
supported.  This includes using CSS (the `<style>` tag) to specify SVG
attributes.

  * SVG paths and transforms are of course supported.
  * The `use` element is supported (including forward references).
  * Stroke modifiers like `stroke-linecap`, `stroke-linejoin` and
     `stroke-miterlimit` are supported.
  * The `stroke-dasharray` and `stroke-dashoffset` attributes are
     supported (cf. Tiny s. 11.4).
  * Gradients are supported, and additionally support `xlink:href` attributes 
     to other gradients, and `gradientTransform` attributes from SVG 1.1.
  * The `mask` element is supported (not in Tiny; see SVG 1.1 s. 14.4).
     Note that as of this writing, a long-standing 
     <a href="https://github.com/flutter/flutter/issues/48417">bug in Flutter
     web's "html" renderer</a> prevents it from working on this niche
     platform, though it works with the canvaskit renderer.  See also
     <a href="https://github.com/zathras/jovial_svg/issues/24">Issue 24</a>.
  * Text elements are supported.
  * Embedded images are supported.
  * Inheritable properties are supported.
  * Object/group opacity is supported -- cf. SVG 1.1 s. 14.5.  (Not
     in Tiny).
  * The symbol element is supported (Not in Tiny; cf.  SVG 5.5).
  * The pattern element is not supported (Not in Tiny; cf. SVG 13.3).
  * The `style` tag for inline CSS and the `style=` attribute are
     supported to specify node attributes (not in Tiny - cf. s. 6.2).
  * CSS attributes that don't have a corresponding SVG attribute generally
    are not supported, e.g. `background` and `transform-origin` are not.
  * Non-scaling stroke is not supported (not in SVG 1.1; cf. Tiny 11.5)
  * Constrained transformations are not supported (not in SVG 1.1;
     cf. Tiny 7.7)
  * A DOM and other features related to animation are not supported.
  * Conditional processing (Tiny s. 5.8) is not supported
  * The `clipPath` SVG element is supported (not in Tiny, cf. SVG 1.1 14.3.5).
  * Filter effects via the `filter` tag are not supported (not in Tiny, cf.
     SVG s. 15) 
  * XML namespaces are ignored.
  * Text profile:
      * `text` and `tspan` tags are supported.
      * Embedded fonts are not supported.  However, the `font-family` attribute
        is used when selecting a font, and fonts can be included in an 
        application that uses this library.  For example, the demo program
        uses the 
        <a href="https://www.dafont.com/rollerball-1975.font">ROLLERBALL
        1975</a> font to render
        <a href="https://raw.githubusercontent.com/zathras/jovial_svg/main/doc/images/demo_hippie.png">this
        image</a>.
      * `textArea` is not supported (not in SVG 1.1).
      * `font-variant` (`small-caps`) is not supported.
      * `rotate` is not supported (but normal transformations, including 
         rotation, apply to text elements).
      * Bi-directional text is not supported

## Supported AVD Profile

  *  Scaling with `android:width`/`android:height` requires specification 
     of `android:viewportWidth`/`android:viewportHeight`.
  *  `android:autoMirrored` is not supported.
  *  `android:alpha` on a `vector` tag is not supported.
 
## Goals and Package Evolution

This library was originally written because existing alternatives didn't
correctly handle many aspects of SVG.  This made it impossible to re-purpose
existing SVG graphical assets, e.g. from other open-source programs.
Additionally, runtime performance wasn't so good, perhaps due to the overhead
associated with parsing XML.

It must be said that the SVG specifications are rather large.  SVG 2 notably
added a rich set of features that aren't needed for a graphics interchange
format.  SVG in browsers also supports scripting and animation.  Further, 
this family of specifications has always been somewhat squishy about conformance
and profiling -- there's a whole set of resources devoted to tracking which
browsers support which features, and that's with fairly large and well-funded
teams developing browsers over decades.

However, there are a large number of (quite beautiful!) SVG assets for static
images that generally stay within the bounds of SVG 1.1.  SVG Tiny 1.2 is a
reasonable collection of the most important parts of SVG 1.1 -- it was intended
as such (though it has since been essentially abandoned).  One of the 
challenges in developing this kind of library is deciding which features are 
essential, and which are gold-plating that are not in wide use.  For this 
library, informed guesses were necessary at some points; SVG Tiny provided
a solid starting point that a group of experts put considerable thought behind.

If you come across an SVG
asset that falls within the scope of this library, but that doesn't render,
please try to narrow down what support would be needed in the library, and 
submit an image that correctly uses that feature in any bug 
report.  Contributions can be considered too -- and the binary format 
has plenty of room for extensibility.

For the binary format, it is a goal to ensure that new versions of the
library continue to read old files.  Old versions of the library do not need
to read new `.si` files, however - the library can simply fail when 
it detects a newer file version number.  `.si` files are intended to be bundled 
as application resources alongside the library, and not used as a 
publication format.

## Internal Documentation

There's a high-level overview of the source code in the repo, in
`doc/index.html`.  This complements a reasonably (though not extensive)
level of comments in the source itself.
