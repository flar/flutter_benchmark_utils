// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:meta/meta.dart';

import 'benchmark_utils.dart';
import 'time_utils.dart';

@immutable
class ThreadInfo {
  const ThreadInfo._({
    @required this.titleName,
    @required this.keyString,
    @required this.startKey,
    @required this.durationKey,
    @required this.eventKey,
  });

  static const ThreadInfo build = ThreadInfo._(
    titleName:   'Build',
    keyString:   'build',
    startKey:    'frame_begin_times',
    durationKey: 'frame_build_times',
    eventKey:    'Frame',
  );
  static const ThreadInfo render = ThreadInfo._(
    titleName:   'Render',
    keyString:   'rasterizer',
    startKey:    'frame_rasterizer_begin_times',
    durationKey: 'frame_rasterizer_times',
    eventKey:    'GPURasterizer::Draw',
  );

  final String titleName;
  final String keyString;
  final String startKey;
  final String durationKey;
  final String eventKey;

  String _measurementKey(String prefix) =>
      '${prefix}_frame_${keyString}_time_millis';

  String get averageKey   => _measurementKey('average');
  String get percent90Key => _measurementKey('90th_percentile');
  String get percent99Key => _measurementKey('99th_percentile');
  String get worstKey     => _measurementKey('worst');
}

abstract class GraphableEvent extends TimeFrame implements Comparable<GraphableEvent> {
  GraphableEvent({@required TimeVal start, TimeVal end, TimeVal duration})
      : super(start: start, end: end, duration: duration);

  double get value;
  String get valueString;
  String get units;

  @override int compareTo(GraphableEvent other) => value.compareTo(other.value);
}

class MillisDurationEvent extends GraphableEvent {
  MillisDurationEvent({@required TimeVal start, TimeVal end, TimeVal duration})
      : super(start: start, end: end, duration: duration);

  @override double get value => duration.millis;
  @override String get valueString => duration.stringMillis();
  @override String get units => 'ms';
}

class PercentUsageEvent extends GraphableEvent {
  PercentUsageEvent({@required TimeVal measurementTime, @required this.percent})
      : super(start: measurementTime, duration: TimeVal.fromNanos(1));

  final double percent;

  @override double get value => percent;
  @override String get valueString => '${percent.toStringAsFixed(1)}%';
  @override String get units => '%';
}

class TimelineThreadResults extends Iterable<GraphableEvent> {
  factory TimelineThreadResults.fromSummaryMap(Map<String,dynamic> jsonMap, ThreadInfo threadInfo) {
    return TimelineThreadResults._internal(
      titleName:  threadInfo.titleName,
      frames:     _getFrameListMicros(jsonMap, threadInfo.startKey, threadInfo.durationKey),
      average:    _getTimeVal(jsonMap, threadInfo.averageKey),
      percent90:  _getTimeVal(jsonMap, threadInfo.percent90Key),
      percent99:  _getTimeVal(jsonMap, threadInfo.percent99Key),
      worst:      _getTimeVal(jsonMap, threadInfo.worstKey),
    );
  }

  factory TimelineThreadResults.fromEvents({
    @required List<dynamic> eventList,
    @required String titleName,
    @required String eventKey
  }) {
    final List<GraphableEvent> frames = _getSortedFrameListFromEvents(eventList, eventKey);
    if (frames.isEmpty) {
      throw 'No $eventKey events found in trace';
    }
    final List<GraphableEvent> immutableFrames = List<GraphableEvent>.unmodifiable(frames);

    // Then sort by duration for statistics
    frames.sort();
    final double valueSum = frames.fold(0.0, (double prev, GraphableEvent e) => prev + e.value);
    return TimelineThreadResults._internal(
      titleName:  titleName,
      frames:     immutableFrames,
      average:    valueSum * (1.0 / frames.length),
      percent90:  _percent(frames, 90).value,
      percent99:  _percent(frames, 99).value,
      worst:      frames.last.value,
    );
  }

  TimelineThreadResults._internal({
    @required this.titleName,
    @required this.frames,
    @required this.average,
    @required this.percent90,
    @required this.percent99,
    @required this.worst,
  })
      : assert(titleName != null),
        assert(frames != null),
        assert(average != null),
        assert(percent90 != null),
        assert(percent99 != null),
        assert(worst != null);

  static bool hasSummaryValues(Map<String,dynamic> jsonMap, ThreadInfo threadInfo) {
    try {
      BenchmarkUtils.validateJsonEntryIsNumber(jsonMap, threadInfo.averageKey);
      BenchmarkUtils.validateJsonEntryIsNumber(jsonMap, threadInfo.percent90Key);
      BenchmarkUtils.validateJsonEntryIsNumber(jsonMap, threadInfo.percent99Key);
      BenchmarkUtils.validateJsonEntryIsNumber(jsonMap, threadInfo.worstKey);
      BenchmarkUtils.validateJsonEntryIsNumberList(jsonMap, threadInfo.startKey);
      BenchmarkUtils.validateJsonEntryIsNumberList(jsonMap, threadInfo.durationKey);
      return true;
    } catch (_) {
      return false;
    }
  }

  Map<String,dynamic> _summaryMap(ThreadInfo threadInfo) {
    final TimeVal threadStart = frames.first.start;
    return <String,dynamic>{
      threadInfo.averageKey:   average,
      threadInfo.percent90Key: percent90,
      threadInfo.percent99Key: percent99,
      threadInfo.worstKey:     worst,
      threadInfo.startKey:     List<num>.generate(frames.length, (int i) => (frames[i].start - threadStart).micros),
      threadInfo.durationKey:  List<num>.generate(frames.length, (int i) => frames[i].duration.micros),
    };
  }

  final String titleName;
  final double average;
  final double percent90;
  final double percent99;
  final double worst;
  final List<GraphableEvent> frames;

  int get frameCount => frames.length;

  @override
  Iterator<GraphableEvent> get iterator => frames.iterator;

  TimeVal get start => frames.first.start;
  TimeVal get end => frames.last.end;
  TimeVal get duration => end - start;
  TimeFrame get wholeRun => TimeFrame(start: start, end: end);

  static double _getTimeVal(Map<String,dynamic> jsonMap, String key) {
    final dynamic rawTimeVal = jsonMap[key];
    if (rawTimeVal is num) {
      return rawTimeVal.toDouble();
    }
    throw '$key entry is not a number';
  }

  static List<dynamic> _getList(Map<String,dynamic> jsonMap, String key, String description) {
    final dynamic rawStarts = jsonMap[key];
    if (rawStarts is List<dynamic>) {
      return rawStarts;
    }
    throw '$key does not map to a List of $description';
  }

  static List<GraphableEvent> _getFrameListMicros(Map<String,dynamic> jsonMap, String startKey, String durationKey) {
    final List<dynamic> starts = _getList(jsonMap, startKey, 'start times');
    final List<dynamic> durations = _getList(jsonMap, durationKey, 'durations');
    if (starts.length != durations.length) {
      throw 'frame start times ($startKey) and frame durations ($durationKey) not the same length';
    }
    return List<GraphableEvent>.generate(starts.length, (int index) =>
        MillisDurationEvent(
          start: TimeVal.fromMicros(starts[index] as num),
          duration: TimeVal.fromMicros(durations[index] as num),
        ),
      growable: false,
    );
  }

  static List<String> getEventKeys(List<dynamic> eventList) {
    final Set<String> beginKeys = <String>{};
    final Set<String> keys = <String>{};
    bool hasBuild = false;
    bool hasRender = false;
    for (final dynamic rawEvent in eventList) {
      final Map<String,dynamic> event = rawEvent as Map<String,dynamic>;
      final String name = event['name'] as String;
      if (name != null) {
        switch (event['ph'] as String) {
          case 'B':
          case 'b':
            beginKeys.add(name);
            break;
          case 'E':
          case 'e':
            if (beginKeys.contains(name)) {
              // ensures at least one "end" following at least one "begin"
              if (name == ThreadInfo.build.eventKey) {
                hasBuild = true;
              } else if (name == ThreadInfo.render.eventKey) {
                hasRender = true;
              } else {
                keys.add(name);
              }
            }
            break;
          case 'i':
            if (name == 'GpuUsage' || name == 'CpuUsage') {
              keys.add(name);
            }
            break;
        }
      }
    }
    return <String>[
      if (hasBuild) ThreadInfo.build.titleName,
      if (hasRender) ThreadInfo.render.titleName,
      ...keys,
    ];
  }

  static List<GraphableEvent> _getSortedFrameListFromEvents(List<dynamic> eventList, String key) {
    final List<GraphableEvent> frames = <GraphableEvent>[];
    TimeVal startMicros;
    bool isSorted = true;
    final String argKey = key == 'GpuUsage' ? 'gpu_usage'
        : key == 'CpuUsage' ? 'total_cpu_usage' : null;
    for (final dynamic rawEvent in eventList) {
      final Map<String,dynamic> event = rawEvent as Map<String,dynamic>;
      if (event['name'] == key) {
        switch (event['ph'] as String) {
          case 'B':
          case 'b':
            startMicros = TimeVal.fromMicros(event['ts'] as num);
            break;
          case 'E':
          case 'e':
            if (startMicros != null) {
              final TimeVal endMicros = TimeVal.fromMicros(event['ts'] as num);
              frames.add(MillisDurationEvent(start: startMicros, end: endMicros));
              startMicros = null;
              if (isSorted && frames.last.start < frames[frames.length - 1].start) {
                isSorted = false;
              }
            }
            break;
          case 'i': {
            print('found matching instant event');
            final dynamic args = event['args'];
            if (args is Map<String,dynamic>) {
              final dynamic usage = args[argKey];
              if (usage is String) {
                final double usageVal = double.parse(usage);
                final TimeVal measurementUs = TimeVal.fromMicros(event['ts'] as num);
                frames.add(PercentUsageEvent(measurementTime: measurementUs, percent: usageVal));
                if (isSorted && frames.last.start < frames[frames.length - 1].start) {
                  isSorted = false;
                }
              } else {
                print('usage was not a num');
              }
            } else {
              print('args were not a map');
            }
            break;
          }
        }
      }
    }
    if (!isSorted) {
      frames.sort(TimeFrame.startOrder);
    }
    return frames;
  }

  static T _percent<T>(List<T> list, double percent) {
    return list[((list.length - 1) * (percent / 100)).round()];
  }

  GraphableEvent _find(TimeVal t, bool strict) {
    TimeVal loT = start;
    TimeVal hiT = end;
    if (t < loT) {
      return strict ? null : frames.first;
    }
    if (t > hiT) {
      return strict ? null : frames.last;
    }
    int lo = 0;
    int hi = frameCount - 1;
    while (lo < hi) {
      final int mid = (lo + hi) ~/ 2;
      if (mid == lo) {
        break;
      }
      final TimeVal midT = frames[mid].start;
      if (t < midT) {
        hi = mid;
        hiT = midT;
      } else if (t > midT) {
        lo = mid;
        loT = midT;
      }
    }
    final GraphableEvent loEvent = frames[lo];
    if (loEvent.contains(t)) {
      return loEvent;
    }
    if (strict) {
      return null;
    } else {
      if (lo >= frameCount) {
        return loEvent;
      }
      final GraphableEvent hiEvent = frames[lo + 1];
      return (t - loEvent.end < hiEvent.start - t) ? loEvent : hiEvent;
    }
  }

  GraphableEvent eventAt(TimeVal t) => _find(t, true);
  GraphableEvent eventNear(TimeVal t) => _find(t, false);

  String labelFor(double t) {
    return (t < average) ? 'Good'
        : (t < percent90) ? 'Nominal'
        : (t < percent99) ? '90th Percentile'
        : '99th Percentile';
  }

  int heatIndex(double t) {
    return (t < average) ? 0
        : (t < percent90) ? 1
        : (t < percent99) ? 2
        : 3;
  }
}

class TimelineResults {
  factory TimelineResults(Map<String,dynamic> jsonMap) {
    final dynamic rawEvents = jsonMap['traceEvents'];
    if (rawEvents is List) {
      for (final dynamic event in rawEvents) {
        if (event is! Map<String,dynamic>) {
          throw 'trace contains ill-formed event: $event';
        }
      }
      return TimelineResults._internal(
        TimelineThreadResults.fromEvents(
          eventList: rawEvents,
          titleName: ThreadInfo.build.titleName,
          eventKey:  ThreadInfo.build.eventKey,
        ),
        TimelineThreadResults.fromEvents(
          eventList: rawEvents,
          titleName: ThreadInfo.render.titleName,
          eventKey:  ThreadInfo.render.eventKey,
        ),
        TimelineThreadResults.getEventKeys(rawEvents),
        false,
        jsonMap,
      );
    }
    return TimelineResults._internal(
      TimelineThreadResults.fromSummaryMap(jsonMap, ThreadInfo.build),
      TimelineThreadResults.fromSummaryMap(jsonMap, ThreadInfo.render),
      <String>[ ThreadInfo.build.titleName, ThreadInfo.render.titleName, ],
      true,
      jsonMap,
    );
  }

  TimelineResults._internal(this.buildData, this.renderData, this.measurements, this.isSummary, this._jsonMap)
      : assert(buildData != null),
        assert(renderData != null),
        assert(measurements != null),
        assert(isSummary != null),
        assert(_jsonMap != null);

  static bool isTraceMap(Map<String,dynamic> jsonMap) {
    final dynamic rawEvents = jsonMap['traceEvents'];
    if (rawEvents is List) {
      for (final dynamic event in rawEvents) {
        if (event is! Map<String,dynamic>) {
          return false;
        }
      }
      final List<String> eventKeys = TimelineThreadResults.getEventKeys(rawEvents);
      return eventKeys.contains(ThreadInfo.build.titleName)
          && eventKeys.contains(ThreadInfo.render.titleName);
    }
    return false;
  }

  static bool isSummaryMap(Map<String,dynamic> jsonMap) {
    return TimelineThreadResults.hasSummaryValues(jsonMap, ThreadInfo.build)
        && TimelineThreadResults.hasSummaryValues(jsonMap, ThreadInfo.render);
  }

  Map<String,dynamic> get _toSummaryMap {
    return <String,dynamic>{
      ...buildData._summaryMap(ThreadInfo.build),
      ...renderData._summaryMap(ThreadInfo.render),
    };
  }

  String get jsonSummary {
    return const JsonEncoder.withIndent(' ').convert(isSummary ? _jsonMap : _toSummaryMap);
  }

  final TimelineThreadResults buildData;
  final TimelineThreadResults renderData;
  final List<String> measurements;
  final bool isSummary;
  final Map<String,dynamic> _jsonMap;

  TimelineThreadResults getResults(String measurement) {
    assert(measurements.contains(measurement));
    if (measurement == ThreadInfo.build.titleName) {
      return buildData;
    }
    if (measurement == ThreadInfo.render.titleName) {
      return renderData;
    }
    return TimelineThreadResults.fromEvents(
      eventList: _jsonMap['traceEvents'] as List<dynamic>,
      titleName: measurement,
      eventKey:  measurement,
    );
  }
}
