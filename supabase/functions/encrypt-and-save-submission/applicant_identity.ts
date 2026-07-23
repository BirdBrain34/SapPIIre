// ---------------------------------------------------------------------------
// Applicant identity derivation for submission dedup.
//
// Spec: docs/15_Submission_Deduplication.md
//
// Copied from supabase/functions/search-applicants/index.ts, which itself
// notes at :34-38 that Supabase deploys each function directory independently,
// so cross-directory imports are fragile and duplication is the correct trade.
// Source line ranges are cited per helper below. Keep them in sync by hand.
//
// This lives beside index.ts rather than inside it so tests can import it
// without triggering the top-level Deno.serve().
// ---------------------------------------------------------------------------

// search-applicants/index.ts:25.
//
// MUST stay server-side. Name + date of birth is low-entropy and trivially
// enumerable offline, so publishing this salt -- e.g. by shipping a hash
// implementation into the Flutter web bundle, where it becomes readable JS --
// would turn the plaintext applicant_key column into recoverable PII.
const SEARCH_FINGERPRINT_SALT = 'sappiire-applicant-fingerprint-v1';

const FIELD_TTL_MS = 10 * 60_000;

export interface NameProjection {
  last: string;
  first: string;
  middle: string;
  birthDate: string;
  phone: string;
  email: string;
}

export interface FieldMap {
  fieldIdToBucket: Record<string, string>;
  candidateFieldIds: string[];
  fieldNameToBucket: Record<string, string>;
}

const fieldCache: { map: FieldMap | null; exp: number } = { map: null, exp: 0 };

export function emptyProjection(): NameProjection {
  return { last: '', first: '', middle: '', birthDate: '', phone: '', email: '' };
}

// search-applicants/index.ts:128-139.
async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(input),
  );
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

export const fingerprint = async (parts: string[]): Promise<string> =>
  (await sha256Hex(`${SEARCH_FINGERPRINT_SALT}|${parts.join('|')}`)).slice(0, 32);

// search-applicants/index.ts:147-189.
export function normalizeCanonicalKey(raw: string): string | null {
  const t = raw.trim().toLowerCase();
  if (!t) return null;

  if (
    t === 'lastname' || t === 'last_name' || t === 'surname' ||
    t === 'family_name' || t.includes('apelyido') ||
    (t.includes('last') && t.includes('name'))
  ) return 'last_name';

  if (
    t === 'firstname' || t === 'first_name' || t === 'given_name' ||
    t === 'given_names' || t.includes('pangalan') ||
    (t.includes('first') && t.includes('name'))
  ) {
    // "gitnang pangalan" is a middle name -- it also contains "pangalan",
    // so the middle-name test has to win.
    if (!t.includes('gitnang')) return 'first_name';
  }

  if (
    t === 'middlename' || t === 'middle_name' || t.includes('gitnang') ||
    (t.includes('middle') && t.includes('name'))
  ) return 'middle_name';

  if (
    t === 'birthdate' || t === 'date_of_birth' || t.includes('kapanganakan') ||
    (t.includes('birth') && (t.includes('date') || t.includes('day')))
  ) return 'birth_date';

  if (
    t === 'cp_number' || t === 'contact_no' || t === 'contact_number' ||
    t === 'mobile_no' || t === 'cellphone_number' ||
    t.includes('phone') || t.includes('mobile') || t.includes('contact')
  ) return 'phone';

  if (t === 'email_address' || t.includes('email') || t.includes('e_mail')) {
    return 'email';
  }

  return null;
}

// search-applicants/index.ts:192-194.
const SEARCHABLE_BUCKETS = new Set([
  'last_name', 'first_name', 'middle_name', 'birth_date', 'phone', 'email',
]);

// search-applicants/index.ts:200-214.
const GENERATIONAL_SUFFIXES = new Set(['jr', 'sr', 'ii', 'iii', 'iv']);

export function normalizeToken(raw: unknown): string {
  const s = (raw ?? '').toString();
  if (!s.trim()) return '';
  const stripped = s
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '') // strip combining marks: Jose accents -> Jose
    .toLowerCase();

  return stripped
    .split(/[^a-z0-9]+/)
    .filter((part) => part.length > 0 && !GENERATIONAL_SUFFIXES.has(part))
    .join('');
}

// search-applicants/index.ts:216-253.
const MONTHS: Record<string, number> = {
  jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6,
  jul: 7, aug: 8, sep: 9, oct: 10, nov: 11, dec: 12,
};

export function normalizeBirthDate(raw: unknown): string {
  const s = (raw ?? '').toString().trim();
  if (!s) return '';

  const pad = (n: number) => n.toString().padStart(2, '0');
  const build = (y: number, m: number, d: number): string =>
    (y >= 1900 && y <= 2200 && m >= 1 && m <= 12 && d >= 1 && d <= 31)
      ? `${y}-${pad(m)}-${pad(d)}`
      : '';

  const iso = s.match(/^(\d{4})-(\d{1,2})-(\d{1,2})/);
  if (iso) return build(+iso[1], +iso[2], +iso[3]);

  const slash = s.match(/^(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{4})$/);
  if (slash) {
    const a = +slash[1];
    const b = +slash[2];
    const year = +slash[3];
    // Ambiguous when both <= 12; resolve as MM/DD/YYYY.
    if (a > 12 && b <= 12) return build(year, b, a); // DD/MM/YYYY
    return build(year, a, b);                        // MM/DD/YYYY
  }

  const monthName = s.match(/^([A-Za-z]{3,})\.?\s+(\d{1,2}),?\s+(\d{4})$/);
  if (monthName) {
    const m = MONTHS[monthName[1].slice(0, 3).toLowerCase()];
    if (m) return build(+monthName[3], m, +monthName[2]);
  }

  return '';
}

// search-applicants/index.ts:256-259.
export function normalizePhone(raw: unknown): string {
  const digits = (raw ?? '').toString().replace(/\D/g, '');
  return digits.length >= 10 ? digits.slice(-10) : '';
}

// search-applicants/index.ts:1066-1087.
function bucketValue(projection: NameProjection, bucket: string): string {
  switch (bucket) {
    case 'last_name': return projection.last;
    case 'first_name': return projection.first;
    case 'middle_name': return projection.middle;
    case 'birth_date': return projection.birthDate;
    case 'phone': return projection.phone;
    case 'email': return projection.email;
    default: return '';
  }
}

function setBucket(projection: NameProjection, bucket: string, value: string): void {
  switch (bucket) {
    case 'last_name': projection.last = value; break;
    case 'first_name': projection.first = value; break;
    case 'middle_name': projection.middle = value; break;
    case 'birth_date': projection.birthDate = value; break;
    case 'phone': projection.phone = value; break;
    case 'email': projection.email = value; break;
  }
}

// search-applicants/index.ts:1089-1123.
//
// Payload keys are human-readable labels ("Date of Birth"), not field ids, so
// resolving them requires form_fields.canonical_field_key. The 10-minute
// warm-isolate cache amortizes that to roughly nothing.
export async function loadFieldMap(supabase: any): Promise<FieldMap> {
  if (fieldCache.map && fieldCache.exp > Date.now()) return fieldCache.map;

  const empty: FieldMap = { fieldIdToBucket: {}, candidateFieldIds: [], fieldNameToBucket: {} };

  const { data: fieldRows, error } = await supabase
    .from('form_fields')
    .select('field_id, field_name, canonical_field_key')
    .not('canonical_field_key', 'is', null);

  if (error) {
    console.warn('[encrypt-and-save-submission] form_fields fetch failed:', error.message);
    return fieldCache.map ?? empty;
  }

  const map: FieldMap = { fieldIdToBucket: {}, candidateFieldIds: [], fieldNameToBucket: {} };

  for (const row of (fieldRows ?? []) as Array<Record<string, unknown>>) {
    const bucket = normalizeCanonicalKey((row.canonical_field_key ?? '').toString());
    if (!bucket || !SEARCHABLE_BUCKETS.has(bucket)) continue;

    const fieldId = (row.field_id ?? '').toString();
    if (fieldId) {
      map.fieldIdToBucket[fieldId] = bucket;
      map.candidateFieldIds.push(fieldId);
    }

    const fieldName = (row.field_name ?? '').toString();
    if (fieldName) map.fieldNameToBucket[fieldName] = bucket;
  }

  fieldCache.map = map;
  fieldCache.exp = Date.now() + FIELD_TTL_MS;
  return map;
}

// search-applicants/index.ts:1128-1135.
const LITERAL_KEY_BUCKETS: Array<[string[], string]> = [
  [['last_name', 'Last Name', 'lastname', 'Apelyido'], 'last_name'],
  [['first_name', 'First Name', 'firstname', 'Pangalan'], 'first_name'],
  [['middle_name', 'Middle Name', 'middlename', 'Gitnang Pangalan'], 'middle_name'],
  [['date_of_birth', 'Date of Birth', 'birthdate', 'birth_date', 'Kapanganakan'], 'birth_date'],
  [['cp_number', 'contact_number', 'phone_number', 'Contact Number'], 'phone'],
  [['email', 'email_address', 'Email Address'], 'email'],
];

// search-applicants/index.ts:1137-1175.
//
// Note: __applicant_name is excluded from the CSH-1 hash but is still read
// here. Not a contradiction -- identity tolerates a missing name and falls
// back to field lookup, whereas the hash cannot tolerate a key that appears
// and disappears between runs. It also carries no birth date, so loadFieldMap
// is required even when it is present.
export function projectFromBlob(payload: unknown, fieldMap: FieldMap): NameProjection {
  const projection = emptyProjection();
  if (payload === null || typeof payload !== 'object') return projection;

  const data = payload as Record<string, unknown>;

  const embedded = data['__applicant_name'];
  if (embedded && typeof embedded === 'object') {
    const n = embedded as Record<string, unknown>;
    const last = (n.last ?? '').toString().trim();
    const first = (n.first ?? '').toString().trim();
    if ((last || first) && !looksEncryptedToken(last) && !looksEncryptedToken(first)) {
      projection.last = last;
      projection.first = first;
      projection.middle = (n.middle ?? '').toString().trim();
    }
  }

  for (const [key, raw] of Object.entries(data)) {
    if (key.startsWith('__')) continue;
    const value = (raw ?? '').toString().trim();
    if (!value) continue;

    let bucket = fieldMap.fieldNameToBucket[key] ?? normalizeCanonicalKey(key);
    if (!bucket) {
      for (const [aliases, target] of LITERAL_KEY_BUCKETS) {
        if (aliases.includes(key)) { bucket = target; break; }
      }
    }
    if (!bucket || !SEARCHABLE_BUCKETS.has(bucket)) continue;
    if (bucketValue(projection, bucket)) continue;

    setBucket(projection, bucket, value);
  }

  return projection;
}

// search-applicants/index.ts:1178-1184.
export function looksEncryptedToken(value: string): boolean {
  const v = value.trim();
  if (v.length < 24) return false;
  if (v.includes(' ') || v.includes(',')) return false;
  if (!/^[A-Za-z0-9+/=]+$/.test(v)) return false;
  return /[0-9+/=]/.test(v);
}

/// Resolves the dedup scope for a submission.
///
/// Returns `null` when identity is not derivable, which disables dedup for
/// that row. See docs/15_Submission_Deduplication.md for why a NULL key skips
/// dedup rather than falling back to content_hash alone, and why the
/// name-only branch present in search-applicants:845-848 is deliberately
/// omitted here.
export async function deriveApplicantKey(
  supabase: any,
  sessionId: string,
  data: unknown,
): Promise<string | null> {
  // 1. A linked mobile account is the strongest signal.
  try {
    const { data: session } = await supabase
      .from('form_submission')
      .select('user_id')
      .eq('id', sessionId)
      .maybeSingle();

    const userId = session?.user_id?.toString() ?? '';
    if (userId) return `user:${userId}`;
  } catch (error) {
    const message = error instanceof Error ? error.message : 'unknown';
    console.warn('[encrypt-and-save-submission] session lookup failed:', message);
    // Fall through to the PII fingerprint rather than failing the submission.
  }

  // 2. Walk-ins have no account. Fall back to a salted PII fingerprint.
  const fieldMap = await loadFieldMap(supabase);
  const projection = projectFromBlob(data, fieldMap);

  const nLast = normalizeToken(projection.last);
  const nFirst = normalizeToken(projection.first);
  const nDob = normalizeBirthDate(projection.birthDate);
  const nPhone = normalizePhone(projection.phone);

  if (nLast && nFirst && nDob) {
    return `pii:${await fingerprint([nLast, nFirst, nDob])}`;
  }
  if (nLast && nFirst && nPhone) {
    return `pii:${await fingerprint([nLast, nFirst, nPhone])}`;
  }

  // 3. Name-only would collide two unrelated "Santos, Maria". search-applicants
  //    tolerates that because it only groups; here it would BLOCK a real
  //    applicant at a counter. Skip dedup instead.
  return null;
}
