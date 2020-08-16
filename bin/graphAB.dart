// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_benchmark_utils/GraphCommand.dart';
import 'package:flutter_benchmark_utils/GraphServer.dart';
import 'package:flutter_benchmark_utils/benchmark_data.dart';

class ABGraphCommand extends GraphCommand {
  ABGraphCommand() : super('graphAB');

  @override
  GraphResult validateJson(String filename, String json, Map<String, dynamic> jsonMap, bool isWebClient) {
    final BenchmarkType type = BenchmarkUtils.getBenchmarkType(jsonMap);
    switch (type) {
      case BenchmarkType.BENCHMARK_AB_COMPARISON:
        return GraphResult(type, filename, json);
      default:
        throw 'Not recognized as an A/B comparison summary';
    }
  }
}

void main(List<String> rawArgs) {
  final GraphCommand command = ABGraphCommand();
  command.graphMain(rawArgs);
}
