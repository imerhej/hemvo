-- Supabase Realtime filters DELETE (and UPDATE oldRecord) events by matching
-- column values against the subscriber's filter clause. With the default
-- REPLICA IDENTITY (primary-key only), the WAL log omits non-PK columns for
-- DELETE, so the `household_id` filter on the channel can never match and
-- DELETE events are silently dropped. Setting FULL makes Postgres log every
-- column for every change, letting Realtime apply any column filter correctly.
ALTER TABLE events     REPLICA IDENTITY FULL;
ALTER TABLE house_tasks REPLICA IDENTITY FULL;
