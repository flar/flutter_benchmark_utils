// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class ForcedPanDetector extends StatelessWidget {
  const ForcedPanDetector({
    required this.child,
    required this.onPanDown,
    required this.onPanUpdate,
    this.onPanEnd,
    this.onDoubleTap,
    this.onTap,
  });

  final Widget child;
  final bool Function(Offset) onPanDown;
  final Function(Offset) onPanUpdate;
  final Function(Offset)? onPanEnd;
  final Function? onDoubleTap;
  final Function? onTap;

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      gestures: <Type,GestureRecognizerFactory>{
        CustomPanGestureRecognizer: GestureRecognizerFactoryWithHandlers<CustomPanGestureRecognizer>(
          () => CustomPanGestureRecognizer(),
          (CustomPanGestureRecognizer instance) { instance._detector = this; },
        ),
      },
      child: child,
    );
  }
}

class CustomPanGestureRecognizer extends OneSequenceGestureRecognizer {
  CustomPanGestureRecognizer();

  late ForcedPanDetector _detector;
  Duration? _tapTimestamp;

  bool _isTap(Duration timestamp) =>
      _tapTimestamp != null &&
          timestamp - _tapTimestamp! < kDoubleTapTimeout * 0.5;

  bool _isDoubleTap(Duration timestamp) =>
      _tapTimestamp != null &&
          timestamp - _tapTimestamp! < kDoubleTapTimeout;

  @override
  void addPointer(PointerDownEvent event) {
    if (_detector.onPanDown(event.position)) {
      final Function? onDoubleTap = _detector.onDoubleTap;
      if (onDoubleTap != null && _isDoubleTap(event.timeStamp)) {
        onDoubleTap();
        _tapTimestamp = null;
        stopTrackingPointer(event.pointer);
      } else {
        _tapTimestamp = event.timeStamp;
        startTrackingPointer(event.pointer);
        resolve(GestureDisposition.accepted);
      }
    } else {
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      _detector.onPanUpdate(event.position);
    } else if (event is PointerUpEvent) {
      if (_detector.onPanEnd != null) {
        _detector.onPanEnd!(event.position);
      }
      final Function? onTap = _detector.onTap;
      if (onTap != null && _isTap(event.timeStamp)) {
        onTap();
      }
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'CustomPanRecognizer';
}

class InputManager extends StatelessWidget {
  const InputManager({
    required this.child,
    this.mouseKey,
    this.scaleTo,
    this.focusNode,
    this.onPanDown,
    this.onPanUpdate,
    this.onPanEnd,
    this.onTap,
    this.onDoubleTap,
    this.onEnter,
    this.onHover,
    this.onExit,
  })
      : assert((onPanDown == null) == (onPanUpdate == null)),
        assert(onPanDown != null || (onPanEnd == null && onTap == null && onDoubleTap == null));

  final GlobalKey? mouseKey;
  final Widget child;
  final Rect? scaleTo;

  final FocusNode? focusNode;
  bool get _needsKeyboardListener => focusNode != null;

  final bool Function(Offset)? onPanDown;
  final Function(Offset)? onPanUpdate;
  final Function(Offset)? onPanEnd;
  final Function? onTap;
  final Function? onDoubleTap;
  bool get _needsPanDetector =>
      onPanDown != null || onPanUpdate != null || onPanEnd != null || onTap != null || onDoubleTap != null;

  bool Function(Offset offset)? get _onPanDown => (onPanDown == null)
      ? null
      : (Offset offset) => onPanDown!(_getOffset(offset));

  void Function(Offset offset)? get _onPanUpdate => (onPanUpdate == null)
      ? null
      : (Offset offset) => onPanUpdate!(_getOffset(offset));

  void Function(Offset offset)? get _onPanEnd => (onPanEnd == null)
      ? null
      : (Offset offset) => onPanEnd!(_getOffset(offset));

  final Function(Offset)? onEnter;
  final Function(Offset)? onHover;
  final Function(Offset)? onExit;
  bool get _needsMouseRegion =>
      focusNode != null || onEnter != null || onHover != null || onExit != null;

  Offset _getOffset(Offset position) {
    final GlobalKey key = mouseKey ?? child.key as GlobalKey;
    final RenderBox? box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box != null) {
      position = box.globalToLocal(position);
      if (scaleTo != null) {
        position = Offset(
          scaleTo!.left + position.dx * scaleTo!.width  / box.size.width,
          scaleTo!.top  + position.dy * scaleTo!.height / box.size.height,
        );
      }
    }
    return position;
  }

  void Function(PointerEnterEvent event)? get _onEnter => (focusNode == null && onEnter == null)
      ? null
      : (PointerEnterEvent event) {
    if (focusNode != null) {
      focusNode!.requestFocus();
    }
    if (onEnter != null) {
      onEnter!(_getOffset(event.position));
    }
  };

  void Function(PointerHoverEvent event)? get _onHover => (onHover == null)
      ? null
      : (PointerHoverEvent event) => onHover!(_getOffset(event.position));

  void Function(PointerExitEvent event)? get _onExit => (focusNode == null && onExit == null)
      ? null
      : (PointerExitEvent event) {
    if (focusNode != null) {
      focusNode!.unfocus();
    }
    if (onExit != null) {
      onExit!(_getOffset(event.position));
    }
  };

  @override
  Widget build(BuildContext context) {
    Widget widget = child;
    if (_needsPanDetector || _needsMouseRegion) {
      widget = Container(key: mouseKey, child: child);
      if (_needsPanDetector) {
        widget = ForcedPanDetector(
          child: widget,
          onPanDown:   _onPanDown!,
          onPanUpdate: _onPanUpdate!,
          onPanEnd:    _onPanEnd,
          onTap:       onTap,
          onDoubleTap: onDoubleTap,
        );
      }
      if (_needsKeyboardListener) {
        widget = RawKeyboardListener(
          child: widget,
          focusNode: focusNode!,
        );
      }
      if (_needsMouseRegion) {
        widget = MouseRegion(
          child: widget,
          onEnter: _onEnter,
          onHover: _onHover,
          onExit:  _onExit,
        );
      }
    }
    return widget;
  }
}
