// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_benchmark_utils/GraphCommand.dart';

class ABGraphCommand extends GraphCommand {
  ABGraphCommand() : super('graphAB');

  @override
  String validateJson(Map<String, dynamic> jsonMap, bool isWebClient) {
    return validateJsonEntryMatches(jsonMap, 'benchmark_type', 'A/B summaries')
        ?? validateJsonEntryMatches(jsonMap, 'version', '1.0')
        ?? validateJsonEntryMapsStringToNumberList(jsonMap, 'default_results')
        ?? validateJsonEntryMapsStringToNumberList(jsonMap, 'local_engine_results');
  }
}

void main(List<String> rawArgs) {
  GraphCommand command = ABGraphCommand();
  command.graphMain(rawArgs);
}
