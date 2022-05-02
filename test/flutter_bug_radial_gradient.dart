import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

void main() async {
  final recorder = PictureRecorder();
  final Canvas c = Canvas(recorder);
  final Paint p = Paint();
  final xform = Float64List.fromList([
    86.80000129342079,
    0.0,
    0.0,
    0.0,
    0.0,
    94.5,
    0.0,
    0.0,
    0.0,
    0.0,
    1.0,
    0.0,
    60.0,
    224.310302734375,
    0.0,
    1.0
  ]);
  p.shader = Gradient.radial(
      Offset(-0.1, -1.7),
      0.5,
      [Color(0xffff0000), Color(0xff00ff00)],
      [0.0, 1.0],
      TileMode.repeated,
      xform);
  c.drawRect(Rect.fromLTWH(0, 0, 100, 100), p);
  final Picture pict = recorder.endRecording();
  final Image rendered = await pict.toImage(100, 100);
  final bd = await rendered.toByteData(format: ImageByteFormat.png);
  final bytes = Uint8List.fromList(bd!.buffer.asUint8List());
  File('flutter_bug.png').writeAsBytesSync(bytes);
  print('Wrote ${bytes.length} to flutter_bug.png');
}
