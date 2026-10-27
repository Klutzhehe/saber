import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:one_dollar_unistroke_recognizer/one_dollar_unistroke_recognizer.dart';
import 'package:path_drawing/path_drawing.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_polygon_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/extensions/color_extensions.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/laser_pointer.dart';
import 'package:saber/data/tools/line_tool.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/data/tools/shape_edit.dart';
import 'package:saber/data/tools/shape_pen.dart';

class CanvasPainter extends CustomPainter {
  const new({
    super.repaint,
    this.invert = false,
    required this.strokes,
    required this.laserStrokes,
    required this.currentStroke,
    required this.currentSelection,
    required this.primaryColor,
    required this.page,
    required this.showPageIndicator,
    required this.pageIndex,
    required this.totalPages,
    required this.currentScale,
    required this.defaultTextStyle,
  });

  final bool invert;
  final List<Stroke> strokes;
  final List<LaserStroke> laserStrokes;
  final Stroke? currentStroke;
  final SelectResult? currentSelection;
  final Color primaryColor;
  final EditorPage page;
  final bool showPageIndicator;
  final int pageIndex;
  final int totalPages;
  final double currentScale;
  final TextStyle defaultTextStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final canvasRect = Offset.zero & size;

    _drawHighlighterStrokes(canvas, canvasRect);
    _drawNonHighlighterStrokes(canvas);
    for (final stroke in laserStrokes) _drawLaserStroke(canvas, stroke);
    _drawCurrentStroke(canvas);
    _drawDetectedShape(canvas);
    _drawSelection(canvas);
    _drawShapeEditHandles(canvas);
    _drawLineToolPreview(canvas);
    _drawPageIndicator(canvas, size);
  }

  @override
  bool shouldRepaint(CanvasPainter oldDelegate) {
    return false ||
        // Current stroke is being drawn, so always repaint if present
        (currentStroke != null || oldDelegate.currentStroke != null) ||
        // Laser strokes are always fading out, so always repaint if present
        (laserStrokes.isNotEmpty || oldDelegate.laserStrokes.isNotEmpty) ||
        // Check for any other changes
        invert != oldDelegate.invert ||
        strokes.length != oldDelegate.strokes.length ||
        currentSelection != oldDelegate.currentSelection ||
        primaryColor != oldDelegate.primaryColor ||
        page != oldDelegate.page ||
        showPageIndicator != oldDelegate.showPageIndicator ||
        pageIndex != oldDelegate.pageIndex ||
        totalPages != oldDelegate.totalPages ||
        currentScale != oldDelegate.currentScale;
  }

  void _drawHighlighterStrokes(Canvas canvas, Rect canvasRect) {
    final layerPaint = Paint()
      ..blendMode = invert ? BlendMode.lighten : BlendMode.darken
      ..color = Colors.white.withAlpha(Highlighter.alpha);
    bool needToRestoreCanvasLayer = false;

    Color? lastColor;
    for (final stroke in strokes) {
      if (stroke.toolId != .highlighter) continue;

      final color = stroke.color.withValues(alpha: 1).withInversion(invert);

      if (color != lastColor) {
        // new layer for each color
        if (needToRestoreCanvasLayer) canvas.restore();
        canvas.saveLayer(canvasRect, layerPaint);

        needToRestoreCanvasLayer = true;
        lastColor = color;
      }

      canvas.drawPath(_selectPath(stroke), Paint()..color = color);
    }

    if (needToRestoreCanvasLayer) canvas.restore();
  }

  void _drawNonHighlighterStrokes(Canvas canvas) {
    late final paint = Paint();

    for (final stroke in strokes) {
      if (stroke.toolId == .highlighter) continue;

      var color = stroke.color.withInversion(invert);
      if (currentSelection?.strokes.contains(stroke) ?? false) {
        color = Color.lerp(color, primaryColor, 0.5)!;
      }

      paint.color = color;
      paint.shader = null;
      paint.maskFilter = null;
      if (stroke.toolId == .pencil) {
        if (shouldUsePencilShader(stroke.options.size)) {
          paint.color = Colors.white;
          paint.shader = page.pencilShader
            ..setFloat(0, color.r)
            ..setFloat(1, color.g)
            ..setFloat(2, color.b);
          paint.maskFilter = _getPencilMaskFilter(stroke.options.size);
        } else {
          // Fast imitation of pencil when zoomed out
          final background = invert ? Colors.black : Colors.white;
          paint.color = Color.lerp(background, color, 0.6)!;
        }
      }

      late final shapePaint = Paint()
        ..color = paint.color
        ..style = .stroke
        ..strokeWidth = stroke.options.size
        ..strokeJoin = .round
        ..strokeCap = .round;

      if (stroke is CircleStroke) {
        canvas.drawCircle(stroke.center, stroke.radius, shapePaint);
      } else if (stroke is RectangleStroke) {
        final strokeSize = stroke.options.size;
        canvas.drawRRect(
          RRect.fromRectAndRadius(stroke.rect, Radius.circular(strokeSize / 4)),
          shapePaint,
        );
      } else if (stroke is PolygonStroke) {
        canvas.drawPath(stroke.outlinePath, shapePaint);
      } else {
        canvas.drawPath(_selectPath(stroke), paint);
      }
    }
  }

  void _drawCurrentStroke(Canvas canvas) {
    if (currentStroke == null) return;

    if (currentStroke! is LaserStroke) {
      return _drawLaserStroke(canvas, currentStroke as LaserStroke);
    }

    final color = currentStroke!.color.withInversion(invert);

    // A stroke snapped to a shape while the pen is still held down
    if (currentStroke case final CircleStroke stroke) {
      canvas.drawCircle(stroke.center, stroke.radius, _shapePaint(stroke, color));
      return;
    } else if (currentStroke case final RectangleStroke stroke) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          stroke.rect,
          Radius.circular(stroke.options.size / 4),
        ),
        _shapePaint(stroke, color),
      );
      return;
    } else if (currentStroke case final PolygonStroke stroke) {
      canvas.drawPath(stroke.outlinePath, _shapePaint(stroke, color));
      return;
    }

    final paint = Paint();

    paint.color = color;
    paint.shader = null;
    paint.maskFilter = null;
    if (currentStroke!.toolId == .pencil) {
      paint.color = Colors.white;
      paint.shader = page.pencilShader
        ..setFloat(0, color.r)
        ..setFloat(1, color.g)
        ..setFloat(2, color.b);
      paint.maskFilter = _getPencilMaskFilter(currentStroke!.options.size);
    }

    // Current stroke always uses high quality
    canvas.drawPath(currentStroke!.highQualityPath, paint);
  }

  static Paint _shapePaint(Stroke stroke, Color color) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = stroke.options.size
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;

  void _drawLaserStroke(Canvas canvas, LaserStroke stroke) {
    canvas.drawPath(
      _selectPath(stroke),
      Paint()
        ..color = stroke.color.withInversion(invert)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.solid,
          stroke.options.size * 0.4,
        ),
    );
    canvas.drawPath(stroke.innerPath, Paint()..color = const Color(0xDDffffff));
  }

  void _drawDetectedShape(Canvas canvas) {
    final shape = ShapePen.detectedShape;
    if (shape == null) return;

    final color = currentStroke?.color.withInversion(invert) ?? Colors.black;
    final shapePaint = Paint()
      ..color = Color.lerp(color, primaryColor, 0.5)!.withValues(alpha: 0.7)
      ..style = .stroke
      ..strokeWidth = currentStroke?.options.size ?? 3;

    switch (shape.name) {
      case null:
        break;
      case DefaultUnistrokeNames.line:
        var (firstPoint, lastPoint) = shape.convertToLine();
        (firstPoint, lastPoint) = Stroke.snapLine(
          firstPoint is PointVector
              ? firstPoint
              : PointVector.fromOffset(offset: firstPoint),
          lastPoint is PointVector
              ? lastPoint
              : PointVector.fromOffset(offset: lastPoint),
        );
        canvas.drawLine(firstPoint, lastPoint, shapePaint);
      case DefaultUnistrokeNames.rectangle:
        final rect = shape.convertToRect();
        canvas.drawRect(rect, shapePaint);
      case DefaultUnistrokeNames.circle:
        final (center, radius) = shape.convertToCircle();
        canvas.drawCircle(center, radius, shapePaint);
      case DefaultUnistrokeNames.triangle:
      case DefaultUnistrokeNames.star:
        final polygon = shape.convertToCanonicalPolygon();
        canvas.drawPath(Path()..addPolygon(polygon, true), shapePaint);
    }
  }

  void _drawSelection(Canvas canvas) {
    if (currentSelection == null) return;

    // draw translucent fill
    canvas.drawPath(
      currentSelection!.path,
      Paint()..color = primaryColor.withValues(alpha: 0.1),
    );

    // draw dashed stroke
    canvas.drawPath(
      dashPath(
        currentSelection!.path,
        dashArray: CircularIntervalList([10, 10]),
      ),
      Paint()
        ..color = primaryColor
        ..strokeWidth = 3
        ..style = .stroke,
    );
  }

  void _drawShapeEditHandles(Canvas canvas) {
    final shapeEdit = ShapeEditTool.current;
    if (shapeEdit.selectedStroke == null ||
        shapeEdit.selectedPageIndex != pageIndex) {
      return;
    }

    final stroke = shapeEdit.selectedStroke!;
    final handles = shapeEdit.getHandles();

    // 1. Draw dashed outline connecting or highlighting the shape
    final outlinePaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.8)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    if (stroke is RectangleStroke) {
      canvas.drawPath(
        dashPath(
          Path()..addRect(stroke.rect),
          dashArray: CircularIntervalList([8, 8]),
        ),
        outlinePaint,
      );
    } else if (stroke is CircleStroke) {
      canvas.drawPath(
        dashPath(
          Path()
            ..addOval(
              Rect.fromCircle(center: stroke.center, radius: stroke.radius),
            ),
          dashArray: CircularIntervalList([8, 8]),
        ),
        outlinePaint,
      );
      // Line from center to radius handle
      canvas.drawLine(
        stroke.center,
        stroke.center + Offset(stroke.radius, 0),
        Paint()
          ..color = primaryColor.withValues(alpha: 0.5)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
    } else {
      final pts = stroke.keyPoints;
      if (pts.length >= 2) {
        final polyPath = Path()..moveTo(pts[0].dx, pts[0].dy);
        for (int i = 1; i < pts.length; i++) {
          polyPath.lineTo(pts[i].dx, pts[i].dy);
        }
        canvas.drawPath(
          dashPath(polyPath, dashArray: CircularIntervalList([8, 8])),
          outlinePaint,
        );
      }
    }

    // 2. Draw handles
    final fillPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = primaryColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    for (final handle in handles) {
      final pos = handle.position;
      final isActive = shapeEdit.activeHandleIndex == handle.index;
      final radius = isActive ? 9.5 : 7.5;

      // Outer shadow
      canvas.drawCircle(
        pos + const Offset(0, 1),
        radius + 0.5,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.25)
          ..style = PaintingStyle.fill,
      );
      // White body
      canvas.drawCircle(pos, radius, fillPaint);
      // Colored border
      canvas.drawCircle(pos, radius, borderPaint);

      // Distinguish center handle of circle
      if (stroke is CircleStroke && handle.index == 0) {
        canvas.drawCircle(
          pos,
          3.5,
          Paint()
            ..color = primaryColor
            ..style = PaintingStyle.fill,
        );
      }
    }
  }

  void _drawLineToolPreview(Canvas canvas) {
    final lineTool = LineTool.current;
    if (lineTool.activePageIndex != pageIndex || !lineTool.isActive) return;

    final pts = lineTool.committedPoints;
    final color = lineTool.color.withInversion(invert);
    final strokeWidth = lineTool.strokeWidth;

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // Draw completed segments
    if (pts.length >= 2) {
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (int i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      canvas.drawPath(path, linePaint);
    }

    // Draw active segment to currentPointer
    if (lineTool.currentPointer != null && pts.isNotEmpty) {
      final last = pts.last;
      final target = lineTool.currentPointer!;
      final previewPaint = Paint()
        ..color = primaryColor
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke;

      canvas.drawPath(
        dashPath(
          Path()
            ..moveTo(last.dx, last.dy)
            ..lineTo(target.dx, target.dy),
          dashArray: CircularIntervalList([6, 6]),
        ),
        previewPaint,
      );
    }

    // Draw vertex dots at committed points
    final dotFill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final dotBorder = Paint()
      ..color = primaryColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    for (final pt in pts) {
      canvas.drawCircle(pt, 4.5, dotFill);
      canvas.drawCircle(pt, 4.5, dotBorder);
    }

    // Draw snap indicator if snapTarget exists
    if (lineTool.snapTarget != null) {
      final snapPos = lineTool.snapTarget!;
      final isClosing = pts.isNotEmpty && (snapPos - pts.first).distance < 2;

      final snapRing = Paint()
        ..color = isClosing ? Colors.greenAccent : primaryColor
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke;

      canvas.drawCircle(snapPos, isClosing ? 10.0 : 7.0, snapRing);
      canvas.drawCircle(
        snapPos,
        isClosing ? 4.0 : 2.5,
        Paint()
          ..color = isClosing ? Colors.greenAccent : primaryColor
          ..style = PaintingStyle.fill,
      );
    }
  }

  static const double _pageIndicatorFontSize = 20;
  static const double _pageIndicatorPadding = 5;
  void _drawPageIndicator(Canvas canvas, Size pageSize) {
    if (!showPageIndicator) return;

    final style = ui.ParagraphStyle(
      textAlign: .end,
      textDirection: .ltr,
      maxLines: 1,
    );

    final builder = ui.ParagraphBuilder(style)
      ..pushStyle(
        ui.TextStyle(
          color: Colors.black.withInversion(invert).withValues(alpha: 0.5),
          fontSize: _pageIndicatorFontSize,
          fontFamily: defaultTextStyle.fontFamily,
          fontFamilyFallback: defaultTextStyle.fontFamilyFallback,
        ),
      )
      ..addText('${pageIndex + 1} / $totalPages');

    final paragraph = builder.build();
    paragraph.layout(
      ui.ParagraphConstraints(
        width: pageSize.width - 2 * _pageIndicatorPadding,
      ),
    );

    canvas.drawParagraph(
      paragraph,
      Offset(
        _pageIndicatorPadding,
        pageSize.height - _pageIndicatorPadding - _pageIndicatorFontSize * 1.2,
      ),
    );
  }

  static MaskFilter _getPencilMaskFilter(double size) =>
      MaskFilter.blur(BlurStyle.normal, min(size * 0.2, 3));
  bool shouldUsePencilShader(double strokeSize) =>
      currentScale >= _zoomThreshold && (strokeSize * currentScale) >= 3;

  static const _zoomThreshold = 0.9;
  Path _selectPath(Stroke stroke) => switch (currentScale) {
    < _zoomThreshold => stroke.lowQualityPath,
    _ => stroke.highQualityPath,
  };
}
