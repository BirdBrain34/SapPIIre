import 'package:flutter/material.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/mobile/utils/date_utils.dart';

class HistoryDetailDialog {
  static Future<void> show(BuildContext context, Map<String, dynamic> item) {
    final formType = item['form_type'] as String? ?? 'Unknown Form';
    final intakeRef = item['intake_reference'] as String?;
    final scannedAt = item['scanned_at'] as String?;
    final processedAt = item['last_edited_at'] as String?;
    final createdAt = item['created_at'] as String?;
    final workerName = item['last_edited_by']?.toString().trim() ?? '';

    return showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row
              Row(
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
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          formType,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E)),
                        ),
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('Submitted', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.green)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),

              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),

              // Detail rows
              if (intakeRef != null && intakeRef.isNotEmpty)
                _detailRow(
                  icon: Icons.tag,
                  label: 'Reference No.',
                  value: intakeRef,
                  valueStyle: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryBlue,
                    fontFamily: 'monospace',
                  ),
                ),

              _detailRow(
                icon: Icons.qr_code_scanner,
                label: 'Scanned at',
                value: AppDateUtils.formatDisplay(scannedAt),
              ),

              if (workerName.isNotEmpty)
                _detailRow(
                  icon: Icons.person_outline,
                  label: 'Assisted by',
                  value: workerName,
                  valueStyle: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryBlue,
                  ),
                )
              else
                _detailRow(
                  icon: Icons.person_outline,
                  label: 'Assisted by',
                  value: 'Not yet processed',
                  valueStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400, fontStyle: FontStyle.italic),
                ),

              if (processedAt != null && processedAt.isNotEmpty)
                _detailRow(
                  icon: Icons.edit_outlined,
                  label: 'Processed at',
                  value: AppDateUtils.formatDisplay(processedAt),
                ),

              _detailRow(
                icon: Icons.calendar_today_outlined,
                label: 'Record created',
                value: AppDateUtils.formatDisplay(createdAt),
              ),

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  child: const Text('Close', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _detailRow({
    required IconData icon,
    required String label,
    required String value,
    TextStyle? valueStyle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withOpacity(0.06),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 14, color: AppColors.primaryBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: valueStyle ?? const TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
