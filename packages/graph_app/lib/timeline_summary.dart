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
  );
  static final ThreadInfo render = ThreadInfo._(
    'Render',
    'rasterizer',
    'frame_rasterizer_begin_times',
    'frame_rasterizer_times',
  );

  ThreadInfo._(this.titleName, this.keyString, this.startKey, this.durationKey);

  final String titleName;
  final String keyString;
  final String startKey;
  final String durationKey;

  String _measurementKey(String prefix) =>
      '${prefix}_frame_${keyString}_time_millis';

  String get averageKey   => _measurementKey('average');
  String get percent90Key => _measurementKey('90th_percentile');
  String get percent99Key => _measurementKey('99th_percentile');
  String get worstKey     => _measurementKey('worst');
}

class TimelineThreadResults extends Iterable<TimeFrame> {
  TimelineThreadResults.fromJson(Map<String,dynamic> jsonMap, this.threadInfo)
      : this.average        = _getTimeVal(jsonMap[threadInfo.averageKey]),
        this.percent90      = _getTimeVal(jsonMap[threadInfo.percent90Key]),
        this.percent99      = _getTimeVal(jsonMap[threadInfo.percent99Key]),
        this.worst          = _getTimeVal(jsonMap[threadInfo.worstKey]),
        this.frameStarts    = _getTimeListMicros(jsonMap[threadInfo.startKey]),
        this.frameDurations = _getTimeListMicros(jsonMap[threadInfo.durationKey])
  {
    assert(this.frameStarts.length == this.frameDurations.length);
  }

  final ThreadInfo threadInfo;

  final TimeVal average;
  final TimeVal percent90;
  final TimeVal percent99;
  final TimeVal worst;
  final List<TimeVal> frameStarts;
  final List<TimeVal> frameDurations;

  int get frameCount => frameStarts.length;

  Iterable<TimeFrame> get frames =>
      Iterable<TimeFrame>.generate(frameCount, (index) => getEvent(index));
  Iterator<TimeFrame> get iterator => frames.iterator;

  TimeVal get start => frameStarts.first;
  TimeVal get end => frameStarts.last + frameDurations.last;
  TimeVal get duration => end - start;
  TimeFrame get wholeRun => TimeFrame(start: start, end: end);

  static TimeVal _getTimeVal(dynamic rawTimeVal) {
    assert(rawTimeVal is num);
    return TimeVal.fromMillis(rawTimeVal);
  }

  static List<TimeVal> _getTimeListMicros(dynamic rawTimes) {
    return (rawTimes as List<dynamic>).map((e) => TimeVal.fromMicros(e)).toList();
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
      TimeVal midT = frameStarts[mid];
      if (t < midT) {
        hi = mid;
        hiT = midT;
      } else if (t > midT) {
        lo = mid;
        loT = midT;
      }
    }
    TimeFrame loEvent = getEvent(lo);
    if (loEvent.contains(t)) return loEvent;
    if (strict) {
      return null;
    } else {
      if (lo >= frameCount) return loEvent;
      TimeFrame hiEvent = getEvent(lo + 1);
      return (t - loEvent.end < hiEvent.start - t) ? loEvent : hiEvent;
    }
  }

  TimeFrame eventAt(TimeVal t) => _find(t, true);
  TimeFrame eventNear(TimeVal t) => _find(t, false);

  TimeFrame getEvent(int index) => TimeFrame(start: frameStarts[index], duration: frameDurations[index]);

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
  TimelineResults.fromJson(Map<String,dynamic> jsonMap)
      : this.buildData  = TimelineThreadResults.fromJson(jsonMap, ThreadInfo.build),
        this.renderData = TimelineThreadResults.fromJson(jsonMap, ThreadInfo.render);

  final TimelineThreadResults buildData;
  final TimelineThreadResults renderData;
}
