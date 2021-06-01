import 'dart:io';

import 'package:args/args.dart';
import 'package:jovial_svg/src/common_noui.dart';
import 'package:jovial_svg/src/compact_noui.dart';
import 'package:jovial_svg/src/svg_parser.dart';

abstract class ToSI {
  String get programName;

  void usage(final ArgParser argp) {
    print('');
    print('dart run jovial_svg:$programName [options] <input> <output>');
    print('    <input> may be a single file, or a directory');
    print('    <output> is the output file or directory');
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
    argp.addFlag('big',
        abbr: 'b', help: 'Use 64 bit double-precision floats, instead of 32.');
    final ArgResults results = argp.parse(arguments);
    bool big = results['big'] == true;
    if (results.rest.length != 2) {
      usage(argp);
    }
    final b = SICompactBuilderNoUI(bigFloats: big, warn: true);
    parse(File(results.rest[0]).readAsStringSync(), b);
    final out = File(results.rest[1]);
    final bytes = b.si.writeToFile(out);
    print('Wrote $bytes bytes to $out.');
  }

  void parse(String src, SIBuilder<String> builder);
}

class SvgToSI extends ToSI {
  @override
  String get programName => 'svg_to_si';

  @override
  void parse(String src, SIBuilder<String> builder) =>
    StringSvgParser(src, builder).parse();
}

Future<void> main(List<String> arguments) {
  final converter = SvgToSI();
  return converter.main(arguments);
}
