-- Migration: add_source_meal_date_to_notification_schedule
-- Adds two columns used by meal push scheduling:
--   source    — identifies the origin ('meal', 'event', etc.) so meal rows can
--               be deleted and replaced when meals for a date change.
--   meal_date — 'yyyy-MM-dd' string for the planned meal day, used to identify
--               which scheduled push belongs to which meal date.

ALTER TABLE notification_schedule
  ADD COLUMN IF NOT EXISTS source    TEXT,
  ADD COLUMN IF NOT EXISTS meal_date TEXT;
