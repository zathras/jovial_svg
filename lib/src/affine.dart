/*
Copyright (c) 2021-2025, William Foote

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

///
/// A little wrapper around Dart matrix operations to efficiently
/// represent affine transformations, without depending on Flutter.
//
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:vector_math/vector_math_64.dart';

///
/// Affine matrix, used to represent scale, translate and other
/// transformations applied to e.g. an SVG node.  Attaching an
/// affine matrix to a node is equivalent to calling `dart:ui`'s
/// `Canvas.transform` method.
///
abstract class Affine {
  Affine._p();

  ///
  /// Create a new immutable matrix as a view on underlying storage with an
  /// offset.  The first two rows are taken from storage, in row major order;
  /// the final row of "0 0 1" is implicit.  The storage must have a length
  /// of at least offset + 6.  The caller must ensure that the underlying list
  /// is not changed.
  ///
  factory Affine.fromCompact(List<double> storage, int offset) =>
      _CompactAffine(storage, offset);

  ///
  /// Copy this affine into the compact format, as described in
  /// [Affine.fromCompact].
  ///
  void copyIntoCompact(List<double> storage, [int offset = 0]);

  void _checkIndices(int row, int col) {
    if (row < 0 || row > 2) {
      throw IndexError.withLength(row, 3, indexable: this);
    } else if (col < 0 || col > 2) {
      throw IndexError.withLength(col, 3, indexable: this);
    }
  }

  ///
  /// Get the element at [row], [col]
  ///
  double get(int row, int col) {
    _checkIndices(row, col);
    return _get(row, col);
  }

  double _get(int row, int col);

  ///
  /// Give the 4x4 column-major matrix that Canvas wants
  ///
  Float64List get forCanvas {
    final r = Float64List(16);
    r[15] = 1;
    int p = 0;
    for (int col = 0; col < 2; col++) {
      for (int row = 0; row < 3; row++) {
        r[p++] = get(row, col);
      }
      p++;
    }
    p += 2;
    r[p++] = 1;
    p++;
    for (int row = 0; row < 2; row++) {
      r[p++] = get(row, 2);
    }
    return r;
  }

  ///
  /// Give a mutable version of this matrix, by making a copy if necessary.
  ///
  MutableAffine get toMutable;

  ///
  /// Give a copy of this matrix that is mutable.
  ///
  MutableAffine mutableCopy();

  ///
  /// Give an immutable key that can be used to find equivalent
  /// transformation matrices using ==.
  ///
  Affine get toKey;

  @override
  String toString() {
    final sb = StringBuffer();
    sb.write('Affine:\n');
    for (int r = 0; r < 3; r++) {
      for (int c = 0; c < 3; c++) {
        sb.write('\t${get(r, c)}');
      }
      sb.write('\n');
    }
    return sb.toString();
  }

  ///
  /// Return a point transformed by this matrix.
  ///
  Point<double> transformed(Point<double> p) => Point(
        p.x * _get(0, 0) + p.y * _get(0, 1) + _get(0, 2),
        p.x * _get(1, 0) + p.y * _get(1, 1) + _get(1, 2),
      );

  @override
  int get hashCode =>
      0x6a41efee ^
      Object.hash(
        _get(0, 0),
        _get(0, 1),
        _get(0, 2),
        _get(1, 0),
        _get(1, 1),
        _get(1, 2),
      );

  @override
  bool operator ==(Object other) => _equals(other);

  bool _equals(Object other) {
    if (identical(this, other)) {
      return true;
    } else if (other is Affine) {
      for (int c = 0; c < 3; c++) {
        for (int r = 0; r < 2; r++) {
          if (_get(r, c) != other._get(r, c)) {
            return false;
          }
        }
      }
      return true;
    } else {
      return false;
    }
  }
}

class _CompactAffine extends Affine {
  final List<double> _storage;
  final int _offset;

  _CompactAffine(this._storage, this._offset) : super._p() {
    assert(_storage.length >= _offset + 6, '${_storage.length} $_offset');
  }

  ///
  /// Copy the six values of this matrix into storage starting at offset,
  /// in row major order.
  ///
  @override
  void copyIntoCompact(List<double> storage, [int offset = 0]) => storage
      .setRange(offset, offset + 6, _storage.getRange(_offset, _offset + 6));

  @override
  double _get(int row, int column) {
    assert(row >= 0 && row < 3 && column >= 0 && column < 3);
    if (row == 2) {
      if (column == 2) {
        return 1;
      } else {
        return 0;
      }
    } else {
      return _storage[_offset + _storageIndex(row, column)];
    }
  }

  static int _storageIndex(int row, int column) => row * 3 + column;

  @override
  bool _equals(Object other) {
    if (other is _CompactAffine &&
        identical(_storage, other._storage) &&
        _offset == other._offset) {
      return true;
    } else {
      return super._equals(other);
    }
  }

  @override
  MutableAffine get toMutable {
    final storage = Matrix3.zero();
    for (int c = 0; c < 3; c++) {
      for (int r = 0; r < 3; r++) {
        storage.setEntry(r, c, get(r, c));
      }
    }
    return MutableAffine._p(storage);
  }

  @override
  MutableAffine mutableCopy() => toMutable;

  @override
  Affine get toKey => this;
}

///
/// An mutable version of an [Affine] matrix.
///
class MutableAffine extends Affine {
  final Matrix3 _storage;

  MutableAffine._p([Matrix3? storage])
      : _storage = storage ?? Matrix3.zero(),
        super._p();

  ///
  /// Create a matrix representing the identity transform.
  ///
  MutableAffine.identity()
      : _storage = Matrix3.identity(),
        super._p();

  ///
  /// Create a matrix representing a scaling transform.
  ///
  MutableAffine.scale(double sx, double sy)
      : _storage = Matrix3.zero(),
        super._p() {
    set(0, 0, sx);
    set(1, 1, sy);
    set(2, 2, 1);
  }

  ///
  /// Create a matrix representing a translation.
  ///
  MutableAffine.translation(double tx, double ty)
      : _storage = Matrix3.identity(),
        super._p() {
    set(0, 2, tx);
    set(1, 2, ty);
  }

  ///
  /// Create a matrix representing a rotation transform, for the
  /// angle [a] in radians.
  ///
  MutableAffine.rotation(double a)
      : _storage = Matrix3.zero(),
        super._p() {
    final c = cos(a);
    final s = sin(a);
    set(0, 0, c);
    set(0, 1, -s);
    set(1, 0, s);
    set(1, 1, c);
    set(2, 2, 1);
  }

  ///
  /// Create a matrix representing x skew transformation.
  ///
  MutableAffine.skewX(double a)
      : _storage = Matrix3.identity(),
        super._p() {
    set(0, 1, tan(a));
  }

  ///
  /// Create a matrix representing y skew transformation.
  ///
  MutableAffine.skewY(double a)
      : _storage = Matrix3.identity(),
        super._p() {
    set(1, 0, tan(a));
  }

  MutableAffine._copy(MutableAffine other)
      : _storage = Matrix3.copy(other._storage),
        super._p();

  ///
  /// Create an affine matrix representing a transformation matrix as described
  /// in CSS's format, which consists of six float values.  See the matrix
  /// transform in s. 7.6.1 of
  /// https://www.w3.org/TR/SVGTiny12/coords.html#TransformAttribute .
  ///
  MutableAffine.cssTransform(List<double> css)
      : _storage = Matrix3.zero(),
        super._p() {
    // s. 7.5 https://www.w3.org/TR/SVGTiny12/coords.html
    set(0, 0, css[0]);
    set(1, 0, css[1]);
    set(0, 1, css[2]);
    set(1, 1, css[3]);
    set(0, 2, css[4]);
    set(1, 2, css[5]);
    set(2, 2, 1);
  }

  ///
  /// Set the given matrix element
  ///
  void set(int row, int col, double v) => _storage.setEntry(row, col, v);

  ///
  /// Mutliply this matrix by [other], storing the result in this matrix.
  ///
  void multiplyBy(MutableAffine other) => _storage.multiply(other._storage);

  ///
  /// Find the inverse of this matrix.  Caller should ensure determinant
  /// isn't too close to zero.
  ///
  void invert() => _storage.invert();

  ///
  /// Give the determinent of this matrix.
  ///
  double determinant() => _storage.determinant();

  ///
  /// Return `true` if this is the identity matrix
  ///
  bool isIdentity() => _storage.isIdentity();

  @override
  double _get(int row, int col) => _storage.entry(row, col);

  @override
  void copyIntoCompact(List<double> storage, [int offset = 0]) {
    for (int col = 0; col < 3; col++) {
      for (int row = 0; row < 2; row++) {
        storage[offset + _CompactAffine._storageIndex(row, col)] = _get(
          row,
          col,
        );
      }
    }
  }

  @override
  Affine get toKey {
    final storage = Float64List(6);
    copyIntoCompact(storage);
    return _CompactAffine(storage, 0);
  }

  ///
  /// Return this instance.
  ///
  @override
  MutableAffine get toMutable => this;

  ///
  /// Make a copy of this affine matrix.
  ///
  @override
  MutableAffine mutableCopy() => MutableAffine._copy(this);
}
