class CanonicalKeyEntry {
  final String keyName;
  final String displayLabel;
  final String? description;
  final bool isSystem;
  final bool isActive;

  const CanonicalKeyEntry({
    required this.keyName,
    required this.displayLabel,
    this.description,
    this.isSystem = false,
    this.isActive = true,
  });

  factory CanonicalKeyEntry.fromMap(Map<String, dynamic> m) => CanonicalKeyEntry(
    keyName: m['key_name'] as String,
    displayLabel: (m['display_label'] as String?)?.trim().isNotEmpty == true
        ? m['display_label'] as String
        : m['key_name'] as String,
    description: m['description'] as String?,
    isSystem: m['is_system'] == true,
    isActive: m['is_active'] != false,
  );
}