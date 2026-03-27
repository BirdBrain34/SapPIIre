-- supabase/staff_security_migration.sql

-- 1. Add is_first_login flag to staff_accounts
--    true  = account just created, must change password before accessing dashboard
--    false = has logged in and set their own password at least once
ALTER TABLE public.staff_accounts
  ADD COLUMN IF NOT EXISTS is_first_login boolean NOT NULL DEFAULT true;

-- 2. Mark existing active accounts as NOT first login
--    (they've already been using the system, don't force them)
UPDATE public.staff_accounts
  SET is_first_login = false
  WHERE account_status = 'active' AND is_active = true;

-- 3. Add staff_password_reset_otp table
--    Stores temporary OTPs for the "forgot password" flow.
--    Separate from phone_otp (which is for citizens).
CREATE TABLE IF NOT EXISTS public.staff_password_reset_otp (
  id          uuid NOT NULL DEFAULT gen_random_uuid(),
  cswd_id     uuid NOT NULL,
  email       text NOT NULL,
  otp         text NOT NULL,
  expires_at  timestamp with time zone NOT NULL,
  used        boolean NOT NULL DEFAULT false,
  created_at  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT staff_password_reset_otp_pkey PRIMARY KEY (id),
  CONSTRAINT staff_password_reset_otp_account_fkey
    FOREIGN KEY (cswd_id) REFERENCES public.staff_accounts(cswd_id)
      ON DELETE CASCADE
);

-- Index for fast lookup by email
CREATE INDEX IF NOT EXISTS staff_password_reset_otp_email_idx
  ON public.staff_password_reset_otp(email);

-- RLS: open for anon since staff are not Supabase Auth users
ALTER TABLE public.staff_password_reset_otp ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public can manage staff OTPs"
  ON public.staff_password_reset_otp
  FOR ALL TO anon, authenticated
  USING (true)
  WITH CHECK (true);
