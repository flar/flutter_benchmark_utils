import 'graph_utils.dart';
import 'time_utils.dart';

class MeminfoEntry implements Comparable<MeminfoEntry> {
  factory MeminfoEntry.fromJson(Map<String,dynamic> jsonMap) {
    final TimeVal timestamp = _getTimestamp(jsonMap['timestamp']);
    final int rss = _getMemory(jsonMap['rss']);
    final int capacity = _getMemory(jsonMap['capacity']);
    final int used = _getMemory(jsonMap['used']);
    final dynamic adbInfo = jsonMap['adb_memoryInfo'];
    if (adbInfo is! Map<String,dynamic>) {
      throw 'Missing or unrecognized adb memory info: $adbInfo';
    }
    final TimeVal adbRealTime = _getTimestamp(adbInfo['Realtime']);
    final int adbJavaHeap = _getMemory(adbInfo['Java Heap']);
    final int adbNativeHeap = _getMemory(adbInfo['Native Heap']);
    final int adbCode = _getMemory(adbInfo['Code']);
    final int adbStack = _getMemory(adbInfo['Stack']);
    final int adbGraphics = _getMemory(adbInfo['Graphics']);
    final int adbOther = _getMemory(adbInfo['Private Other']);
    final int adbSystem = _getMemory(adbInfo['System']);
    final int adbTotal = _getMemory(adbInfo['Total']);
    if (adbTotal != (adbJavaHeap + adbNativeHeap + adbCode + adbStack + adbGraphics + adbOther + adbSystem)) {
      throw 'adb memory values do not add up to recorded total $adbTotal';
    }
    final dynamic cacheInfo = jsonMap['raster_cache'];
    if (cacheInfo is! Map<String,dynamic>) {
      throw 'Missing or unrecognized raster cache info: $cacheInfo';
    }
    final int cacheLayer = _getMemory(cacheInfo['layerBytes']);
    final int cachePicture = _getMemory(cacheInfo['pictureBytes']);
    return MeminfoEntry._internal(
      timestamp: timestamp,
      rss: rss,
      capacity: capacity,
      used: used,
      adbRealTime: adbRealTime,
      adbJavaHeap: adbJavaHeap,
      adbNativeHeap: adbNativeHeap,
      adbCode: adbCode,
      adbStack: adbStack,
      adbGraphics: adbGraphics,
      adbOther: adbOther,
      adbSystem: adbSystem,
      adbTotal: adbTotal,
      cacheLayer: cacheLayer,
      cachePicture: cachePicture,
    );
  }

  MeminfoEntry._internal({
    required this.timestamp,
    required this.rss,
    required this.capacity,
    required this.used,
    required this.adbRealTime,
    required this.adbJavaHeap,
    required this.adbNativeHeap,
    required this.adbCode,
    required this.adbStack,
    required this.adbGraphics,
    required this.adbOther,
    required this.adbSystem,
    required this.adbTotal,
    required this.cacheLayer,
    required this.cachePicture,
  });

  static TimeVal _getTimestamp(dynamic ts) {
    if (ts is int) {
      return TimeVal.fromMillis(ts);
    }
    throw 'Unrecognized timestamp: $ts';
  }

  static int _getMemory(dynamic size) {
    if (size is int) {
      return size;
    }
    throw 'Unrecognized memory size: $size';
  }

  final TimeVal timestamp;

  final int rss;
  final int capacity;
  final int used;

  final TimeVal adbRealTime;
  final int adbJavaHeap;
  final int adbNativeHeap;
  final int adbCode;
  final int adbStack;
  final int adbGraphics;
  final int adbOther;
  final int adbSystem;
  final int adbTotal;

  final int cacheLayer;
  final int cachePicture;

  @override
  int compareTo(MeminfoEntry other) {
    return timestamp.compareTo(other.timestamp);
  }
}

class MeminfoSeries extends GraphableSeries {
  MeminfoSeries._internal({
    required this.titleName,
    required this.frames,
    required this.average,
    required this.percent90,
    required this.percent99,
    required this.worst,
  });

  @override final String titleName;
  @override SeriesType get seriesType => SeriesType.SEQUENTIAL_EVENTS;

  @override final List<GraphableEvent> frames;
  @override TimeFrame get wholeRun => TimeFrame(start: frames.first.start, end: frames.last.end);

  @override final UnitValue average;
  @override final UnitValue percent90;
  @override final UnitValue percent99;
  @override final UnitValue worst;
  @override UnitValue get largest => worst;

  @override UnitValue get minRange => MemoryUnits.oneMegabyte;
}

class MeminfoSeriesSource extends GraphableSeriesSource {
  factory MeminfoSeriesSource.fromJsonMap(Map<String,dynamic> jsonMap) {
    final dynamic samples = jsonMap['samples'];
    if (samples is! Map<String,dynamic>) {
      throw 'unrecognized samples: $samples';
    }
    if (samples['version'] != 1) {
      throw 'unrecognized version in meminfo dump: ${samples['version']}';
    }
    if (samples['dartDevToolsScreen'] != 'memory') {
      throw 'unrecognized devTools screen: ${samples['dartDevToolsScreen']}';
    }
    final dynamic list = samples['data'];
    if (list is! List) {
      throw 'unrecognized data list: $list';
    }
    final List<MeminfoEntry> entries = <MeminfoEntry>[];
    for (final dynamic entry in list) {
      if (entry is! Map<String,dynamic>) {
        throw 'data contains ill-formed entry: $entry';
      }
      entries.add(MeminfoEntry.fromJson(entry));
    }
    entries.sort();
    return MeminfoSeriesSource._internal(entries);
  }

  MeminfoSeriesSource._internal(this.entries);

  final List<MeminfoEntry> entries;

  @override
  List<String> get allSeriesNames => const <String>[
    'Java Heap',
    'Native Heap',
    'Code',
    'Stack',
    'Graphics',
    'Other',
    'System',
    'Total',
    'Layer Cache',
    'Picture Cache',
  ];

  @override
  List<GraphableSeries> get defaultGraphs => <GraphableSeries>[
    seriesFor('Total'),
  ];

  GraphableSeries _makeSeries(String title, int Function(MeminfoEntry) accessor) {
    final List<GraphableEvent> events = entries
        .map((MeminfoEntry e) => MemorySizeEvent.kilobytes(measurementTime: e.timestamp, size: accessor(e).toDouble()))
        .toList();
    final List<GraphableEvent> immutableEvents = List<GraphableEvent>.unmodifiable(events);

    // Then sort by duration for statistics
    events.sort();
    return MeminfoSeries._internal(
      titleName:  '$title Memory Usage',
      frames:     immutableEvents,
      average:    GraphableSeries.computeAverage(events),
      percent90:  GraphableSeries.locatePercentile(events, 90).reading,
      percent99:  GraphableSeries.locatePercentile(events, 99).reading,
      worst:      events.last.reading,
    );
  }

  @override
  GraphableSeries seriesFor(String seriesName) {
    switch (seriesName) {
      case 'Java Heap': return _makeSeries(seriesName, (MeminfoEntry e) => e.adbJavaHeap);
      case 'Native Heap': return _makeSeries(seriesName, (MeminfoEntry e) => e.adbNativeHeap);
      case 'Code': return _makeSeries(seriesName, (MeminfoEntry e) => e.adbCode);
      case 'Stack': return _makeSeries(seriesName, (MeminfoEntry e) => e.adbStack);
      case 'Graphics': return _makeSeries(seriesName, (MeminfoEntry e) => e.adbGraphics);
      case 'Other': return _makeSeries(seriesName, (MeminfoEntry e) => e.adbOther);
      case 'System': return _makeSeries(seriesName, (MeminfoEntry e) => e.adbSystem);
      case 'Total': return _makeSeries(seriesName, (MeminfoEntry e) => e.adbTotal);
      case 'Layer Cache': return _makeSeries(seriesName, (MeminfoEntry e) => e.cacheLayer);
      case 'Picture Cache': return _makeSeries(seriesName, (MeminfoEntry e) => e.cachePicture);
    }
    throw 'Unrecognized timeline measurement name: $seriesName';
  }
}