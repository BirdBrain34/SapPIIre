/// Customer-facing second monitor display.
///
/// The screen listens to Supabase Realtime for station updates and switches
/// between a standby view, a QR view for the current form session, and a
/// read-only "review" view that mirrors the applicant's autofilled form once
/// their scan data arrives — so the customer can double-check their details.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/dynamic_form/dynamic_form_renderer.dart';
import 'package:sappiire/dynamic_form/form_state_controller.dart';
import 'package:sappiire/models/form_template_models.dart';
import 'package:sappiire/services/display_session_service.dart';
import 'package:sappiire/services/form_template_service.dart';
import 'package:sappiire/services/forms/submission_service.dart';

class CustomerDisplayScreen extends StatefulWidget {
  final String stationId;

  const CustomerDisplayScreen({super.key, required this.stationId});

  @override
  State<CustomerDisplayScreen> createState() => _CustomerDisplayScreenState();
}

class _CustomerDisplayScreenState extends State<CustomerDisplayScreen>
    with SingleTickerProviderStateMixin {
  final _displayService = DisplaySessionService();
  final _submissionService = SubmissionService();
  final _templateService = FormTemplateService();

  StreamSubscription? _subscription; // station row (display_sessions)
  StreamSubscription? _sessionSub; // active session row (form_submission)
  Timer? _pollTimer; // backup poll for the scan (realtime is unreliable here)
  Timer? _countdownTimer;

  String? _sessionId;
  String? _templateId;
  String? _formName;
  String _status = 'standby'; // 'active' | 'standby'

  // Expiry countdown
  Duration _timeRemaining = Duration.zero;
  bool _sessionExpired = false;

  // Review ("mirror") state — populated once the applicant's scan arrives so
  // the customer can verify the autofilled form on their own monitor.
  bool _showReview = false;
  bool _loadingReview = false;
  String? _reviewedSessionId;
  FormTemplate? _reviewTemplate;
  FormStateController? _reviewController;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _startListening();
  }

  void _startListening() {
    _subscription = _displayService.listenStation(
      widget.stationId,
      _onStationUpdate,
    );
  }

  /// Handle a station (display_sessions) update: drive the QR/standby state and
  /// (re)subscribe to the active session so we can react to its scan result.
  void _onStationUpdate(Map<String, dynamic>? row) {
    if (!mounted) return;
    final status = row?['status'] as String? ?? 'standby';
    final sessionId = row?['session_id'] as String?;
    final templateId = row?['template_id'] as String?;
    final formName = row?['form_name'] as String?;

    debugPrint(
      '[CustomerDisplayScreen/_onStationUpdate] status=$status sessionId=$sessionId',
    );

    // Session ended / reset → clear everything back to the standby welcome.
    if (status != 'active' || sessionId == null) {
      _sessionSub?.cancel();
      _sessionSub = null;
      _pollTimer?.cancel();
      _pollTimer = null;
      _stopCountdown();
      _clearReview();
      setState(() {
        _status = 'standby';
        _sessionId = null;
        _templateId = null;
        _formName = null;
      });
      return;
    }

    final isNewSession = sessionId != _sessionId;
    setState(() {
      _status = status;
      _sessionId = sessionId;
      _templateId = templateId;
      _formName = formName;
    });

    // A new active session starts on the QR view; watch for its scan result.
    if (isNewSession) {
      _clearReview();
      _subscribeToSession(sessionId);
      // Fetch expires_at and start countdown
      _submissionService.fetchSessionExpiresAt(sessionId).then((expiresAt) {
        if (expiresAt != null && mounted) _startCountdown(expiresAt);
      });
    }
  }

  void _startCountdown(DateTime expiresAt) {
    _countdownTimer?.cancel();
    setState(() {
      _timeRemaining = expiresAt.difference(DateTime.now());
      _sessionExpired = _timeRemaining.isNegative;
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      final remaining = expiresAt.difference(DateTime.now());
      if (remaining.isNegative || remaining == Duration.zero) {
        timer.cancel();
        setState(() {
          _timeRemaining = Duration.zero;
          _sessionExpired = true;
        });
      } else {
        setState(() => _timeRemaining = remaining);
      }
    });
  }

  void _stopCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _timeRemaining = Duration.zero;
    _sessionExpired = false;
  }

  String _formatCountdown(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// Watch the active session's form_submission row for the applicant's scan.
  ///
  /// Realtime on form_submission is unreliable (the worker dashboard polls for
  /// the same reason), so we use the realtime stream as the primary signal and
  /// a snapshot poll as the backup.
  void _subscribeToSession(String sessionId) {
    _sessionSub?.cancel();
    _pollTimer?.cancel();

    // Primary: realtime stream. Emits the current row on subscribe, then updates.
    _sessionSub = _submissionService.streamSession(sessionId).listen(
      (rows) {
        if (!mounted || rows.isEmpty) return;
        _maybeReviewFromStatus(rows.first['status'] as String?, sessionId);
      },
      onError: (e) {
        debugPrint('[CustomerDisplayScreen/_subscribeToSession] Stream error: $e');
      },
      cancelOnError: false,
    );

    // Backup: poll the session snapshot until the scan arrives.
    _pollSession(sessionId);
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted ||
          _sessionId != sessionId ||
          _reviewedSessionId == sessionId) {
        timer.cancel();
        return;
      }
      _pollSession(sessionId);
    });
  }

  Future<void> _pollSession(String sessionId) async {
    try {
      final row = await _submissionService.fetchSessionSnapshot(sessionId);
      if (!mounted || row == null) return;
      _maybeReviewFromStatus(row['status'] as String?, sessionId);
    } catch (e) {
      debugPrint('[CustomerDisplayScreen/_pollSession] Error: $e');
    }
  }

  /// Trigger the review load once the applicant's scan lands (status='scanned').
  void _maybeReviewFromStatus(String? status, String sessionId) {
    if (status == 'scanned' &&
        _reviewedSessionId != sessionId &&
        !_loadingReview) {
      _loadReview(sessionId, _templateId);
    }
  }

  /// Decrypt the scanned session and build a read-only mirror of the form.
  ///
  /// Reuses the same decrypt + render path the worker dashboard uses
  /// (serve-submission-for-review Edge Function + DynamicFormRenderer).
  Future<void> _loadReview(String sessionId, String? templateId) async {
    if (templateId == null || templateId.isEmpty) {
      debugPrint('[CustomerDisplayScreen/_loadReview] Skipped — no templateId');
      return;
    }

    debugPrint(
      '[CustomerDisplayScreen/_loadReview] Loading mirror session=$sessionId templateId=$templateId',
    );
    setState(() {
      _showReview = true;
      _loadingReview = true;
    });

    try {
      final staffId = _staffIdFromStation(widget.stationId);
      final template = await _templateService.fetchTemplate(templateId);
      final decrypted = await _submissionService.fetchDecryptedStagingSubmission(
        sessionId: sessionId,
        staffId: staffId,
      );

      debugPrint(
        '[CustomerDisplayScreen/_loadReview] template=${template?.templateId} decryptedKeys=${decrypted?.keys.toList()}',
      );

      if (!mounted) return;

      // Fail safe: never surface a raw error to the customer — fall back to QR.
      if (template == null || decrypted == null || decrypted.isEmpty) {
        debugPrint(
          '[CustomerDisplayScreen/_loadReview] Decrypt/template unavailable — staying on QR',
        );
        _clearReview();
        return;
      }

      final controller = FormStateController(template: template)
        ..loadFromJson(decrypted);
      _reviewController?.dispose();
      setState(() {
        _reviewTemplate = template;
        _reviewController = controller;
        _reviewedSessionId = sessionId;
        _loadingReview = false;
        _showReview = true;
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('[CustomerDisplayScreen/_loadReview] Error: $e');
      _clearReview();
    }
  }

  void _clearReview() {
    _reviewController?.dispose();
    _reviewController = null;
    _reviewTemplate = null;
    _reviewedSessionId = null;
    if (mounted) {
      setState(() {
        _showReview = false;
        _loadingReview = false;
      });
    } else {
      _showReview = false;
      _loadingReview = false;
    }
  }

  /// Station ids are formatted as `desk_<cswd_id>`; the staff id is the suffix.
  String _staffIdFromStation(String stationId) {
    const prefix = 'desk_';
    return stationId.startsWith(prefix)
        ? stationId.substring(prefix.length)
        : stationId;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _sessionSub?.cancel();
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    _reviewController?.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Pick the view: review mirror > active QR > standby welcome.
    final Widget body;
    if (_showReview) {
      body = _buildReviewView();
    } else if (_status == 'active' && _sessionId != null) {
      body = _buildActiveView();
    } else {
      body = _buildStandbyView();
    }

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0A1628), Color(0xFF0D1B4E), Color(0xFF132B6E)],
          ),
        ),
        child: body,
      ),
    );
  }

  Widget _buildStandbyView() {
    // Show the waiting screen while the station is idle.
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Show a subtle pulse while the station is waiting.
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (context, child) => Opacity(
              opacity: _pulseAnim.value,
              child: child,
            ),
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: AppColors.highlight.withValues(alpha:  0.15),
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Icon(
                Icons.qr_code_2_rounded,
                size: 64,
                color: AppColors.highlight,
              ),
            ),
          ),
          const SizedBox(height: 48),
          const Text(
            'Welcome',
            style: TextStyle(
              color: Colors.white,
              fontSize: 48,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Please wait for the staff to start your session.',
            style: TextStyle(
              color: Colors.white.withValues(alpha:  0.6),
              fontSize: 20,
              fontWeight: FontWeight.w300,
            ),
          ),
          const SizedBox(height: 48),
          // Show the station identifier so staff can confirm the active monitor.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha:  0.08),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white.withValues(alpha:  0.12)),
            ),
            child: Text(
              'Station: ${widget.stationId}',
              style: TextStyle(
                color: Colors.white.withValues(alpha:  0.5),
                fontSize: 14,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveView() {
    // Show the QR code and session details when a session is active.
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Show the active session state above the QR code.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.successGreen.withValues(alpha:  0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.successGreen,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Session Active',
                  style: TextStyle(
                    color: AppColors.successGreen,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Show the form name so the customer knows which intake is active.
          if (_formName != null)
            Text(
              _formName!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          const SizedBox(height: 12),

          Text(
            'Scan the QR code below with the SapPIIre app',
            style: TextStyle(
              color: Colors.white.withValues(alpha:  0.6),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 40),

          // QR code card
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: AppColors.highlight.withValues(alpha:  0.25),
                  blurRadius: 60,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: QrImageView(
              data: _sessionId!,
              version: QrVersions.auto,
              size: 280,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Color(0xFF0D1B4E),
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Color(0xFF0D1B4E),
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Session ID hint
          Text(
            'Session: ${_sessionId!.split('-').first}...',
            style: TextStyle(
              color: Colors.white.withValues(alpha:  0.35),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),

          // Expiry countdown — large and prominent for the customer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: _sessionExpired
                  ? Colors.red.withValues(alpha:  0.15)
                  : _timeRemaining.inMinutes < 5
                      ? Colors.orange.withValues(alpha:  0.15)
                      : Colors.white.withValues(alpha:  0.08),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: _sessionExpired
                    ? Colors.red.withValues(alpha:  0.4)
                    : _timeRemaining.inMinutes < 5
                        ? Colors.orange.withValues(alpha:  0.4)
                        : Colors.white.withValues(alpha:  0.15),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _sessionExpired ? Icons.timer_off_rounded : Icons.timer_rounded,
                  color: _sessionExpired
                      ? Colors.red
                      : _timeRemaining.inMinutes < 5
                          ? Colors.orange
                          : Colors.white60,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(
                  _sessionExpired
                      ? 'Session Expired'
                      : 'Expires in ${_formatCountdown(_timeRemaining)}',
                  style: TextStyle(
                    color: _sessionExpired
                        ? Colors.red
                        : _timeRemaining.inMinutes < 5
                            ? Colors.orange
                            : Colors.white60,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Instructions row
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _instructionStep('1', 'Open SapPIIre app'),
              const SizedBox(width: 32),
              _instructionStep('2', 'Select fields to share'),
              const SizedBox(width: 32),
              _instructionStep('3', 'Scan this QR code'),
            ],
          ),
        ],
      ),
    );
  }

  /// Read-only "mirror" of the applicant's autofilled form, shown after the scan
  /// so the customer can confirm their details are correct.
  Widget _buildReviewView() {
    if (_loadingReview ||
        _reviewController == null ||
        _reviewTemplate == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.highlight),
            SizedBox(height: 24),
            Text(
              'Loading your details…',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w300,
              ),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 32),
          const Text(
            'Please confirm your details',
            style: TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Check that the information below is correct.',
            style: TextStyle(
              color: Colors.white.withValues(alpha:  0.6),
              fontSize: 18,
              fontWeight: FontWeight.w300,
            ),
          ),
          if (_formName != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.highlight.withValues(alpha:  0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _formName!,
                style: const TextStyle(
                  color: AppColors.highlight,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: DynamicFormRenderer(
                    template: _reviewTemplate!,
                    controller: _reviewController!,
                    mode: 'web',
                    isReadOnly: true,
                    showCheckboxes: false,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _instructionStep(String number, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppColors.highlight.withValues(alpha:  0.2),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            number,
            style: const TextStyle(
              color: AppColors.highlight,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            color: Colors.white.withValues(alpha:  0.5),
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
