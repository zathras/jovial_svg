import 'package:flutter/material.dart';
import 'package:jovial_svg/dom.dart';
import 'package:jovial_svg/jovial_svg.dart';

///
/// Small program to show how to handle embedded images with DOM
/// modification, from issue 138
///
void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late SvgDOMManager _domManager;
  ScalableImage? _img;

  @override
  void initState() {
    super.initState();
    _domManager = SvgDOMManager.fromString(
        '''<svg xmlns="http://www.w3.org/2000/svg" width="110" height="60">
      <image x="0" y="0" width="50" height="50"
        href="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADIAAAAyCAIAAACRXR/mAAAAS0lEQVR4nO3OsQEAEADAMPz/Mw9YMjE0F2Tu8aP1OnBXS9QStUQtUUvUErVELVFL1BK1RC1RS9QStUQtUUvUErVELVFL1BK1RC1xAEGqAWOFuDKrAAAAAElFTkSuQmCC"/>
      <circle cx="85" cy="25" r="25" fill="blue"/>
    </svg>
    ''');
    _img = _domManager.build();
  }

  void _handleTap() {
    setState(() {
      _img = _domManager.build();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Embedded image missing',
      debugShowCheckedModeBanner: false,
      home: _img == null
          ? Text("Error loading SVG")
          : GestureDetector(
              onTap: _handleTap,
              child: ScalableImageWidget(
                si: _img!,
              ),
            ),
    );
  }
}
