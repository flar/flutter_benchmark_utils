// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_benchmark_utils/benchmark_data.dart';

final List<Color> heatColors = <Color>[
  Colors.green,
  Colors.green.shade200,
  Colors.yellow.shade600,
  Colors.red,
];

class TimelineResultsGraphWidget extends StatefulWidget {
  const TimelineResultsGraphWidget(this.results)
      : assert(results != null);

  final TimelineResults results;

  @override
  State createState() => TimelineResultsGraphWidgetState();
}

class TimelineResultsGraphWidgetState extends State<TimelineResultsGraphWidget> {
  ScrollController _controller;
  List<TimelineGraphWidget> _graphs;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    _graphs = <TimelineGraphWidget>[
      TimelineGraphWidget(widget.results.buildData, _closeGraph),
      TimelineGraphWidget(widget.results.renderData, _closeGraph),
    ];
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _closeGraph(TimelineGraphWidget graph) {
    setState(() => _graphs.remove(graph));
  }

  void _addGraph(String measurement) {
    final TimelineThreadResults results = widget.results.getResults(measurement);
    final TimelineGraphWidget graph = TimelineGraphWidget(results, _closeGraph);
    setState(() => _graphs.add(graph));
  }

  bool isGraphed(String measurement) {
    for (final TimelineGraphWidget graph in _graphs) {
      if (graph.timeline.titleName == measurement) {
        return true;
      }
    }
    return false;
  }
  bool isNotGraphed(String measurement) => !isGraphed(measurement);

  @override
  Widget build(BuildContext context) {
    final Iterable<String> remainingMeasurements = widget.results.measurements.where(isNotGraphed);
    return Stack(
      children: <Widget>[
        Container(
          child: SingleChildScrollView(
            controller: _controller,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (TimelineGraphWidget graph in _graphs)
                  Container(
                    margin: const EdgeInsets.only(top: 20, bottom: 20),
                    child: graph,
                  ),
                Container(
                  margin: const EdgeInsets.only(top: 20, bottom: 20),
                  child: TimelineGraphAdditionalWidget(remainingMeasurements, _addGraph),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class TimelineGraphAdditionalWidget extends StatelessWidget {
  const TimelineGraphAdditionalWidget(this.measurements, this.addCallback);

  final Iterable<String> measurements;
  final Function(String) addCallback;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        DropdownButton<String>(
          icon: const Icon(Icons.add),
          onChanged: addCallback,
          hint: const Text('Add a new graph'),
          items: <DropdownMenuItem<String>>[
            for (String measurement in measurements)
              DropdownMenuItem<String>(value: measurement, child: Text(measurement)),
          ],
        ),
      ],
    );
  }
}

abstract class TimelineAxisPainter extends CustomPainter {
  TimelineAxisPainter({
    this.range,
    this.units,
    this.horizontal,
    int minTicks,
    int maxTicks,
  })
      : ticks = makeTicks(range, _optimalTickUnit(range, units, minTicks, maxTicks));

  static List<TimeVal> makeTicks(TimeFrame range, TimeVal tickUnit) {
    final double minTick = (range.start / tickUnit).floorToDouble() + 1;
    final double maxTick = (range.end   / tickUnit).ceilToDouble()  - 1;
    return <TimeVal>[
      for (double t = minTick; t <= maxTick; t++)
        tickUnit * t,
    ];
  }

  static TimeVal _optimalTickUnit(TimeFrame range, TimeVal proposedUnit, int minTicks, int maxTicks) {
    final int numTicks = _numTicks(range, proposedUnit);
    if (numTicks < minTicks) {
      return _optimalTickUnit(range, proposedUnit * 0.10, minTicks, maxTicks);
    }
    if (numTicks <= maxTicks) {
      return proposedUnit;
    }
    if (_numTicks(range, proposedUnit * 2) <= maxTicks) {
      return proposedUnit * 2;
    }
    if (_numTicks(range, proposedUnit * 5) <= maxTicks) {
      return proposedUnit * 5;
    }
    return _optimalTickUnit(range, proposedUnit * 10, minTicks, maxTicks);
  }

  static int _numTicks(TimeFrame range, TimeVal proposedUnit) {
    final int minTick = (range.start / proposedUnit).floor() + 1;
    final int maxTick = (range.end   / proposedUnit).ceil()  - 1;
    return maxTick - minTick + 1;
  }

  final TimeFrame range;
  final TimeVal units;
  final bool horizontal;
  final List<TimeVal> ticks;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.black;
    const TextStyle style = TextStyle(
      color: Colors.black,
    );
    for (final TimeVal t in ticks) {
      final double fraction = range.getFraction(t);
      double x, y;
      if (horizontal) {
        x = fraction * size.width;
        y = 15;
        canvas.drawLine(Offset(x, 5), Offset(x, 10), paint);
      } else {
        x = 15;
        y = (1.0 - fraction) * size.height;
        canvas.drawLine(Offset(5, y), Offset(10, y), paint);
      }
      final String label = (t / units).toString();
      final TextSpan span = TextSpan(text: label, style: style);
      final TextPainter textPainter = TextPainter(text: span);
      textPainter.layout();
      if (horizontal) {
        x -= textPainter.width / 2.0;
      } else {
        y -= textPainter.height / 2.0;
      }
      textPainter.paint(canvas, Offset(x, y));
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

class TimelineHAxisPainter extends TimelineAxisPainter {
  TimelineHAxisPainter(TimelineGraphPainter graphPainter) : super(
    range: TimeFrame(
      start: graphPainter.run.elapsedTime(graphPainter.zoom.left),
      end:   graphPainter.run.elapsedTime(graphPainter.zoom.right),
    ) - graphPainter.run.start,
    units: TimeVal.oneSecond,
    horizontal: true,
    minTicks: 10,
    maxTicks: 25,
  );
}

class TimelineVAxisPainter extends TimelineAxisPainter {
  TimelineVAxisPainter(TimelineGraphPainter graphPainter) : super(
    range: TimeFrame(
      start: graphPainter.timeline.worst * (1 - graphPainter.zoom.bottom),
      end:   graphPainter.timeline.worst * (1 - graphPainter.zoom.top),
    ),
    units: TimeVal.oneMillisecond,
    horizontal: false,
    minTicks: 4,
    maxTicks: 10,
  );
}

class TimelineGraphPainter extends CustomPainter {
  TimelineGraphPainter(this.timeline, [this.zoom = unitRect, this.showInactiveRegions = false])
      : run = timeline.wholeRun;

  static const Rect unitRect = Rect.fromLTRB(0, 0, 1, 1);

  final TimelineThreadResults timeline;
  final TimeFrame run;
  final Rect zoom;
  final bool showInactiveRegions;

  TimelineHAxisPainter _timePainter;
  TimelineHAxisPainter get timePainter => _timePainter ??= TimelineHAxisPainter(this);

  TimelineVAxisPainter _durationPainter;
  TimelineVAxisPainter get durationPainter => _durationPainter ??= TimelineVAxisPainter(this);

  double getX(TimeVal t, Rect bounds) => bounds.left + bounds.width  * run.getFraction(t);
  double getY(TimeVal d, Rect bounds) => bounds.bottom - bounds.height * (d / timeline.worst);

  Rect _getRectBar(TimeFrame f, double barY, Rect view, double minWidth) {
    double startX = getX(f.start, view);
    double endX = getX(f.end, view);
    if (minWidth > 0) {
      final double pad = minWidth - (endX - startX);
      if (pad > 0) {
        startX -= pad / 2;
        endX += pad / 2;
      }
    }
    return Rect.fromLTRB(startX, barY, endX, view.height);
  }

  Rect getRect(TimeFrame f, Rect view, double minWidth) =>
      _getRectBar(f, getY(f.duration, view), view, minWidth);
  Rect getMaxRect(TimeFrame f, Rect bounds) =>
      _getRectBar(f, 0, bounds, 0.0);

  void drawLine(Canvas canvas, Size size, Paint paint, double y, Color heatColor) {
    paint.color = heatColor.withAlpha(128);
    paint.strokeWidth = 1.0;
    const double dashLen = 10.0;
    for (double x = 0; x < size.width; x += dashLen + dashLen) {
      canvas.drawLine(Offset(x, y), Offset(x + dashLen, y), paint);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Rect view = Offset.zero & size;
    canvas.clipRect(view);

    canvas.scale(1.0 / zoom.width, 1.0 / zoom.height);
    canvas.translate(-zoom.left * size.width, -zoom.top * size.height);
    final double minWidth = zoom.width;

    final Paint paint = Paint();

    // Draw gaps first (if enabled)
    if (showInactiveRegions) {
      paint.style = PaintingStyle.fill;
      paint.color = Colors.grey.shade200;
      TimeFrame prevFrame = timeline.first;
      for (final TimeFrame frame in timeline.skip(1)) {
        final TimeFrame gap = frame.gapFrameSince(prevFrame);
        if (gap.duration.millis > 16) {
          canvas.drawRect(getMaxRect(gap, view), paint);
        }
        prevFrame = frame;
      }
    }

    // Then lines over gaps
    paint.style = PaintingStyle.stroke;
    drawLine(canvas, size, paint, getY(timeline.average,   view), heatColors[0]);
    drawLine(canvas, size, paint, getY(timeline.percent90, view), heatColors[1]);
    drawLine(canvas, size, paint, getY(timeline.percent99, view), heatColors[2]);

    // Finally frame times over lines
    paint.style = PaintingStyle.fill;
    for (final TimeFrame frame in timeline) {
      paint.color = heatColors[timeline.heatIndex(frame.duration)];
      canvas.drawRect(getRect(frame, view, minWidth), paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

class TimelineGraphWidget extends StatefulWidget {
  TimelineGraphWidget(this.timeline, this.closeCallback) : super(key: ObjectKey(timeline));

  final TimelineThreadResults timeline;
  final Function(TimelineGraphWidget) closeCallback;

  @override State createState() => TimelineGraphWidgetState(timeline);
}

class TimelineGraphWidgetState extends State<TimelineGraphWidget> {
  TimelineGraphWidgetState(this.timeline)
      : _mouseKey = GlobalKey(),
        _imageKey = GlobalKey(),
        _painter = TimelineGraphPainter(timeline),
        _hoverString = '';

  final TimelineThreadResults timeline;
  final GlobalKey _mouseKey;
  final GlobalKey _imageKey;
  FocusNode focusNode;
  Offset _dragAnchor;

  @override
  void initState() {
    super.initState();

    focusNode = FocusNode(
      onKey: (FocusNode node, RawKeyEvent event) => _onKey(event),
    );
  }

  @override
  void dispose() {
    focusNode.dispose();

    super.dispose();
  }

  TimelineGraphPainter _painter;
  Offset _zoomAnchor;
  TimeFrame _hoverFrame;
  String _hoverString;

  void _setHoverEvent(TimeFrame newHoverFrame) {
    if (_hoverFrame != newHoverFrame) {
      final TimeFrame e = newHoverFrame - timeline.wholeRun.start;
      final String start = e.start.stringSeconds();
      final String end = e.end.stringSeconds();
      final String dur = e.duration.stringMillis();
      final String label = timeline.labelFor(e.duration);
      setState(() {
        _hoverFrame = newHoverFrame;
        _hoverString = 'frame[$start => $end] = $dur ($label)';
      });
    }
  }

  Offset _getWidgetRelativePosition(Offset position) {
    final RenderBox box = _mouseKey.currentContext.findRenderObject() as RenderBox;
    final Offset mousePosition = box.globalToLocal(position);
    return Offset(mousePosition.dx / box.size.width, mousePosition.dy / box.size.height);
  }

  Offset _getViewRelativePosition(Offset position) {
    final Offset widgetRelative = _getWidgetRelativePosition(position);
    return Offset(
      _painter.zoom.left + widgetRelative.dx * _painter.zoom.width,
      _painter.zoom.top  + widgetRelative.dy * _painter.zoom.height,
    );
  }

  Rect _scaleRectAround(Rect r, Offset p, Size s) {
    // Tx(xy) == xy * s + (p - p * s)
    // Tx(p) == p * s + (p - p * s)
    //       == p * s + p - p * s
    //       == p
    // Tx(r.topLeft) == tL * s + (p - p * s)
    //               == p + (tL - p) * s
    //               == fractionBiasAtoB(p, tL, s)
    // Tx(r.botRight) == bR * s + (p - p * s)
    //                == p + (bR - p) * s
    //                == fractionBiasAtoB(p, bR, s)
    return Rect.fromLTRB(
      p.dx + (r.left   - p.dx) * s.width,
      p.dy + (r.top    - p.dy) * s.height,
      p.dx + (r.right  - p.dx) * s.width,
      p.dy + (r.bottom - p.dy) * s.height,
    );
  }

  Rect _keepInside(Rect r, Rect bounds) {
    if (r.width < bounds.width) {
      if (r.left < bounds.left) {
        r = r.shift(Offset(bounds.left - r.left, 0));
      } else if (r.right > bounds.right) {
        r = r.shift(Offset(bounds.right - r.right, 0));
      }
    } else {
      r = Rect.fromLTRB(bounds.left, r.top, bounds.right, r.bottom);
    }
    if (r.height < bounds.height) {
      if (r.top < bounds.top) {
        r = r.shift(Offset(0, bounds.top - r.top));
      } else if (r.bottom > bounds.bottom) {
        r = r.shift(Offset(0, bounds.bottom - r.bottom));
      }
    } else {
      r = Rect.fromLTRB(r.left, bounds.top, r.right, bounds.bottom);
    }
    return r;
  }

  void _onHover(Offset position) {
    final Offset relative = _getViewRelativePosition(position);
    _zoomAnchor = relative;
    final TimeVal t = timeline.wholeRun.elapsedTime(relative.dx);
    final TimeFrame e = timeline.eventNear(t);
    _setHoverEvent(e);
  }

  void _zoom(Offset relative, double scale) {
    Rect zoom = _scaleRectAround(_painter.zoom, relative, Size(scale, scale));
    zoom = _keepInside(zoom, TimelineGraphPainter.unitRect);
    setState(() => _painter = TimelineGraphPainter(timeline, zoom));
  }

  void _move(double dx, double dy) {
    Rect view = _painter.zoom.translate(_painter.zoom.width * dx, _painter.zoom.height * dy);
    view = _keepInside(view, TimelineGraphPainter.unitRect);
    setState(() => _painter = TimelineGraphPainter(timeline, view));
  }

  void _reset() {
    setState(() => _painter = TimelineGraphPainter(timeline));
  }

  bool _dragDown(Offset position) {
    if (_painter.zoom == TimelineGraphPainter.unitRect) {
      return false;
    }
    _dragAnchor = _getWidgetRelativePosition(position);
    return TimelineGraphPainter.unitRect.contains(_dragAnchor);
  }

  void _drag(Offset position) {
    final Offset newAnchor = _getWidgetRelativePosition(position);
    final Offset relative = _dragAnchor - newAnchor;
    _dragAnchor = newAnchor;
    _move(relative.dx, relative.dy);
  }

//  void _capture() async {
//    RenderRepaintBoundary boundary = _imageKey.currentContext.findRenderObject();
//    Rect bounds = boundary.paintBounds;
//    Size size = bounds.size;
//    ui.PictureRecorder recorder = ui.PictureRecorder();
//    ui.Canvas canvas = ui.Canvas(recorder, bounds);
//    _painter.paint(canvas, size);
//    ui.Picture picture = recorder.endRecording();
//    ui.Image img = await picture.toImage(size.width.ceil(), size.height.ceil());
//    ByteData bytes = await img.toByteData(format: ui.ImageByteFormat.png);
//    final _base64 = base64Encode(Uint8List.sublistView(bytes));
//    // Create the link with the file
//    final anchor = AnchorElement(href: 'data:application/octet-stream;base64,$_base64')
//      ..target = 'blank'
//      ..download = 'test.png';
//    // trigger download
//    document.body.append(anchor);
//    anchor.click();
//    anchor.remove();
//  }

  bool _onKey(RawKeyEvent keyEvent) {
    if (keyEvent is RawKeyDownEvent) {
      if (keyEvent.logicalKey.keyLabel == 'r') {
        _reset();
      } else if (keyEvent.logicalKey.keyLabel == 'w') {
        _move(0.0, -0.1);
      } else if (keyEvent.logicalKey.keyLabel == 'a') {
        _move(-0.1, 0.0);
      } else if (keyEvent.logicalKey.keyLabel == 's') {
        _move(0.0, 0.1);
      } else if (keyEvent.logicalKey.keyLabel == 'd') {
        _move(0.1, 0.0);
      } else if (keyEvent.logicalKey.keyLabel == '=') {
        _zoom(_zoomAnchor, 0.8);
      } else if (keyEvent.logicalKey.keyLabel == '-') {
        _zoom(_zoomAnchor, 1/0.8);
//      } else if (keyEvent.logicalKey.keyLabel == 'c') {
//        _capture();
      } else {
        print('unrecognized: ${keyEvent.logicalKey.keyLabel}');
        return false;
      }
      return true;
    } else {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget theGraph = CustomPaint(
      isComplex: true,
      willChange: false,
      child: Container(
        height: 200,
        key: _mouseKey,
      ),
      painter: _painter,
    );
    final Widget timeAxis = CustomPaint(
      isComplex: true,
      willChange: false,
      child: Container(height: 30),
      painter: _painter.timePainter,
    );
    final Widget durationAxis = CustomPaint(
      isComplex: true,
      willChange: false,
      child: Container(height: 200),
      painter: _painter.durationPainter,
    );

    final Widget annotatedGraph = MouseRegion(
      onEnter: (_) => focusNode.requestFocus(),
      onExit: (_) => focusNode.unfocus(),
      onHover: (PointerHoverEvent e) => _onHover(e.position),
      child: RawKeyboardListener(
        focusNode: focusNode,
        child: ForcedPanDetector(
          onDoubleTap: _reset,
          onPanDown: _dragDown,
          onPanUpdate: _drag,
          child: theGraph,
        ),
      ),
    );

    Row _makeLegendItem(String name, TimeVal value, Color color) {
      return Row(
        children: <Widget>[
          Container(alignment: Alignment.center, color: color, width: 12, height: 12,),
          Container(width: 10),
          Text('$name: ${value.stringMillis()}'),
        ],
      );
    }
    final Row legend = Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: <Widget>[
        _makeLegendItem('average value',   timeline.average,   heatColors[0]),
        _makeLegendItem('90th percentile', timeline.percent90, heatColors[1]),
        _makeLegendItem('99th percentile', timeline.percent99, heatColors[2]),
        _makeLegendItem('worst value',     timeline.worst,     heatColors[3]),
      ],
    );

    return RepaintBoundary(
      key: _imageKey,
      child: Column(
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text('Frame ${timeline.titleName} Times', style: const TextStyle(fontSize: 24),),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => widget.closeCallback(widget),
              ),
            ]
          ),
          Text(_hoverString),

          // Table layout:
          //  +---------------------+---+
          //  |                     | v |
          //  |                     | A |
          //  |        Graph        | x |
          //  |                     | i |
          //  |                     | s |
          //  +---------------------+---+
          //  |        hAxis        |   |
          //  +---------------------+---+
          //  +---------------------+---+
          //  |  legend1...legend4  |   |
          //  +---------------------+---+
          Table(
            columnWidths: const <int, TableColumnWidth>{
              0: FractionColumnWidth(0.8),
              1: FixedColumnWidth(50.0),
            },
            children: <TableRow>[
              // Main graph and vertical axis aligned to right of graph
              TableRow(
                children: <Widget>[
                  annotatedGraph,
                  durationAxis,
                ],
              ),
              // Horizontal axis aligned below graph
              TableRow(
                children: <Widget>[
                  timeAxis,
                  Container(),
                ],
              ),
              // Spacer
              TableRow(
                children: <Widget>[
                  Container(height: 15),
                  Container(),
                ],
              ),
              // Legend below graph
              TableRow(
                children: <Widget>[
                  legend,
                  Container(),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ForcedPanDetector extends StatelessWidget {
  const ForcedPanDetector({
    @required this.child,
    @required this.onPanDown,
    @required this.onPanUpdate,
    this.onPanEnd = defaultEnd,
    this.onDoubleTap,
  })
      : assert(child != null),
        assert(onPanDown != null),
        assert(onPanUpdate != null);

  final bool Function(Offset) onPanDown;
  final Function(Offset) onPanUpdate;
  final Function(Offset) onPanEnd;
  final Function onDoubleTap;
  final Widget child;

  static void defaultEnd(Offset o) {}

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      gestures: <Type,GestureRecognizerFactory>{
        CustomPanGestureRecognizer:
        GestureRecognizerFactoryWithHandlers<CustomPanGestureRecognizer>(
              () => CustomPanGestureRecognizer(this),
              (CustomPanGestureRecognizer instance) {},
        ),
      },
      child: child,
    );
  }
}

class CustomPanGestureRecognizer extends OneSequenceGestureRecognizer {
  CustomPanGestureRecognizer(this._detector) : super(debugOwner: _detector);

  final ForcedPanDetector _detector;
  Duration _doubleTapTimestamp;

  @override
  void addPointer(PointerDownEvent event) {
    if (_detector.onPanDown(event.position)) {
      if (_doubleTapTimestamp != null && event.timeStamp - _doubleTapTimestamp < kDoubleTapTimeout) {
        _detector.onDoubleTap();
        _doubleTapTimestamp = null;
        stopTrackingPointer(event.pointer);
      } else {
        if (_detector.onDoubleTap != null) {
          _doubleTapTimestamp = event.timeStamp;
        }
        startTrackingPointer(event.pointer);
        resolve(GestureDisposition.accepted);
      }
    } else {
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      _detector.onPanUpdate(event.position);
    } else if (event is PointerUpEvent) {
      _detector.onPanEnd(event.position);
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'CustomPanRecognizer';
}
