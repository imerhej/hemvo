-- Migration: cleanup_house_tasks_policies
-- The house_tasks table accumulated duplicate and conflicting policies
-- from multiple manual edits. Drop everything and apply the single
-- canonical set defined in rls_policies.sql.

-- ── Drop all existing house_tasks policies ────────────────────────────────
DROP POLICY IF EXISTS "house_tasks_delete"               ON house_tasks;
DROP POLICY IF EXISTS "house_tasks_insert"               ON house_tasks;
DROP POLICY IF EXISTS "house_tasks_select"               ON house_tasks;
DROP POLICY IF EXISTS "house_tasks_update"               ON house_tasks;
DROP POLICY IF EXISTS "creator or household owner can delete" ON house_tasks;
DROP POLICY IF EXISTS "creator_delete_house_tasks"       ON house_tasks;
DROP POLICY IF EXISTS "household members can delete"     ON house_tasks;
DROP POLICY IF EXISTS "household members can insert"     ON house_tasks;
DROP POLICY IF EXISTS "household members can select"     ON house_tasks;
DROP POLICY IF EXISTS "household members can update"     ON house_tasks;
DROP POLICY IF EXISTS "household members manage tasks"   ON house_tasks;
DROP POLICY IF EXISTS "only creator can delete"          ON house_tasks;

-- ── Recreate the canonical set ────────────────────────────────────────────

-- Any household member (or the creator) can read tasks.
CREATE POLICY "house_tasks_select"
  ON house_tasks FOR SELECT
  TO authenticated
  USING (
    household_id IN (
      SELECT household_id FROM profiles WHERE id = auth.uid()
    )
    OR created_by = auth.uid()
  );

-- Only authenticated users can insert; they must own the created_by field.
CREATE POLICY "house_tasks_insert"
  ON house_tasks FOR INSERT
  TO authenticated
  WITH CHECK (created_by = auth.uid());

-- Creator OR assigned member can update (e.g. toggle is_complete).
CREATE POLICY "house_tasks_update"
  ON house_tasks FOR UPDATE
  TO authenticated
  USING (
    created_by    = auth.uid()
    OR assigned_to_id = auth.uid()
  )
  WITH CHECK (
    created_by    = auth.uid()
    OR assigned_to_id = auth.uid()
  );

-- Only the creator can delete a task.
CREATE POLICY "house_tasks_delete"
  ON house_tasks FOR DELETE
  TO authenticated
  USING (created_by = auth.uid());
