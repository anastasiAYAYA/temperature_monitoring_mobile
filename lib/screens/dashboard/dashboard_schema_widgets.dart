part of '../dashboard_screen.dart';

class _SchemaViewport extends StatefulWidget {
  const _SchemaViewport({
    super.key,
    required this.imageUrl,
    required this.sensors,
    required this.transformCtrl,
    required this.textDim,
    required this.isDark,
  });
  final String imageUrl;
  final List<SensorModel> sensors;
  final TransformationController transformCtrl;
  final Color textDim;
  final bool isDark;

  @override
  State<_SchemaViewport> createState() => _SchemaViewportState();
}

class _SchemaViewportState extends State<_SchemaViewport> {
  double? _aspectRatio;

  @override
  void initState() {
    super.initState();
    _resolveImageSize();
  }

  void _resolveImageSize() {
    final stream = NetworkImage(
      widget.imageUrl,
    ).resolve(ImageConfiguration.empty);
    stream.addListener(
      ImageStreamListener((info, _) {
        if (!mounted) return;
        final w = info.image.width.toDouble();
        final h = info.image.height.toDouble();
        if (h > 0) setState(() => _aspectRatio = w / h);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final ratio = _aspectRatio ?? (16 / 9);
        final height = width / ratio;
        return SizedBox(
          width: width,
          height: height,
          child: InteractiveViewer(
            transformationController: widget.transformCtrl,
            minScale: 0.5,
            maxScale: 6.0,
            child: Stack(
              children: [
                Image.network(
                  widget.imageUrl,
                  width: width,
                  height: height,
                  fit: BoxFit.fill,
                  color: widget.isDark
                      ? Colors.black.withOpacity(0.45)
                      : Colors.black.withOpacity(0.15),
                  colorBlendMode: BlendMode.darken,
                  errorBuilder: (_, __, ___) => Center(
                    child: Text(
                      'Не удалось загрузить план',
                      style: TextStyle(color: widget.textDim, fontSize: 12),
                    ),
                  ),
                ),
                ...widget.sensors.map(
                  (sensor) => Positioned(
                    left: sensor.x * width,
                    top: sensor.y * height,
                    child: FractionalTranslation(
                      translation: const Offset(-0.5, -0.5),
                      child: SensorDot(state: sensor.state, sensor: sensor),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Мнемосхема в режиме редактирования ───────────────────────────────────────

/// Режим редактирования: без InteractiveViewer, координаты обновляются жестами [_SmoothDraggableDot].
class _EditableSchema extends StatefulWidget {
  const _EditableSchema({
    super.key,
    required this.imageUrl,
    required this.sensors,
    required this.onPanUpdate,
  });
  final String? imageUrl;
  final List<SensorModel> sensors;
  final void Function(SensorModel sensor, Offset delta) onPanUpdate;

  @override
  State<_EditableSchema> createState() => _EditableSchemaState();
}

class _EditableSchemaState extends State<_EditableSchema> {
  double? _aspectRatio;

  @override
  void initState() {
    super.initState();
    if (widget.imageUrl != null) _resolveImageSize();
  }

  void _resolveImageSize() {
    final stream = NetworkImage(
      widget.imageUrl!,
    ).resolve(ImageConfiguration.empty);
    stream.addListener(
      ImageStreamListener((info, _) {
        if (!mounted) return;
        final w = info.image.width.toDouble();
        final h = info.image.height.toDouble();
        if (h > 0) setState(() => _aspectRatio = w / h);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final ratio = _aspectRatio ?? (16 / 9);
        final height = width / ratio;
        final schemaBg = c.isDark
            ? const Color(0xFF060E0F)
            : const Color(0xFFF0F4F8);
        return SizedBox(
          width: width,
          height: height,
          child: Stack(
            children: [
              Container(
                color: schemaBg,
                width: width,
                height: height,
                child: widget.imageUrl != null
                    ? Image.network(
                        widget.imageUrl!,
                        fit: BoxFit.fill,
                        width: width,
                        height: height,
                        color: c.isDark
                            ? Colors.black.withOpacity(0.45)
                            : Colors.black.withOpacity(0.15),
                        colorBlendMode: BlendMode.darken,
                        errorBuilder: (_, __, ___) => Center(
                          child: Text(
                            'Не удалось загрузить план',
                            style: TextStyle(color: c.textDim, fontSize: 12),
                          ),
                        ),
                      )
                    : Center(
                        child: Text(
                          'Мнемосхема не загружена',
                          style: TextStyle(color: c.textDim, fontSize: 12),
                        ),
                      ),
              ),
              ...widget.sensors.map(
                (s) => _SmoothDraggableDot(
                  sensor: s,
                  schemaWidth: width,
                  schemaHeight: height,
                  onPanUpdate: (delta) => widget.onPanUpdate(s, delta),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Датчик с плавным перетаскиванием ─────────────────────────────────────────

class _SmoothDraggableDot extends StatefulWidget {
  const _SmoothDraggableDot({
    required this.sensor,
    required this.schemaWidth,
    required this.schemaHeight,
    required this.onPanUpdate,
  });
  final SensorModel sensor;
  final double schemaWidth;
  final double schemaHeight;
  final void Function(Offset delta) onPanUpdate;

  @override
  State<_SmoothDraggableDot> createState() => _SmoothDraggableDotState();
}

class _SmoothDraggableDotState extends State<_SmoothDraggableDot> {
  AppScheme get c => AppColors.of(context);
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    const cardW = 62.0;
    const cardH = 36.0;
    final px = widget.sensor.x * widget.schemaWidth - cardW / 2;
    final py = widget.sensor.y * widget.schemaHeight - cardH / 2;

    return Positioned(
      left: px.clamp(0.0, widget.schemaWidth - cardW),
      top: py.clamp(0.0, widget.schemaHeight - cardH),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => setState(() => _dragging = true),
        onPanUpdate: (d) => widget.onPanUpdate(d.delta),
        onPanEnd: (_) => setState(() => _dragging = false),
        child: AnimatedScale(
          scale: _dragging ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (_dragging)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(7),
                      color: _stateColor(widget.sensor.state).withOpacity(0.15),
                    ),
                  ),
                ),
              SensorDot(state: widget.sensor.state, sensor: widget.sensor),
            ],
          ),
        ),
      ),
    );
  }

  Color _stateColor(SensorState s) => switch (s) {
    SensorState.normal => c.green,
    SensorState.warning => c.orange,
    SensorState.critical => c.red,
  };
}
