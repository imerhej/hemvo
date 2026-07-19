-- Migration: expenses_budget_replica_identity_full
--
-- Bug: a household expense deleted by one member kept showing on every other
-- member's device (and looked like it was "still in Supabase" when observed
-- through that stale device).
--
-- Root cause: the BudgetViewModel Realtime subscriptions filter on
--   household_id=eq.<hid>
-- Supabase Realtime evaluates that filter against the row payload. For INSERT
-- and UPDATE the payload's record carries every column, so the filter matches
-- and the event is delivered — which is why *adding* an expense propagated.
-- For DELETE, the payload's "old record" only contains the columns in the
-- table's REPLICA IDENTITY. With the default identity (primary key only) that
-- is just `id`; `household_id` is absent, the filter never matches, and the
-- DELETE event is silently dropped. Other members therefore never learn the
-- row was removed until a full reload.
--
-- events / house_tasks / meals / profiles were already switched to REPLICA
-- IDENTITY FULL for this exact reason; expenses and budget_categories were
-- missed. Setting FULL makes the DELETE payload carry household_id so the
-- filtered subscription delivers deletes to every household member.
--
-- Cost is negligible: these are low-write tables, and FULL only adds the old
-- row to the WAL on UPDATE/DELETE.

ALTER TABLE public.expenses          REPLICA IDENTITY FULL;
ALTER TABLE public.budget_categories REPLICA IDENTITY FULL;
