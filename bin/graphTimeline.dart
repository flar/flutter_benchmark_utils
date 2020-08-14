// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_benchmark_utils/GraphCommand.dart';
import 'package:flutter_benchmark_utils/benchmark_data.dart';

class TimelineGraphCommand extends GraphCommand {
  TimelineGraphCommand() : super('graphTimeline');

  @override
  String validateJson(Map<String, dynamic> jsonMap, bool isWebClient) {
    switch (BenchmarkUtils.getBenchmarkType(jsonMap)) {
      case BenchmarkType.TIMELINE_SUMMARY:
        return null;
      case BenchmarkType.TIMELINE_TRACE:
        return isWebClient ? null : TimelineResults(jsonMap).jsonSummary;
      default:
        throw 'Not recognized as a timeline summary or event trace';
    }
  }
}

void main(List<String> rawArgs) {
  final GraphCommand command = TimelineGraphCommand();
  command.graphMain(rawArgs);
}
