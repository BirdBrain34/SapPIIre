import 'package:flutter/material.dart';

import 'package:sappiire/config/retention_config.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/services/retention_analytics_service.dart';
import 'package:sappiire/web/utils/web_navigator.dart';
import 'package:sappiire/web/utils/web_session.dart';
import 'package:sappiire/web/widgets/filter_controls.dart';
import 'package:sappiire/web/widgets/retention_summary_cards.dart';
import 'package:sappiire/web/widgets/web_shell.dart';

/// Admin view of finalized records that have not been updated in a long time,
/// so an admin can review them and flag any for archival.
///
/// Shows only non-sensitive metadata (reference number, form type, last-updated
/// date, age, staleness tier) — never decrypted submission content. Restricted
/// to admin / superadmin: [WebNavigator] gates the route, the side menu only
/// renders the entry for those roles, and [initState] self-pops as a backstop.
class DataRetentionScreen extends StatefulWidget {
  const DataRetentionScreen({
    super.key,
    required this.cswdId,
    required this.role,
    required this.displayName,
  });

  final String cswdId;
  final String role;
  final String displayName;

  @override
  State<DataRetentionScreen> createState() => _DataRetentionScreenState();
}

class _DataRetentionScreenState extends State<DataRetentionScreen> {
  final _service = RetentionAnalyticsService();

  /// Every stale record (all form types, all tiers). Filtering is done in the
  /// browser against this list, which is a small subset of the archive.
  List<StaleRecord> _allStale = [];
  List<String> _formTypes = [];
  bool _isLoading = true;

  String _formTypeFilter = 'All';
  RetentionTier? _tierFilter;

  // Ids currently mid-flag, so their row action shows a spinner and can't be
  // double-tapped.
  final Set<String> _busyIds = {};

  bool get _isAdmin =>
      widget.role == 'admin' || widget.role == 'superadmin';

  @override
  void initState() {
    super.initState();
    if (!_isAdmin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
      return;
    }
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final records = await _service.fetchStaleRecords();
    if (!mounted) return;

    final types = records.map((r) => r.formType).toSet().toList()..sort();
    setState(() {
      _allStale = records;
      _formTypes = types;
      _isLoading = false;
      // Drop a form-type filter that no longer has any stale records.
      if (_formTypeFilter != 'All' && !types.contains(_formTypeFilter)) {
        _formTypeFilter = 'All';
      }
    });
  }

  /// Records after applying the form-type filter (drives the tier summary).
  List<StaleRecord> get _scopedByForm => _formTypeFilter == 'All'
      ? _allStale
      : _allStale.where((r) => r.formType == _formTypeFilter).toList();

  /// Records after applying both filters (drives the table).
  List<StaleRecord> get _visible {
    final scoped = _scopedByForm;
    if (_tierFilter == null) return scoped;
    return scoped.where((r) => r.tier == _tierFilter).toList();
  }

  Map<RetentionTier, int> get _summaryCounts {
    final counts = <RetentionTier, int>{
      for (final t in RetentionConfig.tiersAscending) t.tier: 0,
    };
    for (final r in _scopedByForm) {
      counts[r.tier] = (counts[r.tier] ?? 0) + 1;
    }
    return counts;
  }

  Future<void> _toggleFlag(StaleRecord record) async {
    final key = record.id.toString();
    if (_busyIds.contains(key)) return;
    setState(() => _busyIds.add(key));

    final flagging = !record.isFlaggedForArchival;
    final ok = flagging
        ? await _service.flagForArchival(
            submissionId: record.id,
            staffId: widget.cswdId,
            staffName: widget.displayName,
            staffRole: widget.role,
            intakeReference: record.intakeReference,
          )
        : await _service.clearArchivalFlag(
            submissionId: record.id,
            staffId: widget.cswdId,
            staffName: widget.displayName,
            staffRole: widget.role,
            intakeReference: record.intakeReference,
          );

    if (!mounted) return;
    setState(() {
      _busyIds.remove(key);
      if (ok) {
        final idx = _allStale.indexWhere((r) => r.id == record.id);
        if (idx != -1) {
          _allStale[idx] = StaleRecord(
            id: record.id,
            intakeReference: record.intakeReference,
            formType: record.formType,
            lastUpdated: record.lastUpdated,
            ageDays: record.ageDays,
            tier: record.tier,
            usesEditTimestamp: record.usesEditTimestamp,
            retentionStatus: flagging ? 'flagged_for_archival' : null,
            flaggedAt: flagging ? DateTime.now() : null,
            flaggedBy: flagging ? widget.cswdId : null,
          );
        }
      }
    });

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update the record. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return WebShell(
      activePath: 'DataRetention',
      pageTitle: 'Data Retention',
      pageSubtitle: 'Old records that may be due for archival',
      role: widget.role,
      cswdId: widget.cswdId,
      displayName: widget.displayName,
      onLogout: () => WebSession.logout(context),
      onNavigate: (path) => WebNavigator.go(
        context,
        path,
        cswdId: widget.cswdId,
        role: widget.role,
        displayName: widget.displayName,
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.highlight),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RetentionSummaryCards(
                    counts: _summaryCounts,
                    selectedTier: _tierFilter,
                    onTierTap: (tier) => setState(() {
                      _tierFilter = _tierFilter == tier ? null : tier;
                    }),
                  ),
                  const SizedBox(height: 20),
                  _buildFilterBar(),
                  const SizedBox(height: 20),
                  Expanded(child: _buildTable()),
                ],
              ),
      ),
    );
  }

  Widget _buildFilterBar() {
    final formItems = ['All', ..._formTypes];
    final tierItems = ['All', ...RetentionConfig.tiersAscending.map((t) => t.label)];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          const Text(
            'Filter',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 16),
          WebDropdownFilter(
            value: _formTypeFilter,
            hint: 'All form types',
            items: formItems,
            labels: {
              for (final f in formItems) f: f == 'All' ? 'All form types' : f,
            },
            onChanged: (v) => setState(() => _formTypeFilter = v ?? 'All'),
          ),
          const SizedBox(width: 12),
          WebDropdownFilter(
            value: _tierFilter == null
                ? 'All'
                : RetentionConfig.thresholdFor(_tierFilter!)?.label ?? 'All',
            hint: 'All tiers',
            items: tierItems,
            labels: {for (final t in tierItems) t: t == 'All' ? 'All tiers' : t},
            onChanged: (v) => setState(() {
              if (v == null || v == 'All') {
                _tierFilter = null;
              } else {
                _tierFilter = RetentionConfig.tiersAscending
                    .firstWhere((t) => t.label == v)
                    .tier;
              }
            }),
          ),
          const Spacer(),
          Text(
            '${_visible.length} record${_visible.length == 1 ? '' : 's'}',
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh, color: AppColors.textMuted),
            tooltip: 'Refresh',
          ),
        ],
      ),
    );
  }

  Widget _buildTable() {
    final rows = _visible;
    if (rows.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 64,
              color: AppColors.textMuted.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            const Text(
              'No stale records match these filters',
              style: TextStyle(fontSize: 16, color: AppColors.textMuted),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: const BoxDecoration(
              color: AppColors.pageBg,
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: const Row(
              children: [
                Expanded(flex: 3, child: _HeaderCell('Reference')),
                Expanded(flex: 3, child: _HeaderCell('Form type')),
                Expanded(flex: 3, child: _HeaderCell('Last updated')),
                Expanded(flex: 2, child: _HeaderCell('Age')),
                Expanded(flex: 2, child: _HeaderCell('Tier')),
                Expanded(flex: 3, child: _HeaderCell('Action')),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.cardBorder),
          Expanded(
            child: ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: AppColors.cardBorder),
              itemBuilder: (_, i) => _buildRow(rows[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(StaleRecord record) {
    final threshold = RetentionConfig.thresholdFor(record.tier);
    final tierColor = threshold?.color ?? AppColors.textMuted;
    final tierLabel = threshold?.label ?? '—';
    final busy = _busyIds.contains(record.id.toString());
    final flagged = record.isFlaggedForArchival;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 3,
            child: Text(
              record.intakeReference,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              record.formType,
              style: const TextStyle(fontSize: 13, color: AppColors.textDark),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatDate(record.lastUpdated),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textDark,
                  ),
                ),
                Text(
                  record.usesEditTimestamp ? 'last edited' : 'created',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              RetentionConfig.formatAge(record.ageDays),
              style: const TextStyle(fontSize: 13, color: AppColors.textDark),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: tierColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  tierLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: tierColor,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _buildAction(record, busy: busy, flagged: flagged),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAction(
    StaleRecord record, {
    required bool busy,
    required bool flagged,
  }) {
    if (busy) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
      );
    }

    if (flagged) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.inventory_2,
            size: 16,
            color: AppColors.warningAmber,
          ),
          const SizedBox(width: 6),
          const Text(
            'Flagged',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.warningAmber,
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => _toggleFlag(record),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textMuted,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Undo', style: TextStyle(fontSize: 12)),
          ),
        ],
      );
    }

    return OutlinedButton.icon(
      onPressed: () => _toggleFlag(record),
      icon: const Icon(Icons.archive_outlined, size: 15),
      label: const Text('Flag for archival', style: TextStyle(fontSize: 12)),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primaryBlue,
        side: const BorderSide(color: AppColors.cardBorder),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final local = dt.toLocal();
    return '${months[local.month - 1]} ${local.day}, ${local.year}';
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.textMuted,
        letterSpacing: 0.5,
      ),
    );
  }
}
