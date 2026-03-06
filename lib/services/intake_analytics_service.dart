import 'package:flutter/foundation.dart';import 'package:supabase_flutter/supabase_flutter.dart';

class IntakeAnalyticsService {
  static final IntakeAnalyticsService _instance =
      IntakeAnalyticsService._internal();

  factory IntakeAnalyticsService() {
    return _instance;
  }

  IntakeAnalyticsService._internal();

  final _supabase = Supabase.instance.client;

  /// Fetch all General Intake submissions
  Future<List<Map<String, dynamic>>> fetchIntakeSubmissions() async {
    try {
      final response = await _supabase
          .from('client_submissions')
          .select('id, form_type, data, created_at')
          .eq('form_type', 'General Intake Sheet')
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error fetching intake submissions: $e');
      return [];
    }
  }

  /// Get total count of submissions
  Future<int> getTotalSubmissions() async {
    final submissions = await fetchIntakeSubmissions();
    return submissions.length;
  }

  /// Analyze gender distribution from "Kasarian" field
  Future<Map<String, int>> getGenderDistribution() async {
    final submissions = await fetchIntakeSubmissions();
    final distribution = <String, int>{};

    for (final submission in submissions) {
      final data = submission['data'] as Map<String, dynamic>? ?? {};
      final gender = _findFieldValue(data, 'Kasarian')?.toString().trim() ?? '';

      if (gender.isNotEmpty) {
        distribution[gender] = (distribution[gender] ?? 0) + 1;
      }
    }

    return distribution;
  }

  /// Analyze age distribution and youth count (17 and below)
  Future<Map<String, int>> getAgeGroupDistribution() async {
    final submissions = await fetchIntakeSubmissions();
    final distribution = {
      'Youth (≤17)': 0,
      'Young Adult (18-25)': 0,
      'Adult (26-40)': 0,
      'Middle Age (41-60)': 0,
      'Senior (61+)': 0,
    };

    int? parseAge(String ageStr) {
      try {
        return int.parse(ageStr.trim());
      } catch (e) {
        return null;
      }
    }

    for (final submission in submissions) {
      final data = submission['data'] as Map<String, dynamic>? ?? {};
      final ageStr = _findFieldValue(data, 'Age')?.toString() ?? '';

      final age = parseAge(ageStr);
      if (age != null) {
        if (age <= 17) {
          distribution['Youth (≤17)'] = distribution['Youth (≤17)']! + 1;
        } else if (age <= 25) {
          distribution['Young Adult (18-25)'] =
              distribution['Young Adult (18-25)']! + 1;
        } else if (age <= 40) {
          distribution['Adult (26-40)'] = distribution['Adult (26-40)']! + 1;
        } else if (age <= 60) {
          distribution['Middle Age (41-60)'] =
              distribution['Middle Age (41-60)']! + 1;
        } else {
          distribution['Senior (61+)'] = distribution['Senior (61+)']! + 1;
        }
      }
    }

    return distribution;
  }

  /// Get youth count (age 17 and below)
  Future<int> getYouthCount() async {
    final ageGroups = await getAgeGroupDistribution();
    return ageGroups['Youth (≤17)'] ?? 0;
  }

  /// Analyze income distribution into brackets
  Future<Map<String, int>> getIncomeDistribution() async {
    final submissions = await fetchIntakeSubmissions();
    final distribution = {
      'Below ₱5,000': 0,
      '₱5,000 - ₱10,000': 0,
      '₱10,000 - ₱20,000': 0,
      '₱20,000 - ₱50,000': 0,
      'Above ₱50,000': 0,
      'No Income Data': 0,
    };

    double? parseIncome(String incomeStr) {
      try {
        // Remove currency symbols and commas
        final cleaned = incomeStr
            .replaceAll('₱', '')
            .replaceAll(',', '')
            .replaceAll(RegExp(r'[^\d.]'), '')
            .trim();
        return double.parse(cleaned);
      } catch (e) {
        return null;
      }
    }

    for (final submission in submissions) {
      final data = submission['data'] as Map<String, dynamic>? ?? {};
      final incomeStr = _findFieldValue(data, 'Buwanang Kita (A)')?.toString() ?? '';

      if (incomeStr.isEmpty) {
        distribution['No Income Data'] = distribution['No Income Data']! + 1;
      } else {
        final income = parseIncome(incomeStr);
        if (income != null) {
          if (income < 5000) {
            distribution['Below ₱5,000'] = distribution['Below ₱5,000']! + 1;
          } else if (income < 10000) {
            distribution['₱5,000 - ₱10,000'] =
                distribution['₱5,000 - ₱10,000']! + 1;
          } else if (income < 20000) {
            distribution['₱10,000 - ₱20,000'] =
                distribution['₱10,000 - ₱20,000']! + 1;
          } else if (income < 50000) {
            distribution['₱20,000 - ₱50,000'] =
                distribution['₱20,000 - ₱50,000']! + 1;
          } else {
            distribution['Above ₱50,000'] = distribution['Above ₱50,000']! + 1;
          }
        } else {
          distribution['No Income Data'] = distribution['No Income Data']! + 1;
        }
      }
    }

    return distribution;
  }

  /// Analyze membership status (4Ps, PWD, Solo Parent, PHIC)
  Future<Map<String, int>> getMembershipDistribution() async {
    final submissions = await fetchIntakeSubmissions();
    final distribution = {
      '4Ps Member': 0,
      'PWD': 0,
      'Solo Parent': 0,
      'PHIC Member': 0,
      'None': 0,
    };

    for (final submission in submissions) {
      final data = submission['data'] as Map<String, dynamic>? ?? {};
      final membershipData =
          data['__membership'] as Map<String, dynamic>? ?? {};

      bool hasMembership = false;

      if (membershipData['four_ps_member'] == true) {
        distribution['4Ps Member'] = distribution['4Ps Member']! + 1;
        hasMembership = true;
      }
      if (membershipData['pwd'] == true) {
        distribution['PWD'] = distribution['PWD']! + 1;
        hasMembership = true;
      }
      if (membershipData['solo_parent'] == true) {
        distribution['Solo Parent'] = distribution['Solo Parent']! + 1;
        hasMembership = true;
      }
      if (membershipData['phic_member'] == true) {
        distribution['PHIC Member'] = distribution['PHIC Member']! + 1;
        hasMembership = true;
      }

      if (!hasMembership) {
        distribution['None'] = distribution['None']! + 1;
      }
    }

    return distribution;
  }

  /// Analyze employment status
  Future<Map<String, int>> getEmploymentDistribution() async {
    final submissions = await fetchIntakeSubmissions();
    final distribution = <String, int>{};

    for (final submission in submissions) {
      final data = submission['data'] as Map<String, dynamic>? ?? {};
      final employment =
          _findFieldValue(data, 'Trabaho/Pinagkakakitaan')?.toString().trim() ?? '';

      if (employment.isEmpty) {
        distribution['No Data'] = (distribution['No Data'] ?? 0) + 1;
      } else {
        distribution[employment] = (distribution[employment] ?? 0) + 1;
      }
    }

    return distribution;
  }

  /// Analyze educational attainment
  Future<Map<String, int>> getEducationDistribution() async {
    final submissions = await fetchIntakeSubmissions();
    final distribution = <String, int>{};

    for (final submission in submissions) {
      final data = submission['data'] as Map<String, dynamic>? ?? {};
      final education = _findFieldValue(data, 'Natapos o naabot sa pag-aaral')
          ?.toString()
          .trim() ?? '';

      if (education.isEmpty) {
        distribution['No Data'] = (distribution['No Data'] ?? 0) + 1;
      } else {
        distribution[education] = (distribution[education] ?? 0) + 1;
      }
    }

    return distribution;
  }

  /// Analyze housing status
  Future<Map<String, int>> getHousingDistribution() async {
    final submissions = await fetchIntakeSubmissions();
    final distribution = <String, int>{};

    for (final submission in submissions) {
      final data = submission['data'] as Map<String, dynamic>? ?? {};
      final housing = data['__housing_status']?.toString().trim() ?? 'Not Specified';

      distribution[housing] = (distribution[housing] ?? 0) + 1;
    }

    return distribution;
  }

  /// Calculate average household size
  Future<double> getAverageHouseholdSize() async {
    final submissions = await fetchIntakeSubmissions();
    double totalSize = 0;
    int count = 0;

    for (final submission in submissions) {
      final data = submission['data'] as Map<String, dynamic>? ?? {};
      final sizeStr =
          _findFieldValue(data, 'Household Size (E)')?.toString() ?? '';

      try {
        final size = double.parse(sizeStr.trim());
        totalSize += size;
        count++;
      } catch (e) {
        // Skip if can't parse
      }
    }

    return count > 0 ? totalSize / count : 0;
  }

  /// Helper: Find field value with case-insensitive and normalized matching
  String? _findFieldValue(Map<String, dynamic> data, String fieldLabel) {
    // Try exact match first
    if (data.containsKey(fieldLabel)) {
      return data[fieldLabel]?.toString();
    }

    // Try normalized match
    String normalize(String s) =>
        s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final normalizedLabel = normalize(fieldLabel);

    for (final entry in data.entries) {
      if (normalize(entry.key) == normalizedLabel) {
        return entry.value?.toString();
      }
    }

    return null;
  }

  /// Get summary statistics
  Future<Map<String, dynamic>> getSummaryStats() async {
    final [
      total,
      genderDist,
      ageDist,
      memberships,
      avgHousehold,
      youth
    ] = await Future.wait([
      getTotalSubmissions(),
      getGenderDistribution(),
      getAgeGroupDistribution(),
      getMembershipDistribution(),
      getAverageHouseholdSize(),
      getYouthCount(),
    ]);

    return {
      'totalSubmissions': total,
      'genderDistribution': genderDist as Map<String, int>,
      'ageGroupDistribution': ageDist as Map<String, int>,
      'membershipDistribution': memberships as Map<String, int>,
      'averageHouseholdSize': avgHousehold as double,
      'youthCount': youth as int,
    };
  }
}
