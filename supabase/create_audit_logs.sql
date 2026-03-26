-- supabase/create_audit_logs.sql

CREATE TABLE public.audit_logs (
  id            uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at    timestamp with time zone NOT NULL DEFAULT now(),
  actor_id      uuid,
  actor_name    text,
  actor_role    text,
  action_type   text NOT NULL,
  category      text NOT NULL,
  severity      text NOT NULL DEFAULT 'info',
  target_type   text,
  target_id     text,
  target_label  text,
  details       jsonb DEFAULT '{}'::jsonb,
  CONSTRAINT audit_logs_pkey PRIMARY KEY (id)
);

CREATE INDEX audit_logs_actor_id_idx ON public.audit_logs(actor_id);
CREATE INDEX audit_logs_created_at_idx ON public.audit_logs(created_at DESC);
CREATE INDEX audit_logs_category_idx ON public.audit_logs(category);
CREATE INDEX audit_logs_action_type_idx ON public.audit_logs(action_type);

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

-- This project uses custom table-based login (not Supabase Auth sessions),
-- so clients typically execute as anon. Keep access permissive here and
-- enforce superadmin-only viewing in the application layer.
CREATE POLICY "Public can insert audit logs"
  ON public.audit_logs FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

CREATE POLICY "Public can read audit logs"
  ON public.audit_logs FOR SELECT
  TO anon, authenticated
  USING (true);
