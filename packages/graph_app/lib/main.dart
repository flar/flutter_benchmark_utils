// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;

import 'package:flutter/material.dart';

final List<Color> heatColors = [
  Colors.green,
  Colors.green.shade200,
  Colors.yellow.shade600,
  Colors.red,
];

class TimeVal {
  static max(TimeVal a, TimeVal b) { return a > b ? a : b; }
  static min(TimeVal a, TimeVal b) { return a < b ? a : b; }

  TimeVal.fromNanos(num nanos)     : this._nanos = nanos.toDouble();
  TimeVal.fromMicros(num micros)   : this._nanos = micros * 1000.0;
  TimeVal.fromMillis(num millis)   : this._nanos = millis * 1000.0 * 1000.0;
  TimeVal.fromSeconds(num seconds) : this._nanos = seconds * 1000.0 * 1000.0 * 1000.0;

  final double _nanos;

  double get seconds => millis / 1000.0;
  double get millis  => micros / 1000.0;
  double get micros  => nanos  / 1000.0;
  double get nanos   => _nanos;

  String get stringSeconds => seconds.toString();
  String get stringMillis  => millis.toString();
  String get stringMicros  => micros.toString();
  String get stringNanos   => nanos.toString();

  @override int get hashCode => _nanos.hashCode;
  @override bool operator == (dynamic t) => t is TimeVal && this._nanos == t._nanos;

  bool operator <  (TimeVal t) => this._nanos < t._nanos;
  bool operator <= (TimeVal t) => this._nanos <= t._nanos;
  bool operator >= (TimeVal t) => this._nanos >= t._nanos;
  bool operator >  (TimeVal t) => this._nanos > t._nanos;

  TimeVal operator + (TimeVal t) => TimeVal.fromNanos(this._nanos + t._nanos);
  TimeVal operator - (TimeVal t) => TimeVal.fromNanos(this._nanos - t._nanos);

  double operator / (TimeVal t) => this._nanos / t._nanos;
}

class Event {
  Event(this.start, this.end);

  final TimeVal start;
  final TimeVal end;
}

class ThreadInfo {
  static final ThreadInfo build = ThreadInfo._(
    'Build',
    'build',
    'frame_begin_times',
    'frame_build_times',
  );
  static final ThreadInfo render = ThreadInfo._(
    'Render',
    'rasterizer',
    'frame_rasterizer_begin_times',
    'frame_rasterizer_times',
  );

  ThreadInfo._(this.titleName, this.keyString, this.startKey, this.durationKey);

  final String titleName;
  final String keyString;
  final String startKey;
  final String durationKey;

  String _measurementKey(String prefix) =>
      '${prefix}_frame_${keyString}_time_millis';

  String get averageKey   => _measurementKey('average');
  String get percent90Key => _measurementKey('90th_percentile');
  String get percent99Key => _measurementKey('99th_percentile');
  String get worstKey     => _measurementKey('worst');
}

class TimelineThreadResults {
  TimelineThreadResults.fromJson(Map<String,dynamic> jsonMap, this.threadInfo)
      : this.average   = _getTimeVal(jsonMap[threadInfo.averageKey]),
        this.percent90 = _getTimeVal(jsonMap[threadInfo.percent90Key]),
        this.percent99 = _getTimeVal(jsonMap[threadInfo.percent99Key]),
        this.worst     = _getTimeVal(jsonMap[threadInfo.worstKey]),
        this.startTimes = _getTimeListMicros(jsonMap[threadInfo.startKey]),
        this.durations  = _getTimeListMicros(jsonMap[threadInfo.durationKey])
  {
    assert(this.startTimes.length == this.durations.length);
  }

  final ThreadInfo threadInfo;

  final TimeVal average;
  final TimeVal percent90;
  final TimeVal percent99;
  final TimeVal worst;
  final List<TimeVal> startTimes;
  final List<TimeVal> durations;

  static TimeVal _getTimeVal(dynamic rawTimeVal) {
    assert(rawTimeVal is num);
    return TimeVal.fromMillis(rawTimeVal);
  }

  static List<TimeVal> _getTimeListMicros(dynamic rawTimes) {
    return (rawTimes as List<dynamic>).map((e) => TimeVal.fromMicros(e)).toList();
  }

  int heatIndex(TimeVal t) {
    if (t < average) return 0;
    if (t < percent90) return 1;
    if (t < percent99) return 2;
    return 3;
  }
}

class TimelineResults {
  TimelineResults.fromJson(Map<String,dynamic> jsonMap)
      : this.buildData  = TimelineThreadResults.fromJson(jsonMap, ThreadInfo.build),
        this.renderData = TimelineThreadResults.fromJson(jsonMap, ThreadInfo.render);

  final TimelineThreadResults buildData;
  final TimelineThreadResults renderData;
}

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
        try {
          setResults(key, TimelineResults.fromJson(JsonDecoder().convert(response.body)));
        } catch (e) {
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

class TimelineResultsGraphWidget extends StatelessWidget {
  TimelineResultsGraphWidget(this.results)
      : this.worst = TimeVal.max(results.buildData.worst, results.renderData.worst),
        assert(results != null);

  final TimelineResults results;
  final TimeVal worst;

  TableRow _makeTableRow(String name, TimeVal value, Color color) {
    return TableRow(
      children: [
        Container(
          padding: EdgeInsets.only(right: 5.0, top: 10.0),
          child: Text(name, textAlign: TextAlign.right),
        ),
        Container(
          padding: EdgeInsets.only(left: 5.0, top: 10.0),
          child: Text(value.stringMillis),
        ),
        Container(
          alignment: Alignment.centerLeft,
          padding: EdgeInsets.only(left: 5.0, top: 10.0),
          width: 100.0,
          height: 20.0,
          child: FractionallySizedBox(
            widthFactor: value / worst,
            child: Container(
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  List<TableRow> _makeTableRows(TimelineThreadResults tr) {
    return <TableRow>[
      _makeTableRow(tr.threadInfo.averageKey,   tr.average,   heatColors[0]),
      _makeTableRow(tr.threadInfo.percent90Key, tr.percent90, heatColors[1]),
      _makeTableRow(tr.threadInfo.percent99Key, tr.percent99, heatColors[2]),
      _makeTableRow(tr.threadInfo.worstKey,     tr.worst,     heatColors[3]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        Table(
          columnWidths: {
            0: FixedColumnWidth(300.0),
            1: FixedColumnWidth(200.0),
            2: FixedColumnWidth(300.0),
          },
          children: <TableRow>[
            ..._makeTableRows(results.buildData),
            ..._makeTableRows(results.renderData),
          ],
        ),
        TimelineGraphWidget(results.buildData),
        TimelineGraphWidget(results.renderData),
      ],
    );
  }
}

class TimelineGraphWidget extends StatelessWidget {
  TimelineGraphWidget(this._timeline);

  final TimelineThreadResults _timeline;

  Widget _graphLine(int index) {
    TimeVal value = _timeline.durations[index];
    return Container(
      alignment: Alignment.bottomCenter,
      width: 1.0,
      height: 100.0,
      child: FractionallySizedBox(
        heightFactor: value / _timeline.worst,
        child: Container(
          alignment: Alignment.bottomCenter,
          color: heatColors[_timeline.heatIndex(value)],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text('Frame ${_timeline.threadInfo.titleName} Times', style: TextStyle(fontSize: 24),),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (int i = 0; i < _timeline.startTimes.length; i++)
              _graphLine(i),
          ],
        ),
      ],
    );
  }
}