import 'dart:math';
import 'package:flutter/material.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:sbn/tool_id.dart';

class ShapeHandle {
  final int index;
  final Offset position;
  final String label;

  const ShapeHandle({
    required this.index,
    required this.position,
    this.label = '',
  });
}

class ShapeEditTool extends Tool {
  new _();

  static final _current = ShapeEditTool._();
  static ShapeEditTool get current => _current;

  @override
  ToolId get toolId => .shapeEdit;

  Stroke? selectedStroke;
  int? selectedPageIndex;
  int? activeHandleIndex;
  Stroke? strokeBeforeDrag;
  Offset? dragStartPosition;

  void unselect() {
    selectedStroke = null;
    selectedPageIndex = null;
    activeHandleIndex = null;
    strokeBeforeDrag = null;
    dragStartPosition = null;
  }

  /// Returns the control points (handles) for the currently selected shape.
  List<ShapeHandle> getHandles() {
    final stroke = selectedStroke;
    if (stroke == null) return const [];

    if (stroke is RectangleStroke) {
      final r = stroke.rect;
      return [
        ShapeHandle(index: 0, position: r.topLeft, label: 'TL'),
        ShapeHandle(index: 1, position: r.topRight, label: 'TR'),
        ShapeHandle(index: 2, position: r.bottomRight, label: 'BR'),
        ShapeHandle(index: 3, position: r.bottomLeft, label: 'BL'),
      ];
    } else if (stroke is CircleStroke) {
      return [
        ShapeHandle(index: 0, position: stroke.center, label: 'Center'),
        ShapeHandle(
          index: 1,
          position: stroke.center + Offset(stroke.radius, 0),
          label: 'Radius',
        ),
      ];
    } else {
      // General stroke (lines, triangles, polygons)
      final pts = stroke.keyPoints;
      if (pts.isEmpty) return const [];

      final handles = <ShapeHandle>[];
      for (int i = 0; i < pts.length; i++) {
        // Don't duplicate the closing point if it's a closed loop
        if (i > 0 && i == pts.length - 1 && (pts[i] - pts[0]).distance < 8) {
          continue;
        }
        handles.add(ShapeHandle(index: i, position: pts[i]));
      }
      return handles;
    }
  }

  /// Hit test handles. Returns handle index if hit within [threshold], or null.
  int? hitTestHandle(Offset position, {double threshold = 28.0}) {
    final handles = getHandles();
    for (final handle in handles) {
      if ((handle.position - position).distance <= threshold) {
        return handle.index;
      }
    }
    return null;
  }

  /// Update the active handle position.
  void updateHandle(int handleIndex, Offset newPos) {
    final stroke = selectedStroke;
    if (stroke == null) return;

    if (stroke is RectangleStroke) {
      final r = stroke.rect;
      Rect newRect;
      switch (handleIndex) {
        case 0: // Top-Left
          newRect = Rect.fromLTRB(
            min(newPos.dx, r.right - 10),
            min(newPos.dy, r.bottom - 10),
            r.right,
            r.bottom,
          );
        case 1: // Top-Right
          newRect = Rect.fromLTRB(
            r.left,
            min(newPos.dy, r.bottom - 10),
            max(newPos.dx, r.left + 10),
            r.bottom,
          );
        case 2: // Bottom-Right
          newRect = Rect.fromLTRB(
            r.left,
            r.top,
            max(newPos.dx, r.left + 10),
            max(newPos.dy, r.top + 10),
          );
        case 3: // Bottom-Left
          newRect = Rect.fromLTRB(
            min(newPos.dx, r.right - 10),
            r.top,
            r.right,
            max(newPos.dy, r.top + 10),
          );
        default:
          return;
      }
      stroke.rect = newRect;
      stroke.markPolygonNeedsUpdating();
    } else if (stroke is CircleStroke) {
      switch (handleIndex) {
        case 0: // Center
          stroke.center = newPos;
        case 1: // Radius
          stroke.radius = max(8.0, (newPos - stroke.center).distance);
        default:
          return;
      }
      stroke.markPolygonNeedsUpdating();
    } else {
      final pts = stroke.keyPoints;
      if (handleIndex < 0 || handleIndex >= pts.length) return;

      stroke.setPoint(handleIndex, newPos);
      if (handleIndex == 0 &&
          pts.length > 2 &&
          (pts.last - pts.first).distance < 8) {
        stroke.setPoint(pts.length - 1, newPos);
      }
      stroke.markPolygonNeedsUpdating();
    }
  }

  /// Hit test whether a position is on or inside a stroke.
  static bool hitTestStroke(
    Stroke stroke,
    Offset tapPos, {
    double tolerance = 24.0,
  }) {
    if (stroke is RectangleStroke) {
      return stroke.rect.inflate(tolerance).contains(tapPos);
    } else if (stroke is CircleStroke) {
      final dist = (tapPos - stroke.center).distance;
      return dist <= stroke.radius + tolerance;
    } else {
      final poly = stroke.lowQualityPolygon;
      if (poly.isEmpty) return false;

      for (int i = 0; i < poly.length; i++) {
        if ((poly[i] - tapPos).distance <= tolerance) return true;
        if (i < poly.length - 1) {
          if (_distanceToSegment(tapPos, poly[i], poly[i + 1]) <= tolerance) {
            return true;
          }
        }
      }
      return false;
    }
  }

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lengthSquared == 0) return (p - a).distance;

    final ap = p - a;
    final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / lengthSquared).clamp(0.0, 1.0);
    final projection = a + Offset(ab.dx * t, ab.dy * t);
    return (p - projection).distance;
  }
}
