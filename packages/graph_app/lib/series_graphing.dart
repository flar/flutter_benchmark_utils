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

class SeriesSourceGraphWidget extends StatefulWidget {
  const SeriesSourceGraphWidget(this.source);

  final GraphableSeriesSource source;

  @override
  State createState() => SeriesSourceGraphWidgetState();
}

class SeriesSourceGraphWidgetState extends State<SeriesSourceGraphWidget> {
  ScrollController? _controller;
  late List<SeriesGraphWidget> _graphWidgets;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    _graphWidgets = widget.source.defaultGraphs.map(_widgetFor).toList();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  void _closeGraph(SeriesGraphWidget widget) {
    setState(() => _graphWidgets.remove(widget));
  }

  SeriesGraphWidget _widgetFor(GraphableSeries series) {
    return SeriesGraphWidget(series, _closeGraph);
  }

  void _addGraph(String seriesName) {
    setState(() => _graphWidgets.add(_widgetFor(widget.source.seriesFor(seriesName))));
  }

  bool isGraphed(String seriesName) {
    return _graphWidgets.any((SeriesGraphWidget graph) => graph.series.titleName == seriesName);
  }
  bool isNotGraphed(String seriesName) => !isGraphed(seriesName);

  @override
  Widget build(BuildContext context) {
    final Iterable<String> remainingSeriesNames = widget.source.allSeriesNames.where(isNotGraphed);
    return Stack(
      children: <Widget>[
        Container(
          child: SingleChildScrollView(
            controller: _controller,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (SeriesGraphWidget graph in _graphWidgets)
                  Container(
                    margin: const EdgeInsets.only(top: 20, bottom: 20),
                    child: graph,
                  ),
                Container(
                  margin: const EdgeInsets.only(top: 20, bottom: 20),
                  child: AdditionalSeriesWidget(remainingSeriesNames, _addGraph),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class AdditionalSeriesWidget extends StatelessWidget {
  const AdditionalSeriesWidget(this.seriesNames, this.addCallback);

  final Iterable<String> seriesNames;
  final void Function(String)? addCallback;

  void _callback(String? name) {
    if (name != null && addCallback != null) {
      addCallback!(name);
    }
  }
  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        DropdownButton<String>(
          icon: const Icon(Icons.add),
          onChanged:  addCallback == null ? null : _callback,
          hint: const Text('Add a new graph'),
          items: <DropdownMenuItem<String>>[
            for (String name in seriesNames)
              DropdownMenuItem<String>(value: name, child: Text(name)),
          ],
        ),
      ],
    );
  }
}

abstract class GraphAxisPainter extends CustomPainter {
  GraphAxisPainter({
    required this.rangeMin,
    required this.rangeMax,
    required this.horizontal,
    required int minTicks,
    required int maxTicks,
  })
      : ticks = makeTicks(rangeMin, rangeMax, _optimalTickUnit(rangeMin.value, rangeMax.value, 1.0, minTicks, maxTicks));

  static List<UnitValue> makeTicks(UnitValue rangeMin, UnitValue rangeMax, double tickUnit) {
    final double minTick = (rangeMin.value / tickUnit).floorToDouble() + 1;
    final double maxTick = (rangeMax.value / tickUnit).ceilToDouble()  - 1;
    final Units units = rangeMin.units;
    return <UnitValue>[
      for (double t = minTick; t <= maxTick; t++)
        units.value(tickUnit * t),
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

  final UnitValue rangeMin;
  final UnitValue rangeMax;
  final bool horizontal;
  final List<UnitValue> ticks;

  // String _formatTick(double v) {
  //   String str = v.toStringAsFixed(3);
  //   if (str.contains('.')) {
  //     while (str.endsWith('00')) {
  //       str = str.substring(0, str.length - 1);
  //     }
  //   }
  //   return str;
  // }

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.black;
    const TextStyle style = TextStyle(
      color: Colors.black,
    );
    final Units units = rangeMin.units;
    final UnitValueFormatter formatter = units.rangeFormatter(rangeMin, rangeMax);
    for (final UnitValue t in ticks) {
      final double fraction = (t.value - rangeMin.value) / (rangeMax.value - rangeMin.value);
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
      final String label = formatter.format(t, precision: 3);
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

class GraphHAxisTimePainter extends GraphAxisPainter {
  GraphHAxisTimePainter(TimeFrame run, Rect zoom) : super(
    rangeMin: TimeUnits.seconds(run.duration.seconds * zoom.left),
    rangeMax: TimeUnits.seconds(run.duration.seconds * zoom.right),
    horizontal: true,
    minTicks: 10,
    maxTicks: 25,
  );
}

class GraphVAxisDurationPainter extends GraphAxisPainter {
  GraphVAxisDurationPainter(SeriesPainter graphPainter) : super(
    rangeMin: graphPainter.series.maxValue * (1 - graphPainter.zoom.bottom),
    rangeMax: graphPainter.series.maxValue * (1 - graphPainter.zoom.top),
    horizontal: false,
    minTicks: 4,
    maxTicks: 10,
  );
}

class GraphAxisPercentPainter extends GraphAxisPainter {
  GraphAxisPercentPainter(Rect view, bool horizontal) : super(
    rangeMin: PercentUnits.fraction(horizontal ? view.left : view.top),
    rangeMax: PercentUnits.fraction(horizontal ? view.right : view.bottom),
    horizontal: horizontal,
    minTicks: 4,
    maxTicks: 10,
  );
}

const Rect unitRect = Rect.fromLTRB(0, 0, 1, 1);

abstract class SeriesPainter extends CustomPainter {
  SeriesPainter(this.series, [this.zoom = unitRect]);

  final GraphableSeries series;
  final Rect zoom;

  GraphAxisPainter get horizontalAxisPainter;
  GraphAxisPainter? get verticalAxisPainter;

  SeriesPainter withZoom(Rect newZoom);

  double getY(double d, Rect bounds) => bounds.bottom - bounds.height * (d / series.maxValue.value);

  GraphableEvent eventNear(Offset graphRelative);

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

class SeriesGraphPainter extends SeriesPainter {
  SeriesGraphPainter(GraphableSeries series, {
    Rect zoom = unitRect,
    this.showInactiveRegions = false,
  })
      : run = series.wholeRun,
        super(series, zoom);

  final TimeFrame run;
  final bool showInactiveRegions;

  // GraphableEvent? _find(TimeVal t, bool strict) {
  //   TimeVal loT = run.start;
  //   TimeVal hiT = run.end;
  //   final List<GraphableEvent> frames = series.frames;
  //   if (t < loT) {
  //     return strict ? null : frames.first;
  //   }
  //   if (t > hiT) {
  //     return strict ? null : frames.last;
  //   }
  //   int lo = 0;
  //   int hi = frames.length - 1;
  //   while (lo < hi) {
  //     final int mid = (lo + hi) ~/ 2;
  //     if (mid == lo) {
  //       break;
  //     }
  //     final TimeVal midT = frames[mid].start;
  //     if (t < midT) {
  //       hi = mid;
  //       hiT = midT;
  //     } else if (t > midT) {
  //       lo = mid;
  //       loT = midT;
  //     }
  //   }
  //   final GraphableEvent loEvent = frames[lo];
  //   if (loEvent.contains(t)) {
  //     return loEvent;
  //   }
  //   if (strict) {
  //     return null;
  //   } else {
  //     if (lo >= frames.length) {
  //       return loEvent;
  //     }
  //     final GraphableEvent hiEvent = frames[lo + 1];
  //     return (t - loEvent.end < hiEvent.start - t) ? loEvent : hiEvent;
  //   }
  // }

  @override GraphableEvent eventNear(Offset graphRelative) =>
      series.eventNear(series.wholeRun.elapsedTime(graphRelative.dx));

  late final GraphHAxisTimePainter _timePainter = GraphHAxisTimePainter(run, zoom);
  @override
  GraphAxisPainter get horizontalAxisPainter => _timePainter;

  late final GraphVAxisDurationPainter _durationPainter = GraphVAxisDurationPainter(this);
  @override
  GraphAxisPainter get verticalAxisPainter => _durationPainter;

  @override
  SeriesGraphPainter withZoom(Rect newZoom) =>
      SeriesGraphPainter(series,
        zoom: newZoom,
        showInactiveRegions: showInactiveRegions,
      );

  double getX(TimeVal t, Rect bounds) => bounds.left + bounds.width * run.getFraction(t);

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
      TimeFrame prevFrame = series.frames.first;
      for (final TimeFrame frame in series.skip(1)) {
        final TimeFrame gap = frame.gapFrameSince(prevFrame);
        if (gap.duration.millis > 16) {
          canvas.drawRect(getMaxRect(gap, view), paint);
        }
        prevFrame = frame;
      }
    }

    // Then lines over gaps
    paint.style = PaintingStyle.stroke;
    drawLine(canvas, size, paint, getY(series.average.value,   view), heatColors[0]);
    drawLine(canvas, size, paint, getY(series.percent90.value, view), heatColors[1]);
    drawLine(canvas, size, paint, getY(series.percent99.value, view), heatColors[2]);

    // Finally frame times over lines
    paint.style = PaintingStyle.fill;
    for (final GraphableEvent frame in series) {
      paint.color = heatColors[series.heatIndex(frame)];
      canvas.drawRect(getRect(frame, view, minWidth), paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

class SeriesDistributionPainter extends SeriesPainter {
  SeriesDistributionPainter(GraphableSeries series, {
    Rect zoom = unitRect,
  })
      : run = series.wholeRun,
        indices = List<int>.generate(series.frames.length, (int index) => index),
        super(series, zoom) {
    indices.sort((int a, int b) {
      return series.frames[a].compareTo(series.frames[b]);
    });
  }

  final TimeFrame run;
  final List<int> indices;

  @override
  GraphableEvent eventNear(Offset graphRelative) {
    int index = (graphRelative.dx * series.frameCount).floor();
    if (index < 0) {
      index = 0;
    } else if (index >= indices.length) {
      index = indices.length - 1;
    }
    return series.frames[indices[index]];
  }

  late final GraphAxisPercentPainter _timePainter = GraphAxisPercentPainter(zoom, true);
  @override
  GraphAxisPainter get horizontalAxisPainter => _timePainter;

  late final GraphVAxisDurationPainter _durationPainter = GraphVAxisDurationPainter(this);
  @override
  GraphAxisPainter get verticalAxisPainter => _durationPainter;

  @override
  SeriesDistributionPainter withZoom(Rect newZoom) =>
      SeriesDistributionPainter(series,
        zoom: newZoom,
      );

  @override
  void paint(Canvas canvas, Size size) {
    final Rect view = Offset.zero & size;
    canvas.clipRect(view);

    canvas.translate(0, size.height);
    canvas.scale(size.width / indices.length, -size.height / series.maxValue.value);
    // coordinates now go from BL(0, 0) to TR(#indices, worst)

    canvas.scale(1.0 / zoom.width, 1.0 / zoom.height);
    canvas.translate(-zoom.left * indices.length, (zoom.bottom - 1) * series.maxValue.value);

    final Paint paint = Paint();

    final int i0 = (zoom.left * indices.length).floor();
    final int i1 = (zoom.right * indices.length).ceil();
    for (int i = i0; i < i1; i++) {
      final GraphableEvent frame = series.frames[indices[i]];
      paint.color = heatColors[series.heatIndex(frame)];
      final double x = i.toDouble();
      canvas.drawRect(Rect.fromLTRB(x, 0, x+1, frame.reading.value), paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

class FlowGraphPainter extends SeriesPainter {
  factory FlowGraphPainter(GraphableSeries series, {
    Rect zoom = unitRect,
  }) {
    final List<int> slots = List<int>.filled(series.frameCount, 0);
    final int numSlots = _countActive(series, slots);
    return FlowGraphPainter._(series, zoom, slots, numSlots);
  }

  FlowGraphPainter._(GraphableSeries series, Rect zoom, this.slots, this.numSlots)
      : super(series, zoom);

  static int _countActive(GraphableSeries series, List<int> slots) {
    final List<TimeVal?> active = <TimeVal>[];
    // As long as the graph is over 500 pixels wide we'll ensure at least 1 pixel gap
    final TimeVal gap = series.wholeRun.duration * (1 / 500);
    int num = 0;
    // first count the number of slots needed, only growing active when necessary
    for (int i = 0; i < series.frameCount; i++) {
      final GraphableEvent frame = series.frames[i];
      int keep = 0;
      for (int j = 0; j < num; j++) {
        if (active[j]! >= frame.start) {
          active[keep++] = active[j];
        }
      }
      if (keep < active.length) {
        active[keep] = frame.end + gap;
      } else {
        active.add(frame.end + gap);
      }
      num = keep + 1;
    }

    // next start over and place each frame in a slot in an upward "spiral"

    // For some reason fillRange gets type errors filling an array with nulls in JS
    // active.fillRange(0, active.length);
    // So we do it manually...
    for (int i = 0; i < active.length; i++) {
      active[i] = null;
    }
    int pos = -1;
    for (int i = 0; i < series.frameCount; i++) {
      final GraphableEvent frame = series.frames[i];
      pos = _nextSlot(active, pos, frame.start, frame.end + gap, TimeVal.zero);
      slots[i] = pos;
    }
    return active.length;
  }

  static int _nextSlot(List<TimeVal?> active, int pos, TimeVal start, TimeVal end, TimeVal restartGap) {
    bool restart = true;
    for (int i = 0; i < active.length; i++) {
      final TimeVal? t = active[i];
      if (t != null && t + restartGap >= start) {
        restart = false;
        break;
      }
    }
    if (restart) {
      active[0] = end;
      return 0;
    }
    for (int i = pos + 1; i < active.length; i++) {
      final TimeVal? t = active[i];
      if (t == null || t < start) {
        active[i] = end;
        return i;
      }
    }
    for (int i = 0; i <= pos; i++) {
      final TimeVal? t = active[i];
      if (t == null || t < start) {
        active[i] = end;
        return i;
      }
    }
    throw 'no slot to put new flow event';
  }

  final List<int> slots;
  final int numSlots;

  @override
  GraphableEvent eventNear(Offset graphRelative) {
    final TimeVal t = series.wholeRun.elapsedTime(graphRelative.dx);
    final double slotY = 1 - graphRelative.dy;
    GraphableEvent best = series.frames.first;
    double bestDistanceSquared = double.infinity;
    for (int i = 0; i < series.frameCount; i++) {
      final GraphableEvent frame = series.frames[i];
      final double dx = (t < frame.start) ? ((frame.start - t) / series.wholeRun.duration)
          : (t > frame.end) ? ((t - frame.end) / series.wholeRun.duration)
          : 0;
      final double frameY = (slots[i] + 0.5) / numSlots;
      final double dy = frameY - slotY;
      // dx and dy are fractions relative to the total size of the graph area. The
      // dx distances thus represent a much larger screen distance than the dy distances.
      // So we bias the distance equation against the x distance a bit to compensate
      final double dsq = (dx * dx * 100) + (dy * dy);
      if (dsq < bestDistanceSquared) {
        best = frame;
        bestDistanceSquared = dsq;
      }
    }
    return best;
  }

  double getX(TimeVal t, Rect bounds) => bounds.left + bounds.width * series.wholeRun.getFraction(t);

  @override
  FlowGraphPainter withZoom(Rect newZoom) => FlowGraphPainter(series, zoom: newZoom);

  late final GraphHAxisTimePainter _timePainter = GraphHAxisTimePainter(series.wholeRun, zoom);
  @override
  GraphAxisPainter get horizontalAxisPainter => _timePainter;
  @override
  GraphAxisPainter? get verticalAxisPainter => null;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect view = Offset.zero & size;
    canvas.clipRect(view);

    canvas.scale(1.0 / zoom.width, 1.0 / zoom.height);
    canvas.translate(-zoom.left * size.width, -zoom.top * size.height);

    final Paint paint = Paint();

    paint.style = PaintingStyle.fill;
    final double barH = size.height / (numSlots + 1);
    final double stepT = barH / 4;
    final double stepB = stepT * 3;
    final double barGap = size.height / numSlots;
    for (int i = 0; i < series.frameCount; i++) {
      final GraphableEvent frame = series.frames[i];
      final double startX = getX(frame.start, view);
      final double endX = getX(frame.end, view);
      final double y = size.height - slots[i] * barGap;
      paint.color = heatColors[series.heatIndex(frame)];
      canvas.drawRect(Rect.fromLTRB(startX, y - barH, endX, y), paint);
      if (frame is FlowEvent) {
        paint.color = Colors.black;
        for (final TimeVal step in frame.steps) {
          final double x = getX(step, view);
          canvas.drawRect(Rect.fromLTRB(x, y - stepB, x + 0.5, y - stepT), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

class SeriesGraphWidget extends StatefulWidget {
  SeriesGraphWidget(this.series, this.closeCallback) : super(key: ObjectKey(series));

  final GraphableSeries series;
  final Function(SeriesGraphWidget) closeCallback;

  @override State createState() => SeriesGraphWidgetState(series);
}

class SeriesGraphWidgetState extends State<SeriesGraphWidget> {
  SeriesGraphWidgetState(this.series)
      : _mouseKey = GlobalKey(),
        _imageKey = GlobalKey(),
        _distribution = false,
        _painter = _painterFor(series),
        _hoverString = '';

  static SeriesPainter _painterFor(GraphableSeries series) {
    switch (series.seriesType) {
      case SeriesType.SEQUENTIAL_EVENTS:
        return SeriesGraphPainter(series);
      case SeriesType.OVERLAPPING_EVENTS:
        return FlowGraphPainter(series);
    }
  }

  final GraphableSeries series;
  final GlobalKey _mouseKey;
  final GlobalKey _imageKey;
  FocusNode? focusNode;
  Offset _dragAnchor = Offset.zero;
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
    focusNode?.dispose();
    focusNode = null;

    super.dispose();
  }

  SeriesPainter _painter;
  Offset _zoomAnchor = Offset.zero;
  GraphableEvent? _hoverFrame;
  String _hoverString;

  void _setHoverEvent(GraphableEvent newHoverFrame) {
    if (_hoverFrame != newHoverFrame) {
      final TimeFrame e = newHoverFrame - series.wholeRun.start;
      final String start = e.start.stringSeconds();
      final String end = e.end.stringSeconds();
      final String value = newHoverFrame.reading.valueString(precision: 3);
      final String label = series.labelFor(newHoverFrame);
      setState(() {
        _hoverFrame = newHoverFrame;
        _hoverString = 'frame[$start => $end] = $value ($label)';
      });
    }
  }

  Offset _getWidgetRelativePosition(Offset position) {
    final RenderBox? box = _mouseKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null)
      return position;
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
    final GraphableEvent e = _painter.eventNear(relative);
    _setHoverEvent(e);
  }

  void _setDistribution(bool newDistribution) {
    setState(() {
      _distribution = newDistribution;
      _painter = _distribution
          ? SeriesDistributionPainter(series)
          : _painterFor(series);
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

  KeyEventResult _onKey(RawKeyEvent keyEvent) {
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
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    } else {
      return KeyEventResult.ignored;
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
      onEnter: (_) => focusNode!.requestFocus(),
      onExit: (_) => focusNode!.unfocus(),
      onHover: (PointerHoverEvent e) => _onHover(e.position),
      child: RawKeyboardListener(
        focusNode: focusNode!,
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
          Text('$name: ${value.valueString(precision: 3)}'),
        ],
      );
    }
    final Row legend = Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: <Widget>[
        _makeLegendItem('average value',   series.average,   heatColors[0]),
        _makeLegendItem('90th percentile', series.percent90, heatColors[1]),
        _makeLegendItem('99th percentile', series.percent99, heatColors[2]),
        _makeLegendItem('worst value',     series.worst,     heatColors[3]),
      ],
    );

    return RepaintBoundary(
      key: _imageKey,
      child: Column(
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(series.titleName, style: const TextStyle(fontSize: 24),),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => widget.closeCallback(widget),
              ),
              Checkbox(
                value: _distribution,
                onChanged: (bool? value) => _setDistribution(value!),
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
