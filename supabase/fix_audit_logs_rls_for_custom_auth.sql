-- supabase/fix_audit_logs_rls_for_custom_auth.sql
-- Run this once if audit_logs policies were already created with authenticated-only access.

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Staff can insert audit logs" ON public.audit_logs;
DROP POLICY IF EXISTS "Superadmin can read audit logs" ON public.audit_logs;
DROP POLICY IF EXISTS "Public can insert audit logs" ON public.audit_logs;
DROP POLICY IF EXISTS "Public can read audit logs" ON public.audit_logs;

CREATE POLICY "Public can insert audit logs"
  ON public.audit_logs FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

CREATE POLICY "Public can read audit logs"
  ON public.audit_logs FOR SELECT
  TO anon, authenticated
  USING (true);
