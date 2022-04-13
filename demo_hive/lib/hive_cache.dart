/*
Copyright (c) 2021-2022, William Foote

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
import 'package:jovial_misc/async_fetcher.dart';
import 'package:jovial_svg/jovial_svg.dart';

///
/// A persistent cache of scalable images originally created from SVG files.
/// It can use Hive's [LazyBox] or [Box] for the underlying storage.
///
/// This is a simple proof-of-concept implementation.  It never removes
/// cached images.  A production-quality persistent cache would likely
/// include at least a strategy to keep the cache from growing too large.
///
class HiveSICache {
  final BoxBase<Object> _box;
  // The url is the key, and a Uint8List is the value.  In case of loading
  // error, a String error message is stored.

  late final _SIFetcher _fetcher;

  ///
  /// Create a new cache that uses the given box for its underlying persistent
  /// storage.
  ///
  HiveSICache(this._box) {
    assert(_box is Box || _box is LazyBox);
    // See https://github.com/hivedb/hive/issues/820
    _fetcher = _SIFetcher(this, true);
  }

  ///
  /// Get an image source that will, on demand, create an instance of
  /// [ScalableImage] based on data found at [url], which might have been
  /// previously cached.
  ///
  ScalableImageSource get(String url) => _HiveSource(this, url);
}

///
/// Helper to fetch a [ScalableImage] from the cache, or if there's a miss,
/// from the network.  Using [AsyncCanonicalizingFetcher] for this ensures that
/// we don't make two network requests for the same resource, even if the
/// same URL is requested by our caller more than once.
///
/// _SiFetcher does not guard against duplicate [ScalableImage] instances, but
/// that is not needed, because [ScalableImageWidget]'s cache protects against
/// that.
///
class _SIFetcher extends AsyncCanonicalizingFetcher<String, ScalableImage> {
  final HiveSICache _cache;
  final bool _warn;

  _SIFetcher(this._cache, this._warn);

  @override
  Future<ScalableImage> create(String url) async {
    final box = _cache._box;
    Object? cached;
    if (box is LazyBox) {
      cached = await (box as LazyBox).get(url);
    } else {
      // It would be slightly more efficient to hoist this synchronous
      // case outside the future, but it would be less elegant.  In production
      // code I might well prefer efficiency.
      cached = (box as Box).get(url);
    }
    if (cached is Uint8List) {
      if (_warn) {
        print('    from cache: $url');
      }
      return ScalableImage.fromSIBytes(cached, compact: false);
    } else if (cached is String) {
      if (_warn) {
        print('    cached error $cached');
      }
      throw cached;
    }
    assert(cached == null);
    try {
      final si = await ScalableImageSource.fromSvgHttpUrl(Uri.parse(url),
              compact: true, bigFloats: true)
          .createSI();
      await _cache._box.put(url, si.toSIBytes());
      if (_warn) {
        print('FROM NETWORK: $url');
      }
      return si.toDag();
    } catch (err) {
      if (_warn) {
        print('Network error $err');
      }
      await _cache._box.put(url, err.toString());
      // In a production-quality implementation, we'd likely want to
      // make it possible for our caller to retry later.
      rethrow;
    }
  }
}

class _HiveSource extends ScalableImageSource {
  final HiveSICache _cache;
  final String _url;
  @override
  final bool warn; // for the demo, this makes us downright chatty

  _HiveSource(this._cache, this._url, {this.warn = true});

  @override
  bool operator ==(Object other) =>
      other is _HiveSource && _url == other._url && _cache == other._cache;

  @override
  int get hashCode => Object.hash(_url, _cache) ^ 0x5eb3bb2c;
  // The hex constant is just a random number.  This ensures that _HiveSource
  // hashes to different values than other ScalableImageSource subtypes.

  @override
  Future<ScalableImage> createSI() => _cache._fetcher.get(_url);
}
