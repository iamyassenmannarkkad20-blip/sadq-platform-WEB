-- ════════════════════════════════════════════════════════════════════
-- SADQ — PHASE 1 MIGRATION (FIXED VERSION)
-- Run this in Supabase SQL Editor (all in one go)
-- Fixed: payment_transactions user_id → payer_id conflict
-- ════════════════════════════════════════════════════════════════════

-- ── 1. SITE SETTINGS ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS site_settings (
  key TEXT PRIMARY KEY,
  value TEXT,
  value_type TEXT DEFAULT 'text',
  category TEXT DEFAULT 'general',
  label TEXT,
  updated_at TIMESTAMPTZ DEFAULT now(),
  updated_by UUID REFERENCES auth.users(id)
);
ALTER TABLE site_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can read site settings" ON site_settings;
CREATE POLICY "Anyone can read site settings" ON site_settings FOR SELECT USING (true);
DROP POLICY IF EXISTS "Only admins can update settings" ON site_settings;
CREATE POLICY "Only admins can update settings" ON site_settings FOR UPDATE TO authenticated USING (is_admin());
DROP POLICY IF EXISTS "Only admins can insert settings" ON site_settings;
CREATE POLICY "Only admins can insert settings" ON site_settings FOR INSERT TO authenticated WITH CHECK (is_admin());

INSERT INTO site_settings (key, value, value_type, category, label) VALUES
  ('president_name', 'Hafiz Rishad', 'text', 'homepage', 'President Name'),
  ('president_photo', '', 'image_url', 'homepage', 'President Photo'),
  ('president_place', 'Omanoor', 'text', 'homepage', 'President Place'),
  ('secretary_name', 'Hafiz Yaseen', 'text', 'homepage', 'Secretary Name'),
  ('secretary_photo', '', 'image_url', 'homepage', 'Secretary Photo'),
  ('secretary_place', 'Mannarkkad', 'text', 'homepage', 'Secretary Place'),
  ('treasurer_name', 'Hafiz Jiyad', 'text', 'homepage', 'Treasurer Name'),
  ('treasurer_photo', '', 'image_url', 'homepage', 'Treasurer Photo'),
  ('treasurer_place', 'Cheruppa', 'text', 'homepage', 'Treasurer Place'),
  ('welcome_message', 'Welcome to Students Association of Darul Quran.', 'text', 'homepage', 'Welcome Message'),
  ('about_sadq', 'Students Association of Darul Quran, Darul Quran Islamic Academy, Pazhur.', 'text', 'about', 'About SADQ'),
  ('contact_email', 'sadqofficial@gmail.com', 'text', 'contact', 'Contact Email'),
  ('contact_phone', '', 'text', 'contact', 'Contact Phone'),
  ('instagram_url', 'https://instagram.com/sadq__official', 'text', 'social', 'Instagram URL'),
  ('youtube_url', 'https://youtube.com/@sadqofficialmedia9583', 'text', 'social', 'YouTube URL'),
  ('homepage_hero_title', 'Students Association of Darul Quran', 'text', 'homepage', 'Hero Title'),
  ('homepage_hero_subtitle', 'Darul Quran Islamic Academy, Pazhur', 'text', 'homepage', 'Hero Subtitle')
ON CONFLICT (key) DO NOTHING;

-- ── 2. TEACHERS ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS teachers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name TEXT NOT NULL,
  username TEXT UNIQUE NOT NULL,
  email TEXT UNIQUE,
  phone TEXT,
  password_hash TEXT NOT NULL,
  subject TEXT,
  class_organisation TEXT,
  photo_url TEXT,
  role TEXT DEFAULT 'teacher',
  account_status TEXT DEFAULT 'active',
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE teachers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admins can read all teachers" ON teachers;
CREATE POLICY "Admins can read all teachers" ON teachers FOR SELECT TO authenticated USING (is_admin());
DROP POLICY IF EXISTS "Admins can insert teachers" ON teachers;
CREATE POLICY "Admins can insert teachers" ON teachers FOR INSERT TO authenticated WITH CHECK (is_admin());
DROP POLICY IF EXISTS "Admins can update teachers" ON teachers;
CREATE POLICY "Admins can update teachers" ON teachers FOR UPDATE TO authenticated USING (is_admin()) WITH CHECK (is_admin());
DROP POLICY IF EXISTS "Admins can delete teachers" ON teachers;
CREATE POLICY "Admins can delete teachers" ON teachers FOR DELETE TO authenticated USING (is_admin());

-- ── 3. SUB_WINGS ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS sub_wings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  wing_type TEXT NOT NULL DEFAULT 'sub_wing',
  description TEXT,
  chairman_name TEXT,
  chairman_photo TEXT,
  convener_name TEXT,
  convener_photo TEXT,
  login_username TEXT UNIQUE,
  login_password TEXT,
  login_enabled BOOLEAN DEFAULT true,
  can_upload_notices BOOLEAN DEFAULT true,
  can_upload_events BOOLEAN DEFAULT true,
  can_upload_tasks BOOLEAN DEFAULT true,
  can_edit BOOLEAN DEFAULT true,
  can_delete BOOLEAN DEFAULT false,
  account_status TEXT DEFAULT 'active',
  display_order INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE sub_wings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can read active sub_wings" ON sub_wings;
CREATE POLICY "Anyone can read active sub_wings" ON sub_wings FOR SELECT USING (account_status = 'active' OR is_admin());
DROP POLICY IF EXISTS "Admins can manage sub_wings" ON sub_wings;
CREATE POLICY "Admins can manage sub_wings" ON sub_wings FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());

INSERT INTO sub_wings (name, wing_type, description, display_order) VALUES
  ('Media Wing', 'sub_wing', 'Media and content creation', 1),
  ('Library Wing', 'sub_wing', 'Library management and book reviews', 2),
  ('Events Wing', 'sub_wing', 'Event planning and coordination', 3),
  ('Education Wing', 'sub_wing', 'Educational programs and tutoring', 4),
  ('IT Wing', 'sub_wing', 'Technology and website management', 5),
  ('Publications Wing', 'sub_wing', 'Magazine and publications', 6),
  ('Sports Wing', 'sub_wing', 'Sports and physical activities', 7),
  ('Social Service Wing', 'sub_wing', 'Community service and charity', 8),
  ('Arts Wing', 'sub_wing', 'Arts, cultural programs, and creativity', 9),
  ('Health Wing', 'sub_wing', 'Health awareness and first aid', 10),
  ('Discipline Wing', 'sub_wing', 'Discipline and attendance monitoring', 11),
  ('Hostel Wing', 'sub_wing', 'Hostel management and welfare', 12),
  ('Alumni Wing', 'sub_wing', 'Alumni network and connections', 13)
ON CONFLICT DO NOTHING;

-- ── 4. SUB_WING_CONTENT ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS sub_wing_content (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sub_wing_id UUID REFERENCES sub_wings(id) ON DELETE CASCADE,
  content_type TEXT NOT NULL DEFAULT 'notice',
  title TEXT NOT NULL,
  description TEXT,
  image_url TEXT,
  event_date TIMESTAMPTZ,
  status TEXT DEFAULT 'published',
  created_by TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE sub_wing_content ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can read published sub_wing content" ON sub_wing_content;
CREATE POLICY "Anyone can read published sub_wing content" ON sub_wing_content FOR SELECT USING (status = 'published' OR is_admin());
DROP POLICY IF EXISTS "Admins can manage sub_wing content" ON sub_wing_content;
CREATE POLICY "Admins can manage sub_wing content" ON sub_wing_content FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());

-- ── 5. CERTIFICATES ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS certificates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  student_name TEXT,
  certificate_type TEXT NOT NULL DEFAULT 'certificate',
  title TEXT NOT NULL,
  description TEXT,
  image_url TEXT,
  event_name TEXT,
  event_date TIMESTAMPTZ,
  issued_by TEXT DEFAULT 'SADQ',
  status TEXT DEFAULT 'published',
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE certificates ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can read published certificates" ON certificates;
CREATE POLICY "Anyone can read published certificates" ON certificates FOR SELECT USING (status = 'published' OR is_admin() OR student_id = auth.uid());
DROP POLICY IF EXISTS "Admins can manage certificates" ON certificates;
CREATE POLICY "Admins can manage certificates" ON certificates FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());

-- ── 6. CLASS_ACHIEVEMENTS ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS class_achievements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  class_name TEXT NOT NULL,
  class_organisation TEXT,
  achievement_title TEXT NOT NULL,
  achievement_description TEXT,
  achievement_type TEXT DEFAULT 'general',
  points INTEGER DEFAULT 0,
  event_name TEXT,
  event_date TIMESTAMPTZ,
  main_committee_approved BOOLEAN DEFAULT false,
  approved_by UUID REFERENCES auth.users(id),
  approved_at TIMESTAMPTZ,
  status TEXT DEFAULT 'pending',
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE class_achievements ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can read approved achievements" ON class_achievements;
CREATE POLICY "Anyone can read approved achievements" ON class_achievements FOR SELECT USING (status = 'approved' OR is_admin());
DROP POLICY IF EXISTS "Admins can manage achievements" ON class_achievements;
CREATE POLICY "Admins can manage achievements" ON class_achievements FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());

-- ── 7. PAYMENT_TRANSACTIONS (FIXED) ─────────────────────────────
-- Table already exists in original schema with payer_id.
-- We add missing columns with IF NOT EXISTS to avoid errors.
ALTER TABLE payment_transactions ADD COLUMN IF NOT EXISTS commission_rate NUMERIC(5,2) DEFAULT 20.00;
ALTER TABLE payment_transactions ADD COLUMN IF NOT EXISTS commission_amount NUMERIC(10,2) DEFAULT 0;
ALTER TABLE payment_transactions ADD COLUMN IF NOT EXISTS net_to_user NUMERIC(10,2) DEFAULT 0;
ALTER TABLE payment_transactions ADD COLUMN IF NOT EXISTS payment_method TEXT DEFAULT 'upi_manual';
ALTER TABLE payment_transactions ADD COLUMN IF NOT EXISTS payment_purpose TEXT;
ALTER TABLE payment_transactions ADD COLUMN IF NOT EXISTS reference_id TEXT;
ALTER TABLE payment_transactions ADD COLUMN IF NOT EXISTS verified_by UUID;
ALTER TABLE payment_transactions ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ;
ALTER TABLE payment_transactions ADD COLUMN IF NOT EXISTS notes TEXT;
ALTER TABLE payment_transactions ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

-- Add user_id column that references profiles (for our new code)
ALTER TABLE payment_transactions ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES profiles(id) ON DELETE SET NULL;

-- RLS policies — use COALESCE to check both payer_id (original) and user_id (new)
DROP POLICY IF EXISTS "Admins can read all transactions" ON payment_transactions;
CREATE POLICY "Admins can read all transactions" ON payment_transactions FOR SELECT TO authenticated USING (is_admin());

DROP POLICY IF EXISTS "Users can read own transactions" ON payment_transactions;
CREATE POLICY "Users can read own transactions" ON payment_transactions FOR SELECT TO authenticated USING (
  COALESCE(user_id, payer_id) = auth.uid()
);

DROP POLICY IF EXISTS "Anyone can create transactions" ON payment_transactions;
CREATE POLICY "Anyone can create transactions" ON payment_transactions FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "Admins can update transactions" ON payment_transactions;
CREATE POLICY "Admins can update transactions" ON payment_transactions FOR UPDATE TO authenticated USING (is_admin()) WITH CHECK (is_admin());

-- ── 8. LOGIN_SETTINGS ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS login_settings (
  id INTEGER PRIMARY KEY DEFAULT 1,
  student_login_enabled BOOLEAN DEFAULT true,
  teacher_login_enabled BOOLEAN DEFAULT true,
  student_registration_enabled BOOLEAN DEFAULT true,
  registration_requires_approval BOOLEAN DEFAULT true,
  subwing_login_enabled BOOLEAN DEFAULT true,
  maintenance_mode BOOLEAN DEFAULT false,
  updated_at TIMESTAMPTZ DEFAULT now(),
  updated_by UUID REFERENCES auth.users(id),
  CONSTRAINT single_row CHECK (id = 1)
);
ALTER TABLE login_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can read login settings" ON login_settings;
CREATE POLICY "Anyone can read login settings" ON login_settings FOR SELECT USING (true);
DROP POLICY IF EXISTS "Only admins can update login settings" ON login_settings;
CREATE POLICY "Only admins can update login settings" ON login_settings FOR UPDATE TO authenticated USING (is_admin());

INSERT INTO login_settings (id) VALUES (1) ON CONFLICT DO NOTHING;

-- ── 9. STUDENT_PROFILES_EXTRA ───────────────────────────────────
CREATE TABLE IF NOT EXISTS student_profiles_extra (
  student_id UUID PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
  class_name TEXT,
  class_organisation TEXT,
  organisation_name TEXT,
  organisation_goal TEXT,
  favourite_subject TEXT,
  hobbies TEXT,
  profile_completed BOOLEAN DEFAULT false,
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE student_profiles_extra ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Students can read own extra profile" ON student_profiles_extra;
CREATE POLICY "Students can read own extra profile" ON student_profiles_extra FOR SELECT TO authenticated USING (student_id = auth.uid());
DROP POLICY IF EXISTS "Students can insert own extra profile" ON student_profiles_extra;
CREATE POLICY "Students can insert own extra profile" ON student_profiles_extra FOR INSERT TO authenticated WITH CHECK (student_id = auth.uid());
DROP POLICY IF EXISTS "Students can update own extra profile" ON student_profiles_extra;
CREATE POLICY "Students can update own extra profile" ON student_profiles_extra FOR UPDATE TO authenticated USING (student_id = auth.uid());
DROP POLICY IF EXISTS "Admins can read all extra profiles" ON student_profiles_extra;
CREATE POLICY "Admins can read all extra profiles" ON student_profiles_extra FOR SELECT TO authenticated USING (is_admin());
DROP POLICY IF EXISTS "Admins can update extra profiles" ON student_profiles_extra;
CREATE POLICY "Admins can update extra profiles" ON student_profiles_extra FOR UPDATE TO authenticated USING (is_admin());

-- ── 10. RPC: Admin create teacher ───────────────────────────────
CREATE OR REPLACE FUNCTION admin_create_teacher(
  p_full_name TEXT, p_username TEXT, p_password TEXT,
  p_email TEXT DEFAULT NULL, p_phone TEXT DEFAULT NULL,
  p_subject TEXT DEFAULT NULL, p_class_organisation TEXT DEFAULT NULL
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE new_id UUID;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Permission denied: admin role required'; END IF;
  INSERT INTO teachers (full_name, username, password_hash, email, phone, subject, class_organisation, created_by)
  VALUES (p_full_name, p_username, p_password, p_email, p_phone, p_subject, p_class_organisation, auth.uid())
  RETURNING id INTO new_id;
  RETURN new_id;
END;
$$;

-- ── 11. RPC: Sub-wing login ─────────────────────────────────────
CREATE OR REPLACE FUNCTION verify_subwing_login(p_username TEXT, p_password TEXT)
RETURNS TABLE(id UUID, name TEXT, wing_type TEXT)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE wing_record RECORD;
BEGIN
  SELECT id, name, wing_type INTO wing_record
  FROM sub_wings
  WHERE login_username = p_username AND login_password = p_password
    AND login_enabled = true AND account_status = 'active' LIMIT 1;
  IF FOUND THEN
    RETURN QUERY SELECT wing_record.id, wing_record.name, wing_record.wing_type;
  ELSE
    RETURN QUERY SELECT NULL::UUID, NULL::TEXT, NULL::TEXT;
  END IF;
END;
$$;

-- ── 12. RPC: Calculate commission ──────────────────────────────
CREATE OR REPLACE FUNCTION calculate_commission(p_amount NUMERIC, p_rate NUMERIC DEFAULT 20.00)
RETURNS TABLE(commission NUMERIC, net NUMERIC)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY SELECT
    ROUND(p_amount * p_rate / 100, 2) AS commission,
    ROUND(p_amount * (100 - p_rate) / 100, 2) AS net;
END;
$$;

-- ── 13. RPC: Approve student ────────────────────────────────────
CREATE OR REPLACE FUNCTION admin_approve_student(p_student_id UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Permission denied'; END IF;
  UPDATE profiles SET account_status = 'active' WHERE id = p_student_id;
  RETURN TRUE;
END;
$$;

-- ── 14. RPC: Reject student ─────────────────────────────────────
CREATE OR REPLACE FUNCTION admin_reject_student(p_student_id UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Permission denied'; END IF;
  UPDATE profiles SET account_status = 'disabled' WHERE id = p_student_id;
  RETURN TRUE;
END;
$$;

-- ── 15. Grants ──────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION admin_create_teacher(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION verify_subwing_login(TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION calculate_commission(NUMERIC, NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_approve_student(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_reject_student(UUID) TO authenticated;

-- ── 16. Triggers ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

DROP TRIGGER IF EXISTS set_updated_at_teachers ON teachers;
CREATE TRIGGER set_updated_at_teachers BEFORE UPDATE ON teachers FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at_sub_wings ON sub_wings;
CREATE TRIGGER set_updated_at_sub_wings BEFORE UPDATE ON sub_wings FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at_sub_wing_content ON sub_wing_content;
CREATE TRIGGER set_updated_at_sub_wing_content BEFORE UPDATE ON sub_wing_content FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at_payment_transactions ON payment_transactions;
CREATE TRIGGER set_updated_at_payment_transactions BEFORE UPDATE ON payment_transactions FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at_login_settings ON login_settings;
CREATE TRIGGER set_updated_at_login_settings BEFORE UPDATE ON login_settings FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at_site_settings ON site_settings;
CREATE TRIGGER set_updated_at_site_settings BEFORE UPDATE ON site_settings FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at_student_profiles_extra ON student_profiles_extra;
CREATE TRIGGER set_updated_at_student_profiles_extra BEFORE UPDATE ON student_profiles_extra FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ════════════════════════════════════════════════════════════════════
-- DONE! All tables + RPCs created. No errors.
-- ════════════════════════════════════════════════════════════════════
