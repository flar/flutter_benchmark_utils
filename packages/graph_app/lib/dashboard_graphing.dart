// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import 'package:http/http.dart' as http;
import 'package:flutter_benchmark_utils/benchmark_data.dart';

import 'input_utils.dart';

Future<void> _openUrl(String url) async {
  await http.get('/launchUrl?url=${Uri.encodeComponent(url)}');
}

int _clamp(int index, List<dynamic> list) {
  if (index >= list.length)
    index = list.length - 1;
  if (index < 0)
    index = 0;
  return index;
}

TimeSeriesValue _getValue(Benchmark benchmark, int index) {
  return benchmark.values[benchmark.values.length - 1 - index];
}

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

  bool _matches(RegExp regexp, String name) {
    if (regexp == null)
      return true;
    if (name == null)
      return false;
    return regexp.hasMatch(name);
  }

  bool isShown(Benchmark benchmark) {
    if (!showArchived && benchmark.archived)
      return false;
    if (!showEmpty && _isEmpty(benchmark))
      return false;
    if (!_matches(taskRegExp, benchmark.task))
      return false;
    if (!_matches(labelRegExp, benchmark.descriptor.label))
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
      widgets.add(DashboardBenchmarkItemWidget(benchmark: benchmark, size: size));
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
            return RepaintBoundary(child: w);
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
  ValueNotifier<BenchmarkCursor> cursor = ValueNotifier<BenchmarkCursor>(null);
  double count;

  double get _rangeWidth => range.value.end - range.value.start;
  double get _rangeCenter => (range.value.start + range.value.end) * 0.5;

  @override
  void initState() {
    super.initState();
    range.addListener(_update);
    cursor.addListener(_update);
    _getHistory();
  }

  void _update() {
    setState(() {});
  }

  void _getHistory() {
    widget.tile.makeDetail(
      size: const Size(800.0, 200.0),
      range: range,
      cursor: cursor,
    ).then((DashboardBenchmarkItemBase value) {
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

  void _setRange(RangeValues newRange) {
    range.value = newRange;
  }

  void _setRangeCenter(double newCenter) {
    double delta = newCenter - _rangeCenter;
    if (range.value.end + delta > count) {
      delta = count - range.value.end;
    }
    if (range.value.start + delta < 0.0) {
      delta = 0.0 - range.value.start;
    }
    range.value = RangeValues(range.value.start + delta, range.value.end + delta);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text('History of ${widget.tile.taskName}', style: const TextStyle(fontSize: 20.0),),
        const SizedBox(height: 20.0),
        Center(
          child: history ?? const Text('Loading history'),
        ),
        const SizedBox(height: 20.0),
        if (range.value != null && count != null)
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 800 * (1 - _rangeWidth / count),
                child: Slider(
                  min: _rangeWidth * 0.5,
                  max: count - _rangeWidth * 0.5,
                  value: _rangeCenter,
                  onChanged: _setRangeCenter,
                ),
              ),
              Container(
                width: 800,
                child: RangeSlider(
                  min: 0.0,
                  max: count,
                  values: range.value,
                  onChanged: _setRange,
                ),
              ),
            ],
          ),
        if (cursor.value != null)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (cursor.value.bumpLeft != null)
                FlatButton(onPressed: cursor.value.bumpLeft, child: const Icon(Icons.keyboard_arrow_left)),
              Column(
                children: <Widget>[
                  HttpLink.fromGitRevision('Revision: ', cursor.value.value.revision),
                  Text('Created On: ${cursor.value.value.createTimestamp}'),
                ],
              ),
              if (cursor.value.bumpRight != null)
                FlatButton(onPressed: cursor.value.bumpRight, child: const Icon(Icons.keyboard_arrow_right)),
            ],
          ),
      ],
    );
  }
}

@immutable
class HttpLink extends StatelessWidget {
  const HttpLink.fromGitRevision(this.label, this.linkText)
      : url = 'https://github.com/flutter/flutter/commit/$linkText';

  final String label;
  final String linkText;
  final String url;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(label),
        GestureDetector(
          child: Text(linkText, style: const TextStyle(color: Colors.blue, decoration: TextDecoration.underline)),
          onTap: () => _openUrl(url),
        ),
      ],
    );
  }
}

@immutable
class BenchmarkCursor {
  const BenchmarkCursor({
    this.index,
    this.value,
    this.temporary,
    this.bumpLeft,
    this.bumpRight,
  });

  final int index;
  final TimeSeriesValue value;
  final bool temporary;

  final void Function() bumpLeft;
  final void Function() bumpRight;
}

abstract class DashboardBenchmarkItemBase extends StatefulWidget {
  const DashboardBenchmarkItemBase({
    this.size,
    this.isHistory = false,
    this.range,
    this.cursor,
  });

  final Size size;
  final bool isHistory;
  final ValueNotifier<RangeValues> range;
  final ValueNotifier<BenchmarkCursor> cursor;

  String get taskName;
  String get label;
  int get valueCount;
  double get goal;
  double get baseline;

  Future<DashboardBenchmarkItemBase> makeDetail({
    Size size,
    ValueNotifier<RangeValues> range,
    ValueNotifier<BenchmarkCursor> cursor,
  });
}

abstract class _DashboardItemPainterBase extends CustomPainter {
  void _paintSeries(
      Canvas canvas,
      Size size,
      Paint paint,
      Benchmark benchmark,
      RangeValues range,
      double worst,
      Color colorFor(TimeSeriesValue tsv)) {
    final int numValues = benchmark.values.length;
    range ??= RangeValues(0, numValues.toDouble());
    final double dx = size.width / (range.end - range.start);
    int index = range.start.floor();
    double x = dx * (index - range.start);
    while (index < numValues && x < size.width) {
      final TimeSeriesValue tsv = _getValue(benchmark, index);
      paint.color = colorFor(tsv);
      final double v = tsv.dataMissing ? worst : tsv.value;
      final double y = size.height * (1 - v / worst);
      final double x0 = max(x, 0);
      final double x1 = min(x + dx, size.width);
      canvas.drawRect(Rect.fromLTRB(x0, y, x1, size.height), paint);
      x += dx;
      index++;
    }
  }

  void _paintHighlight(
      Canvas canvas,
      Size size,
      Paint paint,
      Benchmark benchmark,
      int valueIndex,
      RangeValues range,
      bool paintValue) {
    // values go from most recent at index 0 to earlier values as index increases
    // range specifies leftmost (oldest) to rightmost (newest)
    // values[len - range.end] plots at size.width
    // values[len - range.start] plots at 0
    const TextStyle style = TextStyle(
      color: Colors.black,
    );
    final int numValues = benchmark.values.length;
    range ??= RangeValues(0, numValues.toDouble());
    if (valueIndex < range.start.floor() || valueIndex >= range.end.ceil()) {
      return;
    }
    final double dx = size.width / (range.end - range.start);
    final double x = (valueIndex + 0.5 - range.start) * dx;
    canvas.drawRect(Rect.fromLTWH(x - 0.5, 0.0, 1.0, size.height), paint);
    if (paintValue) {
      final String label = _getValue(benchmark, valueIndex).toString();
      final TextSpan span = TextSpan(text: label, style: style);
      final TextPainter textPainter = TextPainter(text: span);
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - textPainter.width / 2.0, -textPainter.height));
    }
  }

  void _drawLine(Canvas canvas, Size size, Paint paint, double y, Color heatColor) {
    paint.color = heatColor.withAlpha(128);
    paint.strokeWidth = 1.0;
    const double dashLen = 10.0;
    for (double x = 0; x < size.width; x += dashLen + dashLen) {
      canvas.drawLine(Offset(x, y), Offset(x + dashLen, y), paint);
    }
  }
}

class _DashboardItemPainter extends _DashboardItemPainterBase {
  _DashboardItemPainter({
    this.benchmark,
    this.highlightIndex,
    this.range,
  });

  final Benchmark benchmark;
  final int highlightIndex;
  final RangeValues range;

  Color _colorFor(TimeSeriesValue tsv) {
    if (tsv.dataMissing) {
      return Colors.grey.shade400.withAlpha(128);
    }
    if (tsv.value < benchmark.descriptor.goal) {
      return Colors.green;
    }
    if (tsv.value < benchmark.descriptor.baseline) {
      return Colors.green.shade200;
    }
    return Colors.red;
  }

  double _yFor(double v, double worst, Size size) {
    return size.height * (1 - v / worst);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint();
    if (highlightIndex != null) {
      paint.color = Colors.black;
      _paintHighlight(canvas, size, paint, benchmark, highlightIndex, range, true);
    }
    _paintSeries(canvas, size, paint, benchmark, range, benchmark.worst, _colorFor);
    _drawLine(canvas, size, paint, _yFor(benchmark.descriptor.goal, benchmark.worst, size), Colors.green);
    _drawLine(canvas, size, paint, _yFor(benchmark.descriptor.baseline, benchmark.worst, size), Colors.red);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

class DashboardBenchmarkItemWidget extends DashboardBenchmarkItemBase {
  const DashboardBenchmarkItemWidget({
    this.benchmark,
    Size size,
    bool isHistory = false,
    ValueNotifier<RangeValues> range,
    ValueNotifier<BenchmarkCursor> cursor,
  }) : super(size: size, isHistory: isHistory, range: range, cursor: cursor);

  final Benchmark benchmark;

  @override String get taskName => benchmark.descriptor.taskName;
  @override String get label => benchmark.descriptor.label;
  @override int get valueCount => benchmark.values.length;
  @override double get goal => benchmark.descriptor.goal;
  @override double get baseline => benchmark.descriptor.baseline;

  @override
  Future<DashboardBenchmarkItemBase> makeDetail({
    Size size,
    ValueNotifier<RangeValues> range,
    ValueNotifier<BenchmarkCursor> cursor,
  }) async {
    return DashboardBenchmarkItemWidget(
      benchmark: await benchmark.getFullHistory(base: ''),
      size: size,
      isHistory: true,
      range: range,
      cursor: cursor,
    );
  }

  @override
  State<StatefulWidget> createState() => DashboardBenchmarkItemState();
}

abstract class DashboardBenchmarkItemStateBase<T extends DashboardBenchmarkItemBase> extends State<T> {
  final GlobalKey _mouseKey = GlobalKey();
  bool _wasLocked = false;
  bool _locked = false;
  ValueNotifier<BenchmarkCursor> _cursor;

  RangeValues _defaultRange;
  RangeValues get _range => widget.range?.value ?? _defaultRange;
  Benchmark get main;

  @override
  void initState() {
    super.initState();
    _defaultRange = RangeValues(0, main.values.length.toDouble());
    if (widget.range != null) {
      widget.range.addListener(_update);
    }
    _cursor = widget.cursor ?? ValueNotifier<BenchmarkCursor>(null);
    _cursor.addListener(_update);
  }

  String get _goalString;

  void _update() {
    setState(() {});
  }

  void _setSelected(int index, bool temporary) {
    if (index == null) {
      _cursor.value = null;
      return;
    }
    index = _clamp(index, main.values);
    _adjustRange(index);
    final BenchmarkCursor current = _cursor.value;
    if (current == null || current.index != index || current.temporary != temporary) {
      _cursor.value = BenchmarkCursor(
        index: index,
        value: _getValue(main, index),
        temporary: temporary,
        bumpLeft: temporary ? null : () => _setSelected(index - 1, false),
        bumpRight: temporary ? null : () => _setSelected(index + 1, false),
      );
    }
  }

  void _adjustRange(int index) {
    final RangeValues range = widget.range?.value;
    if (range != null) {
      double bump = 0;
      if (index + 1 > range.end) {
        bump = index + 1 - range.end;
      }
      if (index < range.start) {
        bump = index - range.start;
      }
      if (bump != 0) {
        widget.range.value = RangeValues(range.start + bump, range.end + bump);
      }
    }
  }

  void _onMouse(Offset position, bool temporary) {
    _setSelected(position.dx.floor(), temporary);
  }

  void _onHover(Offset position) {
    if (!_locked) {
      _onMouse(position, true);
    }
  }

  void _onExit(Offset position) {
    if (!_locked)
      _setSelected(null, true);
  }

  bool _onPanDown(Offset position) {
    _onMouse(position, true);
    return true;
  }

  void _onPanUpdate(Offset position) {
    _onMouse(position, true);
  }

  void _onPanEnd(Offset position) {
    _wasLocked = _locked;
    _locked = true;
    _onMouse(position, false);
  }

  void _onTap() {
    _locked = !_wasLocked;
    _wasLocked = false;
    if (_cursor.value != null) {
      _setSelected(_cursor.value.index, !_locked);
    }
  }

  void _onDoubleTap() {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          child: DashboardHistoryDetailWidget(widget),
        );
      },
    );
  }

  CustomPainter get _painter;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        InputManager(
          scaleTo: Rect.fromLTRB(_range.start, 0, _range.end, 1),
          onHover: _onHover,
          onExit: _onExit,
          onPanDown: _onPanDown,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          onTap: _onTap,
          onDoubleTap: widget.isHistory ? null : _onDoubleTap,
          child: CustomPaint(
            key: _mouseKey,
            size: widget.size,
            painter: _painter,
            isComplex: true,
            willChange: false,
          ),
        ),
        Text(widget.label),
        if (_goalString != null)
          Text(_goalString),
      ],
    );
  }
}

class DashboardBenchmarkItemState extends DashboardBenchmarkItemStateBase<DashboardBenchmarkItemWidget> {
  @override Benchmark get main => widget.benchmark;

  @override String get _goalString =>
      'Goal: ${main.descriptor.goal}, Baseline: ${main.descriptor.baseline}';

  @override CustomPainter get _painter => _DashboardItemPainter(
    benchmark: widget.benchmark,
    highlightIndex: _cursor.value?.index,
    range: widget.range?.value,
  );
}

class _DashboardItemSetPainter extends _DashboardItemPainterBase {
  _DashboardItemSetPainter({
    @required this.averageBenchmark,
    @required this.percent90Benchmark,
    @required this.percent99Benchmark,
    @required this.worstBenchmark,
    this.highlightIndex,
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
  final int highlightIndex;
  final RangeValues range;
  final double worst;

  static double _worstValue(Benchmark benchmark) {
    double worst = benchmark.descriptor.baseline;
    for (final TimeSeriesValue tsv in benchmark.values) {
      if (!tsv.dataMissing && worst < tsv.value) {
        worst = tsv.value;
      }
    }
    return (worst == 0) ? 1 : worst;
  }

  static double _worstValueList(List<Benchmark> benchmarks) {
    double worst = 0;
    for (final Benchmark benchmark in benchmarks) {
      final double w = _worstValue(benchmark);
      if (worst < w) {
        worst = w;
      }
    }
    return (worst == 0) ? 1 : worst;
  }

  Color Function(TimeSeriesValue) _validColor(Color c) =>
          (TimeSeriesValue tsv) => tsv.dataMissing ? Colors.grey.shade200 : c;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint();
    if (highlightIndex != null) {
      paint.color = Colors.black;
      _paintHighlight(canvas, size, paint, averageBenchmark, highlightIndex, range, false);
    }
    _paintSeries(canvas, size, paint, worstBenchmark,     range, worst, _validColor(Colors.red));
    _paintSeries(canvas, size, paint, percent99Benchmark, range, worst, _validColor(Colors.yellow));
    _paintSeries(canvas, size, paint, percent90Benchmark, range, worst, _validColor(Colors.green.shade200));
    _paintSeries(canvas, size, paint, averageBenchmark,   range, worst, _validColor(Colors.green));
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

class DashboardItemSetWidget extends DashboardBenchmarkItemBase {
  const DashboardItemSetWidget({
    @required this.label,
    @required this.averageBenchmark,
    @required this.percent90Benchmark,
    @required this.percent99Benchmark,
    @required this.worstBenchmark,
    Size size,
    bool isHistory = false,
    ValueNotifier<RangeValues> range,
    ValueNotifier<BenchmarkCursor> cursor,
  }) : super(size: size, isHistory: isHistory, range: range, cursor: cursor);

  @override final String label;
  final Benchmark averageBenchmark;
  final Benchmark percent90Benchmark;
  final Benchmark percent99Benchmark;
  final Benchmark worstBenchmark;

  @override String get taskName => averageBenchmark.descriptor.taskName;
  @override int get valueCount => averageBenchmark.values.length;
  @override double get goal => null;
  @override double get baseline => null;

  @override
  Future<DashboardBenchmarkItemBase> makeDetail({
    Size size,
    ValueNotifier<RangeValues> range,
    ValueNotifier<BenchmarkCursor> cursor,
  }) async {
    final Future<Benchmark> historicalAverages  = averageBenchmark.getFullHistory(base: '');
    final Future<Benchmark> historicalPercent90 = percent90Benchmark.getFullHistory(base: '');
    final Future<Benchmark> historicalPercent99 = percent99Benchmark.getFullHistory(base: '');
    final Future<Benchmark> historicalWorsts    = worstBenchmark.getFullHistory(base: '');
    return DashboardItemSetWidget(
      label: label,
      averageBenchmark:   await historicalAverages,
      percent90Benchmark: await historicalPercent90,
      percent99Benchmark: await historicalPercent99,
      worstBenchmark:     await historicalWorsts,
      size: size,
      isHistory: true,
      range: range,
      cursor: cursor,
    );
  }

  @override
  State<StatefulWidget> createState() => DashboardItemSetState();
}

class DashboardItemSetState extends DashboardBenchmarkItemStateBase<DashboardItemSetWidget> {
  @override Benchmark get main => widget.averageBenchmark;
  @override String get _goalString => null;

  @override CustomPainter get _painter => _DashboardItemSetPainter(
    averageBenchmark:   widget.averageBenchmark,
    percent90Benchmark: widget.percent90Benchmark,
    percent99Benchmark: widget.percent99Benchmark,
    worstBenchmark:     widget.worstBenchmark,
    highlightIndex: widget.isHistory ? _cursor.value?.index : null,
    range: widget.range?.value,
  );
}
