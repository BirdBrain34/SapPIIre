import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  final _supabase = Supabase.instance.client;

  Future<void> savePiiData({
    required Map<String, dynamic> personalInfo,
    required Map<String, dynamic> addressInfo,
    required List<Map<String, dynamic>> familyMembers,
    required Map<String, dynamic>? socioData,
  }) async {
    // 1. Get current user (Ensure they are logged in)
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    // 2. Insert Profile (Matches your 'user_profiles' table)
    final profileResponse = await _supabase.from('user_profiles').upsert({
      'user_id': user.id,
      ...personalInfo,
    }).select('profile_id').single();

    final profileId = profileResponse['profile_id'];

    // 3. Insert Address (Matches 'user_addresses')
    await _supabase.from('user_addresses').upsert({
      'profile_id': profileId,
      ...addressInfo,
    });

    // 4. Insert Family members if they exist
    if (familyMembers.isNotEmpty) {
      final familyWithId = familyMembers.map((m) => {
        'profile_id': profileId,
        ...m,
      }).toList();
      await _supabase.from('family_composition').upsert(familyWithId);
    }

    // 5. Insert Socio-Economic data if "meron"
    if (socioData != null) {
      await _supabase.from('socio_economic_data').upsert({
        'profile_id': profileId,
        ...socioData,
      });
    }
  }
}