// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:flutter/material.dart';

import 'package:flutter_benchmark_utils/benchmark_data.dart';

import 'timeline_summary_graphing.dart';

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

void performGet(String url, void onValue(http.Response value), void onError(String msg)) async {
  await http.get(url)
      .then(onValue)
      .catchError((error) => onError('Error contacting results server: $error'));
}

class _GraphTab {
  _GraphTab(this.name, this.graph);

  final String name;
  final Widget graph;
}

class _TimelineGraphPageState extends State<_TimelineGraphPage> with SingleTickerProviderStateMixin {
  List<_GraphTab> _tabs;
  String _message;

  @override
  void initState() {
    super.initState();
    _tabs = <_GraphTab>[];
    getList();
  }

  void setMessage(String message, [String key]) {
    setState(() {
      _message = message;
    });
  }

  void addKey(String name) {
    setState(() {
      _message = null;
      _tabs.add(_GraphTab(name, _TimelineLoaderPage(name)));
    });
  }

  void getList() {
    setMessage('Loading list of results...');
    performGet('/list', (http.Response response) {
      if (response.statusCode == 200) {
        dynamic json = JsonDecoder().convert(response.body);
        for (String key in json) {
          addKey(key);
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
          title: Text('Timeline Graphing Page'),
          centerTitle: true,
          bottom: TabBar(
            isScrollable: true,
            tabs: [ ..._tabs.map((tab) => Text(tab.name)) ],
          ),
        ),
        body: _message != null ? Text(_message) : TabBarView(
          children: [ ..._tabs.map((tab) => tab.graph) ],
        ),
      ),
    );
  }
}

class _TimelineLoaderPage extends StatefulWidget {
  _TimelineLoaderPage(this.pageKey);

  final String pageKey;

  @override
  State createState() => _TimelineLoaderPageState();
}

class _TimelineLoaderPageState extends State<_TimelineLoaderPage> with AutomaticKeepAliveClientMixin {
  Widget _body;

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

  void setResults(TimelineResults results) {
    setState(() {
      _body = RepaintBoundary(child: TimelineResultsGraphWidget(results));
    });
  }

  void getResults(String key) {
    setMessage('Loading results from $key...');
    performGet('/result?$key', (http.Response response) {
      if (response.statusCode == 200) {
        TimelineResults results = TimelineResults(JsonDecoder().convert(response.body));
        if (results != null) {
          setResults(results);
        } else {
          setMessage('Error: Results file for $key was not in a recognizable format.');
        }
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