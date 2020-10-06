// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_benchmark_utils/benchmark_data.dart';

import 'input_utils.dart';

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
    this.rangeMin,
    this.rangeMax,
    this.units,
    this.horizontal,
    int minTicks,
    int maxTicks,
  })
      : ticks = makeTicks(rangeMin, rangeMax, _optimalTickUnit(rangeMin, rangeMax, 1.0, minTicks, maxTicks));

  static List<double> makeTicks(double rangeMin, double rangeMax, double tickUnit) {
    final double minTick = (rangeMin / tickUnit).floorToDouble() + 1;
    final double maxTick = (rangeMax / tickUnit).ceilToDouble()  - 1;
    return <double>[
      for (double t = minTick; t <= maxTick; t++)
        tickUnit * t,
    ];
  }

  static double _optimalTickUnit(double rangeMin, double rangeMax, double proposedUnit, int minTicks, int maxTicks) {
    final int numTicks = _numTicks(rangeMin, rangeMax, proposedUnit);
    if (numTicks < minTicks) {
      return _optimalTickUnit(rangeMin, rangeMax, proposedUnit * 0.10, minTicks, maxTicks);
    }
    if (numTicks <= maxTicks) {
      return proposedUnit;
    }
    if (_numTicks(rangeMin, rangeMax, proposedUnit * 2) <= maxTicks) {
      return proposedUnit * 2;
    }
    if (_numTicks(rangeMin, rangeMax, proposedUnit * 5) <= maxTicks) {
      return proposedUnit * 5;
    }
    return _optimalTickUnit(rangeMin, rangeMax, proposedUnit * 10, minTicks, maxTicks);
  }

  static int _numTicks(double rangeMin, double rangeMax, double proposedUnit) {
    final int minTick = (rangeMin / proposedUnit).floor() + 1;
    final int maxTick = (rangeMax / proposedUnit).ceil()  - 1;
    return maxTick - minTick + 1;
  }

  final double rangeMin;
  final double rangeMax;
  final String units;
  final bool horizontal;
  final List<double> ticks;

  String _formatTick(double v) {
    String str = v.toStringAsFixed(3);
    if (str.contains('.')) {
      while (str.endsWith('00')) {
        str = str.substring(0, str.length - 1);
      }
    }
    return str;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.black;
    const TextStyle style = TextStyle(
      color: Colors.black,
    );
    for (final double t in ticks) {
      final double fraction = (t - rangeMin) / (rangeMax - rangeMin);
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
      final String label = '${_formatTick(t)}$units';
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

class TimelineHAxisTimePainter extends TimelineAxisPainter {
  TimelineHAxisTimePainter(TimelineGraphPainter graphPainter) : super(
    rangeMin: graphPainter.run.duration.seconds * graphPainter.zoom.left,
    rangeMax: graphPainter.run.duration.seconds * graphPainter.zoom.right,
    units: 's',
    horizontal: true,
    minTicks: 10,
    maxTicks: 25,
  );
}

class TimelineVAxisDurationPainter extends TimelineAxisPainter {
  TimelineVAxisDurationPainter(TimelinePainter graphPainter) : super(
    rangeMin: graphPainter.timeline.maxValue * (1 - graphPainter.zoom.bottom),
    rangeMax: graphPainter.timeline.maxValue * (1 - graphPainter.zoom.top),
    units: graphPainter.timeline.frames.first.reading.units,
    horizontal: false,
    minTicks: 4,
    maxTicks: 10,
  );
}

class TimelineAxisPercentPainter extends TimelineAxisPainter {
  TimelineAxisPercentPainter(Rect view, bool horizontal) : super(
    rangeMin: 100 * (horizontal ? view.left : view.top),
    rangeMax: 100 * (horizontal ? view.right : view.bottom),
    units: '%',
    horizontal: horizontal,
    minTicks: 4,
    maxTicks: 10,
  );
}

const Rect unitRect = Rect.fromLTRB(0, 0, 1, 1);

abstract class TimelinePainter extends CustomPainter {
  TimelinePainter(this.timeline, [this.zoom = unitRect]);

  final TimelineThreadResults timeline;
  final Rect zoom;

  TimelineAxisPainter horizontalAxisPainter;
  TimelineAxisPainter verticalAxisPainter;

  TimelinePainter withZoom(Rect newZoom);

  double getY(double d, Rect bounds) => bounds.bottom - bounds.height * (d / timeline.maxValue);

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

class TimelineGraphPainter extends TimelinePainter {
  TimelineGraphPainter(TimelineThreadResults timeline, {
    Rect zoom = unitRect,
    this.showInactiveRegions = false,
  })
      : run = timeline.wholeRun,
        super(timeline, zoom);

  final TimeFrame run;
  final bool showInactiveRegions;

  TimelineHAxisTimePainter _timePainter;
  @override
  TimelineAxisPainter get horizontalAxisPainter => _timePainter ??= TimelineHAxisTimePainter(this);

  TimelineVAxisDurationPainter _durationPainter;
  @override
  TimelineAxisPainter get verticalAxisPainter => _durationPainter ??= TimelineVAxisDurationPainter(this);

  @override
  TimelineGraphPainter withZoom(Rect newZoom) =>
      TimelineGraphPainter(timeline,
        zoom: newZoom ?? unitRect,
        showInactiveRegions: showInactiveRegions,
      );

  double getX(TimeVal t, Rect bounds) => bounds.left + bounds.width  * run.getFraction(t);

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

  Rect getRect(GraphableEvent f, Rect view, double minWidth) =>
      _getRectBar(f, getY(f.reading.value, view), view, minWidth);
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
    drawLine(canvas, size, paint, getY(timeline.average.value,   view), heatColors[0]);
    drawLine(canvas, size, paint, getY(timeline.percent90.value, view), heatColors[1]);
    drawLine(canvas, size, paint, getY(timeline.percent99.value, view), heatColors[2]);

    // Finally frame times over lines
    paint.style = PaintingStyle.fill;
    for (final GraphableEvent frame in timeline) {
      paint.color = heatColors[timeline.heatIndex(frame)];
      canvas.drawRect(getRect(frame, view, minWidth), paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

class TimelineDistributionPainter extends TimelinePainter {
  TimelineDistributionPainter(TimelineThreadResults timeline, {
    Rect zoom = unitRect,
  })
      : run = timeline.wholeRun,
        indices = List<int>.generate(timeline.frames.length, (int index) => index),
        super(timeline, zoom) {
    indices.sort((int a, int b) {
      return timeline.frames[a].reading.value.compareTo(timeline.frames[b].reading.value);
    });
  }

  final TimeFrame run;
  final List<int> indices;

  TimelineAxisPercentPainter _timePainter;
  @override
  TimelineAxisPainter get horizontalAxisPainter =>
      _timePainter ??= TimelineAxisPercentPainter(zoom, true);

  TimelineVAxisDurationPainter _durationPainter;
  @override
  TimelineAxisPainter get verticalAxisPainter => _durationPainter ??= TimelineVAxisDurationPainter(this);

  @override
  TimelineDistributionPainter withZoom(Rect newZoom) =>
      TimelineDistributionPainter(timeline,
        zoom: newZoom ?? unitRect,
      );

  @override
  void paint(Canvas canvas, Size size) {
    final Rect view = Offset.zero & size;
    canvas.clipRect(view);

    canvas.translate(0, size.height);
    canvas.scale(size.width / indices.length, -size.height / timeline.maxValue);
    // coordinates now go from BL(0, 0) to TR(#indices, worst)

    canvas.scale(1.0 / zoom.width, 1.0 / zoom.height);
    canvas.translate(-zoom.left * indices.length, (zoom.bottom - 1) * timeline.maxValue);

    final Paint paint = Paint();

    final int i0 = (zoom.left * indices.length).floor();
    final int i1 = (zoom.right * indices.length).ceil();
    for (int i = i0; i < i1; i++) {
      final GraphableEvent frame = timeline.frames[indices[i]];
      paint.color = heatColors[timeline.heatIndex(frame)];
      final double x = i.toDouble();
      canvas.drawRect(Rect.fromLTRB(x, 0, x+1, frame.reading.value), paint);
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
        _distribution = false,
        _painter = TimelineGraphPainter(timeline),
        _hoverString = '';

  final TimelineThreadResults timeline;
  final GlobalKey _mouseKey;
  final GlobalKey _imageKey;
  FocusNode focusNode;
  Offset _dragAnchor;
  bool _distribution;

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

  TimelinePainter _painter;
  Offset _zoomAnchor;
  GraphableEvent _hoverFrame;
  String _hoverString;

  void _setHoverEvent(GraphableEvent newHoverFrame) {
    if (_hoverFrame != newHoverFrame) {
      final TimeFrame e = newHoverFrame - timeline.wholeRun.start;
      final String start = e.start.stringSeconds();
      final String end = e.end.stringSeconds();
      final String value = newHoverFrame.reading.valueString;
      final String label = timeline.labelFor(newHoverFrame);
      setState(() {
        _hoverFrame = newHoverFrame;
        _hoverString = 'frame[$start => $end] = $value ($label)';
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
    final GraphableEvent e = timeline.eventNear(t);
    _setHoverEvent(e);
  }

  void _setDistribution(bool newDistribution) {
    setState(() {
      _distribution = newDistribution;
      _painter = _distribution
          ? TimelineDistributionPainter(timeline)
          : TimelineGraphPainter(timeline);
    });
  }

  void _setZoom(Rect newZoom) {
    setState(() {
      _painter = _painter.withZoom(_keepInside(newZoom, unitRect));
    });
  }

  void _zoom(Offset relative, double scale) {
    _setZoom(_scaleRectAround(_painter.zoom, relative, Size(scale, scale)));
  }

  void _move(double dx, double dy) {
    _setZoom(_painter.zoom.translate(_painter.zoom.width * dx, _painter.zoom.height * dy));
  }

  void _reset() {
    _setZoom(unitRect);
  }

  bool _dragDown(Offset position) {
    if (_painter.zoom == unitRect) {
      return false;
    }
    _dragAnchor = _getWidgetRelativePosition(position);
    return unitRect.contains(_dragAnchor);
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
    final Widget horizontalAxis = CustomPaint(
      isComplex: true,
      willChange: false,
      child: Container(height: 30),
      painter: _painter.horizontalAxisPainter,
    );
    final Widget verticalAxis = CustomPaint(
      isComplex: true,
      willChange: false,
      child: Container(height: 200),
      painter: _painter.verticalAxisPainter,
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

    Row _makeLegendItem(String name, UnitValue value, Color color) {
      return Row(
        children: <Widget>[
          Container(alignment: Alignment.center, color: color, width: 12, height: 12,),
          Container(width: 10),
          Text('$name: ${value.valueString}'),
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
              Checkbox(
                value: _distribution,
                onChanged: (bool value) => _setDistribution(value),
              ),
              const Text('Distribution style graph'),
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
                  verticalAxis,
                ],
              ),
              // Horizontal axis aligned below graph
              TableRow(
                children: <Widget>[
                  horizontalAxis,
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
