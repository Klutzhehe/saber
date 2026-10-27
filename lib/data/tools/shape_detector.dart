import 'dart:math';
import 'package:flutter/material.dart';
import 'package:one_dollar_unistroke_recognizer/one_dollar_unistroke_recognizer.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_polygon_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';

class ShapeDetector {
  new _();

  /// Converts [stroke] into a clean shape (circle, rectangle, triangle,
  /// diamond or other quadrilateral), or returns null if no shape is found.
  ///
  /// [minScore] is the minimum $1 recognizer score for circles and
  /// rectangles that aren't found by geometric analysis.
  /// If [includeLinesAndStars] is true, lines and stars are also recognized.
  static Stroke? recognize(
    Stroke stroke, {
    double minScore = 0.65,
    bool includeLinesAndStars = false,
  }) {
    // Polygons first: corner analysis handles rotated shapes (e.g. diamonds)
    // which the $1 recognizer would turn into an axis-aligned rectangle.
    final geom = analyzeClosedStroke(stroke.points);
    if (geom != null) {
      final (name, vertices) = geom;
      if (name == 'rectangle' && _isAxisAligned(vertices)) {
        return RectangleStroke(
          color: stroke.color,
          pressureEnabled: stroke.pressureEnabled,
          options: stroke.options.copyWith(isComplete: true),
          pageIndex: stroke.pageIndex,
          page: stroke.page,
          toolId: stroke.toolId,
          rect: _boundingRect(vertices),
        );
      }
      return polygonStroke(stroke, vertices);
    }

    final detected = stroke.detectShape();
    if (detected == null || detected.score < minScore) return null;
    switch (detected.name) {
      case DefaultUnistrokeNames.circle:
        final (center, radius) = detected.convertToCircle();
        return CircleStroke(
          color: stroke.color,
          pressureEnabled: stroke.pressureEnabled,
          options: stroke.options.copyWith(isComplete: true),
          pageIndex: stroke.pageIndex,
          page: stroke.page,
          toolId: stroke.toolId,
          radius: radius,
          center: center,
        );
      case DefaultUnistrokeNames.rectangle:
        return RectangleStroke(
          color: stroke.color,
          pressureEnabled: stroke.pressureEnabled,
          options: stroke.options.copyWith(isComplete: true),
          pageIndex: stroke.pageIndex,
          page: stroke.page,
          toolId: stroke.toolId,
          rect: detected.convertToRect(),
        );
      case DefaultUnistrokeNames.triangle:
        return polygonStroke(stroke, detected.convertToCanonicalPolygon());
      case DefaultUnistrokeNames.star:
        if (!includeLinesAndStars) return null;
        return polygonStroke(stroke, detected.convertToCanonicalPolygon());
      case DefaultUnistrokeNames.line:
        if (!includeLinesAndStars) return null;
        return stroke.copy()..convertToLine();
      case null:
        return null;
    }
  }

  /// Builds a polygon stroke whose edges render as solid, constant-width lines.
  static PolygonStroke polygonStroke(Stroke source, List<Offset> vertices) {
    return PolygonStroke(
      color: source.color,
      pressureEnabled: false,
      options: StrokeOptions(
        size: source.options.size,
        isComplete: true,
        smoothing: 0,
        streamline: 0,
      ),
      pageIndex: source.pageIndex,
      page: source.page,
      toolId: source.toolId,
    )..addPoints(vertices);
  }

  /// Analyzes a closed stroke to detect whether it is a triangle or
  /// quadrilateral based on geometric corner and polygon simplification.
  ///
  /// Returns `(shapeName, closedVertices)` or `null` if not a recognized polygon.
  static (String shapeName, List<Offset> vertices)? analyzeClosedStroke(
    List<PointVector> points,
  ) {
    if (points.length < 6) return null;

    final first = Offset(points.first.x, points.first.y);
    final last = Offset(points.last.x, points.last.y);

    double minX = points[0].x, maxX = points[0].x;
    double minY = points[0].y, maxY = points[0].y;
    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
    final width = maxX - minX;
    final height = maxY - minY;
    final diagonal = sqrt(width * width + height * height);

    if (diagonal < 20) return null;

    final gap = (first - last).distance;
    final isClosed = gap < diagonal * 0.4 || gap < 50.0;
    if (!isClosed) return null;

    final offsets = points.map((p) => Offset(p.x, p.y)).toList();
    if (gap > 2) offsets.add(first);

    // Test adaptive epsilons for Ramer-Douglas-Peucker simplification
    for (final factor in [0.08, 0.065, 0.095, 0.05, 0.11]) {
      final epsilon = diagonal * factor;
      final simplified = _rdpSimplify(offsets, epsilon);
      if (simplified.length < 4) continue;

      // Drop duplicate closing point
      final vertices = simplified.sublist(0, simplified.length - 1);
      if (vertices.length != 3 && vertices.length != 4) continue;

      // Reject curvy strokes (e.g. circles) that only simplify to a polygon
      // at a coarse epsilon: the stroke must hug the polygon's edges.
      if (_averageDistanceToPolygon(offsets, vertices) > diagonal * 0.04) {
        continue;
      }

      final v = _snapVertices(vertices);
      return (v.length == 3 ? 'triangle' : 'rectangle', [...v, v.first]);
    }

    return null;
  }

  static List<Offset> _rdpSimplify(List<Offset> pts, double epsilon) {
    if (pts.length < 3) return pts;

    double maxDist = 0;
    int index = 0;
    for (int i = 1; i < pts.length - 1; i++) {
      final d = _perpendicularDistance(pts[i], pts.first, pts.last);
      if (d > maxDist) {
        maxDist = d;
        index = i;
      }
    }

    if (maxDist > epsilon) {
      final left = _rdpSimplify(pts.sublist(0, index + 1), epsilon);
      final right = _rdpSimplify(pts.sublist(index), epsilon);
      return [...left.sublist(0, left.length - 1), ...right];
    } else {
      return [pts.first, pts.last];
    }
  }

  static double _perpendicularDistance(
    Offset pt,
    Offset lineStart,
    Offset lineEnd,
  ) {
    final dx = lineEnd.dx - lineStart.dx;
    final dy = lineEnd.dy - lineStart.dy;
    final lenSq = dx * dx + dy * dy;
    if (lenSq == 0) return (pt - lineStart).distance;
    final t =
        ((pt.dx - lineStart.dx) * dx + (pt.dy - lineStart.dy) * dy) / lenSq;
    final proj = Offset(lineStart.dx + t * dx, lineStart.dy + t * dy);
    return (pt - proj).distance;
  }

  static double _segmentDistance(Offset pt, Offset a, Offset b) {
    final ab = b - a;
    final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lenSq == 0) return (pt - a).distance;
    final t = (((pt.dx - a.dx) * ab.dx + (pt.dy - a.dy) * ab.dy) / lenSq)
        .clamp(0.0, 1.0)
        .toDouble();
    return (pt - (a + ab * t)).distance;
  }

  static double _averageDistanceToPolygon(
    List<Offset> pts,
    List<Offset> vertices,
  ) {
    double total = 0;
    for (final pt in pts) {
      double best = double.infinity;
      for (int i = 0; i < vertices.length; i++) {
        final d = _segmentDistance(
          pt,
          vertices[i],
          vertices[(i + 1) % vertices.length],
        );
        if (d < best) best = d;
      }
      total += best;
    }
    return total / pts.length;
  }

  /// Aligns vertices whose x or y coordinates are nearly equal,
  /// e.g. so a triangle's base is horizontal or a diamond is symmetric.
  static List<Offset> _snapVertices(List<Offset> v) {
    final res = List<Offset>.from(v);
    for (int i = 0; i < res.length; i++) {
      for (int j = i + 1; j < res.length; j++) {
        final p1 = res[i];
        final p2 = res[j];
        if ((p1.dy - p2.dy).abs() < 12) {
          final avgY = (p1.dy + p2.dy) / 2;
          res[i] = Offset(res[i].dx, avgY);
          res[j] = Offset(res[j].dx, avgY);
        }
        if ((p1.dx - p2.dx).abs() < 12) {
          final avgX = (p1.dx + p2.dx) / 2;
          res[i] = Offset(avgX, res[i].dy);
          res[j] = Offset(avgX, res[j].dy);
        }
      }
    }
    return res;
  }

  /// Whether every edge of the closed polygon [vertices]
  /// is close to horizontal or vertical.
  static bool _isAxisAligned(List<Offset> vertices) {
    const tolerance = 12 * pi / 180;
    for (int i = 0; i < vertices.length - 1; i++) {
      final d = vertices[i + 1] - vertices[i];
      final angle = atan2(d.dy.abs(), d.dx.abs());
      if (angle > tolerance && angle < pi / 2 - tolerance) return false;
    }
    return true;
  }

  static Rect _boundingRect(List<Offset> vertices) {
    var rect = Rect.fromPoints(vertices.first, vertices.first);
    for (final v in vertices) {
      rect = rect.expandToInclude(Rect.fromPoints(v, v));
    }
    return rect;
  }
}
