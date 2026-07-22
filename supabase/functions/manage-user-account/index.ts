// @ts-nocheck - Deno Edge Functions use URL imports and the Deno namespace.
// These are resolved at runtime by Supabase's Deno environment.
//
// manage-user-account — self-service account actions for MOBILE applicants.
// Authenticates the caller via their Supabase Auth JWT (never a body-supplied
// id), so a user can only ever act on THEIR OWN account. Mirrors the auth
// pattern in derive-field-key and the action-discriminator shape in
// manage-staff-account.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return json({ error: 'method_not_allowed' }, 405);
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return json({ error: 'unauthorized', message: 'Missing or malformed Authorization header.' }, 401);
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!supabaseUrl || !serviceRoleKey) {
      console.error('[manage-user-account] Missing required secrets');
      return json({ error: 'server_configuration_error' }, 500);
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    // Secure server-side identity resolution — re-validate the token against
    // the Auth service and derive the userId from it. Any user_id in the body
    // is deliberately ignored.
    const token = authHeader.replace('Bearer ', '').trim();
    const { data: { user }, error: authError } = await supabase.auth.getUser(token);
    if (authError || !user) {
      return json({ error: 'unauthorized', message: 'Invalid or expired session.' }, 401);
    }
    const userId = user.id;

    const body = await req.json().catch(() => ({}));
    const action = typeof body?.action === 'string' ? body.action.trim() : '';
    if (!action) {
      return json({ error: 'missing_action' }, 400);
    }

    switch (action) {
      case 'delete_account': {
        console.log(`[manage-user-account/delete_account] userId=${userId}`);

        // Look up the username for a human-readable audit label. Missing row is
        // fine — the purge is idempotent and still proceeds.
        const account = await supabase
          .from('user_accounts')
          .select('username')
          .eq('user_id', userId)
          .maybeSingle()
          .then((r: { data: { username?: string } | null }) => r.data);
        const username = account?.username ?? null;

        // 1. Deactivate first, so login is blocked even if a later step fails
        //    (the login path checks is_active — supabase_service.dart:671).
        await supabase
          .from('user_accounts')
          .update({ is_active: false })
          .eq('user_id', userId);

        // 2. Record the erasure BEFORE the purge so the actor label survives.
        //    audit_logs is intentionally FK-free and must be retained.
        //    Swallow any error (e.g. a CHECK constraint on action_type) so it
        //    can never block the deletion itself.
        try {
          await supabase.from('audit_logs').insert({
            actor_id: userId,
            actor_name: username,
            actor_role: 'applicant',
            action_type: 'user_account_deleted',
            category: 'auth',
            severity: 'warning',
            target_type: 'user',
            target_id: userId,
            target_label: username,
            details: { self_service: true },
          });
        } catch (auditError) {
          console.error(`[manage-user-account/delete_account] Audit write failed: ${auditError}`);
        }

        // 3. Purge user-owned PII. Finalized government records
        //    (client_submissions) are deliberately RETAINED so they remain
        //    visible in the web staff dashboard.
        await supabase.from('user_field_values').delete().eq('user_id', userId);
        await supabase.from('form_submission').delete().eq('user_id', userId);
        await supabase.from('user_notification_reads').delete().eq('user_id', userId);
        await supabase.from('user_accounts').delete().eq('user_id', userId);

        // 4. Delete the Auth login identity (service-role admin API).
        const { error: deleteAuthError } = await supabase.auth.admin.deleteUser(userId);
        if (deleteAuthError) {
          console.error(`[manage-user-account/delete_account] auth.admin.deleteUser failed: ${deleteAuthError.message}`);
          return json({ success: false, message: deleteAuthError.message }, 500);
        }

        return json({ success: true });
      }

      default:
        return json({ error: `unknown_action: ${action}` }, 400);
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : 'unknown_error';
    console.error(`[manage-user-account] Error: ${message}`);
    return json({ success: false, message }, 500);
  }
});
