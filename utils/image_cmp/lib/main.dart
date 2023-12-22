import 'dart:io';

import 'package:flutter/material.dart';
import 'package:filesystem_picker/filesystem_picker.dart';
import 'package:path/path.dart' as path;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Compare Reference Images',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const CompareImages(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class CompareImages extends StatefulWidget {
  const CompareImages({super.key});

  @override
  State<CompareImages> createState() => _CompareImagesState();
}

class _CompareImagesState extends State<CompareImages> {
  bool first = true;
  Directory? newImages;
  Directory? oldImages;
  List<File>? files;
  int pos = 0;

  @override
  Widget build(BuildContext context) {
    if (first) {
      first = false;
      () async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        while (newImages == null) {
          final s = await FilesystemPicker.open(
              context: context,
              rootDirectory: Directory('../..'),
              directory: Directory('../../tmp'),
              title: 'New images directory',
              fsType: FilesystemType.folder);
          if (s != null) {
            newImages = Directory(path.normalize(path.relative(s)));
          }
        }
        while (oldImages == null) {
          final s = await FilesystemPicker.open(
              context: context,
              rootDirectory: Directory('../..'),
              directory: Directory('../../test/reference_images'),
              title: 'Old images directory',
              fsType: FilesystemType.folder);
          if (s != null) {
            oldImages = Directory(path.normalize(path.relative(s)));
          }
        }
        final files = <File>[];
        addFilesFrom(newImages!, files);
        setState(() {
          if (files.isNotEmpty) {
            this.files = files;
          }
        });
      }();
    }
    return Scaffold(
      appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          title: Text(files == null
              ? ''
              : '${pos+1} / ${files!.length} : ${files![pos].path}'),
          actions: [
            IconButton(
              onPressed: (files == null) ? null : _last,
              tooltip: 'Last',
              icon: const Icon(Icons.arrow_back),
              iconSize: 36,
            ),
            const SizedBox(width: 20),
            IconButton(
              onPressed: (files == null) ? null : _next,
              tooltip: 'Next',
              icon: const Icon(Icons.arrow_forward),
              iconSize: 36,
            ),
          ]),
      body: files == null
          ? Container()
          : Stack(children: [
              Image.file(files![(pos + 1) % files!.length],
                  scale: .1, fit: BoxFit.contain), // Preload
              Container(color: Colors.white),
              Image.file(files![pos], scale: .1, fit: BoxFit.contain),
            ]),
    );
  }

  void addFilesFrom(Directory dir, List<File> files) {
    List<String> images = [];
    for (final f in dir.listSync(recursive: true)) {
      if (f is File) {
        images.add(path.relative(f.path, from: dir.path));
        print(images[images.length - 1]);
      }
    }
    images.sort();
    for (final image in images) {
      files.add(File(path.join(oldImages!.path, image)));
      files.add(File(path.join(newImages!.path, image)));
    }
  }

  void _next() {
    setState(() {
      pos = (pos + 1) % files!.length;
    });
  }

  void _last() {
    setState(() {
      pos = ((pos - 1) + files!.length) % files!.length;
    });
  }
}
