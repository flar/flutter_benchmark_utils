// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:flutter_benchmark_utils/benchmark_data.dart';

Future<void> main(List<String> rawArgs) async {
  BenchmarkDashboard dashboard;
  switch (rawArgs.length) {
    case 0:
      dashboard = await BenchmarkDashboard.loadFromAppspot();
      break;
    case 1:
      dashboard = await BenchmarkDashboard.loadFromFile(rawArgs[0]);
      break;
    default:
      print('Usage: dart analyzeBenchmarks [file downloaded from dashboard.appspot.com/get-benchmarks]');
      print('    if no filename is given, the live contents are downloaded from appspot.com');
      exitCode = 1;
      return;
  }
  print('${dashboard.allEntries.length} benchmarks');
  int alive = 0;
  for (final Benchmark benchmark in dashboard.allEntries) {
    if (!benchmark.descriptor.archived) {
      alive++;
    }
  }
  print('${dashboard.allTasks.length} tasks ($alive measurements still tracked)');
  final Map<String,List<Benchmark>> tasks = dashboard.allTasks;
  for (final String name in tasks.keys) {
    print('  $name:');
    for (final Benchmark b in tasks[name]!.where((Benchmark b) => !b.descriptor.archived)) {
      print('    ${b.descriptor.label}: ${b.values.length} values');
    }
    for (final Benchmark b in tasks[name]!.where((Benchmark b) => b.descriptor.archived)) {
      print('    (archived) ${b.descriptor.label}: ${b.values.length} values');
    }
  }
}
