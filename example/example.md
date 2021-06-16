
You can display an SVG file quite simply, letting the widget do all
of the asynchronous work, like this:

```
import 'package:flutter/material.dart';
import 'package:jovial_svg/jovial_svg.dart';

void main() {
  runApp(MinimalSample());
}

///
/// A minimal sample application using `jovial_svg`.  This example lets
/// [ScalableImageWidget] handle the asynchronous loading, which is resonable
/// for a prototype.
///
class MinimalSample extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'SVG Minimal Sample',
        home: ScalableImageWidget.fromSISource(
            si: ScalableImageSource.fromSvgHttpUrl(
                Uri.parse('https://jovial.com/images/jupiter.svg'))));
  }
}
```

Typically resources come from an `AssetBundle`, but they still need to be
loaded asynchronously.  You can pre-load them before building the UI,
which is often a better choice - it saves re-rendering the UI, and avoids
any possibility of a visible flash.  That only takes a little more effort.
To take our example of loading over a network, pre-loading can be done
like this:

```
import 'package:flutter/material.dart';
import 'package:jovial_svg/jovial_svg.dart';

void main() async {
  final si = await ScalableImage.fromSvgHttpUrl(
      Uri.parse('https://jovial.com/images/jupiter.svg'));
  runApp(AssetsPreLoaded(si));
}

///
/// A sample application using `jovial_svg`.  This example shows how to do
/// the asynchronous part before the widget tree is built, so as to avoid
/// changes on the screen.
///
class AssetsPreLoaded extends StatelessWidget {
  final ScalableImage icon;

  AssetsPreLoaded(this.icon);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'SVG Minimal Sample', home: ScalableImageWidget(si: icon));
  }
}
```

Both of these examples are in the `examples` directory.
