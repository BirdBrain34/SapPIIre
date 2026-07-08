import 'package:flutter/material.dart';

class SaveButton extends StatelessWidget {
  final VoidCallback onTap;
  final VoidCallback onDiscard;
  final bool isSaving;

  const SaveButton({
    super.key,
    required this.onTap,
    required this.onDiscard,
    this.isSaving = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── X (discard) side ──────────────────────────────────────
          GestureDetector(
            onTap: isSaving ? null : onDiscard,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSaving ? Colors.red.shade900 : Colors.red.shade800,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                Icons.close,
                color: isSaving ? Colors.white38 : Colors.white,
                size: 18,
              ),
            ),
          ),

          // ── Divider ───────────────────────────────────────────────
          Container(
            width: 1,
            height: 24,
            color: Colors.white.withValues(alpha: 0.25),
          ),

          // ── Save side ─────────────────────────────────────────────
          GestureDetector(
            onTap: isSaving ? null : onTap,
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isSaving
                    ? Colors.green.shade700.withValues(alpha: 0.75)
                    : Colors.green.shade700,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isSaving)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white70,
                      ),
                    )
                  else
                    const Icon(Icons.save, color: Colors.white, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    isSaving ? 'Saving…' : 'Save changes',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
