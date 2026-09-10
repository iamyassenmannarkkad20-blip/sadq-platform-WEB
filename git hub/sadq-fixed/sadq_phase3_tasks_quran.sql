-- ════════════════════════════════════════════════════════════════════
-- SADQ — PHASE 3: TASK + QURAN + CAPACITY ECOSYSTEM
-- Run this in Supabase SQL Editor
-- Idempotent — safe to run multiple times
-- ════════════════════════════════════════════════════════════════════

-- ── ENUM TYPES ─────────────────────────────────────────────────────

DO $$ BEGIN
  CREATE TYPE task_status AS ENUM ('draft','published','assigned','in_progress','submitted','completed','approved','rejected','overdue','cancelled','archived');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE task_priority AS ENUM ('low','medium','high','urgent');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE juz_status AS ENUM ('not_started','in_progress','completed');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE service_availability AS ENUM ('open','limited','full','closed','expired','archived');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE recognition_type AS ENUM ('task_champion','top_performer','consistency_star','class_leader','quran_champion','perfect_completion','on_time_hero');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ════════════════════════════════════════════════════════════════════
-- 1. TEACHER CLASSES — which teacher manages which class
-- ════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS teacher_classes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  teacher_id UUID NOT NULL REFERENCES teachers(id) ON DELETE CASCADE,
  class_name TEXT NOT NULL,
  class_organisation TEXT,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(teacher_id, class_name)
);

ALTER TABLE teacher_classes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Teachers read own classes" ON teacher_classes;
CREATE POLICY "Teachers read own classes" ON teacher_classes
  FOR SELECT TO authenticated
  USING (
    teacher_id IN (SELECT id FROM teachers WHERE username = (
      SELECT username FROM profiles WHERE id = auth.uid()
    ))
    OR is_admin()
  );

DROP POLICY IF EXISTS "Admins manage teacher classes" ON teacher_classes;
CREATE POLICY "Admins manage teacher classes" ON teacher_classes
  FOR ALL TO authenticated
  USING (is_admin())
  WITH CHECK (is_admin());

-- ════════════════════════════════════════════════════════════════════
-- 2. CLASS MEMBERSHIPS — which students belong to which class
-- ════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS class_memberships (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  teacher_class_id UUID NOT NULL REFERENCES teacher_classes(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(student_id, teacher_class_id)
);

ALTER TABLE class_memberships ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Students read own class memberships" ON class_memberships;
CREATE POLICY "Students read own class memberships" ON class_memberships
  FOR SELECT TO authenticated
  USING (
    student_id = auth.uid()
    OR is_admin()
    OR teacher_class_id IN (
      SELECT id FROM teacher_classes WHERE teacher_id IN (
        SELECT id FROM teachers WHERE username = (SELECT username FROM profiles WHERE id = auth.uid())
      )
    )
  );

DROP POLICY IF EXISTS "Admins manage memberships" ON class_memberships;
CREATE POLICY "Admins manage memberships" ON class_memberships
  FOR ALL TO authenticated
  USING (is_admin())
  WITH CHECK (is_admin());

DROP POLICY IF EXISTS "Teachers manage own class memberships" ON class_memberships;
CREATE POLICY "Teachers manage own class memberships" ON class_memberships
  FOR INSERT TO authenticated
  WITH CHECK (
    teacher_class_id IN (
      SELECT id FROM teacher_classes WHERE teacher_id IN (
        SELECT id FROM teachers WHERE username = (SELECT username FROM profiles WHERE id = auth.uid())
      )
    )
  );

-- ════════════════════════════════════════════════════════════════════
-- 3. TASKS — main task table
-- ════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  description TEXT,
  category TEXT DEFAULT 'general',
  task_type TEXT DEFAULT 'assignment',
  priority task_priority DEFAULT 'medium',
  created_by UUID NOT NULL REFERENCES auth.users(id),
  creator_role TEXT DEFAULT 'admin',
  teacher_class_id UUID REFERENCES teacher_classes(id) ON DELETE SET NULL,
  teacher_id UUID REFERENCES teachers(id) ON DELETE SET NULL,
  start_date DATE,
  due_date DATE,
  points INTEGER DEFAULT 0,
  require_evidence BOOLEAN DEFAULT false,
  require_teacher_approval BOOLEAN DEFAULT true,
  status task_status DEFAULT 'draft',
  completion_percentage INTEGER DEFAULT 0,
  quran_linked BOOLEAN DEFAULT false,
  quran_juz_target INTEGER,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  completed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_tasks_created_by ON tasks(created_by);
CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
CREATE INDEX IF NOT EXISTS idx_tasks_teacher_class ON tasks(teacher_class_id);
CREATE INDEX IF NOT EXISTS idx_tasks_due_date ON tasks(due_date);

ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone authenticated can read tasks" ON tasks;
CREATE POLICY "Anyone authenticated can read tasks" ON tasks
  FOR SELECT TO authenticated
  USING (
    status IN ('published','assigned','in_progress','submitted','completed','approved','rejected','overdue')
    OR created_by = auth.uid()
    OR is_admin()
    OR teacher_class_id IN (
      SELECT id FROM teacher_classes WHERE teacher_id IN (
        SELECT id FROM teachers WHERE username = (SELECT username FROM profiles WHERE id = auth.uid())
      )
    )
  );

DROP POLICY IF EXISTS "Admins and teachers create tasks" ON tasks;
CREATE POLICY "Admins and teachers create tasks" ON tasks
  FOR INSERT TO authenticated
  WITH CHECK (
    is_admin()
    OR teacher_class_id IN (
      SELECT id FROM teacher_classes WHERE teacher_id IN (
        SELECT id FROM teachers WHERE username = (SELECT username FROM profiles WHERE id = auth.uid())
      )
    )
  );

DROP POLICY IF EXISTS "Creators and admins update tasks" ON tasks;
CREATE POLICY "Creators and admins update tasks" ON tasks
  FOR UPDATE TO authenticated
  USING (
    created_by = auth.uid() OR is_admin()
    OR teacher_class_id IN (
      SELECT id FROM teacher_classes WHERE teacher_id IN (
        SELECT id FROM teachers WHERE username = (SELECT username FROM profiles WHERE id = auth.uid())
      )
    )
  );

-- ════════════════════════════════════════════════════════════════════
-- 4. TASK ITEMS — checklist items within a task
-- ════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS task_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id UUID NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  label TEXT NOT NULL,
  sort_order INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_task_items_task ON task_items(task_id);

ALTER TABLE task_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Read task items" ON task_items;
CREATE POLICY "Read task items" ON task_items
  FOR SELECT TO authenticated
  USING (
    task_id IN (SELECT id FROM tasks)
  );

DROP POLICY IF EXISTS "Task creators manage items" ON task_items;
CREATE POLICY "Task creators manage items" ON task_items
  FOR ALL TO authenticated
  USING (
    task_id IN (SELECT id FROM tasks WHERE created_by = auth.uid() OR is_admin())
  )
  WITH CHECK (
    task_id IN (SELECT id FROM tasks WHERE created_by = auth.uid() OR is_admin())
  );

-- ════════════════════════════════════════════════════════════════════
-- 5. TASK ASSIGNMENTS — task assigned to students
-- ════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS task_assignments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id UUID NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  student_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  status task_status DEFAULT 'assigned',
  completion_percentage INTEGER DEFAULT 0,
  started_at TIMESTAMPTZ,
  submitted_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  approved_at TIMESTAMPTZ,
  approved_by UUID REFERENCES auth.users(id),
  rejection_reason TEXT,
  evidence_url TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(task_id, student_id)
);

CREATE INDEX IF NOT EXISTS idx_assignments_task ON task_assignments(task_id);
CREATE INDEX IF NOT EXISTS idx_assignments_student ON task_assignments(student_id);
CREATE INDEX IF NOT EXISTS idx_assignments_status ON task_assignments(status);

ALTER TABLE task_assignments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Students read own assignments" ON task_assignments;
CREATE POLICY "Students read own assignments" ON task_assignments
  FOR SELECT TO authenticated
  USING (
    student_id = auth.uid()
    OR is_admin()
    OR task_id IN (
      SELECT t.id FROM tasks t
      JOIN teacher_classes tc ON t.teacher_class_id = tc.id
      WHERE tc.teacher_id IN (
        SELECT id FROM teachers WHERE username = (SELECT username FROM profiles WHERE id = auth.uid())
      )
    )
  );

DROP POLICY IF EXISTS "Creators assign tasks" ON task_assignments;
CREATE POLICY "Creators assign tasks" ON task_assignments
  FOR INSERT TO authenticated
  WITH CHECK (
    task_id IN (SELECT id FROM tasks WHERE created_by = auth.uid() OR is_admin())
    OR is_admin()
  );

DROP POLICY IF EXISTS "Students update own assignments" ON task_assignments;
CREATE POLICY "Students update own assignments" ON task_assignments
  FOR UPDATE TO authenticated
  USING (
    student_id = auth.uid()
    OR is_admin()
    OR task_id IN (
      SELECT t.id FROM tasks t
      JOIN teacher_classes tc ON t.teacher_class_id = tc.id
      WHERE tc.teacher_id IN (
        SELECT id FROM teachers WHERE username = (SELECT username FROM profiles WHERE id = auth.uid())
      )
    )
  );

-- ════════════════════════════════════════════════════════════════════
-- 6. TASK COMPLETION ITEMS — checklist tick state per student
-- ════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS task_completion_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  assignment_id UUID NOT NULL REFERENCES task_assignments(id) ON DELETE CASCADE,
  task_item_id UUID NOT NULL REFERENCES task_items(id) ON DELETE CASCADE,
  is_completed BOOLEAN DEFAULT false,
  completed_at TIMESTAMPTZ,
  UNIQUE(assignment_id, task_item_id)
);

ALTER TABLE task_completion_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Read own completion items" ON task_completion_items;
CREATE POLICY "Read own completion items" ON task_completion_items
  FOR SELECT TO authenticated
  USING (
    assignment_id IN (
      SELECT id FROM task_assignments WHERE student_id = auth.uid() OR is_admin()
    )
  );

DROP POLICY IF EXISTS "Students toggle own completion items" ON task_completion_items;
CREATE POLICY "Students toggle own completion items" ON task_completion_items
  FOR ALL TO authenticated
  USING (
    assignment_id IN (
      SELECT id FROM task_assignments WHERE student_id = auth.uid() OR is_admin()
    )
  )
  WITH CHECK (
    assignment_id IN (
      SELECT id FROM task_assignments WHERE student_id = auth.uid() OR is_admin()
    )
  );

-- ════════════════════════════════════════════════════════════════════
-- 7. TASK REVIEWS — teacher review records
-- ════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS task_reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  assignment_id UUID NOT NULL REFERENCES task_assignments(id) ON DELETE CASCADE,
  reviewer_id UUID NOT NULL REFERENCES auth.users(id),
  action TEXT NOT NULL CHECK (action IN ('approve','reject','request_changes')),
  comment TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE task_reviews ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Read task reviews" ON task_reviews;
CREATE POLICY "Read task reviews" ON task_reviews
  FOR SELECT TO authenticated
  USING (
    assignment_id IN (
      SELECT id FROM task_assignments WHERE student_id = auth.uid() OR is_admin()
    )
  );

DROP POLICY IF EXISTS "Teachers and admins create reviews" ON task_reviews;
CREATE POLICY "Teachers and admins create reviews" ON task_reviews
  FOR INSERT TO authenticated
  WITH CHECK (
    is_admin()
    OR assignment_id IN (
      SELECT ta.id FROM task_assignments ta
      JOIN tasks t ON ta.task_id = t.id
      JOIN teacher_classes tc ON t.teacher_class_id = tc.id
      WHERE tc.teacher_id IN (
        SELECT id FROM teachers WHERE username = (SELECT username FROM profiles WHERE id = auth.uid())
      )
    )
  );

-- ════════════════════════════════════════════════════════════════════
-- 8. TASK RECOGNITIONS
-- ════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS task_recognitions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  recognition_type recognition_type NOT NULL,
  reason TEXT,
  metric TEXT,
  awarded_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE task_recognitions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Read recognitions" ON task_recognitions;
CREATE POLICY "Read recognitions" ON task_recognitions
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Admins and teachers award recognitions" ON task_recognitions;
CREATE POLICY "Admins and teachers award recognitions" ON task_recognitions
  FOR INSERT TO authenticated
  WITH CHECK (is_admin());

-- ════════════════════════════════════════════════════════════════════
-- 9. QURAN JUZ PROGRESS — track 30 Juz per student
-- ════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS quran_juz_progress (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  juz_number INTEGER NOT NULL CHECK (juz_number >= 1 AND juz_number <= 30),
  status juz_status DEFAULT 'not_started',
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  reading_notes TEXT,
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(student_id, juz_number)
);

CREATE INDEX IF NOT EXISTS idx_quran_student ON quran_juz_progress(student_id);
CREATE INDEX IF NOT EXISTS idx_quran_status ON quran_juz_progress(status);

ALTER TABLE quran_juz_progress ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Students read own Quran progress" ON quran_juz_progress;
CREATE POLICY "Students read own Quran progress" ON quran_juz_progress
  FOR SELECT TO authenticated
  USING (
    student_id = auth.uid()
    OR is_admin()
    OR student_id IN (
      SELECT cm.student_id FROM class_memberships cm
      JOIN teacher_classes tc ON cm.teacher_class_id = tc.id
      WHERE tc.teacher_id IN (
        SELECT id FROM teachers WHERE username = (SELECT username FROM profiles WHERE id = auth.uid())
      )
    )
  );

DROP POLICY IF EXISTS "Students update own Quran progress" ON quran_juz_progress;
CREATE POLICY "Students update own Quran progress" ON quran_juz_progress
  FOR ALL TO authenticated
  USING (student_id = auth.uid() OR is_admin())
  WITH CHECK (student_id = auth.uid() OR is_admin());

-- ════════════════════════════════════════════════════════════════════
-- 10. QURAN KHATM — completed full Quran records
-- ════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS quran_khatm (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  completed_at TIMESTAMPTZ DEFAULT now(),
  verification_status TEXT DEFAULT 'pending' CHECK (verification_status IN ('pending','verified','rejected')),
  verified_by UUID REFERENCES auth.users(id),
  verified_at TIMESTAMPTZ,
  notes TEXT
);

CREATE INDEX IF NOT EXISTS idx_khatm_student ON quran_khatm(student_id);

ALTER TABLE quran_khatm ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Read Quran Khatm records" ON quran_khatm;
CREATE POLICY "Read Quran Khatm records" ON quran_khatm
  FOR SELECT TO authenticated
  USING (
    student_id = auth.uid()
    OR is_admin()
    OR student_id IN (
      SELECT cm.student_id FROM class_memberships cm
      JOIN teacher_classes tc ON cm.teacher_class_id = tc.id
      WHERE tc.teacher_id IN (
        SELECT id FROM teachers WHERE username = (SELECT username FROM profiles WHERE id = auth.uid())
      )
    )
  );

DROP POLICY IF EXISTS "Students record own Khatm" ON quran_khatm;
CREATE POLICY "Students record own Khatm" ON quran_khatm
  FOR INSERT TO authenticated
  WITH CHECK (student_id = auth.uid() OR is_admin());

DROP POLICY IF EXISTS "Admins verify Khatm" ON quran_khatm;
CREATE POLICY "Admins verify Khatm" ON quran_khatm
  FOR UPDATE TO authenticated
  USING (is_admin());

-- ════════════════════════════════════════════════════════════════════
-- 11. QURAN GOALS
-- ════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS quran_goals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  description TEXT,
  goal_type TEXT DEFAULT 'juz_target',
  target_juz INTEGER,
  target_count INTEGER,
  teacher_class_id UUID REFERENCES teacher_classes(id) ON DELETE SET NULL,
  student_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
  start_date DATE,
  end_date DATE,
  is_active BOOLEAN DEFAULT true,
  linked_task_id UUID REFERENCES tasks(id) ON DELETE SET NULL,
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE quran_goals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Read Quran goals" ON quran_goals;
CREATE POLICY "Read Quran goals" ON quran_goals
  FOR SELECT TO authenticated
  USING (
    is_active = true OR created_by = auth.uid() OR is_admin()
    OR student_id = auth.uid()
    OR teacher_class_id IN (
      SELECT id FROM teacher_classes WHERE teacher_id IN (
        SELECT id FROM teachers WHERE username = (SELECT username FROM profiles WHERE id = auth.uid())
      )
    )
  );

DROP POLICY IF EXISTS "Admins and teachers create goals" ON quran_goals;
CREATE POLICY "Admins and teachers create goals" ON quran_goals
  FOR INSERT TO authenticated
  WITH CHECK (is_admin() OR created_by = auth.uid());

DROP POLICY IF EXISTS "Creators update goals" ON quran_goals;
CREATE POLICY "Creators update goals" ON quran_goals
  FOR UPDATE TO authenticated
  USING (created_by = auth.uid() OR is_admin());

-- ════════════════════════════════════════════════════════════════════
-- 12. CAPACITY: Add columns to existing services table
-- ════════════════════════════════════════════════════════════════════

ALTER TABLE services ADD COLUMN IF NOT EXISTS max_applications INTEGER DEFAULT 0;
ALTER TABLE services ADD COLUMN IF NOT EXISTS current_applications INTEGER DEFAULT 0;
ALTER TABLE services ADD COLUMN IF NOT EXISTS availability_status service_availability DEFAULT 'open';
ALTER TABLE services ADD COLUMN IF NOT EXISTS max_active_orders INTEGER DEFAULT 0;

-- ════════════════════════════════════════════════════════════════════
-- 13. CAPACITY: Add columns to existing jobs table
-- ════════════════════════════════════════════════════════════════════

ALTER TABLE jobs ADD COLUMN IF NOT EXISTS max_applications INTEGER DEFAULT 0;
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS current_applications INTEGER DEFAULT 0;
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS availability_status service_availability DEFAULT 'open';
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS application_deadline TIMESTAMPTZ;

-- ════════════════════════════════════════════════════════════════════
-- 14. CAPACITY: Add columns to existing marketplace products
-- ════════════════════════════════════════════════════════════════════

-- Note: marketplace products may be in a table called 'products' or 'marketplace_items'
-- We try both
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'products' AND table_schema = 'public') THEN
    ALTER TABLE products ADD COLUMN IF NOT EXISTS stock_quantity INTEGER DEFAULT 0;
    ALTER TABLE products ADD COLUMN IF NOT EXISTS reserved_quantity INTEGER DEFAULT 0;
    ALTER TABLE products ADD COLUMN IF NOT EXISTS sold_quantity INTEGER DEFAULT 0;
    ALTER TABLE products ADD COLUMN IF NOT EXISTS availability_status service_availability DEFAULT 'open';
  END IF;
  
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'marketplace_items' AND table_schema = 'public') THEN
    ALTER TABLE marketplace_items ADD COLUMN IF NOT EXISTS stock_quantity INTEGER DEFAULT 0;
    ALTER TABLE marketplace_items ADD COLUMN IF NOT EXISTS reserved_quantity INTEGER DEFAULT 0;
    ALTER TABLE marketplace_items ADD COLUMN IF NOT EXISTS sold_quantity INTEGER DEFAULT 0;
    ALTER TABLE marketplace_items ADD COLUMN IF NOT EXISTS availability_status service_availability DEFAULT 'open';
  END IF;
END $$;

-- ════════════════════════════════════════════════════════════════════
-- 15. RPC: ASSIGN TASK — assign a task to students
-- ════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION assign_task(p_task_id uuid, p_student_ids uuid[])
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  caller_role text;
  task_rec RECORD;
  inserted_count integer := 0;
  student_id uuid;
BEGIN
  SELECT role::text INTO caller_role FROM profiles WHERE id = auth.uid();
  IF caller_role IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  SELECT * INTO task_rec FROM tasks WHERE id = p_task_id;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Task not found');
  END IF;

  -- Only creator or admin can assign
  IF task_rec.created_by != auth.uid() AND caller_role NOT IN ('admin', 'super_admin') THEN
    RETURN json_build_object('success', false, 'error', 'Not authorized to assign this task');
  END IF;

  FOREACH student_id IN ARRAY p_student_ids LOOP
    INSERT INTO task_assignments (task_id, student_id, status)
    VALUES (p_task_id, student_id, 'assigned')
    ON CONFLICT (task_id, student_id) DO NOTHING;
    inserted_count := inserted_count + 1;
  END LOOP;

  -- Update task status
  UPDATE tasks SET status = 'assigned', updated_at = now() WHERE id = p_task_id AND status = 'published';

  RETURN json_build_object('success', true, 'assigned_count', inserted_count);
END;
$$;

-- ════════════════════════════════════════════════════════════════════
-- 16. RPC: SUBMIT TASK — student submits task for review
-- ════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION submit_task(p_assignment_id uuid, p_evidence_url text DEFAULT NULL)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  assignment_rec RECORD;
BEGIN
  SELECT * INTO assignment_rec FROM task_assignments WHERE id = p_assignment_id;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Assignment not found');
  END IF;

  IF assignment_rec.student_id != auth.uid() THEN
    RETURN json_build_object('success', false, 'error', 'Not your assignment');
  END IF;

  UPDATE task_assignments
  SET status = 'submitted',
      submitted_at = now(),
      evidence_url = COALESCE(p_evidence_url, evidence_url),
      updated_at = now()
  WHERE id = p_assignment_id;

  RETURN json_build_object('success', true, 'message', 'Task submitted for review');
END;
$$;

-- ════════════════════════════════════════════════════════════════════
-- 17. RPC: REVIEW TASK — teacher/admin approves or rejects
-- ════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION review_task(p_assignment_id uuid, p_action text, p_comment text DEFAULT NULL)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  caller_role text;
  assignment_rec RECORD;
  new_status task_status;
BEGIN
  SELECT role::text INTO caller_role FROM profiles WHERE id = auth.uid();
  IF caller_role IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  IF caller_role NOT IN ('admin', 'super_admin') AND p_action NOT IN ('approve', 'reject') THEN
    -- Teachers can also review if they own the class
    SELECT ta.* INTO assignment_rec FROM task_assignments ta WHERE ta.id = p_assignment_id;
    IF NOT FOUND THEN
      RETURN json_build_object('success', false, 'error', 'Assignment not found');
    END IF;
    -- Check teacher authorization
    SELECT t.id INTO assignment_rec FROM tasks t
    JOIN teacher_classes tc ON t.teacher_class_id = tc.id
    WHERE t.id = assignment_rec.task_id AND tc.teacher_id IN (
      SELECT id FROM teachers WHERE username = (SELECT username FROM profiles WHERE id = auth.uid())
    );
    IF NOT FOUND AND caller_role NOT IN ('admin', 'super_admin') THEN
      RETURN json_build_object('success', false, 'error', 'Not authorized to review');
    END IF;
  END IF;

  IF p_action = 'approve' THEN
    new_status := 'approved';
  ELSIF p_action = 'reject' THEN
    new_status := 'rejected';
  ELSE
    RETURN json_build_object('success', false, 'error', 'Invalid action');
  END IF;

  UPDATE task_assignments
  SET status = new_status,
      approved_at = CASE WHEN p_action = 'approve' THEN now() ELSE approved_at END,
      approved_by = CASE WHEN p_action = 'approve' THEN auth.uid() ELSE approved_by END,
      rejection_reason = CASE WHEN p_action = 'reject' THEN p_comment ELSE NULL END,
      updated_at = now()
  WHERE id = p_assignment_id;

  INSERT INTO task_reviews (assignment_id, reviewer_id, action, comment)
  VALUES (p_assignment_id, auth.uid(), p_action, p_comment);

  RETURN json_build_object('success', true, 'message',
    CASE WHEN p_action = 'approve' THEN 'Task approved' ELSE 'Task rejected' END);
END;
$$;

-- ════════════════════════════════════════════════════════════════════
-- 18. RPC: UPDATE QURAN PROGRESS
-- ════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION update_quran_progress(p_juz_number integer, p_status text, p_notes text DEFAULT NULL)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_student_id uuid := auth.uid();
  v_existing RECORD;
BEGIN
  IF v_student_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  IF p_juz_number < 1 OR p_juz_number > 30 THEN
    RETURN json_build_object('success', false, 'error', 'Juz number must be 1-30');
  END IF;

  IF p_status NOT IN ('not_started', 'in_progress', 'completed') THEN
    RETURN json_build_object('success', false, 'error', 'Invalid status');
  END IF;

  SELECT * INTO v_existing FROM quran_juz_progress qjp WHERE qjp.student_id = v_student_id AND qjp.juz_number = p_juz_number;

  IF FOUND THEN
    UPDATE quran_juz_progress
    SET status = p_status::juz_status,
        reading_notes = COALESCE(p_notes, reading_notes),
        started_at = CASE WHEN p_status = 'in_progress' AND v_existing.status = 'not_started' THEN now() ELSE started_at END,
        completed_at = CASE WHEN p_status = 'completed' THEN now() ELSE completed_at END,
        updated_at = now()
    WHERE student_id = v_student_id AND juz_number = p_juz_number;
  ELSE
    INSERT INTO quran_juz_progress (student_id, juz_number, status, reading_notes, started_at, completed_at)
    VALUES (v_student_id, p_juz_number, p_status::juz_status, p_notes,
      CASE WHEN p_status = 'in_progress' THEN now() ELSE NULL END,
      CASE WHEN p_status = 'completed' THEN now() ELSE NULL END
    );
  END IF;

  -- Check if all 30 Juz completed → auto-record Khatm
  IF p_status = 'completed' THEN
    PERFORM 1 FROM quran_juz_progress
    WHERE quran_juz_progress.student_id = v_student_id AND quran_juz_progress.status = 'completed'
    GROUP BY student_id
    HAVING COUNT(*) = 30;

    IF FOUND THEN
      INSERT INTO quran_khatm (student_id, completed_at, verification_status)
      VALUES (v_student_id, now(), 'pending')
      ON CONFLICT DO NOTHING;
    END IF;
  END IF;

  RETURN json_build_object('success', true, 'message', 'Quran progress updated');
END;
$$;

-- ════════════════════════════════════════════════════════════════════
-- 19. RPC: GET STUDENT QURAN STATS
-- ════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION get_quran_stats(p_student_id uuid DEFAULT NULL)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  target_id uuid := COALESCE(p_student_id, auth.uid());
  completed_juz integer;
  in_progress_juz integer;
  khatm_count integer;
  progress_pct numeric;
BEGIN
  SELECT COUNT(*) INTO completed_juz FROM quran_juz_progress WHERE student_id = target_id AND status = 'completed';
  SELECT COUNT(*) INTO in_progress_juz FROM quran_juz_progress WHERE student_id = target_id AND status = 'in_progress';
  SELECT COUNT(*) INTO khatm_count FROM quran_khatm WHERE student_id = target_id AND verification_status != 'rejected';

  progress_pct := ROUND((completed_juz::numeric / 30) * 100, 1);

  RETURN json_build_object(
    'completed_juz', completed_juz,
    'in_progress_juz', in_progress_juz,
    'not_started_juz', 30 - completed_juz - in_progress_juz,
    'progress_percentage', progress_pct,
    'khatm_count', khatm_count,
    'total_juz', 30
  );
END;
$$;

-- ════════════════════════════════════════════════════════════════════
-- 20. RPC: GET STUDENT TASK STATS
-- ════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION get_task_stats(p_student_id uuid DEFAULT NULL)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  target_id uuid := COALESCE(p_student_id, auth.uid());
  total_tasks integer;
  completed_tasks integer;
  in_progress_tasks integer;
  pending_tasks integer;
  overdue_tasks integer;
  total_points integer;
BEGIN
  SELECT COUNT(*) INTO total_tasks FROM task_assignments WHERE student_id = target_id;
  SELECT COUNT(*) INTO completed_tasks FROM task_assignments WHERE student_id = target_id AND status IN ('completed', 'approved');
  SELECT COUNT(*) INTO in_progress_tasks FROM task_assignments WHERE student_id = target_id AND status = 'in_progress';
  SELECT COUNT(*) INTO pending_tasks FROM task_assignments WHERE student_id = target_id AND status IN ('assigned', 'submitted');
  SELECT COUNT(*) INTO overdue_tasks FROM task_assignments WHERE student_id = target_id AND status = 'overdue';

  SELECT COALESCE(SUM(t.points), 0) INTO total_points
  FROM task_assignments ta JOIN tasks t ON ta.task_id = t.id
  WHERE ta.student_id = target_id AND ta.status IN ('completed', 'approved');

  RETURN json_build_object(
    'total_tasks', total_tasks,
    'completed_tasks', completed_tasks,
    'in_progress_tasks', in_progress_tasks,
    'pending_tasks', pending_tasks,
    'overdue_tasks', overdue_tasks,
    'total_points', total_points
  );
END;
$$;

-- ════════════════════════════════════════════════════════════════════
-- 21. RPC: CALCULATE COMPLETION PERCENTAGE
-- ════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION calculate_completion(p_assignment_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  total_items integer;
  completed_items integer;
  pct integer;
BEGIN
  SELECT COUNT(*) INTO total_items FROM task_items WHERE task_id = (SELECT task_id FROM task_assignments WHERE id = p_assignment_id);
  IF total_items = 0 THEN
    SELECT CASE WHEN status IN ('completed', 'approved') THEN 100 ELSE 0 END INTO pct FROM task_assignments WHERE id = p_assignment_id;
    RETURN COALESCE(pct, 0);
  END IF;

  SELECT COUNT(*) INTO completed_items FROM task_completion_items WHERE assignment_id = p_assignment_id AND is_completed = true;
  pct := ROUND((completed_items::numeric / total_items) * 100);
  RETURN pct;
END;
$$;

-- ════════════════════════════════════════════════════════════════════
-- 22. RPC: CLOSE SERVICE — admin/owner closes a service
-- ════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION close_service(p_service_id uuid, p_reason text DEFAULT NULL)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  caller_role text;
BEGIN
  SELECT role::text INTO caller_role FROM profiles WHERE id = auth.uid();
  IF caller_role IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  UPDATE services
  SET availability_status = 'closed'
  WHERE id = p_service_id;

  RETURN json_build_object('success', true, 'message', 'Service closed');
END;
$$;

-- ════════════════════════════════════════════════════════════════════
-- 23. GRANT EXECUTE
-- ════════════════════════════════════════════════════════════════════

GRANT EXECUTE ON FUNCTION assign_task(uuid, uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION submit_task(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION review_task(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION update_quran_progress(integer, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION get_quran_stats(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION get_task_stats(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION calculate_completion(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION close_service(uuid, text) TO authenticated;

-- ════════════════════════════════════════════════════════════════════
-- 24. AUTO-UPDATE OVERDUE STATUS — trigger function
-- ════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION update_overdue_assignments()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE task_assignments
  SET status = 'overdue'
  WHERE status IN ('assigned', 'in_progress')
    AND task_id IN (SELECT id FROM tasks WHERE due_date < CURRENT_DATE AND due_date IS NOT NULL);
END;
$$;

GRANT EXECUTE ON FUNCTION update_overdue_assignments() TO authenticated;

-- ════════════════════════════════════════════════════════════════════
-- DONE — Phase 3 Migration Complete
-- ════════════════════════════════════════════════════════════════════
-- Tables created:
--   teacher_classes, class_memberships
--   tasks, task_items, task_assignments, task_completion_items
--   task_reviews, task_recognitions
--   quran_juz_progress, quran_khatm, quran_goals
--
-- Capacity columns added to: services, jobs, products/marketplace_items
--
-- RPCs created:
--   assign_task, submit_task, review_task
--   update_quran_progress, get_quran_stats, get_task_stats
--   calculate_completion, close_service, update_overdue_assignments
--
-- RLS policies enforced for:
--   Students: own data only
--   Teachers: authorized classes only
--   Admins: global access
-- ════════════════════════════════════════════════════════════════════
