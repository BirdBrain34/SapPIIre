// @ts-nocheck - Deno Edge Functions use URL imports and Deno namespace
// These are resolved at runtime by Supabase's Deno environment.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
// bcryptjs is a pure JavaScript bcrypt implementation (no Workers needed)
import bcrypt from 'npm:bcryptjs@2.4.3';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

// ── Rate limiting (in-memory) ──────────────────────────────────
const RATE_LIMIT_WINDOW_MS = 60_000; // 1 minute
const MAX_LOGIN_ATTEMPTS = 5;
const rateLimitStore = new Map<string, { count: number; resetAt: number }>();

function checkLoginRateLimit(identifier: string): boolean {
  const now = Date.now();
  const record = rateLimitStore.get(identifier);
  if (!record || now > record.resetAt) {
    rateLimitStore.set(identifier, { count: 1, resetAt: now + RATE_LIMIT_WINDOW_MS });
    return true;
  }
  if (record.count >= MAX_LOGIN_ATTEMPTS) {
    return false;
  }
  record.count++;
  return true;
}

// ── SHA-256 helper (for migration fallback only) ──────────────
async function sha256Hex(password: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(password);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map((b: number) => b.toString(16).padStart(2, '0')).join('');
}

// ── Detect if a hash is SHA-256 (64 hex chars, no bcrypt prefix) ──
function isSha256Hash(hash: string): boolean {
  return /^[0-9a-f]{64}$/i.test(hash);
}

// ── bcrypt helpers ─────────────────────────────────────────────
async function hashPassword(password: string): Promise<string> {
  const salt = await bcrypt.genSalt(12);
  return await bcrypt.hash(password, salt);
}

async function verifyPassword(password: string, hash: string): Promise<boolean> {
  try {
    return await bcrypt.compare(password, hash);
  } catch {
    return false;
  }
}

Deno.serve(async (req: Request) => {
  console.log('[manage-staff-account] Function invoked');

  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 200, headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return json({ error: 'method_not_allowed' }, 405);
  }

  try {
    const body = await req.json().catch(() => ({}));
    const action = typeof body?.action === 'string' ? body.action.trim() : '';

    if (!action) {
      return json({ error: 'missing_action' });
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

    if (!supabaseUrl || !serviceRoleKey) {
      return json({ error: 'missing_env_vars' });
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    switch (action) {
      case 'login': {
        const loginIdentifier = typeof body?.login_identifier === 'string' ? body.login_identifier.trim() : '';

        console.log(`[manage-staff-account/login] loginIdentifier=${loginIdentifier}`);

        if (!loginIdentifier) {
          return json({ error: 'missing_login_identifier' });
        }

        if (!checkLoginRateLimit(loginIdentifier)) {
          return json({
            error: 'rate_limited',
            message: 'Too many login attempts. Please wait 1 minute before trying again.',
          }, 429);
        }

        const rawPassword = typeof body?.password === 'string' ? body.password : '';
        const precomputedHash = typeof body?.password_hash === 'string' ? body.password_hash.trim() : '';
        const isOldClient = !rawPassword && !!precomputedHash;

        let account: Record<string, unknown> | null = await supabase
          .from('staff_accounts')
          .select('cswd_id, username, email, is_active, role, account_status, password_hash, is_first_login')
          .ilike('username', loginIdentifier)
          .maybeSingle()
          .then((r: { data: Record<string, unknown> | null }) => r.data);

        if (!account) {
          account = await supabase
            .from('staff_accounts')
            .select('cswd_id, username, email, is_active, role, account_status, password_hash, is_first_login')
            .ilike('email', loginIdentifier)
            .maybeSingle()
            .then((r: { data: Record<string, unknown> | null }) => r.data);
        }

        if (!account) {
          return json({ account: null });
        }

        const storedHash: string = (account.password_hash as string) || '';
        let isValid = false;
        let needsMigration = false;

        if (isOldClient) {
          isValid = precomputedHash === storedHash;
          if (isValid && isSha256Hash(storedHash)) {
            console.log(`[manage-staff-account/login] Old client login success for cswd_id=${account.cswd_id}`);
          }
        } else {
          if (storedHash.startsWith('$2')) {
            isValid = await verifyPassword(rawPassword, storedHash);
          } else if (isSha256Hash(storedHash)) {
            const computedHash = await sha256Hex(rawPassword);
            isValid = computedHash === storedHash.toLowerCase();
            if (isValid) {
              needsMigration = true;
              console.log(`[manage-staff-account/login] Migrating SHA-256 → bcrypt for cswd_id=${account.cswd_id}`);
            }
          } else {
            isValid = false;
          }
        }

        if (needsMigration) {
          const bcryptHash = await hashPassword(rawPassword);
          supabase
            .from('staff_accounts')
            .update({ password_hash: bcryptHash })
            .eq('cswd_id', account.cswd_id as string)
            .then(({ error }: { error: Error | null }) => {
              if (error) {
                console.error(`[manage-staff-account/login] Migration failed for cswd_id=${account.cswd_id}: ${error.message}`);
              } else {
                console.log(`[manage-staff-account/login] Migration successful for cswd_id=${account.cswd_id}`);
              }
            });
        }

        return json({
          account: {
            ...account,
            is_valid: isValid,
            password_hash: undefined,
          },
        });
      }

      case 'change_password': {
        const cswdId = typeof body?.cswd_id === 'string' ? body.cswd_id.trim() : '';
        const currentPassword = typeof body?.current_password === 'string' ? body.current_password : '';
        const newPassword = typeof body?.new_password === 'string' ? body.new_password : '';

        if (!cswdId || !currentPassword || !newPassword) {
          return json({ error: 'missing_required_fields' });
        }

        if (newPassword.length < 8) {
          return json({ success: false, message: 'New password must be at least 8 characters.' });
        }

        const account = await supabase
          .from('staff_accounts')
          .select('password_hash')
          .eq('cswd_id', cswdId)
          .maybeSingle()
          .then((r: { data: { password_hash: string } | null }) => r.data);

        if (!account || !account.password_hash) {
          return json({ success: false, message: 'Account not found.' });
        }

        const isValid = await verifyPassword(currentPassword, account.password_hash);
        if (!isValid) {
          return json({ success: false, message: 'Current password is incorrect.' });
        }

        const newHash = await hashPassword(newPassword);
        await supabase
          .from('staff_accounts')
          .update({ password_hash: newHash })
          .eq('cswd_id', cswdId);

        return json({ success: true, message: 'Password changed successfully.' });
      }

      case 'update_password': {
        const cswdId = typeof body?.cswd_id === 'string' ? body.cswd_id.trim() : '';
        const newPassword = typeof body?.new_password === 'string' ? body.new_password : '';
        const isFirstLogin = body?.is_first_login === true;
        const accountStatus = typeof body?.account_status === 'string' ? body.account_status.trim() : '';

        if (!cswdId || !newPassword) {
          return json({ error: 'missing_required_fields' });
        }

        if (newPassword.length < 8) {
          return json({ success: false, message: 'Password must be at least 8 characters.' });
        }

        const newHash = await hashPassword(newPassword);
        const updates: Record<string, unknown> = { password_hash: newHash };
        if (isFirstLogin) updates.is_first_login = false;
        if (accountStatus) updates.account_status = accountStatus;

        await supabase
          .from('staff_accounts')
          .update(updates)
          .eq('cswd_id', cswdId);

        return json({ success: true, message: 'Password updated successfully.' });
      }

      case 'reset_superadmin_password': {
        const resetToken = typeof body?.reset_token === 'string' ? body.reset_token.trim() : '';
        const newPassword = typeof body?.new_password === 'string' ? body.new_password : '';
        const expectedToken = (Deno.env.get('SUPERADMIN_PASSWORD_RESET_TOKEN') || '').trim();

        if (!expectedToken || resetToken !== expectedToken) {
          return json({ error: 'unauthorized' }, 401);
        }

        if (newPassword.length < 8) {
          return json({ success: false, message: 'Password must be at least 8 characters.' });
        }

        const account = await supabase
          .from('staff_accounts')
          .select('cswd_id')
          .eq('username', 'superadmin')
          .eq('role', 'superadmin')
          .maybeSingle()
          .then((r: { data: { cswd_id: string } | null }) => r.data);

        const cswdId = account?.cswd_id;
        if (!cswdId) {
          return json({ error: 'superadmin_not_found' });
        }

        const newHash = await hashPassword(newPassword);
        await supabase
          .from('staff_accounts')
          .update({ password_hash: newHash })
          .eq('cswd_id', cswdId);

        return json({ success: true, message: 'Superadmin password reset successfully.' });
      }

      case 'update_last_login': {
        const cswdId = typeof body?.cswd_id === 'string' ? body.cswd_id.trim() : '';
        if (!cswdId) return json({ error: 'missing_cswd_id' });

        await supabase
          .from('staff_accounts')
          .update({ last_login: new Date().toISOString() })
          .eq('cswd_id', cswdId);

        return json({ success: true });
      }

      case 'fetch_profile': {
        const cswdId = typeof body?.cswd_id === 'string' ? body.cswd_id.trim() : '';
        if (!cswdId) return json({ error: 'missing_cswd_id' });

        const profile = await supabase
          .from('staff_profiles')
          .select('first_name, middle_name, last_name, position, department, phone_number')
          .eq('cswd_id', cswdId)
          .maybeSingle()
          .then((r: { data: Record<string, unknown> | null }) => r.data);

        return json({ profile: profile ?? null });
      }

      case 'fetch_account': {
        const email = typeof body?.email === 'string' ? body.email.trim().toLowerCase() : '';
        const cswdId = typeof body?.cswd_id === 'string' ? body.cswd_id.trim() : '';

        if (!email && !cswdId) return json({ error: 'missing_email_or_cswd_id' });

        let query = supabase
          .from('staff_accounts')
          .select('cswd_id, email, username, role, is_active, account_status, is_first_login');

        if (cswdId) {
          query = query.eq('cswd_id', cswdId);
        } else {
          query = query.ilike('email', email);
        }

        const account = await query.maybeSingle()
          .then((r: { data: Record<string, unknown> | null }) => r.data);
        return json({ account: account ?? null });
      }

      case 'fetch_password_hash': {
        const cswdId = typeof body?.cswd_id === 'string' ? body.cswd_id.trim() : '';
        if (!cswdId) return json({ error: 'missing_cswd_id' });

        const result = await supabase
          .from('staff_accounts')
          .select('password_hash')
          .eq('cswd_id', cswdId)
          .maybeSingle()
          .then((r: { data: { password_hash: string } | null }) => r.data);

        return json({ password_hash: result?.password_hash ?? null });
      }

      case 'check_username': {
        const username = typeof body?.username === 'string' ? body.username.trim() : '';
        if (!username) return json({ error: 'missing_username' });

        const existing = await supabase
          .from('staff_accounts')
          .select('username')
          .ilike('username', username)
          .maybeSingle()
          .then((r: { data: Record<string, unknown> | null }) => r.data);

        return json({ exists: existing != null });
      }

      case 'check_username_unique': {
        const candidate = typeof body?.candidate === 'string' ? body.candidate.trim() : '';
        if (!candidate) return json({ error: 'missing_candidate' });

        const existing = await supabase
          .from('staff_accounts')
          .select('username')
          .eq('username', candidate)
          .maybeSingle()
          .then((r: { data: Record<string, unknown> | null }) => r.data);

        return json({ exists: existing != null });
      }

      case 'create_pending': {
        const email = typeof body?.email === 'string' ? body.email.trim() : '';
        const username = typeof body?.username === 'string' ? body.username.trim() : '';
        const rawPassword = typeof body?.password === 'string' ? body.password : '';
        const requestedRole = typeof body?.requested_role === 'string' ? body.requested_role.trim() : '';
        const firstName = typeof body?.first_name === 'string' ? body.first_name.trim() : '';
        const middleName = typeof body?.middle_name === 'string' ? body.middle_name.trim() : null;
        const lastName = typeof body?.last_name === 'string' ? body.last_name.trim() : '';
        const nameSuffix = typeof body?.name_suffix === 'string' ? body.name_suffix.trim() : null;
        const position = typeof body?.position === 'string' ? body.position.trim() : '';
        const department = typeof body?.department === 'string' ? body.department.trim() : '';
        const phoneNumber = typeof body?.phone_number === 'string' ? body.phone_number.trim() : null;

        if (!email || !username || !rawPassword || !requestedRole || !firstName || !lastName || !position || !department) {
          return json({ error: 'missing_required_fields' });
        }

        const passwordHash = await hashPassword(rawPassword);

        const accountResult = await supabase
          .from('staff_accounts')
          .insert({
            // Pending accounts are stored as 'admin' to satisfy the
            // role CHECK constraint, but stay inactive/pending until a
            // superadmin approves — login is blocked while is_active=false.
            email, username, password_hash: passwordHash,
            role: 'admin', requested_role: requestedRole,
            account_status: 'pending', is_active: false,
          })
          .select('cswd_id')
          .single();

        if (accountResult.error) {
          return json({ error: accountResult.error.message, code: accountResult.error.code });
        }

        const cswdId = accountResult.data?.cswd_id?.toString();
        if (!cswdId) return json({ error: 'failed_to_get_cswd_id' });

        const profileResult = await supabase
          .from('staff_profiles')
          .insert({
            cswd_id: cswdId, first_name: firstName,
            middle_name: middleName === '' ? null : middleName,
            last_name: lastName, name_suffix: nameSuffix === '' ? null : nameSuffix,
            position, department,
            phone_number: phoneNumber === '' ? null : phoneNumber,
          });

        if (profileResult.error) {
          await supabase.from('staff_accounts').delete().eq('cswd_id', cswdId);
          return json({ error: profileResult.error.message, code: profileResult.error.code });
        }

        return json({ success: true, cswd_id: cswdId });
      }

      case 'create_admin': {
        const email = typeof body?.email === 'string' ? body.email.trim() : '';
        const username = typeof body?.username === 'string' ? body.username.trim() : '';
        const rawPassword = typeof body?.password === 'string' ? body.password : '';
        const firstName = typeof body?.first_name === 'string' ? body.first_name.trim() : '';
        const middleName = typeof body?.middle_name === 'string' ? body.middle_name.trim() : null;
        const lastName = typeof body?.last_name === 'string' ? body.last_name.trim() : '';
        const nameSuffix = typeof body?.name_suffix === 'string' ? body.name_suffix.trim() : null;
        const position = typeof body?.position === 'string' ? body.position.trim() : null;
        const department = typeof body?.department === 'string' ? body.department.trim() : null;
        const phoneNumber = typeof body?.phone_number === 'string' ? body.phone_number.trim() : null;

        if (!email || !username || !rawPassword || !firstName || !lastName) {
          return json({ error: 'missing_required_fields' });
        }

        const passwordHash = await hashPassword(rawPassword);

        const accountResult = await supabase
          .from('staff_accounts')
          .insert({
            email, username, password_hash: passwordHash,
            role: 'admin', requested_role: 'admin',
            account_status: 'active', is_active: true, is_first_login: true,
          })
          .select('cswd_id')
          .single();

        if (accountResult.error) {
          return json({ error: accountResult.error.message, code: accountResult.error.code });
        }

        const cswdId = accountResult.data?.cswd_id?.toString();
        if (!cswdId) return json({ error: 'failed_to_get_cswd_id' });

        const profileResult = await supabase
          .from('staff_profiles')
          .insert({
            cswd_id: cswdId, first_name: firstName,
            middle_name: middleName === '' ? null : middleName,
            last_name: lastName, name_suffix: nameSuffix === '' ? null : nameSuffix,
            position: position === '' ? null : position,
            department: department === '' ? null : department,
            phone_number: phoneNumber === '' ? null : phoneNumber,
          });

        if (profileResult.error) {
          await supabase.from('staff_accounts').delete().eq('cswd_id', cswdId);
          return json({ error: profileResult.error.message, code: profileResult.error.code });
        }

        return json({ success: true, cswd_id: cswdId, username });
      }

      case 'update_account': {
        const cswdId = typeof body?.cswd_id === 'string' ? body.cswd_id.trim() : '';
        const updates = body?.updates;

        if (!cswdId) return json({ error: 'missing_cswd_id' });
        if (!updates || typeof updates !== 'object' || Object.keys(updates).length === 0) {
          return json({ error: 'missing_or_empty_updates' });
        }

        // Only admin/superadmin are valid roles — reject any other value.
        const ALLOWED_ROLES = ['admin', 'superadmin'];
        if ('role' in updates && !ALLOWED_ROLES.includes(updates.role)) {
          return json({ error: `invalid_role: ${updates.role}` });
        }
        if ('requested_role' in updates &&
            updates.requested_role != null &&
            !ALLOWED_ROLES.includes(updates.requested_role)) {
          return json({ error: `invalid_requested_role: ${updates.requested_role}` });
        }

        const { error: updateError } = await supabase
          .from('staff_accounts')
          .update(updates)
          .eq('cswd_id', cswdId);

        if (updateError) return json({ error: updateError.message });
        return json({ success: true });
      }

      case 'fetch_accounts': {
        const pending = await supabase
          .from('staff_accounts')
          .select('cswd_id, username, email, requested_role, created_at')
          .eq('account_status', 'pending')
          .order('created_at')
          .then((r: { data: Record<string, unknown>[] }) => r.data ?? []);

        const active = await supabase
          .from('staff_accounts')
          .select('cswd_id, username, email, role, account_status, is_active, is_first_login')
          .neq('account_status', 'pending')
          .order('username')
          .then((r: { data: Record<string, unknown>[] }) => r.data ?? []);

        return json({ pending, active });
      }

      case 'fetch_staff_batch': {
        const ids = body?.ids;
        if (!Array.isArray(ids) || ids.length === 0) return json({ error: 'missing_ids' });

        const accounts = await supabase
          .from('staff_accounts')
          .select('cswd_id, username, email')
          .inFilter('cswd_id', ids)
          .then((r: { data: Record<string, unknown>[] }) => r.data ?? []);

        const profiles = await supabase
          .from('staff_profiles')
          .select('cswd_id, first_name, middle_name, last_name')
          .inFilter('cswd_id', ids)
          .then((r: { data: Record<string, unknown>[] }) => r.data ?? []);

        return json({ accounts, profiles });
      }

      case 'fetch_display': {
        const cswdId = typeof body?.cswd_id === 'string' ? body.cswd_id.trim() : '';
        if (!cswdId) return json({ error: 'missing_cswd_id' });

        const display = await supabase
          .from('staff_display_view')
          .select('*')
          .eq('cswd_id', cswdId)
          .maybeSingle()
          .then((r: { data: Record<string, unknown> | null }) => r.data);

        return json({ display: display ?? null });
      }

      default:
        return json({ error: `unknown_action: ${action}` });
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : 'unknown_error';
    console.error(`[manage-staff-account] Error: ${message}`);
    return json({ error: message });
  }
});