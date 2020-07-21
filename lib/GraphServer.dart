// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:resource/resource.dart' show Resource;
import 'package:archive/archive.dart';

const kPackagePrefix = 'package:flutter_benchmark_utils/src/';
const kStandardScripts = [
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

Future<Archive> _loadWebAppArchive() async {
  Resource webAppResource = Resource('package:flutter_benchmark_utils/src/webapp.zip');
  return ZipDecoder().decodeBytes(await webAppResource.readAsBytes());
}

class ServedResults {
  ServedResults(this.name, this.url);

  final String name;
  final String url;
}

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

  Future<ServedResults> initWebServer() async {
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
    return ServedResults(results == null ? 'page' : results.filename, serverUrl);
  }
}

Future<ServedResults> serveToWebApp(
    List<GraphResult> results,
    String webAppPath,
    bool verbose,
    ) async
{
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
  if (webAppPath != null) {
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
      print('[web app server] served ${request.response.headers.contentLength} bytes: $uri');
    }
  });
  return ServedResults('web app', 'http://localhost:${server.port}');
}
