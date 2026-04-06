import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/mobile/screens/auth/manage_info_screen.dart';
import 'package:sappiire/models/id_information.dart';
import 'package:sappiire/services/supabase_service.dart';

class InfoScannerScreen extends StatefulWidget {
  /// If true, tapping Confirm returns IdInformation to the caller
  /// instead of saving to Supabase (used during signup flow).
  final bool returnOnly;

  const InfoScannerScreen({super.key, this.returnOnly = false});

  @override
  State<InfoScannerScreen> createState() => _InfoScannerScreenState();
}

class _InfoScannerScreenState extends State<InfoScannerScreen> {
  final _supabaseService = SupabaseService();
  bool _isProcessing = false;
  bool _frontScanned = false;
  bool _backScanned = false;

  final IdInformation _data = IdInformation(
    lastName: '',
    firstName: '',
    middleName: '',
    address: '',
    dateOfBirth: '',
    sex: '',
    bloodType: '',
    maritalStatus: '',
    placeOfBirth: '',
  );

  CameraController? _controller;
  bool _isInitialized = false;
  final TextRecognizer _textRecognizer = TextRecognizer();

  @override
  void initState() {
    super.initState();
    _setupCamera();
  }

  Future<void> _setupCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;
    _controller = CameraController(
      cameras.first,
      ResolutionPreset.high,
      enableAudio: false,
    );
    try {
      await _controller!.initialize();
      if (mounted) setState(() => _isInitialized = true);
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _controller == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    final String stepLabel = !_frontScanned
        ? 'Step 1 of 2 — Scan FRONT of ID'
        : !_backScanned
            ? 'Step 2 of 2 — Scan BACK of ID'
            : 'All done! Review below.';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_controller!),
          _buildOverlayCutout(),

          // Close button
          Positioned(
            top: 48,
            left: 16,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // Step label
          Positioned(
            top: 52,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  stepLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),

          // Data summary
          Positioned(
            top: 100,
            left: 16,
            right: 16,
            child: _buildDataSummary(),
          ),

          // Instruction
          Positioned(
            bottom: 110,
            left: 16,
            right: 16,
            child: Text(
              !_frontScanned
                  ? 'Point camera at the FRONT of your Philippine National ID'
                  : !_backScanned
                      ? 'Now flip the ID and scan the BACK'
                      : 'Tap Confirm to save your information',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                shadows: [Shadow(blurRadius: 4, color: Colors.black)],
              ),
            ),
          ),

          // Scan button
          if (!_backScanned)
            Positioned(
              bottom: 28,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _isProcessing ? null : _scanImage,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primaryBlue,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: _isProcessing
                        ? const Padding(
                            padding: EdgeInsets.all(20),
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 32,
                          ),
                  ),
                ),
              ),
            ),

          // Re-scan Front
          if (_frontScanned && !_backScanned)
            Positioned(
              bottom: 110,
              left: 32,
              right: 32,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white54),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.refresh, color: Colors.white70),
                label: const Text(
                  'Re-scan Front',
                  style: TextStyle(color: Colors.white70),
                ),
                onPressed: () => setState(() {
                  _frontScanned = false;
                  _data.lastName = '';
                  _data.firstName = '';
                  _data.middleName = '';
                  _data.dateOfBirth = '';
                  _data.address = '';
                }),
              ),
            ),

          // Re-scan Back
          if (_backScanned)
            Positioned(
              bottom: 92,
              left: 32,
              right: 32,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white54),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.refresh, color: Colors.white70),
                label: const Text(
                  'Re-scan Back',
                  style: TextStyle(color: Colors.white70),
                ),
                onPressed: () => setState(() {
                  _backScanned = false;
                  _data.sex = '';
                  _data.bloodType = '';
                  _data.maritalStatus = '';
                  _data.placeOfBirth = '';
                }),
              ),
            ),

          // Confirm button
          if (_backScanned)
            Positioned(
              bottom: 28,
              left: 32,
              right: 32,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.check, color: Colors.white),
                label: const Text(
                  'Confirm & Save',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: () {
                  if (widget.returnOnly) {
                    Navigator.pop(context, _data);
                  } else {
                    _saveToSupabase();
                  }
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOverlayCutout() {
    return ColorFiltered(
      colorFilter: ColorFilter.mode(
        Colors.black.withOpacity(0.55),
        BlendMode.srcOut,
      ),
      child: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              color: Colors.black,
              backgroundBlendMode: BlendMode.dstOut,
            ),
          ),
          Center(
            child: Container(
              height: 210,
              width: 340,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataSummary() {
    final rows = [
      ['Last Name', _data.lastName],
      ['Given Name(s)', _data.firstName],
      ['Middle Name', _data.middleName],
      ['Date of Birth', _data.dateOfBirth],
      ['Address', _data.address],
      ['Sex', _data.sex],
      ['Blood Type', _data.bloodType],
      ['Marital Status', _data.maritalStatus],
      ['Place of Birth', _data.placeOfBirth],
    ].where((r) => r[1].isNotEmpty).toList();

    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.65),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows
            .map(
              (r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 1.5),
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                    children: [
                      TextSpan(
                        text: '${r[0]}: ',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      TextSpan(text: r[1]),
                    ],
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Future<void> _scanImage() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final XFile imageFile = await _controller!.takePicture();
      final inputImage = InputImage.fromFilePath(imageFile.path);
      final RecognizedText recognized =
          await _textRecognizer.processImage(inputImage);

      final List<String> lines = recognized.blocks
          .expand((b) => b.lines.map((l) => l.text.trim()))
          .where((l) => l.isNotEmpty)
          .toList();

      debugPrint('=== OCR LINES ===');
      for (final l in lines) debugPrint(l);
      debugPrint('=================');

      if (!_frontScanned) {
        _parseFront(lines);
        setState(() => _frontScanned = true);
        _showSnack('Front scanned — now flip to the back', Colors.blue);
      } else {
        _parseBack(lines);
        setState(() => _backScanned = true);
        _showSnack('Back scanned — review and confirm', Colors.green);
      }

      HapticFeedback.mediumImpact();
    } catch (e) {
      debugPrint('Scan error: $e');
      _showSnack('Scan failed. Try again.', Colors.red);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ── FRONT parser ──────────────────────────────────────────
  void _parseFront(List<String> lines) {
    for (int i = 0; i < lines.length; i++) {
      final lower = lines[i].toLowerCase();

      // Middle name FIRST — "Gitnang Apelyido" contains "apelyido"
      if (lower.contains('gitnang') ||
          lower.contains('middie name') ||
          lower.contains('middle name')) {
        final val = _valueAfter(lines, i);
        if (val.isNotEmpty) _data.middleName = val;

        // Last name — exclude "Gitnang Apelyido" line
      } else if ((lower.contains('apel') || lower.contains('last name')) &&
          !lower.contains('gitnang')) {
        final val = _valueAfter(lines, i);
        if (val.isNotEmpty) _data.lastName = val;

        // Given names
      } else if (lower.contains('pangalan') || lower.contains('given name')) {
        final val = _valueAfter(lines, i);
        if (val.isNotEmpty) _data.firstName = val;

        // Date of birth — label contains "petsa ng kapanganakan" or "date of birth"
        // Value is on the NEXT line
      } else if (lower.contains('petsa ng kapanganakan') ||
          lower.contains('date of birth') ||
          (lower.contains('petsa') && !lower.contains('lugar')) ||
          lower.contains('retsa ng kapanganakan')) {
        if (i + 1 < lines.length) {
          final next = lines[i + 1].trim();
          if (next.isNotEmpty && !_isLabel(next) && !_isJunk(next)) {
            _data.dateOfBirth = next;
          }
        }

        // Address — label is "Tirahan/Address", value starts on next line
      } else if (lower.contains('tirahan') ||
          lower == 'address' ||
          lower == 'tirahan/address') {
        final val = _addressValue(lines, i);
        if (val.isNotEmpty) _data.address = val;
      }
    }
  }

  // ── BACK parser ───────────────────────────────────────────
  void _parseBack(List<String> lines) {
    for (int i = 0; i < lines.length; i++) {
      final lower = lines[i].toLowerCase();

      // Sex — "Kasarian/Sex" then next line is value
      if (lower.contains('kasarian/sex') ||
          lower.contains('kasarian') ||
          (lower.contains('sex') &&
              !lower.contains('sibil') &&
              !lower.contains('marital'))) {
        if (i + 1 < lines.length) {
          final next = lines[i + 1].trim();
          if (next.isNotEmpty && !_isLabel(next) && !_isJunk(next)) {
            _data.sex = next;
          }
        }

        // Blood type — "Uri ng Dugo/Blood Type"
      } else if (lower.contains('uri ng dugo') ||
          lower.contains('blood type')) {
        if (i + 1 < lines.length) {
          final next = lines[i + 1].trim();
          if (next.isNotEmpty && !_isLabel(next) && !_isJunk(next)) {
            _data.bloodType = next;
          }
        }

        // Marital status — "Sibil/Marital Status" or "SING Sbil/Marital Status"
        // The "SING" prefix is blood type OCR merged in
      } else if (lower.contains('sibil') || lower.contains('marital')) {
        // Extract blood type from prefix if present
        if (_data.bloodType.isEmpty) {
          final beforeLabel = lower.indexOf('sbil') != -1
              ? lines[i].substring(0, lower.indexOf('sbil')).trim()
              : lower.indexOf('sibil') != -1
              ? lines[i].substring(0, lower.indexOf('sibil')).trim()
              : '';
          if (beforeLabel.isNotEmpty && !_isJunk(beforeLabel)) {
            _data.bloodType = beforeLabel;
          }
        }
        if (i + 1 < lines.length) {
          final next = lines[i + 1].trim();
          if (next.isNotEmpty && !_isLabel(next) && !_isJunk(next)) {
            _data.maritalStatus = next;
          }
        }

        // Place of birth — "Lugar ng Kapanganakan/Place of Birth"
        // FIX: more specific matching so front DOB label doesn't false-match
      } else if (lower.contains('lugar ng kapanganakan') ||
          lower.contains('place of birth') ||
          lower.contains('piace of birth') ||
          lower.contains('kapanganakan/place') ||
          (lower.contains('lugar') && lower.contains('birth'))) {
        // Try inline value first (after slash or colon)
        String inlineVal = '';
        for (final sep in ['/', ':']) {
          if (lines[i].contains(sep)) {
            final parts = lines[i].split(sep);
            // Take the last segment that's not the label itself
            for (int p = parts.length - 1; p >= 0; p--) {
              final after = parts[p].trim();
              if (after.isNotEmpty &&
                  !_isLabel(after) &&
                  !_isJunk(after) &&
                  after.length > 2 &&
                  !after.toLowerCase().contains('lugar') &&
                  !after.toLowerCase().contains('place') &&
                  !after.toLowerCase().contains('kapanganakan')) {
                inlineVal = after;
                break;
              }
            }
            if (inlineVal.isNotEmpty) break;
          }
        }

        if (inlineVal.isNotEmpty) {
          _data.placeOfBirth = inlineVal;
        } else {
          // Collect next 1–2 lines (city/province may span two lines)
          final parts = <String>[];
          for (int j = i + 1;
              j < lines.length && parts.length < 2;
              j++) {
            final next = lines[j].trim();
            if (next.isEmpty) continue;
            if (_isLabel(next) || _isJunk(next)) break;
            if (next == 'PHL') break;
            // Stop if we hit a clearly different field value (sex/blood type)
            final nl = next.toLowerCase();
            if (nl == 'male' ||
                nl == 'female' ||
                nl == 'lalaki' ||
                nl == 'babae') break;
            parts.add(next);
          }
          if (parts.isNotEmpty) {
            _data.placeOfBirth = parts.join(', ').trim();
          }
        }
      }
    }
  }

  // ── Value helpers ─────────────────────────────────────────
  String _valueAfter(List<String> lines, int i) {
    final line = lines[i];

    for (final sep in ['/', ':']) {
      if (line.contains(sep)) {
        final after = line.split(sep).last.trim();
        if (after.isNotEmpty && !_isLabel(after) && after.length > 1) {
          return after;
        }
      }
    }

    if (i + 1 < lines.length) {
      final next = lines[i + 1].trim();
      if (next.isNotEmpty && !_isLabel(next) && !_isJunk(next)) return next;
    }

    return '';
  }

  /// Address collector — scans lines after the label.
  /// FIX: made _isLabel more specific so address lines aren't
  /// cut short by partial label matches.
  String _addressValue(List<String> lines, int i) {
    final List<String> collected = [];
    for (int j = i + 1; j < lines.length; j++) {
      final l = lines[j].trim();
      if (l.isEmpty) continue;
      if (_isLabel(l)) break;
      if (l == 'PHL') break;
      // Skip ID number pattern
      if (RegExp(r'^[0-9]{4}-[0-9]{4}').hasMatch(l)) continue;
      if (_isJunk(l)) continue;
      // Skip background garbage text
      final ll = l.toLowerCase();
      if (ll.contains('examination') ||
          ll.contains('booklet') ||
          ll.contains('reserved') ||
          ll.contains('mapua') ||
          ll.contains('mmcl') ||
          ll.contains('rights') ||
          ll.contains('exclusively') ||
          ll.contains('distributed') ||
          ll.contains('property') ||
          ll.contains('university')) continue;
      // Stop if we reach sex/back-of-ID values
      if (ll == 'male' || ll == 'female' || ll == 'lalaki' || ll == 'babae') {
        break;
      }
      collected.add(l);
      // Max 3 lines for address
      if (collected.length >= 3) break;
    }
    return collected.join(' ').trim();
  }

  // ── Label detection — SPECIFIC matches to avoid false positives ──
  bool _isLabel(String text) {
    final l = text.toLowerCase().trim();

    // Exact or very specific label patterns only
    // Using 'contains' only for multi-word labels that won't appear in values
    return l.contains('apelyido') ||
        l.contains('last name') ||
        l.contains('pangalan') ||
        l.contains('given name') ||
        l.contains('gitnang') ||
        l.contains('middle name') ||
        // DOB label — must contain 'petsa ng' or 'date of birth' (not just 'petsa')
        l.contains('petsa ng kapanganakan') ||
        l.contains('date of birth') ||
        l.contains('retsa ng kapanganakan') ||
        // Address label — full label or exact 'address'
        l.contains('tirahan') ||
        l == 'address' ||
        // Back labels — specific combos
        l.contains('kasarian/sex') ||
        l.contains('kasarian') ||
        l.contains('uri ng dugo') ||
        l.contains('blood type') ||
        l.contains('estadong sibil') ||
        l.contains('civil status') ||
        l.contains('marital status') ||
        l.contains('sibil') ||
        // Place of birth label — must be the full label phrase
        l.contains('lugar ng kapanganakan') ||
        l.contains('place of birth') ||
        l.contains('piace of birth');
  }

  bool _isJunk(String text) {
    final l = text.toLowerCase();
    return l.contains('republika') ||
        l.contains('pilipinas') ||
        l.contains('republic') ||
        l.contains('philippine') ||
        l.contains('identification') ||
        l.contains('pambansang') ||
        l.contains('pagkakakilanlan') ||
        l.contains('authority') ||
        l.contains('psa.gov') ||
        l == 'phl' ||
        l.contains('found, please') ||
        l.contains('nearest');
  }

  // ── Save to Supabase ──────────────────────────────────────
  Future<void> _saveToSupabase() async {
    final userId = _supabaseService.currentUserId;
    if (userId == null) {
      _showSnack('Not logged in.', Colors.red);
      return;
    }

    try {
      final sexValue = _data.sex.isNotEmpty
          ? (_data.sex.toLowerCase().startsWith('f') ? 'Female' : 'Male')
          : '';
      final civilValue = _civilStatusWord(_data.maritalStatus);
      final dobFormatted = _data.dateOfBirth.isNotEmpty
          ? (_parseDateOfBirth(_data.dateOfBirth) ?? _data.dateOfBirth)
          : '';

      // Build canonical map — only include non-empty values
      final piiMap = <String, String>{
        if (_data.lastName.isNotEmpty) 'last_name': _data.lastName,
        if (_data.firstName.isNotEmpty) 'first_name': _data.firstName,
        if (_data.middleName.isNotEmpty) 'middle_name': _data.middleName,
        if (dobFormatted.isNotEmpty) 'date_of_birth': dobFormatted,
        if (sexValue.isNotEmpty) 'kasarian_sex': sexValue,
        if (civilValue.isNotEmpty) 'estadong_sibil_civil_status': civilValue,
        if (_data.address.isNotEmpty)
          'house_number_street_name_phase_purok': _data.address,
        // Place of birth — saved under both canonical keys for coverage
        if (_data.placeOfBirth.isNotEmpty)
          'lugar_ng_kapanganakan_place_of_birth': _data.placeOfBirth,
        if (_data.placeOfBirth.isNotEmpty)
          'place_of_birth': _data.placeOfBirth,
      };

      debugPrint('InfoScanner saving piiMap: $piiMap');

      final result = await _supabaseService.saveScannedIdFieldValues(
        userId: userId,
        canonicalValues: piiMap,
      );

      if (result['success'] != true) {
        _showSnack(
          result['message']?.toString() ?? 'Save failed.',
          Colors.red,
        );
        return;
      }

      if (!mounted) return;
      _showSnack('Information saved!', Colors.green);
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ManageInfoScreen(userId: userId),
        ),
      );
    } catch (e) {
      debugPrint('Supabase save error: $e');
      _showSnack('Save failed: $e', Colors.red);
    }
  }

  /// Tries to parse OCR date text into yyyy-MM-dd for Supabase date column.
  String? _parseDateOfBirth(String raw) {
    try {
      if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) return raw;
      if (RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(raw)) {
        final parts = raw.split('/');
        return '${parts[2]}-${parts[0]}-${parts[1]}';
      }
      final months = {
        'january': '01', 'jan': '01', 'february': '02', 'feb': '02',
        'march': '03', 'mar': '03', 'april': '04', 'apr': '04',
        'may': '05', 'june': '06', 'jun': '06', 'july': '07', 'jul': '07',
        'august': '08', 'aug': '08', 'september': '09', 'sep': '09',
        'october': '10', 'oct': '10', 'november': '11', 'nov': '11',
        'december': '12', 'dec': '12',
        // Handle OCR misreads of month names
        'ul': '07', 'uly': '07', 'une': '06', 'arch': '03',
        'ebruary': '02', 'pril': '04', 'ugust': '08',
        'eptember': '09', 'ctober': '10', 'ovember': '11', 'ecember': '12',
      };
      final clean = raw.replaceAll(',', '').trim();
      final parts = clean.split(RegExp(r'\s+'));
      if (parts.length >= 3) {
        String? month, day, year;
        for (final p in parts) {
          final pl = p.toLowerCase().replaceAll('.', '');
          if (months.containsKey(pl)) {
            month = months[pl];
          } else if (p.length == 4 && int.tryParse(p) != null) {
            year = p;
          } else if (p.length <= 2 && int.tryParse(p) != null) {
            day = p.padLeft(2, '0');
          }
        }
        if (month != null && day != null && year != null) {
          return '$year-$month-$day';
        }
      }
    } catch (_) {}
    return null;
  }

  String _civilStatusWord(String raw) {
    final l = raw.toLowerCase();
    if (l.contains('single')) return 'Single';
    if (l.contains('married')) return 'Married';
    if (l.contains('widow') || l.contains('widower')) return 'Widowed';
    if (l.contains('separated')) return 'Separated';
    if (l.contains('annul')) return 'Annulled';
    return raw;
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }
}