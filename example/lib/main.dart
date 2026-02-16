import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:painter2/painter2.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Painter2 Example',
      home: ExamplePage(),
    );
  }
}

class ExamplePage extends StatefulWidget {
  const ExamplePage({super.key});

  @override
  State<ExamplePage> createState() => _ExamplePageState();
}

class _ExamplePageState extends State<ExamplePage> {
  bool _finished = false;
  late PainterController _controller;

  List<PathPoints>? _pathPoints;
  MyPaths? _myNote;

  @override
  void initState() {
    super.initState();
    _controller = _newController();
  }

  PainterController _newController() {
    final controller = PainterController();
    controller.thickness = 5.0;
    controller.backgroundColor = Colors.white;
    // controller.backgroundImage = Image.network('...');
    return controller;
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> actions = _finished
        ? <Widget>[
            IconButton(
              icon: const Icon(Icons.content_copy),
              tooltip: 'New Painting',
              onPressed: () => setState(() {
                _finished = false;
                _controller = _newController();
              }),
            ),
          ]
        : <Widget>[
            IconButton(
              icon: const Icon(Icons.undo),
              tooltip: 'Undo',
              onPressed: () {
                if (_controller.canUndo) _controller.undo();
              },
            ),
            IconButton(
              icon: const Icon(Icons.redo),
              tooltip: 'Redo',
              onPressed: () {
                if (_controller.canRedo) _controller.redo();
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              tooltip: 'Clear',
              onPressed: () => _controller.clear(),
            ),
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: () async {
                final navigator = Navigator.of(context);
                setState(() => _finished = true);

                _pathPoints = _controller.getPathPoints();
                _myNote = _controller.getMyPaths();

                // Debug prints
                final noteJson = jsonEncode(_myNote);
                // ignore: avoid_print
                print(noteJson);

                final pointsJson = jsonEncode(_pathPoints);
                // ignore: avoid_print
                print(pointsJson);

                final Uint8List bytes = await _controller.exportAsPNGBytes();

                navigator.push(
                  MaterialPageRoute(
                    builder: (BuildContext context) {
                      return Scaffold(
                        appBar: AppBar(
                          title: const Text('View your image'),
                        ),
                        body: Center(
                          child: Image.memory(bytes),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.restore),
              onPressed: () {
                final note = _myNote;
                if (note != null) {
                  _controller.loadPaths(note);
                  setState(() => _finished = false);
                }
              },
            ),
          ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Painter2 Example'),
        actions: actions,
        bottom: PreferredSize(
          preferredSize: Size(MediaQuery.of(context).size.width, 34.0),
          child: DrawBar(_controller),
        ),
      ),
      body: Center(
        child: Painter(_controller),
      ),
    );
  }
}

class DrawBar extends StatelessWidget {
  final PainterController controller;

  const DrawBar(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Flexible(
          child: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              return Slider(
                value: controller.thickness,
                min: 1.0,
                max: 20.0,
                activeColor: Colors.white,
                onChanged: (value) => setState(() {
                  controller.thickness = value;
                }),
              );
            },
          ),
        ),
        ColorPickerButton(controller: controller, background: false),
        ColorPickerButton(controller: controller, background: true),
      ],
    );
  }
}

class ColorPickerButton extends StatefulWidget {
  final PainterController controller;
  final bool background;

  const ColorPickerButton({
    super.key,
    required this.controller,
    required this.background,
  });

  @override
  State<ColorPickerButton> createState() => _ColorPickerButtonState();
}

class _ColorPickerButtonState extends State<ColorPickerButton> {
  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(_iconData, color: _color),
      tooltip:
          widget.background ? 'Change background color' : 'Change draw color',
      onPressed: _pickColor,
    );
  }

  void _pickColor() {
    Color pickerColor = _color;

    Navigator.of(context)
        .push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (BuildContext context) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Pick color'),
            ),
            body: Center(
              child: ColorPicker(
                pickerColor: pickerColor,
                onColorChanged: (Color c) => pickerColor = c,
              ),
            ),
          );
        },
      ),
    )
        .then((_) {
      if (!mounted) return;
      setState(() => _color = pickerColor);
    });
  }

  Color get _color =>
      widget.background ? widget.controller.backgroundColor : widget.controller.drawColor;

  IconData get _iconData =>
      widget.background ? Icons.format_color_fill : Icons.brush;

  set _color(Color color) {
    if (widget.background) {
      widget.controller.backgroundColor = color;
    } else {
      widget.controller.drawColor = color;
    }
  }
}
