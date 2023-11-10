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

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:jovial_svg/jovial_svg.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'hive_cache.dart';

///
/// A sample application to demonstrate using a persistent
/// cache integrated with jovial_svg.  See
/// https://github.com/zathras/jovial_svg/issues/12
///
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final d = await getTemporaryDirectory();
  print('Storing hive DB in $d');
  Hive.init(d.path);
  hiveBox = await Hive.openBox<Object>('svgCache');
  // LazyBox works too, but it's surprisingly slow, at least on MacOS.
  // hiveBox = await Hive.openLazyBox<Object>('svgCache');
  persistentCache = HiveSICache(hiveBox);
  runApp(MyApp(await getSvgs()));
}

///
/// The Hive persistent a-v pair database
///
late final BoxBase<Object> hiveBox;

///
/// A persistent SI cache that stores cached entries in hiveBox
///
late final HiveSICache persistentCache;

///
/// Some SVG images to show.
///
Future<List<String>> getSvgs() async {
  String? json;
  if (hiveBox is LazyBox) {
    json = await (hiveBox as LazyBox).get('svg_list') as String?;
  } else {
    json = (hiveBox as Box).get('svg_list') as String?;
  }
  if (json != null) {
    print('Got URL list from Hive.');
  } else {
    final url = Uri.parse('https://pastebin.com/raw/iLn5UqZM');
    final response = await http.get(url);
    json = response.body;
    unawaited(hiveBox.put('svg_list', json));
    print('Got URL list from network.');
  }
  return (jsonDecode(json) as List).cast<String>();
  // If the external assets, above, ever go away, we can do this:
  // return List.generate(100,
  //      (i) => 'https://jovial.com/images/jupiter.svg?x=$i');
  // The parameter is ignored by the server, but it makes the URLs distinct.
}

///
/// Application class for the sample.
///
class MyApp extends StatelessWidget {
  final List<String> svgs;

  const MyApp(this.svgs, {super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CacheDemo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: HomePage(svgs),
    );
  }
}

///
/// A stateful widget that displays a big list of SVG images.  It loads
/// them lazily, and uses a persistent cache.
///
class HomePage extends StatefulWidget {
  final List<String> svgs;

  const HomePage(this.svgs, {super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ScalableImageCache _memoryCache = ScalableImageCache(size: 80);
  // An in-memory cache of the SVG images, to avoid excessive image rebuilding.
  // This isn't the persistent cache.
  //
  // Even though we have a persistent cache, it's a good idea to have
  // an in-memory cache, at least big enough to hold as many SVGs as are
  // likely to be on the screen at a time.  This can save rebuilding
  // CPU overhead, e.g. during animations.

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Persistent Cache'), actions: [
        ElevatedButton(
            onPressed: _clearStorage,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
            child: const Text('Clear Storage'))
      ]),
      body: GridView.builder(
          itemCount: widget.svgs.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5),
          itemBuilder: (context, index) {
            return GridTile(
              child: ScalableImageWidget.fromSISource(
                  cache: _memoryCache,
                  si: persistentCache.get(widget.svgs[index]),
                  onLoading: _onLoading,
                  onError: _onError),
            );
          }),
    );
  }

  void _clearStorage() {
    unawaited(() async {
      print('Clearing Hive storage...');
      // This is a pretty slow way of doing things, but it's simple, and good
      // enough for this demo.  A production-quality app would probably have
      // a much more selective way of limiting cache size anyway.
      await hiveBox.deleteAll(hiveBox.keys);
      await hiveBox.compact();
      print('Hive storage cleared.');
    }());
  }

  Widget _onLoading(BuildContext context) => Container(color: Colors.green);
  Widget _onError(BuildContext context) => Container(color: Colors.red);
}
