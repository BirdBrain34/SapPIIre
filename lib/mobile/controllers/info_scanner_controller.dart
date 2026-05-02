import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:sappiire/models/id_information.dart';
import 'package:sappiire/services/supabase_service.dart';

class InfoScannerController extends ChangeNotifier {
  final SupabaseService _supabaseService = SupabaseService();

  bool isProcessing = false;
  bool frontScanned = false;
  bool backScanned = false;
  bool isInitialized = false;

  final IdInformation data = IdInformation(
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

  CameraController? cameraController;
  final TextRecognizer _textRecognizer = TextRecognizer();

  String? get currentUserId => _supabaseService.currentUserId;

  Future<void> setupCamera() async {

    final cameras = await availableCameras();
    if (cameras.isEmpty) return;
    cameraController = CameraController(
      cameras.first,
      ResolutionPreset.high,
      enableAudio: false,
    );
    try {
      await cameraController!.initialize();
      isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  Future<void> scanImage() async {
    if (isProcessing) return;
    isProcessing = true;
    notifyListeners();

    try {
      final XFile imageFile = await cameraController!.takePicture();
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

      if (!frontScanned) {
        _parseFront(lines);
        frontScanned = true;
      } else {
        _parseBack(lines);
        backScanned = true;
      }

      HapticFeedback.mediumImpact();
    } catch (e) {
      debugPrint('Scan error: $e');
      rethrow;
    } finally {
      isProcessing = false;
      notifyListeners();
    }
  }

  void _parseFront(List<String> lines) {
    for (int i = 0; i < lines.length; i++) {
      final lower = lines[i].toLowerCase();

      if (lower.contains('gitnang') ||
          lower.contains('middie name') ||
          lower.contains('middle name')) {
        final val = _valueAfter(lines, i);
        if (val.isNotEmpty) data.middleName = val;
      } else if ((lower.contains('apel') || lower.contains('last name')) &&
          !lower.contains('gitnang')) {
        final val = _valueAfter(lines, i);
        if (val.isNotEmpty) data.lastName = val;
      } else if (lower.contains('pangalan') || lower.contains('given name')) {
        final val = _valueAfter(lines, i);
        if (val.isNotEmpty) data.firstName = val;
      } else if (lower.contains('petsa ng kapanganakan') ||
          lower.contains('date of birth') ||
          (lower.contains('petsa') && !lower.contains('lugar')) ||
          lower.contains('retsa ng kapanganakan')) {
        if (i + 1 < lines.length) {
          final next = lines[i + 1].trim();
          if (next.isNotEmpty && !_isLabel(next) && !_isJunk(next)) {
            data.dateOfBirth = next;
          }
        }
      } else if (lower.contains('tirahan') ||
          lower == 'address' ||
          lower == 'tirahan/address') {
        final val = _addressValue(lines, i);
        if (val.isNotEmpty) data.address = val;
      }
    }
  }

  void _parseBack(List<String> lines) {
    for (int i = 0; i < lines.length; i++) {
      final lower = lines[i].toLowerCase();

      if (lower.contains('kasarian/sex') ||
          lower.contains('kasarian') ||
          (lower.contains('sex') &&
              !lower.contains('sibil') &&
              !lower.contains('marital'))) {
        if (i + 1 < lines.length) {
          final next = lines[i + 1].trim();
          if (next.isNotEmpty && !_isLabel(next) && !_isJunk(next)) {
            data.sex = next;
          }
        }
      } else if (lower.contains('uri ng dugo') ||
          lower.contains('blood type')) {
        if (i + 1 < lines.length) {
          final next = lines[i + 1].trim();
          if (next.isNotEmpty && !_isLabel(next) && !_isJunk(next)) {
            data.bloodType = next;
          }
        }
      } else if (lower.contains('sibil') || lower.contains('marital')) {
        if (data.bloodType.isEmpty) {
          final beforeLabel = lower.indexOf('sbil') != -1
              ? lines[i].substring(0, lower.indexOf('sbil')).trim()
              : lower.indexOf('sibil') != -1
              ? lines[i].substring(0, lower.indexOf('sibil')).trim()
              : '';
          if (beforeLabel.isNotEmpty && !_isJunk(beforeLabel)) {
            data.bloodType = beforeLabel;
          }
        }
        if (i + 1 < lines.length) {
          final next = lines[i + 1].trim();
          if (next.isNotEmpty && !_isLabel(next) && !_isJunk(next)) {
            data.maritalStatus = next;
          }
        }
      } else if (lower.contains('lugar ng kapanganakan') ||
          lower.contains('place of birth') ||
          lower.contains('piace of birth') ||
          lower.contains('kapanganakan/place') ||
          (lower.contains('lugar') && lower.contains('birth'))) {
        String inlineVal = '';
        for (final sep in ['/', ':']) {
          if (lines[i].contains(sep)) {
            final parts = lines[i].split(sep);
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
          data.placeOfBirth = inlineVal;
        } else {
          final parts = <String>[];
          for (int j = i + 1;
              j < lines.length && parts.length < 2;
              j++) {
            final next = lines[j].trim();
            if (next.isEmpty) continue;
            if (_isLabel(next) || _isJunk(next)) break;
            if (next == 'PHL') break;
            final nl = next.toLowerCase();
            if (nl == 'male' ||
                nl == 'female' ||
                nl == 'lalaki' ||
                nl == 'babae') break;
            parts.add(next);
          }
          if (parts.isNotEmpty) {
            data.placeOfBirth = parts.join(', ').trim();
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

  String _addressValue(List<String> lines, int i) {
    final List<String> collected = [];
    for (int j = i + 1; j < lines.length; j++) {
      final l = lines[j].trim();
      if (l.isEmpty) continue;
      if (_isLabel(l)) break;
      if (l == 'PHL') break;
      if (RegExp(r'^[0-9]{4}-[0-9]{4}').hasMatch(l)) continue;
      if (_isJunk(l)) continue;
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
      if (ll == 'male' || ll == 'female' || ll == 'lalaki' || ll == 'babae') {
        break;
      }
      collected.add(l);
      if (collected.length >= 3) break;
    }
    return collected.join(' ').trim();
  }

  bool _isLabel(String text) {
    final l = text.toLowerCase().trim();

    return l.contains('apelyido') ||
        l.contains('last name') ||
        l.contains('pangalan') ||
        l.contains('given name') ||
        l.contains('gitnang') ||
        l.contains('middle name') ||
        l.contains('petsa ng kapanganakan') ||
        l.contains('date of birth') ||
        l.contains('retsa ng kapanganakan') ||
        l.contains('tirahan') ||
        l == 'address' ||
        l.contains('kasarian/sex') ||
        l.contains('kasarian') ||
        l.contains('uri ng dugo') ||
        l.contains('blood type') ||
        l.contains('estadong sibil') ||
        l.contains('civil status') ||
        l.contains('marital status') ||
        l.contains('sibil') ||
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

  Future<void> saveToSupabase() async {
    final userId = _supabaseService.currentUserId;
    if (userId == null) {
      throw Exception('Not logged in.');
    }

    try {
      final sexValue = data.sex.isNotEmpty
          ? (data.sex.toLowerCase().startsWith('f') ? 'Female' : 'Male')
          : '';
      final civilValue = _civilStatusWord(data.maritalStatus);
      final dobFormatted = data.dateOfBirth.isNotEmpty
          ? (_parseDateOfBirth(data.dateOfBirth) ?? data.dateOfBirth)
          : '';

      final piiMap = <String, String>{
        if (data.lastName.isNotEmpty) 'last_name': data.lastName,
        if (data.firstName.isNotEmpty) 'first_name': data.firstName,
        if (data.middleName.isNotEmpty) 'middle_name': data.middleName,
        if (dobFormatted.isNotEmpty) 'date_of_birth': dobFormatted,
        if (sexValue.isNotEmpty) 'kasarian_sex': sexValue,
        if (civilValue.isNotEmpty) 'estadong_sibil_civil_status': civilValue,
        if (data.address.isNotEmpty)
          'house_number_street_name_phase_purok': data.address,
        if (data.placeOfBirth.isNotEmpty)
          'lugar_ng_kapanganakan_place_of_birth': data.placeOfBirth,
        if (data.placeOfBirth.isNotEmpty)
          'place_of_birth': data.placeOfBirth,
      };

      debugPrint('InfoScanner saving piiMap: $piiMap');

      final result = await _supabaseService.saveScannedIdFieldValues(
        userId: userId,
        canonicalValues: piiMap,
      );

      if (result['success'] != true) {
        throw Exception(result['message']?.toString() ?? 'Save failed.');
      }
    } catch (e) {
      debugPrint('Supabase save error: $e');
      rethrow;
    }
  }

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

  @override
  void dispose() {
    cameraController?.dispose();
    _textRecognizer.close();
    super.dispose();
  }
}
