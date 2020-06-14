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
const String kPortOpt = 'port';
const String kWebAppOpt = 'web';
const String kWebDebugAppOpt = 'web-debug';
const String kVerboseOpt = 'verbose';

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
      GraphServer.nextWebPort = int.parse(args[kPortOpt]);
    } on FormatException catch (error) {
      _usage('${error.message}\n');
      return;
    }

    bool useWebApp = (args[kWebAppOpt] as bool) || (args[kWebDebugAppOpt] as bool);

    List<GraphServer> servers = [];
    if (args.rest.length == 0) {
      servers.add(await launch(null, args[kLaunchOpt] as bool));
    } else {
      for (String arg in args.rest) {
        String json = _validateJsonFile(arg);
        if (json == null) {
          return;
        }
        if (useWebApp) {
          await serveToWebApp(GraphResult(arg, json));
        } else {
          servers.add(await launch(GraphResult(arg, json), args[kLaunchOpt] as bool));
        }
      }
    }

    Future<Process> webApp = useWebApp
        ? launchWebApp(verbose: args[kVerboseOpt] as bool, debug: args[kWebDebugAppOpt] as bool)
        : null;

    print('');
    if (!useWebApp) {
      print("Type 'l' to launch URL(s) in system default browser.");
    }
    print("Type 'q' to quit.");
    print('');
    stdin.lineMode = false;
    stdin.echoMode = false;
    stdin.forEach((List<int> chars) {
      for (int char in chars) {
        if (char == 'q'.codeUnitAt(0)) {
          if (webApp != null) {
            webApp.then((process) {
              process.stdin.writeln('q');
            });
            // Return instead of exit to give the web app a chance to shut down gracefully.
            return;
          } else {
            // Exit instead of return because we don't have a good way to notify the servers.
            exit(0);
          }
        } else if (char == 'l'.codeUnitAt(0)) {
          launchAll(servers);
        }
      }
    });
  }

  webOut(String origin, String output) {
    for (String line in output.split('\n')) {
      print('web app [$origin]: $line');
    }
  }

  launchAll(List<GraphServer> servers) async {
    for (var server in servers) {
      await openUrl(server.serverUrl);
    }
  }

  Future<GraphServer> launch(GraphResult results, bool launchBrowser) async {
    GraphServer server = GraphServer(
      graphHtmlName: '/$commandName.html',
      resultsScriptName: '/$commandName-results.js',
      resultsVariableName: '${commandName}_data',
      results: results,
    );
    await server.initWebServer();
    if (launchBrowser) {
      await openUrl(server.serverUrl);
    }
    return server;
  }

  Future<Process> launchWebApp({bool verbose, bool debug}) {
    String repoPath = new File(Platform.script.path).parent.parent.path;
    List<String> args = [ 'run', debug ? '--debug' : '--release', '-d', 'chrome' ];
    return Process.start('flutter', args, workingDirectory: repoPath).then((Process process) {
      if (verbose) {
        process.stdout.transform(utf8.decoder).listen((chunk) => webOut('stdout', chunk));
      }
      process.stderr.transform(utf8.decoder).listen((chunk) => webOut('stderr', chunk));
      process.exitCode.then((value) => exit(value));
      return process;
    });
  }

  Future<HttpServer> _server;
  Map<String,GraphResult> _results = <String,GraphResult>{};

  Future<void> serveToWebApp(GraphResult result) async {
    if (_results.isEmpty) {
      _server = HttpServer.bind(InternetAddress.loopbackIPv4, 4090);
      _server.then((HttpServer server) async {
        server.listen((HttpRequest request) {
          String uri = request.uri.toString();
          if (uri == '/list') {
            List<String> filenames = [ ..._results.keys ];
            request.response.headers.contentType = ContentType.json;
            request.response.headers.set('access-control-allow-origin', '*');
            request.response.write(JsonEncoder.withIndent('  ').convert(filenames));
            request.response.close();
          } else if (uri.startsWith('/result?')) {
            String key = uri.substring(8);
            request.response.headers.contentType = ContentType.json;
            request.response.headers.set('access-control-allow-origin', '*');
            request.response.write(_results[key].json);
            request.response.close();
          }
        });
      });
    }
    if (_results.containsKey(result.filename)) {
      if (_results[result.filename].json == result.json) {
        stderr.writeln('Ignoring duplicate results added for ${result.filename}');
      } else {
        stderr.writeln('Conflicting results added for ${result.filename}');
        exit(-1);
      }
    } else {
      _results[result.filename] = result;
    }
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
    kWebDebugAppOpt,
    defaultsTo: false,
    help: 'Use a (debug) Dart Web App to graph the results.',
  )
  ..addFlag(
    kVerboseOpt,
    abbr: 'v',
    defaultsTo: false,
    help: 'Verbose output.',
  )
  ..addOption(
    kPortOpt,
    defaultsTo: '4040',
    help: 'Default port for (first) graph page URL.',
  );
