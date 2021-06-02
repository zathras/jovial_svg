import 'package:jovial_svg/src/avd_parser.dart';
import 'package:jovial_svg/src/common_noui.dart';
import 'svg_to_si.dart';

class AvdToSI extends ToSI {
  @override
  String get programName => 'avd_to_si';

  @override
  void parse(String src, SIBuilder<String> builder) =>
      StringAvdParser(src, builder).parse();

  @override
  String get extension => '.xml';
}

Future<void> main(List<String> arguments) =>
    AvdToSI().main(arguments);
