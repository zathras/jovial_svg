import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:jovial_svg/jovial_svg.dart';
import 'package:http/http.dart' as http;

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
void main() async {
  runApp(MyApp(await getSvgs()));
}

///
/// Some SVG images to show.
///
Future<List<Uri>> getSvgs() async {
  final url = Uri.parse('https://pastebin.com/raw/iLn5UqZM');
  final response = await http.get(url);
  final svgs = (jsonDecode(response.body) as List).cast<String>();
  final r = svgs.map((s) => Uri.parse(s)).toList(growable: true);
  const usesUtf8 =
      'https://openseauserdata.com/files/0817d1e5f53e504601a85e900cae85d1.svg';
  r.add(Uri.parse(usesUtf8));
  return r;
  // If the external assets, above, ever go away, we can do this:
  // return List.generate(100,
  //      (i) => Uri.parse('https://jovial.com/images/jupiter.svg?x=$i'));
  // The parameter is ignored by the server, but it makes the URLs distinct.
}

///
/// Application class for the sample.
///
class MyApp extends StatelessWidget {
  final List<Uri> svgs;

  const MyApp(this.svgs, {super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CacheDemo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: HomePage(svgs),
    );
  }
}

///
/// A stateful widget that displays a big list of SVG images.  It loads
/// them lazily, and uses a cache to avoid excessive reloading.
///
class HomePage extends StatefulWidget {
  final List<Uri> svgs;

  const HomePage(this.svgs, {super.key});

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
                  scale: 1000,
                  si: ScalableImageSource.fromSvgHttpUrl(widget.svgs[index]),
                  onLoading: _onLoading,
                  onLoaded: _onLoaded,
                  onError: _onError,
                  switcher: _switcher),
            );
          }),
    );
  }

  Widget _onLoading(BuildContext context) => Container(
      key: const ValueKey(1), color: Colors.green, width: 500, height: 500);
  Widget _onLoaded(BuildContext context, ScalableImage si) =>
      ScalableImageWidget(si: si, scale: 1000);
  Widget _onError(BuildContext context) =>
      Container(key: const ValueKey(2), color: Colors.red);
  Widget _switcher(BuildContext context, Widget child) => AnimatedSwitcher(
      duration: const Duration(milliseconds: 250), child: child);
}
