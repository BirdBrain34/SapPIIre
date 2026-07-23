/// Supabase project endpoint and public anon key.
///
/// These values are duplicated as string literals throughout
/// `submission_service.dart` and elsewhere. New code should import them from
/// here instead; the existing literals are left alone deliberately, since a
/// repo-wide sweep is its own change.
///
/// The anon key is public by design — it is shipped in every web build and is
/// safe to commit. Confidentiality rests on ciphertext and Edge Function
/// authorization, not on this key being secret.
library;

const String kSupabaseUrl = 'https://tgbfxepldpdswxehhlkx.supabase.co';

const String kSupabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRnYmZ4ZXBsZHBkc3d4ZWhobGt4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA4NDYzMDcsImV4cCI6MjA4NjQyMjMwN30.DhoD6RHExKynXw34mibc3XRP-NwfmDnq1PttVM7-GL4';

/// Standard headers for a direct Edge Function invocation.
Map<String, String> supabaseFunctionHeaders() => const {
  'Authorization': 'Bearer $kSupabaseAnonKey',
  'apikey': kSupabaseAnonKey,
  'Content-Type': 'application/json',
};

/// Absolute URL for the named Edge Function.
Uri supabaseFunctionUri(String functionName) =>
    Uri.parse('$kSupabaseUrl/functions/v1/$functionName');
