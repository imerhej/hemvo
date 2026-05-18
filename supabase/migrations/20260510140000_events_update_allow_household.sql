-- Allow any household member to UPDATE an event, not just the creator.
-- The original "events_update" policy restricted edits to created_by = auth.uid(),
-- which blocked non-creator household members from saving changes.
-- The new policy checks household membership for both USING and WITH CHECK so
-- users can only edit events that belong to their household.
-- created_by and household_id are never written by the app's UPDATE path
-- (supabaseUpdateEvent omits those columns), so ownership is preserved naturally.

DROP POLICY IF EXISTS "events_update" ON events;

CREATE POLICY "events_update"
  ON events FOR UPDATE TO authenticated
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
