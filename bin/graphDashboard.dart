// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:args/args.dart';

import 'package:flutter_benchmark_utils/GraphCommand.dart';
import 'package:flutter_benchmark_utils/GraphServer.dart';
import 'package:flutter_benchmark_utils/benchmark_data.dart';

class DashboardGraphCommand extends GraphCommand {
  DashboardGraphCommand() : super('graphDashboard');

  @override
  void addArgOptions(ArgParser args) {
    args.addFlag(
      kDashboardOpt,
      defaultsTo: true,
      help: 'Load the information from the Flutter benchmark dashboard.',
    );
  }

  @override
  bool processResults(ArgResults args, List<GraphResult> results) {
    if (args[kDashboardOpt] as bool) {
      if (isWebClient) {
        results.add(GraphResult.fromWebLazy(
            BenchmarkType.BENCHMARK_DASHBOARD,
            'flutter-dashboard.appspot.com',
            BenchmarkDashboard.dashboardUrl));
      } else {
        usage('Dashboard graphing only supported when using the web client');
        return false;
      }
    }
    return super.processResults(args, results);
  }

  @override
  GraphResult validateJson(String filename, String json, Map<String, dynamic> jsonMap, bool isWebClient) {
    BenchmarkType type = BenchmarkUtils.getBenchmarkType(jsonMap);
    switch (type) {
      case BenchmarkType.BENCHMARK_DASHBOARD:
        type = BenchmarkType.BENCHMARK_DASHBOARD;
        break;
      default:
        throw '$filename not recognized as a dashboard get-benchmarks dump';
    }
    return GraphResult(type, filename, json);
  }
}

void main(List<String> rawArgs) {
  final GraphCommand command = DashboardGraphCommand();
  command.graphMain(rawArgs);
}
