import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:sappiire/constants/supabase_config.dart';

/// Sort orders accepted by the `search-applicants` Edge Function.
enum ApplicantSortOrder { recent, oldest, name, mostRecords }

extension ApplicantSortOrderWire on ApplicantSortOrder {
  String get wireValue => switch (this) {
    ApplicantSortOrder.recent => 'recent',
    ApplicantSortOrder.oldest => 'oldest',
    ApplicantSortOrder.name => 'name',
    ApplicantSortOrder.mostRecords => 'most_records',
  };

  String get label => switch (this) {
    ApplicantSortOrder.recent => 'Most recent',
    ApplicantSortOrder.oldest => 'Oldest first',
    ApplicantSortOrder.name => 'Name (A-Z)',
    ApplicantSortOrder.mostRecords => 'Most records',
  };
}

/// Whether the applicant came in through the mobile app or as a walk-in.
enum AccountLinkFilter { all, linked, walkin }

extension AccountLinkFilterWire on AccountLinkFilter {
  String get wireValue => switch (this) {
    AccountLinkFilter.all => 'all',
    AccountLinkFilter.linked => 'linked',
    AccountLinkFilter.walkin => 'walkin',
  };

  String get label => switch (this) {
    AccountLinkFilter.all => 'All applicants',
    AccountLinkFilter.linked => 'Mobile account',
    AccountLinkFilter.walkin => 'Walk-in',
  };
}

@immutable
class ApplicantSearchFilters {
  const ApplicantSearchFilters({
    this.formType,
    this.dateFrom,
    this.dateTo,
    this.intakeReference,
    this.accountLink = AccountLinkFilter.all,
  });

  final String? formType;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String? intakeReference;
  final AccountLinkFilter accountLink;

  bool get isEmpty =>
      (formType == null || formType == 'All') &&
      dateFrom == null &&
      dateTo == null &&
      (intakeReference == null || intakeReference!.isEmpty) &&
      accountLink == AccountLinkFilter.all;

  ApplicantSearchFilters copyWith({
    Object? formType = _unset,
    Object? dateFrom = _unset,
    Object? dateTo = _unset,
    Object? intakeReference = _unset,
    AccountLinkFilter? accountLink,
  }) {
    return ApplicantSearchFilters(
      formType: formType == _unset ? this.formType : formType as String?,
      dateFrom: dateFrom == _unset ? this.dateFrom : dateFrom as DateTime?,
      dateTo: dateTo == _unset ? this.dateTo : dateTo as DateTime?,
      intakeReference: intakeReference == _unset
          ? this.intakeReference
          : intakeReference as String?,
      accountLink: accountLink ?? this.accountLink,
    );
  }

  Map<String, dynamic> toJson() => {
    if (formType != null && formType != 'All') 'formType': formType,
    if (dateFrom != null) 'dateFrom': dateFrom!.toUtc().toIso8601String(),
    // Inclusive upper bound — the caller passes a date, the user means the
    // whole of that day.
    if (dateTo != null)
      'dateTo': DateTime(
        dateTo!.year,
        dateTo!.month,
        dateTo!.day,
        23,
        59,
        59,
      ).toUtc().toIso8601String(),
    if (intakeReference != null && intakeReference!.trim().isNotEmpty)
      'intakeReference': intakeReference!.trim(),
    'accountLink': accountLink.wireValue,
  };

  static const Object _unset = Object();
}

/// One submission belonging to an applicant. Metadata only — no PII beyond
/// what the list row needs.
@immutable
class ApplicantSubmissionRef {
  const ApplicantSubmissionRef({
    required this.id,
    required this.formType,
    required this.createdAt,
    this.sessionId,
    this.intakeReference,
  });

  final int id;
  final String formType;
  final String createdAt;
  final String? sessionId;
  final String? intakeReference;

  factory ApplicantSubmissionRef.fromJson(Map<String, dynamic> json) {
    return ApplicantSubmissionRef(
      id: (json['id'] as num).toInt(),
      formType: json['formType']?.toString() ?? '',
      createdAt: json['createdAt']?.toString() ?? '',
      sessionId: json['sessionId']?.toString(),
      intakeReference: json['intakeReference']?.toString(),
    );
  }

  /// Shape the rest of the app still expects for a submission map.
  Map<String, dynamic> toSubmissionMap() => {
    'id': id,
    'form_type': formType,
    'created_at': createdAt,
    'session_id': sessionId,
    'intake_reference': intakeReference,
  };
}

/// A distinct person, as resolved server-side for this request.
@immutable
class ApplicantSummary {
  const ApplicantSummary({
    required this.identityKey,
    required this.identitySource,
    required this.confidence,
    required this.displayName,
    required this.submissionCount,
    required this.formTypes,
    required this.submissions,
    this.userId,
    this.username,
    this.firstSubmissionAt,
    this.latestSubmissionAt,
    this.latestIntakeReference,
    this.matchedOn = const [],
  });

  /// EPHEMERAL. Recomputed server-side per request — never persist it, write
  /// it to an audit target, or put it in a URL.
  final String identityKey;

  /// `linked_account` | `pii_fingerprint` | `unlinked_submission`
  final String identitySource;

  /// `high` | `medium` | `low`
  final String confidence;

  final String displayName;
  final int submissionCount;
  final List<String> formTypes;
  final List<ApplicantSubmissionRef> submissions;
  final String? userId;

  /// Mobile account username. Null for walk-ins, who have no account.
  final String? username;

  final String? firstSubmissionAt;
  final String? latestSubmissionAt;
  final String? latestIntakeReference;
  final List<String> matchedOn;

  bool get isLinkedAccount => userId != null && userId!.isNotEmpty;

  /// Two applicants with the same name are told apart by the badges on the
  /// row, so surface where this record came from.
  String get originLabel => isLinkedAccount ? 'Mobile' : 'Walk-in';

  factory ApplicantSummary.fromJson(Map<String, dynamic> json) {
    final rawSubmissions = json['submissions'];
    return ApplicantSummary(
      identityKey: json['identityKey']?.toString() ?? '',
      identitySource: json['identitySource']?.toString() ?? 'unlinked_submission',
      confidence: json['confidence']?.toString() ?? 'low',
      displayName: json['displayName']?.toString() ?? 'Unknown Applicant',
      submissionCount: (json['submissionCount'] as num?)?.toInt() ?? 0,
      formTypes: rawListOfString(json['formTypes']),
      submissions: rawSubmissions is List
          ? rawSubmissions
                .whereType<Map>()
                .map((s) => ApplicantSubmissionRef.fromJson(
                      Map<String, dynamic>.from(s),
                    ))
                .toList()
          : const [],
      userId: json['userId']?.toString(),
      username: json['username']?.toString(),
      firstSubmissionAt: json['firstSubmissionAt']?.toString(),
      latestSubmissionAt: json['latestSubmissionAt']?.toString(),
      latestIntakeReference: json['latestIntakeReference']?.toString(),
      matchedOn: rawListOfString(json['matchedOn']),
    );
  }

  static List<String> rawListOfString(Object? raw) {
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  }
}

/// Diagnostics describing how much work the search actually did.
@immutable
class ApplicantScanStats {
  const ApplicantScanStats({
    this.candidateRows = 0,
    this.decryptedBlobs = 0,
    this.usersResolved = 0,
    this.cacheHits = 0,
    this.truncated = false,
    this.elapsedMs = 0,
  });

  final int candidateRows;
  final int decryptedBlobs;
  final int usersResolved;
  final int cacheHits;
  final bool truncated;
  final int elapsedMs;

  factory ApplicantScanStats.fromJson(Map<String, dynamic> json) {
    return ApplicantScanStats(
      candidateRows: (json['candidateRows'] as num?)?.toInt() ?? 0,
      decryptedBlobs: (json['decryptedBlobs'] as num?)?.toInt() ?? 0,
      usersResolved: (json['usersResolved'] as num?)?.toInt() ?? 0,
      cacheHits: (json['cacheHits'] as num?)?.toInt() ?? 0,
      truncated: json['truncated'] == true,
      elapsedMs: (json['elapsedMs'] as num?)?.toInt() ?? 0,
    );
  }
}

@immutable
class ApplicantSearchResult {
  const ApplicantSearchResult({
    required this.applicants,
    required this.hasMore,
    required this.degraded,
    this.scan = const ApplicantScanStats(),
    this.error,
  });

  final List<ApplicantSummary> applicants;
  final bool hasMore;

  /// The scan hit its row ceiling, so these results are INCOMPLETE. The UI
  /// must say so — silent truncation on a PII lookup tool is a correctness
  /// trap, not a performance detail.
  final bool degraded;

  final ApplicantScanStats scan;
  final String? error;

  bool get isError => error != null;

  static const ApplicantSearchResult empty = ApplicantSearchResult(
    applicants: [],
    hasMore: false,
    degraded: false,
  );

  factory ApplicantSearchResult.failure(String message) =>
      ApplicantSearchResult(
        applicants: const [],
        hasMore: false,
        degraded: false,
        error: message,
      );
}

/// Client for the `search-applicants` Edge Function.
///
/// Search is server-side because applicant PII is AES-GCM ciphertext: the
/// browser cannot filter on names, and pulling every row down to try would
/// neither scale nor be defensible.
class ApplicantSearchService {
  ApplicantSearchService({http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final http.Client _http;

  /// Monotonic request counter. Debouncing alone does not prevent an older,
  /// slower response from landing after a newer one and overwriting it.
  int _seq = 0;

  /// Minimum characters before a query is sent. Below this the result set is
  /// so broad the scan is wasted work.
  static const int minQueryLength = 3;

  /// Discards the response if another [search] started while this one was in
  /// flight. Returns `null` for a superseded call — callers should ignore it
  /// rather than clearing their list.
  Future<ApplicantSearchResult?> search({
    required String staffId,
    String query = '',
    ApplicantSearchFilters filters = const ApplicantSearchFilters(),
    ApplicantSortOrder sort = ApplicantSortOrder.recent,
    int limit = 25,
    int offset = 0,
  }) async {
    final seq = ++_seq;

    try {
      final response = await _http.post(
        supabaseFunctionUri('search-applicants'),
        headers: supabaseFunctionHeaders(),
        body: jsonEncode({
          'staffId': staffId,
          'query': query.trim(),
          'filters': filters.toJson(),
          'sort': sort.wireValue,
          'limit': limit,
          'offset': offset,
        }),
      );

      if (seq != _seq) return null; // superseded

      if (response.statusCode != 200) {
        debugPrint(
          '[ApplicantSearchService/search] status=${response.statusCode} '
          'body=${response.body}',
        );
        return ApplicantSearchResult.failure(
          response.statusCode == 403
              ? 'Your account is not permitted to search applicants.'
              : 'Search failed (${response.statusCode}). Please try again.',
        );
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final rawApplicants = decoded['applicants'];
      final page = decoded['page'] is Map
          ? Map<String, dynamic>.from(decoded['page'] as Map)
          : const <String, dynamic>{};

      return ApplicantSearchResult(
        applicants: rawApplicants is List
            ? rawApplicants
                  .whereType<Map>()
                  .map((a) => ApplicantSummary.fromJson(
                        Map<String, dynamic>.from(a),
                      ))
                  .toList()
            : const [],
        hasMore: page['hasMore'] == true,
        degraded: decoded['degraded'] == true,
        scan: decoded['scan'] is Map
            ? ApplicantScanStats.fromJson(
                Map<String, dynamic>.from(decoded['scan'] as Map),
              )
            : const ApplicantScanStats(),
      );
    } catch (e) {
      if (seq != _seq) return null;
      debugPrint('[ApplicantSearchService/search] Error: $e');
      return ApplicantSearchResult.failure(
        'Could not reach the search service. Check your connection.',
      );
    }
  }

  void dispose() => _http.close();
}
