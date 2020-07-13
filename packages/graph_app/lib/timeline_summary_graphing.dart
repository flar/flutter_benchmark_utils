// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'time_utils.dart';
import 'timeline_summary.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

final List<Color> heatColors = [
  Colors.green,
  Colors.green.shade200,
  Colors.yellow.shade600,
  Colors.red,
];

class TimelineResultsGraphWidget extends StatelessWidget {
  TimelineResultsGraphWidget(this.results)
      : this.worst = TimeVal.max(results.buildData.worst, results.renderData.worst),
        assert(results != null);

  final TimelineResults results;
  final TimeVal worst;

  TableRow _makeTableRow(String name, TimeVal value, Color color) {
    return TableRow(
      children: [
        Container(
          padding: EdgeInsets.only(right: 5.0, top: 10.0),
          child: Text(name, textAlign: TextAlign.right),
        ),
        Container(
          padding: EdgeInsets.only(left: 5.0, top: 10.0),
          child: Text(value.stringMillis()),
        ),
        Container(
          alignment: Alignment.centerLeft,
          padding: EdgeInsets.only(left: 5.0, top: 10.0),
          width: 100.0,
          height: 20.0,
          child: FractionallySizedBox(
            widthFactor: value / worst,
            child: Container(
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  List<TableRow> _makeTableRows(TimelineThreadResults tr) {
    return <TableRow>[
      _makeTableRow(tr.threadInfo.averageKey,   tr.average,   heatColors[0]),
      _makeTableRow(tr.threadInfo.percent90Key, tr.percent90, heatColors[1]),
      _makeTableRow(tr.threadInfo.percent99Key, tr.percent99, heatColors[2]),
      _makeTableRow(tr.threadInfo.worstKey,     tr.worst,     heatColors[3]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        Table(
          columnWidths: {
            0: FixedColumnWidth(300.0),
            1: FixedColumnWidth(200.0),
            2: FixedColumnWidth(300.0),
          },
          children: <TableRow>[
            ..._makeTableRows(results.buildData),
            ..._makeTableRows(results.renderData),
          ],
        ),
        TimelineGraphWidget(results.buildData),
        TimelineGraphWidget(results.renderData),
      ],
    );
  }
}

abstract class TimelineAxisPainter extends CustomPainter {
  TimelineAxisPainter(this.graphPainter, this.range, this.baseline, this.units, this.horizontal, int maxTicks)
      : ticks = makeTicks(range, baseline, units, maxTicks);

  static List<TimeVal> makeTicks(TimeFrame range, TimeVal baseline, TimeVal units, int maxTicks) {
    TimeVal adjUnit = _optimalTickUnit(range, units, maxTicks);
    double minTick = ((range.start - baseline) / adjUnit).floorToDouble() + 1;
    double maxTick = ((range.end   - baseline) / adjUnit).ceilToDouble()  - 1;
    return <TimeVal>[
      for (double t = minTick; t <= maxTick; t++)
        adjUnit * t,
    ];
  }

  static TimeVal _optimalTickUnit(TimeFrame range, TimeVal proposedUnit, int maxTicks) {
    if (_isTickUnitOptimal(range, proposedUnit, maxTicks)) return proposedUnit;
    if (_isTickUnitOptimal(range, proposedUnit * 2, maxTicks)) return proposedUnit * 2;
    if (_isTickUnitOptimal(range, proposedUnit * 5, maxTicks)) return proposedUnit * 5;
    return _optimalTickUnit(range, proposedUnit * 10, maxTicks);
  }

  static bool _isTickUnitOptimal(TimeFrame range, TimeVal proposedUnit, int maxTicks) {
    double minTick = (range.start / proposedUnit).floorToDouble() + 1;
    double maxTick = (range.end   / proposedUnit).ceilToDouble()  - 1;
    return (maxTick - minTick + 1 <= maxTicks);
  }

  final TimelineGraphPainter graphPainter;
  final TimeFrame range;
  final TimeVal baseline;
  final TimeVal units;
  final bool horizontal;
  final List<TimeVal> ticks;

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = Colors.black;
    TextStyle style = TextStyle(
      color: Colors.black,
    );
    for (TimeVal t in ticks) {
      double fraction = range.getFraction(baseline + t);
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
      String label = (t / units).toStringAsFixed(1);
      TextSpan span = new TextSpan(text: label, style: style);
      TextPainter textPainter = TextPainter(text: span);
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
    graphPainter,
    TimeFrame(
      start: graphPainter.run.elapsedTime(graphPainter.zoom.left),
      end:   graphPainter.run.elapsedTime(graphPainter.zoom.right),
    ),
    graphPainter.run.start,
    TimeVal.oneSecond,
    true,
    25,
  );
}

class TimelineVAxisPainter extends TimelineAxisPainter {
  TimelineVAxisPainter(TimelineGraphPainter graphPainter) : super(
    graphPainter,
    TimeFrame(
      start: graphPainter.timeline.worst * (1 - graphPainter.zoom.bottom),
      end:   graphPainter.timeline.worst * (1 - graphPainter.zoom.top),
    ),
    TimeVal.zero,
    TimeVal.oneMillisecond,
    false,
    10,
  );
}

class TimelineGraphPainter extends CustomPainter {
  static const Rect unitRect = Rect.fromLTRB(0, 0, 1, 1);

  TimelineGraphPainter(this.timeline, [this.zoom = unitRect])
      : run = timeline.wholeRun;

  final TimelineThreadResults timeline;
  final TimeFrame run;
  final Rect zoom;

  TimelineHAxisPainter _timePainter;
  TimelineHAxisPainter get timePainter => _timePainter ??= TimelineHAxisPainter(this);

  TimelineVAxisPainter _durationPainter;
  TimelineVAxisPainter get durationPainter => _durationPainter ??= TimelineVAxisPainter(this);

  double getX(TimeVal t, Rect bounds) => bounds.left + bounds.width  * run.getFraction(t);
  double getY(TimeVal d, Rect bounds) => bounds.bottom - bounds.height * (d / timeline.worst);

  Rect _getRectBar(TimeFrame f, double barY, Rect view) =>
      Rect.fromLTRB(getX(f.start, view), barY, getX(f.end, view), view.height);

  Rect getRect(TimeFrame f, Rect view) => _getRectBar(f, getY(f.duration, view), view);
  Rect getMaxRect(TimeFrame f, Rect bounds) => _getRectBar(f, 0, bounds);

  void drawLine(Canvas canvas, Size size, Paint paint, double y, Color heatColor) {
    paint.color = heatColor.withAlpha(128);
    paint.strokeWidth = 1.0;
    double dashLen = 10.0;
    for (double x = 0; x < size.width; x += dashLen + dashLen) {
      canvas.drawLine(Offset(x, y), Offset(x + dashLen, y), paint);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    Rect view = Offset.zero & size;
    canvas.clipRect(view);

    canvas.scale(1.0 / zoom.width, 1.0 / zoom.height);
    canvas.translate(-zoom.left * size.width, -zoom.top * size.height);

    Paint paint = Paint();

    // Draw gaps first
    paint.style = PaintingStyle.fill;
    paint.color = Colors.grey.shade200;
    TimeFrame prevFrame = timeline.first;
    for (TimeFrame frame in timeline.skip(1)) {
      TimeFrame gap = frame.gapFrameSince(prevFrame);
      if (gap.duration.millis > 16) {
        canvas.drawRect(getMaxRect(gap, view), paint);
      }
      prevFrame = frame;
    }

    // Then lines over gaps
    paint.style = PaintingStyle.stroke;
    drawLine(canvas, size, paint, getY(timeline.average,   view), heatColors[0]);
    drawLine(canvas, size, paint, getY(timeline.percent90, view), heatColors[1]);
    drawLine(canvas, size, paint, getY(timeline.percent99, view), heatColors[2]);

    // Finally frame times over lines
    paint.style = PaintingStyle.fill;
    for (TimeFrame frame in timeline) {
      paint.color = heatColors[timeline.heatIndex(frame.duration)];
      canvas.drawRect(getRect(frame, view), paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

class TimelineGraphWidget extends StatefulWidget {
  TimelineGraphWidget(this._timeline);

  final TimelineThreadResults _timeline;

  @override
  State createState() => TimelineGraphWidgetState(_timeline);
}

class TimelineGraphWidgetState extends State<TimelineGraphWidget> {
  TimelineGraphWidgetState(this._timeline)
      : _mouseKey = GlobalKey(),
        _imageKey = GlobalKey(),
        _painter = TimelineGraphPainter(_timeline),
        _hoverString = '';

  final TimelineThreadResults _timeline;
  final GlobalKey _mouseKey;
  final GlobalKey _imageKey;
  FocusNode focusNode;
  Offset _dragAnchor;

  @override
  void initState() {
    super.initState();

    focusNode = FocusNode(
      onKey: (node, event) => _onKey(event),
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

  void _setHoverEvent(TimeFrame e) {
    if (_hoverFrame != e) {
      String start = e.start.stringSeconds();
      String end = e.end.stringSeconds();
      String dur = e.duration.stringMillis();
      String label = _timeline.labelFor(e.duration);
      setState(() {
        _hoverFrame = e;
        _hoverString = 'frame[$start => $end] = $dur ($label)';
      });
    }
  }

  Offset _getWidgetRelativePosition(Offset position) {
    RenderBox box = _mouseKey.currentContext.findRenderObject();
    Offset mousePosition = box.globalToLocal(position);
    return Offset(mousePosition.dx / box.size.width, mousePosition.dy / box.size.height);
  }

  Offset _getViewRelativePosition(Offset position) {
    Offset widgetRelative = _getWidgetRelativePosition(position);
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
    Offset relative = _getViewRelativePosition(position);
    _zoomAnchor = relative;
    TimeVal t = _timeline.wholeRun.elapsedTime(relative.dx);
    TimeFrame e = _timeline.eventNear(t);
    _setHoverEvent(e);
  }

  void _zoom(Offset relative, double scale) {
    Rect zoom = _scaleRectAround(_painter.zoom, relative, Size(scale, scale));
    zoom = _keepInside(zoom, TimelineGraphPainter.unitRect);
    setState(() => _painter = TimelineGraphPainter(_timeline, zoom));
  }

  void _move(double dx, double dy) {
    Rect view = _painter.zoom.translate(_painter.zoom.width * dx, _painter.zoom.height * dy);
    view = _keepInside(view, TimelineGraphPainter.unitRect);
    setState(() => _painter = TimelineGraphPainter(_timeline, view));
  }

  void _reset() {
    setState(() => _painter = TimelineGraphPainter(_timeline));
  }

  void _dragDown(Offset position) {
    _dragAnchor = _getWidgetRelativePosition(position);
  }

  void _drag(Offset position) {
    Offset newAnchor = _getWidgetRelativePosition(position);
    Offset relative = _dragAnchor - newAnchor;
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
    Widget theGraph = CustomPaint(
      isComplex: true,
      willChange: false,
      child: Container(
        height: 200,
        key: _mouseKey,
      ),
      painter: _painter,
    );
    Widget timeAxis = CustomPaint(
      isComplex: true,
      willChange: false,
      child: Container(height: 30),
      painter: _painter.timePainter,
    );
    Widget durationAxis = CustomPaint(
      isComplex: true,
      willChange: false,
      child: Container(height: 200),
      painter: _painter.durationPainter,
    );

    Widget annotatedGraph = MouseRegion(
      onEnter: (_) => focusNode.requestFocus(),
      onExit: (_) => focusNode.unfocus(),
      onHover: (e) => _onHover(e.position),
      child: RawKeyboardListener(
        focusNode: focusNode,
        child: GestureDetector(
          onDoubleTap: _reset,
          onPanDown: (e) => _dragDown(e.globalPosition),
          onPanUpdate: (e) => _drag(e.globalPosition),
          child: theGraph,
        ),
      ),
    );

    return RepaintBoundary(
      key: _imageKey,
      child: Column(
        children: <Widget>[
          Text('Frame ${_timeline.threadInfo.titleName} Times', style: TextStyle(fontSize: 24),),
          Text(_hoverString),
          Table(
            columnWidths: <int, TableColumnWidth>{
              0: FractionColumnWidth(0.8),
              1: FixedColumnWidth(50),
            },
            children: <TableRow>[
              TableRow(
                children: <Widget>[
                  annotatedGraph,
                  durationAxis,
                ],
              ),
              TableRow(
                children: <Widget>[
                  timeAxis,
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
