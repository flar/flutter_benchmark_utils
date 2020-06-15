// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';
import 'dart:async';

import 'package:resource/resource.dart' show Resource;

const kPackagePrefix = 'package:flutter_benchmark_utils/src/';
const kStandardScripts = [
  '/crc-png.js',
  '/base64-data-converter.js',
  '/png-utils.js',
  '/html-utils.js',
];

final ContentType kContentTypeJs = ContentType('application', 'javascript');

class GraphResult {
  GraphResult(this.filename, this.json);

  final String filename;
  final String json;
}

abstract class _RequestHandler {
  Future handle(HttpResponse response, String uri);
}

class _IgnoreRequestHandler extends _RequestHandler {
  Future handle(HttpResponse response, String uri) async {
    response.statusCode = HttpStatus.notFound;
    await response.close();
  }
}

class _DefaultRequestHandler extends _FileRequestHandler {
  _DefaultRequestHandler(String packagePrefix, this.defaultFile) : super(packagePrefix);

  final String defaultFile;

  Future handle(HttpResponse response, String uri) {
    return super.handle(response, defaultFile);
  }
}

class _FileRequestHandler extends _RequestHandler {
  _FileRequestHandler(this.packagePrefix);

  final String packagePrefix;

  ContentType _typeFor(String uri) {
    if (uri.endsWith('.html')) return ContentType.html;
    if (uri.endsWith('.js')) return kContentTypeJs;
    return ContentType.binary;
  }

  Future handle(HttpResponse response, String uri) async {
    Resource fileResource = Resource('$packagePrefix$uri');
    response.headers.contentType = _typeFor(uri);
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

class _ResultsRequestHandler extends _StringRequestHandler {
  _ResultsRequestHandler(String variableName, [ GraphResult results ])
      : super(kContentTypeJs,
              'results_filename = "${results?.filename}";\n'
              '$variableName = ${results == null ? null : results.json};');
}

class GraphServer {
  GraphServer(
      {
        this.graphHtmlName,
        this.resultsScriptName,
        this.resultsVariableName,
        this.results,
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
      for (var script in kStandardScripts)
        script: _FileRequestHandler(kPackagePrefix),
    };
  }

  final String graphHtmlName;
  final String resultsScriptName;
  final String resultsVariableName;
  final GraphResult results;

  Map<String,_RequestHandler> _responseMap;
  Map<String, _RequestHandler> get responseMap => _responseMap;

  Future<String> initWebServer() async {
    var webServer = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );

    webServer.listen((request) async {
      _RequestHandler handler = responseMap[request.uri.toString()];
      if (handler != null) {
        await handler.handle(request.response, request.uri.toString());
      } else {
        print('request uri: ${request.uri}\n'
            'request requested uri: ${request.requestedUri}');
        await request.response.close();
      }
    });

    String serverUrl = 'http://localhost:${webServer.port}';
    if (results == null) {
      print('Graphing page at ${serverUrl}');
    } else {
      print('Graphing ${results.filename} on ${serverUrl}');
    }
    return serverUrl;
  }
}
