// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'time_utils.dart';

class ThreadInfo {
  static final ThreadInfo build = ThreadInfo._(
    'Build',
    'build',
    'frame_begin_times',
    'frame_build_times',
    'Frame',
  );
  static final ThreadInfo render = ThreadInfo._(
    'Render',
    'rasterizer',
    'frame_rasterizer_begin_times',
    'frame_rasterizer_times',
    'GPURasterizer::Draw',
  );

  ThreadInfo._(this.titleName, this.keyString, this.startKey, this.durationKey, this.timelineKey);

  final String titleName;
  final String keyString;
  final String startKey;
  final String durationKey;
  final String timelineKey;

  String _measurementKey(String prefix) =>
      '${prefix}_frame_${keyString}_time_millis';

  String get averageKey   => _measurementKey('average');
  String get percent90Key => _measurementKey('90th_percentile');
  String get percent99Key => _measurementKey('99th_percentile');
  String get worstKey     => _measurementKey('worst');
}

class TimelineThreadResults extends Iterable<TimeFrame> {
  TimelineThreadResults._internal({
    this.threadInfo,
    this.frames,
    this.average,
    this.percent90,
    this.percent99,
    this.worst
  }) {
    assert(threadInfo != null);
    assert(frames != null);
    assert(average != null);
    assert(percent90 != null);
    assert(percent99 != null);
    assert(worst != null);
  }

  factory TimelineThreadResults.fromSummaryJson(Map<String,dynamic> jsonMap, ThreadInfo threadInfo) {
    return TimelineThreadResults._internal(
      threadInfo: threadInfo,
      frames:     _getFrameListMicros(jsonMap[threadInfo.startKey], jsonMap[threadInfo.durationKey]),
      average:    _getTimeVal(jsonMap[threadInfo.averageKey]),
      percent90:  _getTimeVal(jsonMap[threadInfo.percent90Key]),
      percent99:  _getTimeVal(jsonMap[threadInfo.percent99Key]),
      worst:      _getTimeVal(jsonMap[threadInfo.worstKey]),
    );
  }

  factory TimelineThreadResults.fromEvents(List<dynamic> eventList, ThreadInfo threadInfo) {
    List<TimeFrame> frames = _getSortedFrameListFromEvents(eventList, threadInfo.timelineKey);
    List<TimeFrame> immutableFrames = List.unmodifiable(frames);

    // Then sort by duration for statistics
    frames.sort(TimeFrame.durationOrder);
    TimeVal durationSum = frames.fold(TimeVal.zero, (prev, e) => prev + e.duration);
    return TimelineThreadResults._internal(
      threadInfo: threadInfo,
      frames:     immutableFrames,
      average:    durationSum * (1.0 / frames.length),
      percent90:  _percent(frames, 90).duration,
      percent99:  _percent(frames, 99).duration,
      worst:      frames.last.duration,
    );
  }

  final ThreadInfo threadInfo;

  final TimeVal average;
  final TimeVal percent90;
  final TimeVal percent99;
  final TimeVal worst;
  final List<TimeFrame> frames;

  int get frameCount => frames.length;

  Iterator<TimeFrame> get iterator => frames.iterator;

  TimeVal get start => frames.first.start;
  TimeVal get end => frames.last.end;
  TimeVal get duration => end - start;
  TimeFrame get wholeRun => TimeFrame(start: start, end: end);

  static TimeVal _getTimeVal(dynamic rawTimeVal) {
    assert(rawTimeVal is num);
    return TimeVal.fromMillis(rawTimeVal);
  }

  static List<TimeFrame> _getFrameListMicros(dynamic rawStarts, dynamic rawDurations) {
    if (rawStarts is List<dynamic> && rawDurations is List<dynamic> &&
        rawStarts.length == rawDurations.length)
    {
      return List<TimeFrame>.generate(rawStarts.length, (index) =>
          TimeFrame(
            start: TimeVal.fromMicros(rawStarts[index]),
            duration: TimeVal.fromMicros(rawDurations[index]),
          ),
        growable: false,
      );
    }
    return null;
  }

  static List<TimeFrame> _getSortedFrameListFromEvents(List<dynamic> eventList, String key) {
    List<TimeFrame> frames = <TimeFrame>[];
    TimeVal startMicros;
    bool isSorted = true;
    for (Map<String,dynamic> event in eventList) {
      if (event['name'] == key) {
        switch (event['ph']) {
          case 'B':
            startMicros = TimeVal.fromMicros(event['ts'] as num);
            break;
          case 'E':
            if (startMicros != null) {
              TimeVal endMicros = TimeVal.fromMicros(event['ts'] as num);
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
    if (t < loT) return strict ? null : frames.first;
    if (t > hiT) return strict ? null : frames.last;
    int lo = 0;
    int hi = frameCount - 1;
    while (lo < hi) {
      int mid = (lo + hi) ~/ 2;
      if (mid == lo) break;
      TimeVal midT = frames[mid].start;
      if (t < midT) {
        hi = mid;
        hiT = midT;
      } else if (t > midT) {
        lo = mid;
        loT = midT;
      }
    }
    TimeFrame loEvent = frames[lo];
    if (loEvent.contains(t)) return loEvent;
    if (strict) {
      return null;
    } else {
      if (lo >= frameCount) return loEvent;
      TimeFrame hiEvent = frames[lo + 1];
      return (t - loEvent.end < hiEvent.start - t) ? loEvent : hiEvent;
    }
  }

  TimeFrame eventAt(TimeVal t) => _find(t, true);
  TimeFrame eventNear(TimeVal t) => _find(t, false);

  String labelFor(TimeVal t) {
    if (t < average) return 'Good';
    if (t < percent90) return 'Nominal';
    if (t < percent99) return '90th Percentile';
    return '99th Percentile';
  }

  int heatIndex(TimeVal t) {
    if (t < average) return 0;
    if (t < percent90) return 1;
    if (t < percent99) return 2;
    return 3;
  }
}

class TimelineResults {
  TimelineResults._internal(this.buildData, this.renderData)
      : assert(buildData != null),
        assert(renderData != null);

  factory TimelineResults(Map<String,dynamic> jsonMap) {
    try {
      var rawEvents = jsonMap['traceEvents'];
      if (rawEvents is List) {
        bool mapList = true;
        for (var event in rawEvents) {
          if (event is! Map<String,dynamic>) {
            mapList = false;
            print('$event is not a dynamic String map');
            break;
          }
        }
        if (mapList) {
          return TimelineResults._internal(
            TimelineThreadResults.fromEvents(rawEvents, ThreadInfo.build),
            TimelineThreadResults.fromEvents(rawEvents, ThreadInfo.render),
          );
        }
      }
    } catch (e) {}
    try {
      return TimelineResults._internal(
        TimelineThreadResults.fromSummaryJson(jsonMap, ThreadInfo.build),
        TimelineThreadResults.fromSummaryJson(jsonMap, ThreadInfo.render),
      );
    } catch (e) {}
    return null;
  }

  final TimelineThreadResults buildData;
  final TimelineThreadResults renderData;
}
