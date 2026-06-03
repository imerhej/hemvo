-- Migration: fix_house_tasks_update_rls_household_members
-- Problem: the UPDATE policy only allows the creator or assigned members to
-- update a task. Any other household member with write access (owner/adult)
-- whose edit goes through supabaseUpsert gets a silent RLS rejection — no DB
-- change, no realtime event, so the creator never sees their changes.
--
-- Fix: allow any household member to update tasks that belong to their
-- household. Role-based write restrictions (owner/adult vs restricted) are
-- already enforced client-side by canWrite + the Edit button gate.
--
-- Run in: Supabase Dashboard → SQL Editor → Run

DROP POLICY IF EXISTS "house_tasks_update" ON house_tasks;

CREATE POLICY "house_tasks_update"
  ON house_tasks FOR UPDATE
  TO authenticated
  USING (
    household_id IN (
      SELECT household_id FROM profiles WHERE id = auth.uid()
    )
  )
  WITH CHECK (
    household_id IN (
      SELECT household_id FROM profiles WHERE id = auth.uid()
    )
  );
