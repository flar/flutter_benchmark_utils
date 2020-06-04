// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:open_url/open_url.dart';
import 'package:args/args.dart';

import 'GraphServer.dart';

const String kLaunchOpt = 'launch';

abstract class GraphCommand {
  GraphCommand(this.commandName);

  final String commandName;

  String validateJsonEntryIsNumberList(Map<String,dynamic> map, String key, [String outerKey = '']) {
    dynamic val = map[key];
    if (val is List<num> || val is List<int> || val is List<double>) {
      return null;
    }
    if (val is List) {
      for (var subVal in val) {
        if (subVal is! num) {
          return 'not all values in $outerKey[$key] are num: $subVal';
        }
      }
      return null;
    }
    return '$outerKey[$key] is not a list: $val';
  }

  String validateJsonEntryMapsStringToNumberList(Map<String,dynamic> jsonMap, String key) {
    dynamic val = jsonMap[key];
    if (val == null) {
      return 'missing $key';
    }
    if (val is Map<String,List<num>>) {
      return null;
    }
    if (val is Map<String,List<int>>) {
      return null;
    }
    if (val is Map<String,List<double>>) {
      return null;
    }
    if (val is Map<String,List<dynamic>> || val is Map<String,dynamic>) {
      Map<String,dynamic> map = val;
      String error = null;
      for (var subKey in map.keys) {
        error ??= validateJsonEntryIsNumberList(map, subKey);
      }
      return error;
    }
    return 'unrecognized $key: $val is not Map<String,List<num>>';
  }

  String validateJsonEntryMatches(Map<String,dynamic> jsonMap, String key, String val) {
    if (jsonMap[key] != val) {
      return 'unrecognized $key: ${jsonMap[key]} != $val';
    }
    return null;
  }

  String validateJson(Map<String,dynamic> jsonMap);

  void _usage(String error) {
    if (error != null) {
      exitCode = 1;
      stderr.writeln(error);
    }
    stderr.writeln('Usage: dart $commandName [options (see below)] [<resultsfilename>]\n');
    stderr.writeln(_argParser.usage);
  }

  String _validateJsonFile(String filename) {
    File file = File(filename);
    if (!file.existsSync()) {
      _usage('$filename does not exist');
      return null;
    }
    String json = file.readAsStringSync();
    Map<String,dynamic> jsonMap = JsonDecoder().convert(json);
    String error = validateJson(jsonMap);
    if (error == null) {
      return json;
    }
    _usage('$filename is not a valid $commandName results json file: $error');
    return null;
  }

  Future graphMain(List<String> rawArgs) async {
    ArgResults args;
    try {
      args = _argParser.parse(rawArgs);
    } on FormatException catch (error) {
      _usage('${error.message}\n');
      return;
    }

    if (args.rest.length > 1) {
      _usage('Only one result JSON file supported.');
      return;
    }

    List<GraphResult> results = [];
    for (String arg in args.rest) {
      String json = _validateJsonFile(arg);
      if (json == null) {
        return;
      }
      results.add(GraphResult(arg, json));
    }

    GraphServer server = GraphServer(
      graphHtmlName: '/$commandName.html',
      resultsScriptName: '/$commandName-results.js',
      resultsVariableName: '${commandName}_data',
      results: results,
    );
    await server.initWebServer();
    if (args[kLaunchOpt] as bool) {
      await openUrl(server.serverUrl);
    }

    stdin.lineMode = false;
    stdin.echoMode = false;
    int char;
    while ((char = stdin.readByteSync()) != -1) {
      if (char == 'q'.codeUnitAt(0)) {
        break;
      }
    }
    exit(0);
  }
}

/// Command-line options for the `graphAB.dart` command.
final ArgParser _argParser = ArgParser()
  ..addFlag(
    kLaunchOpt,
    defaultsTo: false,
    help: 'Automatically launches the graphing URL in the system default browser.',
  );
