-- Migration: add_notification_schedule_rls
-- The iOS client inserts rows when scheduling event pushes and deletes them
-- when cancelling. RLS was enabled on this table without any authenticated
-- policies, silently blocking those writes. This adds the minimum policies
-- needed: members of the relevant household can insert and delete.

CREATE POLICY "notification_schedule_insert"
  ON notification_schedule FOR INSERT
  TO authenticated
  WITH CHECK (
    household_id IN (
      SELECT household_id FROM profiles WHERE id = auth.uid()
    )
  );

CREATE POLICY "notification_schedule_delete"
  ON notification_schedule FOR DELETE
  TO authenticated
  USING (
    household_id IN (
      SELECT household_id FROM profiles WHERE id = auth.uid()
    )
  );
