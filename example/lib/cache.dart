import 'package:flutter/material.dart';
import 'package:jovial_svg/jovial_svg.dart';

///
/// A sample application to demonstrate using ScalableImageCache
/// (https://github.com/zathras/jovial_svg/issues/6).  Providing a
/// cache can be important to avoid image reloading, particularly 
/// for a screen that gets rebuilt frequently.
///
/// A global cache can be simply held in a static data member.  This demo
/// shows a more sophisticated cache that's tied to a [StatefulWidget],
/// so that the cache is GC'd when the screen is no longer being used.
///
void main() {
  runApp(const MyApp());
}


///
/// A random SVG image to show.  The server ignores the parameter, but our
/// code is forced to treat each URL like a different image.
///
final _demoSvgs = List.generate(100,
        (index) => Uri.parse('https://jovial.com/images/jupiter.svg?x=$index'));

///
/// Application class for the sample.
///
class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CacheDemo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: HomePage(_demoSvgs),
    );
  }
}

///
/// A stateful widget that displays a big list of SVG images.  It loads
/// them lazily, and uses a cache to avoid excessive reloading.
///
class HomePage extends StatefulWidget {

  final List<Uri> svgs;

  HomePage(this.svgs, {Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  ScalableImageCache _svgCache = ScalableImageCache(size: 70);
  // A cache of the SVG images, to avoid excessive image reloading.
  // Depending on your application, it might make sense to
  // make a static cache instead.
  //
  // For this demo, we make it a little smaller than the length of the list,
  // so you can see reloading if you scroll all the way back and forth.

  @override
  void didUpdateWidget(HomePage old) {
    super.didUpdateWidget(old);
    if (old.svgs != widget.svgs) {
      // If we get re-parented to a new widget with different svgs,
      // it's reasonable to dump the old cache.  In a real app, we might
      // adapt the size of the cache to what's being displayed.
      _svgCache = ScalableImageCache(size: 70);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Issues 6, 7'),
      ),
      body: GridView.builder(
          itemCount: widget.svgs.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5),
          itemBuilder: (context, index) {
            return GridTile(
              child: ScalableImageWidget.fromSISource(
                  cache: _svgCache,
                  si: ScalableImageSource.fromSvgHttpUrl(widget.svgs[index])),
            );
          }),
    );
  }
}
