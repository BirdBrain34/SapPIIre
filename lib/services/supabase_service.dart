import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class SupabaseService {
  final _supabase = Supabase.instance.client;

  // Hash password using SHA-256
  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // ================================================================
  // AUTHENTICATION
  // ================================================================

  // Sign up - Create user account + profile
  Future<Map<String, dynamic>> signUp({
    required String username,
    required String password,
    required String email,
    required String firstName,
    required String middleName,
    required String lastName,
    required String dateOfBirth,
    required String phoneNumber,
  }) async {
    try {
      final existingUser = await _supabase
          .from('user_accounts')
          .select('username')
          .eq('username', username)
          .maybeSingle();

      if (existingUser != null) {
        return {'success': false, 'message': 'Username already exists'};
      }

      final hashedPassword = _hashPassword(password);

      final accountResponse = await _supabase
          .from('user_accounts')
          .insert({
            'username': username,
            'password': hashedPassword,
            'email': email,
            'is_active': true,
          })
          .select()
          .single();

      final String userId = accountResponse['user_id'];

      final dateParts = dateOfBirth.split('/');
      final formattedDate =
          '${dateParts[2]}-${dateParts[0].padLeft(2, '0')}-${dateParts[1].padLeft(2, '0')}';

      // Calculate age from birthdate
      final birthYear = int.parse(dateParts[2]);
      final currentYear = DateTime.now().year;
      final age = currentYear - birthYear;

      await _supabase.from('user_profiles').insert({
        'user_id': userId,
        'firstname': firstName,
        'middle_name': middleName,
        'lastname': lastName,
        'birthdate': formattedDate,
        'age': age,
        'email': email,
        'cellphone_number': phoneNumber,
      });

      return {
        'success': true,
        'message': 'Account created successfully',
        'user_id': userId,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Error creating account: ${e.toString()}',
      };
    }
  }

  // Login - Verify credentials
  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    try {
      final hashedPassword = _hashPassword(password);

      final account = await _supabase
          .from('user_accounts')
          .select('user_id, username, email, password, is_active')
          .eq('username', username)
          .maybeSingle();

      if (account == null) {
        return {
          'success': false,
          'code': 'no_user',
          'message': 'Account does not exist'
        };
      }

      if (account['password'] != hashedPassword) {
        return {
          'success': false,
          'code': 'wrong_password',
          'message': 'Invalid username or password'
        };
      }

      if (account['is_active'] == false) {
        return {
          'success': false,
          'code': 'deactivated',
          'message': 'Account is deactivated'
        };
      }

      final profileResponse = await _supabase
          .from('user_profiles')
          .select()
          .eq('user_id', account['user_id'])
          .maybeSingle();

      return {
        'success': true,
        'message': 'Login successful',
        'user_id': account['user_id'],
        'username': account['username'],
        'email': account['email'],
        'profile': profileResponse,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Error during login: ${e.toString()}'
      };
    }
  }

  // ================================================================
  // USER PROFILE
  // ================================================================

  // Get username for the header
  Future<String?> getUsername(String userId) async {
    try {
      final response = await _supabase
          .from('user_accounts')
          .select('username')
          .eq('user_id', userId)
          .maybeSingle();
      
      return response?['username'] as String?;
    } catch (e) {
      print('Error fetching username: $e');
      return null;
    }
  }

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

      // Fetch supporting family if exists
      List<Map<String, dynamic>> supportingFamily = [];
      if (socio['socio_economic_id'] != null) {
        final supportResponse = await _supabase
            .from('supporting_family')
            .select()
            .eq('socio_economic_id', socio['socio_economic_id'])
            .order('sort_order');
        supportingFamily = List<Map<String, dynamic>>.from(supportResponse);
      }

      // 2. Map to the EXACT keys used in _webControllers on ManageFormsScreen
      final formData = <String, dynamic>{
        // Client Info
        'Last Name': profile['lastname'] ?? '',
        'First Name': profile['firstname'] ?? '',
        'Middle Name': profile['middle_name'] ?? '',
        'Date of Birth': profile['birthdate'] ?? '',
        'Age': profile['age']?.toString() ?? '',
        'House number, street name, phase/purok': address['address_line'] ?? '',
        'Subdivision': address['subdivision'] ?? '',
        'Barangay': address['barangay'] ?? '',
        'Kasarian': profile['gender'] ?? '',
        'Kasarian / Sex': profile['gender'] ?? '',
        'Uri ng Dugo / Blood Type': profile['blood_type'] ?? '',
        'Estadong Sibil': profile['civil_status'] ?? '',
        'Estadong Sibil / Martial Status': profile['civil_status'] ?? '',
        'Relihiyon': profile['religion'] ?? '',
        'CP Number': profile['cellphone_number'] ?? '',
        'Email Address': profile['email'] ?? '',
        'Natapos o naabot sa pag-aaral': profile['education'] ?? '',
        'Lugar ng Kapanganakan': profile['birthplace'] ?? '',
        'Lugar ng Kapanganakan / Place of Birth': profile['birthplace'] ?? '',
        'Trabaho/Pinagkakakitaan': profile['occupation'] ?? '',
        'Kumpanyang Pinagtratrabuhan': profile['workplace'] ?? '',
        'Buwanang Kita (A)': profile['monthly_allowance']?.toString() ?? '',

        // Membership data
        '__membership': {
          'solo_parent': profile['solo_parent'] ?? false,
          'pwd': profile['pwd'] ?? false,
          'four_ps_member': profile['four_ps_member'] ?? false,
          'phic_member': profile['phic_member'] ?? false,
        },

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
        'Kabuuang Tulong/Sustento kada Buwan (C)': supportingFamily.isNotEmpty 
            ? supportingFamily[0]['monthly_alimony']?.toString() ?? '' 
            : '',

        // Socio-economic metadata
        '__has_support': socio['has_support'] ?? false,
        '__housing_status': socio['housing_status'] ?? '',

        // Supporting family as JSON array
        '__supporting_family': supportingFamily.map((m) => {
          'name': m['name'] ?? '',
          'relationship': m['relationship'] ?? '',
          'regular_sustento': m['regular_sustento']?.toString() ?? '',
        }).toList(),

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

        // Signature
        '__signature': profile['signature_data'] ?? '',
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
  /// Sends the specific filtered data selected by the user to the web session.
  /// This allows the user to choose exactly which fields to transmit via checkboxes.
Future<bool> sendDataToWebSession(String sessionId, Map<String, dynamic> data) async {
  try {
    final response = await _supabase
        .from('form_submission')
        .update({
          'form_data': data, // The filtered checkboxes map
          'status': 'scanned',
          'scanned_at': DateTime.now().toIso8601String(),
        })
        .eq('id', sessionId)
        .select()
        .maybeSingle();

    return response != null;
  } catch (e) {
    debugPrint('Supabase Update Error: $e');
    return false;
  }
}
}