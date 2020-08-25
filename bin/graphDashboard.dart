// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;

import 'package:flutter_benchmark_utils/GraphCommand.dart';
import 'package:flutter_benchmark_utils/GraphServer.dart';
import 'package:flutter_benchmark_utils/benchmark_data.dart';

const String kDashboardOpt = 'dashboard';

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
            BenchmarkDashboard.dashboardGetBenchmarksUrl));
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

  @override
  Future<bool> handleOther(HttpResponse response, String url) async {
    if (url.startsWith('/get-timeseries-history?TimeSeriesKey=')) {
      final String queryUrl = '${BenchmarkDashboard.dashboardUrlBase}/get-timeseries-history';
      final Map<String, dynamic> request = <String, dynamic>{
        'TimeSeriesKey': url.substring(38),
      };
      print('loading lazy resource from $queryUrl');
      try {
        final http.Response queryResponse = await http.post(queryUrl, body: json.encode(request));
        final List<int> encoded = response.encoding.encoder.convert(queryResponse.body);
        response.headers.contentType = ContentType.json;
        response.headers.contentLength = encoded.length;
        response.add(encoded);
        response.close();
        print('done loading');
        return true;
      } catch (e) {
        print('caught error while loading: $e');
      }
    }
    return false;
  }
}

void main(List<String> rawArgs) {
  final GraphCommand command = DashboardGraphCommand();
  command.graphMain(rawArgs);
}
