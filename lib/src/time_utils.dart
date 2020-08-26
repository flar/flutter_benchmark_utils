// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:meta/meta.dart';

abstract class TimeValUnit {
  factory TimeValUnit.percentageOf(TimeFrame run) => _TimeValUnitPercent(run);

  factory TimeValUnit.forUnits(String units) {
    switch (units) {
      case 's':  return seconds;
      case 'ms': return millis;
      case 'us': return micros;
      case 'ns': return nanos;
      case '%':  throw 'Cannot determine percentage units for time without a TimeFrame';
    }
    throw 'Unrecognized time units: $units';
  }

  static const TimeValUnit seconds = _TimeValUnitSeconds();
  static const TimeValUnit millis  = _TimeValUnitMillis();
  static const TimeValUnit micros  = _TimeValUnitMicros();
  static const TimeValUnit nanos   = _TimeValUnitNanos();

  String get units;

  double getValue(TimeVal tv);
  String getValueString(TimeVal tv, [int digits = 3]);
}

class _TimeValUnitPercent implements TimeValUnit {
  _TimeValUnitPercent(this._run);

  final TimeFrame _run;

  @override String get units => '%';

  @override double getValue(TimeVal tv) => _run.getFraction(tv);
  @override String getValueString(TimeVal tv, [int digits = 3]) => '${getValue(tv).toStringAsFixed(digits)}%';
}

@immutable
class _TimeValUnitSeconds implements TimeValUnit {
  const _TimeValUnitSeconds();

  @override String get units => 's';

  @override double getValue(TimeVal tv) => tv.seconds;
  @override String getValueString(TimeVal tv, [int digits = 3]) => tv.stringSeconds(digits);
}

@immutable
class _TimeValUnitMillis implements TimeValUnit {
  const _TimeValUnitMillis();

  @override String get units => 'ms';

  @override double getValue(TimeVal tv) => tv.millis;
  @override String getValueString(TimeVal tv, [int digits = 3]) => tv.stringMillis(digits);
}

@immutable
class _TimeValUnitMicros implements TimeValUnit {
  const _TimeValUnitMicros();

  @override String get units => 'us';

  @override double getValue(TimeVal tv) => tv.micros;
  @override String getValueString(TimeVal tv, [int digits = 3]) => tv.stringMicros(digits);
}

@immutable
class _TimeValUnitNanos implements TimeValUnit {
  const _TimeValUnitNanos();

  @override String get units => 'ns';

  @override double getValue(TimeVal tv) => tv.nanos;
  @override String getValueString(TimeVal tv, [int digits = 3]) => tv.stringNanos(digits);
}

@immutable
class TimeVal implements Comparable<TimeVal> {
  const TimeVal._(double nanos) : _nanos = nanos;

  TimeVal.fromNanos(num nanos)     : _nanos = nanos.toDouble();
  TimeVal.fromMicros(num micros)   : _nanos = micros.toDouble() * 1000.0;
  TimeVal.fromMillis(num millis)   : _nanos = millis.toDouble() * 1000.0 * 1000.0;
  TimeVal.fromSeconds(num seconds) : _nanos = seconds.toDouble() * 1000.0 * 1000.0 * 1000.0;

  static const TimeVal zero           = TimeVal._(0.0);
  static const TimeVal oneNanosecond  = TimeVal._(1.0);
  static const TimeVal oneMicrosecond = TimeVal._(1000.0);
  static const TimeVal oneMillisecond = TimeVal._(1000.0 * 1000.0);
  static const TimeVal oneSecond      = TimeVal._(1000.0 * 1000.0 * 1000.0);

  static TimeVal max(TimeVal a, TimeVal b) { return a > b ? a : b; }
  static TimeVal min(TimeVal a, TimeVal b) { return a < b ? a : b; }

  final double _nanos;

  double get seconds => millis / 1000.0;
  double get millis  => micros / 1000.0;
  double get micros  => nanos  / 1000.0;
  double get nanos   => _nanos;

  DateTime get asDateTime => DateTime.fromMicrosecondsSinceEpoch(micros.round());

  String stringSeconds([int digits = 3]) => '${seconds.toStringAsFixed(digits)}s';
  String stringMillis([int digits = 3])  => '${millis.toStringAsFixed(digits)}ms';
  String stringMicros([int digits = 3])  => '${micros.toStringAsFixed(digits)}us';
  String stringNanos([int digits = 3])   => '${nanos.toStringAsFixed(digits)}ns';

  @override int get hashCode => _nanos.hashCode;
  @override bool operator == (dynamic other) => other is TimeVal && _nanos == other._nanos;

  bool operator <  (TimeVal t) => _nanos <  t._nanos;
  bool operator <= (TimeVal t) => _nanos <= t._nanos;
  bool operator >= (TimeVal t) => _nanos >= t._nanos;
  bool operator >  (TimeVal t) => _nanos >  t._nanos;

  bool get isNegative    => _nanos < 0;
  bool get isNonPositive => _nanos <= 0;
  bool get isZero        => _nanos == 0;
  bool get isNonNegative => _nanos >= 0;
  bool get isPositive    => _nanos > 0;

  TimeVal operator + (TimeVal t) => TimeVal._(_nanos + t._nanos);
  TimeVal operator - (TimeVal t) => TimeVal._(_nanos - t._nanos);

  double  operator / (TimeVal t) => _nanos / t._nanos;
  TimeVal operator * (double s)  => TimeVal._(_nanos * s);

  @override int compareTo(TimeVal other) => _nanos.compareTo(other._nanos);

  @override
  String toString() {
    if (_nanos < 1000) {
      return 'TimeVal[${nanos.toString()}ns]';
    } else if (_nanos < 1000 * 1000) {
      return 'TimeVal[${micros.toString()}us]';
    } else if (_nanos < 1000 * 1000 * 1000) {
      return 'TimeVal[${millis.toString()}ms]';
    } else {
      return 'TimeVal[${seconds.toString()}s]';
    }
  }
}

@immutable
class TimeFrame {
  TimeFrame({@required this.start, TimeVal end, TimeVal duration})
      : assert(start != null),
        assert((end == null) != (duration == null)),
        end = end ?? start + duration,
        duration = duration ?? end - start,
        assert(duration.isNonNegative),
        assert(start + duration == end);

  const TimeFrame._(this.start, this.end, this.duration);

  static const TimeFrame zero = TimeFrame._(TimeVal.zero, TimeVal.zero, TimeVal.zero);

  static TimeVal gapTime(TimeFrame a, TimeFrame b) {
    if (a.end <= b.start) {
      return b.start - a.end;
    } if (b.end <= a.start) {
      return a.start - b.end;
    } else {
      return TimeVal.zero;
    }
  }

  static TimeFrame gapFrame(TimeFrame a, TimeFrame b) {
    if (a.end <= b.start) {
      return TimeFrame._(a.end, b.start, b.start - a.end);
    } if (b.end <= a.start) {
      return TimeFrame._(b.end, a.start, a.start - b.end);
    } else {
      return TimeFrame.zero;
    }
  }

  final TimeVal start;
  final TimeVal end;
  final TimeVal duration;

  TimeVal elapsedTime(double fraction) {
    if (fraction <= 0) {
      return start;
    }
    if (fraction <  1) {
      return start + (duration * fraction);
    }
    return end;
  }

  double getFraction(TimeVal t) => (t - start) / duration;

  bool contains(TimeVal t) => t >= start && t < end;

  TimeVal gapTimeUntil(TimeFrame f) => f.gapTimeSince(this);
  TimeVal gapTimeSince(TimeFrame f) => f.end < start
      ? f.end - start
      : TimeVal.zero;

  TimeFrame gapFrameUntil(TimeFrame f) => f.gapFrameSince(this);
  TimeFrame gapFrameSince(TimeFrame f) => f.end < start
      ? TimeFrame(start: f.end, end: start)
      : TimeFrame.zero;

  TimeFrame operator - (TimeVal t) => TimeFrame._(start - t, end - t, duration);

  static int startOrder   (TimeFrame a, TimeFrame b) => a.start   .compareTo(b.start);
  static int endOrder     (TimeFrame a, TimeFrame b) => a.end     .compareTo(b.end);
  static int durationOrder(TimeFrame a, TimeFrame b) => a.duration.compareTo(b.duration);

  static int reverseStartOrder   (TimeFrame a, TimeFrame b) => b.start   .compareTo(a.start);
  static int reverseEndOrder     (TimeFrame a, TimeFrame b) => b.end     .compareTo(a.end);
  static int reverseDurationOrder(TimeFrame a, TimeFrame b) => b.duration.compareTo(a.duration);

  @override int get hashCode => (start.hashCode + 17) * 23 + end.hashCode;
  @override bool operator == (dynamic other) =>
      other is TimeFrame && start == other.start && end == other.end;

  @override
  String toString() {
    return 'TimeFrame[$start => $end ($duration)]';
  }
}
