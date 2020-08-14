// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'timeline_summary.dart';

enum BenchmarkType {
  TIMELINE_SUMMARY,
  TIMELINE_TRACE,
  BENCHMARK_AB_COMPARISON,
}

class BenchmarkUtils {
  static void validateJsonEntryIsNumber(Map<String,dynamic> map, String key) {
    final dynamic val = map[key];
    if (val is! num) {
      throw '$key is not a number: $val';
    }
  }

  static void validateJsonEntryIsNumberList(Map<String,dynamic> map, String key, [String outerKey = '']) {
    final dynamic val = map[key];
    if (val is List<num> || val is List<int> || val is List<double>) {
      return;
    }
    if (val is List) {
      for (final dynamic subVal in val) {
        if (subVal is! num) {
          throw 'not all values in $outerKey[$key] are num: $subVal';
        }
      }
    } else {
      throw '$outerKey[$key] is not a list: $val';
    }
  }

  static void validateJsonEntryMapsStringToNumberList(Map<String,dynamic> jsonMap, String key) {
    final dynamic val = jsonMap[key];
    if (val == null) {
      throw 'missing $key';
    }
    if (val is Map<String,List<num>> ||
        val is Map<String,List<int>> ||
        val is Map<String,List<double>>) {
      return;
    }
    if (val is Map<String,List<dynamic>> || val is Map<String,dynamic>) {
      final Map<String,dynamic> map = val as Map<String,dynamic>;
      for (final String subKey in map.keys) {
        validateJsonEntryIsNumberList(map, subKey);
      }
    }
    throw 'unrecognized $key: $val is not Map<String,List<num>>';
  }

  static void validateJsonEntryMatches(Map<String,dynamic> jsonMap, String key, String val) {
    if (jsonMap[key] != val) {
      throw 'unrecognized $key: ${jsonMap[key]} != $val';
    }
  }

  static bool _isABJson(Map<String,dynamic> jsonMap) {
    try {
      validateJsonEntryMatches(jsonMap, 'benchmark_type', 'A/B summaries');
      validateJsonEntryMatches(jsonMap, 'version', '1.0');
      validateJsonEntryMapsStringToNumberList(jsonMap, 'default_results');
      validateJsonEntryMapsStringToNumberList(jsonMap, 'local_engine_results');
      return true;
    } catch (e) {
      return false;
    }
  }

  static BenchmarkType getBenchmarkType(Map<String,dynamic> jsonMap) {
    if (TimelineResults.isSummaryMap(jsonMap)) {
      return BenchmarkType.TIMELINE_SUMMARY;
    }
    if (TimelineResults.isTraceMap(jsonMap)) {
      return BenchmarkType.TIMELINE_TRACE;
    }
    if (_isABJson(jsonMap)) {
      return BenchmarkType.BENCHMARK_AB_COMPARISON;
    }
    return null;
  }
}
