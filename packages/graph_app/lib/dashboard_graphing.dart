// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math';

import 'package:flutter/material.dart';

import 'package:flutter_benchmark_utils/benchmark_data.dart';

@immutable
class DashboardFilter {
  const DashboardFilter({
    this.showArchived = false,
    this.showEmpty = false,
    this.taskRegExp,
    this.labelRegExp,
    this.minimumRed = 0,
  });

  final bool showArchived;
  final bool showEmpty;
  final RegExp taskRegExp;
  final RegExp labelRegExp;
  final int minimumRed;

  DashboardFilter withShowArchived(bool showArchived) =>
      DashboardFilter(
        showArchived: showArchived,
        showEmpty: showEmpty,
        taskRegExp: taskRegExp,
        labelRegExp: labelRegExp,
        minimumRed: minimumRed,
      );

  DashboardFilter withShowEmpty(bool showEmpty) =>
      DashboardFilter(
        showArchived: showArchived,
        showEmpty: showEmpty,
        taskRegExp: taskRegExp,
        labelRegExp: labelRegExp,
        minimumRed: minimumRed,
      );

  DashboardFilter withTaskRegExp(RegExp taskRegExp) =>
      DashboardFilter(
        showArchived: showArchived,
        showEmpty: showEmpty,
        taskRegExp: taskRegExp,
        labelRegExp: labelRegExp,
        minimumRed: minimumRed,
      );

  DashboardFilter withLabelRegExp(RegExp labelRegExp) =>
      DashboardFilter(
        showArchived: showArchived,
        showEmpty: showEmpty,
        taskRegExp: taskRegExp,
        labelRegExp: labelRegExp,
        minimumRed: minimumRed,
      );

  DashboardFilter withMinimumRed(int minimumRed) =>
      DashboardFilter(
        showArchived: showArchived,
        showEmpty: showEmpty,
        taskRegExp: taskRegExp,
        labelRegExp: labelRegExp,
        minimumRed: minimumRed,
      );

  static bool _isEmpty(Benchmark benchmark) {
    for (final TimeSeriesValue value in benchmark.values) {
      if (!value.dataMissing)
        return false;
    }
    return true;
  }

  bool _redEnough(Benchmark benchmark) {
    if (minimumRed > 0) {
      int numRed = 0;
      for (final TimeSeriesValue value in benchmark.values) {
        if (value.value > benchmark.descriptor.baseline) {
          if (++numRed >= minimumRed)
            return true;
        }
      }
      return false;
    }
    return true;
  }

  bool isShown(Benchmark benchmark) {
    if (!showArchived && benchmark.archived)
      return false;
    if (!showEmpty && _isEmpty(benchmark))
      return false;
    if (taskRegExp != null && !taskRegExp.hasMatch(benchmark.task))
      return false;
    if (labelRegExp != null && !labelRegExp.hasMatch(benchmark.descriptor.label))
      return false;
    if (!_redEnough(benchmark))
      return false;
    return true;
  }

  @override
  int get hashCode => hashValues(showArchived, showEmpty, taskRegExp, labelRegExp, minimumRed);

  @override bool operator ==(Object other) {
    return other is DashboardFilter &&
        showArchived == other.showArchived &&
        showEmpty == other.showEmpty &&
        taskRegExp == other.taskRegExp &&
        labelRegExp == other.labelRegExp &&
        minimumRed == other.minimumRed;
  }
}

class DashboardFilterWidget extends StatefulWidget {
  const DashboardFilterWidget(this.initialFilter, this.onChanged, [this.onRemove, this.maxRed = 60]);

  final DashboardFilter initialFilter;
  final Function(DashboardFilter newFilter) onChanged;
  final Function() onRemove;
  final int maxRed;

  @override
  State createState() => DashboardFilterState();
}

class DashboardFilterState extends State<DashboardFilterWidget> {
  @override
  void initState() {
    super.initState();
    filter = widget.initialFilter;
    taskController = TextEditingController(text: filter.taskRegExp?.pattern ?? '');
    labelController = TextEditingController(text: filter.labelRegExp?.pattern ?? '');
  }

  static TextStyle labelStyle = const TextStyle(
    color: Colors.black,
    fontSize: 16.0,
    fontWeight: FontWeight.normal,
    fontStyle: FontStyle.normal,
    decoration: TextDecoration.none,
  );

  DashboardFilter filter;
  TextEditingController taskController;
  TextEditingController labelController;

  void _setFilter(DashboardFilter newFilter) {
    setState(() {
      filter = newFilter;
    });
    widget.onChanged(newFilter);
  }

  void _newTaskFilter(RegExp newRegExp) {
    _setFilter(filter.withTaskRegExp(newRegExp));
  }

  void _newLabelFilter(RegExp newRegExp) {
    _setFilter(filter.withLabelRegExp(newRegExp));
  }

  void _newArchived(bool newValue) {
    _setFilter(filter.withShowArchived(newValue));
  }

  void _newEmpty(bool newValue) {
    _setFilter(filter.withShowEmpty(newValue));
  }

  void _newMinRed(int newMinimum) {
    _setFilter(filter.withMinimumRed(newMinimum));
  }

  Widget _pad(Widget child, Alignment alignment) {
    return Container(
      padding: const EdgeInsets.all(5.0),
      child: child,
      alignment: alignment,
    );
  }

  TableRow _makeRow(String label, Widget editable) {
    return TableRow(
      children: <Widget>[
        _pad(Text(label, style: labelStyle), Alignment.centerRight),
        _pad(editable, Alignment.centerLeft),
      ],
    );
  }

  TableRow _makeTextFilterRow(String label, TextEditingController controller, void onChanged(RegExp newValue)) {
    return _makeRow(label,
      TextField(
        controller: controller,
        decoration: const InputDecoration(
          hintText: '(regular expression)',
        ),
        onChanged: (String newValue) => onChanged(RegExp(newValue)),
      ),
    );
  }

  TableRow _makeBoolRow(String label, bool currentValue, void onChanged(bool newValue)) {
    return _makeRow(label,
      Checkbox(value: currentValue, onChanged: onChanged),
    );
  }

  TableRow _makeIntRow(String label, int currentValue, void onChanged(int newValue)) {
    return _makeRow(label,
      Slider(
        value: currentValue.toDouble(),
        min: 0.0,
        max: widget.maxRed.toDouble(),
        onChanged: (double value) => onChanged(value.round()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned(
          child: FlatButton(
            child: const Icon(Icons.close),
            onPressed: widget.onRemove,
          ),
        ),
        Table(
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          columnWidths: const <int, TableColumnWidth>{
            0: IntrinsicColumnWidth(),
            1: FixedColumnWidth(250.0),
          },
          children: <TableRow>[
            _makeTextFilterRow('Task name matches:', taskController, _newTaskFilter),
            _makeTextFilterRow('Measurement name matches:', labelController, _newLabelFilter),
            _makeBoolRow('Show Archived', filter.showArchived, _newArchived),
            _makeBoolRow('Show Empty', filter.showEmpty, _newEmpty),
            _makeIntRow('Minimum Red entries', filter.minimumRed, _newMinRed)
          ],
        ),
      ],
    );
  }
}

class DashboardGraphWidget extends StatefulWidget {
  const DashboardGraphWidget(this.results)
      : assert(results != null);

  final BenchmarkDashboard results;

  @override
  State createState() => DashboardGraphState();
}

class DashboardGraphState extends State<DashboardGraphWidget> {
  ScrollController _controller;

  DashboardFilter filter = const DashboardFilter();
  OverlayEntry _filterEditor;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
  }

  @override
  void dispose() {
    _controller.dispose();
    _filterEditor?.remove();
    super.dispose();
  }

  Iterable<String> _taskNames() {
    return widget.results.allTasks.keys.where((String taskName) {
      for (final Benchmark benchmark in widget.results.allTasks[taskName]) {
        if (filter.isShown(benchmark))
          return true;
      }
      return false;
    });
  }

  List<Benchmark> _benchmarksForTask(String taskName) {
    return widget.results.allTasks[taskName]
        .where((Benchmark benchmark) => filter.isShown(benchmark))
        .toList();
  }

  void _setFilter(DashboardFilter newFilter) {
    if (filter != newFilter) {
      setState(() {
        filter = newFilter;
      });
    }
  }

  int _maxValues() {
    int numValues = 0;
    for (final Benchmark benchmark in widget.results.allEntries) {
      numValues = max(numValues, benchmark.values.length);
    }
    return numValues;
  }

  void _hideFilters() {
    _filterEditor?.remove();
    _filterEditor = null;
  }

  void _showFilters(BuildContext context) {
    if (_filterEditor != null)
      return;
    _filterEditor = OverlayEntry(
      builder: (BuildContext context) {
        return Positioned(
          top: 80.0,
          right: 10.0,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(0xc0),
              borderRadius: BorderRadius.circular(20.0),
            ),
            child: DashboardFilterWidget(filter, _setFilter, _hideFilters, _maxValues()),
          ),
        );
      },
    );

    Overlay.of(context).insert(_filterEditor);
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
                    child: DashboardTaskWidget(taskName, _benchmarksForTask(taskName)),
                  ),
              ],
            ),
          ),
        ),
        Positioned(
          right: 5.0,
          top: 5.0,
          child: RaisedButton(
            color: Colors.grey.shade400.withAlpha(128),
            child: const Icon(Icons.sort),
            onPressed: () => _showFilters(context),
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
        'Frame Build Time Metrics Overlay',
        'average_frame_build_time_millis',
        '90th_percentile_frame_build_time_millis',
        '99th_percentile_frame_build_time_millis',
        'worst_frame_build_time_millis');
    _addItemSetWidget(widgets, size,
        'Frame Render Time Metrics Overlay',
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
          child: DashboardHistoryDetailWidget(tile),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<DashboardBenchmarkItemBase> widgets = _widgets();
    return Column(
      children: <Widget>[
        Text(widget.taskName, style: const TextStyle(fontSize: 20.0),),
        const SizedBox(height: 20.0),
        Wrap(
          runSpacing: 20.0,
          spacing: 20.0,
          alignment: WrapAlignment.spaceEvenly,
          children: widgets.map((DashboardBenchmarkItemBase w) {
            return GestureDetector(
              child: RepaintBoundary(child: w),
              onTap: () => showHistory(context, w),
            );
          }).toList(),
        ),
        const SizedBox(height: 30.0),
      ],
    );
  }
}

class DashboardHistoryDetailWidget extends StatefulWidget {
  const DashboardHistoryDetailWidget(this.tile);

  final DashboardBenchmarkItemBase tile;

  @override
  State createState() => DashboardHistoryDetailState();
}

class DashboardHistoryDetailState extends State<DashboardHistoryDetailWidget> {
  DashboardBenchmarkItemBase history;
  ValueNotifier<RangeValues> range = ValueNotifier<RangeValues>(null);
  double count;
  bool lockRange = true;

  @override
  void initState() {
    super.initState();
    range.addListener(() => setState(() {}));
    getHistory();
  }

  void getHistory() {
    widget.tile.makeDetail(size: const Size(800.0, 200.0), range: range).then(
            (DashboardBenchmarkItemBase value) {
              setState(() {
                history = value;
                count = value.valueCount.toDouble();
                if (count > 400) {
                  range.value = RangeValues(count - 400, count);
                } else {
                  range.value = RangeValues(0.0, count);
                }
              });
            });
  }

  void setRange(RangeValues newRange) {
    if (lockRange) {
      final RangeValues curRange = range.value;
      double delta = newRange.start - curRange.start + newRange.end - curRange.end;
      if (curRange.end + delta > count) {
        delta = count - curRange.end;
      }
      if (curRange.start + delta < 0.0) {
        delta = 0.0 - curRange.start;
      }
      range.value = RangeValues(curRange.start + delta, curRange.end + delta);
    } else {
      range.value = newRange;
    }
  }

  void setLockRange(bool lock) {
    setState(() {
      lockRange = lock;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text('History of ${widget.tile.taskName}', style: const TextStyle(fontSize: 20.0),),
        if (widget.tile.goal != null || widget.tile.baseline != null)
          Text('Goal: ${widget.tile.goal}, baseline = ${widget.tile.baseline}'),
        const SizedBox(height: 20.0),
        Center(
          child: history ?? const Text('Loading history'),
        ),
        const SizedBox(height: 20.0),
        if (range.value != null && count != null)
          RangeSlider(
            min: 0.0,
            max: count,
            values: range.value,
            onChanged: setRange,
          ),
        if (range.value != null && count != null)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Text('Lock Range Size'),
              Checkbox(value: lockRange, onChanged: setLockRange,),
            ],
          ),
      ],
    );
  }
}

abstract class DashboardBenchmarkItemBase extends StatefulWidget {
  const DashboardBenchmarkItemBase();

  String get taskName;
  int get valueCount;
  double get goal;
  double get baseline;

  Future<DashboardBenchmarkItemBase> makeDetail({
    Size size,
    ValueNotifier<RangeValues> range,
  });
}

void _paintSeries(
    Canvas canvas,
    Size size,
    Paint paint,
    List<TimeSeriesValue> values,
    RangeValues range,
    double worst,
    Color colorFor(TimeSeriesValue tsv)) {
  // values go from most recent at index 0 to earlier values as index increases
  // range specifies 0 (oldest) to values.length (most recent)
  range ??= RangeValues(0, values.length.toDouble());
  final double dx = size.width / (range.end - range.start);
  int index = range.end.ceil();
  double x = size.width + dx * (index - range.end);
  index = values.length - index;
  while (index < values.length && x > 0) {
    x -= dx;
    final TimeSeriesValue tsv = values[index];
    paint.color = colorFor(tsv);
    final double v = tsv.dataMissing ? worst : tsv.value;
    final double y = size.height * (1 - v / worst);
    canvas.drawRect(Rect.fromLTRB(x, y, x + dx, size.height), paint);
    index++;
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
  DashboardItemPainter(this.benchmark, this.range) : worst = _worstValue(benchmark);

  final Benchmark benchmark;
  final RangeValues range;
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
    _paintSeries(canvas, size, paint, benchmark.values, range, worst, _colorFor);
    _drawLine(canvas, size, paint, _yFor(benchmark.descriptor.goal, worst, size), Colors.green);
    _drawLine(canvas, size, paint, _yFor(benchmark.descriptor.baseline, worst, size), Colors.red);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

class DashboardBenchmarkItemWidget extends DashboardBenchmarkItemBase {
  const DashboardBenchmarkItemWidget(this.benchmark, this.size, {this.range});

  final Benchmark benchmark;
  final Size size;
  final ValueNotifier<RangeValues> range;

  @override String get taskName => benchmark.descriptor.taskName;
  @override int get valueCount => benchmark.values.length;
  @override double get goal => benchmark.descriptor.goal;
  @override double get baseline => benchmark.descriptor.baseline;

  @override
  Future<DashboardBenchmarkItemBase> makeDetail({
    Size size,
    ValueNotifier<RangeValues> range,
  }) async {
    return DashboardBenchmarkItemWidget(await benchmark.getFullHistory(base: ''), size, range: range);
  }

  @override
  State<StatefulWidget> createState() => DashboardBenchmarkItemState();
}

class DashboardBenchmarkItemState extends State<DashboardBenchmarkItemWidget> {
  @override
  void initState() {
    super.initState();
    if (widget.range != null) {
      widget.range.addListener(() => setState(() {}));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        CustomPaint(
          size: widget.size,
          painter: DashboardItemPainter(widget.benchmark, widget.range?.value),
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
    this.range,
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
  final RangeValues range;
  final double worst;

  Color Function(TimeSeriesValue) _validColor(Color c) =>
          (TimeSeriesValue tsv) => tsv.dataMissing ? Colors.grey.shade200 : c;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint();
    _paintSeries(canvas, size, paint, worstBenchmark.values,     range, worst, _validColor(Colors.red));
    _paintSeries(canvas, size, paint, percent99Benchmark.values, range, worst, _validColor(Colors.yellow));
    _paintSeries(canvas, size, paint, percent90Benchmark.values, range, worst, _validColor(Colors.green.shade200));
    _paintSeries(canvas, size, paint, averageBenchmark.values,   range, worst, _validColor(Colors.green));
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
    this.range,
  });

  final String label;
  final Size size;
  final Benchmark averageBenchmark;
  final Benchmark percent90Benchmark;
  final Benchmark percent99Benchmark;
  final Benchmark worstBenchmark;
  final ValueNotifier<RangeValues> range;

  @override String get taskName => averageBenchmark.descriptor.taskName;
  @override int get valueCount => averageBenchmark.values.length;
  @override double get goal => null;
  @override double get baseline => null;

  @override
  Future<DashboardBenchmarkItemBase> makeDetail(
      {Size size, ValueNotifier<RangeValues> range}) async {
    final Future<Benchmark> historicalAverages  = averageBenchmark.getFullHistory(base: '');
    final Future<Benchmark> historicalPercent90 = percent90Benchmark.getFullHistory(base: '');
    final Future<Benchmark> historicalPercent99 = percent99Benchmark.getFullHistory(base: '');
    final Future<Benchmark> historicalWorsts    = worstBenchmark.getFullHistory(base: '');
    return DashboardItemSetWidget(
      label: label,
      size: size,
      averageBenchmark:   await historicalAverages,
      percent90Benchmark: await historicalPercent90,
      percent99Benchmark: await historicalPercent99,
      worstBenchmark:     await historicalWorsts,
      range: range,
    );
  }

  @override
  State<StatefulWidget> createState() => DashboardItemSetState();
}

class DashboardItemSetState extends State<DashboardItemSetWidget> {
  @override
  void initState() {
    super.initState();
    if (widget.range != null) {
      widget.range.addListener(() => setState(() {}));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        CustomPaint(
          size: widget.size,
          painter: DashboardItemSetPainter(
            averageBenchmark:   widget.averageBenchmark,
            percent90Benchmark: widget.percent90Benchmark,
            percent99Benchmark: widget.percent99Benchmark,
            worstBenchmark:     widget.worstBenchmark,
            range: widget.range?.value,
          ),
          isComplex: true,
          willChange: false,
        ),
        Text(widget.label, style: const TextStyle(fontSize: 9.0)),
      ],
    );
  }
}
