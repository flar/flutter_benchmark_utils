// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:open_url/open_url.dart';
import 'package:args/args.dart';

import 'GraphServer.dart';

const String kLaunchOpt = 'launch';
const String kWebAppOpt = 'web';
const String kWebAppLocalOpt = 'web-local';
const String kCanvasKitOpt = 'canvas-kit';
const String kVerboseOpt = 'verbose';

abstract class GraphCommand {
  GraphCommand(this.commandName);

  final String commandName;
  bool verbose;

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
      String error;
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

  String validateJson(Map<String,dynamic> jsonMap, bool webClient);

  void _usage(String error) {
    if (error != null) {
      exitCode = 1;
      stderr.writeln('');
      stderr.writeln(error);
      stderr.writeln('');
    }
    stderr.writeln('Usage: dart $commandName [options (see below)] [<results_filename>]\n');
    stderr.writeln(_argParser.usage);
  }

  String _validateJsonFile(String filename, bool webClient) {
    File file = File(filename);
    if (!file.existsSync()) {
      _usage('$filename does not exist');
      return null;
    }
    String json = file.readAsStringSync();
    Map<String,dynamic> jsonMap = JsonDecoder().convert(json);
    String error = validateJson(jsonMap, webClient);
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
    verbose = args[kVerboseOpt] as bool;

    List<GraphResult> results = [];
    bool isWebClient = args[kWebAppLocalOpt] || args[kWebAppOpt];
    for (String arg in args.rest) {
      String json = _validateJsonFile(arg, isWebClient);
      if (json == null) {
        return;
      }
      results.add(GraphResult(arg, json));
    }

    List<ServedResults> servedUrls = [];
    Future<Process> webBuilder;
    if (args[kWebAppLocalOpt] as bool) {
      if (args[kWebAppOpt] as bool) {
        _usage('Only one of --$kWebAppOpt or --$kWebAppLocalOpt flags allowed.');
        return;
      }
      servedUrls.add(await serveToWebApp(results, webAppPath, verbose));
      webBuilder = buildWebApp(args[kCanvasKitOpt] as bool);
    } else if (args[kCanvasKitOpt] as bool) {
      _usage('CanvasKit back end currently only supported for --$kWebAppLocalOpt.');
      return;
    } else if (args[kWebAppOpt] as bool) {
      servedUrls.add(await serveToWebApp(results, null, verbose));
    } else {
      if (results.length == 0) {
        servedUrls.add(await launchHtml(null));
      }
      for (GraphResult result in results) {
        servedUrls.add(await launchHtml(result));
      }
    }

    if (webBuilder != null) {
      await webBuilder.then((process) => process.exitCode.then((code) {
        if (code != 0) {
          print('');
          print('Compile failed with exit code $code');
          exit(code);
        }
      }));
    }

    print('');
    printAndLaunchUrls(servedUrls, true, args[kLaunchOpt] as bool);
    print('');
    print("Type 'l' to launch URL(s) in system default browser.");
    print("Type 'q' to quit.");
    print('');
    stdin.echoMode = false;
    stdin.lineMode = false;
    stdin.listen((List<int> chars) async {
      for (int char in chars) {
        if (char == 'q'.codeUnitAt(0)) {
          if (webBuilder != null) {
            await webBuilder.then((process) => process.kill());
          }
          exit(0);
        } else if (char == 'l'.codeUnitAt(0)) {
          printAndLaunchUrls(servedUrls, false, true);
        }
      }
    });
  }

  webOut(String origin, String output) {
    for (String line in output.split('\n')) {
      print('[$origin]: $line');
    }
  }

  printAndLaunchUrls(List<ServedResults> servedUrls, bool show, bool launch) async {
    for (var result in servedUrls) {
      if (show) {
        print('Serving ${result.name} at ${result.url}');
      }
      if (launch) {
        await openUrl(result.url);
      }
    }
  }

  Future<ServedResults> launchHtml(GraphResult results) async {
    GraphServer server = GraphServer(
      graphHtmlName: '/$commandName.html',
      resultsScriptName: '/$commandName-results.js',
      resultsVariableName: '${commandName}_data',
      results: results,
    );
    return await server.initWebServer();
  }

  String _webAppPath;
  String get webAppPath => _webAppPath ??= _findWebAppPath();
  String _findWebAppPath() {
    Directory repo = new File(Platform.script.path).parent.parent;
    Directory webapp_repo = Directory('${repo.path}/packages/graph_app');
    return webapp_repo.path;
  }

  Future<Process> buildWebApp(bool useCanvasKit) {
    List<String> args = [ 'build', 'web' ];
    if (useCanvasKit) {
      args.add('--dart-define=FLUTTER_WEB_USE_SKIA=true');
    }
    if (verbose) {
      print('[web app command]: flutter ${args.join(' ')}');
    }
    return Process.start('flutter', args, workingDirectory: webAppPath).then((Process process) {
      if (verbose) {
        process.stdout.transform(utf8.decoder).listen((chunk) => webOut('web app stdout', chunk));
      }
      process.stderr.transform(utf8.decoder).listen((chunk) => webOut('web app stderr', chunk));
      return process;
    });
  }
}

/// Command-line options for the `graphAB.dart` command.
final ArgParser _argParser = ArgParser()
  ..addFlag(
    kLaunchOpt,
    defaultsTo: false,
    help: 'Automatically launches the graphing URL in the system default browser.',
  )
  ..addFlag(
    kWebAppOpt,
    defaultsTo: false,
    help: 'Use a Dart Web App to graph the results.',
  )
  ..addFlag(
    kWebAppLocalOpt,
    hide: true,
    defaultsTo: false,
    help: 'Runs the web app from the web app package directory for debugging.',
  )
  ..addFlag(
    kCanvasKitOpt,
    hide: true,
    defaultsTo: false,
    help: 'Uses CanvasKit backend for local web.',
  )
  ..addFlag(
    kVerboseOpt,
    abbr: 'v',
    defaultsTo: false,
    help: 'Verbose output.',
  );
