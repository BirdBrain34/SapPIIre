import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class SupabaseService {
  final _supabase = Supabase.instance.client;

  // Load user profile with related data (address, socio-economic, family)
  Future<Map<String, dynamic>?> loadUserProfile(String userId) async {
    return await _supabase
        .from('user_profiles')
        .select('*, user_addresses(*), socio_economic_data(*)')
        .eq('user_id', userId)
        .maybeSingle();
  }

  // Load family composition for a profile
  Future<List<Map<String, dynamic>>> loadFamilyComposition(String profileId) async {
    final response = await _supabase
        .from('family_composition')
        .select()
        .eq('profile_id', profileId)
        .order('created_at');
    return List<Map<String, dynamic>>.from(response);
  }

  // Load supporting family members
  Future<List<Map<String, dynamic>>> loadSupportingFamily(String socioEconomicId) async {
    final response = await _supabase
        .from('supporting_family')
        .select()
        .eq('socio_economic_id', socioEconomicId)
        .order('sort_order');
    return List<Map<String, dynamic>>.from(response);
  }

  // Save complete user profile data
  Future<String> saveUserProfile({
    required String userId,
    required Map<String, dynamic> profileData,
    required Map<String, bool> membershipData,
  }) async {
    final profileUpdate = {'user_id': userId, ...profileData, ...membershipData};
    final profileRes = await _supabase
        .from('user_profiles')
        .upsert(profileUpdate, onConflict: 'user_id')
        .select('profile_id')
        .single();
    return profileRes['profile_id'];
  }

  // Save user address
  Future<void> saveUserAddress(String profileId, Map<String, dynamic> addressData) async {
    if (addressData.isNotEmpty) {
      final addressUpdate = {'profile_id': profileId, ...addressData};
      await _supabase.from('user_addresses').upsert(addressUpdate, onConflict: 'profile_id');
    }
  }

  // Save family composition
  Future<void> saveFamilyComposition(String profileId, List<Map<String, dynamic>> familyData) async {
    await _supabase.from('family_composition').delete().eq('profile_id', profileId);
    
    if (familyData.isNotEmpty) {
      final familyPayload = familyData.map((member) => {
        'profile_id': profileId,
        ...member,
      }).toList();
      await _supabase.from('family_composition').insert(familyPayload);
    }
  }

  // Save socio-economic data
  Future<String> saveSocioEconomicData(String profileId, Map<String, dynamic> socioData) async {
    final socioUpdate = {'profile_id': profileId, ...socioData};
    final socioRes = await _supabase
        .from('socio_economic_data')
        .upsert(socioUpdate, onConflict: 'profile_id')
        .select('socio_economic_id')
        .single();
    return socioRes['socio_economic_id'].toString();
  }

  // Save supporting family members
  Future<void> saveSupportingFamily(String socioEconomicId, List<Map<String, dynamic>> supportData, double monthlyAlimony) async {
    await _supabase.from('supporting_family').delete().eq('socio_economic_id', socioEconomicId);
    
    if (supportData.isNotEmpty) {
      final supportList = supportData.asMap().entries.map((entry) => {
        'socio_economic_id': socioEconomicId,
        'name': entry.value['name'],
        'relationship': entry.value['relationship'],
        'regular_sustento': entry.value['regular_sustento'],
        'monthly_alimony': monthlyAlimony,
        'sort_order': entry.key,
      }).where((item) => item['name'].toString().isNotEmpty).toList();

      if (supportList.isNotEmpty) {
        await _supabase.from('supporting_family').insert(supportList);
      }
    }
  }

  // Save user profile, address, family composition, and socio-economic data to Supabase
  Future<void> savePiiData({
    required Map<String, dynamic> personalInfo,
    required Map<String, dynamic> addressInfo,
    required List<Map<String, dynamic>> familyMembers,
    required Map<String, dynamic>? socioData,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final profileResponse = await _supabase.from('user_profiles').upsert({
      'user_id': user.id,
      ...personalInfo,
    }).select('profile_id').single();

    final profileId = profileResponse['profile_id'];

    await _supabase.from('user_addresses').upsert({
      'profile_id': profileId,
      ...addressInfo,
    });

    if (familyMembers.isNotEmpty) {
      final familyWithId = familyMembers.map((m) => {
        'profile_id': profileId,
        ...m,
      }).toList();
      await _supabase.from('family_composition').upsert(familyWithId);
    }

    if (socioData != null) {
      await _supabase.from('socio_economic_data').upsert({
        'profile_id': profileId,
        ...socioData,
      });
    }
  }

  /// Reads the logged-in user's full profile from Supabase,
  /// maps it to GIS field keys, and pushes it into form_submission
  /// so the web listener receives it via Realtime and autofills live.
  Future<bool> pushProfileToSession({
    required String sessionId,
    required String userId,
  }) async {
    try {
      // 1. Fetch all PII in one query — profile + address + socio + family
      final profile = await _supabase
          .from('user_profiles')
          .select('*, user_addresses(*), socio_economic_data(*)')
          .eq('user_id', userId)
          .single();

      final familyResponse = await _supabase
          .from('family_composition')
          .select()
          .eq('profile_id', profile['profile_id'])
          .order('created_at');

      final address = (profile['user_addresses'] as Map<String, dynamic>?) ?? {};
      final socio = (profile['socio_economic_data'] as Map<String, dynamic>?) ?? {};
      final family = List<Map<String, dynamic>>.from(familyResponse);

      // 2. Map to the EXACT keys used in _webControllers on ManageFormsScreen
      final formData = <String, dynamic>{
        // Client Info
        'Last Name': profile['lastname'] ?? '',
        'First Name': profile['firstname'] ?? '',
        'Middle Name': profile['middle_name'] ?? '',
        'House number, street name, phase/purok': address['address_line'] ?? '',
        'Subdivision': address['subdivision'] ?? '',
        'Barangay': address['barangay'] ?? '',
        'Kasarian': profile['gender'] ?? '',
        'Estadong Sibil': profile['civil_status'] ?? '',
        'Relihiyon': profile['religion'] ?? '',
        'CP Number': profile['cellphone_number'] ?? '',
        'Email Address': profile['email'] ?? '',
        'Natapos o naabot sa pag-aaral': profile['education'] ?? '',
        'Lugar ng Kapanganakan': profile['birthplace'] ?? '',
        'Trabaho/Pinagkakakitaan': profile['occupation'] ?? '',
        'Kumpanyang Pinagtratrabuhan': profile['workplace'] ?? '',
        'Buwanang Kita (A)': profile['monthly_allowance']?.toString() ?? '',

        // Socio-Economic
        'Total Gross Family Income (A+B+C)=(D)': socio['gross_family_income']?.toString() ?? '',
        'Household Size (E)': socio['household_size']?.toString() ?? '',
        'Monthly Per Capita Income (D/E)': socio['monthly_per_capita']?.toString() ?? '',
        'Total Monthly Expense (F)': socio['monthly_expenses']?.toString() ?? '',
        'Net Monthly Income (D-F)': socio['net_monthly_income']?.toString() ?? '',
        'Bayad sa bahay': socio['house_rent']?.toString() ?? '',
        'Food items': socio['food_items']?.toString() ?? '',
        'Non-food items': socio['non_food_items']?.toString() ?? '',
        'Utility bills': socio['utility_bills']?.toString() ?? '',
        "Baby's needs": socio['baby_needs']?.toString() ?? '',
        'School needs': socio['school_needs']?.toString() ?? '',
        'Medical needs': socio['medical_needs']?.toString() ?? '',
        'Transpo expense': socio['transport_expenses']?.toString() ?? '',
        'Loans': socio['loans']?.toString() ?? '',
        'Gasul': socio['gas']?.toString() ?? '',

        // Family composition as a JSON array — web FamilyTable will render this
        '__family_composition': family.map((m) => {
          'name': m['name'] ?? '',
          'relationship': m['relationship_of_relative'] ?? '',
          'birthdate': m['birthdate']?.toString() ?? '',
          'age': m['age']?.toString() ?? '',
          'gender': m['gender'] ?? '',
          'civil_status': m['civil_status'] ?? '',
          'education': m['education'] ?? '',
          'occupation': m['occupation'] ?? '',
          'allowance': m['allowance']?.toString() ?? '',
        }).toList(),
      };

      // 3. Push to form_submission — Realtime fires instantly to web listener
      await _supabase
          .from('form_submission')
          .update({
            'form_data': formData,
            'status': 'scanned',
          })
          .eq('id', sessionId)
          .eq('status', 'active'); // Safety guard — only update if still active

      return true;
    } catch (e) {
      debugPrint('pushProfileToSession error: $e');
      return false;
    }
  }
}