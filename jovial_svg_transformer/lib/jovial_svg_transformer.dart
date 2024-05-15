// ignore_for_file: implementation_imports

///
/// This package exposes an API that can be used to build an asset transformer
/// to turn SVG or AVD files into an efficient binary representation for
/// `jovial_svg`.
///
library jovial_svg_transformer;

import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:jovial_misc/io_utils.dart';
import 'package:jovial_svg/src/common_noui.dart';
import 'package:jovial_svg/src/compact_noui.dart';
import 'package:jovial_svg/src/svg_parser.dart';
import 'package:jovial_svg/src/avd_parser.dart';

///
/// Convert SVG or AVD to SI
///
class ToSI {
  final List<Pattern> _exportedIds = List.empty(growable: true);
  bool _parseAVD = false;

  void _parse(String src, SIBuilder<String, SIImageData> builder,
      void Function(String) warn) {
    if (_parseAVD) {
      StringAvdParser(src, builder).parse();
    } else {
      StringSvgParser(src, _exportedIds, builder, warn: warn).parse();
    }
  }

  void _usage(final ArgParser argp) {
    print('');
    print('dart run jovial_svg_transformer [options]'
        ' --input <name> --output <name>');
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

  ///
  /// Run the program according to [arguments].
  ///
  void main(List<String> arguments) async {
    final argp = ArgParser(usageLineLength: 72);
    argp.addFlag('help', abbr: 'h', help: 'show help message');
    argp.addFlag('big',
        abbr: 'b', help: 'Use 64 bit double-precision floats, instead of 32.');
    argp.addFlag('quiet', abbr: 'q', help: 'Quiet:  Suppress warnings.');

    argp.addMultiOption('exportx',
        abbr: 'x',
        splitCommas: false,
        help:
            'Export:  Export the SVG node IDs matched by the given regular expression.  '
            'Multiple values may be specified.');
    final ArgResults results;
    final String? inFile;
    final String? outFile;
    try {
      results = argp.parse(arguments);
      if (results['help'] == true) {
        print('');
        _usage(argp);
      }
      inFile = results['input'];
      outFile = results['output'];
    } catch (ex) {
      print('');
      print(ex);
      _usage(argp);
      return;
    }
    bool big = results['big'] == true;
    bool warn = results['quiet'] != true;
    for (final String e in (results['export'] as List<String>)) {
      _exportedIds.add(e);
    }
    for (final String ex in (results['exportx'] as List<String>)) {
      _exportedIds.add(RegExp(ex));
    }
    _parseAVD = results['avd'] == true;
    if (results.rest.isNotEmpty || inFile == null || outFile == null) {
      _usage(argp);
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
      _parse(f.readAsStringSync(), b, warnF);
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
