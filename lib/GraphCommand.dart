// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:open_url/open_url.dart';
//import 'package:resource/resource.dart' show Resource;

import 'GraphServer.dart';

const String kLaunchOpt = 'launch';
const String kWebAppOpt = 'web';
const String kWebAppLocalOpt = 'web-local';
const String kCanvasKitOpt = 'canvas-kit';
const String kVerboseOpt = 'verbose';

abstract class GraphCommand {
  GraphCommand(this.commandName, { this.webClientDefault = false });

  final String commandName;
  final bool webClientDefault;
  late bool verbose;
  late bool isWebClient;

  late final ArgParser _argParser = makeArgOptions();

  ArgParser makeArgOptions() {
    /// Common Command-line options for the `graphAB.dart` and 'graphTimeline.dart' commands.
    return ArgParser()
      ..addFlag(
        kLaunchOpt,
        defaultsTo: false,
        help: 'Automatically launches the graphing URL in the system default browser.',
      )
      ..addFlag(
        kWebAppOpt,
        defaultsTo: webClientDefault,
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
        defaultsTo: true,
        help: 'Uses CanvasKit backend for local web.',
      )
      ..addFlag(
        kVerboseOpt,
        abbr: 'v',
        defaultsTo: false,
        help: 'Verbose output.',
      );
  }

  bool processResults(ArgResults args, List<GraphResult> results) {
    for (final String arg in args.rest) {
      final List<GraphResult>? fileResults = _validateJsonFile(arg, isWebClient);
      if (fileResults == null) {
        return false;
      }
      results.addAll(fileResults);
    }
    return true;
  }

  String? validateJsonEntryIsNumberList(Map<String,dynamic> map, String key, [String outerKey = '']) {
    final dynamic val = map[key];
    if (val is List<num> || val is List<int> || val is List<double>) {
      return null;
    }
    if (val is List) {
      for (final dynamic subVal in val) {
        if (subVal is! num) {
          return 'not all values in $outerKey[$key] are num: $subVal';
        }
      }
      return null;
    }
    return '$outerKey[$key] is not a list: $val';
  }

  String? validateJsonEntryMapsStringToNumberList(Map<String,dynamic> jsonMap, String key) {
    final dynamic val = jsonMap[key];
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
      final Map<String,dynamic> map = val as Map<String,dynamic>;
      String? error;
      for (final String subKey in map.keys) {
        error ??= validateJsonEntryIsNumberList(map, subKey);
      }
      return error;
    }
    return 'unrecognized $key: $val is not Map<String,List<num>>';
  }

  String? validateJsonEntryMatches(Map<String,dynamic> jsonMap, String key, String val) {
    if (jsonMap[key] != val) {
      return 'unrecognized $key: ${jsonMap[key]} != $val';
    }
    return null;
  }

  GraphResult validateJson(String filename, String json, Map<String,dynamic> jsonMap, bool webClient);

  void usage(String? error) {
    if (error != null) {
      exitCode = 1;
      stderr.writeln('');
      stderr.writeln(error);
      stderr.writeln('');
    }
    stderr.writeln('Usage: dart $commandName [options (see below)] [<results_filename>]\n');
    stderr.writeln(_argParser.usage);
  }

  List<GraphResult>? _validateJsonFile(String filename, bool webClient) {
    final File file = File(filename);
    if (!file.existsSync()) {
      usage('$filename does not exist');
      return null;
    }
    final Map<String,String> fileContents = <String,String>{};
    if (filename.endsWith('.zip')) {
      for (final ArchiveFile file in ZipDecoder().decodeBytes(file.readAsBytesSync()).files) {
        final String name = '$filename:${file.name}';
        if (file.name.endsWith('.json')) {
          if (fileContents.containsKey(name)) {
            stderr.writeln('multiple conflicting entries in zip file for $name');
          } else {
            fileContents[name] = String.fromCharCodes(file.content as Iterable<int>);
          }
        } else {
          stderr.writeln('ignoring non-json file in zip: $name');
        }
      }
      if (fileContents.isEmpty) {
        usage('zip file $filename contains no json files');
        return null;
      }
    } else {
      fileContents[filename] = file.readAsStringSync();
    }
    final List<GraphResult> results = <GraphResult>[];
    for (final MapEntry<String,String> entry in fileContents.entries) {
      final Map<String,dynamic> jsonMap = const JsonDecoder().convert(entry.value) as Map<String,dynamic>;
      try {
        final GraphResult result = validateJson(entry.key, entry.value, jsonMap, webClient);
        results.add(result);
      } catch (error) {
        usage('$filename is not a valid $commandName results json file: $error');
        return null;
      }
    }
    return results;
  }

  Archive? _webAppArchive;

  Future<Archive> _loadWebAppArchive() async {
    if (_webAppArchive == null) {
      Uri? webappUri = await Isolate.resolvePackageUri(Uri.parse('package:flutter_benchmark_utils/src/webapp.zip'));
      webappUri ??= Uri.base.resolve('src/webapp.zip');
      final File webappFile = File.fromUri(webappUri);
      _webAppArchive = ZipDecoder().decodeBytes(await webappFile.readAsBytes());
    }
    return _webAppArchive!;
  }

  Future<bool> handleOther(HttpResponse response, String url) async {
    return false;
  }

  String _stripVersioning(String url) {
    final int index = url.indexOf('?');
    return (index >= 0) ? url.substring(0, index) : url;
  }

  Future<bool> handleWebLocal(HttpResponse response, String url) async {
    final String fileUrl = _stripVersioning(url);
    final File f = File('$webAppPath/build/web$fileUrl');
    if (!f.existsSync()) {
      return handleOther(response, url);
    }
    response.headers.contentType = typeFor(fileUrl);
    response.headers.contentLength = f.lengthSync();
    response.addStream(f.openRead()).then<void>((void _) => response.close());
    return true;
  }

  Future<bool> handleWebApp(HttpResponse response, String url) async {
    final String fileUrl = _stripVersioning(url);
    final Archive webAppArchive = await _loadWebAppArchive();
    final ArchiveFile? f = webAppArchive.findFile('webapp$fileUrl');
    if (f == null) {
      return handleOther(response, url);
    }
    response.headers.contentType = typeFor(fileUrl);
    response.headers.contentLength = f.size;
    response.add(f.content as List<int>);
    response.close();
    return true;
  }

  Future<void> graphMain(List<String> rawArgs) async {
    ArgResults args;
    try {
      args = _argParser.parse(rawArgs);
    } on FormatException catch (error) {
      usage('${error.message}\n');
      return;
    }
    verbose = args[kVerboseOpt] as bool;

    final List<GraphResult> results = <GraphResult>[];
    isWebClient = args[kWebAppLocalOpt] as bool || args[kWebAppOpt] as bool;
    if (!processResults(args, results)) {
      return;
    }

    final List<ServedResults> servedUrls = <ServedResults>[];
    Future<Process>? webBuilder;
    if (args[kWebAppLocalOpt] as bool) {
      if (args[kWebAppOpt] as bool && !webClientDefault) {
        usage('Only one of --$kWebAppOpt or --$kWebAppLocalOpt flags allowed.');
        return;
      }
      servedUrls.add(await serveToWebApp(results: results, handler: handleWebLocal, verbose: verbose));
      webBuilder = buildWebApp(args[kCanvasKitOpt] as bool);
    } else if (!(args[kCanvasKitOpt] as bool)) {
      usage('CanvasKit back end currently only supported for --$kWebAppLocalOpt.');
      return;
    } else if (args[kWebAppOpt] as bool) {
      servedUrls.add(await serveToWebApp(results: results, handler: handleWebApp, verbose: verbose));
    } else {
      if (results.isEmpty) {
        servedUrls.add(await launchHtml(null));
      }
      for (final GraphResult result in results) {
        servedUrls.add(await launchHtml(result));
      }
    }

    if (webBuilder != null) {
      await webBuilder.then((Process process) => process.exitCode.then((int code) {
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
      for (final int char in chars) {
        if (char == 'q'.codeUnitAt(0)) {
          if (webBuilder != null) {
            await webBuilder.then((Process process) => process.kill());
          }
          exit(0);
        } else if (char == 'l'.codeUnitAt(0)) {
          printAndLaunchUrls(servedUrls, false, true);
        }
      }
    });
  }

  void webOut(String origin, String output) {
    for (final String line in output.split('\n')) {
      print('[$origin]: $line');
    }
  }

  Future<void> printAndLaunchUrls(List<ServedResults> servedUrls, bool show, bool launch) async {
    for (final ServedResults result in servedUrls) {
      if (show) {
        print('Serving ${result.name} at ${result.url}');
      }
      if (launch) {
        await openUrl(result.url);
      }
    }
  }

  Future<ServedResults> launchHtml(GraphResult? results) async {
    final GraphServer server = GraphServer(
      graphHtmlName: '/$commandName.html',
      resultsScriptName: '/$commandName-results.js',
      resultsVariableName: '${commandName}_data',
      results: results,
    );
    return await server.initWebServer();
  }

  String? _webAppPath;
  String get webAppPath => _webAppPath ??= _findWebAppPath();
  String _findWebAppPath() {
    final Directory repo = File(Platform.script.path).parent.parent;
    final Directory webappRepo = Directory('${repo.path}/packages/graph_app');
    return webappRepo.path;
  }

  Future<Process> buildWebApp(bool useCanvasKit) {
    final List<String> args = <String>[ 'build', 'web' ];
    if (useCanvasKit) {
      args.add('--dart-define=FLUTTER_WEB_USE_SKIA=true');
    }
    if (verbose) {
      print('[web app command]: flutter ${args.join(' ')}');
    }
    return Process.start('flutter', args, workingDirectory: webAppPath).then((Process process) {
      if (verbose) {
        process.stdout.transform(utf8.decoder).listen((String chunk) => webOut('web app stdout', chunk));
      }
      process.stderr.transform(utf8.decoder).listen((String chunk) => webOut('web app stderr', chunk));
      return process;
    });
  }
}
