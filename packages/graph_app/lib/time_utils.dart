// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

class TimeVal implements Comparable<TimeVal> {
  static const TimeVal zero           = TimeVal._(0.0);
  static const TimeVal oneNanosecond  = TimeVal._(1.0);
  static const TimeVal oneMicrosecond = TimeVal._(1000.0);
  static const TimeVal oneMillisecond = TimeVal._(1000.0 * 1000.0);
  static const TimeVal oneSecond      = TimeVal._(1000.0 * 1000.0 * 1000.0);

  static TimeVal max(TimeVal a, TimeVal b) { return a > b ? a : b; }
  static TimeVal min(TimeVal a, TimeVal b) { return a < b ? a : b; }

  const TimeVal._(double nanos) : this._nanos = nanos;

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

  bool operator <  (TimeVal t) => this._nanos <  t._nanos;
  bool operator <= (TimeVal t) => this._nanos <= t._nanos;
  bool operator >= (TimeVal t) => this._nanos >= t._nanos;
  bool operator >  (TimeVal t) => this._nanos >  t._nanos;

  bool get isNegative    => this._nanos < 0;
  bool get isNonPositive => this._nanos <= 0;
  bool get isZero        => this._nanos == 0;
  bool get isNonNegative => this._nanos >= 0;
  bool get isPositive    => this._nanos > 0;

  TimeVal operator + (TimeVal t) => TimeVal._(this._nanos + t._nanos);
  TimeVal operator - (TimeVal t) => TimeVal._(this._nanos - t._nanos);

  double  operator / (TimeVal t) => this._nanos / t._nanos;
  TimeVal operator * (double s)  => TimeVal._(this._nanos * s);

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

class TimeFrame {
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

  const TimeFrame._(this.start, this.end, this.duration);

  TimeFrame({this.start, TimeVal end, TimeVal duration})
      : assert(start != null),
        assert((end == null) != (duration == null)),
        this.end = end == null ? start + duration : end,
        this.duration = duration == null ? end - start : duration,
        assert(duration.isNonNegative),
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

  bool contains(TimeVal t) => t >= start && t < end;

  TimeVal gapTimeUntil(TimeFrame f) => f.gapTimeSince(this);
  TimeVal gapTimeSince(TimeFrame f) => f.end < this.start
      ? f.end - this.start
      : TimeVal.zero;

  TimeFrame gapFrameUntil(TimeFrame f) => f.gapFrameSince(this);
  TimeFrame gapFrameSince(TimeFrame f) => f.end < this.start
      ? TimeFrame(start: f.end, end: this.start)
      : TimeFrame.zero;

  static int startOrder   (TimeFrame a, TimeFrame b) => a.start   .compareTo(b.start);
  static int endOrder     (TimeFrame a, TimeFrame b) => a.end     .compareTo(b.end);
  static int durationOrder(TimeFrame a, TimeFrame b) => a.duration.compareTo(b.duration);

  static int reverseStartOrder   (TimeFrame a, TimeFrame b) => b.start   .compareTo(a.start);
  static int reverseEndOrder     (TimeFrame a, TimeFrame b) => b.end     .compareTo(a.end);
  static int reverseDurationOrder(TimeFrame a, TimeFrame b) => b.duration.compareTo(a.duration);

  @override int get hashCode => (start.hashCode + 17) * 23 + end.hashCode;
  @override bool operator == (dynamic t) => t is TimeFrame && this.start == t.start && this.end == t.end;

  @override
  String toString() {
    return 'TimeFrame[$start => $end ($duration)]';
  }
}
