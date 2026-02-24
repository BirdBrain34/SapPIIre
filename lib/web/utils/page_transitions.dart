// lib/web/utils/page_transitions.dart
// Fade transition that only animates content — sidebar stays static outside this route

import 'package:flutter/material.dart';

class ContentFadeRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  ContentFadeRoute({required this.page})
      : super(
          transitionDuration: const Duration(milliseconds: 220),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (_, __, ___) => page,
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeInOut,
              ),
              child: child,
            );
          },
        );
}
