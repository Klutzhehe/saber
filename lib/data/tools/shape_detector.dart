import 'dart:math';
import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart';

class ShapeDetector {
  new _();

  /// Analyzes a closed stroke to detect whether it is a triangle or rectangle
  /// based on geometric corner and polygon simplification.
  ///
  /// Returns `(shapeName, canonicalVertices)` or `null` if not a recognized polygon.
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

      if (vertices.length == 3) {
        // Triangle with 3 corners!
        final v = _snapTriangleVertices(vertices);
        return ('triangle', [v[0], v[1], v[2], v[0]]);
      } else if (vertices.length == 4) {
        // Quadrilateral with 4 corners!
        return ('rectangle', [
          vertices[0],
          vertices[1],
          vertices[2],
          vertices[3],
          vertices[0],
        ]);
      }
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

  static List<Offset> _snapTriangleVertices(List<Offset> v) {
    final res = List<Offset>.from(v);
    for (int i = 0; i < 3; i++) {
      final next = (i + 1) % 3;
      final p1 = res[i];
      final p2 = res[next];
      // Snap nearly horizontal edge
      if ((p1.dy - p2.dy).abs() < 12) {
        final avgY = (p1.dy + p2.dy) / 2;
        res[i] = Offset(p1.dx, avgY);
        res[next] = Offset(p2.dx, avgY);
      }
      // Snap nearly vertical edge
      if ((p1.dx - p2.dx).abs() < 12) {
        final avgX = (p1.dx + p2.dx) / 2;
        res[i] = Offset(avgX, p1.dy);
        res[next] = Offset(avgX, p2.dy);
      }
    }
    return res;
  }
}
