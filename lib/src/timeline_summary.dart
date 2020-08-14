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

class TimelineThreadResults extends Iterable<TimeFrame> {
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
    final List<TimeFrame> frames = _getSortedFrameListFromEvents(eventList, eventKey);
    if (frames.isEmpty) {
      throw 'No $eventKey events found in trace';
    }
    final List<TimeFrame> immutableFrames = List<TimeFrame>.unmodifiable(frames);

    // Then sort by duration for statistics
    frames.sort(TimeFrame.durationOrder);
    final TimeVal durationSum = frames.fold(TimeVal.zero, (TimeVal prev, TimeFrame e) => prev + e.duration);
    return TimelineThreadResults._internal(
      titleName:  titleName,
      frames:     immutableFrames,
      average:    durationSum * (1.0 / frames.length),
      percent90:  _percent(frames, 90).duration,
      percent99:  _percent(frames, 99).duration,
      worst:      frames.last.duration,
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
      threadInfo.averageKey:   average.millis,
      threadInfo.percent90Key: percent90.millis,
      threadInfo.percent99Key: percent99.millis,
      threadInfo.worstKey:     worst.millis,
      threadInfo.startKey:     List<num>.generate(frames.length, (int i) => (frames[i].start - threadStart).micros),
      threadInfo.durationKey:  List<num>.generate(frames.length, (int i) => frames[i].duration.micros),
    };
  }

  final String titleName;
  final TimeVal average;
  final TimeVal percent90;
  final TimeVal percent99;
  final TimeVal worst;
  final List<TimeFrame> frames;

  int get frameCount => frames.length;

  @override
  Iterator<TimeFrame> get iterator => frames.iterator;

  TimeVal get start => frames.first.start;
  TimeVal get end => frames.last.end;
  TimeVal get duration => end - start;
  TimeFrame get wholeRun => TimeFrame(start: start, end: end);

  static TimeVal _getTimeVal(Map<String,dynamic> jsonMap, String key) {
    final dynamic rawTimeVal = jsonMap[key];
    if (rawTimeVal is num) {
      return TimeVal.fromMillis(rawTimeVal);
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

  static List<TimeFrame> _getFrameListMicros(Map<String,dynamic> jsonMap, String startKey, String durationKey) {
    final List<dynamic> starts = _getList(jsonMap, startKey, 'start times');
    final List<dynamic> durations = _getList(jsonMap, durationKey, 'durations');
    if (starts.length != durations.length) {
      throw 'frame start times ($startKey) and frame durations ($durationKey) not the same length';
    }
    return List<TimeFrame>.generate(starts.length, (int index) =>
        TimeFrame(
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
              } else if (name != ThreadInfo.render.eventKey) {
                hasRender = true;
              } else {
                keys.add(name);
              }
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

  static List<TimeFrame> _getSortedFrameListFromEvents(List<dynamic> eventList, String key) {
    final List<TimeFrame> frames = <TimeFrame>[];
    TimeVal startMicros;
    bool isSorted = true;
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
              frames.add(TimeFrame(start: startMicros, end: endMicros));
              startMicros = null;
              if (isSorted && frames.last.start < frames[frames.length - 1].start) {
                isSorted = false;
              }
            }
            break;
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

  TimeFrame _find(TimeVal t, bool strict) {
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
    final TimeFrame loEvent = frames[lo];
    if (loEvent.contains(t)) {
      return loEvent;
    }
    if (strict) {
      return null;
    } else {
      if (lo >= frameCount) {
        return loEvent;
      }
      final TimeFrame hiEvent = frames[lo + 1];
      return (t - loEvent.end < hiEvent.start - t) ? loEvent : hiEvent;
    }
  }

  TimeFrame eventAt(TimeVal t) => _find(t, true);
  TimeFrame eventNear(TimeVal t) => _find(t, false);

  String labelFor(TimeVal t) {
    return (t < average) ? 'Good'
        : (t < percent90) ? 'Nominal'
        : (t < percent99) ? '90th Percentile'
        : '99th Percentile';
  }

  int heatIndex(TimeVal t) {
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
