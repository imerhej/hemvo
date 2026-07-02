-- Migration: drop_stray_broad_write_policies
--
-- Follow-up to standardize_bills_meals_edit_permissions: two ad-hoc,
-- dashboard-created policies (not tracked in any prior migration) were still
-- present on the live database and are broader than the new Owner/Adult-aware
-- policies. Since Postgres RLS policies are OR'd together within a command,
-- these silently defeated the role restriction just added:
--
--   "household members manage meals" (ALL, meals)   — any household member,
--       no role check — overrides meals_update / meals_delete.
--   "members can update expenses" (UPDATE, expenses) — any household member,
--       no role check — overrides expenses_update.
--
-- Confirmed via `supabase db query` against pg_policy that these were the
-- only two stray policies broader than their canonical counterparts; the
-- remaining duplicates (only creator can delete, creator_delete_meals,
-- creator can delete expenses, creator_or_owner_delete_expenses) are strict
-- subsets of the canonical policies and are left in place as harmless.

DROP POLICY IF EXISTS "household members manage meals" ON meals;
DROP POLICY IF EXISTS "members can update expenses"     ON expenses;
