/*
MIT License

Copyright (c) 2022, William Foote

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
 */

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jovial_svg/src/exported.dart';
import 'package:jovial_svg/src/widget.dart';

class TestSource extends ScalableImageSource {
  final String svg;
  final int delay;
  final done = Completer<void>();
  @override
  void Function(String) get warnF => _noWarn;

  TestSource(this.svg, this.delay);

  @override
  Future<ScalableImage> createSI() async {
    await Future<void>.delayed(Duration(milliseconds: delay));
    Timer(Duration(milliseconds: delay ~/ 5), () {
      done.complete(null);
    });
    if (svg == '') {
      throw 'Expected Error';
    }
    return ScalableImage.fromSvgString(svg);
  }

  @override
  bool operator ==(Object other) {
    if (other is! TestSource) {
      return false;
    } else {
      return svg == other.svg && delay == other.delay;
    }
  }

  @override
  int get hashCode {
    return 0x36ee5e21 ^ Object.hash(svg, delay);
  }
}

class TestApp extends StatelessWidget {
  TestApp({super.key});
  static const simpleSVG = '<svg><text>foo</text></svg>';
  static const simpleAVD = '<vector></vector>';
  final si = ScalableImage.fromSvgString(
    simpleSVG,
    compact: true,
  ).modifyCurrentColor(const Color(0xffff0000));
  final testSource = TestSource(simpleSVG, 100);
  final errorSource = TestSource('', 100);

  @override
  Widget build(BuildContext context) {
    final widgets = [
      ScalableImageWidget.fromSISource(
        si: ScalableImageSource.fromSvgHttpUrl(
          Uri.dataFromString(simpleSVG),
          warnF: _noWarn,
        ),
      ),
      ScalableImageWidget.fromSISource(
        si: ScalableImageSource.fromSvgHttpUrl(
          Uri.parse('https://jovial.com/images/jupiter.svg'),
          warnF: _noWarn,
        ),
      ),
      ScalableImageWidget.fromSISource(
        si: ScalableImageSource.fromAvdHttpUrl(
          Uri.dataFromString(simpleAVD),
          warnF: _noWarn,
        ),
      ),
      ScalableImageWidget.fromSISource(
        si: ScalableImageSource.fromSvgHttpUrl(
          Uri.parse('https://jovial.com/images/jupiter.svg'),
          warnF: _noWarn,
        ),
      ),
      ScalableImageWidget.fromSISource(
        si: ScalableImageSource.fromSvg(
          rootBundle,
          '../../demo/assets/svg/svg11_gradient_1.svg',
          warnF: _noWarn,
        ),
      ),
      ScalableImageWidget.fromSISource(
        si: ScalableImageSource.fromSI(
          rootBundle,
          '../../demo/assets/si/svg11_gradient_1.si',
        ),
      ),
      ScalableImageWidget.fromSISource(
        reload: true,
        background: Colors.amberAccent,
        si: ScalableImageSource.fromAvd(
          rootBundle,
          '../../demo/assets/avd/svg11_gradient_1.xml',
          warnF: _noWarn,
        ),
      ),
      ScalableImageWidget.fromSISource(reload: true, si: testSource),
      ScalableImageWidget.fromSISource(reload: true, si: errorSource),
      ScalableImageWidget(si: si),
    ];
    for (final fit in BoxFit.values) {
      widgets.add(
        ScalableImageWidget.fromSISource(
          fit: fit,
          alignment: Alignment.topLeft,
          si: ScalableImageSource.fromSI(
            rootBundle,
            '../../demo/assets/si/svg11_gradient_1.si',
          ),
        ),
      );
    }
    return MaterialApp(
      title: 'SVG Widget Smoke Test',
      home: Column(
        children: widgets
            .map((siw) => SizedBox(width: 10, height: 10, child: siw))
            .toList(),
      ),
    );
  }
}

void testSIWidget() {
  testWidgets('SI Widget', (WidgetTester tester) async {
    final app = TestApp();
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    await app.testSource.done.future;
    await app.errorSource.done.future;
  });
}

void _noWarn(String message) {}
