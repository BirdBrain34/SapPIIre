import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

Deno.serve(async (req: Request) => {
  console.log('[manage-staff-account] Function invoked');

  // Handle CORS preflight
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
        const passwordHash = typeof body?.password_hash === 'string' ? body.password_hash.trim() : '';

        console.log(`[manage-staff-account/login] loginIdentifier=${loginIdentifier}`);

        if (!loginIdentifier) {
          return json({ error: 'missing_login_identifier' });
        }

        // First try: superadmin lookup by username
        console.log(`[manage-staff-account/login] Trying superadmin lookup by username: ${loginIdentifier}`);
        let account = await supabase
          .from('staff_accounts')
          .select('cswd_id, username, email, is_active, role, account_status, password_hash, is_first_login')
          .ilike('username', loginIdentifier)
          .eq('role', 'superadmin')
          .maybeSingle()
          .then(r => {
            console.log(`[manage-staff-account/login] Superadmin query result: found=${r.data != null}, error=${r.error?.message ?? 'none'}`);
            return r.data;
          });

        // Second try: non-superadmin lookup by email
        if (!account) {
          console.log(`[manage-staff-account/login] Trying non-superadmin lookup by email: ${loginIdentifier}`);
          account = await supabase
            .from('staff_accounts')
            .select('cswd_id, username, email, is_active, role, account_status, password_hash, is_first_login')
            .ilike('email', loginIdentifier)
            .neq('role', 'superadmin')
            .maybeSingle()
            .then(r => {
              console.log(`[manage-staff-account/login] Non-superadmin query result: found=${r.data != null}, error=${r.error?.message ?? 'none'}, role=${r.data?.role ?? 'N/A'}`);
              return r.data;
            });
        } else {
          console.log(`[manage-staff-account/login] Superadmin found: cswd_id=${account.cswd_id}`);
        }

        console.log(`[manage-staff-account/login] Returning account: ${account != null ? 'found' : 'null'}`);
        return json({ account: account ?? null });
      }

      case 'update_last_login': {
        const cswdId = typeof body?.cswd_id === 'string' ? body.cswd_id.trim() : '';
        if (!cswdId) {
          return json({ error: 'missing_cswd_id' });
        }

        await supabase
          .from('staff_accounts')
          .update({ last_login: new Date().toISOString() })
          .eq('cswd_id', cswdId);

        return json({ success: true });
      }

      case 'fetch_profile': {
        const cswdId = typeof body?.cswd_id === 'string' ? body.cswd_id.trim() : '';
        if (!cswdId) {
          return json({ error: 'missing_cswd_id' });
        }

        const profile = await supabase
          .from('staff_profiles')
          .select('first_name, middle_name, last_name, position, department, phone_number')
          .eq('cswd_id', cswdId)
          .maybeSingle()
          .then(r => r.data);

        return json({ profile: profile ?? null });
      }

      case 'fetch_account': {
        const email = typeof body?.email === 'string' ? body.email.trim().toLowerCase() : '';
        const cswdId = typeof body?.cswd_id === 'string' ? body.cswd_id.trim() : '';

        if (!email && !cswdId) {
          return json({ error: 'missing_email_or_cswd_id' });
        }

        let query = supabase
          .from('staff_accounts')
          .select('cswd_id, email, username, role, is_active, account_status, is_first_login');

        if (cswdId) {
          query = query.eq('cswd_id', cswdId);
        } else {
          query = query.ilike('email', email);
        }

        const account = await query.maybeSingle().then(r => r.data);
        return json({ account: account ?? null });
      }

      case 'fetch_password_hash': {
        const cswdId = typeof body?.cswd_id === 'string' ? body.cswd_id.trim() : '';
        if (!cswdId) {
          return json({ error: 'missing_cswd_id' });
        }

        const result = await supabase
          .from('staff_accounts')
          .select('password_hash')
          .eq('cswd_id', cswdId)
          .maybeSingle()
          .then(r => r.data);

        return json({ password_hash: result?.password_hash ?? null });
      }

      case 'check_username': {
        const username = typeof body?.username === 'string' ? body.username.trim() : '';
        if (!username) {
          return json({ error: 'missing_username' });
        }

        const existing = await supabase
          .from('staff_accounts')
          .select('username')
          .ilike('username', username)
          .maybeSingle()
          .then(r => r.data);

        return json({ exists: existing != null });
      }

      case 'check_username_unique': {
        const candidate = typeof body?.candidate === 'string' ? body.candidate.trim() : '';
        if (!candidate) {
          return json({ error: 'missing_candidate' });
        }

        const existing = await supabase
          .from('staff_accounts')
          .select('username')
          .eq('username', candidate)
          .maybeSingle()
          .then(r => r.data);

        return json({ exists: existing != null });
      }

      case 'create_pending': {
        const email = typeof body?.email === 'string' ? body.email.trim() : '';
        const username = typeof body?.username === 'string' ? body.username.trim() : '';
        const passwordHash = typeof body?.password_hash === 'string' ? body.password_hash.trim() : '';
        const requestedRole = typeof body?.requested_role === 'string' ? body.requested_role.trim() : '';
        const firstName = typeof body?.first_name === 'string' ? body.first_name.trim() : '';
        const middleName = typeof body?.middle_name === 'string' ? body.middle_name.trim() : null;
        const lastName = typeof body?.last_name === 'string' ? body.last_name.trim() : '';
        const nameSuffix = typeof body?.name_suffix === 'string' ? body.name_suffix.trim() : null;
        const position = typeof body?.position === 'string' ? body.position.trim() : '';
        const department = typeof body?.department === 'string' ? body.department.trim() : '';
        const phoneNumber = typeof body?.phone_number === 'string' ? body.phone_number.trim() : null;

        if (!email || !username || !passwordHash || !requestedRole || !firstName || !lastName || !position || !department) {
          return json({ error: 'missing_required_fields' });
        }

        // Insert into staff_accounts
        const accountResult = await supabase
          .from('staff_accounts')
          .insert({
            email,
            username,
            password_hash: passwordHash,
            role: 'viewer',
            requested_role: requestedRole,
            account_status: 'pending',
            is_active: false,
          })
          .select('cswd_id')
          .single();

        if (accountResult.error) {
          return json({ error: accountResult.error.message, code: accountResult.error.code });
        }

        const cswdId = accountResult.data?.cswd_id?.toString();
        if (!cswdId) {
          return json({ error: 'failed_to_get_cswd_id' });
        }

        // Insert into staff_profiles
        const profileResult = await supabase
          .from('staff_profiles')
          .insert({
            cswd_id: cswdId,
            first_name: firstName,
            middle_name: middleName === '' ? null : middleName,
            last_name: lastName,
            name_suffix: nameSuffix === '' ? null : nameSuffix,
            position,
            department,
            phone_number: phoneNumber === '' ? null : phoneNumber,
          });

        if (profileResult.error) {
          // Rollback: delete the account we just created
          await supabase.from('staff_accounts').delete().eq('cswd_id', cswdId);
          return json({ error: profileResult.error.message, code: profileResult.error.code });
        }

        return json({ success: true, cswd_id: cswdId });
      }

      case 'create_admin': {
        const email = typeof body?.email === 'string' ? body.email.trim() : '';
        const username = typeof body?.username === 'string' ? body.username.trim() : '';
        const passwordHash = typeof body?.password_hash === 'string' ? body.password_hash.trim() : '';
        const firstName = typeof body?.first_name === 'string' ? body.first_name.trim() : '';
        const middleName = typeof body?.middle_name === 'string' ? body.middle_name.trim() : null;
        const lastName = typeof body?.last_name === 'string' ? body.last_name.trim() : '';
        const nameSuffix = typeof body?.name_suffix === 'string' ? body.name_suffix.trim() : null;
        const position = typeof body?.position === 'string' ? body.position.trim() : null;
        const department = typeof body?.department === 'string' ? body.department.trim() : null;
        const phoneNumber = typeof body?.phone_number === 'string' ? body.phone_number.trim() : null;

        if (!email || !username || !passwordHash || !firstName || !lastName) {
          return json({ error: 'missing_required_fields' });
        }

        // Insert into staff_accounts
        const accountResult = await supabase
          .from('staff_accounts')
          .insert({
            email,
            username,
            password_hash: passwordHash,
            role: 'admin',
            requested_role: 'admin',
            account_status: 'active',
            is_active: true,
            is_first_login: true,
          })
          .select('cswd_id')
          .single();

        if (accountResult.error) {
          return json({ error: accountResult.error.message, code: accountResult.error.code });
        }

        const cswdId = accountResult.data?.cswd_id?.toString();
        if (!cswdId) {
          return json({ error: 'failed_to_get_cswd_id' });
        }

        // Insert into staff_profiles
        const profileResult = await supabase
          .from('staff_profiles')
          .insert({
            cswd_id: cswdId,
            first_name: firstName,
            middle_name: middleName === '' ? null : middleName,
            last_name: lastName,
            name_suffix: nameSuffix === '' ? null : nameSuffix,
            position: position === '' ? null : position,
            department: department === '' ? null : department,
            phone_number: phoneNumber === '' ? null : phoneNumber,
          });

        if (profileResult.error) {
          // Rollback: delete the account we just created
          await supabase.from('staff_accounts').delete().eq('cswd_id', cswdId);
          return json({ error: profileResult.error.message, code: profileResult.error.code });
        }

        return json({ success: true, cswd_id: cswdId, username });
      }

      case 'update_account': {
        const cswdId = typeof body?.cswd_id === 'string' ? body.cswd_id.trim() : '';
        const updates = body?.updates;

        if (!cswdId) {
          return json({ error: 'missing_cswd_id' });
        }

        if (!updates || typeof updates !== 'object' || Object.keys(updates).length === 0) {
          return json({ error: 'missing_or_empty_updates' });
        }

        const { error: updateError } = await supabase
          .from('staff_accounts')
          .update(updates)
          .eq('cswd_id', cswdId);

        if (updateError) {
          return json({ error: updateError.message });
        }

        return json({ success: true });
      }

      case 'fetch_accounts': {
        console.log('[manage-staff-account/fetch_accounts] Fetching pending accounts');
        const pending = await supabase
          .from('staff_accounts')
          .select('cswd_id, username, email, requested_role, created_at')
          .eq('account_status', 'pending')
          .order('created_at')
          .then(r => r.data ?? []);

        console.log(`[manage-staff-account/fetch_accounts] Fetching active accounts`);
        const active = await supabase
          .from('staff_accounts')
          .select('cswd_id, username, email, role, account_status, is_active, is_first_login')
          .neq('account_status', 'pending')
          .order('username')
          .then(r => r.data ?? []);

        console.log(`[manage-staff-account/fetch_accounts] Pending=${pending.length}, Active=${active.length}`);
        return json({ pending, active });
      }

      case 'fetch_staff_batch': {
        const ids = body?.ids;
        if (!Array.isArray(ids) || ids.length === 0) {
          return json({ error: 'missing_ids' });
        }

        const accounts = await supabase
          .from('staff_accounts')
          .select('cswd_id, username, email')
          .inFilter('cswd_id', ids)
          .then(r => r.data ?? []);

        const profiles = await supabase
          .from('staff_profiles')
          .select('cswd_id, first_name, middle_name, last_name')
          .inFilter('cswd_id', ids)
          .then(r => r.data ?? []);

        return json({ accounts, profiles });
      }

      case 'fetch_display': {
        const cswdId = typeof body?.cswd_id === 'string' ? body.cswd_id.trim() : '';
        if (!cswdId) {
          return json({ error: 'missing_cswd_id' });
        }

        const display = await supabase
          .from('staff_display_view')
          .select('*')
          .eq('cswd_id', cswdId)
          .maybeSingle()
          .then(r => r.data);

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