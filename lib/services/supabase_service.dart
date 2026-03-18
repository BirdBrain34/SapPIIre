import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/form_template_models.dart';

class SupabaseService {
  final _supabase = Supabase.instance.client;

  // ================================================================
  // KNOWN COLUMN DEFINITIONS (for extra_data split logic)
  // ================================================================
  /// Known columns in user_profiles table. Any other columns go to extra_data.
  static const _knownProfileColumns = <String>[
    'user_id', 'profile_id', 'firstname', 'lastname', 'birthdate', 'age',
    'middle_name', 'gender', 'blood_type', 'civil_status', 'religion',
    'cellphone_number', 'email', 'education', 'birthplace', 'occupation',
    'workplace', 'monthly_allowance', 'solo_parent', 'pwd', 'four_ps_member',
    'phic_member', 'signature_data', 'extra_data'
  ];

  /// Known columns in user_addresses table
  static const _knownAddressColumns = <String>[
    'profile_id', 'address_line', 'subdivision', 'barangay', 'extra_data'
  ];

  /// Known columns in family_composition table
  static const _knownFamilyColumns = <String>[
    'profile_id', 'name', 'relationship_of_relative', 'birthdate', 'age',
    'gender', 'civil_status', 'education', 'occupation', 'allowance',
    'created_at', 'extra_data'
  ];

  /// Known columns in socio_economic_data table
  static const _knownSocioColumns = <String>[
    'socio_economic_id', 'profile_id', 'gross_family_income', 'household_size',
    'monthly_per_capita', 'monthly_expenses', 'net_monthly_income', 'house_rent',
    'food_items', 'non_food_items', 'utility_bills', 'baby_needs', 'school_needs',
    'medical_needs', 'transport_expenses', 'loans', 'gas', 'has_support',
    'housing_status', 'extra_data'
  ];

  /// Known columns in supporting_family table
  static const _knownSupportingColumns = <String>[
    'socio_economic_id', 'name', 'relationship', 'regular_sustento',
    'monthly_alimony', 'sort_order', 'extra_data'
  ];

  // ================================================================
  // AUTHENTICATION
  // ================================================================

  /// Step 1 of signup: register with Supabase Auth.
  /// Supabase sends an OTP to the email automatically.
  Future<Map<String, dynamic>> signUpWithEmail({
    required String email,
  }) async {
    try {
      // Check user_accounts for this email
      final existing = await _supabase
          .from('user_accounts')
          .select('email, user_id')
          .eq('email', email)
          .maybeSingle();

      if (existing != null) {
        final userId = existing['user_id'] as String?;
        if (userId != null && userId.isNotEmpty) {
          // Check if they finished signup (have a profile)
          final profile = await _supabase
              .from('user_profiles')
              .select('profile_id')
              .eq('user_id', userId)
              .maybeSingle();

          if (profile != null) {
            // Fully registered — block
            return {
              'success': false,
              'message': 'This email is already registered. Please log in instead.',
            };
          } else {
            // Verified email but never finished — send OTP via signInWithOtp
            // and treat it as continuing their signup
            await _supabase.auth.signInWithOtp(
              email: email,
              shouldCreateUser: false, // don't create, just send OTP to existing
            );
            return {
              'success': true,
              'message': 'OTP sent! Check your email.',
              'user_id': userId,
            };
          }
        }
      }

      // Brand new email — use signUp which sends OTP only
      final res = await _supabase.auth.signUp(
        email: email,
        password: DateTime.now().millisecondsSinceEpoch.toString(),
      );

      if (res.user == null) {
        return {'success': false, 'message': 'Sign-up failed. Try again.'};
      }

      return {
        'success': true,
        'message': 'OTP sent! Check your email.',
        'user_id': res.user!.id,
      };
    } catch (e) {
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  /// Step 2 of signup: verify the OTP sent to email.
  Future<Map<String, dynamic>> verifyEmailOtp({
    required String email,
    required String otp,
  }) async {
    try {
      final response = await _supabase.auth.verifyOTP(
        email: email,
        token: otp,
        type: OtpType.email,
      );

      if (response.user == null) {
        return {'success': false, 'message': 'Invalid or expired code.'};
      }

      return {
        'success': true,
        'user_id': response.user!.id,  // ← this is now reliable since OTP confirmed
      };
    } on AuthException catch (e) {
      return {'success': false, 'message': e.message};
    } catch (e) {
      return {'success': false, 'message': 'Verification error: ${e.toString()}'};
    }
  }

    /// Step 3 of signup: Phone OTP.
  Future<Map<String, dynamic>> sendPhoneOtp(String phone) async {
    try {
      final otp = (100000 + (DateTime.now().millisecondsSinceEpoch % 900000)).toString();
      
      final response = await http.post(
        Uri.parse('https://api.semaphore.co/api/v4/otp'),
        body: {
          'apikey': 'fc4874818b2f98480dbba9e862b90334',
          'number': phone,
          'message': 'Your SapPIIre verification code is {otp}. Do not share this with anyone.',
          'code': otp,
          //'sendername': 'SEMAPHORE',
          'sendername': 'SapPIIre',
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Store OTP in Supabase directly
        await _supabase.from('phone_otp').delete().eq('phone', phone);
        await _supabase.from('phone_otp').insert({
          'phone': phone,
          'otp': otp,
          'expires_at': DateTime.now().add(const Duration(minutes: 10)).toUtc().toIso8601String(),
        });
        return {'success': true, 'message': 'OTP sent!'};
      } else {
        return {'success': false, 'message': 'Semaphore error: ${response.body}'};
      }
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> verifyPhoneOtp({
    required String phone,
    required String otp,
  }) async {
    try {
      final data = await _supabase
          .from('phone_otp')
          .select()
          .eq('phone', phone)
          .eq('otp', otp)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (data == null) {
        return {'success': false, 'message': 'Invalid code'};
      }

      if (DateTime.parse(data['expires_at']).isBefore(DateTime.now().toUtc())) {
        await _supabase.from('phone_otp').delete().eq('id', data['id']);
        return {'success': false, 'message': 'Code has expired. Please request a new one.'};
      }

      await _supabase.from('phone_otp').delete().eq('id', data['id']);
      return {'success': true, 'message': 'Phone verified!'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Step 4 of signup: save profile data after OTP is verified.
  Future<Map<String, dynamic>> saveProfileAfterVerification({
    required String userId,
    required String username,
    required String password,   // ← new param
    required String email,
    required String firstName,
    required String middleName,
    required String lastName,
    required String dateOfBirth,
    required String phoneNumber,
    required String birthplace,
    required String gender,
    required String civilStatus,
    required String addressLine,
  }) async {
    try {
      // Set the password now that they've verified their email
      await _supabase.auth.updateUser(
        UserAttributes(password: password),
      );

      // Update username in user_accounts
      await _supabase
          .from('user_accounts')
          .update({'username': username})
          .eq('user_id', userId);

      final dateParts = dateOfBirth.split('/');
      final formattedDate =
          '${dateParts[2]}-${dateParts[0].padLeft(2, '0')}-${dateParts[1].padLeft(2, '0')}';
      final birthYear = int.parse(dateParts[2]);
      final age = DateTime.now().year - birthYear;

      final profileRes = await _supabase.from('user_profiles').insert({
        'user_id': userId,
        'firstname': firstName,
        'middle_name': middleName,
        'lastname': lastName,
        'birthdate': formattedDate,
        'age': age,
        'email': email,
        'cellphone_number': phoneNumber,
        'birthplace': birthplace,
        'gender': gender,
        'civil_status': civilStatus,
      }).select('profile_id').single();

      await saveUserAddress(profileRes['profile_id'].toString(), {
        'address_line': addressLine,
        'subdivision': '',
        'barangay': '',
      });

      return {
        'success': true,
        'message': 'Account created successfully',
        'user_id': userId,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Error saving profile: ${e.toString()}',
      };
    }
  }



  /// Login using Supabase Auth
  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    try {
      // Resolve email from username
      final account = await _supabase
          .from('user_accounts')
          .select('user_id, username, email, is_active')
          .eq('username', username)
          .maybeSingle();

      if (account == null) {
        return {'success': false, 'message': 'Account does not exist'};
      }

      if (account['is_active'] == false) {
        return {'success': false, 'message': 'Account is deactivated'};
      }

      final response = await _supabase.auth.signInWithPassword(
        email: account['email'],
        password: password,
      );

      if (response.user == null) {
        return {'success': false, 'message': 'Invalid username or password'};
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
    } on AuthException catch (e) {
      return {'success': false, 'message': e.message};
    } catch (e) {
      return {'success': false, 'message': 'Error during login: ${e.toString()}'};
    }
  }

  // ================================================================
  // USER PROFILE  (all original methods below — unchanged)
  // ================================================================

  Future<String?> getUsername(String userId) async {
    try {
      final response = await _supabase
          .from('user_accounts')
          .select('username')
          .eq('user_id', userId)
          .maybeSingle();
      return response?['username'] as String?;
    } catch (e) {
      debugPrint('Error fetching username: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> loadUserProfile(String userId) async {
    return await _supabase
        .from('user_profiles')
        .select('*, user_addresses(*), socio_economic_data(*)')
        .eq('user_id', userId)
        .maybeSingle();
  }

  Future<List<Map<String, dynamic>>> loadFamilyComposition(String profileId) async {
    final response = await _supabase
        .from('family_composition')
        .select()
        .eq('profile_id', profileId)
        .order('created_at');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> loadSupportingFamily(String socioEconomicId) async {
    final response = await _supabase
        .from('supporting_family')
        .select()
        .eq('socio_economic_id', socioEconomicId)
        .order('sort_order');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<String> saveUserProfile({
    required String userId,
    required Map<String, dynamic> profileData,
    required Map<String, bool> membershipData,
  }) async {
    final profileUpdate = <String, dynamic>{'user_id': userId};
    profileUpdate.addAll(membershipData);
    final extraData = <String, dynamic>{};

    // Split profileData into known columns and extra_data
    profileData.forEach((key, value) {
      if (_knownProfileColumns.contains(key)) {
        profileUpdate[key] = value;
      } else {
        extraData[key] = value;
      }
    });

    // Only include extra_data if there are extra fields
    if (extraData.isNotEmpty) {
      profileUpdate['extra_data'] = extraData;
    }

    final profileRes = await _supabase
        .from('user_profiles')
        .upsert(profileUpdate, onConflict: 'user_id')
        .select('profile_id')
        .single();
    return profileRes['profile_id'];
  }

  Future<void> saveUserAddress(String profileId, Map<String, dynamic> addressData) async {
    if (addressData.isNotEmpty) {
      final addressUpdate = <String, dynamic>{'profile_id': profileId};
      final extraData = <String, dynamic>{};

      // Split addressData into known columns and extra_data
      addressData.forEach((key, value) {
        if (_knownAddressColumns.contains(key)) {
          addressUpdate[key] = value;
        } else {
          extraData[key] = value;
        }
      });

      // Only include extra_data if there are extra fields
      if (extraData.isNotEmpty) {
        addressUpdate['extra_data'] = extraData;
      }

      await _supabase.from('user_addresses').upsert(addressUpdate, onConflict: 'profile_id');
    }
  }

  Future<void> saveFamilyComposition(String profileId, List<Map<String, dynamic>> familyData) async {
    await _supabase.from('family_composition').delete().eq('profile_id', profileId);
    if (familyData.isNotEmpty) {
      final familyPayload = familyData.map((member) => {'profile_id': profileId, ...member}).toList();
      await _supabase.from('family_composition').insert(familyPayload);
    }
  }

  Future<String> saveSocioEconomicData(String profileId, Map<String, dynamic> socioData) async {
    final socioUpdate = <String, dynamic>{'profile_id': profileId};
    final extraData = <String, dynamic>{};

    // Split socioData into known columns and extra_data
    socioData.forEach((key, value) {
      if (_knownSocioColumns.contains(key)) {
        socioUpdate[key] = value;
      } else {
        extraData[key] = value;
      }
    });

    // Only include extra_data if there are extra fields
    if (extraData.isNotEmpty) {
      socioUpdate['extra_data'] = extraData;
    }

    final socioRes = await _supabase
        .from('socio_economic_data')
        .upsert(socioUpdate, onConflict: 'profile_id')
        .select('socio_economic_id')
        .single();
    return socioRes['socio_economic_id'].toString();
  }

  Future<void> saveSupportingFamily(String socioEconomicId, List<Map<String, dynamic>> supportData, double monthlyAlimony) async {
    await _supabase.from('supporting_family').delete().eq('socio_economic_id', socioEconomicId);
    if (supportData.isNotEmpty) {
      final supportList = supportData.asMap().entries.map((entry) {
        final knownFields = {
          'socio_economic_id': socioEconomicId,
          'name': entry.value['name'],
          'relationship': entry.value['relationship'],
          'regular_sustento': entry.value['regular_sustento'],
          'monthly_alimony': monthlyAlimony,
          'sort_order': entry.key,
        };

        // Collect any extra fields not in knownFields
        final extraData = <String, dynamic>{};
        entry.value.forEach((key, value) {
          if (!_knownSupportingColumns.contains(key) &&
              !knownFields.containsKey(key)) {
            extraData[key] = value;
          }
        });

        // Add extra_data if there are extra fields
        if (extraData.isNotEmpty) {
          knownFields['extra_data'] = extraData;
        }

        return knownFields;
      }).where((item) => item['name'].toString().isNotEmpty).toList();
      if (supportList.isNotEmpty) {
        await _supabase.from('supporting_family').insert(supportList);
      }
    }
  }

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

    await _supabase.from('user_addresses').upsert({'profile_id': profileId, ...addressInfo});

    if (familyMembers.isNotEmpty) {
      final familyWithId = familyMembers.map((m) => {'profile_id': profileId, ...m}).toList();
      await _supabase.from('family_composition').upsert(familyWithId);
    }

    if (socioData != null) {
      await _supabase.from('socio_economic_data').upsert({'profile_id': profileId, ...socioData});
    }
  }

  Future<bool> pushProfileToSession({required String sessionId, required String userId}) async {
    try {
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

      List<Map<String, dynamic>> supportingFamily = [];
      if (socio['socio_economic_id'] != null) {
        final supportResponse = await _supabase
            .from('supporting_family')
            .select()
            .eq('socio_economic_id', socio['socio_economic_id'])
            .order('sort_order');
        supportingFamily = List<Map<String, dynamic>>.from(supportResponse);
      }

      final formData = <String, dynamic>{
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
        '__membership': {
          'solo_parent': profile['solo_parent'] ?? false,
          'pwd': profile['pwd'] ?? false,
          'four_ps_member': profile['four_ps_member'] ?? false,
          'phic_member': profile['phic_member'] ?? false,
        },
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
        '__has_support': socio['has_support'] ?? false,
        '__housing_status': socio['housing_status'] ?? '',
        '__supporting_family': supportingFamily.map((m) => {
          'name': m['name'] ?? '',
          'relationship': m['relationship'] ?? '',
          'regular_sustento': m['regular_sustento']?.toString() ?? '',
        }).toList(),
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
        '__signature': profile['signature_data'] ?? '',
      };

      await _supabase
          .from('form_submission')
          .update({'form_data': formData, 'status': 'scanned'})
          .eq('id', sessionId)
          .eq('status', 'active');

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
            'form_data': data,
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

  // ================================================================
  // SUBMISSION INTERCEPTOR
  // ================================================================

  /// Routes system-block data from a JSON payload to their dedicated
  /// Supabase tables. Call from any submission path (mobile save,
  /// web finalize) to ensure familyTable data lands in normalised
  /// storage instead of only the generic JSONB blob.
  ///
  /// [profileId] – the applicant's profile_id (from user_profiles)
  /// [template]  – the active FormTemplate (tells us which blocks exist)
  /// [formData]  – the full JSON payload from FormStateController.toJson()
  ///
  /// Does NOT remove keys from [formData] so the JSONB audit copy in
  /// client_submissions stays complete.
  Future<void> interceptAndRouteSystemFields({
    required String profileId,
    required FormTemplate template,
    required Map<String, dynamic> formData,
  }) async {
    for (final field in template.allFields) {
      if (!field.fieldType.isSystemType) continue;

      switch (field.fieldType) {
        case FormFieldType.familyTable:
          await _routeFamilyTable(profileId, field, formData);
          break;
        // Future system blocks (supportingFamilyTable, etc.) can be
        // added here following the same pattern.
        default:
          break;
      }
    }
  }

  /// Extracts __family_composition from the payload and uses best-effort
  /// mapping: whatever db_map_key values are present in the template columns
  /// get routed to the family_composition table. If a core key (e.g. age,
  /// name) is missing because the staff deleted that column, null is passed
  /// to the Supabase upsert (Postgres schema allows NULLs). Custom columns
  /// (no db_map_key) are ignored here — their data stays in the JSONB audit
  /// copy in client_submissions.
  ///
  /// Falls back to legacy hardcoded mapping when the template has no
  /// column definitions (backwards compat with pre-migration templates).

  /// The 9 core DB columns for family_composition. Used to fill nulls for
  /// any keys not present in the template's column list.
  static const _familyCompositionCoreDbKeys = <String>[
    'name',
    'relationship_of_relative',
    'birthdate',
    'age',
    'gender',
    'civil_status',
    'education',
    'occupation',
    'allowance',
  ];

  Future<void> _routeFamilyTable(
    String profileId,
    FormFieldModel field,
    Map<String, dynamic> formData,
  ) async {
    final raw = formData['__family_composition'];
    if (raw is! List || raw.isEmpty) {
      // User deleted all rows → wipe the table for this profile
      await _supabase
          .from('family_composition')
          .delete()
          .eq('profile_id', profileId);
      return;
    }

    // Build a mapping from UI fieldName → DB column name.
    // Only columns with a db_map_key get routed; custom columns are skipped.
    final colMap = <String, String>{};
    if (field.columns.isNotEmpty) {
      for (final col in field.columns) {
        final dbKey = col.validationRules?['db_map_key'] as String?;
        if (dbKey != null) {
          colMap[col.fieldName] = dbKey;
        }
      }
    } else {
      // Legacy fallback: hardcoded mapping for templates without columns
      colMap.addAll({
        'name': 'name',
        'relationship': 'relationship_of_relative',
        'birthdate': 'birthdate',
        'age': 'age',
        'gender': 'gender',
        'civil_status': 'civil_status',
        'education': 'education',
        'occupation': 'occupation',
        'allowance': 'allowance',
      });
    }

    // Type coercion helpers for specific DB columns
    dynamic coerce(String dbCol, dynamic value) {
      if (value == null) return null;
      switch (dbCol) {
        case 'age':
          return int.tryParse(value.toString());
        case 'allowance':
          return double.tryParse(
                  value.toString().replaceAll(',', ''));
        default:
          return value.toString();
      }
    }

    final mapped = raw.cast<Map<String, dynamic>>().map((memberRow) {
      final dbRow = <String, dynamic>{};
      final customColumns = <String, dynamic>{};

      // Separate known columns from custom columns
      memberRow.forEach((key, value) {
        if (colMap.containsKey(key)) {
          // Known column with a db_map_key
          final dbCol = colMap[key]!;
          dbRow[dbCol] = coerce(dbCol, value);
        } else {
          // Custom column (no db_map_key) → goes to extra_data
          customColumns[key] = value;
        }
      });

      // Best-effort: fill null for any core DB keys NOT present in colMap
      // (i.e. the staff deleted that column from the template)
      for (final coreKey in _familyCompositionCoreDbKeys) {
        if (!dbRow.containsKey(coreKey)) {
          dbRow[coreKey] = null;
        }
      }

      // Attach custom columns as extra_data if any exist
      if (customColumns.isNotEmpty) {
        dbRow['extra_data'] = customColumns;
      }

      return dbRow;
    }).toList();

    await saveFamilyComposition(profileId, mapped);
  }

  /// Resolves profile_id from a form_submission session row.
  /// Returns null if the session has no linked user or profile.
  Future<String?> resolveProfileIdFromSession(String sessionId) async {
    try {
      final session = await _supabase
          .from('form_submission')
          .select('user_id, profile_id')
          .eq('id', sessionId)
          .maybeSingle();

      if (session == null) return null;

      // Prefer explicit profile_id if already set on the session
      if (session['profile_id'] != null) {
        return session['profile_id'] as String;
      }

      // Fall back: look up from user_profiles via user_id
      final userId = session['user_id'] as String?;
      if (userId == null) return null;

      final profile = await _supabase
          .from('user_profiles')
          .select('profile_id')
          .eq('user_id', userId)
          .maybeSingle();

      return profile?['profile_id'] as String?;
    } catch (e) {
      debugPrint('resolveProfileIdFromSession error: $e');
      return null;
    }
  }
}