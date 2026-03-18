import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sappiire/constants/app_colors.dart';
import 'package:sappiire/mobile/screens/auth/manage_info_screen.dart';
import 'package:sappiire/models/id_information.dart';

class InfoScannerScreen extends StatefulWidget {
  const InfoScannerScreen({super.key});

  @override
  State<InfoScannerScreen> createState() => _InfoScannerScreenState();
}

class _InfoScannerScreenState extends State<InfoScannerScreen> {
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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
                                color: Colors.white, strokeWidth: 2.5),
                          )
                        : const Icon(Icons.camera_alt,
                            color: Colors.white, size: 32),
                  ),
                ),
              ),
            ),

          // Re-scan back
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
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.refresh, color: Colors.white70),
                label: const Text('Re-scan Back',
                    style: TextStyle(color: Colors.white70)),
                onPressed: () => setState(() => _backScanned = false),
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
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.check, color: Colors.white),
                label: const Text(
                  'Confirm & Save',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
                onPressed: _saveToSupabase,
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
            .map((r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1.5),
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(
                          fontSize: 11, color: Colors.white70),
                      children: [
                        TextSpan(
                          text: '${r[0]}: ',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                        ),
                        TextSpan(text: r[1]),
                      ],
                    ),
                  ),
                ))
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

      // Show raw OCR lines in a dialog for on-device debugging
      if (mounted) {
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(!_frontScanned ? 'RAW OCR — Front' : 'RAW OCR — Back'),
            content: SingleChildScrollView(
              child: SelectableText(lines.join('\n')),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK — Continue'),
              ),
            ],
          ),
        );
      }

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

  void _parseFront(List<String> lines) {
    for (int i = 0; i < lines.length; i++) {
      final lower = lines[i].toLowerCase();

      // Middle name FIRST — "Gitnang Apelyido" contains "apelyido" so must check before last name
      if (lower.contains('gitnang') || lower.contains('middie name') || lower.contains('middle name')) {
        final val = _valueAfter(lines, i);
        if (val.isNotEmpty) _data.middleName = val;

      // Last name — exclude "Gitnang Apelyido" line
      } else if ((lower.contains('apel') || lower.contains('last name')) && !lower.contains('gitnang')) {
        final val = _valueAfter(lines, i);
        if (val.isNotEmpty) _data.lastName = val;

      // Given names
      } else if (lower.contains('pangalan') || lower.contains('given name')) {
        final val = _valueAfter(lines, i);
        if (val.isNotEmpty) _data.firstName = val;

      // Date of birth — OCR reads "Retsa" instead of "Petsa" sometimes
      } else if (lower.contains('kapanganakan') || lower.contains('date of birth') ||
          lower.contains('petsa') || lower.contains('retsa')) {
        // Value is on the NEXT line e.g. "ULY 22, 2004" (OCR drops the J)
        if (i + 1 < lines.length) {
          final next = lines[i + 1].trim();
          if (next.isNotEmpty && !_isLabel(next) && !_isJunk(next)) {
            _data.dateOfBirth = next;
          }
        }

      // Address — label line is "Tirahan/Address", value starts on next line
      // and spans multiple lines, stop before PHL or junk
      } else if (lower.contains('tirahan') || lower == 'address') {
        final val = _addressValue(lines, i);
        if (val.isNotEmpty) _data.address = val;
      }
    }
  }

  void _parseBack(List<String> lines) {
    // From OCR output, back lines look like:
    // "Kasarian/Sex"  → next line: "MALE"
    // "Uri ng Dugo/Blood Type"  → SOMETIMES merged with next label into one line
    // "SING Sbil/Marital Status" → blood type value merged in, marital on next line
    // "Lugar ng KapanganakaPiace of Birth" → next line: "CITY OF BINAN, LAGUNA"

    for (int i = 0; i < lines.length; i++) {
      final lower = lines[i].toLowerCase();

      // Sex — "Kasarian/Sex" then next line is value
      if (lower.contains('kasarian') || (lower.contains('sex') && !lower.contains('sibil'))) {
        if (i + 1 < lines.length) {
          final next = lines[i + 1].trim();
          if (next.isNotEmpty && !_isLabel(next) && !_isJunk(next)) {
            _data.sex = next;
          }
        }

      // Blood type — "Uri ng Dugo/Blood Type" then next line is value
      // BUT OCR sometimes merges blood type value WITH the next label line
      // e.g. "SING Sbil/Marital Status" means blood type was "SING" (= SINGLE cut off)
      // and next label is Sibil/Marital. So check next line: if it's a label, blood type
      // was missed. If it's a value, grab it.
      } else if (lower.contains('uri ng dugo') || lower.contains('blood type')) {
        if (i + 1 < lines.length) {
          final next = lines[i + 1].trim();
          if (next.isNotEmpty && !_isLabel(next) && !_isJunk(next)) {
            _data.bloodType = next;
          }
          // else blood type was swallowed — leave blank
        }

      // Marital status — "Sibil/Marital Status" or "SING Sbil/Marital Status"
      // The "SING" prefix is actually the blood type value OCR merged in
      } else if (lower.contains('sibil') || lower.contains('marital')) {
        // Extract blood type from prefix if present (e.g. "SING Sbil/Marital Status")
        if (_data.bloodType.isEmpty) {
          // Everything before the first letter of "Sibil" or "s" that starts the label
          final beforeLabel = lower.indexOf('sbil') != -1
              ? lines[i].substring(0, lower.indexOf('sbil')).trim()
              : lower.indexOf('sibil') != -1
                  ? lines[i].substring(0, lower.indexOf('sibil')).trim()
                  : '';
          if (beforeLabel.isNotEmpty) _data.bloodType = beforeLabel;
        }
        // Marital status value is on next line
        if (i + 1 < lines.length) {
          final next = lines[i + 1].trim();
          if (next.isNotEmpty && !_isLabel(next) && !_isJunk(next)) {
            _data.maritalStatus = next;
          }
        }

      // Place of birth — merged label like "Lugar ng KapanganakaPiace of Birth"
      // value is on next line
      } else if (lower.contains('lugar') || lower.contains('place of birth') || lower.contains('piace of birth')) {
        if (i + 1 < lines.length) {
          final next = lines[i + 1].trim();
          if (next.isNotEmpty && !_isLabel(next) && !_isJunk(next)) {
            _data.placeOfBirth = next;
          }
        }
      }
    }
  }

  String _valueAfter(List<String> lines, int i) {
    final line = lines[i];

    for (final sep in ['/', ':']) {
      if (line.contains(sep)) {
        final after = line.split(sep).last.trim();
        if (after.isNotEmpty && !_isLabel(after)) return after;
      }
    }

    if (i + 1 < lines.length) {
      final next = lines[i + 1].trim();
      if (next.isNotEmpty && !_isLabel(next) && !_isJunk(next)) return next;
    }

    return '';
  }

  String _multiLineValue(List<String> lines, int i) {
    final List<String> collected = [];
    int start = i + 1;
    for (int j = start; j < lines.length && j < i + 6; j++) {
      final l = lines[j].trim();
      if (_isLabel(l) || _isJunk(l) || l.isEmpty) break;
      collected.add(l);
    }
    return collected.join(' ').trim();
  }

  /// Address collector — from the OCR, address lines come AFTER the junk header lines.
  /// Structure observed: "Tirahan/Address" → junk lines → address lines → PHL
  /// So we SKIP junk lines and collect until we hit a label or PHL.
  String _addressValue(List<String> lines, int i) {
    final List<String> collected = [];
    bool pastJunk = false;
    for (int j = i + 1; j < lines.length && j < i + 12; j++) {
      final l = lines[j].trim();
      if (l.isEmpty) continue;
      if (_isLabel(l)) break; // next field started
      if (l == 'PHL' || RegExp(r'^[0-9]{4}-[0-9]{4}').hasMatch(l)) break;
      if (_isJunk(l)) {
        // Skip junk header lines (REPUBLIKA NG PILIPINAS etc)
        // but once we've seen real address content, stop
        if (pastJunk) break;
        continue;
      }
      pastJunk = true;
      collected.add(l);
    }
    return collected.join(' ').trim();
  }

  bool _isLabel(String text) {
    final l = text.toLowerCase();
    return l.contains('apelyido') ||
        l.contains('last name') ||
        l.contains('pangalan') ||
        l.contains('given name') ||
        l.contains('gitnang') ||
        l.contains('middle name') ||
        l.contains('petsa') ||
        l.contains('kapanganakan') ||
        l.contains('date of birth') ||
        l.contains('tirahan') ||
        l.contains('address') ||
        l.contains('kasarian') ||
        l.contains('sex') ||
        l.contains('uri ng dugo') ||
        l.contains('blood type') ||
        l.contains('sibil') ||
        l.contains('marital') ||
        l.contains('lugar') ||
        l.contains('place of birth');
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
        l.contains('phl') ||
        l.contains('found, please') ||
        l.contains('nearest');
  }

  Future<void> _saveToSupabase() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      _showSnack('Not logged in.', Colors.red);
      return;
    }

    try {
      await Supabase.instance.client.from('user_profiles').upsert({
        'user_id': userId,
        'lastname': _data.lastName,
        'firstname': _data.firstName,
        'middle_name': _data.middleName,
        'birthdate': _data.dateOfBirth.isNotEmpty
            ? _parseDateOfBirth(_data.dateOfBirth)
            : null,
        'gender': _data.sex.isNotEmpty
            ? (_data.sex.toLowerCase().startsWith('f') ? 'F' : 'M')
            : null,
        'blood_type': _data.bloodType.isNotEmpty ? _data.bloodType : null,
        'civil_status': _data.maritalStatus.isNotEmpty
            ? _civilStatusCode(_data.maritalStatus)
            : null,
        'birthplace': _data.placeOfBirth.isNotEmpty ? _data.placeOfBirth : null,
      }, onConflict: 'user_id');

      // Save address — check what column user_addresses uses
      if (_data.address.isNotEmpty) {
        // First get the profile_id since user_addresses links by profile_id
        final profile = await Supabase.instance.client
            .from('user_profiles')
            .select('profile_id')
            .eq('user_id', userId)
            .maybeSingle();

        if (profile != null) {
          await Supabase.instance.client.from('user_addresses').upsert({
            'profile_id': profile['profile_id'],
            'address_line': _data.address,
          }, onConflict: 'profile_id');
        }
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

  String? _civilStatusCode(String raw) {
    final l = raw.toLowerCase();
    if (l.contains('single')) return 'S';
    if (l.contains('married')) return 'M';
    if (l.contains('widow') || l.contains('widower')) return 'W';
    if (l.contains('separated')) return 'Sep';
    if (l.contains('annul')) return 'A';
    return null;
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }
}