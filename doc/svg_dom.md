
Support for modifying elements of an SVG asset programmatically,
using a document object model.  An SVG asset can be animated
by repeatedly modifying the DOM representation, and displaying
the new `ScalableImage` created from it after each frame.  This
is similar to what some web pages do with JavaScript code
modifying an SVG.

Sample Usage:
```
final String svgSrc = 
    '<svg><circle id="foo" cx="5" cy="5" r="5" fill="green"/></svg>';
final svg = SvgDOMManager.fromString(svgSrc);
final node = svg.dom.idLookup['foo'] as SvgEllipse;
node.paint.fillColor = Colors.blue;
final ScalableImage si = svg.build();
   ... display si, perhaps in a ScalableImageWidget ...
```

A full sample can be found in the GitHub repository in
`example/lib/animation.dart`.

Here's a UML diagram overview of the DOM class structure:
<img src="https://raw.githubusercontent.com/zathras/jovial_svg/main/doc/uml/svg_dom.svg" />

