-- supabase/seed_superadmin.sql
-- Run this in the Supabase SQL Editor.
-- Bootstrap password used for this hash: ChangeMeNow!2026
-- Rotate immediately after first login.
-- NOTE: requested_role must satisfy DB check constraints and may not allow
-- 'superadmin'. Keep role='superadmin' and use an allowed requested_role.
-- IMPORTANT: ON CONFLICT DO NOTHING will keep existing superadmin password_hash.
-- Use README_seed.md UPDATE snippet to rotate password for existing rows.
-- Hash generation examples:
-- Linux/macOS: echo -n 'YourPassword' | sha256sum
-- PowerShell:  [System.BitConverter]::ToString(([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes('YourPassword')))).Replace('-', '').ToLower()

INSERT INTO public.staff_accounts (
  cswd_id,
  email,
  username,
  password_hash,
  role,
  account_status,
  requested_role,
  is_active
) VALUES (
  gen_random_uuid(),
  'superadmin@sappiire.com',
  'superadmin',
  'fd70ea151146289d5bacc3cad0f029928bed07b45ef3affed0151228c9b303ff',
  'superadmin',
  'active',
  'admin',
  true
)
ON CONFLICT (username) DO NOTHING;
