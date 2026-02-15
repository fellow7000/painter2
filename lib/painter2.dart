// Updated library: draw a "point" by tapping on the screen. Store your painting by using MyPath
library painter;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart' as mat show Image;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart' hide Image;

class Painter extends StatefulWidget {
  final PainterController painterController;

  Painter(this.painterController)
      : super(key: ValueKey<PainterController>(painterController));

  @override
  State<Painter> createState() => _PainterState();
}

class _PainterState extends State<Painter> {
  final GlobalKey _globalKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    widget.painterController._globalKey = _globalKey;
  }

  @override
  Widget build(BuildContext context) {
    Widget child = CustomPaint(
      willChange: true,
      painter: _PainterPainter(
        widget.painterController._pathHistory,
        repaint: widget.painterController,
      ),
    );

    child = ClipRect(child: child);

    final bg = widget.painterController.backgroundImage;
    if (bg == null) {
      child = RepaintBoundary(
        key: _globalKey,
        child: GestureDetector(
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          child: child,
        ),
      );
    } else {
      child = RepaintBoundary(
        key: _globalKey,
        child: Stack(
          alignment: FractionalOffset.center,
          fit: StackFit.expand,
          children: <Widget>[
            bg,
            GestureDetector(
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              child: child,
            ),
          ],
        ),
      );
    }

    return SizedBox.expand(child: child);
  }

  void _onPanStart(DragStartDetails start) {
    final box = context.findRenderObject() as RenderBox;
    final pos = box.globalToLocal(start.globalPosition);
    widget.painterController._pathHistory.add(pos);
    widget.painterController._notifyListeners();
  }

  void _onPanUpdate(DragUpdateDetails update) {
    final box = context.findRenderObject() as RenderBox;
    final pos = box.globalToLocal(update.globalPosition);
    widget.painterController._pathHistory.updateCurrent(pos);
    widget.painterController._notifyListeners();
  }

  void _onPanEnd(DragEndDetails end) {
    widget.painterController._pathHistory.endCurrent();
    widget.painterController._notifyListeners();
  }
}

class _PainterPainter extends CustomPainter {
  final _PathHistory _path;

  _PainterPainter(this._path, {Listenable? repaint}) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    _path.draw(canvas, size);
  }

  @override
  bool shouldRepaint(_PainterPainter oldDelegate) => true;
}

class _PathHistory {
  final List<MapEntry<Path, Paint>> _paths = <MapEntry<Path, Paint>>[];
  final List<MapEntry<Path, Paint>> _undone = <MapEntry<Path, Paint>>[];

  final Paint _backgroundPaint = Paint();

  bool _inDrag = false;

  // Canvas size is only known after first draw()
  double _width = 0.0;
  double _height = 0.0;

  // Start coordinate for tap-to-point behavior
  double _startX = 0.0;
  double _startY = 0.0;

  bool _startFlag = false;

  bool _erase = false;
  double _eraseArea = 1.0;

  bool _pathFound = false;

  final List<PathPoints> _pathPoints = <PathPoints>[];
  final List<PathPoints> _pathPointsUnDone = <PathPoints>[];

  final MyPaths _myPaths = MyPaths();

  bool _updated = false;

  // Always set by controller via _updatePaint before drawing
  late Paint currentPaint;

  bool canUndo() => _paths.isNotEmpty;

  bool get erase => _erase;
  set erase(bool e) => _erase = e;

  set eraseArea(double r) => _eraseArea = r;

  bool get updated => _updated;
  set updated(bool u) => _updated = u;

  void undo() {
    if (!_inDrag && canUndo()) {
      _undone.add(_paths.removeLast());
      _pathPointsUnDone.add(_pathPoints.removeLast());
    }
  }

  bool canRedo() => _undone.isNotEmpty;

  void redo() {
    if (!_inDrag && canRedo()) {
      _paths.add(_undone.removeLast());
      _pathPoints.add(_pathPointsUnDone.removeLast());
    }
  }

  void clear() {
    if (!_inDrag) {
      _paths.clear();
      _undone.clear();
      _pathPoints.clear();
      _updated = false;
    }
  }

  void loadStartXY(PathPoints pathPoints) {
    final path = Path();
    final paint = Paint()
      ..style = getPaintingStyle(pathPoints.paintingStyle)
      ..strokeWidth = pathPoints.lineThicknes
      ..color = Color(pathPoints.lineColor);

    path.moveTo(pathPoints.startX, pathPoints.startY);
    _paths.add(MapEntry<Path, Paint>(path, paint));
  }

  void load(
    int lineColor,
    double lineThicknes,
    double lineToX,
    double lineToY,
    bool singlePoint,
  ) {
    final loopPath = _paths.last.key;

    if (!singlePoint) {
      loopPath.lineTo(lineToX, lineToY);
    } else {
      loopPath.addOval(
        Rect.fromCircle(center: Offset(lineToX, lineToY), radius: 1.0),
      );
    }
  }

  PaintingStyle getPaintingStyle(String paintingStyleAsString) {
    for (final element in PaintingStyle.values) {
      if (element.toString() == paintingStyleAsString) {
        return element;
      }
    }
    // sensible default (old code returned null)
    return PaintingStyle.stroke;
  }

  Color get backgroundColor => _backgroundPaint.color;
  set backgroundColor(Color color) => _backgroundPaint.color = color;

  void add(Offset startPoint) {
    if (_inDrag) return;

    _inDrag = true;
    _startFlag = true;
    _startX = startPoint.dx;
    _startY = startPoint.dy;

    if (_erase) return;

    final pathPoints = PathPoints(
      startX: startPoint.dx,
      startY: startPoint.dy,
      lineToX: <double>[],
      lineToY: <double>[],
      lineThicknes: currentPaint.strokeWidth,
      lineColor: currentPaint.color.value,
      paintingStyle: currentPaint.style.toString(),
      singlePoint: true,
    );
    _pathPoints.add(pathPoints);

    final path = Path()..moveTo(startPoint.dx, startPoint.dy);
    _paths.add(MapEntry<Path, Paint>(path, currentPaint));
  }

  void updateCurrent(Offset nextPoint) {
    if (!_inDrag) return;

    _pathFound = false;

    if (!_erase) {
      final path = _paths.last.key;
      path.lineTo(nextPoint.dx, nextPoint.dy);

      final pathPoints = _pathPoints.last;
      pathPoints.lineToX.add(nextPoint.dx);
      pathPoints.lineToY.add(nextPoint.dy);
      pathPoints.singlePoint = false;

      _startFlag = false;
      _updated = true;
    } else {
      erasePath(nextPoint.dx, nextPoint.dy);
      _startFlag = false;
    }
  }

  void erasePath(double dx, double dy) {
    for (int i = 0; i < _paths.length; i++) {
      _pathFound = false;

      for (double x = dx - _eraseArea; x <= dx + _eraseArea; x++) {
        for (double y = dy - _eraseArea; y <= dy + _eraseArea; y++) {
          if (_paths[i].key.contains(Offset(x, y))) {
            _pathPointsUnDone.add(_pathPoints.removeAt(i));
            _undone.add(_paths.removeAt(i));
            i--;
            _pathFound = true;
            _updated = true;
            break;
          }
        }
        if (_pathFound) break;
      }
    }
  }

  void endCurrent() {
    _inDrag = false;

    if (_paths.isEmpty) return; // safety guard

    final path = _paths.last.key;

    // if it was just a tap, draw a point and reset a flag
    if (_startFlag && !_erase) {
      path.addOval(
        Rect.fromCircle(center: Offset(_startX, _startY), radius: 1.0),
      );
      _updated = true;
      _startFlag = false;
    }

    if (_startFlag && _erase) {
      erasePath(_startX, _startY);
      _startFlag = false;
    }
  }

  void draw(Canvas canvas, Size size) {
    _width = size.width;
    _height = size.height;

    canvas.drawRect(
      Rect.fromLTWH(0.0, 0.0, size.width, size.height),
      _backgroundPaint,
    );

    for (final path in _paths) {
      canvas.drawPath(path.key, path.value);
    }
  }
}

class PainterController extends ChangeNotifier {
  Color _drawColor = const Color.fromARGB(255, 0, 0, 0);
  Color _backgroundColor = const Color.fromARGB(255, 255, 255, 255);

  mat.Image? _bgimage;

  double _thickness = 1.0;
  double _erasethickness = 1.0;

  final _PathHistory _pathHistory = _PathHistory();

  // Set by Painter widget in initState
  GlobalKey? _globalKey;

  PainterController() {
    // Ensure currentPaint is initialized immediately
    _updatePaint();
  }

  Color get drawColor => _drawColor;
  set drawColor(Color color) {
    _drawColor = color;
    _updatePaint();
  }

  Color get backgroundColor => _backgroundColor;
  set backgroundColor(Color color) {
    _backgroundColor = color;
    _updatePaint();
  }

  mat.Image? get backgroundImage => _bgimage;
  set backgroundImage(mat.Image? image) {
    _bgimage = image;
    _updatePaint();
  }

  double get thickness => _thickness;
  set thickness(double t) {
    _thickness = t;
    _updatePaint();
  }

  double get erasethickness => _erasethickness;
  set erasethickness(double t) {
    _erasethickness = t;
    _pathHistory._eraseArea = t;
    _updatePaint();
  }

  bool get eraser => _pathHistory.erase;
  set eraser(bool e) {
    _pathHistory.erase = e;
    _pathHistory._eraseArea = _erasethickness;
    _updatePaint();
  }

  bool get updated => _pathHistory.updated;
  set updated(bool u) => _pathHistory.updated = u;

  List<PathPoints> getPathPoints() => _pathHistory._pathPoints;

  MyPaths getMyPaths() {
    _pathHistory._myPaths.pathPoints = getPathPoints();
    _pathHistory._myPaths.width = _pathHistory._width;
    _pathHistory._myPaths.height = _pathHistory._height;
    _pathHistory._myPaths.backGroundColor = _pathHistory.backgroundColor.value;
    return _pathHistory._myPaths;
  }

  void setPathPoints(List<PathPoints> setPoints) {
    _pathHistory.clear();
    notifyListeners();

    for (final item in setPoints) {
      _pathHistory.loadStartXY(item);
      notifyListeners();

      if (!item.singlePoint) {
        for (int i = 0; i < item.lineToX.length; i++) {
          _pathHistory.load(
            item.lineColor,
            item.lineThicknes,
            item.lineToX[i],
            item.lineToY[i],
            item.singlePoint,
          );
        }
      } else {
        _pathHistory.load(
          item.lineColor,
          item.lineThicknes,
          item.startX,
          item.startY,
          item.singlePoint,
        );
      }

      notifyListeners();
    }

    _pathHistory._pathPoints
      ..clear()
      ..addAll(setPoints);
  }

  void loadPaths(MyPaths myPaths) {
    backgroundColor = Color(myPaths.backGroundColor);
    _updatePaint();
    setPathPoints(myPaths.pathPoints);
    notifyListeners();
  }

  void _updatePaint() {
    final paint = Paint()
      ..color = drawColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness;

    _pathHistory.currentPaint = paint;

    if (_bgimage != null) {
      _pathHistory.backgroundColor = const Color(0x00000000);
    } else {
      _pathHistory.backgroundColor = _backgroundColor;
    }

    notifyListeners();
  }

  void undo() {
    _pathHistory.undo();
    notifyListeners();
  }

  void redo() {
    _pathHistory.redo();
    notifyListeners();
  }

  bool get canUndo => _pathHistory.canUndo();
  bool get canRedo => _pathHistory.canRedo();

  void _notifyListeners() => notifyListeners();

  void clear() {
    _pathHistory.clear();
    notifyListeners();
  }

  Future<Uint8List> exportAsPNGBytes() async {
    final key = _globalKey;
    final context = key?.currentContext;
    final ro = context?.findRenderObject();
    final boundary = ro is RenderRepaintBoundary ? ro : null;

    if (boundary == null) {
      throw StateError(
        'RepaintBoundary not ready. Make sure Painter is mounted before exporting.',
      );
    }

    final image = await boundary.toImage();
    final byteData = await image.toByteData(format: ImageByteFormat.png);

    if (byteData == null) {
      throw StateError('Failed to encode image as PNG.');
    }

    return byteData.buffer.asUint8List();
  }
}

class PathPoints {
  double startX;
  double startY;
  List<double> lineToX;
  List<double> lineToY;
  String paintingStyle;
  double lineThicknes;
  int lineColor;
  bool singlePoint;

  PathPoints({
    required this.startX,
    required this.startY,
    List<double>? lineToX,
    List<double>? lineToY,
    required this.paintingStyle,
    required this.lineThicknes,
    required this.lineColor,
    this.singlePoint = true,
  })  : lineToX = lineToX ?? <double>[],
        lineToY = lineToY ?? <double>[];

  Map<String, dynamic> toJson() => <String, dynamic>{
        'startX': startX,
        'startY': startY,
        'lineToX': lineToX,
        'lineToY': lineToY,
        'paintingStyle': paintingStyle,
        'lineThicknes': lineThicknes,
        'lineColor': lineColor,
        'singlePoint': singlePoint,
      };

  factory PathPoints.fromJson(Map<String, dynamic> parsedJson) {
    // Support both: list already decoded OR stringified list
    final dynamic rawX = parsedJson['lineToX'];
    final dynamic rawY = parsedJson['lineToY'];

    final List<dynamic> decodedX =
        rawX is String ? (jsonDecode(rawX) as List<dynamic>) : (rawX as List<dynamic>? ?? <dynamic>[]);
    final List<dynamic> decodedY =
        rawY is String ? (jsonDecode(rawY) as List<dynamic>) : (rawY as List<dynamic>? ?? <dynamic>[]);

    return PathPoints(
      startX: (parsedJson['startX'] as num).toDouble(),
      startY: (parsedJson['startY'] as num).toDouble(),
      lineToX: decodedX.map((e) => (e as num).toDouble()).toList(),
      lineToY: decodedY.map((e) => (e as num).toDouble()).toList(),
      paintingStyle: parsedJson['paintingStyle'] as String,
      lineThicknes: (parsedJson['lineThicknes'] as num).toDouble(),
      lineColor: parsedJson['lineColor'] as int,
      singlePoint: parsedJson['singlePoint'] as bool? ?? true,
    );
  }
}

class MyPaths {
  double width; // canvas' width
  double height; // canvas' height
  int backGroundColor;
  List<PathPoints> pathPoints;

  MyPaths({
    this.width = 0.0,
    this.height = 0.0,
    this.backGroundColor = 0xFFFFFFFF,
    List<PathPoints>? pathPoints,
  }) : pathPoints = pathPoints ?? <PathPoints>[];

  Map<String, dynamic> toJson() => <String, dynamic>{
        'width': width,
        'height': height,
        'backGroundColor': backGroundColor,
        'pathPoints': pathPoints,
      };

  factory MyPaths.fromJson(Map<String, dynamic> parsedJson) {
    final rawList = parsedJson['pathPoints'];

    final List<PathPoints> points;
    if (rawList is List) {
      points = rawList
          .map((i) => PathPoints.fromJson(Map<String, dynamic>.from(i as Map)))
          .toList();
    } else {
      points = <PathPoints>[];
    }

    return MyPaths(
      width: (parsedJson['width'] as num?)?.toDouble() ?? 0.0,
      height: (parsedJson['height'] as num?)?.toDouble() ?? 0.0,
      backGroundColor: parsedJson['backGroundColor'] as int? ?? 0xFFFFFFFF,
      pathPoints: points,
    );
  }
}