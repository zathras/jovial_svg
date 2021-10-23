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

import 'dart:typed_data';

import 'package:hive/hive.dart';
import 'package:jovial_svg/jovial_svg.dart';
import 'package:quiver/core.dart' as quiver;

///
/// A persistent cache of scalable images originally created from SVG files.
/// It can use Hive's [LazyBox] or [Box] for the underlying storage.
///
class HiveSICache {
  final BoxBase<Object> _box;
  // The url is the key, and a Uint8List is the value.  In case of loading
  // error, a String error message is stored.

  final Map<String, Future<ScalableImage>> _pending = {};
  // We record outstanding requests in case the client requests a future
  // for the same URL again, while the first request is still pending
  // future completion (e.g. due to network activity).

  ///
  /// Create a new cache that uses the given box for its underlying persistent
  /// storage.
  ///
  /// This is a simple proof-of-concept implementation.  It never removes
  /// cached images.  A production-quality persistent cache would likely
  /// include at least a strategy to keep the cache from growing too large.
  ///
  HiveSICache(this._box) {
    assert(_box is Box || _box is LazyBox);
  }

  ///
  /// Get an image source that will, on demand, create an instance of
  /// [ScalableImage] based on data found at [url], which might have been
  /// previously cached.
  ///
  ScalableImageSource get(String url) => _HiveSource(this, url);
}

class _HiveSource extends ScalableImageSource {
  final HiveSICache _cache;
  final String _url;
  @override
  final bool warn;

  _HiveSource(this._cache, this._url, {this.warn = true});

  @override
  bool operator ==(Object other) =>
      other is _HiveSource && _url == other._url && _cache == other._cache;

  @override
  int get hashCode => quiver.hash2(_url, _cache) ^ 0x5eb3bb2c;
  // The hex constant is just a random number.  This ensures that _HiveSource
  // hashes to different values than other ScalableImageSource subtypes.

  @override
  Future<ScalableImage> createSI() {
    final box = _cache._box;
    if (box is Box) {
      // If it's in the cache, we can do it synchronously
      Object? cached = (box as Box).get(_url);
      if (cached is Uint8List) {
        print('    from cache: $_url');
        return Future.value(ScalableImage.fromSIBytes(cached, compact: false));
      } else if (cached is String) {
        print('    cached error $cached');
        return Future.error(cached);
      } else {
        assert(cached == null);
      }
    }
    return _cache._pending.update(_url, (v) => v, ifAbsent: _createSI);
    // Recording our outstanding request like this prevents us from fetching
    // the same URL over the network twice, even if our caller requests it
    // a second time while we're still waiting.
  }

  Future<ScalableImage> _createSI() async {
    // Note that we *must* await at least one future in the body of this
    // method, so that the return value gets recorded in the _cache._pending
    // map before we try to remove it in the finally block, below.
    try {
      final box = _cache._box;
      if (box is LazyBox) {
        Object? cached = await (box as LazyBox).get(_url);
        if (cached is Uint8List) {
          print('    from cache: $_url');
          return ScalableImage.fromSIBytes(cached, compact: false);
        } else if (cached is String) {
          print('    cached error $cached');
          throw cached;
        } else {
          assert(cached == null);
        }
      }
      try {
        final si = await ScalableImageSource.fromSvgHttpUrl(Uri.parse(_url),
                compact: true, bigFloats: true)
            .createSI();
        await _cache._box.put(_url, si.toSIBytes());
        print('FROM NETWORK: $_url');
        return si.toDag();
      } catch (err) {
        print('Network error $err');
        await _cache._box.put(_url, err.toString());
        // In a production-quality implementation, we'd likely want to
        // make it possible for our caller to retry later.
        rethrow;
      }
    } finally {
      final check = _cache._pending.remove(_url);
      assert(check != null);
    }
  }
}
