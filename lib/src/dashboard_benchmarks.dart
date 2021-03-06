// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

class TimeSeriesDescriptor {
  factory TimeSeriesDescriptor.fromJsonMap(Map<String,dynamic> jsonMap) {
    final Map<String,dynamic> seriesMap = jsonMap['Timeseries'] as Map<String,dynamic>;
    return TimeSeriesDescriptor._(
      archived: seriesMap['Archived'] as bool,
      baseline: seriesMap['Baseline'] as double,
      goal:     seriesMap['Goal'] as double,
      id:       seriesMap['ID'] as String,
      label:    seriesMap['Label'] as String,
      taskName: seriesMap['TaskName'] as String,
      units:    seriesMap['Unit'] as String,
      key:      jsonMap['Key'] as String,
    );
  }

  TimeSeriesDescriptor._({
    @required this.archived,
    @required this.baseline,
    @required this.goal,
    @required this.id,
    @required this.label,
    @required this.taskName,
    @required this.units,
    @required this.key,
  })
      : assert(archived != null),
        assert(baseline != null),
        assert(goal != null),
        assert(id != null),
        assert(label != null),
        assert(taskName != null),
        assert(units != null),
        assert(key != null);

  final bool archived;
  final double baseline;
  final double goal;
  final String id;
  final String label;
  final String taskName;
  final String units;
  final String key;
}

class TimeSeriesValue {
  factory TimeSeriesValue.fromJsonMap(Map<String,dynamic> jsonMap) => TimeSeriesValue._(
    dataMissing:     jsonMap['DataMissing'] as bool,
    value:           jsonMap['Value'] as double,
    createTimestamp: DateTime.fromMillisecondsSinceEpoch(jsonMap['CreateTimestamp'] as int),
    taskKey:         jsonMap['TaskKey'] as String,
    revision:        jsonMap['Revision'] as String,
  );

  TimeSeriesValue._({
    @required this.dataMissing,
    @required this.value,
    @required this.createTimestamp,
    @required this.taskKey,
    @required this.revision,
  });

  final bool dataMissing;
  final double value;
  final DateTime createTimestamp;
  final String taskKey;
  final String revision;

  @override
  String toString() => dataMissing ? 'N/A' : '${value.toStringAsFixed(1)}ms';
}

class Benchmark {
  factory Benchmark.fromJsonMap(Map<String,dynamic> jsonMap) {
    jsonMap = (jsonMap['BenchmarkData'] ?? jsonMap) as Map<String,dynamic>;
    final TimeSeriesDescriptor descriptor = TimeSeriesDescriptor.fromJsonMap(
      jsonMap['Timeseries'] as Map<String,dynamic>,
    );
    final List<dynamic> valueJsonList = jsonMap['Values'] as List<dynamic>;
    final List<TimeSeriesValue> values =
    valueJsonList.map((dynamic e) => TimeSeriesValue.fromJsonMap(e as Map<String,dynamic>))
        .toList();
    return Benchmark._(
      descriptor: descriptor,
      values: values,
      worst: values.fold(0.0, (double previous, TimeSeriesValue tsv) {
        if (tsv.value > previous)
          return tsv.value;
        return previous;
      }),
    );
  }

  factory Benchmark.fromJsonString(String jsonBody) =>
      Benchmark.fromJsonMap(const JsonDecoder().convert(jsonBody) as Map<String,dynamic>);

  Benchmark._({
    @required this.descriptor,
    @required this.values,
    @required this.worst,
  });

  final TimeSeriesDescriptor descriptor;
  final List<TimeSeriesValue> values;
  final double worst;

  bool get archived => descriptor.archived;
  String get task => descriptor.taskName;

  Future<Benchmark> getFullHistory({String base = BenchmarkDashboard.dashboardUrlBase}) async {
    final String url = BenchmarkDashboard.dashboardGetHistoryUrl(descriptor.key, base: base);
    print('loading benchmark history from $url');
    try {
      final http.Response response = await http.get(url);
      return Benchmark.fromJsonString(response.body);
    } finally {
      print('done loading');
    }
  }
}

class BenchmarkDashboard {
  BenchmarkDashboard.fromJsonString(String jsonBody)
      : this.fromJsonMap(const JsonDecoder().convert(jsonBody) as Map<String,dynamic>);

  BenchmarkDashboard.fromJsonMap(Map<String,dynamic> jsonMap) {
    final List<dynamic> benchmarkJsonList = jsonMap['Benchmarks'] as List<dynamic>;
    final List<Benchmark> benchmarks = benchmarkJsonList.map(_benchmarkFromJson).toList();
    final Map<String,List<Benchmark>> byTask = <String,List<Benchmark>>{};
    for (final Benchmark benchmark in benchmarks) {
      List<Benchmark> associatedBenchmarks = byTask[benchmark.task];
      if (associatedBenchmarks == null) {
        byTask[benchmark.task] = associatedBenchmarks = <Benchmark>[];
      }
      associatedBenchmarks.add(benchmark);
    }
    _allEntries = benchmarks;
    _byTask = byTask;
  }

  static const String dashboardUrlBase =
      'https://flutter-dashboard.appspot.com/api/public';
  static const String dashboardGetBenchmarksUrl =
      '$dashboardUrlBase/get-benchmarks?branch=master';
  static String dashboardGetHistoryUrl(String key, {String base = dashboardUrlBase}) =>
      '$base/get-timeseries-history?TimeSeriesKey=$key';

  static Benchmark _benchmarkFromJson(dynamic e) => Benchmark.fromJsonMap(e as Map<String,dynamic>);

  static Future<BenchmarkDashboard> loadFromFile(String filename) async {
    return BenchmarkDashboard.fromJsonString(await File(filename).readAsString());
  }

  static Future<BenchmarkDashboard> loadFromAppspot() async {
    print('loading benchmarks from $dashboardGetBenchmarksUrl');
    try {
      final http.Response response = await http.get(dashboardGetBenchmarksUrl);
      return BenchmarkDashboard.fromJsonString(response.body);
    } finally {
      print('done loading');
    }
  }

  List<Benchmark> _allEntries;
  Map<String,List<Benchmark>> _byTask;

  static bool _benchmarkAlive(Benchmark b) => !b.archived;
  static bool _benchmarkArchived(Benchmark b) => b.archived;

  List<Benchmark> get allEntries => _allEntries;
  Iterable<Benchmark> get liveEntries => _allEntries.where(_benchmarkAlive);
  Iterable<Benchmark> get archivedEntries => _allEntries.where(_benchmarkArchived);

  Map<String,List<Benchmark>> get allTasks => _byTask;
}
