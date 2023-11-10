import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:jovial_svg/jovial_svg.dart';
import 'package:http/http.dart' as http;

///
/// A sample application using the new-ish Flutter `Hero` widget, to
/// stress rebuild/repaint behavior.
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

ScalableImageCache _svgCache = ScalableImageCache(size: 70);

Widget _onLoading(BuildContext context) => Container(color: Colors.green);

Widget _onError(BuildContext context) => Container(color: Colors.red);

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
        title: const Text('Issue 48'),
      ),
      body: GridView.builder(
        itemCount: widget.svgs.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
        ),
        itemBuilder: (context, index) {
          final Uri uri = widget.svgs[index];
          return GridTile(
            child: GestureDetector(
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => NextPage(uri: uri)),
              ),
              child: Hero(
                tag: widget.svgs[index],
                child: ScalableImageWidget.fromSISource(
                  cache: _svgCache,
                  si: ScalableImageSource.fromSvgHttpUrl(widget.svgs[index]),
                  onLoading: _onLoading,
                  onError: _onError,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class NextPage extends StatefulWidget {
  const NextPage({super.key, required this.uri});

  final Uri uri;

  @override
  State<NextPage> createState() => _NextPageState();
}

class _NextPageState extends State<NextPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.uri.toString())),
      body: SizedBox.expand(
        child: Hero(
          tag: widget.uri,
          child: ScalableImageWidget.fromSISource(
            cache: _svgCache,
            si: ScalableImageSource.fromSvgHttpUrl(widget.uri),
            onLoading: _onLoading,
            onError: _onError,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}
