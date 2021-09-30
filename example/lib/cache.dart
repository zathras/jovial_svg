import 'package:flutter/material.dart';
import 'package:jovial_svg/jovial_svg.dart';

void main() {
  runApp(MyApp());
}

/// A sample application to demonstrate using SICache
/// (https://github.com/zathras/jovial_svg/issues/6) and to reproduce
/// race condition issue 7 (https://github.com/zathras/jovial_svg/issues/7).

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CacheDemo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  final svgs = List.generate(
      100,
      (index) => Uri.parse(
          'https://raw.githubusercontent.com/feathericons/feather/master/icons/activity.svg?x=$index'));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Issues 6, 7'),
      ),
      body: GridView.builder(
          itemCount: svgs.length,
          gridDelegate:
              SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5),
          itemBuilder: (context, index) {
            return GridTile(
              child: ScalableImageWidget.fromSISource(
                  si: ScalableImageSource.fromSvgHttpUrl(svgs[index])),
            );
          }),
    );
  }
}
