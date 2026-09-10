-- ════════════════════════════════════════════════════════════════════
-- SADQ — PHASE 1 FIX: Teacher Login + Registration + RLS Fixes
-- Run this AFTER sadq_admin_fix.sql and sadq_phase1_migration.sql
-- ════════════════════════════════════════════════════════════════════

-- ── 1. RPC: Verify teacher login (SECURITY DEFINER bypasses RLS) ──
CREATE OR REPLACE FUNCTION verify_teacher_login(p_username TEXT, p_password TEXT)
RETURNS TABLE(id UUID, full_name TEXT, username TEXT, subject TEXT, class_organisation TEXT, photo_url TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  t_record RECORD;
BEGIN
  SELECT id, full_name, username, subject, class_organisation, photo_url
  INTO t_record
  FROM teachers
  WHERE username = p_username
    AND password_hash = p_password
    AND account_status = 'active'
  LIMIT 1;

  IF FOUND THEN
    RETURN QUERY SELECT
      t_record.id,
      t_record.full_name,
      t_record.username,
      t_record.subject,
      t_record.class_organisation,
      t_record.photo_url;
  ELSE
    RETURN QUERY SELECT NULL::UUID, NULL::TEXT, NULL::TEXT, NULL::TEXT, NULL::TEXT, NULL::TEXT;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION verify_teacher_login(TEXT, TEXT) TO anon, authenticated;

-- ── 2. Fix registration: set new profiles to 'pending' by default ──
-- First, drop the old trigger that may set 'active'
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Create a function that creates profile with 'pending' status
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO profiles (id, email, full_name, username, role, account_status)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
    COALESCE(NEW.raw_user_meta_data->>'username', ''),
    'student'::user_role,
    'pending'::account_status
  )
  ON CONFLICT (id) DO NOTHING;

  RETURN NEW;
END;
$$;

-- Re-create the trigger
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ── 3. RLS: Allow public to read login_settings (for login page check) ──
-- Already done in phase1 migration, but ensure it works
DROP POLICY IF EXISTS "Public can read login settings" ON login_settings;
CREATE POLICY "Public can read login settings" ON login_settings FOR SELECT USING (true);

-- ── 4. RLS: Allow reading published sub_wing_content by anyone ──
DROP POLICY IF EXISTS "Public can read published wing content" ON sub_wing_content;
CREATE POLICY "Public can read published wing content"
ON sub_wing_content FOR SELECT USING (status = 'published' OR is_admin());

-- ── 5. RLS: Allow reading published certificates by anyone ──
DROP POLICY IF EXISTS "Public can read published certificates" ON certificates;
CREATE POLICY "Public can read published certificates"
ON certificates FOR SELECT USING (status = 'published' OR is_admin() OR student_id = auth.uid());

-- ── 6. RLS: Allow reading approved achievements by anyone ──
DROP POLICY IF EXISTS "Public can read approved achievements" ON class_achievements;
CREATE POLICY "Public can read approved achievements"
ON class_achievements FOR SELECT USING (status = 'approved' OR is_admin());

-- ── 7. RLS: Allow reading active sub_wings by anyone ──
DROP POLICY IF EXISTS "Public can read active sub_wings" ON sub_wings;
CREATE POLICY "Public can read active sub_wings"
ON sub_wings FOR SELECT USING (account_status = 'active' OR is_admin());

-- ── 8. RLS: Anyone can read site_settings (it's public website content) ──
DROP POLICY IF EXISTS "Public can read site settings" ON site_settings;
CREATE POLICY "Public can read site settings" ON site_settings FOR SELECT USING (true);

-- ── 9. RPC: Admin update login settings ────────────────────────────
CREATE OR REPLACE FUNCTION admin_update_login_settings(
  p_student_login BOOLEAN DEFAULT NULL,
  p_teacher_login BOOLEAN DEFAULT NULL,
  p_student_reg BOOLEAN DEFAULT NULL,
  p_reg_approval BOOLEAN DEFAULT NULL,
  p_subwing_login BOOLEAN DEFAULT NULL,
  p_maintenance BOOLEAN DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Permission denied: admin role required';
  END IF;

  UPDATE login_settings SET
    student_login_enabled = COALESCE(p_student_login, student_login_enabled),
    teacher_login_enabled = COALESCE(p_teacher_login, teacher_login_enabled),
    student_registration_enabled = COALESCE(p_student_reg, student_registration_enabled),
    registration_requires_approval = COALESCE(p_reg_approval, registration_requires_approval),
    subwing_login_enabled = COALESCE(p_subwing_login, subwing_login_enabled),
    maintenance_mode = COALESCE(p_maintenance, maintenance_mode),
    updated_at = now(),
    updated_by = auth.uid()
  WHERE id = 1;

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_update_login_settings(BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN) TO authenticated;

-- ── 10. RPC: Get site settings (public, returns all settings as JSON) ──
CREATE OR REPLACE FUNCTION get_site_settings()
RETURNS JSON
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT COALESCE(json_object_agg(key, value), '{}'::json) FROM site_settings;
$$;

GRANT EXECUTE ON FUNCTION get_site_settings() TO anon, authenticated;

-- ── 11. RPC: Get published sub_wing_content for public display ─────
CREATE OR REPLACE FUNCTION get_published_wing_content(p_limit INT DEFAULT 20)
RETURNS TABLE(
  id UUID, wing_name TEXT, content_type TEXT, title TEXT,
  description TEXT, image_url TEXT, event_date TIMESTAMPTZ, created_at TIMESTAMPTZ
)
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT swc.id, sw.name, swc.content_type, swc.title,
         swc.description, swc.image_url, swc.event_date, swc.created_at
  FROM sub_wing_content swc
  JOIN sub_wings sw ON swc.sub_wing_id = sw.id
  WHERE swc.status = 'published' AND sw.account_status = 'active'
  ORDER BY swc.created_at DESC
  LIMIT p_limit;
$$;

GRANT EXECUTE ON FUNCTION get_published_wing_content(INT) TO anon, authenticated;

-- ── 12. RPC: Get student certificates ──────────────────────────────
CREATE OR REPLACE FUNCTION get_student_certificates(p_student_id UUID DEFAULT NULL)
RETURNS TABLE(id UUID, student_name TEXT, certificate_type TEXT, title TEXT,
  description TEXT, image_url TEXT, event_name TEXT, event_date TIMESTAMPTZ, issued_by TEXT)
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT id, student_name, certificate_type, title, description, image_url,
         event_name, event_date, issued_by
  FROM certificates
  WHERE status = 'published'
    AND (p_student_id IS NULL OR student_id = p_student_id OR student_id IS NULL)
  ORDER BY created_at DESC;
$$;

GRANT EXECUTE ON FUNCTION get_student_certificates(UUID) TO anon, authenticated;

-- ── 13. RPC: Get approved achievements (public) ────────────────────
CREATE OR REPLACE FUNCTION get_approved_achievements(p_limit INT DEFAULT 20)
RETURNS TABLE(id UUID, class_name TEXT, achievement_title TEXT, achievement_type TEXT,
  points INTEGER, event_name TEXT, event_date TIMESTAMPTZ, main_committee_approved BOOLEAN)
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT id, class_name, achievement_title, achievement_type,
         points, event_name, event_date, main_committee_approved
  FROM class_achievements
  WHERE status = 'approved'
  ORDER BY points DESC, created_at DESC
  LIMIT p_limit;
$$;

GRANT EXECUTE ON FUNCTION get_approved_achievements(INT) TO anon, authenticated;

-- ════════════════════════════════════════════════════════════════════
-- DONE! Fixes applied:
--   • Teacher login RPC (verify_teacher_login)
--   • Registration trigger fixed (new users = 'pending' status)
--   • Public read policies for all public content
--   • Admin login settings update RPC
--   • Public data access RPCs (site settings, wing content, certificates, achievements)
-- ════════════════════════════════════════════════════════════════════
