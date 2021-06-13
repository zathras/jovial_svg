import 'dart:io';

import 'package:args/args.dart';
import 'package:jovial_svg/src/common_noui.dart';
import 'package:jovial_svg/src/compact_noui.dart';
import 'package:jovial_svg/src/svg_parser.dart';

abstract class ToSI {

  String get programName;
  void parse(String src, SIBuilder<String, SIImageData> builder);
  String get extension;

  void usage(final ArgParser argp) {
    print('');
    print('dart run jovial_svg:$programName [options] <input files>');
    for (final line in argp.usage.split('\n')) {
      print('    $line');
    }
    print('');
    print('Using floats instead of doubles is likely a bit faster, and makes');
    print('the files images smaller in memory at runtime.  For most files,');
    print('floats offer more than enough precision.');
    print('');
    exit(1);
  }

  Future<void> main(List<String> arguments) async {
    final argp = ArgParser(usageLineLength: 72);
    argp.addOption('out',
        abbr: 'o', help: 'output directory');
    argp.addFlag('big',
        abbr: 'b', help: 'Use 64 bit double-precision floats, instead of 32.');
    final ArgResults results = argp.parse(arguments);
    bool big = results['big'] == true;
    if (results.rest.isEmpty) {
      usage(argp);
    }
    final Directory? outDir;
    {
      final String? n = results['out']?.toString();
      if (n == null) {
        outDir = null;
      } else {
        outDir = Directory(n);
        if (!outDir.existsSync()) {
          print('Creating directory $outDir');
          outDir.createSync(recursive: true);
        }
      }
    }
    for (final name in results.rest) {
      final f = File(name);
      if (!f.existsSync()) {
        print('$f not found - skipping');
      } else {
        final b = SICompactBuilderNoUI(bigFloats: big, warn: true);
        try {
          parse(f.readAsStringSync(), b);
        } catch (e) {
          print('');
          print ('***** Error in ${f.path} : skipping *****');
          print('     $e');
          print('');
          continue;
        }
        final outName = changeExtension(f.path);
        final File out;
        if (outDir == null) {
          out = File(outName);
        } else {
          final String basename = Uri
              .file(outName)
              .pathSegments
              .last;
          out = File.fromUri(outDir.uri.resolve(basename));
          final bytes = b.si.writeToFile(out);
          print('Wrote $bytes bytes to ${out.path}.');
        }
      }
    }
  }

  String changeExtension(String fileName) {
    if (fileName.toLowerCase().endsWith(extension)) {
      fileName = fileName.substring(0, fileName.length - extension.length);
    }
    return fileName + '.si';
  }
}

class SvgToSI extends ToSI {
  @override
  String get programName => 'svg_to_si';

  @override
  String get extension => '.svg';

  @override
  void parse(String src, SIBuilder<String, SIImageData> builder) =>
    StringSvgParser(src, builder).parse();
}

Future<void> main(List<String> arguments) =>
    SvgToSI().main(arguments);
