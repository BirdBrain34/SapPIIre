import 'package:flutter/material.dart';

import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/web/controllers/form_builder_controller.dart' as base;
import 'package:sappiire/web/controllers/form_builder_screen_controller.dart';

/// Bottom sheet for creating a new canonical key inline while editing a field.
/// Pattern matches showSystemBlockPicker in form_builder_screen_helpers.dart.
void showCanonicalKeyCreatorSheet(
  BuildContext context,
  FormBuilderScreenController controller, {
  required void Function(String keyName) onCreated,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _CanonicalKeyCreatorSheet(
      controller: controller,
      onCreated: onCreated,
    ),
  );
}

class _CanonicalKeyCreatorSheet extends StatefulWidget {
  final FormBuilderScreenController controller;
  final void Function(String keyName) onCreated;

  const _CanonicalKeyCreatorSheet({
    required this.controller,
    required this.onCreated,
  });

  @override
  State<_CanonicalKeyCreatorSheet> createState() =>
      _CanonicalKeyCreatorSheetState();
}

class _CanonicalKeyCreatorSheetState extends State<_CanonicalKeyCreatorSheet> {
  final _labelCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _isBusy = false;
  String? _error;

  String get _slug => base.slugify(_labelCtrl.text.trim());

  @override
  void dispose() {
    _labelCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _isBusy = true;
      _error = null;
    });

    final entry = await widget.controller.createCanonicalKey(
      label: _labelCtrl.text,
      description: _descCtrl.text.trim().isEmpty
          ? null
          : _descCtrl.text.trim(),
    );

    if (!mounted) return;

    if (entry != null) {
      widget.onCreated(entry.keyName);
      Navigator.pop(context);
    } else {
      setState(() {
        _error = widget.controller.canonicalKeyCreationError;
        _isBusy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.cardBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'New Canonical Key',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Creates a new cross-form autofill key visible in every template.',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _labelCtrl,
            decoration: InputDecoration(
              labelText: 'Key label',
              hintText: 'e.g. Emergency Contact Name',
              filled: true,
              fillColor: AppColors.pageBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.highlight),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text(
                'Key: ',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              Expanded(
                child: Text(
                  _slug.isEmpty ? '(type a label)' : _slug,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: _slug.isNotEmpty
                        ? AppColors.highlight
                        : AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _descCtrl,
            decoration: InputDecoration(
              labelText: 'Description (optional)',
              hintText: 'What this key represents',
              filled: true,
              fillColor: AppColors.pageBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.highlight),
              ),
            ),
            maxLines: 2,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_slug.isEmpty || _isBusy) ? null : _create,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.highlight,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: _isBusy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Create Key',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}