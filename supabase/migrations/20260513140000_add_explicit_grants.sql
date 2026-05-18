-- Migration: add_explicit_grants
-- Supabase is changing the default for new tables in the public schema:
--   • May 30, 2026  → new projects require explicit GRANTs
--   • October 30, 2026 → enforced on all existing projects
--
-- Without explicit GRANTs, supabase-js / PostgREST / GraphQL will return
-- a 42501 error for any table that doesn't have them.
--
-- This migration grants the minimum necessary access per role on every table
-- currently in the project. RLS policies still govern which rows each
-- authenticated user can actually see or modify.
--
-- anon is intentionally omitted — the app requires sign-in for all operations.

-- ── households ────────────────────────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE, DELETE ON public.households TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.households TO service_role;

-- ── profiles ──────────────────────────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE, DELETE ON public.profiles TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.profiles TO service_role;

-- ── house_tasks ───────────────────────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE, DELETE ON public.house_tasks TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.house_tasks TO service_role;

-- ── events ────────────────────────────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE, DELETE ON public.events TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.events TO service_role;

-- ── expenses ──────────────────────────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE, DELETE ON public.expenses TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.expenses TO service_role;

-- ── device_tokens ─────────────────────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE, DELETE ON public.device_tokens TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.device_tokens TO service_role;

-- ── notification_schedule ─────────────────────────────────────────────────
-- The iOS client only inserts and deletes rows (scheduling / cancelling pushes).
-- The edge function (process-scheduled-push) uses the service-role key which
-- bypasses RLS, but still needs the GRANT to reach the table via PostgREST.
GRANT INSERT, DELETE ON public.notification_schedule TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.notification_schedule TO service_role;

-- ── meals ─────────────────────────────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE, DELETE ON public.meals TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.meals TO service_role;
