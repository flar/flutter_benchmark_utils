// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:meta/meta.dart';

import 'benchmark_utils.dart';
import 'graph_utils.dart';
import 'time_utils.dart';

@immutable
class ThreadInfo {
  const ThreadInfo._({
    required this.titleName,
    required this.keyString,
    required this.startKey,
    required this.durationKey,
    required this.eventKey,
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

class TimelineThreadResults extends GraphableSeries {
  factory TimelineThreadResults.fromSummaryMap(Map<String,dynamic> jsonMap, ThreadInfo threadInfo) {
    final UnitValue worst = _getTimeVal(jsonMap, threadInfo.worstKey);
    final List<GraphableEvent> frames = _getFrameListMicros(jsonMap, threadInfo.startKey, threadInfo.durationKey);
    return TimelineThreadResults._internal(
      titleName:  threadInfo.titleName,
      seriesType: SeriesType.SEQUENTIAL_EVENTS,
      frames:     frames,
      wholeRun:   TimeFrame(start: frames.first.start, end: frames.last.end),
      average:    _getTimeVal(jsonMap, threadInfo.averageKey),
      percent90:  _getTimeVal(jsonMap, threadInfo.percent90Key),
      percent99:  _getTimeVal(jsonMap, threadInfo.percent99Key),
      worst:      worst,
      largest:    worst,
      minRange:   TimeUnits.oneMicrosecond,
    );
  }

  factory TimelineThreadResults.fromEvents({
    required List<dynamic> eventList,
    required String titleName,
    required String eventKey
  }) {
    TimeFrame run = _getEventRange(eventList);
    final List<GraphableEvent> frames = _getSortedFrameListFromEvents(eventList, run, eventKey);
    final List<GraphableEvent> immutableFrames = List<GraphableEvent>.unmodifiable(frames);

    // Then sort by duration for statistics
    frames.sort();
    return TimelineThreadResults._internal(
      titleName:  '$titleName ${frames.first.reading.units.upperPluralDescription}',
      seriesType: frames.first is FlowEvent ? SeriesType.OVERLAPPING_EVENTS : SeriesType.SEQUENTIAL_EVENTS,
      frames:     immutableFrames,
      wholeRun:   run,
      average:    GraphableSeries.computeAverage(frames),
      percent90:  GraphableSeries.locatePercentile(frames, 90).reading,
      percent99:  GraphableSeries.locatePercentile(frames, 99).reading,
      worst:      frames.last.reading,
      largest:    frames.first.lowIsGood ? frames.last.reading : frames.first.reading,
      minRange:   frames.last.minRange,
    );
  }

  TimelineThreadResults._internal({
    required this.titleName,
    required this.seriesType,
    required this.frames,
    required this.wholeRun,
    required this.average,
    required this.percent90,
    required this.percent99,
    required this.worst,
    required this.largest,
    required this.minRange,
  });

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

  @override final String titleName;
  @override final SeriesType seriesType;
  @override final UnitValue average;
  @override final UnitValue percent90;
  @override final UnitValue percent99;
  @override final UnitValue worst;
  @override final UnitValue largest;
  @override final List<GraphableEvent> frames;
  @override final TimeFrame wholeRun;

  @override final UnitValue minRange;

  static UnitValue _getTimeVal(Map<String,dynamic> jsonMap, String key) {
    final dynamic rawTimeVal = jsonMap[key];
    if (rawTimeVal is num) {
      return TimeUnits.millis(rawTimeVal);
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
      final String? name = event['name'] as String?;
      if (name != null) {
        switch (event['ph'] as String) {
          case 'B':
          case 'b':
          case 's':
            beginKeys.add(name);
            break;
          case 'E':
          case 'e':
          case 'f':
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
          case 'X':
            if (name == ThreadInfo.build.eventKey) {
              hasBuild = true;
            } else if (name == ThreadInfo.render.eventKey) {
              hasRender = true;
            } else {
              keys.add(name);
            }
            break;
          case 'C':
            if (name == 'DiffContext' || name == 'RasterCache' || name == 'LayerTree::Usage') {
              final Map<String,dynamic> args = event['args'] as Map<String,dynamic>;
              keys.addAll(args.keys.map((String key) => '$name:$key'));
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
      ...List<String>.of(keys)..sort(),
    ];
  }

  static TimeFrame _incorporate(TimeFrame? run, TimeVal event) {
    run ??= TimeFrame(start: event, end: event);
    if (event < run.start) {
      run = TimeFrame(start: event, end: run.end);
    }
    if (event > run.end) {
      run = TimeFrame(start: run.start, end: event);
    }
    return run;
  }

  static TimeFrame _getEventRange(List<dynamic> eventList) {
    TimeFrame? run;
    for (final dynamic rawEvent in eventList) {
      final Map<String,dynamic> event = rawEvent as Map<String,dynamic>;
      switch (event['ph'] as String) {
        case 'B':
        case 'b':
        case 'E':
        case 'e':
        case 's':
        case 't':
        case 'f':
        case 'C':
        case 'i':
          run = _incorporate(run, TimeVal.fromMicros(event['ts'] as num));
          break;
        case 'X':
          final TimeVal completeStartMicros = TimeVal.fromMicros(event['ts'] as num);
          final TimeVal completeDurationMicros = TimeVal.fromMicros(event['dur'] as num);
          run = _incorporate(run, completeStartMicros);
          run = _incorporate(run, completeStartMicros + completeDurationMicros);
          break;
      }
    }
    return run ?? TimeFrame(start: TimeVal.zero, end: TimeVal.zero);
  }

  static List<GraphableEvent> _getSortedFrameListFromEvents(List<dynamic> eventList, TimeFrame run, String key) {
    final List<GraphableEvent> frames = <GraphableEvent>[];
    List<TimeVal> nestedStarts = <TimeVal>[];
    final Map<int,TimeVal> flowStarts = <int,TimeVal>{};
    final Map<int,List<TimeVal>> flowSteps = <int,List<TimeVal>>{};
    final String name = key.startsWith('DiffContext:') ? 'DiffContext' :
                        key.startsWith('RasterCache:') ? 'RasterCache' :
                        key.startsWith('LayerTree::Usage:') ? 'LayerTree::Usage': key;
    final String argKey = key == 'GpuUsage' ? 'gpu_usage'
        : key == 'CpuUsage' ? 'total_cpu_usage'
        : key.startsWith('DiffContext:') ? key.substring(12)
        : key.startsWith('RasterCache:') ? key.substring(12)
        : key.startsWith('LayerTree::Usage:') ? key.substring(17)
        : 'Unknown';
    for (final dynamic rawEvent in eventList) {
      final Map<String,dynamic> event = rawEvent as Map<String,dynamic>;
      if (event['name'] == name) {
        switch (event['ph'] as String) {
          case 'B':
          case 'b':
            if (nestedStarts.isNotEmpty) {
              print('events are nested');
            }
            nestedStarts.add(TimeVal.fromMicros(event['ts'] as num));
            break;
          case 'E':
          case 'e':
            final TimeVal endMicros = TimeVal.fromMicros(event['ts'] as num);
            if (nestedStarts.isNotEmpty) {
              frames.add(MillisDurationEvent(start: nestedStarts.removeLast(), end: endMicros));
            } else {
              print('mismatched end event for $name');
              frames.add(MillisDurationEvent(start: run.start, end: endMicros));
            }
            break;
          case 's':
            final String idString = event['id'] as String;
            final int id = int.parse(idString, radix: 16);
            if (flowStarts[id] != null) {
              print('replacing phantom flow start time for $id');
            }
            flowStarts[id] = TimeVal.fromMicros(event['ts'] as num);
            if (flowSteps[id] == null) {
              flowSteps[id] = <TimeVal>[];
            }
            break;
          case 't':
            final String idString = event['id'] as String;
            final int id = int.parse(idString, radix: 16);
            final TimeVal stepTime = TimeVal.fromMicros(event['ts'] as num);
            final List<TimeVal>? steps = flowSteps[id];
            if (steps == null) {
              // We are missing a start. Fill in a dummy so that we can at least track the
              // steps and end of flow.
              print('inserting phantom flow start time for $id');
              flowStarts[id] = run.start;
              flowSteps[id] = [stepTime];
            } else {
              steps.add(stepTime);
            }
            break;
          case 'f':
            final String idString = event['id'] as String;
            final int id = int.parse(idString, radix: 16);
            final TimeVal? flowStart = flowStarts.remove(id);
            final TimeVal endMicros = TimeVal.fromMicros(event['ts'] as num);
            if (flowStart != null) {
              final List<TimeVal> steps = flowSteps.remove(id)!;
              frames.add(FlowEvent(start: flowStart, end: endMicros, steps: steps));
            } else {
              frames.add(FlowEvent(start: run.start, end: endMicros, steps: const <TimeVal>[]));
              print('mismatched flow end event for $id');
            }
            break;
          case 'X':
            final TimeVal completeStartMicros = TimeVal.fromMicros(event['ts'] as num);
            final TimeVal completeDurationMicros = TimeVal.fromMicros(event['dur'] as num);
            frames.add(MillisDurationEvent(start: completeStartMicros, duration: completeDurationMicros));
            break;
          case 'C':
          case 'i': {
            final dynamic args = event['args'];
            if (args is Map<String,dynamic>) {
              final dynamic valueString = args[argKey];
              if (valueString is String) {
                print('found $valueString for $argKey');
                final double value = double.parse(valueString);
                final TimeVal measurementUs = TimeVal.fromMicros(event['ts'] as num);
                GraphableEvent? graphEvent;
                switch (name) {
                  case 'DiffContext':
                    graphEvent = PictureCounterEvent(measurementTime: measurementUs, count: value);
                    break;
                  case 'RasterCache':
                    switch(argKey) {
                      case 'LayerCount':
                      case 'PictureCount':
                        graphEvent = PictureCounterEvent(measurementTime: measurementUs, count: value);
                        break;
                      case 'LayerMBytes':
                      case 'PictureMBytes':
                        print('making a memory event');
                        graphEvent = MemorySizeEvent.megabytes(measurementTime: measurementUs, size: value);
                        break;
                    }
                    break;
                  case 'LayerTree::Usage':
                    switch (argKey) {
                      case 'PictureCount':
                        graphEvent = PictureCounterEvent(measurementTime: measurementUs, count: value);
                        break;
                      case 'PictureKBytes':
                        print('making a memory event');
                        graphEvent = MemorySizeEvent.kilobytes(measurementTime: measurementUs, size: value);
                        break;
                    }
                    break;
                  default:
                    graphEvent = PercentUsageEvent(measurementTime: measurementUs, percent: value);
                    break;
                }
                if (graphEvent != null) {
                  frames.add(graphEvent);
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
    for (int id in flowStarts.keys) {
      final TimeVal flowStart = flowStarts[id]!;
      final List<TimeVal> steps = flowSteps.remove(id)!;
      frames.add(FlowEvent(start: flowStart, end: run.end, steps: steps));
      print('manually ending flow $id with ${steps.length} steps');
    }
    frames.sort(TimeFrame.startOrder);
    return frames;
  }
}

class TimelineResults extends GraphableSeriesSource {
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

  TimelineResults._internal(this.buildData, this.renderData, this.allSeriesNames, this.isSummary, this._jsonMap);

  static bool isTraceMap(Map<String,dynamic> jsonMap) {
    final dynamic rawEvents = jsonMap['traceEvents'];
    if (rawEvents is List) {
      for (final dynamic event in rawEvents) {
        if (event is! Map<String,dynamic>) {
          print('not an event: $event');
          return false;
        }
      }
      final List<String> eventKeys = TimelineThreadResults.getEventKeys(rawEvents);
      return true;
      // return eventKeys.contains(ThreadInfo.build.titleName)
      //     && eventKeys.contains(ThreadInfo.render.titleName);
    }
    print('not a list: $rawEvents');
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
  @override final List<String> allSeriesNames;
  final bool isSummary;
  final Map<String,dynamic> _jsonMap;

  @override
  List<GraphableSeries> get defaultGraphs {
    return <GraphableSeries>[buildData, renderData];
  }

  @override
  TimelineThreadResults seriesFor(String seriesName) {
    assert(allSeriesNames.contains(seriesName));
    if (seriesName == ThreadInfo.build.titleName) {
      return buildData;
    }
    if (seriesName == ThreadInfo.render.titleName) {
      return renderData;
    }
    return TimelineThreadResults.fromEvents(
      eventList: _jsonMap['traceEvents'] as List<dynamic>,
      titleName: 'Frame $seriesName',
      eventKey:  seriesName,
    );
  }
}
