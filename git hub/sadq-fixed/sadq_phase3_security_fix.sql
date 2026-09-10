-- ════════════════════════════════════════════════════════════════════
-- SADQ — PHASE 3 SECURITY FIX PATCH
-- Run AFTER sadq_phase3_tasks_quran.sql
-- Fixes: review_task, assign_task, close_service, get_quran_stats,
--        get_task_stats, Quran naming, Khatm uniqueness, capacity enforcement
-- ════════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════════
-- FIX 1: review_task — proper teacher authorization
-- ════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS review_task(uuid, text, text);

CREATE OR REPLACE FUNCTION review_task(p_assignment_id uuid, p_action text, p_comment text DEFAULT NULL)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
  v_caller_role text;
  v_assignment RECORD;
  v_task RECORD;
  v_teacher_id uuid;
  v_new_status task_status;
BEGIN
  -- 1. Must be authenticated
  IF v_caller_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  -- 2. Get caller role
  SELECT role::text INTO v_caller_role FROM profiles WHERE id = v_caller_id;
  IF v_caller_role IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Profile not found');
  END IF;

  -- 3. Students cannot review
  IF v_caller_role = 'student' THEN
    RETURN json_build_object('success', false, 'error', 'Students cannot review tasks');
  END IF;

  -- 4. Load assignment + task in a single query (no overwrite bug)
  SELECT ta.*, t.id AS task_id, t.teacher_class_id, t.created_by AS task_created_by
  INTO v_assignment
  FROM task_assignments ta
  JOIN tasks t ON ta.task_id = t.id
  WHERE ta.id = p_assignment_id;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Assignment not found');
  END IF;

  -- 5. Admin/super_admin can review anything
  IF v_caller_role NOT IN ('admin', 'super_admin') THEN
    -- 6. Teacher authorization: must own the teacher_class linked to the task
    IF v_assignment.teacher_class_id IS NULL THEN
      RETURN json_build_object('success', false, 'error', 'This task has no class assignment — only admins can review');
    END IF;

    SELECT tc.teacher_id INTO v_teacher_id
    FROM teacher_classes tc
    WHERE tc.id = v_assignment.teacher_class_id
      AND tc.teacher_id IN (
        SELECT tch.id FROM teachers tch
        WHERE tch.username = (SELECT username FROM profiles WHERE id = v_caller_id)
      );

    IF v_teacher_id IS NULL THEN
      RETURN json_build_object('success', false, 'error', 'You are not authorized to review this class');
    END IF;
  END IF;

  -- 7. Validate action
  IF p_action = 'approve' THEN
    v_new_status := 'approved';
  ELSIF p_action = 'reject' THEN
    v_new_status := 'rejected';
  ELSIF p_action = 'request_changes' THEN
    v_new_status := 'in_progress';
  ELSE
    RETURN json_build_object('success', false, 'error', 'Invalid action — use approve, reject, or request_changes');
  END IF;

  -- 8. Update assignment
  UPDATE task_assignments
  SET status = v_new_status,
      approved_at = CASE WHEN p_action = 'approve' THEN now() ELSE approved_at END,
      approved_by = CASE WHEN p_action = 'approve' THEN v_caller_id ELSE approved_by END,
      rejection_reason = CASE WHEN p_action = 'reject' THEN p_comment ELSE NULL END,
      updated_at = now()
  WHERE id = p_assignment_id;

  -- 9. Log the review
  INSERT INTO task_reviews (assignment_id, reviewer_id, action, comment)
  VALUES (p_assignment_id, v_caller_id, p_action, p_comment);

  RETURN json_build_object('success', true, 'message',
    CASE WHEN p_action = 'approve' THEN 'Task approved'
         WHEN p_action = 'reject' THEN 'Task rejected'
         ELSE 'Changes requested' END);
END;
$$;

-- ════════════════════════════════════════════════════════════════════
-- FIX 2: assign_task — restrict to authorized teacher_classes
-- ════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS assign_task(uuid, uuid[]);

CREATE OR REPLACE FUNCTION assign_task(p_task_id uuid, p_student_ids uuid[])
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
  v_caller_role text;
  v_task RECORD;
  v_authorized_count integer;
  v_inserted_count integer := 0;
  v_student_id uuid;
BEGIN
  -- 1. Must be authenticated
  IF v_caller_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  -- 2. Get caller role
  SELECT role::text INTO v_caller_role FROM profiles WHERE id = v_caller_id;
  IF v_caller_role IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Profile not found');
  END IF;

  -- 3. Load task
  SELECT * INTO v_task FROM tasks WHERE id = p_task_id;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Task not found');
  END IF;

  -- 4. Authorization: admin/super_admin OR teacher who owns the task's class
  IF v_caller_role NOT IN ('admin', 'super_admin') THEN
    -- Teacher: must own the teacher_class_id linked to the task
    IF v_task.teacher_class_id IS NULL THEN
      RETURN json_build_object('success', false, 'error', 'This task has no class — only admins can assign');
    END IF;

    SELECT count(*) INTO v_authorized_count
    FROM teacher_classes tc
    WHERE tc.id = v_task.teacher_class_id
      AND tc.teacher_id IN (
        SELECT tch.id FROM teachers tch
        WHERE tch.username = (SELECT username FROM profiles WHERE id = v_caller_id)
      );

    IF v_authorized_count = 0 THEN
      RETURN json_build_object('success', false, 'error', 'Not authorized to assign tasks for this class');
    END IF;
  END IF;

  -- 5. Assign to each student — verify they belong to the task's class (if class-linked)
  FOREACH v_student_id IN ARRAY p_student_ids LOOP
    -- If task has a class, verify student is in that class
    IF v_task.teacher_class_id IS NOT NULL THEN
      SELECT count(*) INTO v_authorized_count
      FROM class_memberships cm
      WHERE cm.teacher_class_id = v_task.teacher_class_id
        AND cm.student_id = v_student_id;

      IF v_authorized_count = 0 THEN
        -- Skip students not in the class — no cross-class assignment
        CONTINUE;
      END IF;
    END IF;

    INSERT INTO task_assignments (task_id, student_id, status)
    VALUES (p_task_id, v_student_id, 'assigned')
    ON CONFLICT (task_id, student_id) DO NOTHING;

    v_inserted_count := v_inserted_count + 1;
  END LOOP;

  -- 6. Update task status
  UPDATE tasks SET status = 'assigned', updated_at = now()
  WHERE id = p_task_id AND status IN ('published', 'draft');

  RETURN json_build_object('success', true, 'assigned_count', v_inserted_count);
END;
$$;

-- ════════════════════════════════════════════════════════════════════
-- FIX 3: close_service — owner/admin only
-- ════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS close_service(uuid, text);

CREATE OR REPLACE FUNCTION close_service(p_service_id uuid, p_reason text DEFAULT NULL)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
  v_caller_role text;
  v_service RECORD;
BEGIN
  IF v_caller_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  SELECT role::text INTO v_caller_role FROM profiles WHERE id = v_caller_id;
  IF v_caller_role IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Profile not found');
  END IF;

  -- Load service to check ownership
  SELECT * INTO v_service FROM services WHERE id = p_service_id;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Service not found');
  END IF;

  -- Authorization: admin/super_admin OR service owner (seller_id)
  IF v_caller_role NOT IN ('admin', 'super_admin') THEN
    IF v_service.seller_id IS NULL OR v_service.seller_id != v_caller_id THEN
      RETURN json_build_object('success', false, 'error', 'NOT AUTHORIZED — only the service owner or admin can close this service');
    END IF;
  END IF;

  -- Close the service
  UPDATE services
  SET availability_status = 'closed'
  WHERE id = p_service_id;

  RETURN json_build_object('success', true, 'message', 'Service closed');
END;
$$;

-- ════════════════════════════════════════════════════════════════════
-- FIX 4: get_quran_stats — authorization: own data or authorized teacher
-- ════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS get_quran_stats(uuid);

CREATE OR REPLACE FUNCTION get_quran_stats(p_student_id uuid DEFAULT NULL)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
  v_caller_role text;
  v_target_id uuid;
  v_completed_juz integer;
  v_in_progress_juz integer;
  v_khatm_count integer;
  v_progress_pct numeric;
BEGIN
  IF v_caller_id IS NULL THEN
    RETURN json_build_object('error', 'Not authenticated');
  END IF;

  SELECT role::text INTO v_caller_role FROM profiles WHERE id = v_caller_id;

  -- Default: own data
  v_target_id := COALESCE(p_student_id, v_caller_id);

  -- If requesting someone else's data, verify authorization
  IF p_student_id IS NOT NULL AND p_student_id != v_caller_id THEN
    IF v_caller_role = 'student' THEN
      RETURN json_build_object('error', 'Not authorized to view other students data');
    ELSIF v_caller_role IN ('admin', 'super_admin') THEN
      -- Admins can access anyone
      v_target_id := p_student_id;
    ELSE
      -- Teachers: only students in their authorized classes
      PERFORM 1
      FROM class_memberships cm
      JOIN teacher_classes tc ON cm.teacher_class_id = tc.id
      WHERE cm.student_id = p_student_id
        AND tc.teacher_id IN (
          SELECT tch.id FROM teachers tch
          WHERE tch.username = (SELECT username FROM profiles WHERE id = v_caller_id)
        );
      IF NOT FOUND THEN
        RETURN json_build_object('error', 'Not authorized — student is not in your class');
      END IF;
      v_target_id := p_student_id;
    END IF;
  END IF;

  -- Query using explicit table alias (no variable/column ambiguity)
  SELECT count(*) INTO v_completed_juz
  FROM quran_juz_progress qjp
  WHERE qjp.student_id = v_target_id AND qjp.status = 'completed';

  SELECT count(*) INTO v_in_progress_juz
  FROM quran_juz_progress qjp
  WHERE qjp.student_id = v_target_id AND qjp.status = 'in_progress';

  SELECT count(*) INTO v_khatm_count
  FROM quran_khatm qk
  WHERE qk.student_id = v_target_id AND qk.verification_status != 'rejected';

  v_progress_pct := ROUND((v_completed_juz::numeric / 30) * 100, 1);

  RETURN json_build_object(
    'completed_juz', v_completed_juz,
    'in_progress_juz', v_in_progress_juz,
    'not_started_juz', 30 - v_completed_juz - v_in_progress_juz,
    'progress_percentage', v_progress_pct,
    'khatm_count', v_khatm_count,
    'total_juz', 30
  );
END;
$$;

-- ════════════════════════════════════════════════════════════════════
-- FIX 5: get_task_stats — same authorization rules
-- ════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS get_task_stats(uuid);

CREATE OR REPLACE FUNCTION get_task_stats(p_student_id uuid DEFAULT NULL)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
  v_caller_role text;
  v_target_id uuid;
  v_total integer;
  v_completed integer;
  v_progress integer;
  v_pending integer;
  v_overdue integer;
  v_points integer;
BEGIN
  IF v_caller_id IS NULL THEN
    RETURN json_build_object('error', 'Not authenticated');
  END IF;

  SELECT role::text INTO v_caller_role FROM profiles WHERE id = v_caller_id;

  v_target_id := COALESCE(p_student_id, v_caller_id);

  IF p_student_id IS NOT NULL AND p_student_id != v_caller_id THEN
    IF v_caller_role = 'student' THEN
      RETURN json_build_object('error', 'Not authorized');
    ELSIF v_caller_role NOT IN ('admin', 'super_admin') THEN
      -- Teacher: check student is in authorized class
      PERFORM 1
      FROM class_memberships cm
      JOIN teacher_classes tc ON cm.teacher_class_id = tc.id
      WHERE cm.student_id = p_student_id
        AND tc.teacher_id IN (
          SELECT tch.id FROM teachers tch
          WHERE tch.username = (SELECT username FROM profiles WHERE id = v_caller_id)
        );
      IF NOT FOUND THEN
        RETURN json_build_object('error', 'Not authorized — student not in your class');
      END IF;
    END IF;
    v_target_id := p_student_id;
  END IF;

  SELECT count(*) INTO v_total FROM task_assignments ta WHERE ta.student_id = v_target_id;
  SELECT count(*) INTO v_completed FROM task_assignments ta WHERE ta.student_id = v_target_id AND ta.status IN ('completed','approved');
  SELECT count(*) INTO v_progress FROM task_assignments ta WHERE ta.student_id = v_target_id AND ta.status = 'in_progress';
  SELECT count(*) INTO v_pending FROM task_assignments ta WHERE ta.student_id = v_target_id AND ta.status IN ('assigned','submitted');
  SELECT count(*) INTO v_overdue FROM task_assignments ta WHERE ta.student_id = v_target_id AND ta.status = 'overdue';

  SELECT COALESCE(SUM(t.points), 0) INTO v_points
  FROM task_assignments ta JOIN tasks t ON ta.task_id = t.id
  WHERE ta.student_id = v_target_id AND ta.status IN ('completed','approved');

  RETURN json_build_object(
    'total_tasks', v_total,
    'completed_tasks', v_completed,
    'in_progress_tasks', v_progress,
    'pending_tasks', v_pending,
    'overdue_tasks', v_overdue,
    'total_points', v_points
  );
END;
$$;

-- ════════════════════════════════════════════════════════════════════
-- FIX 6: update_quran_progress — fix variable naming ambiguity
-- ════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS update_quran_progress(integer, text, text);

CREATE OR REPLACE FUNCTION update_quran_progress(p_juz_number integer, p_status text, p_notes text DEFAULT NULL)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_student_id uuid := auth.uid();
  v_existing RECORD;
  v_completed_count integer;
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

  -- Use explicit alias qjp — no variable/column ambiguity
  SELECT * INTO v_existing
  FROM quran_juz_progress qjp
  WHERE qjp.student_id = v_student_id AND qjp.juz_number = p_juz_number;

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

  -- Check Khatm with explicit count using v_ prefix
  IF p_status = 'completed' THEN
    SELECT count(*) INTO v_completed_count
    FROM quran_juz_progress qjp
    WHERE qjp.student_id = v_student_id AND qjp.status = 'completed';

    IF v_completed_count = 30 THEN
      -- Use unique constraint to prevent duplicates
      INSERT INTO quran_khatm (student_id, completed_at, verification_status)
      VALUES (v_student_id, now(), 'pending')
      ON CONFLICT DO NOTHING;
    END IF;
  END IF;

  RETURN json_build_object('success', true, 'message', 'Quran progress updated');
END;
$$;

-- ════════════════════════════════════════════════════════════════════
-- FIX 7: Khatm uniqueness — add partial unique index
-- ════════════════════════════════════════════════════════════════════

-- Prevent duplicate pending Khatm per student (only one pending at a time)
CREATE UNIQUE INDEX IF NOT EXISTS idx_quran_khatm_one_pending
  ON quran_khatm (student_id)
  WHERE verification_status = 'pending';

-- ════════════════════════════════════════════════════════════════════
-- FIX 8: Capacity enforcement RPCs
-- ════════════════════════════════════════════════════════════════════

-- Apply to service — checks capacity before accepting application
CREATE OR REPLACE FUNCTION apply_to_service(p_service_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
  v_service RECORD;
  v_current integer;
BEGIN
  IF v_caller_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  SELECT * INTO v_service FROM services WHERE id = p_service_id;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Service not found');
  END IF;

  -- Check if closed
  IF v_service.availability_status = 'closed' THEN
    RETURN json_build_object('success', false, 'error', 'APPLICATIONS CLOSED — this service is no longer accepting applications');
  END IF;

  -- Check capacity
  IF v_service.max_applications > 0 THEN
    v_current := COALESCE(v_service.current_applications, 0);
    IF v_current >= v_service.max_applications THEN
      -- Auto-close when full
      UPDATE services SET availability_status = 'full' WHERE id = p_service_id;
      RETURN json_build_object('success', false, 'error', 'CAPACITY REACHED — this service is full');
    END IF;
  END IF;

  -- Increment counter
  UPDATE services SET current_applications = COALESCE(current_applications, 0) + 1 WHERE id = p_service_id;

  -- Check if now full
  IF v_service.max_applications > 0 AND COALESCE(v_service.current_applications, 0) + 1 >= v_service.max_applications THEN
    UPDATE services SET availability_status = 'full' WHERE id = p_service_id;
  END IF;

  RETURN json_build_object('success', true, 'message', 'Application submitted');
END;
$$;

-- Apply to job — checks capacity + deadline
CREATE OR REPLACE FUNCTION apply_to_job(p_job_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
  v_job RECORD;
  v_current integer;
BEGIN
  IF v_caller_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  SELECT * INTO v_job FROM jobs WHERE id = p_job_id;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Job not found');
  END IF;

  -- Check if closed
  IF v_job.availability_status = 'closed' THEN
    RETURN json_build_object('success', false, 'error', 'APPLICATIONS CLOSED — this job is no longer accepting applications');
  END IF;

  -- Check deadline
  IF v_job.application_deadline IS NOT NULL AND now() > v_job.application_deadline THEN
    UPDATE jobs SET availability_status = 'expired' WHERE id = p_job_id;
    RETURN json_build_object('success', false, 'error', 'DEADLINE PASSED — applications closed');
  END IF;

  -- Check capacity
  IF v_job.max_applications > 0 THEN
    v_current := COALESCE(v_job.current_applications, 0);
    IF v_current >= v_job.max_applications THEN
      UPDATE jobs SET availability_status = 'closed' WHERE id = p_job_id;
      RETURN json_build_object('success', false, 'error', 'CAPACITY REACHED — this job is full');
    END IF;
  END IF;

  -- Increment counter
  UPDATE jobs SET current_applications = COALESCE(current_applications, 0) + 1 WHERE id = p_job_id;

  RETURN json_build_object('success', true, 'message', 'Application submitted');
END;
$$;

-- Purchase product — checks stock
CREATE OR REPLACE FUNCTION purchase_product(p_product_id uuid, p_quantity integer DEFAULT 1)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
  v_product RECORD;
  v_available integer;
BEGIN
  IF v_caller_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  -- Try products table first
  SELECT * INTO v_product FROM products WHERE id = p_product_id;
  IF NOT FOUND THEN
    -- Try marketplace_items
    SELECT * INTO v_product FROM marketplace_items WHERE id = p_product_id;
  END IF;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Product not found');
  END IF;

  -- Check if closed/archived
  IF v_product.availability_status IN ('closed', 'archived') THEN
    RETURN json_build_object('success', false, 'error', 'This product is no longer available');
  END IF;

  -- Check stock
  v_available := COALESCE(v_product.stock_quantity, 0) - COALESCE(v_product.reserved_quantity, 0) - COALESCE(v_product.sold_quantity, 0);

  IF v_available < p_quantity THEN
    IF v_available <= 0 THEN
      -- Mark out of stock
      UPDATE products SET availability_status = 'out_of_stock' WHERE id = p_product_id;
      RETURN json_build_object('success', false, 'error', 'OUT OF STOCK — this product is no longer available');
    ELSE
      RETURN json_build_object('success', false, 'error', 'Insufficient stock — only ' || v_available || ' remaining');
    END IF;
  END IF;

  -- Reserve the quantity
  UPDATE products
  SET reserved_quantity = COALESCE(reserved_quantity, 0) + p_quantity,
      availability_status = CASE
        WHEN COALESCE(stock_quantity, 0) - COALESCE(reserved_quantity, 0) - p_quantity - COALESCE(sold_quantity, 0) <= 0 THEN 'out_of_stock'
        WHEN COALESCE(stock_quantity, 0) - COALESCE(reserved_quantity, 0) - p_quantity - COALESCE(sold_quantity, 0) <= 5 THEN 'low_stock'
        ELSE availability_status
      END
  WHERE id = p_product_id;

  RETURN json_build_object('success', true, 'message', 'Order placed', 'quantity', p_quantity);
END;
$$;

-- ════════════════════════════════════════════════════════════════════
-- FIX 9: GRANT EXECUTE on all fixed/new RPCs
-- ════════════════════════════════════════════════════════════════════

GRANT EXECUTE ON FUNCTION review_task(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION assign_task(uuid, uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION close_service(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION get_quran_stats(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION get_task_stats(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION update_quran_progress(integer, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION apply_to_service(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION apply_to_job(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION purchase_product(uuid, integer) TO authenticated;

-- ════════════════════════════════════════════════════════════════════
-- FIX 10: Unique constraint on task_assignments(task_id, student_id)
-- Required for assign_task RPC's ON CONFLICT (task_id, student_id) clause
-- ════════════════════════════════════════════════════════════════════

CREATE UNIQUE INDEX IF NOT EXISTS idx_task_assignments_task_student
  ON task_assignments (task_id, student_id);

-- ════════════════════════════════════════════════════════════════════
-- FIX 11: update_overdue_assignments — add SECURITY DEFINER + search_path
-- Original in Phase 3 SQL was missing these — RLS would block the UPDATE
-- ════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS update_overdue_assignments();

CREATE OR REPLACE FUNCTION update_overdue_assignments()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer;
BEGIN
  UPDATE task_assignments
  SET status = 'overdue', updated_at = now()
  WHERE status IN ('assigned', 'in_progress')
    AND task_id IN (
      SELECT id FROM tasks
      WHERE due_date IS NOT NULL AND due_date < now()
    );
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION update_overdue_assignments() TO authenticated;

-- ════════════════════════════════════════════════════════════════════
-- FIX 12: Revoke execute on calculate_completion from authenticated
-- This is an internal helper function — should not be callable by students
-- ════════════════════════════════════════════════════════════════════

REVOKE EXECUTE ON FUNCTION calculate_completion(uuid) FROM authenticated;

-- ════════════════════════════════════════════════════════════════════
-- DONE — All security fixes applied
-- ════════════════════════════════════════════════════════════════════
