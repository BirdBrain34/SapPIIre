import 'package:supabase_flutter/supabase_flutter.dart';

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
}