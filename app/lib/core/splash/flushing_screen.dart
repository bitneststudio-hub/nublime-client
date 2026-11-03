// lib/core/splash/flushing_screen.dart
import 'package:flutter/material.dart';
import 'dart:async';

class FlushingScreen extends StatefulWidget {
  final VoidCallback onFinished;
  const FlushingScreen({super.key, required this.onFinished});

  @override
  State<FlushingScreen> createState() => _FlushingScreenState();
}

class _FlushingScreenState extends State<FlushingScreen> with TickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(duration: const Duration(milliseconds: 500), vsync: this)
      ..repeat(reverse: true);
    Future.delayed(const Duration(milliseconds: 2200), () => widget.onFinished());
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        final r = ((0xFF * (1 - t)) + (0x4C * t)).round();
        final g = ((0x44 * (1 - t)) + (0xAF * t)).round();
        final b = ((0x44 * (1 - t)) + (0x50 * t)).round();
        final color = Color.fromARGB(255, r, g, b);
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Container(
            color: const Color(0xFF060C18),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 100, height: 100,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.15),
                    border: Border.all(color: color, width: 2),
                    boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 30)]),
                  child: Center(child: Image.asset('assets/icon/icon_512x512.png', width: 64, height: 64)),
                ),
                const SizedBox(height: 20),
                Text('WildLime VPN', style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
              ]),
            ),
          ),
        );
      },
    );
  }
}
