// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_benchmark_utils/GraphCommand.dart';

class TimelineGraphCommand extends GraphCommand {
  TimelineGraphCommand() : super('graphTimeline');

  @override
  String validateJson(Map<String, dynamic> jsonMap) {
    return validateJsonEntryIsNumberList(jsonMap, 'frame_build_times')
        ?? validateJsonEntryIsNumberList(jsonMap, 'frame_rasterizer_times');
  }
}

void main(List<String> rawArgs) {
  GraphCommand command = TimelineGraphCommand();
  command.graphMain(rawArgs);
}
