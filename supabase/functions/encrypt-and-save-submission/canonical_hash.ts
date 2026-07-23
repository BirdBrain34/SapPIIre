// ---------------------------------------------------------------------------
// CSH-1 — Canonical Submission Hash, version 1.
//
// Normative spec: docs/15_Submission_Deduplication.md
//
// Produces a stable digest of a plaintext submission payload so two logically
// identical submissions hash identically, regardless of key order, whitespace,
// or the empty/null/absent distinction that FormStateController.toJson()
// leaves ambiguous (lib/dynamic_form/form_state_controller.dart:538-592).
//
// This lives in its own module rather than in index.ts so the test suite can
// import it without triggering the top-level Deno.serve() in index.ts.
//
// Any change to the rules below is a spec change and REQUIRES bumping
// HASH_VERSION, because stored hashes are compared across deploys.
// ---------------------------------------------------------------------------

export const HASH_VERSION = 'v1';

/// Top-level keys removed before hashing.
///
/// `__session_id` changes on every QR session; including it would mean the
/// hash never matches and dedup silently never fires.
///
/// `__applicant_name` is derived metadata, not a staff-entered answer, and it
/// is *unstable*: ManageFormsController.embedApplicantName
/// (lib/web/controllers/manage_forms_controller.dart:189-261) makes two network
/// calls inside a try/catch that swallows failures, then falls through to two
/// progressively weaker heuristics. A transient RPC failure changes the key's
/// shape or drops it entirely, so an otherwise-identical payload would hash
/// differently with nothing logging why.
///
/// `__signature` is deliberately NOT excluded — see the spec doc. A re-signed
/// form is treated as a genuine update.
export const EXCLUDED_TOP_LEVEL_KEYS = new Set<string>([
  '__session_id',
  '__applicant_name',
]);

/// Sentinel meaning "this entry disappears from its parent container".
const OMIT = Symbol('OMIT');

type Canonical = string | CanonicalMap | CanonicalList | typeof OMIT;
interface CanonicalMap {
  [key: string]: Exclude<Canonical, typeof OMIT>;
}
type CanonicalList = Array<Exclude<Canonical, typeof OMIT>>;

/// Finite number -> shortest round-trip decimal, no exponent, no trailing
/// zeros, `-0` collapsed to `"0"`.
///
/// Dart and JS disagree on default number stringification (`1.0` renders as
/// "1.0" in Dart and "1" in JS), so the rule is pinned explicitly here rather
/// than delegated to either runtime's default.
function numberToCanonicalString(n: number): string {
  if (Object.is(n, -0)) return '0';

  const s = String(n);
  if (!s.includes('e') && !s.includes('E')) return s;

  // Expand exponential notation to plain decimal.
  const [mantissa, expPart] = s.split(/[eE]/);
  const exp = Number(expPart);
  const negative = mantissa.startsWith('-');
  const unsigned = negative ? mantissa.slice(1) : mantissa;
  const [intPart, fracPart = ''] = unsigned.split('.');

  let digits = intPart + fracPart;
  let pointPos = intPart.length + exp;

  let out: string;
  if (pointPos <= 0) {
    out = '0.' + '0'.repeat(-pointPos) + digits;
  } else if (pointPos >= digits.length) {
    out = digits + '0'.repeat(pointPos - digits.length);
  } else {
    out = digits.slice(0, pointPos) + '.' + digits.slice(pointPos);
  }

  if (out.includes('.')) out = out.replace(/\.?0+$/, '');
  if (out === '' || out === '-') out = '0';
  return negative && out !== '0' ? '-' + out : out;
}

/// Recursive normalization. See spec §Step 2.
function norm(value: unknown): Canonical {
  if (value === null || value === undefined) return OMIT;

  if (typeof value === 'string') {
    const trimmed = value.trim();
    return trimmed.length === 0 ? OMIT : trimmed;
  }

  if (typeof value === 'boolean') return value ? 'true' : 'false';

  if (typeof value === 'number') {
    if (!Number.isFinite(value)) return OMIT;
    return numberToCanonicalString(value);
  }

  if (typeof value === 'bigint') return value.toString();

  if (Array.isArray(value)) {
    // Order IS significant and is NOT sorted — __family_composition row order
    // is user-meaningful. Only survivors are kept, in their original order.
    const out: CanonicalList = [];
    for (const element of value) {
      const normalized = norm(element);
      if (normalized === OMIT) continue;
      out.push(normalized);
    }
    return out.length === 0 ? OMIT : out;
  }

  if (typeof value === 'object') {
    const source = value as Record<string, unknown>;
    const out: CanonicalMap = {};
    let kept = 0;
    // Sort by UTF-16 code unit — what both Dart's String.compareTo and JS's
    // default Array.prototype.sort do natively. Not locale-aware.
    for (const key of Object.keys(source).sort()) {
      const normalized = norm(source[key]);
      if (normalized === OMIT) continue;
      out[key] = normalized;
      kept += 1;
    }
    return kept === 0 ? OMIT : out;
  }

  // Anything exotic (function, symbol) cannot appear in parsed JSON.
  return OMIT;
}

/// Explicit serializer. Deliberately NOT JSON.stringify — its escaping of
/// control characters and lone surrogates differs from Dart's jsonEncode.
function serialize(value: Exclude<Canonical, typeof OMIT>): string {
  if (typeof value === 'string') return escapeString(value);

  if (Array.isArray(value)) {
    return '[' + value.map(serialize).join(',') + ']';
  }

  const entries = Object.keys(value).map(
    (key) => escapeString(key) + ':' + serialize(value[key]),
  );
  return '{' + entries.join(',') + '}';
}

function escapeString(raw: string): string {
  let out = '"';
  for (const char of splitCodeUnits(raw)) {
    const code = char.charCodeAt(0);
    if (char === '\\') out += '\\\\';
    else if (char === '"') out += '\\"';
    else if (code < 0x20) out += '\\u' + code.toString(16).padStart(4, '0');
    else out += char;
  }
  return out + '"';
}

/// Iterate UTF-16 code units, not code points — a lone surrogate must survive
/// byte-for-byte rather than being replaced with U+FFFD.
function splitCodeUnits(raw: string): string[] {
  const out: string[] = [];
  for (let i = 0; i < raw.length; i += 1) out.push(raw[i]);
  return out;
}

/// The canonical string for a payload. Exported so tests can assert the
/// intermediate form: a mismatch here localizes which rule broke, whereas a
/// bare hash mismatch only says that something did.
export function canonicalize(data: unknown): string {
  let source: Record<string, unknown> = {};
  if (data !== null && typeof data === 'object' && !Array.isArray(data)) {
    source = { ...(data as Record<string, unknown>) };
    for (const key of EXCLUDED_TOP_LEVEL_KEYS) delete source[key];
  }

  const normalized = norm(source);
  if (normalized === OMIT) return '{}';
  return serialize(normalized);
}

/// `"v1:<64 lowercase hex chars>"`.
export async function computeContentHash(data: unknown): Promise<string> {
  const canonical = canonicalize(data);
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(canonical),
  );
  const hex = Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
  return `${HASH_VERSION}:${hex}`;
}
