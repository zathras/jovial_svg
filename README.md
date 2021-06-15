# jovial_svg 

Robust, efficient rendering of SVG static images, supporting a well-defined 
profile of SVG and an efficient binary storage format.  Very fast load times 
result from using this binary format - loading a pre-compiled binary file 
is usually an order of magnitude faster than parsing an XML SVG file - observed
speedups for loading larger SVG files range from 5x to 20x.

The supported SVG profile
includes the parts of 
[SVG Tiny 1.2](https://www.w3.org/TR/2008/REC-SVGTiny12-20081222/)
that are applicable to static images, plus commonly-used elements from
[SVG 1.1](https://www.w3.org/TR/2011/REC-SVG11-20110816/).  In addition,
[Android Vector Drawable](https://developer.android.com/guide/topics/graphics/vector-drawable-resources) files
are supported.  A widget for displaying scalable images is provided.

<img width="100%" src="https://raw.githubusercontent.com/zathras/jovial_svg/main/doc/images/demo_screen_shot.png">

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
A [minimal application](https://github.com/zathras/jovial_svg/tree/main/sample) is
available as a sample.

Parsing an XML file isn't terribly efficient, and it's generally better to
do any asynchronous loading before building a widget tree.  This package 
includes tools to make its use more efficient in bot of these aspects.  

The `svg_to_si` program compiles an SVG file into a much more efficient 
binary representation, suitable for inclusion in an asset bundle.  
It can be run with `dart run jovial_svg:svg_to_si`, or if you have an
Android Vector Drawable, `dart run jovial_svg:avd_to_si`.  This speeds
runtime loading by an order of magnitude.

In order to avoid a visual flash while assets are asynchronously loaded,
you can pre-load a `ScalableImage` using various static methods defined 
on the class.  You can also proactively cause any embedded images to be
decoded before first display.  Once ready, your `ScalableImage` can be used
synchronously with `ScalableImageWidget`, or directly with a Flutter
`CustomPaint`.  `ScalableImageWidget` also has an option for the widget
to do the asynchronous operations, for convenience and/or quick prototyping.

## Demo Program

To try out the library, see the 
[demo program](https://github.com/zathras/jovial_svg/tree/main/demo).  It's 
mostly intended to be run on the desktop, though it will run fine on other
platforms.  It lets you cycle through a series of test
images, including several taken from an open-source card game
([Aisleriot](https://wiki.gnome.org/Apps/Aisleriot)).  The demo also lets
you paste a URL to an SVG asset into the program; it then loads and renders
it.

## Supported SVG Profile

SVG profile notes:

  *  SVG paths and transforms are of course supported.
  *  The `use` element is supported (including forward references).
  *  Stroke modifiers like `stroke-linecap`, `stroke-linejoin` and
     `stroke-miterlimit` are supported.
  *  The `stroke-dasharray` and `stroke-dashoffset` attributes are
     supported (cf. Tiny s. 11.4).
  *  Gradients are supported, and additionally support xlink:href attributes 
     to other gradients, and gradientTransform attributes from SVG 1.1.
  *  Text elements are supported.
  *  Embedded images are supported.
  *  As per the Tiny spec s. 6.2, full CSS is not supported.  However, the
     `style=` attribute is supported as a way of specifying presentation
     attributes.
  *  Non-scaling stroke is not supported (not in SVG 1.1; cf. Tiny 11.5)
  *  Constrained transformations are not supported (not in SVG 1.1;
     cf. Tiny 7.7)
  *  `fill-opacity` and `stroke-opacity` are supported, but the object/group
     `opacity` property is not (cf. SVG 1.1 s. 14.5).  It was eliminated
     from SVG Tiny 1.2, probably because it is expensive and complex to
     implement.  However, the `opacity` attribute is treated as a default 
     value for both `fill-opacity` and `stroke-opacity`
     *  Using `opacity` like this works when shapes don't overlap, and
        there are no `use` tags in the affected render tree.  Some SVG authors
        seem to confuse the complex and expensive group opacity feature of 
        the `opacity` attribute with the much simpler `fill-opacity` and 
        `stroke-opacity` drawing attributes; this workaround helps with 
        rendering of such SVG assets.  It generally helps more than
        it hurts.
  *  A DOM and features related to animation are not supported.
  *  Conditional processing (Tiny s. 5.8) is not supported
  *  The `clipPath` SVG element is not supported (cf. SVG 1.1 14.3.5).  It 
     is not defined for SVG Tiny 1.2.  (The more restricted Android Vector
     Drawable `clipPath` is supported for AVD files, however.)
  *  Text restrictions:
      * Embedded fonts are not supported.  However, the font-family attribute
        is used when selecting a font, and fonts can be included in an 
        application that uses this library.  For example, the demo program
        includes the "ROLLERBALL 1975" font.
      * `textArea` is not supported (not in SVG 1.1).
      * `font-variant` (`small-caps`) is not supported.
      * `rotate` is not supported (but normal transformations, including 
         rotation, apply to text elements).
      * Bi-directional text is not supported

## Goals and Package Evolution

This library was originally written because existing alternatives didn't
correctly handle many aspects of SVG.  This made it impossible to re-purpose
existing SVG graphical assets, e.g. from other open-source programs.  
Additionally, runtime performance wasn't so good, perhaps due to the overhead
associated with parsing XML.

It must be said that the SVG specifications are rather large.  SVG 2 notably
added a rich set of features that aren't needed for a graphics interchange
format.  SVG in browsers also supports scripting and animation.  Additionally, 
this family of specifications has always been somewhat squishy about conformance
and profiling -- there's a whole set of resources devoted to tracking which
browsers support which features, and that's with fairly large and well-funded
teams developing browsers over decades.

However, there are a large number of (quite beautiful!) SVG assets for static
images that generally stay within the bounds of SVG 1.1.  SVG Tiny 1.2 is a
reasonable collection of the most important parts of SVG 1.1 - it was intended
as such (though it has since been essentially abandoned).  One of the 
challenges in developing this kind of library is deciding which features are 
essential, and which are gold-plating that are not in wide use.  For this 
library, informed guesses were necessary at some points; SVG Tiny provided
a solid starting point that a group of experts put considerable thought behind.

If you come across an SVG
asset that falls within the scope of this library, but which doesn't render,
please try to narrow down what support would be needed in the library, and 
submit an image that correctly uses that feature in any bug 
report.  Contributions can be considered too -- and the binary format 
has plenty of room for extensibility.

For the binary format, it is a goal to make it so that new versions of the
library continue to read old files.  Old versions of the library do not need
to read new `.si` files, however - the current version will simply fail when 
it detects the new version number.  `.si` files are intended to be bundled 
as application resources alongside the library, and not used as a 
publication format.

