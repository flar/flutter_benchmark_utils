// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

class TimeVal implements Comparable<TimeVal> {
  static TimeVal max(TimeVal a, TimeVal b) { return a > b ? a : b; }
  static TimeVal min(TimeVal a, TimeVal b) { return a < b ? a : b; }

  TimeVal.fromNanos(num nanos)     : this._nanos = nanos.toDouble();
  TimeVal.fromMicros(num micros)   : this._nanos = micros * 1000.0;
  TimeVal.fromMillis(num millis)   : this._nanos = millis * 1000.0 * 1000.0;
  TimeVal.fromSeconds(num seconds) : this._nanos = seconds * 1000.0 * 1000.0 * 1000.0;

  final double _nanos;

  double get seconds => millis / 1000.0;
  double get millis  => micros / 1000.0;
  double get micros  => nanos  / 1000.0;
  double get nanos   => _nanos;

  String stringSeconds([int digits = 3]) => '${seconds.toStringAsFixed(digits)}s';
  String stringMillis([int digits = 3])  => '${millis.toStringAsFixed(digits)}ms';
  String stringMicros([int digits = 3])  => '${micros.toStringAsFixed(digits)}us';
  String stringNanos([int digits = 3])   => '${nanos.toStringAsFixed(digits)}ns';

  @override int get hashCode => _nanos.hashCode;
  @override bool operator == (dynamic t) => t is TimeVal && this._nanos == t._nanos;

  bool operator <  (TimeVal t) => this._nanos < t._nanos;
  bool operator <= (TimeVal t) => this._nanos <= t._nanos;
  bool operator >= (TimeVal t) => this._nanos >= t._nanos;
  bool operator >  (TimeVal t) => this._nanos > t._nanos;

  TimeVal operator + (TimeVal t) => TimeVal.fromNanos(this._nanos + t._nanos);
  TimeVal operator - (TimeVal t) => TimeVal.fromNanos(this._nanos - t._nanos);

  double operator / (TimeVal t) => this._nanos / t._nanos;
  TimeVal operator * (double s) => TimeVal.fromNanos(this._nanos * s);

  @override
  int compareTo(TimeVal other) => _nanos.compareTo(other._nanos);

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

class TimeFrame implements Comparable<TimeFrame> {
  TimeFrame({this.start, TimeVal end, TimeVal duration})
      : assert(start != null),
        this.end = end == null ? start + duration : end,
        this.duration = duration == null ? end - start : duration,
        assert(end != null),
        assert(duration != null),
        assert(duration.nanos > 0),
        assert(start + duration == end);

  final TimeVal start;
  final TimeVal end;
  final TimeVal duration;

  TimeVal elapsedTime(double fraction) {
    if (fraction <= 0) return start;
    if (fraction <  1) return start + (duration * fraction);
    return end;
  }

  double getFraction(TimeVal t) => (t - start) / duration;
  bool contains(TimeVal t) => t >= start && t <= end;

  TimeFrame operator - (TimeFrame e) => TimeFrame(start: e.end, end: this.start);

  @override
  int compareTo(TimeFrame other) => start.compareTo(other.start);

  @override
  String toString() {
    return 'TimeFrame[$start => $end ($duration)]';
  }
}
