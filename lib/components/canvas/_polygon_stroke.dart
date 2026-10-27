import 'package:flutter/material.dart';
import 'package:saber/components/canvas/_stroke.dart';

/// A stroke made of straight edges between its points,
/// e.g. a recognized triangle or diamond.
///
/// Unlike a freehand [Stroke], it is drawn with a constant-width outline
/// (like rectangle and circle strokes) instead of
/// through perfect_freehand, which would curve and thin the edges.
class PolygonStroke extends Stroke {
  new({
    required super.color,
    required super.pressureEnabled,
    required super.options,
    required super.pageIndex,
    required super.page,
    required super.toolId,
  }) {
    options.isComplete = true;
  }

  @override
  Map<String, dynamic> toJson() => super.toJson()..['shape'] = 'polygon';

  /// Whether the last point meets the first point.
  bool get isClosed =>
      length > 2 && (keyPoints.first - keyPoints.last).distance < 1;

  /// The edges of the polygon, to be drawn with a stroke [Paint].
  Path get outlinePath => Path()..addPolygon(keyPoints, isClosed);

  /// A list of points along the polygon's edges.
  /// Each edge has 24/N points.
  @override
  List<Offset> getPolygon({required StrokeQuality quality}) {
    final pts = keyPoints;
    if (pts.length < 2) return pts;
    return [
      for (int i = 0; i < pts.length - 1; ++i)
        for (int j = 0; j < 24 / quality.N; ++j)
          Offset.lerp(pts[i], pts[i + 1], j * quality.N / 24)!,
      pts.last,
    ];
  }

  /// Returns the area enclosed by the polygon (used for hit testing).
  @override
  Path getPath(List<Offset> polygon, {bool smooth = true}) =>
      Path()..addPolygon(keyPoints, true);

  @override
  void optimisePoints({double thresholdMultiplier = 0}) {
    // no-op: every point is a vertex
  }

  @override
  String toSvgPath() {
    String toSvgPoint(Offset point) =>
        '${point.dx} ${page.size.height - point.dy}';

    final pts = keyPoints.where((offset) => offset.isFinite).map(toSvgPoint);
    if (pts.isEmpty) return '';
    return 'M${pts.join('L')}${isClosed ? 'Z' : ''}';
  }

  @override
  bool isStraightLine([int minLength = 0]) => false;

  @override
  PolygonStroke copy() => PolygonStroke(
    color: color,
    pressureEnabled: pressureEnabled,
    options: options.copyWith(),
    pageIndex: pageIndex,
    page: page,
    toolId: toolId,
  )..addPoints(keyPoints);
}
