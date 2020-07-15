// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'timeline_summary.dart';
import 'timeline_summary_graphing.dart';

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:flutter/material.dart';

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

class _TimelineGraphPageState extends State<_TimelineGraphPage> {
  List<String> _keys = <String>[];
  String _currentKey;
  Widget _body;

  @override
  void initState() {
    super.initState();
    setMessage('Loading list of results...');
    getList();
  }

  void setMessage(String message, [String key]) {
    setState(() {
      _currentKey = key;
      _body = Text(message.toString());
    });
  }

  void setResults(String key, TimelineResults results) {
    setState(() {
      _currentKey = key;
      _body = TimelineResultsGraphWidget(results);
    });
  }

  void addKey(String name) {
    setState(() {
      _keys.add(name);
    });
  }

  void performGet(String url, void onValue(http.Response value)) async {
    await http.get(url)
        .then(onValue)
        .catchError((error) => setMessage('Error contacting results server: $error'));
  }

  void getList() {
    performGet('/list', (http.Response response) {
      if (response.statusCode == 200) {
        dynamic json = JsonDecoder().convert(response.body);
        for (String key in json) {
          addKey(key);
        }
        if (_keys.isNotEmpty) {
          getResults(_keys[0]);
        } else {
          setMessage('No results to load');
        }
      } else {
        setMessage('Cannot load list of results, status = ${response.statusCode}');
      }
    });
  }

  void getResults(String key) {
    setMessage('Loading results from $key...', key);
    performGet('/result?$key', (http.Response response) {
      if (response.statusCode == 200) {
        TimelineResults results = TimelineResults(JsonDecoder().convert(response.body));
        if (results != null) {
          setResults(key, results);
        } else {
          setMessage('Error: Results file for $key was not in a recognizable format.');
        }
      } else {
        setMessage('Error: Cannot load results for $key, status = ${response.statusCode}');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Timeline Graphing Page'),
        centerTitle: true,
        actions: <Widget>[
          DropdownButton<String>(
            onChanged: (key) => getResults(key),
            value: _currentKey,
            icon: const Icon(
              Icons.arrow_downward,
              color: Colors.white,
            ),
            items: <DropdownMenuItem<String>>[
              for (String key in _keys)
                DropdownMenuItem(value: key, child: Text(key),),
            ],
          ),
          Padding(padding: EdgeInsets.only(right: 50.0),),
        ],
      ),
      body: Center(
        child: _body,
      ),
    );
  }
}
