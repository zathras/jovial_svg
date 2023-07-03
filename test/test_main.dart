/*
MIT License

Copyright (c) 2021-2022, William Foote

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

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jovial_misc/io_utils.dart';
import 'package:jovial_svg/src/affine.dart';
import 'package:jovial_svg/src/avd_parser.dart';
import 'package:jovial_svg/src/common.dart';
import 'package:jovial_svg/src/common_noui.dart';
import 'package:jovial_svg/src/compact.dart';
import 'package:jovial_svg/src/compact_noui.dart';
import 'package:jovial_svg/src/dag.dart';
import 'package:jovial_svg/src/exported.dart';
import 'package:jovial_svg/src/svg_graph.dart';
import 'package:jovial_svg/src/svg_parser.dart';
import 'package:jovial_svg/src/widget.dart';

import '../bin/svg_to_si.dart' as svg_to_si;
import '../bin/avd_to_si.dart' as avd_to_si;
import 'test_widget.dart';

void _noWarn(String s) {}

///
/// Test that reading the SVG and the SI results in the same root group,
/// and that they render the same.
///
Future<void> _testSvgSiSame(Directory svgDir, Directory? outputDir) async {
  for (FileSystemEntity ent in svgDir.listSync()
    ..sort((a, b) => a.path.compareTo(b.path))) {
    final name = ent.uri.pathSegments.last;
    final noExt = name.substring(0, name.lastIndexOf('.'));
    if (ent is File && noExt != 'README' && !name.endsWith('.swp')) {
      final fromSvg =
          ScalableImage.fromSvgString(await ent.readAsString(), warnF: _noWarn);
      final fromSvgC = ScalableImage.fromSvgString(await ent.readAsString(),
          warnF: _noWarn, compact: true, bigFloats: true);
      final b = SICompactBuilderNoUI(bigFloats: true, warn: _noWarn);
      StringSvgParser(await ent.readAsString(), b, warn: _noWarn).parse();
      final cs = ByteSink();
      final dos = DataOutputSink(cs);
      b.si.writeToFile(dos);
      dos.close();
      final fromSi = ScalableImage.fromSIBytes(cs.toList(), compact: false);
      final svgB = await renderToBytes(fromSvg, format: ImageByteFormat.png);
      final svgcB = await renderToBytes(fromSvgC, format: ImageByteFormat.png);
      final siB = await renderToBytes(fromSi, format: ImageByteFormat.png);
      void fail(Uint8List si, Uint8List sv, bool compact) {
        if (outputDir != null) {
          final svgOut = File('${outputDir.path}/svg.png');
          final siOut = File('${outputDir.path}/si.png');
          print('Writing debug images for compact=$compact, $ent:');
          print('    $svgOut');
          print('    $siOut');
          outputDir.createSync(recursive: true);
          svgOut.writeAsBytesSync(sv);
          siOut.writeAsBytesSync(si);
        }
      }

      try {
        (fromSvg as ScalableImageDag)
            .privateAssertIsEquivalent(fromSi as ScalableImageDag);
        expect(siB, svgB);
      } catch (failure) {
        fail(siB, svgB, false);
        rethrow;
      }
      try {
        _checkDrawingSame(fromSvg, fromSvgC, '$ent differs');
        expect(siB, svgcB);
      } catch (failure) {
        fail(svgB, svgcB, true);
        rethrow;
      }
    }
  }
}

Future<Uint8List> renderToBytes(ScalableImage si,
    {required ImageByteFormat format, Size? scaleTo}) async {
  await si.prepareImages();
  final vpSize = si.viewport;
  final recorder = PictureRecorder();
  final Canvas c = Canvas(recorder);
  if (scaleTo != null) {
    c.scale(scaleTo.width / vpSize.width, scaleTo.height / vpSize.height);
  }
  si.paint(c);
  expect(1, c.getSaveCount());
  si.unprepareImages();
  final size = scaleTo ?? Size(vpSize.width, vpSize.height);
  final Picture pict = recorder.endRecording();
  final Image rendered =
      await pict.toImage(size.width.round(), size.height.round());
  final ByteData? bd = await rendered.toByteData(format: format);
  final r = Uint8List.fromList(bd!.buffer.asUint8List());
  pict.dispose();
  rendered.dispose();
  return r;
}

///
/// Test against reference images.
/// Note that the Flutter test framework uses the "Ahem" font, which renders
/// everything as a box.  Cf.
/// https://github.com/flutter/flutter/issues/28729
///
Future<void> _testReference(
    String description,
    Directory inputDir,
    Directory referenceDir,
    Directory? outputDir,
    Future<ScalableImage> Function(File f) producer,
    {Directory? overrideReferenceDir,
    final Size? scaleTo}) async {
  print('Running test:  $description');
  for (FileSystemEntity ent in inputDir.listSync()) {
    final name = ent.uri.pathSegments.last;
    final noExt = name.substring(0, name.lastIndexOf('.'));
    if (ent is File && noExt != 'README' && !noExt.startsWith('.')) {
      final ScalableImage si;
      try {
        si = await producer(ent);
      } catch (failed) {
        print('=>  Failed parsing $ent');
        rethrow;
      }

      File refName = File('${referenceDir.path}/$noExt.png');
      if (overrideReferenceDir != null) {
        final o = File('${overrideReferenceDir.path}/$noExt.png');
        if (o.existsSync()) {
          refName = o;
        }
      }
      await checkRendered(
          si: si,
          refName: refName,
          outputDir: outputDir,
          outNoExt: noExt,
          description: '$description: $ent and',
          scaleTo: scaleTo);
    }
  }
}

Future<void> checkRendered(
    {required ScalableImage si,
    required File refName,
    Directory? outputDir,
    required String outNoExt,
    required String description,
    Size? scaleTo}) async {
  final Uint8List renderedBytes = await renderToBytes(si,
      scaleTo: scaleTo, format: ImageByteFormat.rawRgba);
  try {
    final codec = await instantiateImageCodec(refName.readAsBytesSync());
    final Image im = (await codec.getNextFrame()).image;
    final reference = await im.toByteData(format: ImageByteFormat.rawRgba);
    expect(renderedBytes, reference!.buffer.asUint8List(),
        reason: '$description $refName differ');
    codec.dispose();
    im.dispose();
  } catch (failed) {
    if (outputDir != null) {
      final outName = File('${outputDir.path}/$outNoExt.png');
      print('Writing rendered result to $outName');
      outputDir.createSync(recursive: true);
      outName.writeAsBytesSync(await renderToBytes(si,
          scaleTo: scaleTo, format: ImageByteFormat.png));
    }
    rethrow;
  }
}

class CanvasRecorder implements Canvas {
  int _saveCount = 1;
  final records = List<Object>.empty(growable: true);

  void record(Object o) {
    records.add(o);
  }

  @override
  void clipPath(Path path, {bool doAntiAlias = true}) {
    record('clipPath');
  }

  @override
  void clipRRect(RRect rrect, {bool doAntiAlias = true}) {
    record('clipRRect');
  }

  @override
  void clipRect(Rect rect,
      {ClipOp clipOp = ClipOp.intersect, bool doAntiAlias = true}) {
    record('clipRect $rect $clipOp $doAntiAlias');
  }

  @override
  void drawArc(Rect rect, double startAngle, double sweepAngle, bool useCenter,
      Paint paint) {
    record('drawArc $rect $startAngle $sweepAngle $useCenter $paint');
  }

  @override
  void drawAtlas(Image atlas, List<RSTransform> transforms, List<Rect> rects,
      List<Color>? colors, BlendMode? blendMode, Rect? cullRect, Paint paint) {
    record('drawAtlas');
  }

  @override
  void drawCircle(Offset c, double radius, Paint paint) {
    record('drawCircle $radius $paint');
  }

  @override
  void drawColor(Color color, BlendMode blendMode) {
    record('drawColor $blendMode');
  }

  @override
  void drawDRRect(RRect outer, RRect inner, Paint paint) {
    record('drawDRRect $outer $inner $paint');
  }

  @override
  void drawImage(Image image, Offset offset, Paint paint) {
    record('drawImage $offset $paint');
  }

  @override
  void drawImageNine(Image image, Rect center, Rect dst, Paint paint) {
    record('drawImageNine');
  }

  @override
  void drawImageRect(Image image, Rect src, Rect dst, Paint paint) {
    record('drawImageRect $src $dst $paint');
  }

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    record('drawLine $p1 $p2 $paint');
  }

  @override
  void drawOval(Rect rect, Paint paint) {
    record('drawOval $rect $paint');
  }

  @override
  void drawPaint(Paint paint) {
    record('drawPaint $paint');
  }

  @override
  void drawParagraph(Paragraph paragraph, Offset offset) {
    record('drawParagraph $offset');
    record(paragraph.longestLine);
  }

  @override
  void drawPath(Path path, Paint paint) {
    record('drawPath $paint');
  }

  @override
  void drawPicture(Picture picture) {
    record('drawPicture');
  }

  @override
  void drawPoints(PointMode pointMode, List<Offset> points, Paint paint) {
    record('drawPoints $points $paint');
  }

  @override
  void drawRRect(RRect rrect, Paint paint) {
    record('drawRRect $rrect $paint');
  }

  @override
  void drawRawAtlas(Image atlas, Float32List rstTransforms, Float32List rects,
      Int32List? colors, BlendMode? blendMode, Rect? cullRect, Paint paint) {
    record('drawRawAtlas');
  }

  @override
  void drawRawPoints(PointMode pointMode, Float32List points, Paint paint) {
    record('drawRawPoints');
  }

  @override
  void drawRect(Rect rect, Paint paint) {
    record('drawRect $rect $paint');
  }

  @override
  void drawShadow(
      Path path, Color color, double elevation, bool transparentOccluder) {
    record('drawShadow');
  }

  @override
  void drawVertices(Vertices vertices, BlendMode blendMode, Paint paint) {
    record('drawVertices $vertices $blendMode $paint');
  }

  @override
  int getSaveCount() {
    return _saveCount;
  }

  @override
  void restore() {
    record('restore');
    _saveCount--;
  }

  @override
  void restoreToCount(int count) {
    while (_saveCount > 1 && _saveCount > count) {
      restore();
    }
  }

  @override
  void rotate(double radians) {
    record('rotate $radians');
  }

  @override
  void save() {
    record('save');
    _saveCount++;
  }

  @override
  void saveLayer(Rect? bounds, Paint paint) {
    record('saveLayer $bounds $paint');
    _saveCount++;
  }

  @override
  void scale(double sx, [double? sy]) {
    record('scale $sx $sy');
  }

  @override
  void skew(double sx, double sy) {
    record('skew $sx $sy');
  }

  @override
  void transform(Float64List matrix4) {
    record('transform $matrix4');
  }

  @override
  void translate(double dx, double dy) {
    record('translate $dx $dy');
  }

  @override
  Rect getDestinationClipBounds() {
    throw UnimplementedError();
  }

  @override
  Rect getLocalClipBounds() {
    throw UnimplementedError();
  }

  @override
  Float64List getTransform() {
    throw UnimplementedError();
  }
}

void _createSI() {
  List<String> listFiles(String type, String extension) {
    final List<String> r = [];
    for (final f in Directory('demo/assets/$type').listSync()) {
      final p = f.path;
      if (p.endsWith('.$extension')) {
        r.add(p);
      }
    }
    return r;
  }

  Directory tmp = Directory('/tmp').createTempSync();
  try {
    final svgFiles = listFiles('svg', 'svg');
    svg_to_si.SvgToSI().main(['-q', '-o', tmp.absolute.path, ...svgFiles]);
    final avdFiles = listFiles('avd', 'xml');
    avd_to_si.AvdToSI().main(['-q', '-o', tmp.absolute.path, ...avdFiles]);
  } finally {
    tmp.deleteSync(recursive: true);
  }
}

class TestSource extends ScalableImageSource {
  static final _rand = Random(42);
  final _si = Future.value(ScalableImageDag.forTesting(
      width: 1,
      height: 1,
      images: const [],
      tintMode: BlendMode.src,
      viewport: Rect.zero,
      tintColor: const Color(0x00000000)));
  final int id = _rand.nextInt(400);
  final int badHash = 0; // _rand.nextInt(2);   // to try to get failure

  @override
  Future<ScalableImage> get si => _si;

  @override
  int get hashCode => id + badHash;

  @override
  bool operator ==(Object other) => (other is TestSource) && id == other.id;

  @override
  String toString() => 'TestSrc(id=$id, badHash=$badHash)';
}

void _cacheTest() {
  final cache = ScalableImageCache(size: 120);
  final referenced = <ScalableImageSource>[];
  for (int i = 0; i < 80; i++) {
    final s = TestSource();
    referenced.add(s);
    cache.addReferenceV2(s);
  }
  for (int i = 0; i < 100000; i++) {
    final v = referenced[i % referenced.length];
    cache.removeReference(v);
    final s = TestSource();
    referenced[i % referenced.length] = s;
    if (i % 3500 == 0) {
      cache.forceReload(s);
    }
    cache.addReferenceV2(s);
    if (i % 2000 == 0) {
      cache.size = cache.size + 7;
      cache.forceReload(s);
    }
  }
}

Future<void> _tint() async {
  for (final compact in [true, false]) {
    final orig = ScalableImage.fromSIBytes(
            File('demo/assets/si/tiny_07_12_bbox01.si').readAsBytesSync(),
            compact: compact,
            currentColor: const Color(0x12345642))
        .withNewViewport(const Rect.fromLTWH(50, 0, 100, 120));
    const String dirName = String.fromEnvironment('jovial_svg.output');
    final outputDir = (dirName == '') ? null : Directory(dirName);
    for (final mode in BlendMode.values) {
      final t = orig.modifyTint(
          newTintMode: mode, newTintColor: const Color(0x7f7f7f00));
      await checkRendered(
          si: t,
          refName: File('test/reference_images/blend/$mode.png'),
          outputDir: outputDir,
          outNoExt: mode.toString(),
          description: 'blend mode $mode compact $compact');
      if (compact) {
        final dag = t.toDag();
        expect(dag.currentColor, const Color(0x12345642));
        await checkRendered(
            si: dag,
            refName: File('test/reference_images/blend/$mode.png'),
            outputDir: outputDir,
            outNoExt: mode.toString(),
            description: 'blend mode $mode compact to dag');
        final cs = ByteSink();
        final dos = DataOutputSink(cs);
        (t as ScalableImageCompact).writeToFile(dos);
        dos.close();
        final si2 = ScalableImage.fromSIBytes(t.toSIBytes(), compact: compact);
        expect(si2.currentColor, const Color(0x12345642));
        await checkRendered(
            si: si2,
            refName: File('test/reference_images/blend/$mode.png'),
            outputDir: outputDir,
            outNoExt: mode.toString(),
            description: 'blend mode $mode compact to si2');
      }
    }
  }
}

Future<void> _miscCoverage() async {
  void expectException(void Function() f) {
    try {
      f();
      expect(true, false);
    } catch (f) {
      expect(true, true); // ya happy, lint?
    }
  }

  Future<void> expectExceptionAsync(Future Function() f) async {
    try {
      await f();
      expect(true, false);
    } catch (_) {
      expect(true, true); // ya happy, lint?
    }
  }

  //
  // Dart's code coverage is pretty immature.  To clean up some of the visual
  // clutter, we call unreachable APIs, debugging APIs, etc.
  //
  for (final f in svgGraphUnreachablePrivate) {
    try {
      f();
    } catch (_) {}
  }
  expect(
      false,
      SvgPoly('', true, [const Point(0, 0)]) ==
          SvgPoly('', true, [const Point(0, 1)]));
  {
    final rc =
        RenderContext.root(ScalableImage.blank(), const Color(0xffffffff));
    final g = SIGroup(const [], 0, rc, SIBlendMode.darken);
    final m = SIMasked([g, g], rc, null, true);
    expectException(() => m.privateAssertIsEquivalent(g));
    expectException(() => g.privateAssertIsEquivalent(m));
  }
  Style('').tagName;
  SvgText((_) {}).textAttributes = SvgTextAttributes.empty();
  expect(true,
      SvgTextAttributes.empty().hashCode == SvgTextAttributes.empty().hashCode);
  ScalableImage.blank().toDag().modifyCurrentColor(const Color(0xff000000));
  final something = ScalableImage.fromSvgString(
      '<svg><path d="M 1 2 q 3.5 -7 7 0"></svg>',
      warnF: _noWarn) as ScalableImageDag;
  something.debugSizeMessage();
  final compact = ScalableImage.fromSvgString(
      '<svg><path d="M 1 2 q 3.5 -7 7 0"></svg>',
      compact: true,
      warnF: _noWarn);
  compact.debugSizeMessage();
  SvgPaint.empty().hashCode;
  expect(false,
      SvgPaint.empty() == (SvgPaint.empty()..strokeDashArray = const [1.1]));
  SvgPaint.empty().userSpace();
  expectException(() => SvgGradientStop(
      0,
      SvgLinearGradientColor(
          x1: null,
          y1: null,
          x2: null,
          y2: null,
          objectBoundingBox: null,
          transform: null,
          spreadMethod: null),
      0));
  await expectExceptionAsync(() async => await ScalableImage.fromAvdStream(
      Stream.value('<error/>'),
      warnF: _noWarn));
  await ScalableImage.fromSvgStream(Stream.value('<svg></svg>'),
      warnF: _noWarn);
  await ScalableImage.fromAvdStream(Stream.value('<vector></vector>'),
      warnF: _noWarn);
  await ScalableImage.fromSvgStream(Stream.value('<svg></svg>'),
      compact: true, warnF: _noWarn);
  await ScalableImage.fromAvdStream(Stream.value('<vector></vector>'),
      compact: true, warnF: _noWarn);
  await ScalableImage.fromAvdAsset(
      rootBundle, '../../demo/assets/avd/svg11_gradient_1.xml',
      warnF: _noWarn);
  await ScalableImage.fromSvgAsset(
      rootBundle, '../../demo/assets/svg/svg11_gradient_1.svg',
      warnF: _noWarn);
  await ScalableImage.fromSIAsset(
      rootBundle, '../../demo/assets/si/svg11_gradient_1.si');

  //
  // Some real tests, of things like error conditions.
  //
  {
    final compactR = CanvasRecorder();
    compact.paint(compactR);
    final compactR2 = CanvasRecorder();
    ScalableImage.fromSIBytes(compact.toSIBytes()).paint(compactR2);
    expect(compactR.records, compactR2.records);
    final d =
        SIImageData(x: 1, y: 2, width: 3, height: 4, encoded: Uint8List(1));
    expect(SIImage(d).data, d);
  }

  // Test errors
  ScalableImage.fromSvgString('<svg><path d="error"></svg>', warnF: _noWarn);
  ScalableImage.fromSvgString('<svg/>', warnF: _noWarn);
  ScalableImage.fromSvgString(
      '<svg><g /><mask /><text /><symbol /><clipPath /><style />',
      warnF: _noWarn);
  // objectBoundingBox not supported on mask:
  ScalableImage.fromSvgString(
      '<svg><mask x="1" y="1" width="10" height="10"></mask></svg>',
      warnF: _noWarn);
  ScalableImage.fromSvgString('<svg><polygon points="1, 2 foo"/></svg>',
      warnF: _noWarn);
  ScalableImage.fromSvgString('<svg><polygon points="1, 2 3"/></svg>',
      warnF: _noWarn);
  ScalableImage.fromSvgString('<svg><image /></svg>', warnF: _noWarn);
  expectException(
      () => ScalableImage.fromSvgString('<svg><svg>', warnF: _noWarn));
  ScalableImage.fromSvgString('<svg><defs/></svg>', warnF: _noWarn);
  expectException(() => ScalableImage.fromAvdString('', warnF: _noWarn));
  expectException(
      () => ScalableImage.fromAvdString('', warnF: _noWarn, compact: true));
  expectException(() =>
      ScalableImage.fromSvgString('<svg><tspan /></svg>', warnF: _noWarn));
  expectException(
      () => ScalableImage.fromSvgString('<defs></defs>', warnF: _noWarn));
  expectException(() => ScalableImageDag.blank().toSIBytes());
  expectException(
      () => something.privateAssertIsEquivalent(ScalableImageDag.blank()));
  expectException(() => ScalableImage.fromSvgString('', warnF: _noWarn));
  expectException(
      () => ScalableImage.fromSvgString('<svg><stop /></svg>', warnF: _noWarn));
  expectException(() => something.privateAssertIsEquivalent(something
      .modifyCurrentColor(const Color(0x7f7f7f7f)) as ScalableImageDag));
  expectException(() {
    final m = CMap<int>()..toList();
    m[3];
  });
  {
    final ma = MutableAffine().mutableCopy();
    ma.toString();
    expectException(() => ma.get(999, 0));
    expectException(() => ma.get(0, 999));
  }
}

void _checkDrawingSame(ScalableImage a, ScalableImage b, String reason) {
  final ar = CanvasRecorder();
  a.paint(ar);
  final br = CanvasRecorder();
  b.paint(br);
  expect(ar.records, br.records, reason: reason);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('tint', _tint);
  test('Misc. coverage tests', _miscCoverage);
  test('compact drawing order', () async {
    final inputDir = Directory('demo/assets/si');
    for (final ent in inputDir.listSync()) {
      final name = ent.uri.pathSegments.last;
      final noExt = name.substring(0, name.lastIndexOf('.'));
      if (ent is File && noExt != 'README') {
        final oRegular = ScalableImage.fromSIBytes(await ent.readAsBytes());
        final oCompact =
            ScalableImage.fromSIBytes(await ent.readAsBytes(), compact: true);
        var regular = oRegular;
        var compact = oCompact;
        for (int i = 0; i < 3; i++) {
          _checkDrawingSame(regular, compact, '$ent differs');
          // Do a quick smoke test of zoom/prune
          final vp = regular.viewport;
          final nvp = Rect.fromLTWH(vp.left + vp.width * .4,
              vp.top + vp.height * .4, vp.width * .2, vp.height * .2);
          regular = oRegular.withNewViewport(nvp, prune: i == 2);
          compact = oCompact.withNewViewport(nvp, prune: i == 2);
        }
      }
    }
  });

  test('Reference Images', () async {
    const String dirName = String.fromEnvironment('jovial_svg.output');
    final outputDir = (dirName == '') ? null : Directory(dirName);
    Directory? getDir(Directory? d, String name) =>
        d == null ? null : Directory('${d.path}/$name');
    final referenceDir = Directory('test/reference_images');
    for (final inputDir in [
      Directory('test/old_avd_tests'),
      Directory('test/more_test_images'),
      Directory('demo/assets')
    ]) {
      print('Running test:  SVG and SI are same');
      await _testSvgSiSame(
          getDir(inputDir, 'svg')!, getDir(outputDir, 'svg_si_same'));
      await _testReference(
          'SVG source',
          getDir(inputDir, 'svg')!,
          getDir(referenceDir, 'svg')!,
          getDir(outputDir, 'svg'),
          (File f) async => ScalableImage.fromSvgString(await f.readAsString(),
              warnF: _noWarn));
      await _testReference(
          'SVG source, compact',
          getDir(inputDir, 'svg')!,
          getDir(referenceDir, 'svg')!,
          getDir(outputDir, 'svg'),
          (File f) async => ScalableImage.fromSvgString(await f.readAsString(),
              warnF: _noWarn, bigFloats: true, compact: true));

      // Make sure the latest .si format produces identical results
      for (final compact in [false, true]) {
        await _testReference(
            'SVG => .si',
            getDir(inputDir, 'svg')!,
            getDir(referenceDir, 'svg')!,
            getDir(outputDir, 'svg'), (File f) async {
          final b = SICompactBuilderNoUI(bigFloats: true, warn: _noWarn);
          StringSvgParser(await f.readAsString(), b, warn: _noWarn).parse();
          final cs = ByteSink();
          final dos = DataOutputSink(cs);
          b.si.writeToFile(dos);
          dos.close();
          var result = ScalableImage.fromSIBytes(cs.toList(), compact: compact);
          // While we're here, check pruning
          result = result.withNewViewport(result.viewport, prune: true);
          return result;
        });
        await _testReference(
            'AVD => .si',
            getDir(inputDir, 'avd')!,
            getDir(referenceDir, 'avd')!,
            getDir(outputDir, 'avd'), (File f) async {
          final b = SICompactBuilderNoUI(bigFloats: true, warn: _noWarn);
          StringAvdParser(await f.readAsString(), b).parse();
          final cs = ByteSink();
          final dos = DataOutputSink(cs);
          b.si.writeToFile(dos);
          dos.close();
          var result = ScalableImage.fromSIBytes(cs.toList(), compact: compact);
          // While we're here, check pruning
          result = result.withNewViewport(result.viewport, prune: true);
          return result;
        });
      }

      await _testReference(
        'SI source',
        getDir(inputDir, 'si')!,
        getDir(referenceDir, 'si')!,
        getDir(outputDir, 'si'),
        (File f) async => ScalableImage.fromSIBytes(await f.readAsBytes()),
      );
      await _testReference(
          'SI source, compact',
          getDir(inputDir, 'si')!,
          getDir(referenceDir, 'si')!,
          getDir(outputDir, 'si'),
          (File f) async =>
              ScalableImage.fromSIBytes(await f.readAsBytes(), compact: true));

      await _testReference(
          'AVD source',
          getDir(inputDir, 'avd')!,
          getDir(referenceDir, 'avd')!,
          getDir(outputDir, 'avd'),
          (File f) async => ScalableImage.fromAvdString(await f.readAsString(),
              warnF: _noWarn));
    }
    await _testReference(
        'AVD => .si',
        getDir(Directory('test/more_test_images'), 'avd')!,
        getDir(referenceDir, 'avd')!,
        getDir(outputDir, 'avd'), (File f) async {
      final b = SICompactBuilderNoUI(bigFloats: true, warn: _noWarn);
      StringAvdParser(await f.readAsString(), b).parse();
      final cs = ByteSink();
      final dos = DataOutputSink(cs);
      b.si.writeToFile(dos);
      dos.close();
      return ScalableImage.fromSIBytes(cs.toList(), compact: false);
    });
  }, timeout: const Timeout(Duration(seconds: 240)));

  test('Affine sanity check', () {
    final rand = Random();
    for (int i = 0; i < 1000; i++) {
      final vec = Float64List(6);
      for (int i = 0; i < vec.length; i++) {
        vec[i] = (rand.nextDouble() > 0.5)
            ? rand.nextDouble()
            : (1 / (rand.nextDouble() + 0.00001));
      }
      final m1 = MutableAffine.cssTransform(vec);
      if (m1.determinant().abs() > 0.0000000000001) {
        final m2 = MutableAffine.copy(m1)..invert();
        m1.multiplyBy(m2);
        for (int r = 0; r < 3; r++) {
          for (int c = 0; c < 3; c++) {
            if (r == c) {
              expect((m1.get(r, c) - 1).abs() < 0.0000001, true,
                  reason: 'vec $vec');
            } else {
              expect(m1.get(r, c).abs() < 0.0000001, true, reason: 'vec $vec');
            }
          }
        }
      }
    }
  });
  test('cache test', _cacheTest);
  test('create SI smoke test', _createSI);
  testSIWidget();
}
