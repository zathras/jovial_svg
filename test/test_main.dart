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

import 'package:flutter_test/flutter_test.dart';
import 'package:jovial_svg/src/affine.dart';
import 'package:jovial_svg/src/dag.dart';
import 'package:jovial_svg/src/exported.dart';
import 'package:jovial_svg/src/widget.dart';

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
    {Directory? overrideReferenceDir}) async {
  for (FileSystemEntity ent in inputDir.listSync()) {
    final name = ent.uri.pathSegments.last;
    final noExt = name.substring(0, name.lastIndexOf('.'));
    if (ent is File && noExt != 'README') {
      final ScalableImage si = await producer(ent);
      await si.prepareImages();
      final size = si.viewport;
      final recorder = PictureRecorder();
      si.paint(Canvas(recorder));
      si.unprepareImages();
      final Image rendered = await recorder
          .endRecording()
          .toImage(size.width.round(), size.height.round());
      final renderedBytes =
          await rendered.toByteData(format: ImageByteFormat.rawRgba);

      try {
        File refName = File('${referenceDir.path}/$noExt.png');
        if (overrideReferenceDir != null) {
          final o = File('${overrideReferenceDir.path}/$noExt.png');
          if (o.existsSync()) {
            refName = o;
          }
        }
        final codec = await instantiateImageCodec(refName.readAsBytesSync());
        final reference = await (await codec.getNextFrame())
            .image
            .toByteData(format: ImageByteFormat.rawRgba);
        expect(renderedBytes!.buffer.asUint8List(),
            reference!.buffer.asUint8List(),
            reason: '$description:  $ent and $refName differ');
      } catch (failed) {
        if (outputDir != null) {
          final outName = File('${outputDir.path}/$noExt.png');
          print('Writing rendered result to $outName');
          outputDir.createSync(recursive: true);
          outName.writeAsBytesSync(
              (await rendered.toByteData(format: ImageByteFormat.png))!
                  .buffer
                  .asUint8List());
        }
        // rethrow;
      }
    }
  }
}

class CanvasRecorder implements Canvas {
  int _saveCount = 1;
  final records = List<String>.empty(growable: true);

  void record(String s) {
    records.add(s);
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
    record('drawArc');
  }

  @override
  void drawAtlas(Image atlas, List<RSTransform> transforms, List<Rect> rects,
      List<Color>? colors, BlendMode? blendMode, Rect? cullRect, Paint paint) {
    record('drawAtlas');
  }

  @override
  void drawCircle(Offset c, double radius, Paint paint) {
    record('drawCircle');
  }

  @override
  void drawColor(Color color, BlendMode blendMode) {
    record('drawColor');
  }

  @override
  void drawDRRect(RRect outer, RRect inner, Paint paint) {
    record('drawDRRect');
  }

  @override
  void drawImage(Image image, Offset offset, Paint paint) {
    record('drawImage');
  }

  @override
  void drawImageNine(Image image, Rect center, Rect dst, Paint paint) {
    record('drawImageNine');
  }

  @override
  void drawImageRect(Image image, Rect src, Rect dst, Paint paint) {
    record('drawImageRect');
  }

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    record('drawLine');
  }

  @override
  void drawOval(Rect rect, Paint paint) {
    record('drawOval');
  }

  @override
  void drawPaint(Paint paint) {
    record('drawPaint');
  }

  @override
  void drawParagraph(Paragraph paragraph, Offset offset) {
    record('drawParagraph');
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
    record('drawPoints');
  }

  @override
  void drawRRect(RRect rrect, Paint paint) {
    record('drawRRect');
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
    record('drawRect');
  }

  @override
  void drawShadow(
      Path path, Color color, double elevation, bool transparentOccluder) {
    record('drawShadow');
  }

  @override
  void drawVertices(Vertices vertices, BlendMode blendMode, Paint paint) {
    record('drawVertices');
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
  void rotate(double radians) {
    record('rotate');
  }

  @override
  void save() {
    record('save');
    _saveCount++;
  }

  @override
  void saveLayer(Rect? bounds, Paint paint) {
    record('saveLayer $paint');
    // We intentionally don't save the bounds.  The compact implementation
    // doesn't set it under certain circumstances, since calculating a bounds
    // is slower (and more difficult!) with the compact representation.
    _saveCount++;
  }

  @override
  void scale(double sx, [double? sy]) {
    record('scale');
  }

  @override
  void skew(double sx, double sy) {
    record('skew');
  }

  @override
  void transform(Float64List matrix4) {
    record('transform');
  }

  @override
  void translate(double dx, double dy) {
    record('translate $dx $dy');
  }
}

void main() {
  test('compact drawing order', () async {
    final inputDir = Directory('demo/assets/si');
    for (final ent in inputDir.listSync()) {
      final name = ent.uri.pathSegments.last;
      final noExt = name.substring(0, name.lastIndexOf('.'));
      if (ent is File && noExt != 'README') {
        final regular = ScalableImage.fromSIBytes(await ent.readAsBytes());
        final compact =
            ScalableImage.fromSIBytes(await ent.readAsBytes(), compact: true);
        final rr = CanvasRecorder();
        regular.paint(rr);
        final cr = CanvasRecorder();
        compact.paint(cr);
        expect(cr.records, rr.records, reason: '$ent differs');
      }
    }
  });

  test('Reference Images', () async {
    const String dirName = String.fromEnvironment('jovial_svg.output');
    final outputDir = (dirName == '') ? null : Directory(dirName);
    Directory? getDir(Directory? d, String name) =>
        d == null ? null : Directory('${d.path}/$name');
    final inputDir = Directory('demo/assets');
    final referenceDir = Directory('test/reference_images');
    await _testReference(
        'SVG source',
        getDir(inputDir, 'svg')!,
        getDir(referenceDir, 'svg')!,
        getDir(outputDir, 'svg'),
        (File f) async =>
            ScalableImage.fromSvgString(await f.readAsString(), warn: false));
    await _testReference(
        'SI source',
        getDir(inputDir, 'si')!,
        getDir(referenceDir, 'si')!,
        getDir(outputDir, 'si'),
        (File f) async => ScalableImage.fromSIBytes(await f.readAsBytes()));
    await _testReference(
        'SI source, compact',
        getDir(inputDir, 'si')!,
        getDir(referenceDir, 'si')!,
        getDir(outputDir, 'si_compact'),
        (File f) async =>
            ScalableImage.fromSIBytes(await f.readAsBytes(), compact: true),
        overrideReferenceDir: getDir(referenceDir, 'si_compact')!);
    // The compact renderer doesn't set a bounds for saveLayer() calls when
    // calculating the boundary is required, because doing so is expensive
    // (and a bit complicated :-) ).  This causes rendering to be slightly
    // different, but not perceptibly so, and not in a way that's incorrect.

    await _testReference(
        'AVD source',
        getDir(inputDir, 'avd')!,
        getDir(referenceDir, 'avd')!,
        getDir(outputDir, 'avd'),
        (File f) async =>
            ScalableImage.fromAvdString(await f.readAsString(), warn: false));
  });
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
    cache.addReference(s);
  }
  for (int i = 0; i < 100000; i++) {
    final v = referenced[i % referenced.length];
    cache.removeReference(v);
    final s = TestSource();
    referenced[i % referenced.length] = s;
    cache.addReference(s);
  }
}
