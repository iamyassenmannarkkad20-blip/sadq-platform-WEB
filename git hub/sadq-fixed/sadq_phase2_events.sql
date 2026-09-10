-- ════════════════════════════════════════════════════════════════════
-- SADQ — PHASE 2: EVENTS + WINNERS + SERVICE USERS (FIXED v2)
-- Fixes:
--   1. position → winner_position (reserved keyword)
--   2. certificates table pre-exists without student_id → ALTER TABLE ADD COLUMN
--   3. events table pre-exists → columns already handled with ADD COLUMN IF NOT EXISTS
-- ════════════════════════════════════════════════════════════════════

-- ── 0. ENSURE certificates table has student_id column ────────────
-- The certificates table likely already exists from original schema.
-- CREATE TABLE IF NOT EXISTS in Phase 1 was skipped, so student_id was never added.
ALTER TABLE certificates ADD COLUMN IF NOT EXISTS student_id UUID REFERENCES profiles(id) ON DELETE CASCADE;
ALTER TABLE certificates ADD COLUMN IF NOT EXISTS student_name TEXT;
ALTER TABLE certificates ADD COLUMN IF NOT EXISTS certificate_type TEXT DEFAULT 'certificate';
ALTER TABLE certificates ADD COLUMN IF NOT EXISTS title TEXT;
ALTER TABLE certificates ADD COLUMN IF NOT EXISTS description TEXT;
ALTER TABLE certificates ADD COLUMN IF NOT EXISTS image_url TEXT;
ALTER TABLE certificates ADD COLUMN IF NOT EXISTS event_name TEXT;
ALTER TABLE certificates ADD COLUMN IF NOT EXISTS event_date TIMESTAMPTZ;
ALTER TABLE certificates ADD COLUMN IF NOT EXISTS issued_by TEXT DEFAULT 'SADQ';
ALTER TABLE certificates ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'published';
ALTER TABLE certificates ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now();

-- ── 0b. Re-apply certificates RLS with student_id ─────────────────
ALTER TABLE certificates ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can read published certificates" ON certificates;
CREATE POLICY "Anyone can read published certificates" ON certificates FOR SELECT USING (status = 'published' OR is_admin() OR student_id = auth.uid());
DROP POLICY IF EXISTS "Admins can manage certificates" ON certificates;
CREATE POLICY "Admins can manage certificates" ON certificates FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());

-- ── 1. EVENTS — add columns for approval workflow ─────────────────
ALTER TABLE events ADD COLUMN IF NOT EXISTS sub_wing_id UUID REFERENCES sub_wings(id) ON DELETE SET NULL;
ALTER TABLE events ADD COLUMN IF NOT EXISTS event_date TIMESTAMPTZ;
ALTER TABLE events ADD COLUMN IF NOT EXISTS event_end_date TIMESTAMPTZ;
ALTER TABLE events ADD COLUMN IF NOT EXISTS location TEXT;
ALTER TABLE events ADD COLUMN IF NOT EXISTS rules TEXT;
ALTER TABLE events ADD COLUMN IF NOT EXISTS registration_open BOOLEAN DEFAULT true;
ALTER TABLE events ADD COLUMN IF NOT EXISTS max_participants INTEGER;
ALTER TABLE events ADD COLUMN IF NOT EXISTS poster_url TEXT;
ALTER TABLE events ADD COLUMN IF NOT EXISTS approval_status TEXT DEFAULT 'pending';
ALTER TABLE events ADD COLUMN IF NOT EXISTS approved_by UUID REFERENCES auth.users(id);
ALTER TABLE events ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ;
ALTER TABLE events ADD COLUMN IF NOT EXISTS created_by_wing TEXT;
ALTER TABLE events ADD COLUMN IF NOT EXISTS is_official BOOLEAN DEFAULT false;

-- ── 2. EVENT_REGISTRATIONS ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS event_registrations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID REFERENCES events(id) ON DELETE CASCADE,
  student_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  student_name TEXT,
  class_name TEXT,
  registered_at TIMESTAMPTZ DEFAULT now(),
  attendance_status TEXT DEFAULT 'registered',
  UNIQUE(event_id, student_id)
);
ALTER TABLE event_registrations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can read approved event registrations" ON event_registrations;
CREATE POLICY "Anyone can read approved event registrations" ON event_registrations FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "Students can register for events" ON event_registrations;
CREATE POLICY "Students can register for events" ON event_registrations FOR INSERT TO authenticated WITH CHECK (student_id = auth.uid());
DROP POLICY IF EXISTS "Admins can update registrations" ON event_registrations;
CREATE POLICY "Admins can update registrations" ON event_registrations FOR UPDATE TO authenticated USING (is_admin()) WITH CHECK (is_admin());
DROP POLICY IF EXISTS "Admins can delete registrations" ON event_registrations;
CREATE POLICY "Admins can delete registrations" ON event_registrations FOR DELETE TO authenticated USING (is_admin());

-- ── 3. EVENT_RESULTS ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS event_results (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID REFERENCES events(id) ON DELETE CASCADE,
  student_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
  student_name TEXT NOT NULL,
  class_name TEXT,
  winner_position TEXT,
  result_description TEXT,
  result_photo_url TEXT,
  submitted_by_wing TEXT,
  approval_status TEXT DEFAULT 'pending',
  approved_by UUID REFERENCES auth.users(id),
  approved_at TIMESTAMPTZ,
  is_official_winner BOOLEAN DEFAULT false,
  declared_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE event_results ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can read approved results" ON event_results;
CREATE POLICY "Anyone can read approved results" ON event_results FOR SELECT USING (approval_status = 'approved' OR is_admin());
DROP POLICY IF EXISTS "Admins can manage results" ON event_results;
CREATE POLICY "Admins can manage results" ON event_results FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());

-- ── 4. WINNER_BANNERS ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS winner_banners (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_name TEXT NOT NULL,
  student_photo TEXT,
  event_name TEXT,
  achievement TEXT,
  winner_position TEXT,
  class_name TEXT,
  sub_wing_name TEXT,
  result_id UUID REFERENCES event_results(id) ON DELETE SET NULL,
  is_featured BOOLEAN DEFAULT false,
  display_order INTEGER DEFAULT 0,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE winner_banners ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can read active banners" ON winner_banners;
CREATE POLICY "Anyone can read active banners" ON winner_banners FOR SELECT USING (is_active = true OR is_admin());
DROP POLICY IF EXISTS "Admins can manage banners" ON winner_banners;
CREATE POLICY "Admins can manage banners" ON winner_banners FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());

-- ── 5. SERVICE_USERS ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS service_users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  full_name TEXT NOT NULL,
  email TEXT,
  phone TEXT,
  service_type TEXT DEFAULT 'service',
  skills TEXT,
  approved BOOLEAN DEFAULT false,
  approved_by UUID REFERENCES auth.users(id),
  approved_at TIMESTAMPTZ,
  account_status TEXT DEFAULT 'pending',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE service_users ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admins can read all service users" ON service_users;
CREATE POLICY "Admins can read all service users" ON service_users FOR SELECT TO authenticated USING (is_admin() OR profile_id = auth.uid());
DROP POLICY IF EXISTS "Users can apply for service access" ON service_users;
CREATE POLICY "Users can apply for service access" ON service_users FOR INSERT TO authenticated WITH CHECK (profile_id = auth.uid());
DROP POLICY IF EXISTS "Admins can update service users" ON service_users;
CREATE POLICY "Admins can update service users" ON service_users FOR UPDATE TO authenticated USING (is_admin()) WITH CHECK (is_admin());

-- ── 6. RPC: Approve event ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION admin_approve_event(p_event_id UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Permission denied'; END IF;
  UPDATE events SET approval_status = 'approved', approved_by = auth.uid(), approved_at = now(), is_official = true
  WHERE id = p_event_id;
  RETURN TRUE;
END;
$$;

-- ── 7. RPC: Reject event ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION admin_reject_event(p_event_id UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Permission denied'; END IF;
  UPDATE events SET approval_status = 'rejected', approved_by = auth.uid(), approved_at = now()
  WHERE id = p_event_id;
  RETURN TRUE;
END;
$$;

-- ── 8. RPC: Declare official winner ───────────────────────────────
CREATE OR REPLACE FUNCTION admin_declare_winner(p_result_id UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Permission denied'; END IF;
  UPDATE event_results
  SET is_official_winner = true, approval_status = 'approved', approved_by = auth.uid(), approved_at = now(), declared_at = now()
  WHERE id = p_result_id;
  RETURN TRUE;
END;
$$;

-- ── 9. RPC: Get approved events (public) ──────────────────────────
CREATE OR REPLACE FUNCTION get_approved_events(p_limit INT DEFAULT 10)
RETURNS TABLE(id UUID, title TEXT, description TEXT, event_date TIMESTAMPTZ, location TEXT,
  poster_url TEXT, rules TEXT, registration_open BOOLEAN, max_participants INT, sub_wing_name TEXT)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT e.id, e.title, e.description, e.event_date, e.location,
         e.poster_url, e.rules, e.registration_open, e.max_participants,
         sw.name
  FROM events e
  LEFT JOIN sub_wings sw ON e.sub_wing_id = sw.id
  WHERE e.approval_status = 'approved'
  ORDER BY e.event_date DESC NULLS LAST
  LIMIT p_limit;
$$;

-- ── 10. RPC: Get featured winner banners (public) ──────────────────
CREATE OR REPLACE FUNCTION get_featured_winners(p_limit INT DEFAULT 5)
RETURNS TABLE(id UUID, student_name TEXT, student_photo TEXT, event_name TEXT,
  achievement TEXT, winner_position TEXT, class_name TEXT, sub_wing_name TEXT)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT id, student_name, student_photo, event_name, achievement, winner_position, class_name, sub_wing_name
  FROM winner_banners
  WHERE is_active = true
  ORDER BY is_featured DESC, display_order ASC, created_at DESC
  LIMIT p_limit;
$$;

-- ── 11. RPC: Get student achievements ─────────────────────────────
-- Uses student_id column which we ensured exists in section 0 above.
CREATE OR REPLACE FUNCTION get_student_achievements(p_student_id UUID)
RETURNS TABLE(id UUID, title TEXT, description TEXT, image_url TEXT, event_name TEXT,
  event_date TIMESTAMPTZ, certificate_type TEXT, issued_by TEXT)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT id, title, description, image_url, event_name, event_date, certificate_type, issued_by
  FROM certificates
  WHERE status = 'published' AND (student_id = p_student_id OR student_id IS NULL)
  ORDER BY created_at DESC;
$$;

-- ── 12. Grants ────────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION admin_approve_event(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_reject_event(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_declare_winner(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_approved_events(INT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_featured_winners(INT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_student_achievements(UUID) TO authenticated;

-- ── 13. Triggers ──────────────────────────────────────────────────
DROP TRIGGER IF EXISTS set_updated_at_event_reg ON event_registrations;
CREATE TRIGGER set_updated_at_event_reg BEFORE UPDATE ON event_registrations FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at_service_users ON service_users;
CREATE TRIGGER set_updated_at_service_users BEFORE UPDATE ON service_users FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ── 14. Events RLS ────────────────────────────────────────────────
DROP POLICY IF EXISTS "Anyone can read approved events" ON events;
CREATE POLICY "Anyone can read approved events" ON events FOR SELECT USING (approval_status = 'approved' OR is_admin());
DROP POLICY IF EXISTS "Admins can manage events" ON events;
CREATE POLICY "Admins can manage events" ON events FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());

-- ════════════════════════════════════════════════════════════════════
-- DONE! Phase 2 complete (fixed v2):
--   • position → winner_position (reserved keyword fix)
--   • certificates.student_id added via ALTER TABLE (pre-existing table)
--   • All policies use DROP IF EXISTS (no duplicates)
--   • All triggers use DROP IF EXISTS (no conflicts)
-- ════════════════════════════════════════════════════════════════════
