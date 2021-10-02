import 'package:flutter/material.dart';
import 'package:jovial_svg/jovial_svg.dart';

void main() {
  runApp(const MyApp());
}

/// A sample application to demonstrate using ScalableImageCache
/// (https://github.com/zathras/jovial_svg/issues/6) and to reproduce
/// race condition issue 7 (https://github.com/zathras/jovial_svg/issues/7).

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CacheDemo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  static final svgs = List.generate(100,
      (index) => Uri.parse('https://jovial.com/images/jupiter.svg?x=$index'));
  // A static cache of the SVG images, so that once they are loaded, they
  // stay loaded.  Another alternative would be to make HomePage stateful,
  // and tie the lifetime of the cache to the state.
  //
  // For this demo, we make it a little smaller than the length of the list,
  // so you can see reloading if you scroll all the way back and forth.
  static final ScalableImageCache svgCache = ScalableImageCache(size: 70);

  const HomePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Issues 6, 7'),
      ),
      body: GridView.builder(
          itemCount: svgs.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5),
          itemBuilder: (context, index) {
            return GridTile(
              child: ScalableImageWidget.fromSISource(
                  cache: svgCache,
                  si: ScalableImageSource.fromSvgHttpUrl(svgs[index])),
            );
          }),
    );
  }
}
