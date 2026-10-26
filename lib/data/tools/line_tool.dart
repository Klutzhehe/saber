import 'dart:math';
import 'package:flutter/material.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:sbn/tool_id.dart';

class LineTool extends Tool {
  new _();

  static final _current = LineTool._();
  static LineTool get current => _current;

  @override
  ToolId get toolId => .line;

  Color color = Colors.black;
  double strokeWidth = 2.5;

  int? activePageIndex;
  final List<Offset> committedPoints = [];
  Offset? currentPointer;
  Offset? snapTarget;
  DateTime? lastTapTime;

  bool get isActive => committedPoints.isNotEmpty;

  void reset() {
    activePageIndex = null;
    committedPoints.clear();
    currentPointer = null;
    snapTarget = null;
    lastTapTime = null;
  }

  /// Finds the best snap point for [position] considering existing shapes on the page
  /// and the polyline's own starting point.
  Offset snapPoint(
    Offset position,
    List<Stroke> existingStrokes, {
    double threshold = 20.0,
  }) {
    snapTarget = null;

    // 1. Check snap to starting point (to close a polygon)
    if (committedPoints.length >= 2) {
      final startDist = (position - committedPoints.first).distance;
      if (startDist <= threshold * 1.5) {
        snapTarget = committedPoints.first;
        return committedPoints.first;
      }
    }

    // 2. Check snap to existing shape key points on the page
    Offset? closestPoint;
    double closestDist = threshold;

    for (final stroke in existingStrokes) {
      for (final pt in stroke.keyPoints) {
        final d = (position - pt).distance;
        if (d < closestDist) {
          closestDist = d;
          closestPoint = pt;
        }
      }
      if (stroke is CircleStroke) {
        final cardinals = [
          stroke.center + Offset(0, -stroke.radius),
          stroke.center + Offset(stroke.radius, 0),
          stroke.center + Offset(0, stroke.radius),
          stroke.center + Offset(-stroke.radius, 0),
        ];
        for (final pt in cardinals) {
          final d = (position - pt).distance;
          if (d < closestDist) {
            closestDist = d;
            closestPoint = pt;
          }
        }
      }
    }

    if (closestPoint != null) {
      snapTarget = closestPoint;
      return closestPoint;
    }

    // 3. Check angle snap relative to the last committed point (0°, 45°, 90°, etc.)
    if (committedPoints.isNotEmpty) {
      final last = committedPoints.last;
      final dx = position.dx - last.dx;
      final dy = position.dy - last.dy;
      final dist = sqrt(dx * dx + dy * dy);

      if (dist > 15) {
        // Horizontal snap
        if (dy.abs() < threshold) {
          final snapped = Offset(position.dx, last.dy);
          snapTarget = snapped;
          return snapped;
        }
        // Vertical snap
        if (dx.abs() < threshold) {
          final snapped = Offset(last.dx, position.dy);
          snapTarget = snapped;
          return snapped;
        }
        // 45 degree diagonal snap
        final diff = (dx.abs() - dy.abs()).abs();
        if (diff < threshold) {
          final avg = (dx.abs() + dy.abs()) / 2;
          final snapped = Offset(
            last.dx + (dx >= 0 ? avg : -avg),
            last.dy + (dy >= 0 ? avg : -avg),
          );
          snapTarget = snapped;
          return snapped;
        }
      }
    }

    return position;
  }
}
