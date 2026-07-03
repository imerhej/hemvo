-- Migration: add_maintenance_completions
--
-- Enables recurring Maintenance tasks. Previously MaintenanceViewModel.markComplete
-- retired a house_tasks row for good (is_complete = true), so a weekly/monthly
-- chore never came back after the first completion. Going forward, marking a
-- maintenance task done:
--   1. Logs one row here (a completion event, snapshotting what was done/due)
--   2. Rolls the same house_tasks row's due_date forward by frequency.days,
--      keeping is_complete = false so it stays in the active list
-- History is read from this table instead of house_tasks rows with
-- is_complete = 'true'.
--
-- task_id is nullable with ON DELETE SET NULL (not CASCADE) so completion
-- history survives even if the recurring task definition is later deleted —
-- the row already snapshots title/area/frequency/etc, so it still renders
-- correctly in history with a null task_id.

CREATE TABLE IF NOT EXISTS maintenance_completions (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id                UUID REFERENCES house_tasks(id) ON DELETE SET NULL,
  household_id           UUID NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  completed_by           UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  completed_date         TIMESTAMPTZ NOT NULL DEFAULT now(),
  due_date_at_completion TIMESTAMPTZ NOT NULL,
  title                  TEXT NOT NULL,
  area                   TEXT,
  frequency              TEXT,
  estimated_minutes      INT,
  notes                  TEXT NOT NULL DEFAULT '',
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_maintenance_completions_household
  ON maintenance_completions(household_id);
CREATE INDEX IF NOT EXISTS idx_maintenance_completions_task
  ON maintenance_completions(task_id);

ALTER TABLE maintenance_completions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "maintenance_completions_select"
  ON maintenance_completions FOR SELECT
  TO authenticated
  USING (
    household_id IN (
      SELECT household_id FROM profiles WHERE id = auth.uid()
    )
    OR completed_by = auth.uid()
  );

CREATE POLICY "maintenance_completions_insert"
  ON maintenance_completions FOR INSERT
  TO authenticated
  WITH CHECK (completed_by = auth.uid());

-- Owner/Adult: full delete authority over household completion records.
-- Teen or solo: may only delete records they personally logged.
-- Mirrors house_tasks_delete's role split (20260628120000).
CREATE POLICY "maintenance_completions_delete"
  ON maintenance_completions FOR DELETE
  TO authenticated
  USING (
    household_id IN (
      SELECT household_id FROM profiles
      WHERE id = auth.uid()
        AND role IN ('Owner', 'Adult')
    )
    OR completed_by = auth.uid()
  );

-- Required for PostgREST access since May 30, 2026 (see 20260513140000_add_explicit_grants.sql).
GRANT SELECT, INSERT, DELETE ON public.maintenance_completions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.maintenance_completions TO service_role;

-- ── One-time backfill ────────────────────────────────────────────────────────
-- Convert existing completed maintenance rows into log entries so history
-- isn't empty after this ships. completed_by is approximated as the task's
-- creator since older rows never recorded who actually tapped "Mark Done".
INSERT INTO maintenance_completions
  (task_id, household_id, completed_by, completed_date, due_date_at_completion,
   title, area, frequency, estimated_minutes, notes)
SELECT id, household_id, created_by, COALESCE(completed_date, now()), due_date,
       title, area, frequency, estimated_minutes, notes
FROM house_tasks
WHERE task_type = 'maintenance' AND is_complete = true;
