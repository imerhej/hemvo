-- Fix UPDATE policy to allow any member in the assigned_member_ids array
-- to mark a task complete, matching the client-side canMarkComplete() check.
-- The column was added in 20260507120000 but the RLS policy was never updated.

DROP POLICY IF EXISTS "house_tasks_update" ON house_tasks;

CREATE POLICY "house_tasks_update"
  ON house_tasks FOR UPDATE
  TO authenticated
  USING (
    created_by        = auth.uid()
    OR assigned_to_id = auth.uid()
    OR auth.uid()     = ANY(assigned_member_ids)
  )
  WITH CHECK (
    created_by        = auth.uid()
    OR assigned_to_id = auth.uid()
    OR auth.uid()     = ANY(assigned_member_ids)
  );
