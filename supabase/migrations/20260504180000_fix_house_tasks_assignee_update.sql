-- Migration: fix_house_tasks_assignee_update
-- Problem: the original house_tasks_update policy only allowed the row
-- creator to update a task. Assigned members couldn't mark tasks complete.
--
-- Fix: drop the old policy and recreate it so both the creator AND the
-- assigned member can update the row (e.g. toggle is_complete).
--
-- Run in: Supabase Dashboard → SQL Editor → Run

-- Drop old policy (safe — IF EXISTS guard prevents errors on re-run).
DROP POLICY IF EXISTS "house_tasks_update" ON house_tasks;

-- Recreate with assignee permission.
-- USING  → which existing rows can be targeted by UPDATE
-- WITH CHECK → which new row values are allowed after the update
CREATE POLICY "house_tasks_update"
  ON house_tasks
  FOR UPDATE
  TO authenticated
  USING (
    created_by    = auth.uid()
    OR assigned_to_id = auth.uid()
  )
  WITH CHECK (
    created_by    = auth.uid()
    OR assigned_to_id = auth.uid()
  );
