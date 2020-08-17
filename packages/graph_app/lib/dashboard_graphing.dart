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
      List<DashboardBenchmarkItemBase> widgets, Size size,
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
        size: size,
        averageBenchmark: average,
        percent90Benchmark: percent90,
        percent99Benchmark: percent99,
        worstBenchmark: worst,
      ));
    }
  }

  List<DashboardBenchmarkItemBase> _widgets() {
    final List<DashboardBenchmarkItemBase> widgets = <DashboardBenchmarkItemBase>[];
    const Size size = Size(200.0, 100.0);
    _addItemSetWidget(widgets, size,
        'Build',
        'average_frame_build_time_millis',
        '90th_percentile_frame_build_time_millis',
        '99th_percentile_frame_build_time_millis',
        'worst_frame_build_time_millis');
    _addItemSetWidget(widgets, size,
        'Render',
        'average_frame_rasterizer_time_millis',
        '90th_percentile_frame_rasterizer_time_millis',
        '99th_percentile_frame_rasterizer_time_millis',
        'worst_frame_rasterizer_time_millis');
    for (final Benchmark benchmark in widget.benchmarks) {
      if (!benchmark.archived) {
        widgets.add(DashboardBenchmarkItemWidget(benchmark, size));
      }
    }
    return widgets;
  }

  void showHistory(BuildContext context, DashboardBenchmarkItemBase tile) {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          child: DashboardHistoryDetailWidget(widget.taskName, tile),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    print('building list of tiles');
    final List<DashboardBenchmarkItemBase> widgets = _widgets();
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
                    Column(
                      children: <Widget>[
                        GestureDetector(
                          child: Container(
                            margin: const EdgeInsets.only(left: 20, right: 20),
                            child: widgets[r+c],
                          ),
                          onTap: () => showHistory(context, widgets[r+c]),
                        ),
                      ],
                    ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class DashboardHistoryDetailWidget extends StatefulWidget {
  const DashboardHistoryDetailWidget(this.taskName, this.tile);

  final String taskName;
  final DashboardBenchmarkItemBase tile;

  @override
  State createState() => DashboardHistoryDetailState();
}

class DashboardHistoryDetailState extends State<DashboardHistoryDetailWidget> {
  DashboardBenchmarkItemBase history;

  @override
  void initState() {
    super.initState();
    getHistory();
  }

  void getHistory() {
    print('asynchronously loading history');
    widget.tile.makeDetail(const Size(800.0, 200.0)).then((DashboardBenchmarkItemBase value) {
      print('got history');
      setState(() {
        history = value;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    print('building history widget');
    return Column(
      children: <Widget>[
        Text('History of ${widget.taskName}', style: const TextStyle(fontSize: 20.0),),
        Center(
          child: history ?? const Text('Loading history'),
        ),
      ],
    );
  }
}

abstract class DashboardBenchmarkItemBase extends StatelessWidget {
  const DashboardBenchmarkItemBase();

  Future<DashboardBenchmarkItemBase> makeDetail(Size size);
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
  for (final TimeSeriesValue tsv in values.reversed) {
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

class DashboardBenchmarkItemWidget extends DashboardBenchmarkItemBase {
  const DashboardBenchmarkItemWidget(this.benchmark, this.size);

  final Benchmark benchmark;
  final Size size;

  @override
  Future<DashboardBenchmarkItemBase> makeDetail(Size size) async {
    return DashboardBenchmarkItemWidget(await benchmark.getFullHistory(base: ''), size);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        CustomPaint(
          size: size,
          painter: DashboardItemPainter(benchmark),
          isComplex: true,
          willChange: false,
        ),
        Text(benchmark.descriptor.label, style: const TextStyle(fontSize: 9.0)),
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
  }) : worst = _worstValueList(<Benchmark>[
    averageBenchmark,
    percent90Benchmark,
    percent99Benchmark,
    worstBenchmark,
  ]);

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

class DashboardItemSetWidget extends DashboardBenchmarkItemBase {
  const DashboardItemSetWidget({
    @required this.label,
    @required this.size,
    @required this.averageBenchmark,
    @required this.percent90Benchmark,
    @required this.percent99Benchmark,
    @required this.worstBenchmark,
  });

  final String label;
  final Size size;
  final Benchmark averageBenchmark;
  final Benchmark percent90Benchmark;
  final Benchmark percent99Benchmark;
  final Benchmark worstBenchmark;

  @override
  Future<DashboardBenchmarkItemBase> makeDetail(Size size) async {
    final Benchmark historicalAverages  = await averageBenchmark.getFullHistory(base: '');
    final Benchmark historicalPercent90 = await percent90Benchmark.getFullHistory(base: '');
    final Benchmark historicalPercent99 = await percent99Benchmark.getFullHistory(base: '');
    final Benchmark historicalWorsts    = await worstBenchmark.getFullHistory(base: '');
    return DashboardItemSetWidget(
      label: label,
      size: size,
      averageBenchmark:   historicalAverages,
      percent90Benchmark: historicalPercent90,
      percent99Benchmark: historicalPercent99,
      worstBenchmark:     historicalWorsts,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        CustomPaint(
          size: size,
          painter: DashboardItemSetPainter(
            averageBenchmark:   averageBenchmark,
            percent90Benchmark: percent90Benchmark,
            percent99Benchmark: percent99Benchmark,
            worstBenchmark:     worstBenchmark,
          ),
          isComplex: true,
          willChange: false,
        ),
        Text(label, style: const TextStyle(fontSize: 9.0)),
      ],
    );
  }
}
