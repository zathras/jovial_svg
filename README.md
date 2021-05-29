# scaling_image

Robust rendering of SVG static images, supporting a well-defined profile
of SVG and an efficient binary storage format.  Supported SVG profile
includes the parts of 
[SVG Tiny 1.2](https://www.w3.org/TR/2008/REC-SVGTiny12-20081222/),
plus commonly-used elements from
[SVG 1.1](https://www.w3.org/TR/2011/REC-SVG11-20110816/).
[Android Vector Drawable](https://developer.android.com/guide/topics/graphics/vector-drawable-resources) files
are supported as well.


The AVD format is informally specified
[here](https://developer.android.com/reference/android/graphics/drawable/VectorDrawable),
including an informal mention of [SVG Path Data](https://www.w3.org/TR/SVG/paths.html#TheDProperty).

