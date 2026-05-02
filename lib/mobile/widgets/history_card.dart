import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/mobile/utils/date_utils.dart';

class HistoryCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  const HistoryCard({
    super.key,
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final formType = item['form_type'] as String? ?? 'Unknown Form';
    final intakeRef = item['intake_reference'] as String?;
    final scannedAt = item['scanned_at'] as String?;
    final processedAt = item['last_edited_at'] as String?;
    final workerName = item['last_edited_by']?.toString().trim() ?? '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEEEEF5)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.qr_code_scanner, color: AppColors.primaryBlue, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(formType, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black87)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('Submitted', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.green)),
                        ),
                      ],
                    ),

                    if (intakeRef != null && intakeRef.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.tag, size: 12, color: AppColors.primaryBlue),
                          const SizedBox(width: 4),
                          Text(intakeRef, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primaryBlue, fontFamily: 'monospace')),
                        ],
                      ),
                    ],

                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.qr_code_scanner, size: 12, color: Colors.grey.shade400),
                        const SizedBox(width: 5),
                        Expanded(child: Text('Scanned: ${AppDateUtils.formatDisplay(scannedAt)}', style: TextStyle(fontSize: 12, color: Colors.grey.shade500))),
                      ],
                    ),

                    if (workerName.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.person_outline, size: 12, color: AppColors.primaryBlue.withOpacity(0.7)),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              'Assisted by: $workerName',
                              style: TextStyle(fontSize: 12, color: AppColors.primaryBlue.withOpacity(0.85), fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],

                    if (processedAt != null && processedAt.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 12, color: Colors.grey.shade400),
                          const SizedBox(width: 5),
                          Expanded(child: Text('Processed: ${AppDateUtils.formatDisplay(processedAt)}', style: TextStyle(fontSize: 12, color: Colors.grey.shade500))),
                        ],
                      ),
                    ],

                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text('Tap for details', style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
                        const SizedBox(width: 2),
                        Icon(Icons.info_outline, size: 11, color: Colors.grey.shade400),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
