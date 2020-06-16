// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:open_url/open_url.dart';
import 'package:args/args.dart';
import 'package:resource/resource.dart' show Resource;
import 'package:archive/archive.dart';

import 'GraphServer.dart';

const String kLaunchOpt = 'launch';
const String kWebAppOpt = 'web';
const String kWebAppLocalOpt = 'web-local';
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
    verbose = args[kVerboseOpt] as bool;

    List<GraphResult> results = [];
    for (String arg in args.rest) {
      String json = _validateJsonFile(arg);
      if (json == null) {
        return;
      }
      results.add(GraphResult(arg, json));
    }

    List<String> servedUrls = [];
    Future<Process> webBuilder;
    if (args[kWebAppLocalOpt] as bool) {
      if (args[kWebAppOpt] as bool) {
        _usage('Only one of --$kWebAppOpt or --$kWebAppLocalOpt flags allowed.');
        return;
      }
      servedUrls.add(await serveToWebApp(results, true));
      webBuilder = buildWebApp();
    } else if (args[kWebAppOpt] as bool) {
      servedUrls.add(await serveToWebApp(results, false));
    } else {
      if (results.length == 0) {
        servedUrls.add(await launchHtml(null));
      }
      for (GraphResult result in results) {
        servedUrls.add(await launchHtml(result));
      }
    }

    print('');
    if (args[kLaunchOpt] as bool) {
      if (webBuilder != null) {
        webBuilder.then((process) => process.exitCode.then((_) => launchAll(servedUrls)));
      } else {
        launchAll(servedUrls);
      }
    } else {
      print("Type 'l' to launch URL(s) in system default browser.");
    }
    print("Type 'q' to quit.");
    print('');
    stdin.lineMode = false;
    stdin.echoMode = false;
    stdin.listen((List<int> chars) async {
      for (int char in chars) {
        if (char == 'q'.codeUnitAt(0)) {
          if (webBuilder != null) {
            await webBuilder.then((process) => process.kill());
          }
          exit(0);
        } else if (char == 'l'.codeUnitAt(0)) {
          launchAll(servedUrls);
        }
      }
    });
  }

  webOut(String origin, String output) {
    for (String line in output.split('\n')) {
      print('web app [$origin]: $line');
    }
  }

  launchAll(List<String> servedUrls) async {
    for (var url in servedUrls) {
      await openUrl(url);
    }
  }

  Future<String> launchHtml(GraphResult results) async {
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

  Future<Archive> _loadWebAppArchive() async {
    Resource webAppResource = Resource('package:flutter_benchmark_utils/src/webapp.zip');
    return ZipDecoder().decodeBytes(await webAppResource.readAsBytes());
  }

  Future<Process> buildWebApp() {
    List<String> args = [ 'build', 'web' ];
    return Process.start('flutter', args, workingDirectory: webAppPath).then((Process process) {
      if (verbose) {
        process.stdout.transform(utf8.decoder).listen((chunk) => webOut('stdout', chunk));
      }
      process.stderr.transform(utf8.decoder).listen((chunk) => webOut('stderr', chunk));
      process.exitCode.then((value) { if (value != 0) { exit(value); } } );
      return process;
    });
  }

  static final ContentType jsType = ContentType('text', 'javascript');
  static final ContentType ttfType = ContentType('font', 'ttf');

  ContentType typeFor(String uri) {
    if (uri.endsWith('.html')) {
      return ContentType.html;
    } else if (uri.endsWith('.js')) {
      return jsType;
    } else if (uri.endsWith('.ttf')) {
      return ttfType;
    } else {
      return ContentType.binary;
    }
  }

  Future<String> serveToWebApp(List<GraphResult> results, bool local) async {
    Map<String,GraphResult> resultMap = {};
    for (GraphResult result in results) {
      if (resultMap.containsKey(result.filename)) {
        if (resultMap[result.filename].json == result.json) {
          stderr.writeln('Ignoring duplicate results added for ${result.filename}');
        } else {
          stderr.writeln('Conflicting results added for ${result.filename}');
          exit(-1);
        }
      } else {
        resultMap[result.filename] = result;
      }
    }
    HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var handler;
    if (local) {
      handler = (HttpResponse response, String uri) {
        File f = File('$webAppPath/build/web$uri');
        if (!f.existsSync()) {
          return false;
        }
        response.headers.contentType = typeFor(uri);
        response.headers.contentLength = f.lengthSync();
        response.addStream(f.openRead()).then((_) => response.close());
        return true;
      };
    } else {
      Archive webAppArchive = await _loadWebAppArchive();
      handler = (HttpResponse response, String uri) {
        ArchiveFile f = webAppArchive.findFile('webapp$uri');
        if (f == null) {
          return false;
        }
        response.headers.contentType = typeFor(uri);
        response.headers.contentLength = f.size;
        response.add(f.content);
        response.close();
        return true;
      };
    }
    server.listen((HttpRequest request) {
      request.response.headers.set('access-control-allow-origin', '*');
      String uri = request.uri.toString();
      if (uri == '/list') {
        List<String> filenames = [ ...resultMap.keys ];
        String filenameJson = JsonEncoder.withIndent('  ').convert(filenames);
        request.response.headers.contentType = ContentType.json;
        request.response.headers.contentLength = filenameJson.length;
        request.response.write(filenameJson);
        request.response.close();
      } else if (uri.startsWith('/result?')) {
        String key = uri.substring(8);
        if (resultMap.containsKey(key)) {
          request.response.headers.contentType = ContentType.json;
          request.response.headers.contentLength = resultMap[key].json.length;
          request.response.write(resultMap[key].json);
          request.response.close();
        }
      } else {
        if (uri == '/') uri = '/index.html';
        if (!handler(request.response, uri)) {
          request.response.statusCode = HttpStatus.notFound;
          request.response.close();
        }
      }
      if (verbose) {
        print('web app data server served ${request.response.headers.contentLength} bytes: $uri');
      }
    });
    String url = 'http://localhost:${server.port}';
    print('Serving graphing web app on $url');
    return url;
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
    kVerboseOpt,
    abbr: 'v',
    defaultsTo: false,
    help: 'Verbose output.',
  );
