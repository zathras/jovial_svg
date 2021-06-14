/*
Copyright (c) 2021 William Foote

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:

  * Redistributions of source code must retain the above copyright notice,
    this list of conditions and the following disclaimer.
  * Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in the
    documentation and/or other materials provided with the distribution.
  * Neither the name of the copyright holder nor the names of its
    contributors may be used to endorse or promote products derived
    from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER(S) AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.
*/

import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jovial_svg/jovial_svg.dart';
import 'package:jovial_svg/widget.dart';
import 'package:pedantic/pedantic.dart';
import 'package:tuple/tuple.dart';
import 'package:url_launcher/url_launcher.dart';

const _IMAGE_BASE_URL =
    'https://raw.githubusercontent.com/zathras/jovial_svg/main/demo';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final json = await rootBundle.loadString('assets/manifest.json');
  final typeUnsafe = jsonDecode(json) as List<dynamic>;
  final assets = List<Asset>.empty(growable: true);
  for (int i = 0; i < typeUnsafe.length; i++) {
    final name = typeUnsafe[i] as String;
    final svg = 'assets/svg/$name.svg';
    String? avd = 'assets/avd/$name.xml';
    String si = 'assets/si/$name.si';
    // Disable avd and si if they're not in the asset bundle:
    try {
      await rootBundle.load(avd);
    } on FlutterError catch (_) {
      avd = null;
    }
    await rootBundle.load(si);
    // SVG is required to always be there.
    assets.add(Asset(svg: svg, avd: avd, si: si));
  }
  final firstSI = await assets[0].forType(AssetType.si, rootBundle);
  runApp(Demo(assets, firstSI));
}

class Demo extends StatelessWidget {
  final List<Asset> assets;
  final ScalableImage firstSI;

  Demo(this.assets, this.firstSI);
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jovial SVG Demo',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple, // Not quite Sun purple, but it'll do
      ),
      home: DemoScreen(
          title: 'Jovial SVG Demo',
          bundle: rootBundle,
          // Normally, DefaultAssetBundle.of(context), but since we get
          // the manifest from rootBundle, it makes sense to just hard-wire
          // that in.
          assets: assets,
          firstSI: firstSI),
    );
  }
}

class DemoScreen extends StatefulWidget {
  DemoScreen(
      {Key? key,
      required this.title,
      required this.bundle,
      required this.assets,
      required this.firstSI})
      : super(key: key);

  final String title;
  final List<Asset> assets;
  final ScalableImage firstSI;
  final AssetBundle bundle;

  @override
  _DemoScreenState createState() => _DemoScreenState(firstSI);
}

class _DemoScreenState extends State<DemoScreen> {
  ScalableImage? si;
  String? errorMessage;
  int assetIndex = 0;
  var assetType = AssetType.si;
  double _scale = 0;
  bool _fitToScreen = false;
  Rect? _originalViewport;
  double get _multiplier => pow(2.0, _scale).toDouble();
  final _siWidgetKey = GlobalKey<State<DemoScreen>>();

  _DemoScreenState(this.si);

  List<Asset> get assets => widget.assets;

  void _launch() {
    final String name = assets[assetIndex].svg;
    launch('$_IMAGE_BASE_URL/$name', forceWebView: true);
  }

  @override
  Widget build(BuildContext context) {
    final asset = assets[assetIndex];
    return Scaffold(
        appBar: AppBar(
          leading: ScalableImageWidget.fromSISource(
              si: ScalableImageSource.fromSI(
            DefaultAssetBundle.of(context),
            'assets/other/jupiter.si',
            currentColor: Colors.yellow.shade300,
          )),
          title: Text(widget.title +
              ' - ${assets[assetIndex].fileName(assetType)?.substring(7)}'),
        ),
        body: Column(children: [
          SizedBox(height: 5),
          Center(
            child: Wrap(
                spacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(width: 0),
                  SizedBox(
                      width: 130,
                      child: Row(children: [
                        ElevatedButton(
                          onPressed: (assetIndex > 0)
                              ? () {
                                  assetIndex--;
                                  _setType(AssetType.si);
                                }
                              : null,
                          child: Icon(Icons.arrow_left),
                        ),
                        Spacer(),
                        ElevatedButton(
                          onPressed: (assetIndex + 1 < assets.length)
                              ? () {
                                  assetIndex++;
                                  _setType(AssetType.si);
                                }
                              : null,
                          child: Icon(Icons.arrow_right),
                        ),
                      ])),
                  SizedBox(width: 15),
                  SizedBox(
                      width: 260,
                      child: Row(children: [
                        Text('SI',
                            style: (asset.si == null)
                                ? const TextStyle(color: Colors.grey)
                                : const TextStyle()),
                        Radio(
                            value: AssetType.si,
                            groupValue: assetType,
                            onChanged: asset.si == null ? null : _setType),
                        Spacer(),
                        Text('Compact'),
                        Radio(
                            value: AssetType.compact,
                            groupValue: assetType,
                            onChanged: _setType),
                        Spacer(),
                        Text('SVG'),
                        Radio(
                            value: AssetType.svg,
                            groupValue: assetType,
                            onChanged: _setType),
                        Spacer(),
                        Text('AVD',
                            style: (asset.avd == null)
                                ? const TextStyle(color: Colors.grey)
                                : const TextStyle()),
                        Radio(
                            value: AssetType.avd,
                            groupValue: assetType,
                            onChanged: asset.avd == null ? null : _setType),
                      ])),
                  SizedBox(width: 10),
                  SizedBox(
                      width: 300,
                      child: Row(children: [
                        Slider(
                          min: -8,
                          max: 8,
                          value: _fitToScreen ? 0 : _scale,
                          onChanged: _fitToScreen
                              ? null
                              : (double v) {
                                  setState(() {
                                    _scale = v;
                                  });
                                },
                        ),
                        _fitToScreen
                            ? Text('')
                            : Text(
                                'Scale:  ${_multiplier.toStringAsFixed(3)}  ',
                                textAlign: TextAlign.left),
                      ])),
                  SizedBox(
                      width: 140,
                      child: Row(children: [
                        Text('Fit to screen:  '),
                        Checkbox(
                            value: _fitToScreen,
                            onChanged: (_) => setState(() {
                                  _fitToScreen = !_fitToScreen;
                                })),
                      ])),
                  SizedBox(
                      width: 120,
                      child: Row(children: [
                        Text('Zoom/Prune'),
                        Checkbox(
                            value: _originalViewport != null,
                            onChanged: (_) => _changeZoomPrune())
                      ])),
                  SizedBox(width: 30),
                  ElevatedButton(
                      onPressed: () {
                        _launch();
                      },
                      child: Text('Browser')),
                  SizedBox(width: 30),
                ]),
          ),
          SizedBox(height: 10),
          Expanded(
              child: _maybeScrolling(si == null
                  ? Text(errorMessage ?? '???')
                  : ScalableImageWidget(
                      si: si!,
                      key: _siWidgetKey,
                      alignment: Alignment.center,
                      scale: _fitToScreen ? double.infinity : _multiplier)))
        ]));
  }

  void _setType(AssetType? v) {
    if (v == null) {
      return;
    }
    unawaited(() async {
      String? err;
      ScalableImage? newSI;
      try {
        final sw = Stopwatch()..start();
        newSI = await assets[assetIndex].forType(v, widget.bundle);
        final time = sw.elapsedMilliseconds;
        sw.stop();
        print('Loaded ${assets[assetIndex].fileName(v)} in $time ms.');
      } catch (e, st) {
        err = e.toString();
        print(e);
        print(st);
      }
      setState(() {
        assetType = v;
        si = newSI;
        _originalViewport = null;
        errorMessage = err;
      });
    }());
  }

  Widget _maybeScrolling(Widget scrollee) {
    if (_fitToScreen) {
      return Container(padding: EdgeInsets.all(5), child: scrollee);
    } else {
      // The ValueKey works around a bug with InteractiveViewer, where it
      // doesn't ensure that content is re-scrolled to make it visible when
      // its child's size decreases.  The key forces new InteractiveViewer state
      // when the scale changes, so any scrolling is reset.
      //
      // It's astonishingly hard to get two directional scrolling that works
      // well in Flutter.  Putting a SingleChildScrollView inside another
      // SingleChildScrollView almost works, but the UX is horrible, because
      // it only lets you scroll in one direction at a time (at least on
      // MacOS in May 2021).  InteractiveViewer scrolls OK, but it doesn't
      // give scrollbars, and it has this bug with changing child size.
      //
      // I'm not letting InteractiveViewer control the zoom, because I suspect
      // pinch-zoom doesn't work on desktop, and if it does, I don't know what
      // the gesture would be.  This demo is primarily for desktop; if it
      // weren't I might make it notice if it's on iOS/Android, and take
      // over zooming there.
      //
      // cf. https://github.com/flutter/flutter/issues/83628
      return Container(
          padding: EdgeInsets.all(5),
          child: InteractiveViewer(
              key: ValueKey(Tuple2(_scale, si)),
              constrained: false,
              scaleEnabled: false,
              panEnabled: true,
              child: scrollee));
    }
  }

  void _changeZoomPrune() => setState(() {
        if (_originalViewport != null) {
          si = si!.withNewViewport(_originalViewport!);
          _originalViewport = null;
        } else {
          Rect r = _originalViewport = si!.viewport;
          // Card height/width:
          final ch = r.height / 5;
          final cw = r.width / 13;
          si = si!.withNewViewport(Rect.fromLTWH(9 * cw, 2 * ch, 3 * cw, ch),
              prune: true);
        }
      });
}

enum AssetType { si, compact, svg, avd }

class Asset {
  final String svg;
  final String? avd;
  final String si;

  Asset({required this.svg, required this.avd, required this.si});

  Future<ScalableImage> forType(AssetType t, AssetBundle b) {
    switch (t) {
      case AssetType.svg:
        return ScalableImage.fromSvgAsset(b, svg);
      case AssetType.compact:
        return ScalableImage.fromSIAsset(b, si, compact: true);
      case AssetType.avd:
        return ScalableImage.fromAvdAsset(b, avd!);
      case AssetType.si:
        return ScalableImage.fromSIAsset(b, si);
    }
  }

  String? fileName(AssetType t) {
    switch (t) {
      case AssetType.svg:
        return svg;
      case AssetType.avd:
        return avd;
      case AssetType.compact:
      case AssetType.si:
        return si;
    }
  }
}
