import 'package:flutter/material.dart';

import 'package:jovial_svg/jovial_svg.dart';

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
/// A sample application to show the default behavior, where the cache size
/// is zero.  Inspired by
/// (https://github.com/zathras/jovial_svg/issues/6).  See also the notes
/// about the default cache at [ScalableImageWidget.fromSISource].
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
/// them lazily, but ends up doing a lot of reloading, since the default
/// cache size is zero.
///
class HomePage extends StatefulWidget {
  final List<Uri> svgs;

  const HomePage(this.svgs, {Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void didUpdateWidget(HomePage old) {
    super.didUpdateWidget(old);
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
                  si: ScalableImageSource.fromSvgHttpUrl(widget.svgs[index])),
            );
          }),
    );
  }
}
