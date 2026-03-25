# Superadmin Seed Guide

This repository uses a table-based web staff auth flow via `staff_accounts` with SHA-256 password hashes.

## Seed file

Use `supabase/seed_superadmin.sql` to insert the bootstrap superadmin account.

The seed is idempotent and safe to re-run:
- `ON CONFLICT (username) DO NOTHING`

## Regenerate password hash

Pick a new password and generate a lowercase SHA-256 hex string.

### Linux/macOS

```bash
echo -n 'YourPassword' | sha256sum
```

Use only the first field (64-char hex hash).

### Windows PowerShell

```powershell
$pwdText = 'YourPassword'
$bytes = [System.Text.Encoding]::UTF8.GetBytes($pwdText)
$sha = [System.Security.Cryptography.SHA256]::Create()
($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join ''
```

## Update and run

1. Open `supabase/seed_superadmin.sql`.
2. Replace `password_hash` value with your generated hash.
3. Run the SQL in Supabase SQL Editor.
4. Log in with username `superadmin` and your chosen plaintext password.
5. Rotate the password if you seeded using a temporary bootstrap value.

If `superadmin` already exists, the seed will not overwrite it because it uses
`ON CONFLICT DO NOTHING`. To rotate the password hash for an existing account,
run this update manually:

```sql
UPDATE public.staff_accounts
SET
	password_hash = 'REPLACE_WITH_SHA256_HEX',
	role = 'superadmin',
	account_status = 'active',
	requested_role = 'admin',
	is_active = true
WHERE username = 'superadmin';
```

## Notes

- Do not use `supabase.auth.*` for web staff login.
- Web staff login uses `staff_accounts.password_hash` checked in `WebAuthService`.
- If your DB has a `requested_role` CHECK constraint, keep `role` as `superadmin`
	but set `requested_role` to an allowed value (for example `admin`) in the seed.
