// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_benchmark_utils/GraphCommand.dart';
import 'package:flutter_benchmark_utils/GraphServer.dart';
import 'package:flutter_benchmark_utils/benchmark_data.dart';

class TimelineGraphCommand extends GraphCommand {
  TimelineGraphCommand() : super('graphTimeline', webClientDefault: true);

  @override
  GraphResult validateJson(String filename, String json, Map<String, dynamic> jsonMap, bool isWebClient) {
    BenchmarkType type = BenchmarkUtils.getBenchmarkType(jsonMap);
    switch (type) {
      case BenchmarkType.TIMELINE_SUMMARY:
        break;
      case BenchmarkType.TIMELINE_TRACE:
        if (!isWebClient) {
          type = BenchmarkType.TIMELINE_SUMMARY;
          json = TimelineResults(jsonMap).jsonSummary;
        }
        break;
      default:
        throw 'Not recognized as a timeline summary or event trace';
    }
    return GraphResult(type, filename, json);
  }
}

void main(List<String> rawArgs) {
  final GraphCommand command = TimelineGraphCommand();
  command.graphMain(rawArgs);
}
