// Run from the repo root:
//   deno test --allow-read supabase/functions/encrypt-and-save-submission/canonical_hash_test.ts
//
// test/fixtures/canonical_hash_vectors.json is the normative contract for
// CSH-1 (docs/15_Submission_Deduplication.md). Changing a vector is a spec
// change and requires bumping HASH_VERSION in canonical_hash.ts.
//
// Each vector asserts the intermediate canonical string as well as the final
// hash: a canonical mismatch tells you WHICH rule broke, where a bare hash
// mismatch only tells you that something did.

import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { canonicalize, computeContentHash, HASH_VERSION } from './canonical_hash.ts';

interface Vector {
  name: string;
  input: unknown;
  canonical: string;
  hash: string;
}

interface Group {
  name: string;
  members: string[];
}

interface Fixture {
  spec: string;
  vectors: Vector[];
  equivalenceGroups: Group[];
  distinctGroups: Group[];
}

const fixture: Fixture = JSON.parse(
  await Deno.readTextFile(
    new URL('../../../test/fixtures/canonical_hash_vectors.json', import.meta.url),
  ),
);

const byName = new Map(fixture.vectors.map((v) => [v.name, v]));

Deno.test('fixture is loadable and non-trivial', () => {
  assertEquals(fixture.spec, 'CSH-1');
  if (fixture.vectors.length < 40) {
    throw new Error(`expected at least 40 vectors, got ${fixture.vectors.length}`);
  }
});

for (const vector of fixture.vectors) {
  Deno.test(`canonical: ${vector.name}`, () => {
    assertEquals(canonicalize(vector.input), vector.canonical);
  });

  Deno.test(`hash: ${vector.name}`, async () => {
    const hash = await computeContentHash(vector.input);
    assertEquals(hash, vector.hash);
    assertEquals(hash.startsWith(`${HASH_VERSION}:`), true);
    // v1 prefix + 64 lowercase hex chars.
    assertEquals(/^v1:[0-9a-f]{64}$/.test(hash), true);
  });
}

for (const group of fixture.equivalenceGroups) {
  Deno.test(`equivalence: ${group.name}`, async () => {
    const hashes = new Set<string>();
    for (const member of group.members) {
      const vector = byName.get(member);
      if (!vector) throw new Error(`unknown vector "${member}"`);
      hashes.add(await computeContentHash(vector.input));
    }
    assertEquals(
      hashes.size,
      1,
      `expected one hash across [${group.members.join(', ')}], got ${hashes.size}`,
    );
  });
}

for (const group of fixture.distinctGroups) {
  Deno.test(`distinct: ${group.name}`, async () => {
    const hashes = new Set<string>();
    for (const member of group.members) {
      const vector = byName.get(member);
      if (!vector) throw new Error(`unknown vector "${member}"`);
      hashes.add(await computeContentHash(vector.input));
    }
    assertEquals(
      hashes.size,
      group.members.length,
      `expected ${group.members.length} distinct hashes across [${group.members.join(', ')}], got ${hashes.size}`,
    );
  });
}

Deno.test('a non-object payload canonicalizes to the empty document', () => {
  assertEquals(canonicalize(null), '{}');
  assertEquals(canonicalize('a string'), '{}');
  assertEquals(canonicalize(42), '{}');
  assertEquals(canonicalize(['a', 'list']), '{}');
});
