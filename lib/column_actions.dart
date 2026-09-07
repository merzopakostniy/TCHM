import 'package:flutter/material.dart';

/// A short left swipe reveals actions; only a button press invokes them.
class ColumnActions extends StatefulWidget {
  const ColumnActions({
    super.key,
    required this.child,
    required this.onEdit,
    required this.onDelete,
  });

  final Widget child;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<ColumnActions> createState() => _ColumnActionsState();
}

class _ColumnActionsState extends State<ColumnActions>
    with SingleTickerProviderStateMixin {
  static const _width = 176.0;
  static final _openCard = ValueNotifier<Object?>(null);
  final _identity = Object();
  late final _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  @override
  void initState() {
    super.initState();
    _openCard.addListener(_closeOther);
  }

  void _closeOther() {
    if (_openCard.value != _identity && _slide.value > 0) _slide.reverse();
  }

  void _close() {
    _slide.reverse();
    if (_openCard.value == _identity) _openCard.value = null;
  }

  @override
  void dispose() {
    _openCard.removeListener(_closeOther);
    if (_openCard.value == _identity) _openCard.value = null;
    _slide.dispose();
    super.dispose();
  }

  Widget _action(
    String label,
    IconData icon,
    Color color,
    VoidCallback action,
  ) {
    return Expanded(
      child: Material(
        color: color,
        child: InkWell(
          onTap: () {
            _close();
            action();
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        children: [
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: _width,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _action(
                      'Изменить',
                      Icons.edit_outlined,
                      const Color(0xFF6B727A),
                      widget.onEdit,
                    ),
                    _action(
                      'Удалить',
                      Icons.delete_outline,
                      const Color(0xFFA41418),
                      widget.onDelete,
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _slide,
            builder: (context, child) => Transform.translate(
              offset: Offset(-_width * _slide.value, 0),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (details) {
                  if ((details.primaryDelta ?? 0) < 0) {
                    _openCard.value = _identity;
                  }
                  _slide.value -= (details.primaryDelta ?? 0) / _width;
                },
                onHorizontalDragEnd: (details) {
                  final velocity = details.velocity.pixelsPerSecond.dx;
                  if (velocity < -250 ||
                      (velocity <= 250 && _slide.value > 0.2)) {
                    _openCard.value = _identity;
                    _slide.forward();
                  } else {
                    _close();
                  }
                },
                onHorizontalDragCancel: _close,
                onTap: _slide.value > 0 ? _close : null,
                child: AbsorbPointer(absorbing: _slide.value > 0, child: child),
              ),
            ),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
