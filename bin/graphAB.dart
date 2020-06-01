import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:isolate';

import 'package:resource/resource.dart' show Resource;
import 'package:open_url/open_url.dart';
import 'package:args/args.dart';

const int kWebPort = 4040;
const String kWebUrl = 'http://localhost:$kWebPort';

const String kLaunchOpt = 'launch';
const String kGraphHtmlName = '/graphAB.html';
const String kResultsScriptName = '/ABresults.js';
const String kABPackagePrefix = 'package:flutter_benchmark_utils/src/graphAB';

final ContentType kContentTypeJs = ContentType('application', 'javascript');

void _usage(String error) {
  if (error != null) {
    exitCode = 1;
    stderr.writeln(error);
  }
  stderr.writeln('Usage: dart graphAB [options (see below)] [<ABresultsfilename>]\n');
  stderr.writeln(_argParser.usage);
}

String _validateABJson(String filename) {
  File file = File(filename);
  if (!file.existsSync()) {
    _usage('$filename does not exist');
    return null;
  }
  String json = file.readAsStringSync();
  Map<String,dynamic> jsonMap = JsonDecoder().convert(json);
  if (jsonMap['benchmark_type'] == 'A/B summaries' &&
      jsonMap['version'] == '1.0' &&
      jsonMap['default_results'] is Map<String,dynamic> &&
      jsonMap['local_engine_results'] is Map<String, dynamic>
  ) {
    return json;
  }
  _usage('$filename is not a valid AB results json file');
  return null;
}

Future main(List<String> rawArgs) async {
  ArgResults args;
  try {
    args = _argParser.parse(rawArgs);
  } on FormatException catch (error) {
    _usage('${error.message}\n');
    return;
  }

  if (args.rest.length > 1) {
    _usage('Only one ABresult JSON file supported.');
    return;
  }

  List<Result> results = [];
  for (String arg in args.rest) {
    String json = _validateABJson(arg);
    if (json == null) {
      return;
    }
    results.add(Result(arg, json));
  }

  await initWebServer(results);
  if (args[kLaunchOpt] as bool) {
    await openUrl(kWebUrl);
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

class Result {
  Result(this.filename, this.json);

  final String filename;
  final String json;
}

Future<SendPort> initWebServer(List<Result> results) async {
  Completer completer = new Completer<SendPort>();
  ReceivePort isolateToMainStream = ReceivePort();

  isolateToMainStream.listen((data) {
    if (data is SendPort) {
      SendPort mainToIsolateStream = data;
      completer.complete(mainToIsolateStream);
      mainToIsolateStream.send(results);
    } else {
      print('[isolateToMainStream] $data');
      exit(-1);
    }
  });

  await Isolate.spawn(runWebServer, isolateToMainStream.sendPort);
  return completer.future;
}

abstract class _RequestHandler {
  Future handle(HttpResponse response, String uri);
}

class _DefaultRequestHandler extends _FileRequestHandler {
  _DefaultRequestHandler(this.defaultFile);

  final String defaultFile;

  Future handle(HttpResponse response, String uri) {
    return super.handle(response, defaultFile);
  }
}

class _FileRequestHandler extends _RequestHandler {
  Future handle(HttpResponse response, String uri) async {
    Resource fileResource = Resource('$kABPackagePrefix$uri');
    response.headers.contentType = ContentType.html;
    response.write(await fileResource.readAsString());
    await response.close();
  }
}

class _StringRequestHandler extends _RequestHandler {
  _StringRequestHandler(this.contentType, this.content);

  final ContentType contentType;
  final String content;

  Future handle(HttpResponse response, String uri) async {
    response.headers.contentType = contentType;
    response.write(content);
    await response.close();
  }
}

class _ABResultsRequestHandler extends _StringRequestHandler {
  _ABResultsRequestHandler(String json) : super(kContentTypeJs, 'AB_data = $json;');
}

void runWebServer(SendPort isolateToMainStream) async {
  ReceivePort mainToIsolateStream = ReceivePort();
  isolateToMainStream.send(mainToIsolateStream.sendPort);

  var server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    kWebPort,
  );

  Map<String,_RequestHandler> responseMap = {
    '/': _DefaultRequestHandler(kGraphHtmlName),
    kGraphHtmlName: _FileRequestHandler(),
  };

  mainToIsolateStream.listen((data) {
    if (data is List<Result>) {
      List<Result> results = data;
      if (results.length == 0) {
        responseMap[kResultsScriptName] = _ABResultsRequestHandler(null);
        print('AB results graphing page at $kWebUrl');
      } else {
        responseMap[kResultsScriptName] = _ABResultsRequestHandler(results[0].json);
        print('Graphing results from ${results[0].filename} on $kWebUrl');
      }
    } else {
      print('[mainToIsolateStream] $data');
      exit(-1);
    }
  });

  await for (HttpRequest request in server) {
    _RequestHandler handler = responseMap[request.uri.toString()];
    if (handler != null) {
      await handler.handle(request.response, request.uri.toString());
    } else {
      request.response.write('request uri: ${request.uri}\n'
          'request requested uri: ${request.requestedUri}');
      await request.response.close();
    }
  }
}

/// Command-line options for the `graphAB.dart` command.
final ArgParser _argParser = ArgParser()
  ..addFlag(
    kLaunchOpt,
    defaultsTo: false,
    help: 'Automatically launches the graphing URL in the system default browser.',
  );
