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

class TableInfo {
  final RectangleStroke outerRect;
  final List<Stroke> horizontalDividers;
  final List<Stroke> verticalDividers;

  TableInfo({
    required this.outerRect,
    required this.horizontalDividers,
    required this.verticalDividers,
  });

  List<Stroke> get allStrokes => [
    outerRect,
    ...horizontalDividers,
    ...verticalDividers,
  ];

  List<Stroke> copyStrokes() =>
      allStrokes.map((s) => s.copy()).toList();
}

class ShapeEditTool extends Tool {
  new _();

  static final _current = ShapeEditTool._();
  static ShapeEditTool get current => _current;

  @override
  ToolId get toolId => .shapeEdit;

  Stroke? selectedStroke;
  TableInfo? selectedTable;
  List<Stroke>? tableStrokesBeforeDrag;
  int? selectedPageIndex;
  int? activeHandleIndex;
  Stroke? strokeBeforeDrag;
  Offset? dragStartPosition;

  void unselect() {
    selectedStroke = null;
    selectedTable = null;
    tableStrokesBeforeDrag = null;
    selectedPageIndex = null;
    activeHandleIndex = null;
    strokeBeforeDrag = null;
    dragStartPosition = null;
  }

  /// Sets selection to [stroke], detecting if it is part of a table on [pageStrokes].
  void select(Stroke stroke, int pageIndex, List<Stroke> pageStrokes) {
    final table = findTableForStroke(stroke, pageStrokes);
    selectedPageIndex = pageIndex;
    if (table != null) {
      selectedTable = table;
      selectedStroke = table.outerRect;
    } else {
      selectedTable = null;
      selectedStroke = stroke;
    }
  }

  /// Returns the control points (handles) for the currently selected shape.
  List<ShapeHandle> getHandles() {
    if (selectedTable != null) {
      final r = selectedTable!.outerRect.rect;
      final handles = <ShapeHandle>[
        ShapeHandle(index: 0, position: r.topLeft, label: 'TL'),
        ShapeHandle(index: 1, position: r.topRight, label: 'TR'),
        ShapeHandle(index: 2, position: r.bottomRight, label: 'BR'),
        ShapeHandle(index: 3, position: r.bottomLeft, label: 'BL'),
      ];

      for (int i = 0; i < selectedTable!.horizontalDividers.length; i++) {
        final divider = selectedTable!.horizontalDividers[i];
        final pts = divider.keyPoints;
        if (pts.isNotEmpty) {
          handles.add(
            ShapeHandle(
              index: 100 + i,
              position: Offset(r.center.dx, pts.first.dy),
              label: 'H-Divider',
            ),
          );
        }
      }

      for (int j = 0; j < selectedTable!.verticalDividers.length; j++) {
        final divider = selectedTable!.verticalDividers[j];
        final pts = divider.keyPoints;
        if (pts.isNotEmpty) {
          handles.add(
            ShapeHandle(
              index: 200 + j,
              position: Offset(pts.first.dx, r.center.dy),
              label: 'V-Divider',
            ),
          );
        }
      }

      return handles;
    }

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
    if (selectedTable != null) {
      final table = selectedTable!;
      final r = table.outerRect.rect;

      if (handleIndex < 100) {
        // Outer rectangle corner resize
        Rect newRect;
        switch (handleIndex) {
          case 0: // Top-Left
            newRect = Rect.fromLTRB(
              min(newPos.dx, r.right - 20),
              min(newPos.dy, r.bottom - 20),
              r.right,
              r.bottom,
            );
          case 1: // Top-Right
            newRect = Rect.fromLTRB(
              r.left,
              min(newPos.dy, r.bottom - 20),
              max(newPos.dx, r.left + 20),
              r.bottom,
            );
          case 2: // Bottom-Right
            newRect = Rect.fromLTRB(
              r.left,
              r.top,
              max(newPos.dx, r.left + 20),
              max(newPos.dy, r.top + 20),
            );
          case 3: // Bottom-Left
            newRect = Rect.fromLTRB(
              min(newPos.dx, r.right - 20),
              r.top,
              r.right,
              max(newPos.dy, r.top + 20),
            );
          default:
            return;
        }

        final oldH = r.height > 0 ? r.height : 1.0;
        final oldW = r.width > 0 ? r.width : 1.0;

        table.outerRect.rect = newRect;
        table.outerRect.markPolygonNeedsUpdating();

        // Scale horizontal dividers and strictly clamp within newRect bounds
        for (final hDiv in table.horizontalDividers) {
          final oldY = hDiv.keyPoints.isNotEmpty
              ? hDiv.keyPoints.first.dy
              : r.center.dy;
          final t = ((oldY - r.top) / oldH).clamp(0.05, 0.95);
          final newY = (newRect.top + t * newRect.height).clamp(
            newRect.top + 4,
            newRect.bottom - 4,
          );
          hDiv.setPoints([
            Offset(newRect.left, newY),
            Offset(newRect.right, newY),
          ]);
        }

        // Scale vertical dividers and strictly clamp within newRect bounds
        for (final vDiv in table.verticalDividers) {
          final oldX = vDiv.keyPoints.isNotEmpty
              ? vDiv.keyPoints.first.dx
              : r.center.dx;
          final t = ((oldX - r.left) / oldW).clamp(0.05, 0.95);
          final newX = (newRect.left + t * newRect.width).clamp(
            newRect.left + 4,
            newRect.right - 4,
          );
          vDiv.setPoints([
            Offset(newX, newRect.top),
            Offset(newX, newRect.bottom),
          ]);
        }
        return;
      } else if (handleIndex >= 100 && handleIndex < 200) {
        // Adjust individual horizontal divider
        final i = handleIndex - 100;
        if (i >= 0 && i < table.horizontalDividers.length) {
          final hDiv = table.horizontalDividers[i];
          final newY = newPos.dy.clamp(r.top + 6, r.bottom - 6);
          hDiv.setPoints([
            Offset(r.left, newY),
            Offset(r.right, newY),
          ]);
        }
        return;
      } else if (handleIndex >= 200) {
        // Adjust individual vertical divider
        final j = handleIndex - 200;
        if (j >= 0 && j < table.verticalDividers.length) {
          final vDiv = table.verticalDividers[j];
          final newX = newPos.dx.clamp(r.left + 6, r.right - 6);
          vDiv.setPoints([
            Offset(newX, r.top),
            Offset(newX, r.bottom),
          ]);
        }
        return;
      }
    }

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

  /// Finds table components if [stroke] is part of a table on [pageStrokes].
  static TableInfo? findTableForStroke(
    Stroke stroke,
    List<Stroke> pageStrokes,
  ) {
    RectangleStroke? outerRect;

    if (stroke is RectangleStroke) {
      outerRect = stroke;
    } else {
      final pts = stroke.keyPoints;
      if (pts.length >= 2) {
        for (final s in pageStrokes) {
          if (s is RectangleStroke) {
            final r = s.rect.inflate(12);
            if (r.contains(pts.first) && r.contains(pts.last)) {
              outerRect = s;
              break;
            }
          }
        }
      }
    }

    if (outerRect == null) return null;

    final r = outerRect.rect;
    final hDividers = <Stroke>[];
    final vDividers = <Stroke>[];

    for (final s in pageStrokes) {
      if (s == outerRect) continue;
      final pts = s.keyPoints;
      if (pts.length < 2) continue;

      final p1 = pts.first;
      final p2 = pts.last;

      final isHorizontal = (p1.dy - p2.dy).abs() < 10 &&
          min(p1.dx, p2.dx) <= r.left + 20 &&
          max(p1.dx, p2.dx) >= r.right - 20 &&
          p1.dy >= r.top - 6 &&
          p1.dy <= r.bottom + 6;

      if (isHorizontal) {
        hDividers.add(s);
        continue;
      }

      final isVertical = (p1.dx - p2.dx).abs() < 10 &&
          min(p1.dy, p2.dy) <= r.top + 20 &&
          max(p1.dy, p2.dy) >= r.bottom - 20 &&
          p1.dx >= r.left - 6 &&
          p1.dx <= r.right + 6;

      if (isVertical) {
        vDividers.add(s);
        continue;
      }
    }

    if (hDividers.isEmpty && vDividers.isEmpty) return null;

    return TableInfo(
      outerRect: outerRect,
      horizontalDividers: hDividers,
      verticalDividers: vDividers,
    );
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
