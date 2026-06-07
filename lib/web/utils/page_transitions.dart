// lib/web/utils/page_transitions.dart
// Fade transition that only animates content — sidebar stays static outside this route

import 'package:flutter/material.dart';

class ContentFadeRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  ContentFadeRoute({required this.page})
      : super(
          transitionDuration: const Duration(milliseconds: 220),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (_, _, _) => page,
          transitionsBuilder: (_, animation, _, child) {
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
