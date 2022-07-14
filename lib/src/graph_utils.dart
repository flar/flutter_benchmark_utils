import 'dart:math';

import 'package:flutter_benchmark_utils/benchmark_data.dart';
import 'package:meta/meta.dart';

import 'time_utils.dart';

abstract class UnitValueFormatter {
  /// The name of the units as used in sentences and descriptions.
  String get unitName;

  /// The short name of the units as used as a suffix in formatting values.
  String get unitSuffix;

  /// The formatted string for the given value (which must match the [units]
  /// represented by this formatter) and an optional numeric precision
  /// (with -1 precision representing no numeric formatting preference).
  String format(UnitValue value, {int precision = -1});
}

class _UnitValueFormatterImpl implements UnitValueFormatter {
  _UnitValueFormatterImpl(this.units, this.unitName, this.unitSuffix, {double scale = 1.0})
      : _scale = scale;

  final double _scale;

  final Units units;
  @override final String unitName;
  @override final String unitSuffix;

  @override
  String format(UnitValue value, {int precision = -1}) {
    assert(value.units == units);
    final double v = value.value / _scale;
    String str = precision >= 0 ? v.toStringAsFixed(precision) : v.toString();
    if (str.contains('.') && !str.contains('e') && !str.contains('E')) {
      while (str.endsWith('00')) {
        str = str.substring(0, str.length - 1);
      }
    }
    return '$str$unitSuffix';
  }
}

String _capitalize(String s) => s.substring(0, 1).toUpperCase() + s.substring(1);

abstract class Units {
  /// The general type of the measurement: 'time', 'count', 'memory', etc.
  String get description;
  String get upperDescription;
  String get pluralDescription;
  String get upperPluralDescription;

  /// Format a string for the given value (which must match this [Units]
  /// instance) and the optional precision using any scaling of the common
  /// units. If a particular scale is needed for consistency in describing
  /// multiple values across a range, then a range specific formatter
  /// should be used. See [rangeFormatter].
  String format(UnitValue value, {int precision = -1});

  /// Provide a formatter that can format any value in the specified range
  /// with a consistent scaled unit.
  UnitValueFormatter rangeFormatter(UnitValue begin, UnitValue end);

  UnitValue value(double value);
}

abstract class _FixedUnits implements Units {
  UnitValueFormatter get _formatter;

  @override String get upperDescription => _capitalize(description);
  @override String get pluralDescription => description + 's';
  @override String get upperPluralDescription => _capitalize(pluralDescription);

  @override
  String format(UnitValue value, {int precision = -1}) =>
      _formatter.format(value, precision: precision);

  @override
  UnitValueFormatter rangeFormatter(UnitValue begin, UnitValue end) => _formatter;
}

abstract class _ScaledUnits implements Units {
  List<_UnitValueFormatterImpl> get _formatters;

  @override String get upperDescription => _capitalize(description);
  @override String get pluralDescription => description + 's';
  @override String get upperPluralDescription => _capitalize(pluralDescription);

  UnitValueFormatter _for(double magnitude) =>
      _formatters.lastWhere((_UnitValueFormatterImpl f) => f._scale <= magnitude,
        orElse: () => _formatters.first,
      );

  @override
  String format(UnitValue value, {int precision = -1}) {
    return _for(value.value).format(value, precision: precision);
  }

  @override
  UnitValueFormatter rangeFormatter(UnitValue begin, UnitValue end) =>
      _for(UnitValue.max(begin, end).value);
}

class TimeUnits with _ScaledUnits implements Units {
  TimeUnits._();

  static final TimeUnits units = TimeUnits._();

  static UnitValue seconds(num seconds) => UnitValue(units, seconds.toDouble());
  static UnitValue millis(num millis) => UnitValue(units, millis * 1E-3);
  static UnitValue micros(num micros) => UnitValue(units, micros * 1E-6);
  static UnitValue nanos(num nanos) => UnitValue(units, nanos * 1E-9);

  static final UnitValue oneSecond = seconds(1);
  static final UnitValue oneMillisecond = millis(1);
  static final UnitValue oneMicrosecond = micros(1);
  static final UnitValue oneNanosecond = nanos(1);

  static final _UnitValueFormatterImpl _secondsFormatter = _UnitValueFormatterImpl(units, 'seconds', 's');
  static final _UnitValueFormatterImpl _msFormatter = _UnitValueFormatterImpl(units, 'milliseconds', 'ms', scale: 1E-3);
  static final _UnitValueFormatterImpl _usFormatter = _UnitValueFormatterImpl(units, 'microseconds', 'us', scale: 1E-6);
  static final _UnitValueFormatterImpl _nsFormatter = _UnitValueFormatterImpl(units, 'nanoseconds', 'ns', scale: 1E-9);
  static final List<_UnitValueFormatterImpl> _timeFormatters = <_UnitValueFormatterImpl>[
    _nsFormatter, _usFormatter, _msFormatter, _secondsFormatter,
  ];

  @override String get description => 'time';
  @override List<_UnitValueFormatterImpl> get _formatters => _timeFormatters;

  @override
  UnitValue value(double value) => UnitValue(units, value);
}

class MemoryUnits with _ScaledUnits implements Units {
  MemoryUnits._();

  static final MemoryUnits units = MemoryUnits._();

  static final double _kbScale = pow(2.0, 10).toDouble();
  static final double _mbScale = pow(2.0, 20).toDouble();
  static final double _gbScale = pow(2.0, 30).toDouble();
  static final double _tbScale = pow(2.0, 40).toDouble();

  static UnitValue bytes(num bytes) => UnitValue(units, bytes.toDouble());
  static UnitValue kilobytes(num kb) => UnitValue(units, kb * _kbScale);
  static UnitValue megabytes(num mb) => UnitValue(units, mb * _mbScale);
  static UnitValue gigabytes(num gb) => UnitValue(units, gb * _gbScale);
  static UnitValue terabytes(num tb) => UnitValue(units, tb * _tbScale);

  static final UnitValue oneByte = bytes(1);
  static final UnitValue oneKilobyte = kilobytes(1);
  static final UnitValue oneMegabyte = megabytes(1);
  static final UnitValue oneGigabyte = gigabytes(1);
  static final UnitValue oneTerabyte = terabytes(1);

  static final _UnitValueFormatterImpl _byteFormatter = _UnitValueFormatterImpl(units, 'byte', 'b');
  static final _UnitValueFormatterImpl _kbFormatter = _UnitValueFormatterImpl(units, 'kilobyte', 'kb', scale: _kbScale);
  static final _UnitValueFormatterImpl _mbFormatter = _UnitValueFormatterImpl(units, 'megabyte', 'mb', scale: _mbScale);
  static final _UnitValueFormatterImpl _gbFormatter = _UnitValueFormatterImpl(units, 'gigabyte', 'gb', scale: _gbScale);
  static final _UnitValueFormatterImpl _tbFormatter = _UnitValueFormatterImpl(units, 'terabyte', 'tb', scale: _tbScale);
  static final List<_UnitValueFormatterImpl> _memoryFormatters = <_UnitValueFormatterImpl>[
    _byteFormatter, _kbFormatter, _mbFormatter, _gbFormatter, _tbFormatter
  ];

  @override String get description => 'memory';
  @override String get pluralDescription => 'memory';
  @override List<_UnitValueFormatterImpl> get _formatters => _memoryFormatters;

  @override
  UnitValue value(double value) => UnitValue(units, value);
}

class PercentUnits with _FixedUnits implements Units {
  PercentUnits._();

  static final PercentUnits units = PercentUnits._();

  static UnitValue percent(double percentage) => UnitValue(units, percentage);
  static UnitValue fraction(double fraction) => UnitValue(units, fraction * 100);

  static UnitValue onePercent = percent(1.0);

  @override String get description => 'percentage';
  @override late final UnitValueFormatter _formatter = _UnitValueFormatterImpl(units, 'percent', '%');

  @override
  UnitValue value(double value) => UnitValue(units, value);
}

class PictureCountUnits with _FixedUnits implements Units {
  PictureCountUnits._();

  static final PictureCountUnits units = PictureCountUnits._();

  static UnitValue pictures(num pictures) => UnitValue(units, pictures.toDouble());

  static final UnitValue onePicture = pictures(1);

  @override String get description => 'picture';
  @override late final UnitValueFormatter _formatter = _UnitValueFormatterImpl(units, 'pictures', 'pics');

  @override
  UnitValue value(double value) => UnitValue(units, value);
}

class FlowCountUnits with _FixedUnits implements Units {
  FlowCountUnits._();

  static final FlowCountUnits units = FlowCountUnits._();

  static UnitValue uses(num uses) => UnitValue(units, uses.toDouble());

  static final UnitValue oneUse = uses(1);

  @override String get description => 'use';
  @override late final UnitValueFormatter _formatter = _UnitValueFormatterImpl(units, 'uses', 'uses');

  @override
  UnitValue value(double value) => UnitValue(units, value);
}

@immutable
class UnitValue {
  const UnitValue(this.units, this.value);

  final Units units;
  final double value;

  String valueString({int precision = -1}) => units.format(this, precision: precision);

  UnitValue operator+(UnitValue o) {
    assert(units == o.units);
    return UnitValue(units, value + o.value);
  }
  UnitValue operator-(UnitValue o) {
    assert(units == o.units);
    return UnitValue(units, value - o.value);
  }
  UnitValue operator*(double scale) => UnitValue(units, value * scale);
  UnitValue operator/(double scale) => UnitValue(units, value / scale);

  bool operator>(UnitValue other) {
    assert(units == other.units);
    return value > other.value;
  }
  bool operator>=(UnitValue other) {
    assert(units == other.units);
    return value >= other.value;
  }

  bool operator<(UnitValue other) {
    assert(units == other.units);
    return value < other.value;
  }
  bool operator<=(UnitValue other) {
    assert(units == other.units);
    return value <= other.value;
  }

  static UnitValue min(UnitValue a, UnitValue b) => a <= b ? a : b;
  static UnitValue max(UnitValue a, UnitValue b) => a >= b ? a : b;

  @override
  int get hashCode => Object.hash(units, value);

  @override
  bool operator ==(Object other) =>
      other is UnitValue &&
          units == other.units &&
          value == other.value;
}

abstract class GraphableEvent extends TimeFrame implements Comparable<GraphableEvent> {
  GraphableEvent({
    required TimeVal start,
    TimeVal? end,
    TimeVal? duration,
  })
      : super(start: start, end: end, duration: duration);

  UnitValue get reading;
  UnitValue get minRange;

  bool get lowIsGood => true;

  @override int compareTo(GraphableEvent other) => lowIsGood
      ? reading.value.compareTo(other.reading.value)
      : other.reading.value.compareTo(reading.value);
}

class FlowEvent extends GraphableEvent {
  FlowEvent({
    required TimeVal start,
    TimeVal? end,
    TimeVal? duration,
    List<TimeVal>? steps,
  })
      : steps = List<TimeVal>.unmodifiable(steps ?? <TimeVal>[]),
        super(start: start, end: end, duration: duration);

  final List<TimeVal> steps;

  @override late final UnitValue reading = FlowCountUnits.uses(steps.length);
  @override UnitValue get minRange => FlowCountUnits.oneUse;

  @override bool get lowIsGood => false;
}

class MillisDurationEvent extends GraphableEvent {
  MillisDurationEvent({
    required TimeVal start,
    TimeVal? end,
    TimeVal? duration,
  })
      : super(start: start, end: end, duration: duration);

  @override late final UnitValue reading = TimeUnits.millis(duration.millis);
  @override UnitValue get minRange => TimeUnits.oneMillisecond;
}

class PercentUsageEvent extends GraphableEvent {
  PercentUsageEvent({
    required TimeVal measurementTime,
    required double percent,
  })
      : reading = PercentUnits.percent(percent),
        super(start: measurementTime, duration: TimeVal.fromNanos(1));

  @override final UnitValue reading;

  @override UnitValue get minRange => PercentUnits.onePercent;
}

class PictureCounterEvent extends GraphableEvent {
  PictureCounterEvent({
    required TimeVal measurementTime,
    required double count,
  })
      : reading = PictureCountUnits.pictures(count),
        super(start: measurementTime, duration: TimeVal.fromNanos(1));

  @override final UnitValue reading;

  @override UnitValue get minRange => PictureCountUnits.onePicture;
}

class MemorySizeEvent extends GraphableEvent {
  MemorySizeEvent.megabytes({
    required TimeVal measurementTime,
    required double size,
  })
      : reading = MemoryUnits.megabytes(size),
        super(start: measurementTime,  duration: TimeVal.fromNanos(1));

  MemorySizeEvent.kilobytes({
    required TimeVal measurementTime,
    required double size,
  })
      : reading = MemoryUnits.kilobytes(size),
        super(start: measurementTime,  duration: TimeVal.fromNanos(1));

  @override final UnitValue reading;

  @override UnitValue get minRange => MemoryUnits.oneKilobyte;
}

enum SeriesType {
  SEQUENTIAL_EVENTS,
  OVERLAPPING_EVENTS,
}

abstract class GraphableSeries extends Iterable<GraphableEvent> {
  String get titleName;
  SeriesType get seriesType;

  List<GraphableEvent> get frames;
  UnitValue get average;
  UnitValue get percent90;
  UnitValue get percent99;
  UnitValue get worst;
  UnitValue get largest;

  TimeVal get start => wholeRun.start;
  TimeVal get end => wholeRun.end;
  TimeVal get duration => wholeRun.duration;
  TimeFrame get wholeRun;

  UnitValue get minRange;
  UnitValue get maxValue => UnitValue.max(largest, minRange);

  int get frameCount => frames.length;

  @override
  Iterator<GraphableEvent> get iterator => frames.iterator;

  GraphableEvent? _find(TimeVal t, bool strict) {
    TimeVal loT = start;
    TimeVal hiT = end;
    if (t < loT) {
      return strict ? null : frames.first;
    }
    if (t > hiT) {
      return strict ? null : frames.last;
    }
    int lo = 0;
    int hi = frameCount - 1;
    while (lo < hi) {
      final int mid = (lo + hi) ~/ 2;
      if (mid == lo) {
        break;
      }
      final TimeVal midT = frames[mid].start;
      if (t < midT) {
        hi = mid;
        hiT = midT;
      } else if (t > midT) {
        lo = mid;
        loT = midT;
      }
    }
    final GraphableEvent loEvent = frames[lo];
    if (loEvent.contains(t)) {
      return loEvent;
    }
    if (strict) {
      return null;
    } else {
      if (lo >= frameCount) {
        return loEvent;
      }
      final GraphableEvent hiEvent = frames[lo + 1];
      return (t - loEvent.end < hiEvent.start - t) ? loEvent : hiEvent;
    }
  }

  GraphableEvent? eventAt(TimeVal t) => _find(t, true);
  GraphableEvent eventNear(TimeVal t) => _find(t, false)!;

  static final List<String> _heatNames = <String>[
    'Good',
    'Nominal',
    '90th Percentile',
    '99th Percentile'
  ];
  String labelFor(GraphableEvent t) {
    return _heatNames[heatIndex(t)];
  }

  int heatIndex(GraphableEvent t) {
    final double v = t.reading.value;
    if (t.lowIsGood) {
      return (v < average.value) ? 0
          : (v < percent90.value) ? 1
          : (v < percent99.value) ? 2
          : 3;
    } else {
      return (v <= percent99.value) ? 3
          : (v <= percent90.value) ? 2
          : (v <= average.value) ? 1
          : 0;
    }
  }

  static UnitValue computeAverage(List<GraphableEvent> list) {
    final double valueSum = list.fold<double>(0.0,
            (double previousValue, GraphableEvent element) => previousValue + element.reading.value);
    return list.first.reading.units.value(valueSum * (1.0 / list.length));
  }

  static T locatePercentile<T>(List<T> list, double percent) {
    return list[((list.length - 1) * (percent / 100)).round()];
  }
}

abstract class GraphableSeriesSource {
  List<GraphableSeries> get defaultGraphs;
  List<String> get allSeriesNames;

  GraphableSeries seriesFor(String seriesName);
}
