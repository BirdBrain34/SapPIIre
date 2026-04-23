import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';

class ProfileSectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const ProfileSectionHeader({
    super.key,
    required this.title,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primaryBlue),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primaryBlue, letterSpacing: 0.3)),
      ],
    );
  }
}

class ProfileCard extends StatelessWidget {
  final List<Widget> children;

  const ProfileCard({
    super.key,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEEF5)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(children: children),
    );
  }
}

class ProfileDivider extends StatelessWidget {
  const ProfileDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, indent: 16, endIndent: 16);
  }
}

class ProfileReadOnlyRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const ProfileReadOnlyRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade400),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 14, color: Colors.black87)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final IconData icon;
  final String? hint;
  final int maxLines;

  const ProfileTextField({
    super.key,
    required this.label,
    required this.controller,
    required this.icon,
    this.hint,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade400),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: maxLines,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
              decoration: InputDecoration(
                labelText: label,
                hintText: hint,
                labelStyle: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileDateField extends StatelessWidget {
  final String value;
  final VoidCallback onTap;

  const ProfileDateField({
    super.key,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined, size: 18, color: Colors.grey.shade400),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Date of Birth', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  const SizedBox(height: 2),
                  Text(
                    value.isEmpty ? 'Select date' : value,
                    style: TextStyle(fontSize: 14, color: value.isEmpty ? Colors.grey.shade400 : Colors.black87),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}

class ProfileDropdownField extends StatelessWidget {
  final String label;
  final String? value;
  final IconData icon;
  final List<String> items;
  final void Function(String?) onChanged;

  const ProfileDropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    String? safeValue = value;
    if (safeValue != null && !items.contains(safeValue)) safeValue = null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade400),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: safeValue,
                hint: Text(label, style: TextStyle(fontSize: 14, color: Colors.grey.shade400)),
                isExpanded: true,
                icon: Icon(Icons.expand_more, size: 18, color: Colors.grey.shade400),
                style: const TextStyle(fontSize: 14, color: Colors.black87),
                items: items.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
                onChanged: onChanged,
                selectedItemBuilder: (context) => items.map((item) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                    Text(item, style: const TextStyle(fontSize: 14, color: Colors.black87)),
                  ],
                )).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final bool isDestructive;

  const ProfileActionRow({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? AppColors.dangerRed : AppColors.primaryBlue;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isDestructive ? AppColors.dangerRed : Colors.black87)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}
