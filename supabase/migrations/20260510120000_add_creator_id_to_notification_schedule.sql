-- Migration: add_creator_id_to_notification_schedule
-- Allows process-scheduled-push to exclude the event creator from receiving
-- their own scheduled reminders (alert-time and at-event-time pushes).

ALTER TABLE notification_schedule
  ADD COLUMN IF NOT EXISTS creator_id uuid;
