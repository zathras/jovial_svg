import 'package:flutter/material.dart';
import 'package:jovial_svg/jovial_svg.dart';

void main() {
  final ScalableImage si = ScalableImage.fromSvgString("""
    <svg width="410px" height="210px" xmlns="http://www.w3.org/2000/svg">
    <rect width="400" height="200" x="105" y="5" fill="aqua" stroke-width="4"
        stroke="pink"/>
    <circle cx="305" cy="105" r="45" fill="lightgoldenrodyellow" />
    </svg>
  """, currentColor: Colors.amber)
      .withNewViewport(const Rect.fromLTWH(100, 0, 410, 210));
  runApp(MinimalSample(si));
}

class MinimalSample extends StatelessWidget {
  final ScalableImage si;

  const MinimalSample(this.si, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'SVG scale/translate sample', home: Scaffold(body: Body(si)));
  }
}

///
/// A minimal application demonstrating SVG's currentColor feature.
///
class Body extends StatefulWidget {
  final ScalableImage si;

  const Body(this.si, {Key? key}) : super(key: key);

  @override
  State<Body> createState() => _BodyState();
}

const _alignmentValues = [
  Alignment.topLeft,
  Alignment.topCenter,
  Alignment.topRight,
  Alignment.centerLeft,
  Alignment.center,
  Alignment.centerRight,
  Alignment.bottomLeft,
  Alignment.bottomCenter,
  Alignment.bottomRight,
];

class _BodyState extends State<Body> {
  var fitIndex = 0;
  BoxFit get fit => BoxFit.values[fitIndex];
  var alignmentIndex = 0;
  Alignment get alignment => _alignmentValues[alignmentIndex];
  List<Offset> clicks = [];

  _BodyState();

  @override
  initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(
          child: SizedBox(
              width: double.infinity,
              child: Builder(
                  builder: (BuildContext sub) => GestureDetector(
                      onTapDown: (TapDownDetails d) {
                        Size? size = sub.size;
                        if (size != null) {
                          // Determine the position in the coordinate system
                          // of the SVG.  The pink rectangle in our SVG runs
                          // from (100,0) to (500, 200).
                          final pos = ScalingTransform(
                                  containerSize: size,
                                  siViewport: widget.si.viewport,
                                  fit: fit,
                                  alignment: alignment)
                              .toSICoordinate(d.localPosition);
                          debugPrint('Saw tap down at $pos within SVG');
                          setState(() {
                            clicks.add(pos);
                          });
                        }
                      },
                      child: Stack(fit: StackFit.passthrough, children: [
                        ScalableImageWidget(
                          si: widget.si,
                          fit: fit,
                          alignment: alignment,
                        ),
                        CustomPaint(painter: MyPainter(this))
                      ]))))),
      Row(children: [
        const Spacer(),
        ElevatedButton(
            onPressed: () {
              setState(() {
                fitIndex = (fitIndex + 1) % BoxFit.values.length;
              });
            },
            child: const Text('Fit')),
        const Spacer(),
        ElevatedButton(
            onPressed: () {
              setState(() {
                alignmentIndex = (alignmentIndex + 1) % _alignmentValues.length;
              });
            },
            child: const Text('Alignment')),
        const Spacer(),
        SizedBox(
            width: 300,
            child: Text('$fit  $alignment',
                style: const TextStyle(fontSize: 14, color: Colors.black))),
      ]),
      Container(height: 10)
    ]);
  }
}

class MyPainter extends CustomPainter {
  final _BodyState state;

  MyPainter(this.state);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.black;

    // We store the clicks in the SVG's coordinate space, so we need to
    // transform them back out to the container's.
    final xform = ScalingTransform(
        containerSize: size,
        siViewport: state.widget.si.viewport,
        fit: state.fit,
        alignment: state.alignment);
    for (final c in state.clicks) {
      canvas.drawCircle(xform.toContainerCoordinate(c), 5, p);
    }
  }

  @override
  bool shouldRepaint(MyPainter oldDelegate) {
    return true;
  }
}
