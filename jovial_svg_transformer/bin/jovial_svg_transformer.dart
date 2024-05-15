import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:jovial_misc/io_utils.dart';
import 'package:jovial_svg/src/common_noui.dart';
import 'package:jovial_svg/src/compact_noui.dart';
import 'package:jovial_svg/src/svg_parser.dart';
import 'package:jovial_svg/src/avd_parser.dart';

class ToSI {
  List<Pattern> exportedIds = List.empty(growable: true);
  String get programName => 'jovial_svg_transformer';
  bool parseAVD = false;

  void parse(String src, SIBuilder<String, SIImageData> builder,
      void Function(String) warn) {
    if (parseAVD) {
      StringAvdParser(src, builder).parse();
    } else {
      StringSvgParser(src, exportedIds, builder, warn: warn).parse();
    }
  }

  void usage(final ArgParser argp) {
    print('');
    print('dart run $programName [options]');
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
    argp.addOption('output', abbr: 'o', help: 'output file', mandatory: true);
    argp.addOption('input', abbr: 'i', help: 'input file', mandatory: true);
    argp.addFlag('avd',
        abbr: 'a',
        help: 'Process an Android Vector Drawable instead of an SVG');
    argp.addFlag('big',
        abbr: 'b', help: 'Use 64 bit double-precision floats, instead of 32.');
    argp.addFlag('quiet', abbr: 'q', help: 'Quiet:  Suppress warnings.');
    argp.addMultiOption('export',
        abbr: 'e',
        splitCommas: false,
        help:
            'Export:  Export the given SVG node ID.  Multiple values may be specified.');
    argp.addMultiOption('exportx',
        abbr: 'x',
        splitCommas: false,
        help:
            'Export:  Export the SVG node IDs matched by the given regular expression.  '
            'Multiple values may be specified.');
    final ArgResults results;
    try {
      results = argp.parse(arguments);
    } catch (ex) {
      print('');
      print(ex);
      usage(argp);
      return;
    }
    bool big = results['big'] == true;
    bool warn = results['quiet'] != true;
    for (final String e in (results['export'] as List<String>)) {
      exportedIds.add(e);
    }
    for (final String ex in (results['exportx'] as List<String>)) {
      exportedIds.add(RegExp(ex));
    }
    parseAVD = results['avd'] == true;
    final inFile = results['input'];
    final outFile = results['output'];
    if (results.rest.isNotEmpty || inFile == null || outFile == null) {
      usage(argp);
      return;
    }
    final f = File(inFile);
    if (!f.existsSync()) {
      print('$f not found - aborting');
      exit(1);
    }
    final warnF = warn ? (String s) => print(s) : (String _) {};
    final b = SICompactBuilderNoUI(bigFloats: big, warn: warnF);
    try {
      parse(f.readAsStringSync(), b, warnF);
    } catch (e) {
      print('');
      print('***** Error in ${f.path} *****');
      print('     $e');
      print('');
      exit(1);
    }
    final out = File(outFile);
    final os = DataOutputSink(out.openWrite(), Endian.big);
    final bytes = b.si.writeToFile(os);
    print('Wrote $bytes bytes to ${out.path}.');
  }
}

void main(List<String> arguments) {
  ToSI().main(arguments);
}
