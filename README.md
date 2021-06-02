# jovial_svg 

Robust rendering of SVG static images, supporting a well-defined profile
of SVG and an efficient binary storage format.  Supported SVG profile
includes the parts of 
[SVG Tiny 1.2](https://www.w3.org/TR/2008/REC-SVGTiny12-20081222/),
that are applicable to static images, plus commonly-used elements from
[SVG 1.1](https://www.w3.org/TR/2011/REC-SVG11-20110816/).
[Android Vector Drawable](https://developer.android.com/guide/topics/graphics/vector-drawable-resources) files
are also supported.  A widget for displaying scalable images is provided.

SVG profile notes:

  *  Unlike Tiny, the "`style=`" attribute is supported as an alternative
     to proper SVG Tiny attributes.  The rest of CSS is not supported,
     however.
  *  The `stroke-dasharray` and `stroke-dashoffset` attributes are
     not supported (cf. Tiny s. 11.4).
  *  Non-scaling stroke is not supported (not in SVG 1.1; cf. Tiny 11.5)
  *  Constrained transformations are not supported (not in SVG 1.1;
     cf. Tiny 7.7)
  *  DOM support and features related to animation are not supported.
  *  Text restrictions:
      * `textArea` is not supported (not in SVG 1.1).
      * `font-variant` (`small-caps`) is not supported
      * `rotate` is not supported (but normal transformations, including rotation apply).
      * Embedded fonts are not supported.
