// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_benchmark_utils/GraphCommand.dart';
import 'package:flutter_benchmark_utils/benchmark_data.dart';

class ABGraphCommand extends GraphCommand {
  ABGraphCommand() : super('graphAB');

  @override
  String validateJson(Map<String, dynamic> jsonMap, bool isWebClient) {
    switch (BenchmarkUtils.getBenchmarkType(jsonMap)) {
      case BenchmarkType.BENCHMARK_AB_COMPARISON:
        return null;
      default:
        throw 'Not recognized as an A/B comparison summary';
    }
  }
}

void main(List<String> rawArgs) {
  GraphCommand command = ABGraphCommand();
  command.graphMain(rawArgs);
}
