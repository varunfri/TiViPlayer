import 'dart:async';
import 'package:flutter/material.dart';

enum TvToastType { info, success, warning, error }

class TvToast {
  static OverlayEntry? _currentEntry;
  static Timer? _dismissTimer;

  static void show(
    BuildContext context,
    String message, {
    TvToastType type = TvToastType.info,
    IconData? icon,
    Duration duration = const Duration(milliseconds: 3000),
  }) {
    _dismissTimer?.cancel();
    _currentEntry?.remove();
    _currentEntry = null;

    final overlay = Overlay.of(context, rootOverlay: true);

    Color accentColor;
    IconData defaultIcon;

    switch (type) {
      case TvToastType.success:
        accentColor = const Color(0xFF10B981);
        defaultIcon = Icons.check_circle_rounded;
        break;
      case TvToastType.warning:
        accentColor = const Color(0xFFF59E0B);
        defaultIcon = Icons.warning_amber_rounded;
        break;
      case TvToastType.error:
        accentColor = const Color(0xFFEF4444);
        defaultIcon = Icons.error_outline_rounded;
        break;
      case TvToastType.info:
        accentColor = const Color(0xFF3B82F6);
        defaultIcon = Icons.info_outline_rounded;
        break;
    }

    final entry = OverlayEntry(
      builder: (context) => _TvToastWidget(
        message: message,
        accentColor: accentColor,
        icon: icon ?? defaultIcon,
        onDismiss: () {
          _dismissTimer?.cancel();
          _currentEntry?.remove();
          _currentEntry = null;
        },
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);

    _dismissTimer = Timer(duration, () {
      _currentEntry?.remove();
      _currentEntry = null;
    });
  }

  static void info(BuildContext context, String message, {IconData? icon}) {
    show(context, message, type: TvToastType.info, icon: icon);
  }

  static void success(BuildContext context, String message, {IconData? icon}) {
    show(context, message, type: TvToastType.success, icon: icon);
  }

  static void warning(BuildContext context, String message, {IconData? icon}) {
    show(context, message, type: TvToastType.warning, icon: icon);
  }

  static void error(BuildContext context, String message, {IconData? icon}) {
    show(context, message, type: TvToastType.error, icon: icon);
  }
}

class _TvToastWidget extends StatefulWidget {
  final String message;
  final Color accentColor;
  final IconData icon;
  final VoidCallback onDismiss;

  const _TvToastWidget({
    required this.message,
    required this.accentColor,
    required this.icon,
    required this.onDismiss,
  });

  @override
  State<_TvToastWidget> createState() => _TvToastWidgetState();
}

class _TvToastWidgetState extends State<_TvToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.2, -0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismissWithAnimation() async {
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 24,
      right: 24,
      child: Material(
        color: Colors.transparent,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: InkWell(
              onTap: _dismissWithAnimation,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF131620).withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: widget.accentColor.withValues(alpha: 0.7),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.7),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                      spreadRadius: 1,
                    ),
                    BoxShadow(
                      color: widget.accentColor.withValues(alpha: 0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: widget.accentColor.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        widget.icon,
                        color: widget.accentColor,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.close_rounded,
                      color: Colors.white.withValues(alpha: 0.5),
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
