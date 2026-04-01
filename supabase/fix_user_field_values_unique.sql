-- Add unique constraint so upsert with onConflict:'user_id,field_id' works.
-- Safe to run even if duplicate rows exist by de-duplicating first.

-- Step 1a: Remove duplicate rows and keep the most recently updated row.
DELETE FROM public.user_field_values
WHERE id NOT IN (
  SELECT DISTINCT ON (user_id, field_id) id
  FROM public.user_field_values
  ORDER BY user_id, field_id, updated_at DESC
);

-- Step 1b: Ensure uniqueness used by ON CONFLICT (user_id, field_id).
-- Use an idempotent unique index so reruns do not fail if it already exists.
CREATE UNIQUE INDEX IF NOT EXISTS user_field_values_user_field_unique
  ON public.user_field_values (user_id, field_id);