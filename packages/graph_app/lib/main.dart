// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_benchmark_utils/benchmark_data.dart';
import 'package:graph_app/dashboard_graphing.dart';
import 'package:http/http.dart' as http;

import 'series_graphing.dart';

void main() {
  runApp(_GraphApp());
}

class _GraphApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Timeline Graphing Web App',
      home: _TimelineGraphPage(),
    );
  }
}

class _TimelineGraphPage extends StatefulWidget {
  @override
  State createState() => _TimelineGraphPageState();
}

Future<void> performGet(String url, void onValue(http.Response value), void onError(String msg)) async {
  await http.get(Uri.parse(url))
      .then(onValue)
      .catchError((dynamic error) => onError('Error contacting results server for [$url]: $error'));
}

class _GraphTab {
  _GraphTab(this.name, this.graph);

  final String name;
  final Widget graph;
}

class _TimelineGraphPageState extends State<_TimelineGraphPage> with SingleTickerProviderStateMixin {
  final List<_GraphTab> _tabs = <_GraphTab>[];
  String? _message;

  @override
  void initState() {
    super.initState();
    getList();
  }

  void setMessage(String message) {
    setState(() {
      _message = message;
    });
  }

  void addKey(String key) {
    final int colonIndex = key.indexOf(':');
    String name;
    Widget graph;
    if (colonIndex < 0) {
      name = key;
      graph = _TimelineLoaderPage(BenchmarkType.TIMELINE_SUMMARY, name);
    } else {
      final String typeName = key.substring(0, colonIndex);
      name = key.substring(colonIndex + 1);
      BenchmarkType? type;
      switch (typeName) {
        case 'BenchmarkType.TIMELINE_TRACE':
          type = BenchmarkType.TIMELINE_TRACE;
          break;
        case 'BenchmarkType.TIMELINE_SUMMARY':
          type = BenchmarkType.TIMELINE_SUMMARY;
          break;
        case 'BenchmarkType.BENCHMARK_DASHBOARD':
          type = BenchmarkType.BENCHMARK_DASHBOARD;
          break;
        case 'BenchmarkType.MEMINFO_TRACE':
          type = BenchmarkType.MEMINFO_TRACE;
          break;
        case 'BenchmarkType.BENCHMARK_AB_COMPARISON':
        default:
          break;
      }
      graph = (type == null)
          ? Text('data type $typeName not yet supported by web app')
          : _TimelineLoaderPage(type, name);
    }
    setState(() {
      _message = null;
      _tabs.add(_GraphTab(name, graph));
    });
  }

  void getList() {
    setMessage('Loading list of results...');
    performGet('/list', (http.Response response) {
      if (response.statusCode == 200) {
        final dynamic json = const JsonDecoder().convert(response.body);
        for (final dynamic key in json) {
          addKey(key as String);
        }
        if (_tabs.isEmpty) {
          setMessage('No results to load');
        }
      } else {
        setMessage('Cannot load list of results, status = ${response.statusCode}');
      }
    }, (String msg) => setMessage(msg));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Timeline Graphing Page'),
          centerTitle: true,
          bottom: TabBar(
            isScrollable: true,
            tabs: <Widget>[ ..._tabs.map((_GraphTab tab) => Text(tab.name)) ],
          ),
        ),
        body: _message != null ? Text(_message!) : TabBarView(
          children: <Widget>[ ..._tabs.map((_GraphTab tab) => tab.graph) ],
        ),
      ),
    );
  }
}

class _TimelineLoaderPage extends StatefulWidget {
  const _TimelineLoaderPage(this.pageType, this.pageKey);

  final BenchmarkType pageType;
  final String pageKey;

  @override
  State createState() => _TimelineLoaderPageState();
}

class _TimelineLoaderPageState extends State<_TimelineLoaderPage> with AutomaticKeepAliveClientMixin {
  late Widget _body;

  @override
  void initState() {
    super.initState();
    getResults(widget.pageKey);
  }

  @override bool get wantKeepAlive => true;

  void setMessage(String message) {
    setState(() {
      _body = Center(child:Text(message.toString()));
    });
  }

  void setBody(Widget widget) {
    setState(() {
      _body = RepaintBoundary(child: widget);
    });
  }

  void setResults(Map<String,dynamic> decoded) {
    switch (widget.pageType) {
      case BenchmarkType.TIMELINE_TRACE:
      case BenchmarkType.TIMELINE_SUMMARY:
        setBody(SeriesSourceGraphWidget(TimelineResults(decoded)));
        break;
      case BenchmarkType.MEMINFO_TRACE:
        setBody(SeriesSourceGraphWidget(MeminfoSeriesSource.fromJsonMap(decoded)));
        break;
      case BenchmarkType.BENCHMARK_DASHBOARD:
        setBody(DashboardGraphWidget(BenchmarkDashboard.fromJsonMap(decoded)));
        break;
      default:
        setMessage('No graphing widget for ${widget.pageType}');
        break;
    }
  }

  void getResults(String key) {
    setMessage('Loading results from $key...');
    performGet('/result?$key', (http.Response response) {
      if (response.statusCode == 200) {
        final dynamic decoded = const JsonDecoder().convert(response.body);
        setResults(decoded as Map<String,dynamic>);
      } else {
        setMessage('Error: Cannot load results for $key, status = ${response.statusCode}');
      }
    }, (String msg) => setMessage(msg));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _body;
  }
}
