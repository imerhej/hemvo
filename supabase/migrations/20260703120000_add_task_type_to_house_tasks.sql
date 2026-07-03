-- Migration: add_task_type_to_house_tasks
--
-- Problem: house_tasks is shared, unscoped, between two unrelated features:
--   - ScheduleViewModel's one-off HouseTask rows (Schedule tab)
--   - MaintenanceViewModel's recurring MaintenanceItem rows (Maintenance tab)
-- Both loadTasksFromSupabase (Schedule) and loadFromSupabase (Maintenance)
-- select every row for the household with no way to tell them apart, so a
-- Maintenance chore currently leaks into the Schedule tab's task list (and
-- vice versa). This is a prerequisite for making Maintenance completion
-- recurring (see 20260703130000_add_maintenance_completions.sql) without
-- corrupting Schedule's view of the same rows.
--
-- Backfill heuristic: `frequency` is a Maintenance-only concept — every
-- MaintenanceItem always carries a non-null cadence, while Schedule's
-- HouseTask never writes that column. Existing rows with a non-null
-- frequency are reclassified as 'maintenance'; everything else defaults
-- to 'schedule' (house_tasks predates Maintenance and was Schedule-only
-- originally, per the schema comment in rls_policies.sql).

ALTER TABLE house_tasks
  ADD COLUMN IF NOT EXISTS task_type TEXT NOT NULL DEFAULT 'schedule';

ALTER TABLE house_tasks
  ADD CONSTRAINT house_tasks_task_type_check
  CHECK (task_type IN ('schedule', 'maintenance'));

UPDATE house_tasks SET task_type = 'maintenance' WHERE frequency IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_house_tasks_task_type ON house_tasks(task_type);
