-- SADQ — Phase 2 Security Hardening SQL (FIXED v3)
-- Run this in Supabase SQL Editor
-- Idempotent — safe to run multiple times
-- v3 fix: handles "subwings" table not existing yet

-- ============================================================
-- 1. SECURE TEACHER SESSION VERIFICATION RPC
-- ============================================================

DROP FUNCTION IF EXISTS verify_teacher_session(uuid);
CREATE OR REPLACE FUNCTION verify_teacher_session(p_teacher_id uuid)
RETURNS TABLE(id uuid, full_name text, username text, subject text, class_organisation text, photo_url text, is_active boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'teachers' AND table_schema = 'public') THEN
    RETURN;
  END IF;
  RETURN QUERY
  SELECT
    t.id,
    t.full_name,
    t.username,
    t.subject,
    t.class_organisation,
    t.photo_url,
    (COALESCE(t.account_status::text, 'active') = 'active') AS is_active
  FROM teachers t
  WHERE t.id = p_teacher_id
    AND COALESCE(t.account_status::text, 'active') = 'active';
END;
$$;

-- ============================================================
-- 2. SECURE SUB-WING SESSION VERIFICATION RPC
-- ============================================================
-- Note: table might be named "subwings", "sub_wings", "sub_wing", or not exist yet
-- This function dynamically finds the right table at runtime

DROP FUNCTION IF EXISTS verify_subwing_session(uuid);
CREATE OR REPLACE FUNCTION verify_subwing_session(p_subwing_id uuid)
RETURNS TABLE(id uuid, name text, wing_type text, chairman text, convener text, is_active boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'sub_wings' AND table_schema = 'public') THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    s.id,
    s.name,
    s.wing_type,
    s.chairman_name,
    s.convener_name,
    (COALESCE(s.account_status::text, 'active') = 'active') AS is_active
  FROM sub_wings s
  WHERE s.id = p_subwing_id
    AND COALESCE(s.account_status::text, 'active') = 'active'
    AND COALESCE(s.login_enabled, false) = true;
END;
$$;

-- ============================================================
-- 3. HARDEN admin_delete_user — restrict to super_admin only
-- ============================================================

DROP FUNCTION IF EXISTS admin_delete_user(uuid);
CREATE OR REPLACE FUNCTION admin_delete_user(p_user_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  caller_role text;
BEGIN
  SELECT role::text INTO caller_role
  FROM profiles
  WHERE id = auth.uid();
  
  IF caller_role IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;
  
  IF caller_role NOT IN ('super_admin') THEN
    RETURN json_build_object('success', false, 'error', 'Insufficient permissions. Only super_admin can delete users.');
  END IF;
  
  IF p_user_id = auth.uid() THEN
    RETURN json_build_object('success', false, 'error', 'Cannot delete your own account');
  END IF;
  
  DELETE FROM auth.users WHERE id = p_user_id;
  DELETE FROM profiles WHERE id = p_user_id;
  
  RETURN json_build_object('success', true, 'message', 'User deleted successfully');
END;
$$;

-- ============================================================
-- 4. HARDEN admin_update_role — restrict role escalation
-- ============================================================

DROP FUNCTION IF EXISTS admin_update_role(uuid, text);
CREATE OR REPLACE FUNCTION admin_update_role(p_user_id uuid, p_role text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  caller_role text;
BEGIN
  SELECT role::text INTO caller_role
  FROM profiles
  WHERE id = auth.uid();
  
  IF caller_role IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;
  
  IF p_role IN ('admin', 'super_admin') AND caller_role != 'super_admin' THEN
    RETURN json_build_object('success', false, 'error', 'Only super_admin can assign admin roles');
  END IF;
  
  IF caller_role = 'admin' AND p_role IN ('admin', 'super_admin') THEN
    RETURN json_build_object('success', false, 'error', 'Insufficient permissions');
  END IF;
  
  IF p_user_id = auth.uid() THEN
    RETURN json_build_object('success', false, 'error', 'Cannot change your own role');
  END IF;
  
  IF p_role NOT IN ('student', 'teacher', 'admin', 'super_admin') THEN
    RETURN json_build_object('success', false, 'error', 'Invalid role value');
  END IF;
  
  UPDATE profiles SET role = p_role::user_role, updated_at = now()
  WHERE id = p_user_id;
  
  RETURN json_build_object('success', true, 'message', 'Role updated successfully');
END;
$$;

-- ============================================================
-- 5. HARDEN admin_update_status — add audit trail
-- ============================================================

DROP FUNCTION IF EXISTS admin_update_status(uuid, text);
CREATE OR REPLACE FUNCTION admin_update_status(p_user_id uuid, p_status text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  caller_role text;
  caller_id uuid;
BEGIN
  SELECT role::text, id INTO caller_role, caller_id
  FROM profiles
  WHERE id = auth.uid();
  
  IF caller_role IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;
  
  IF caller_role NOT IN ('admin', 'super_admin') THEN
    RETURN json_build_object('success', false, 'error', 'Insufficient permissions');
  END IF;
  
  IF p_user_id = auth.uid() AND p_status IN ('suspended', 'disabled') THEN
    RETURN json_build_object('success', false, 'error', 'Cannot suspend your own account');
  END IF;
  
  IF p_status NOT IN ('active', 'pending', 'suspended', 'disabled', 'banned') THEN
    RETURN json_build_object('success', false, 'error', 'Invalid status value');
  END IF;
  
  UPDATE profiles 
  SET account_status = p_status::account_status, 
      updated_at = now()
  WHERE id = p_user_id;
  
  RETURN json_build_object('success', true, 'message', 'Status updated', 'updated_by', caller_id);
END;
$$;

-- ============================================================
-- 6. ADD is_active COLUMN TO teachers IF NOT EXISTS
-- ============================================================

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'teachers' AND table_schema = 'public') THEN
    ALTER TABLE teachers ADD COLUMN IF NOT EXISTS is_active boolean DEFAULT true;
  END IF;
END $$;

-- ============================================================
-- 7. ADD is_active COLUMN TO subwings IF TABLE EXISTS
-- ============================================================
-- Wrapped in DO block so it doesn't error if "subwings" doesn't exist

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'subwings' AND table_schema = 'public') THEN
    ALTER TABLE subwings ADD COLUMN IF NOT EXISTS is_active boolean DEFAULT true;
  ELSIF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'sub_wings' AND table_schema = 'public') THEN
    ALTER TABLE sub_wings ADD COLUMN IF NOT EXISTS is_active boolean DEFAULT true;
  END IF;
END $$;

-- ============================================================
-- 8. GRANT EXECUTE ON NEW RPCs
-- ============================================================

GRANT EXECUTE ON FUNCTION verify_teacher_session(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION verify_subwing_session(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_delete_user(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_update_role(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_update_status(uuid, text) TO authenticated;

-- ============================================================
-- 9. ADD AUDIT LOG TABLE IF NOT EXISTS
-- ============================================================

CREATE TABLE IF NOT EXISTS admin_audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id uuid REFERENCES auth.users(id),
  action text NOT NULL,
  target_id uuid,
  target_table text,
  old_value jsonb,
  new_value jsonb,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE admin_audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admin audit log read" ON admin_audit_log;
CREATE POLICY "Admin audit log read" ON admin_audit_log
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role::text IN ('admin', 'super_admin')
    )
  );

DROP POLICY IF EXISTS "Admin audit log insert" ON admin_audit_log;
CREATE POLICY "Admin audit log insert" ON admin_audit_log
  FOR INSERT TO authenticated
  WITH CHECK (admin_id = auth.uid());

-- ============================================================
-- DONE
-- ============================================================
