// Server-side applicant search over encrypted submissions.
//
// client_submissions.data is AES-256-GCM ciphertext and there is no blind
// index, so Postgres cannot filter on names. This function narrows the
// candidate set using the plaintext columns first, decrypts only what
// survives that narrowing, then groups the results into distinct applicants.
//
// Cost is split deliberately by row class (see PHASE B): rows linked to a
// mobile account resolve their name from the small user_field_values EAV —
// once per person, not once per submission — so a repeat visitor with twelve
// submissions costs the same as one with a single submission. The full blob
// decrypt is paid only by walk-in rows, which have no account to resolve
// against, plus the rare linked row whose EAV name is missing.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// Ephemeral. Fingerprints are recomputed per request and never leave it —
// this only keeps raw-PII-derived hashes out of logs.
const SEARCH_FINGERPRINT_SALT = 'sappiire-applicant-fingerprint-v1';

const DEFAULT_SCAN_LIMIT = 1500;
const MAX_SCAN_LIMIT = 3000;
const MAX_PAGE_LIMIT = 50;
const SUBMISSIONS_PER_APPLICANT = 25;
const IN_CHUNK_SESSIONS = 500;
const IN_CHUNK_BLOBS = 200;

// ---------------------------------------------------------------------------
// Crypto helpers — copied verbatim from resolve-applicant-names/index.ts.
// Supabase deploys each function directory independently, so cross-directory
// imports are fragile. Duplication is the correct trade here.
// ---------------------------------------------------------------------------

const base64ToBytes = (base64: string): Uint8Array => {
  const normalized = base64.replace(/\s+/g, '');
  const binary = atob(normalized);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
};

const arrayBufferFromBytes = (bytes: Uint8Array): ArrayBuffer => {
  return bytes.buffer.slice(
    bytes.byteOffset,
    bytes.byteOffset + bytes.byteLength,
  ) as ArrayBuffer;
};

// Derive key using HMAC-SHA256 (same algorithm as derive-field-key)
async function deriveKey(secret: string, userId: string): Promise<Uint8Array> {
  const encoder = new TextEncoder();
  const keyBytes = await crypto.subtle.sign(
    'HMAC',
    await crypto.subtle.importKey(
      'raw',
      encoder.encode(secret),
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['sign'],
    ),
    encoder.encode(userId),
  );
  return new Uint8Array(keyBytes);
}

// Decrypt an AES-GCM field (user_field_values, per-user derived key)
async function decryptField(
  ciphertextB64: string,
  ivB64: string,
  aesKeyBytes: Uint8Array,
): Promise<string> {
  try {
    const ciphertext = base64ToBytes(ciphertextB64);
    const iv = base64ToBytes(ivB64);

    const aesKey = await crypto.subtle.importKey(
      'raw',
      arrayBufferFromBytes(aesKeyBytes),
      { name: 'AES-GCM' },
      false,
      ['decrypt'],
    );

    const decrypted = await crypto.subtle.decrypt(
      { name: 'AES-GCM', iv: arrayBufferFromBytes(iv) },
      aesKey,
      arrayBufferFromBytes(ciphertext),
    );

    return new TextDecoder().decode(new Uint8Array(decrypted));
  } catch {
    return '';
  }
}

// Decrypt one submission blob — copied verbatim from
// decrypt-submission-batch/index.ts:11-31 (server key, not per-user).
async function decryptOne(
  encryptedBase64: string,
  ivBase64: string,
  cryptoKey: CryptoKey,
): Promise<unknown | null> {
  try {
    const iv = Uint8Array.from(atob(ivBase64), (c) => c.charCodeAt(0));
    const ciphertext = Uint8Array.from(
      atob(encryptedBase64),
      (c) => c.charCodeAt(0),
    );
    const buffer = await crypto.subtle.decrypt(
      { name: 'AES-GCM', iv },
      cryptoKey,
      ciphertext,
    );
    return JSON.parse(new TextDecoder().decode(buffer));
  } catch {
    return null; // corrupted or wrong key — caller decides how to handle
  }
}

async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(input),
  );
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

const fingerprint = async (parts: string[]): Promise<string> =>
  (await sha256Hex(`${SEARCH_FINGERPRINT_SALT}|${parts.join('|')}`)).slice(0, 32);

// ---------------------------------------------------------------------------
// Canonical key collapsing — ported from
// lib/services/field_value_service.dart:786-873 (_normalizeCanonicalKey).
// Keeps birthdate / date_of_birth / kapanganakan in one bucket.
// ---------------------------------------------------------------------------

function normalizeCanonicalKey(raw: string): string | null {
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
    // "gitnang pangalan" is a middle name — it also contains "pangalan",
    // so the middle-name test has to win. Guard here rather than reorder,
    // to stay faithful to the Dart ordering for every other input.
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

// Buckets this function actually consumes. Anything else is ignored.
const SEARCHABLE_BUCKETS = new Set([
  'last_name', 'first_name', 'middle_name', 'birth_date', 'phone', 'email',
]);

// ---------------------------------------------------------------------------
// Normalization
// ---------------------------------------------------------------------------

const GENERATIONAL_SUFFIXES = new Set(['jr', 'sr', 'ii', 'iii', 'iv']);

function normalizeToken(raw: unknown): string {
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

const MONTHS: Record<string, number> = {
  jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6,
  jul: 7, aug: 8, sep: 9, oct: 10, nov: 11, dec: 12,
};

// -> "YYYY-MM-DD", or '' when unparseable.
function normalizeBirthDate(raw: unknown): string {
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
    // Ambiguous when both <= 12; resolve as MM/DD/YYYY to match
    // supabase_service.dart:775-806.
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

// Digits only, last 10. '' when fewer than 10 digits survive.
function normalizePhone(raw: unknown): string {
  const digits = (raw ?? '').toString().replace(/\D/g, '');
  return digits.length >= 10 ? digits.slice(-10) : '';
}

function emailLocalPart(raw: unknown): string {
  const s = (raw ?? '').toString().trim().toLowerCase();
  const at = s.indexOf('@');
  return at > 0 ? s.slice(0, at) : '';
}

function formatDisplayName(last: string, first: string, middle: string): string {
  const l = last.trim();
  const f = first.trim();
  const m = middle.trim();
  if (!l && !f) return 'Unknown Applicant';
  // Mirrors ApplicantsController.formatName -> "Last, First M."
  return `${l}, ${f}${m ? ` ${m[0]}.` : ''}`.trim();
}

// ---------------------------------------------------------------------------
// Warm-invocation caches. Projections only (~200 B) — never decrypted blobs
// (2-8 KB), which would put tens of MB in the isolate.
// ---------------------------------------------------------------------------

interface NameProjection {
  last: string;
  first: string;
  middle: string;
  birthDate: string;
  phone: string;
  email: string;
}

interface FieldMap {
  fieldIdToBucket: Record<string, string>;
  candidateFieldIds: string[];
  fieldNameToBucket: Record<string, string>;
}

const PROJ_TTL_MS = 5 * 60_000;
const FIELD_TTL_MS = 10 * 60_000;
const PROJ_MAX = 5000;

const projCache = new Map<string, { v: NameProjection; exp: number }>();
const fieldCache: { map: FieldMap | null; exp: number } = { map: null, exp: 0 };

function projGet(key: string): NameProjection | null {
  const hit = projCache.get(key);
  if (!hit) return null;
  if (hit.exp < Date.now()) {
    projCache.delete(key);
    return null;
  }
  return hit.v;
}

function projSet(key: string, v: NameProjection): void {
  if (projCache.size >= PROJ_MAX) {
    // Map iterates in insertion order — drop the oldest fifth.
    const drop = Math.ceil(PROJ_MAX * 0.2);
    let n = 0;
    for (const k of projCache.keys()) {
      projCache.delete(k);
      if (++n >= drop) break;
    }
  }
  projCache.set(key, { v, exp: Date.now() + PROJ_TTL_MS });
}

const emptyProjection = (): NameProjection => ({
  last: '', first: '', middle: '', birthDate: '', phone: '', email: '',
});

/// `base` wins field by field; `fallback` only fills what is missing.
function mergeProjections(
  base: NameProjection,
  fallback: NameProjection,
): NameProjection {
  const pick = (a: string, b: string) => (a.trim() ? a : b);
  return {
    last: pick(base.last, fallback.last),
    first: pick(base.first, fallback.first),
    middle: pick(base.middle, fallback.middle),
    birthDate: pick(base.birthDate, fallback.birthDate),
    phone: pick(base.phone, fallback.phone),
    email: pick(base.email, fallback.email),
  };
}

// ---------------------------------------------------------------------------
// Union-find over candidate submissions
// ---------------------------------------------------------------------------

class DisjointSet {
  private parent: number[];

  constructor(size: number) {
    this.parent = Array.from({ length: size }, (_, i) => i);
  }

  find(x: number): number {
    let root = x;
    while (this.parent[root] !== root) root = this.parent[root];
    while (this.parent[x] !== root) {
      const next = this.parent[x];
      this.parent[x] = root;
      x = next;
    }
    return root;
  }

  union(a: number, b: number): void {
    const ra = this.find(a);
    const rb = this.find(b);
    if (ra !== rb) this.parent[rb] = ra;
  }
}

// ---------------------------------------------------------------------------

type Confidence = 'high' | 'medium' | 'low';
type IdentitySource = 'linked_account' | 'pii_fingerprint' | 'unlinked_submission';

const CONFIDENCE_RANK: Record<Confidence, number> = { high: 3, medium: 2, low: 1 };

interface CandidateRow {
  id: number;
  sessionId: string | null;
  formType: string;
  createdAt: string;
  intakeReference: string | null;
  encryptionVersion: number;
  userId: string | null;
  projection: NameProjection;
  identityKey: string;
  identitySource: IdentitySource;
  confidence: Confidence;
}

function chunk<T>(items: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) {
    out.push(items.slice(i, i + size));
  }
  return out;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return new Response(
      JSON.stringify({ error: 'Method not allowed' }),
      { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }

  const startedAt = Date.now();

  try {
    const body = await req.json().catch(() => ({}));

    const staffId: string = typeof body?.staffId === 'string' ? body.staffId.trim() : '';
    const rawQuery: string = typeof body?.query === 'string' ? body.query.trim() : '';
    const filters = (body?.filters ?? {}) as Record<string, unknown>;
    const sort: string = typeof body?.sort === 'string' ? body.sort : 'recent';

    const limit = Math.min(
      Math.max(parseInt(`${body?.limit ?? 25}`, 10) || 25, 1),
      MAX_PAGE_LIMIT,
    );
    const offset = Math.max(parseInt(`${body?.offset ?? 0}`, 10) || 0, 0);
    const scanLimit = Math.min(
      Math.max(parseInt(`${body?.scanLimit ?? DEFAULT_SCAN_LIMIT}`, 10) || DEFAULT_SCAN_LIMIT, 1),
      MAX_SCAN_LIMIT,
    );

    // staffId is unconditionally required. Deliberately NOT the
    // `if (staffId)` pattern from decrypt-submission-batch/index.ts:66,
    // which skips validation entirely when the caller omits it.
    if (!staffId) {
      return new Response(
        JSON.stringify({ error: 'Missing required field: staffId' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

    if (!supabaseUrl || !serviceRoleKey) {
      console.error('[search-applicants] Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
      return new Response(
        JSON.stringify({ error: 'Server configuration error' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    // --- Auth: same contract as resolve-applicant-names/index.ts:117-138 ---
    // Any active staff role may search. This returns names and metadata only;
    // full-record decryption stays gated behind decrypt-submission-data.
    const { data: staff, error: staffError } = await supabase
      .from('staff_accounts')
      .select('role, is_active, account_status')
      .eq('cswd_id', staffId)
      .single();

    if (staffError || !staff) {
      console.log(`[search-applicants] Staff not found: staffId=${staffId}`);
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    if (staff.is_active === false || staff.account_status !== 'active') {
      console.log(`[search-applicants] Inactive staff: staffId=${staffId}`);
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // First function needing BOTH secrets — fail fast naming the missing one.
    const serverAesKey = Deno.env.get('SERVER_AES_KEY');
    const fieldKeySecretV2 = Deno.env.get('FIELD_KEY_HMAC_SECRET_V2');

    if (!serverAesKey || !fieldKeySecretV2) {
      const missing = [
        !serverAesKey ? 'SERVER_AES_KEY' : null,
        !fieldKeySecretV2 ? 'FIELD_KEY_HMAC_SECRET_V2' : null,
      ].filter(Boolean).join(', ');
      console.error(`[search-applicants] Missing secret(s): ${missing}`);
      return new Response(
        JSON.stringify({ error: 'Server configuration error', missing }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // =====================================================================
    // PHASE A — plaintext narrowing. Zero crypto. Every SQL-applicable
    // filter runs here, BEFORE anything is decrypted.
    // =====================================================================

    const formType = typeof filters.formType === 'string' && filters.formType.trim() &&
      filters.formType !== 'All' ? filters.formType.trim() : null;
    const dateFrom = typeof filters.dateFrom === 'string' && filters.dateFrom ? filters.dateFrom : null;
    const dateTo = typeof filters.dateTo === 'string' && filters.dateTo ? filters.dateTo : null;
    const refFilter = typeof filters.intakeReference === 'string' && filters.intakeReference.trim()
      ? filters.intakeReference.trim() : null;
    const accountLink = typeof filters.accountLink === 'string' ? filters.accountLink : 'all';

    const METADATA_COLUMNS =
      'id, session_id, form_type, created_at, intake_reference, data_encryption_version';

    const applyCommonFilters = (q: any) => {
      if (formType) q = q.eq('form_type', formType);
      if (dateFrom) q = q.gte('created_at', dateFrom);
      if (dateTo) q = q.lte('created_at', dateTo);
      return q;
    };

    let scanQuery = applyCommonFilters(
      supabase.from('client_submissions').select(METADATA_COLUMNS),
    );
    if (refFilter) scanQuery = scanQuery.ilike('intake_reference', `%${refFilter}%`);
    scanQuery = scanQuery.order('created_at', { ascending: false }).limit(scanLimit);

    const { data: scanRows, error: scanError } = await scanQuery;

    if (scanError) {
      console.error('[search-applicants] Metadata scan failed:', scanError.message);
      return new Response(
        JSON.stringify({ error: 'Database query failed' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const rowsById = new Map<number, Record<string, unknown>>();
    for (const row of (scanRows ?? []) as Array<Record<string, unknown>>) {
      rowsById.set(Number(row.id), row);
    }
    const truncated = (scanRows?.length ?? 0) >= scanLimit;

    // A reference-shaped query gets its own indexed ilike branch, so an exact
    // reference lookup still resolves when the record falls outside the
    // recency-ordered scan window.
    const referenceShaped = /^[A-Za-z0-9][A-Za-z0-9-]{3,}$/.test(rawQuery) && /\d/.test(rawQuery);
    if (referenceShaped && !refFilter) {
      const { data: refRows, error: refError } = await applyCommonFilters(
        supabase.from('client_submissions').select(METADATA_COLUMNS),
      )
        .ilike('intake_reference', `%${rawQuery}%`)
        .order('created_at', { ascending: false })
        .limit(limit * 4);

      if (refError) {
        console.warn('[search-applicants] Reference branch failed:', refError.message);
      } else {
        for (const row of (refRows ?? []) as Array<Record<string, unknown>>) {
          rowsById.set(Number(row.id), row);
        }
      }
    }

    if (rowsById.size === 0) {
      return emptyResult(limit, offset, truncated, startedAt);
    }

    // A2 — session -> user_id join. accountLink is applied here: pre-decrypt.
    const sessionIds = Array.from(rowsById.values())
      .map((r) => (r.session_id ?? '').toString().trim())
      .filter((s) => s.length > 0);

    const sessionToUserId = new Map<string, string>();
    for (const part of chunk(Array.from(new Set(sessionIds)), IN_CHUNK_SESSIONS)) {
      const { data: sessions, error: sessionError } = await supabase
        .from('form_submission')
        .select('id, user_id')
        .in('id', part);

      if (sessionError) {
        console.warn('[search-applicants] Session join failed:', sessionError.message);
        continue;
      }
      for (const s of (sessions ?? []) as Array<Record<string, unknown>>) {
        const uid = (s.user_id ?? '').toString().trim();
        if (uid) sessionToUserId.set((s.id ?? '').toString(), uid);
      }
    }

    const candidates: CandidateRow[] = [];
    for (const row of rowsById.values()) {
      const sessionId = (row.session_id ?? '').toString().trim() || null;
      const userId = sessionId ? (sessionToUserId.get(sessionId) ?? null) : null;

      if (accountLink === 'linked' && !userId) continue;
      if (accountLink === 'walkin' && userId) continue;

      candidates.push({
        id: Number(row.id),
        sessionId,
        formType: (row.form_type ?? '').toString(),
        createdAt: (row.created_at ?? '').toString(),
        intakeReference: row.intake_reference ? row.intake_reference.toString() : null,
        encryptionVersion: Number(row.data_encryption_version ?? 0),
        userId,
        projection: emptyProjection(),
        identityKey: '',
        identitySource: 'unlinked_submission',
        confidence: 'low',
      });
    }

    if (candidates.length === 0) {
      return emptyResult(limit, offset, truncated, startedAt);
    }

    // =====================================================================
    // PHASE B — projection. Cost split by row class.
    // =====================================================================

    const fieldMap = await loadFieldMap(supabase);

    let cacheHits = 0;

    // --- B1: linked rows resolve from the EAV — once per user, not per row.
    const linkedUserIds = Array.from(
      new Set(candidates.map((c) => c.userId).filter((u): u is string => !!u)),
    );

    const projectionsByUser = new Map<string, NameProjection>();
    const usersToFetch: string[] = [];

    for (const userId of linkedUserIds) {
      const cached = projGet(`u:${userId}`);
      if (cached) {
        projectionsByUser.set(userId, cached);
        cacheHits += 1;
      } else {
        usersToFetch.push(userId);
      }
    }

    if (usersToFetch.length > 0 && fieldMap.candidateFieldIds.length > 0) {
      const keyCache: Record<string, Uint8Array> = {};

      for (const part of chunk(usersToFetch, IN_CHUNK_SESSIONS)) {
        const { data: valueRows, error: valuesError } = await supabase
          .from('user_field_values')
          .select('user_id, field_id, field_value, iv, encryption_version, updated_at')
          .in('user_id', part)
          .in('field_id', fieldMap.candidateFieldIds)
          .order('updated_at', { ascending: false });

        if (valuesError) {
          console.warn('[search-applicants] user_field_values fetch failed:', valuesError.message);
          continue;
        }

        // Newest-first ordering means the first non-empty value per bucket
        // wins — same rule as resolve-applicant-names.
        for (const row of (valueRows ?? []) as Array<Record<string, unknown>>) {
          const userId = (row.user_id ?? '').toString();
          const fieldId = (row.field_id ?? '').toString();
          const rawValue = (row.field_value ?? '').toString();

          if (!userId || !fieldId || !rawValue.trim() || rawValue === '__CLEARED__') continue;

          const bucket = fieldMap.fieldIdToBucket[fieldId];
          if (!bucket) continue;

          let projection = projectionsByUser.get(userId);
          if (!projection) {
            projection = emptyProjection();
            projectionsByUser.set(userId, projection);
          }

          if (bucketValue(projection, bucket)) continue; // already filled

          const rawVersion = row.encryption_version;
          const version = typeof rawVersion === 'number'
            ? rawVersion
            : parseInt(rawVersion?.toString() ?? '0', 10) || 0;

          let resolved = '';
          if (version === 2) {
            if (!keyCache[userId]) {
              keyCache[userId] = await deriveKey(fieldKeySecretV2, userId);
            }
            resolved = await decryptField(rawValue, (row.iv ?? '').toString(), keyCache[userId]);
          } else if (version === 0) {
            resolved = rawValue; // legacy plaintext
          } else {
            continue; // v1 and anything unknown is unsupported — skip for safety
          }

          const clean = resolved.trim();
          if (clean && clean !== '__CLEARED__') setBucket(projection, bucket, clean);
        }
      }

      for (const userId of usersToFetch) {
        const projection = projectionsByUser.get(userId) ?? emptyProjection();
        projectionsByUser.set(userId, projection);
        projSet(`u:${userId}`, projection);
      }
    }

    for (const candidate of candidates) {
      if (candidate.userId) {
        candidate.projection = projectionsByUser.get(candidate.userId) ?? emptyProjection();
      }
    }

    // --- B2: blob decrypt, for walk-in rows and for linked rows whose EAV
    // lookup produced no name. That second case matters: a user_field_values
    // row can be missing or cleared even though the submission body still
    // carries the name, and without this fallback that person would show as
    // "Unknown Applicant" and be unfindable by name.
    const needsBlob = candidates.filter(
      (c) => !c.projection.last && !c.projection.first,
    );
    const blobsToFetch: CandidateRow[] = [];

    for (const candidate of needsBlob) {
      const cached = projGet(`s:${candidate.id}`);
      if (cached) {
        candidate.projection = mergeProjections(candidate.projection, cached);
        cacheHits += 1;
      } else {
        blobsToFetch.push(candidate);
      }
    }

    let decryptedBlobs = 0;

    if (blobsToFetch.length > 0) {
      const keyBytes = Uint8Array.from(atob(serverAesKey), (c) => c.charCodeAt(0));
      const cryptoKey = await crypto.subtle.importKey(
        'raw', keyBytes, { name: 'AES-GCM' }, false, ['decrypt'],
      );

      const byId = new Map(blobsToFetch.map((c) => [c.id, c]));

      for (const part of chunk(blobsToFetch.map((c) => c.id), IN_CHUNK_BLOBS)) {
        const { data: blobRows, error: blobError } = await supabase
          .from('client_submissions')
          .select('id, data, data_iv, data_encryption_version')
          .in('id', part);

        if (blobError) {
          console.warn('[search-applicants] Blob fetch failed:', blobError.message);
          continue;
        }

        for (const row of (blobRows ?? []) as Array<Record<string, unknown>>) {
          const candidate = byId.get(Number(row.id));
          if (!candidate) continue;

          let payload: unknown;
          if (Number(row.data_encryption_version ?? 0) !== 1) {
            payload = row.data; // legacy plaintext — same guard as decrypt-submission-batch:109
          } else {
            payload = await decryptOne(
              (row.data ?? '').toString(),
              (row.data_iv ?? '').toString(),
              cryptoKey,
            );
            if (payload !== null) decryptedBlobs += 1;
          }

          const projection = projectFromBlob(payload, fieldMap);
          projSet(`s:${candidate.id}`, projection);
          // Anything the EAV already resolved wins; the blob only fills gaps.
          candidate.projection = mergeProjections(
            candidate.projection,
            projection,
          );
          // The decrypted blob itself is discarded here — only the
          // projection (~200 B) survives this scope.
        }
      }
    }

    // =====================================================================
    // Identity resolution — fingerprint, then union-find.
    // =====================================================================

    // Every candidate gets its canonical identity key AND, independently, the
    // set of strong fingerprints it participates in. Strong fingerprints are
    // computed for linked rows too — that is what lets a walk-in record and a
    // mobile-account record for one person land in the same component.
    const strongKeysPerCandidate: string[][] = [];

    for (const candidate of candidates) {
      const nLast = normalizeToken(candidate.projection.last);
      const nFirst = normalizeToken(candidate.projection.first);
      const nDob = normalizeBirthDate(candidate.projection.birthDate);
      const nPhone = normalizePhone(candidate.projection.phone);
      const nMiddleInitial = normalizeToken(candidate.projection.middle).slice(0, 1);

      const dobKey = (nLast && nFirst && nDob)
        ? `pii:${await fingerprint([nLast, nFirst, nDob])}` : null;
      const phoneKey = (nLast && nFirst && nPhone)
        ? `pii:${await fingerprint([nLast, nFirst, nPhone])}` : null;

      // Low confidence is name-only and must never union — two unrelated
      // "Santos, Maria" have to stay apart.
      strongKeysPerCandidate.push([dobKey, phoneKey].filter((k): k is string => !!k));

      if (candidate.userId) {
        candidate.identityKey = `user:${candidate.userId}`;
        candidate.identitySource = 'linked_account';
        candidate.confidence = 'high';
      } else if (dobKey) {
        candidate.identityKey = dobKey;
        candidate.identitySource = 'pii_fingerprint';
        candidate.confidence = 'high';
      } else if (phoneKey) {
        candidate.identityKey = phoneKey;
        candidate.identitySource = 'pii_fingerprint';
        candidate.confidence = 'medium';
      } else if (nLast && nFirst) {
        candidate.identityKey = `pii:${await fingerprint([nLast, nFirst, nMiddleInitial])}`;
        candidate.identitySource = 'pii_fingerprint';
        candidate.confidence = 'low';
      } else {
        candidate.identityKey = `sub:${candidate.id}`;
        candidate.identitySource = 'unlinked_submission';
        candidate.confidence = 'low';
      }
    }

    const dsu = new DisjointSet(candidates.length);
    const firstByUser = new Map<string, number>();
    const firstByStrongKey = new Map<string, number>();

    candidates.forEach((candidate, index) => {
      if (candidate.userId) {
        const seen = firstByUser.get(candidate.userId);
        if (seen === undefined) firstByUser.set(candidate.userId, index);
        else dsu.union(seen, index);
      }

      for (const key of strongKeysPerCandidate[index]) {
        const seen = firstByStrongKey.get(key);
        if (seen === undefined) firstByStrongKey.set(key, index);
        else dsu.union(seen, index);
      }
    });

    // Collapse components into applicants.
    const components = new Map<number, number[]>();
    candidates.forEach((_, index) => {
      const root = dsu.find(index);
      const list = components.get(root) ?? [];
      list.push(index);
      components.set(root, list);
    });

    const queryTokens = rawQuery
      .split(/\s+/)
      .map(normalizeToken)
      .filter((t) => t.length > 0);

    interface Applicant {
      identityKey: string;
      identitySource: IdentitySource;
      confidence: Confidence;
      displayName: string;
      nameParts: { last: string; first: string; middle: string };
      userId: string | null;
      submissionCount: number;
      firstSubmissionAt: string;
      latestSubmissionAt: string;
      formTypes: string[];
      latestIntakeReference: string | null;
      matchedOn: string[];
      submissions: Array<Record<string, unknown>>;
      sortName: string;
    }

    const applicants: Applicant[] = [];

    for (const members of components.values()) {
      const rows = members
        .map((i) => candidates[i])
        .sort((a, b) => b.createdAt.localeCompare(a.createdAt));

      const linked = rows.find((r) => r.userId);
      const strongest = rows.reduce((best, r) =>
        CONFIDENCE_RANK[r.confidence] > CONFIDENCE_RANK[best.confidence] ? r : best, rows[0]);

      const canonical = linked ?? strongest;
      const weakest = rows.reduce((worst, r) =>
        CONFIDENCE_RANK[r.confidence] < CONFIDENCE_RANK[worst.confidence] ? r : worst, rows[0]);

      // Best available name across the component.
      const named = rows.find((r) => r.projection.last || r.projection.first) ?? rows[0];
      const { last, first, middle } = named.projection;

      // --- PHASE C: match. Every query token must hit some haystack entry.
      const haystack: Array<{ value: string; kind: string }> = [];
      const nLast = normalizeToken(last);
      const nFirst = normalizeToken(first);
      const nMiddle = normalizeToken(middle);

      if (nLast) haystack.push({ value: nLast, kind: 'name' });
      if (nFirst) haystack.push({ value: nFirst, kind: 'name' });
      if (nMiddle) haystack.push({ value: nMiddle, kind: 'name' });
      if (nLast && nFirst) {
        haystack.push({ value: nLast + nFirst, kind: 'name' });
        haystack.push({ value: nFirst + nLast, kind: 'name' });
      }
      for (const row of rows) {
        if (row.intakeReference) {
          const n = normalizeToken(row.intakeReference);
          if (n) haystack.push({ value: n, kind: 'reference' });
        }
      }
      for (const row of rows) {
        const phone = normalizePhone(row.projection.phone);
        if (phone) haystack.push({ value: phone.slice(-4), kind: 'contact' });
        const local = normalizeToken(emailLocalPart(row.projection.email));
        if (local) haystack.push({ value: local, kind: 'contact' });
      }

      const matchedKinds = new Set<string>();
      let matches = true;
      for (const token of queryTokens) {
        const hit = haystack.find((h) => h.value.includes(token));
        if (!hit) { matches = false; break; }
        matchedKinds.add(hit.kind);
      }
      if (!matches) continue;

      const formTypes = Array.from(
        new Set(rows.map((r) => r.formType).filter((f) => f.length > 0)),
      ).sort();

      applicants.push({
        identityKey: canonical.identityKey,
        identitySource: canonical.identitySource,
        confidence: weakest.confidence,
        displayName: formatDisplayName(last, first, middle),
        nameParts: { last, first, middle },
        userId: linked?.userId ?? null,
        submissionCount: rows.length,
        firstSubmissionAt: rows[rows.length - 1].createdAt,
        latestSubmissionAt: rows[0].createdAt,
        formTypes,
        latestIntakeReference: rows.find((r) => r.intakeReference)?.intakeReference ?? null,
        matchedOn: Array.from(matchedKinds),
        submissions: rows.slice(0, SUBMISSIONS_PER_APPLICANT).map((r) => ({
          id: r.id,
          sessionId: r.sessionId,
          formType: r.formType,
          createdAt: r.createdAt,
          intakeReference: r.intakeReference,
        })),
        sortName: `${normalizeToken(last)}${normalizeToken(first)}`,
      });
    }

    // --- PHASE D: sort, paginate, trim.
    applicants.sort((a, b) => {
      switch (sort) {
        case 'oldest':
          return a.latestSubmissionAt.localeCompare(b.latestSubmissionAt);
        case 'name':
          return a.sortName.localeCompare(b.sortName);
        case 'most_records':
          return b.submissionCount - a.submissionCount ||
            b.latestSubmissionAt.localeCompare(a.latestSubmissionAt);
        default:
          return b.latestSubmissionAt.localeCompare(a.latestSubmissionAt);
      }
    });

    const total = applicants.length;
    const page = applicants.slice(offset, offset + limit).map(({ sortName: _s, ...rest }) => rest);

    const elapsedMs = Date.now() - startedAt;
    const scan = {
      candidateRows: candidates.length,
      decryptedBlobs,
      usersResolved: projectionsByUser.size,
      cacheHits,
      truncated,
      elapsedMs,
    };

    console.log(
      `[search-applicants] staff=${staffId} tokens=${queryTokens.length} ` +
      `candidates=${candidates.length} blobs=${decryptedBlobs} users=${projectionsByUser.size} ` +
      `cacheHits=${cacheHits} applicants=${total} truncated=${truncated} ${elapsedMs}ms`,
    );

    await writeAuditRow(supabase, {
      staffId,
      role: staff.role,
      rawQuery,
      queryTokens: queryTokens.length,
      formType,
      dateFrom,
      dateTo,
      hasReferenceFilter: !!refFilter || referenceShaped,
      accountLink,
      scan,
      returned: page.length,
    });

    return new Response(
      JSON.stringify({
        applicants: page,
        page: { limit, offset, returned: page.length, hasMore: offset + page.length < total },
        scan,
        degraded: truncated,
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error';
    console.error('[search-applicants] Error:', message);
    return new Response(
      JSON.stringify({ error: 'Applicant search failed', details: message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

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

async function loadFieldMap(supabase: any): Promise<FieldMap> {
  if (fieldCache.map && fieldCache.exp > Date.now()) return fieldCache.map;

  const empty: FieldMap = { fieldIdToBucket: {}, candidateFieldIds: [], fieldNameToBucket: {} };

  const { data: fieldRows, error } = await supabase
    .from('form_fields')
    .select('field_id, field_name, canonical_field_key')
    .not('canonical_field_key', 'is', null);

  if (error) {
    console.warn('[search-applicants] form_fields fetch failed:', error.message);
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

// Literal fallbacks mirroring ApplicantsController.getApplicantName
// (applicants_controller.dart:47-64) for blobs whose keys carry no
// canonical_field_key mapping.
const LITERAL_KEY_BUCKETS: Array<[string[], string]> = [
  [['last_name', 'Last Name', 'lastname', 'Apelyido'], 'last_name'],
  [['first_name', 'First Name', 'firstname', 'Pangalan'], 'first_name'],
  [['middle_name', 'Middle Name', 'middlename', 'Gitnang Pangalan'], 'middle_name'],
  [['date_of_birth', 'Date of Birth', 'birthdate', 'birth_date', 'Kapanganakan'], 'birth_date'],
  [['cp_number', 'contact_number', 'phone_number', 'Contact Number'], 'phone'],
  [['email', 'email_address', 'Email Address'], 'email'],
];

function projectFromBlob(payload: unknown, fieldMap: FieldMap): NameProjection {
  const projection = emptyProjection();
  if (payload === null || typeof payload !== 'object') return projection;

  const data = payload as Record<string, unknown>;

  // An embedded __applicant_name is authoritative when it isn't itself
  // an encrypted token (guarded by ApplicantsController.looksEncryptedToken).
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

// Port of ApplicantsController.looksEncryptedToken (applicants_controller.dart:161-167)
function looksEncryptedToken(value: string): boolean {
  const v = value.trim();
  if (v.length < 24) return false;
  if (v.includes(' ') || v.includes(',')) return false;
  if (!/^[A-Za-z0-9+/=]+$/.test(v)) return false;
  return /[0-9+/=]/.test(v);
}

function emptyResult(
  limit: number,
  offset: number,
  truncated: boolean,
  startedAt: number,
): Response {
  return new Response(
    JSON.stringify({
      applicants: [],
      page: { limit, offset, returned: 0, hasMore: false },
      scan: {
        candidateRows: 0, decryptedBlobs: 0, usersResolved: 0,
        cacheHits: 0, truncated, elapsedMs: Date.now() - startedAt,
      },
      degraded: truncated,
    }),
    { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
  );
}

// One aggregated row per search. Never logs the raw query, any name, or any
// intake_reference value — query_hash is stable for a repeat and distinct for
// a different query, which is enough to spot abusive lookup patterns without
// revealing who was searched for.
async function writeAuditRow(supabase: any, ctx: {
  staffId: string;
  role: string | null;
  rawQuery: string;
  queryTokens: number;
  formType: string | null;
  dateFrom: string | null;
  dateTo: string | null;
  hasReferenceFilter: boolean;
  accountLink: string;
  scan: Record<string, unknown>;
  returned: number;
}): Promise<void> {
  const queryHash = ctx.rawQuery
    ? (await sha256Hex(`${SEARCH_FINGERPRINT_SALT}|${ctx.rawQuery.toLowerCase()}`)).slice(0, 16)
    : '';

  const details = {
    query_length: ctx.rawQuery.length,
    query_hash: queryHash,
    token_count: ctx.queryTokens,
    filters: {
      form_type: ctx.formType,
      date_from: ctx.dateFrom,
      date_to: ctx.dateTo,
      has_reference_filter: ctx.hasReferenceFilter,
      account_link: ctx.accountLink,
    },
    candidate_rows: ctx.scan.candidateRows,
    decrypted_blobs: ctx.scan.decryptedBlobs,
    users_resolved: ctx.scan.usersResolved,
    applicants_returned: ctx.returned,
    truncated: ctx.scan.truncated,
    elapsed_ms: ctx.scan.elapsedMs,
  };

  const base = {
    category: 'submission',
    severity: 'warning',
    actor_id: ctx.staffId,
    actor_role: ctx.role,
    target_type: 'client_submissions',
  };

  try {
    const { error } = await supabase.from('audit_logs').insert({
      ...base,
      action_type: 'applicant_search',
      details,
    });
    if (!error) return;

    // The live audit_logs table may carry a CHECK on action_type and no DDL
    // is permitted, so fall back to a value already known to be accepted.
    console.warn('[search-applicants] applicant_search action_type rejected:', error.message);
    await supabase.from('audit_logs').insert({
      ...base,
      action_type: 'applicant_names_resolved',
      details: { ...details, purpose: 'search', intended_action: 'applicant_search' },
    });
  } catch (e) {
    // Audit failure must never fail the search.
    console.error('[search-applicants] Audit log insert failed:', e);
  }
}
