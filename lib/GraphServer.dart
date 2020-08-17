// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_benchmark_utils/benchmark_data.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:resource/resource.dart' show Resource;

const String kPackagePrefix = 'package:flutter_benchmark_utils/src/';
const List<String> kStandardScripts = <String>[
  '/crc-png.js',
  '/base64-data-converter.js',
  '/png-utils.js',
  '/html-utils.js',
];

final ContentType kContentTypeJs = ContentType('application', 'javascript');
final ContentType kContentTypeTtf = ContentType('font', 'ttf');

ContentType typeFor(String uri) {
  if (uri.endsWith('.html')) {
    return ContentType.html;
  } else if (uri.endsWith('.js')) {
    return kContentTypeJs;
  } else if (uri.endsWith('.ttf')) {
    return kContentTypeTtf;
  } else {
    return ContentType.binary;
  }
}

class ServedResults {
  ServedResults(this.name, this.url);

  final String name;
  final String url;
}

class GraphResult {
  GraphResult(this.type, this.filename, this._json) : _lazySource = null;
  GraphResult.fromWebLazy(this.type, this.filename, this._lazySource);

  Future<String> _lazyLoad() async {
    print('loading lazy resource from $_lazySource');
    try {
      final http.Response response = await http.get(_lazySource);
      print('done loading');
      return response.body;
    } catch (e) {
      print('caught error while loading: $e');
    }
    return null;
  }

  final BenchmarkType type;
  final String filename;
  final String _lazySource;
  String _json;

  String get webKey => '$type:$filename';
  Future<String> get json async => _json ?? await _lazyLoad();

  bool sameSource(GraphResult other) => type == other.type &&
      _json == other._json &&
      _lazySource == other._lazySource;
}

abstract class _RequestHandler {
  Future<void> handle(HttpResponse response, String uri);
}

class _IgnoreRequestHandler extends _RequestHandler {
  @override
  Future<void> handle(HttpResponse response, String uri) async {
    response.statusCode = HttpStatus.notFound;
    await response.close();
  }
}

class _DefaultRequestHandler extends _FileRequestHandler {
  _DefaultRequestHandler(String packagePrefix, this.defaultFile) : super(packagePrefix);

  final String defaultFile;

  @override
  Future<void> handle(HttpResponse response, String uri) {
    return super.handle(response, defaultFile);
  }
}

class _FileRequestHandler extends _RequestHandler {
  _FileRequestHandler(this.packagePrefix);

  final String packagePrefix;

  ContentType _typeFor(String uri) {
    if (uri.endsWith('.html')) {
      return ContentType.html;
    }
    if (uri.endsWith('.js')) {
      return kContentTypeJs;
    }
    return ContentType.binary;
  }

  @override
  Future<void> handle(HttpResponse response, String uri) async {
    final Resource fileResource = Resource('$packagePrefix$uri');
    response.headers.contentType = _typeFor(uri);
    response.write(await fileResource.readAsString());
    await response.close();
  }
}

class _StringRequestHandler extends _RequestHandler {
  _StringRequestHandler(this.contentType, this.content);

  final ContentType contentType;
  final String content;

  @override
  Future<void> handle(HttpResponse response, String uri) async {
    response.headers.contentType = contentType;
    response.write(content);
    await response.close();
  }
}

class _ResultsRequestHandler extends _StringRequestHandler {
  _ResultsRequestHandler(String variableName, [ GraphResult results ])
      : super(kContentTypeJs,
              'results_filename = "${results?.filename}";\n'
              '$variableName = ${results?.json};');
}

class GraphServer {
  GraphServer(
      {
        @required this.graphHtmlName,
        @required this.resultsScriptName,
        @required this.resultsVariableName,
        @required this.results,
      })
      : assert(graphHtmlName != null),
        assert(resultsScriptName != null),
        assert(resultsVariableName != null),
        assert(results != null)
  {
    _responseMap = <String, _RequestHandler> {
      '/': _DefaultRequestHandler(kPackagePrefix, graphHtmlName),
      '/favicon.ico': _IgnoreRequestHandler(),
      graphHtmlName: _FileRequestHandler(kPackagePrefix),
      resultsScriptName: _ResultsRequestHandler(resultsVariableName, results),
      for (String script in kStandardScripts)
        script: _FileRequestHandler(kPackagePrefix),
    };
  }

  final String graphHtmlName;
  final String resultsScriptName;
  final String resultsVariableName;
  final GraphResult results;

  Map<String,_RequestHandler> _responseMap;
  Map<String, _RequestHandler> get responseMap => _responseMap;

  Future<ServedResults> initWebServer() async {
    final HttpServer webServer = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );

    webServer.listen((HttpRequest request) async {
      final _RequestHandler handler = responseMap[request.uri.toString()];
      if (handler != null) {
        await handler.handle(request.response, request.uri.toString());
      } else {
        print('request uri: ${request.uri}\n'
            'request requested uri: ${request.requestedUri}');
        await request.response.close();
      }
    });

    final String serverUrl = 'http://localhost:${webServer.port}';
    return ServedResults(results == null ? 'page' : results.filename, serverUrl);
  }
}

Future<ServedResults> serveToWebApp({
  List<GraphResult> results,
  Future<bool> handler(HttpResponse response, String uri),
  bool verbose,
}) async {
  final Map<String,GraphResult> resultMap = <String,GraphResult>{};
  for (final GraphResult result in results) {
    if (resultMap.containsKey(result.filename)) {
      if (resultMap[result.filename].sameSource(result)) {
        stderr.writeln('Ignoring duplicate results added for ${result.filename}');
      } else {
        stderr.writeln('Conflicting results added for ${result.filename}');
        exit(-1);
      }
    } else {
      resultMap[result.filename] = result;
    }
  }
  final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((HttpRequest request) async {
    request.response.headers.set('access-control-allow-origin', '*');
    String uri = request.uri.toString();
    if (uri == '/list') {
      final List<String> filenames = resultMap.keys.map((String key) => resultMap[key].webKey).toList();
      final String filenameJson = const JsonEncoder.withIndent('  ').convert(filenames);
      request.response.headers.contentType = ContentType.json;
      request.response.headers.contentLength = filenameJson.length;
      request.response.write(filenameJson);
      request.response.close();
    } else if (uri.startsWith('/result?')) {
      final String key = uri.substring(8);
      if (resultMap.containsKey(key)) {
        final String content = await resultMap[key].json;
        final List<int> encoded = request.response.encoding.encoder.convert(content);
        request.response.headers.contentType = ContentType.json;
        request.response.headers.contentLength = encoded.length;
        request.response.add(encoded);
        request.response.close();
      }
    } else {
      if (uri == '/') {
        uri = '/index.html';
      }
      if (!await handler(request.response, uri)) {
        request.response.statusCode = HttpStatus.notFound;
        request.response.close();
      }
    }
    if (verbose) {
      print('[web app server] served ${request.response.headers.contentLength} bytes: $uri');
    }
  });
  return ServedResults('web app', 'http://localhost:${server.port}');
}
