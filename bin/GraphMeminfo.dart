// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_benchmark_utils/GraphCommand.dart';
import 'package:flutter_benchmark_utils/GraphServer.dart';
import 'package:flutter_benchmark_utils/benchmark_data.dart';

class MeminfoGraphCommand extends GraphCommand {
  MeminfoGraphCommand() : super('graphMeminfo', webClientDefault: true);

  @override
  GraphResult validateJson(String filename, String json, Map<String, dynamic> jsonMap, bool isWebClient) {
    MeminfoSeriesSource.fromJsonMap(jsonMap);
    return GraphResult(BenchmarkType.MEMINFO_TRACE, filename, json);
  }
}

void main(List<String> rawArgs) {
  final GraphCommand command = MeminfoGraphCommand();
  command.graphMain(rawArgs);
}
