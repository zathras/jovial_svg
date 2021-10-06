/*
MIT License

Copyright (c) 2021 William Foote

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

import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:jovial_svg/src/affine.dart';
import 'package:jovial_svg/src/dag.dart';
import 'package:jovial_svg/src/exported.dart';
import 'package:jovial_svg/src/widget.dart';

void main() {
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
  final _si = Future.value(ScalableImageDag(
      width: 1,
      height: 1,
      images: [],
      tintMode: BlendMode.src,
      viewport: Rect.zero,
      tintColor: Color(0)));
  final int id = _rand.nextInt(4000);
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
  final cache = ScalableImageCache(size: 1200);
  final referenced = <ScalableImageSource>[];
  for (int i = 0; i < 800; i++) {
    final s = TestSource();
    referenced.add(s);
    cache.addReference(s);
  }
  for (int i = 0; i < 100000000; i++) {
    final v = referenced[i % referenced.length];
    cache.removeReference(v);
    final s = TestSource();
    referenced[i % referenced.length] = s;
    cache.addReference(s);
  }
}
