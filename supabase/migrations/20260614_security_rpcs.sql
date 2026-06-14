-- ─────────────────────────────────────────────────────────────────────────────
-- Security RPCs — apply to production BEFORE deploying the matching app build.
-- Run via: supabase db push  (or paste into the Supabase SQL editor)
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. save_razorpay_keys ─────────────────────────────────────────────────────
-- Writes Razorpay credentials server-side so the raw key_secret is never
-- readable through the public gyms table.  Callers must be owner or manager
-- of the gym that belongs to their profile.
CREATE OR REPLACE FUNCTION save_razorpay_keys(
  p_key_id     text,
  p_key_secret text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gym_id uuid;
  v_role   text;
BEGIN
  SELECT gym_id, role
    INTO v_gym_id, v_role
    FROM profiles
   WHERE id = auth.uid();

  IF v_gym_id IS NULL THEN
    RAISE EXCEPTION 'unauthorized';
  END IF;

  IF v_role NOT IN ('owner', 'manager') THEN
    RAISE EXCEPTION 'insufficient_role';
  END IF;

  UPDATE gyms
     SET razorpay_key_id     = NULLIF(p_key_id, ''),
         razorpay_key_secret = NULLIF(p_key_secret, '')
   WHERE id = v_gym_id;
END;
$$;

REVOKE ALL ON FUNCTION save_razorpay_keys(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION save_razorpay_keys(text, text) TO authenticated;

-- ── 2. insert_checkin_secure ──────────────────────────────────────────────────
-- Inserts a check-in row after validating that:
--   a) the caller is a staff member of p_gym_id, and
--   b) the member actually belongs to that gym.
-- This replaces the direct check_ins.insert in the offline queue flush so
-- a tampered SharedPreferences entry cannot insert cross-gym check-ins.
CREATE OR REPLACE FUNCTION insert_checkin_secure(
  p_member_id    uuid,
  p_gym_id       uuid,
  p_method       text          DEFAULT 'qr',
  p_checked_in_at timestamptz  DEFAULT now()
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff_gym_id uuid;
BEGIN
  SELECT gym_id
    INTO v_staff_gym_id
    FROM profiles
   WHERE id = auth.uid();

  IF v_staff_gym_id IS NULL OR v_staff_gym_id <> p_gym_id THEN
    RAISE EXCEPTION 'unauthorized: gym mismatch';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM members
     WHERE id = p_member_id AND gym_id = p_gym_id
  ) THEN
    RAISE EXCEPTION 'member_not_in_gym';
  END IF;

  INSERT INTO check_ins (member_id, gym_id, staff_id, method, checked_in_at)
  VALUES (p_member_id, p_gym_id, auth.uid(), p_method, p_checked_in_at);
END;
$$;

REVOKE ALL ON FUNCTION insert_checkin_secure(uuid, uuid, text, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION insert_checkin_secure(uuid, uuid, text, timestamptz) TO authenticated;
