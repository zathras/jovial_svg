import 'package:jovial_svg_transformer/jovial_svg_transformer.dart';
import 'package:test/test.dart';

void main() {
  test('Accepts "input" parameter', () {
    // Since this calls exit if arguments not valid, the test
    // will fail all on its own if arguments are not
    // correct.
    ToSI().main([
      "--input",
      "example/assets/tiger.svg",
      "--output",
      "test/temp.si",
    ]);
  });
}
