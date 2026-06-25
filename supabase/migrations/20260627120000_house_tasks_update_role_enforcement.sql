-- Migration: house_tasks_update_role_enforcement
-- Problem: the UPDATE policy allowed any household member to update any task,
-- meaning a Teen could bypass the client-side canWrite() gate and edit or
-- delete-field any task via direct API calls.
--
-- Fix: enforce the role split at the DB level:
--   Owner / Adult  → may update any task belonging to their household
--   Teen           → may only update tasks they created or are assigned to
--                    (matches the canMarkComplete() check client-side)
--
-- WITH CHECK is intentionally permissive on household_id to avoid blocking
-- legitimate writes; created_by and household_id are never mutated by the
-- app's update paths, so ownership is preserved naturally.

DROP POLICY IF EXISTS "house_tasks_update" ON house_tasks;

CREATE POLICY "house_tasks_update"
  ON house_tasks FOR UPDATE
  TO authenticated
  USING (
    -- Owner or Adult: full write access to any task in their household.
    household_id IN (
      SELECT household_id FROM profiles
      WHERE id = auth.uid()
        AND role IN ('Owner', 'Adult')
    )
    OR
    -- Teen: restricted to tasks they created or are assigned to.
    (
      household_id IN (
        SELECT household_id FROM profiles WHERE id = auth.uid()
      )
      AND (
        created_by       = auth.uid()
        OR assigned_to_id = auth.uid()
        OR auth.uid()    = ANY(assigned_member_ids)
      )
    )
  )
  WITH CHECK (
    household_id IN (
      SELECT household_id FROM profiles WHERE id = auth.uid()
    )
  );
