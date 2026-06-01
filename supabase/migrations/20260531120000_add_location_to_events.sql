-- Migration: add_location_to_events
-- Adds a `location` column to the events table to store a venue or address string.

ALTER TABLE events
  ADD COLUMN IF NOT EXISTS location TEXT NOT NULL DEFAULT '';
