-- Migration: add_invitee_ids_to_events
-- Adds the invitee_ids column to the events table so the iOS app can store
-- and sync the list of household members explicitly invited to an event.
-- The Swift model (CalendarEvent.inviteeIDs) and push notification logic
-- (ScheduleViewModel.sendEventCreationPush) already depend on this column.

ALTER TABLE events
  ADD COLUMN IF NOT EXISTS invitee_ids uuid[] NOT NULL DEFAULT '{}';
