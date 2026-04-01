// Customer-facing "Second Monitor" display screen.
//
// Accessed via the /display?station=<station_id> route.
// Shows a full-screen, high-contrast UI with:
//   • A large QR code when the worker has an active session
//   • A "Welcome / Standby" state otherwise
//
// Uses Supabase Realtime via DisplaySessionService to stay in sync
// with the Worker Dashboard.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/services/display_session_service.dart';

class CustomerDisplayScreen extends StatefulWidget {
  final String stationId;

  const CustomerDisplayScreen({super.key, required this.stationId});

  @override
  State<CustomerDisplayScreen> createState() => _CustomerDisplayScreenState();
}

class _CustomerDisplayScreenState extends State<CustomerDisplayScreen>
    with SingleTickerProviderStateMixin {
  final _displayService = DisplaySessionService();

  StreamSubscription? _subscription;

  String? _sessionId;
  String? _formName;
  String _status = 'standby'; // 'active' | 'standby'

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
      (row) {
        if (!mounted) return;
        debugPrint('\n=== CUSTOMER DISPLAY SCREEN: Realtime Update ===');
        debugPrint('Customer Display: This screen only shows QR code status');
        debugPrint('Customer Display: Form data goes to WORKER screen, not here');
        debugPrint('Customer Display: Row status: ${row?['status']}');
        debugPrint('Customer Display: Session ID: ${row?['session_id']}');
        debugPrint('Customer Display: Form name: ${row?['form_name']}');
        debugPrint('==============================================\n');
        
        setState(() {
          _status = row?['status'] ?? 'standby';
          _sessionId = row?['session_id'];
          _formName = row?['form_name'];
        });
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
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
        child: _status == 'active' && _sessionId != null
            ? _buildActiveView()
            : _buildStandbyView(),
      ),
    );
  }

  // ── Standby / Welcome ─────────────────────────────────────────────
  Widget _buildStandbyView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pulsing logo icon
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
                color: AppColors.highlight.withOpacity(0.15),
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
              color: Colors.white.withOpacity(0.6),
              fontSize: 20,
              fontWeight: FontWeight.w300,
            ),
          ),
          const SizedBox(height: 48),
          // Station badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
            ),
            child: Text(
              'Station: ${widget.stationId}',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 14,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Active session — show QR ──────────────────────────────────────
  Widget _buildActiveView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Status chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.successGreen.withOpacity(0.2),
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

          // Form name
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
              color: Colors.white.withOpacity(0.6),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 40),

          // ── QR code card ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: AppColors.highlight.withOpacity(0.25),
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
              color: Colors.white.withOpacity(0.35),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 48),

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

  Widget _instructionStep(String number, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppColors.highlight.withOpacity(0.2),
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
            color: Colors.white.withOpacity(0.5),
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
