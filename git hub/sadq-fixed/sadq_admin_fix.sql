-- ═══════════════════════════════════════════════════════════════
-- SADQ — ADMIN MANAGEMENT FIX
-- Run this in Supabase SQL Editor to enable admin controls
-- ═══════════════════════════════════════════════════════════════

-- ── 1. Drop the protect_profile trigger (it blocks admin updates) ──
DROP TRIGGER IF EXISTS protect_profile ON profiles;
DROP FUNCTION IF EXISTS protect_profile();

-- ── 2. Create a helper function to check admin ───────────────────
CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid()
    AND role::text IN ('admin', 'super_admin')
  );
$$;

-- ── 3. RLS Policies for admin management ────────────────────────
-- Allow admins to read all profiles
DROP POLICY IF EXISTS "Admins can read all profiles" ON profiles;
CREATE POLICY "Admins can read all profiles"
ON profiles FOR SELECT
TO authenticated
USING (is_admin() OR id = auth.uid());

-- Allow admins to update any profile (suspend, restore, role change)
DROP POLICY IF EXISTS "Admins can update profiles" ON profiles;
CREATE POLICY "Admins can update profiles"
ON profiles FOR UPDATE
TO authenticated
USING (is_admin() OR id = auth.uid())
WITH CHECK (is_admin() OR id = auth.uid());

-- ── 4. RPC: Admin delete user ───────────────────────────────────
-- This allows admin to delete a user from the frontend
CREATE OR REPLACE FUNCTION admin_delete_user(target_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Verify caller is admin
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Permission denied: admin role required';
  END IF;

  -- Prevent self-deletion
  IF target_user_id = auth.uid() THEN
    RAISE EXCEPTION 'Cannot delete your own account';
  END IF;

  -- Delete profile first (in case FK doesn't cascade)
  DELETE FROM profiles WHERE id = target_user_id;

  -- Delete the auth user
  DELETE FROM auth.users WHERE id = target_user_id;

  RETURN TRUE;
END;
$$;

-- ── 5. RPC: Admin update role ──────────────────────────────────
-- This bypasses any remaining triggers
CREATE OR REPLACE FUNCTION admin_update_role(target_user_id UUID, new_role TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Verify caller is admin
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Permission denied: admin role required';
  END IF;

  -- Prevent self-role-change (optional safety)
  IF target_user_id = auth.uid() THEN
    RAISE EXCEPTION 'Cannot change your own role';
  END IF;

  -- Update the role
  UPDATE profiles SET role = new_role::user_role WHERE id = target_user_id;

  RETURN TRUE;
END;
$$;

-- ── 6. RPC: Admin update account status ────────────────────────
CREATE OR REPLACE FUNCTION admin_update_status(target_user_id UUID, new_status TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Permission denied: admin role required';
  END IF;

  IF target_user_id = auth.uid() THEN
    RAISE EXCEPTION 'Cannot suspend your own account';
  END IF;

  UPDATE profiles SET account_status = new_status::account_status WHERE id = target_user_id;

  RETURN TRUE;
END;
$$;

-- ── 7. Grant execute to authenticated users ─────────────────────
GRANT EXECUTE ON FUNCTION is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION admin_delete_user(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_update_role(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_update_status(UUID, TEXT) TO authenticated;

-- ── 8. RLS for content tables (admin can update status) ─────────
-- Posts
DROP POLICY IF EXISTS "Admins can update posts" ON posts;
CREATE POLICY "Admins can update posts"
ON posts FOR UPDATE TO authenticated
USING (is_admin() OR author_id = auth.uid())
WITH CHECK (is_admin() OR author_id = auth.uid());

-- Student magazines
DROP POLICY IF EXISTS "Admins can update student_magazines" ON student_magazines;
CREATE POLICY "Admins can update student_magazines"
ON student_magazines FOR UPDATE TO authenticated
USING (is_admin() OR author_id = auth.uid())
WITH CHECK (is_admin() OR author_id = auth.uid());

-- Videos
DROP POLICY IF EXISTS "Admins can update videos" ON videos;
CREATE POLICY "Admins can update videos"
ON videos FOR UPDATE TO authenticated
USING (is_admin() OR author_id = auth.uid())
WITH CHECK (is_admin() OR author_id = auth.uid());

-- Notes
DROP POLICY IF EXISTS "Admins can update notes" ON notes;
CREATE POLICY "Admins can update notes"
ON notes FOR UPDATE TO authenticated
USING (is_admin() OR author_id = auth.uid())
WITH CHECK (is_admin() OR author_id = auth.uid());

-- Official magazines
DROP POLICY IF EXISTS "Admins can update official_magazines" ON official_magazines;
CREATE POLICY "Admins can update official_magazines"
ON official_magazines FOR UPDATE TO authenticated
USING (is_admin())
WITH CHECK (is_admin());

-- Events
DROP POLICY IF EXISTS "Admins can update events" ON events;
CREATE POLICY "Admins can update events"
ON events FOR UPDATE TO authenticated
USING (is_admin())
WITH CHECK (is_admin());

-- ═══════════════════════════════════════════════════════════════
-- DONE! Admin dashboard now has full control:
--   • Suspend / Restore students
--   • Change student roles
--   • Delete students (permanent)
--   • Approve / Reject posts
--   • Publish / Unpublish videos, notes, magazines
--   • All from the admin dashboard — no SQL needed!
-- ═══════════════════════════════════════════════════════════════
