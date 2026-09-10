# SADQ — Phase 3: Task + Quran + Capacity System Documentation

## Overview

This document covers the complete Task Management, Quran Progress Tracking, and Service Capacity Management ecosystem added to the SADQ platform.

---

## 1. TASK SYSTEM

### Database Tables

| Table | Purpose |
|-------|---------|
| `tasks` | Main task records with title, description, priority, due date, etc. |
| `task_items` | Checklist items within a task |
| `task_assignments` | Task assigned to individual students |
| `task_completion_items` | Checklist tick state per student per assignment |
| `task_reviews` | Teacher/admin review records |
| `task_recognitions` | Achievement-based recognition awards |
| `teacher_classes` | Which teacher manages which class |
| `class_memberships` | Which students belong to which class |

### Task Statuses

```
draft → published → assigned → in_progress → submitted → approved
                                                    ↓
                                               rejected
                                                    ↓
                                             (student retries)
```

Additional: `overdue`, `cancelled`, `archived`

### Task Priority

- `low` — green badge
- `medium` — blue badge  
- `high` — amber badge
- `urgent` — red badge

### Role Permissions

**Super Admin:**
- Create, edit, delete, assign tasks to anyone
- Assign to all students (with confirmation)
- Review submissions
- Award recognitions
- Access all task data

**Admin:**
- Create, edit, assign tasks
- Assign to authorized classes/students
- Review submissions
- Award recognitions

**Teacher:**
- Create tasks for own classes only
- Assign to own class students
- Review submissions from own classes
- Monitor progress
- Cannot access other teachers' classes

**Student:**
- View assigned tasks
- Start tasks
- Tick checklist items
- Upload evidence
- Submit for review
- View own progress and permitted rankings
- Cannot modify points, assignments, or approval fields

### RPC Functions

| Function | Parameters | Purpose |
|----------|-----------|---------|
| `assign_task` | task_id, student_ids[] | Assign task to multiple students |
| `submit_task` | assignment_id, evidence_url | Student submits task for review |
| `review_task` | assignment_id, action, comment | Teacher/admin approves/rejects |
| `calculate_completion` | assignment_id | Returns completion percentage |
| `get_task_stats` | student_id (optional) | Returns task statistics |
| `close_service` | service_id, reason | Close a service listing |

---

## 2. QURAN PROGRESS SYSTEM

### Database Tables

| Table | Purpose |
|-------|---------|
| `quran_juz_progress` | Track 30 Juz per student |
| `quran_khatm` | Completed full Quran records |
| `quran_goals` | Configurable reading goals |

### Juz Tracking

Each of the 30 Juz has three states:
- `not_started` — student hasn't begun this Juz
- `in_progress` — student is currently reading
- `completed` — student has finished this Juz

### Khatm System

When all 30 Juz are marked as `completed`, a Khatm record is automatically created with:
- `verification_status = 'pending'`
- Admin/teacher can verify or reject

Duplicate prevention: Khatm records use `ON CONFLICT DO NOTHING`.

### RPC Functions

| Function | Parameters | Purpose |
|----------|-----------|---------|
| `update_quran_progress` | juz_number, status, notes | Update a Juz's status |
| `get_quran_stats` | student_id (optional) | Returns completed/in_progress/remaining counts |

### Class Quran Dashboard

Teachers can view class-level Quran stats:
- Student count
- Average Juz completed
- Average progress percentage
- Total Khatm count
- Students with 30 Juz completed
- Top readers

---

## 3. CAPACITY MANAGEMENT

### Services

New columns added to `services` table:
- `max_applications` — maximum allowed (0 = unlimited)
- `current_applications` — current count
- `availability_status` — open/limited/full/closed/expired/archived
- `max_active_orders` — maximum concurrent orders

### Jobs

New columns added to `jobs` table:
- `max_applications` — maximum allowed
- `current_applications` — current count
- `availability_status` — open/closed
- `application_deadline` — deadline timestamp

Jobs auto-close when:
1. Deadline reached
2. Application limit reached
3. Admin manually closes

### Marketplace Products

New columns added to `products` (or `marketplace_items`):
- `stock_quantity` — total items available
- `reserved_quantity` — items in pending orders
- `sold_quantity` — items sold
- `availability_status` — in_stock/low_stock/out_of_stock/closed/archived

When stock = 0: `OUT OF STOCK` — new purchases rejected.

### Open/Close Control

Admin/owner can:
- **Open** — accept new applications/orders
- **Pause** — temporary hold (limited status)
- **Close** — reject all new applications/orders

Historical records are never deleted.

---

## 4. RLS POLICIES

### Summary

| Table | Student | Teacher | Admin |
|-------|---------|---------|-------|
| tasks | Read published/assigned | Read + Create for own classes | Full |
| task_items | Read | Read + Manage own tasks | Full |
| task_assignments | Read own + Update own | Read class + Update class | Full |
| task_completion_items | Read + Toggle own | Read class | Full |
| task_reviews | Read own | Read + Create for own classes | Full |
| quran_juz_progress | Read + Update own | Read class | Full |
| quran_khatm | Read + Insert own | Read class | Full + Verify |
| teacher_classes | Read own class | Read + Manage own | Full |
| class_memberships | Read own | Read + Insert own class | Full |

---

## 5. LEADERBOARD SCORING

### Class Ranking Formula

```
class_score = (completed_tasks / total_assignments) * 50
           + (approved_tasks / completed_tasks) * 30
           + (on_time_completions / completed_tasks) * 20
```

This normalizes for class size — a small class with 100% completion can outrank a large class with more raw completions but lower percentage.

### Student Ranking

```
student_score = (completed_tasks * 10)
             + (approved_tasks * 5)
             + (on_time_completions * 3)
             + total_points
             + (quran_juz_completed * 8)
             + (khatm_count * 50)
```

---

## 6. RECOGNITION TYPES

| Type | Criteria |
|------|----------|
| task_champion | Most tasks completed in a period |
| top_performer | Highest total points |
| consistency_star | Completed tasks consistently over time |
| class_leader | Top student in a class |
| quran_champion | Most Quran progress |
| perfect_completion | 100% completion of all assigned tasks |
| on_time_hero | All tasks completed before due date |

---

## 7. NEW PAGES

| Page | URL | Role | Purpose |
|------|-----|------|---------|
| admin-tasks.html | /admin-tasks.html | Admin | Task center — create, assign, review |
| student-tasks.html | /student-tasks.html | Student | My tasks — tabs, checklist, submit |
| quran-tracker.html | /quran-tracker.html | Student | Quran progress — 30 Juz, Khatm |

---

## 8. SQL MIGRATION

Run `sadq_phase3_tasks_quran.sql` in Supabase SQL Editor.

The migration is idempotent — safe to run multiple times.

### What Gets Created

- 5 enum types: task_status, task_priority, juz_status, service_availability, recognition_type
- 11 new tables with RLS
- 8 RPC functions
- Capacity columns on services, jobs, products/marketplace_items
- Indexes for performance
- Foreign keys and unique constraints

---

## 9. SECURITY MODEL

### Server-Side Enforcement

All security is enforced at the database level via RLS policies. Client-side checks are for UX only — the database is the source of truth.

### Key Rules

1. Students can only access their own assignments, completion data, and Quran progress
2. Teachers can only access data for classes they are authorized to manage
3. Teachers cannot modify task points, assignment ownership, or approval fields
4. Students cannot approve their own tasks
5. Closed services/jobs reject new applications at the database level
6. Out-of-stock products reject new orders
7. Admin destructive operations (delete user) require super_admin role

---

## 10. KNOWN LIMITATIONS

1. **Teacher-tasks.html** — Not yet built as a separate page. Teachers can use admin-tasks.html or the task system can be accessed from teacher-dashboard.html
2. **Real-time notifications** — Task events (assigned, due, approved) create records but don't push in real-time
3. **Task attachments** — Storage bucket not yet configured for file uploads
4. **Leaderboard page** — RPC exists but dedicated leaderboard page not yet built
5. **Overdue auto-update** — `update_overdue_assignments()` function exists but needs to be called via scheduled job (cron)
6. **Marketplace products table** — Capacity columns added conditionally (table may be named `products` or `marketplace_items`)
