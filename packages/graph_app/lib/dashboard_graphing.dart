// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';

import 'package:flutter_benchmark_utils/benchmark_data.dart';

class DashboardGraphWidget extends StatefulWidget {
  const DashboardGraphWidget(this.results)
      : assert(results != null);

  final BenchmarkDashboard results;

  @override
  State createState() => DashboardGraphState();
}

class DashboardGraphState extends State<DashboardGraphWidget> {
  ScrollController _controller;

  final bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Iterable<String> _taskNames() {
    if (_showArchived)
      return widget.results.allTasks.keys;

    return widget.results.allTasks.keys.where((String taskName) {
      for (final Benchmark benchmark in widget.results.allTasks[taskName]) {
        if (!benchmark.archived)
          return true;
      }
      return false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Container(
          child: SingleChildScrollView(
            controller: _controller,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (String taskName in _taskNames())
                  Container(
                    margin: const EdgeInsets.only(top: 20, bottom: 20),
                    child: DashboardTaskWidget(taskName, widget.results.allTasks[taskName]),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class DashboardTaskWidget extends StatefulWidget {
  const DashboardTaskWidget(this.taskName, this.benchmarks);

  final String taskName;
  final List<Benchmark> benchmarks;

  @override
  State createState() => DashboardTaskState();
}

class DashboardTaskState extends State<DashboardTaskWidget> {
  Benchmark _findByLabel(String label) {
    for (final Benchmark benchmark in widget.benchmarks) {
      if (benchmark.descriptor.label == label) {
        return benchmark;
      }
    }
    return null;
  }

  void _addItemSetWidget(
      List<Widget> widgets,
      String label,
      String avgLabel,
      String p90Label,
      String p99Label,
      String worstLabel) {
    final Benchmark average = _findByLabel(avgLabel);
    final Benchmark percent90 = _findByLabel(p90Label);
    final Benchmark percent99 = _findByLabel(p99Label);
    final Benchmark worst = _findByLabel(worstLabel);
    if (average != null && percent90 != null && percent99 != null && worst != null) {
      if (average.archived && percent90.archived && percent99.archived && worst.archived) {
        return;
      }
      widgets.add(DashboardItemSetWidget(
        label: label,
        averageBenchmark: average,
        percent90Benchmark: percent90,
        percent99Benchmark: percent99,
        worstBenchmark: worst,
      ));
    }
  }

  List<Widget> _widgets() {
    final List<Widget> widgets = <Widget>[];
    _addItemSetWidget(widgets,
        'Build',
        'average_frame_build_time_millis',
        '90th_percentile_frame_build_time_millis',
        '99th_percentile_frame_build_time_millis',
        'worst_frame_build_time_millis');
    _addItemSetWidget(widgets,
        'Render',
        'average_frame_rasterizer_time_millis',
        '90th_percentile_frame_rasterizer_time_millis',
        '99th_percentile_frame_rasterizer_time_millis',
        'worst_frame_rasterizer_time_millis');
    for (final Benchmark benchmark in widget.benchmarks) {
      if (!benchmark.archived) {
        widgets.add(DashboardBenchmarkItemWidget(benchmark));
      }
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> widgets = _widgets();
    const int columns = 5;
    return Column(
      children: <Widget>[
        Text(widget.taskName, style: const TextStyle(fontSize: 20.0),),
        Column(
          children: <Widget>[
            for (int r = 0; r < widgets.length; r += columns)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  for (int c = 0; c < columns && r+c < widgets.length; c++)
                    Container(
                      margin: const EdgeInsets.only(left: 20, right: 20),
                      child: widgets[r+c],
                    ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

void _paintSeries(
    Canvas canvas,
    Size size,
    Paint paint,
    List<TimeSeriesValue> values,
    double worst,
    Color colorFor(TimeSeriesValue tsv)) {
  double x = 0;
  final double dx = size.width / values.length;
  for (final TimeSeriesValue tsv in values) {
    paint.color = colorFor(tsv);
    final double v = tsv.dataMissing ? worst : tsv.value;
    final double y = size.height * (1 - v / worst);
    canvas.drawRect(Rect.fromLTRB(x, y, x + dx, size.height), paint);
    x += dx;
  }
}

double _worstValue(Benchmark benchmark) {
  double worst = benchmark.descriptor.baseline;
  for (final TimeSeriesValue tsv in benchmark.values) {
    if (!tsv.dataMissing && worst < tsv.value) {
      worst = tsv.value;
    }
  }
  return (worst == 0) ? 1 : worst;
}

double _worstValueList(List<Benchmark> benchmarks) {
  double worst = 0;
  for (final Benchmark benchmark in benchmarks) {
    final double w = _worstValue(benchmark);
    if (worst < w) {
      worst = w;
    }
  }
  return (worst == 0) ? 1 : worst;
}

double _yFor(double v, double worst, Size size) {
  return size.height * (1 - v / worst);
}

void _drawLine(Canvas canvas, Size size, Paint paint, double y, Color heatColor) {
  paint.color = heatColor.withAlpha(128);
  paint.strokeWidth = 1.0;
  const double dashLen = 10.0;
  for (double x = 0; x < size.width; x += dashLen + dashLen) {
    canvas.drawLine(Offset(x, y), Offset(x + dashLen, y), paint);
  }
}

class DashboardItemPainter extends CustomPainter {
  DashboardItemPainter(this.benchmark) : worst = _worstValue(benchmark);

  final Benchmark benchmark;
  final double worst;

  Color _colorFor(TimeSeriesValue tsv) {
    if (tsv.dataMissing) {
      return Colors.grey.shade200;
    }
    if (tsv.value < benchmark.descriptor.goal) {
      return Colors.green;
    }
    if (tsv.value < benchmark.descriptor.baseline) {
      return Colors.green.shade200;
    }
    return Colors.red;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint();
    _paintSeries(canvas, size, paint, benchmark.values, worst, _colorFor);
    _drawLine(canvas, size, paint, _yFor(benchmark.descriptor.goal, worst, size), Colors.green);
    _drawLine(canvas, size, paint, _yFor(benchmark.descriptor.baseline, worst, size), Colors.red);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

class DashboardBenchmarkItemWidget extends StatefulWidget {
  const DashboardBenchmarkItemWidget(this.benchmark);

  final Benchmark benchmark;

  @override
  State createState() => DashboardBenchmarkItemState();
}

class DashboardBenchmarkItemState extends State<DashboardBenchmarkItemWidget> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        CustomPaint(
          size: const Size(200.0, 100.0),
          painter: DashboardItemPainter(widget.benchmark),
          isComplex: true,
          willChange: false,
        ),
        Text(widget.benchmark.descriptor.label, style: const TextStyle(fontSize: 9.0)),
      ],
    );
  }
}

class DashboardItemSetPainter extends CustomPainter {
  DashboardItemSetPainter({
    @required this.averageBenchmark,
    @required this.percent90Benchmark,
    @required this.percent99Benchmark,
    @required this.worstBenchmark,
  }) : worst = _worstValueList(<Benchmark>[averageBenchmark, percent90Benchmark, percent99Benchmark, worstBenchmark]);

  final Benchmark averageBenchmark;
  final Benchmark percent90Benchmark;
  final Benchmark percent99Benchmark;
  final Benchmark worstBenchmark;
  final double worst;

  Color Function(TimeSeriesValue) _validColor(Color c) =>
          (TimeSeriesValue tsv) => tsv.dataMissing ? Colors.grey.shade200 : c;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint();
    _paintSeries(canvas, size, paint, worstBenchmark.values, worst,     _validColor(Colors.red));
    _paintSeries(canvas, size, paint, percent99Benchmark.values, worst, _validColor(Colors.yellow));
    _paintSeries(canvas, size, paint, percent90Benchmark.values, worst, _validColor(Colors.green.shade200));
    _paintSeries(canvas, size, paint, averageBenchmark.values, worst,   _validColor(Colors.green));
    _drawLine(canvas, size, paint, _yFor(averageBenchmark.descriptor.goal, worst, size), Colors.green);
    _drawLine(canvas, size, paint, _yFor(averageBenchmark.descriptor.baseline, worst, size), Colors.red);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

class DashboardItemSetWidget extends StatefulWidget {
  const DashboardItemSetWidget({
    this.label,
    this.averageBenchmark,
    this.percent90Benchmark,
    this.percent99Benchmark,
    this.worstBenchmark,
  });

  final String label;
  final Benchmark averageBenchmark;
  final Benchmark percent90Benchmark;
  final Benchmark percent99Benchmark;
  final Benchmark worstBenchmark;

  @override
  State createState() => DashboardItemSetState();
}

class DashboardItemSetState extends State<DashboardItemSetWidget> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        CustomPaint(
          size: const Size(200.0, 100.0),
          painter: DashboardItemSetPainter(
            averageBenchmark: widget.averageBenchmark,
            percent90Benchmark: widget.percent90Benchmark,
            percent99Benchmark: widget.percent99Benchmark,
            worstBenchmark: widget.worstBenchmark,
          ),
          isComplex: true,
          willChange: false,
        ),
        Text(widget.label, style: const TextStyle(fontSize: 9.0)),
      ],
    );
  }
}
