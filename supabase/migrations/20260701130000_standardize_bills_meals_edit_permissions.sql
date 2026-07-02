-- Migration: standardize_bills_meals_edit_permissions
--
-- Inconsistency: expenses (bills) DELETE was creator-only, and meals DELETE
-- allowed any household member — neither matched the Owner/Adult role split
-- already enforced on events/house_tasks (see fix_delete_rls_role_enforcement
-- and house_tasks_update_role_enforcement):
--   Owner / Adult → full write authority over any household item
--   Teen / solo   → restricted to items they created
--
-- This migration brings expenses and meals in line with that model.

-- ── expenses (bills) ──────────────────────────────────────────────────────────

-- UPDATE: was "any household member" for household-scope items; now Owner/Adult
-- get full authority, Teen/solo are restricted to items they created.
-- Personal-scope items remain creator-only (unchanged — they're private by design).
DROP POLICY IF EXISTS "expenses_update" ON expenses;

CREATE POLICY "expenses_update"
  ON expenses FOR UPDATE TO authenticated
  USING (
    (
      scope = 'household'
      AND (
        household_id IN (
          SELECT household_id FROM profiles
          WHERE id = auth.uid() AND role IN ('Owner', 'Adult')
        )
        OR created_by = auth.uid()
      )
    )
    OR (scope <> 'household' AND created_by = auth.uid())
  )
  WITH CHECK (
    (
      scope = 'household'
      AND (
        household_id IN (
          SELECT household_id FROM profiles
          WHERE id = auth.uid() AND role IN ('Owner', 'Adult')
        )
        OR created_by = auth.uid()
      )
    )
    OR (scope <> 'household' AND created_by = auth.uid())
  );

-- DELETE: was creator-only; now Owner/Adult may delete any household-scope
-- expense, Teen/solo restricted to their own. Personal-scope stays creator-only.
DROP POLICY IF EXISTS "expenses_delete" ON expenses;

CREATE POLICY "expenses_delete"
  ON expenses FOR DELETE TO authenticated
  USING (
    (
      scope = 'household'
      AND (
        household_id IN (
          SELECT household_id FROM profiles
          WHERE id = auth.uid() AND role IN ('Owner', 'Adult')
        )
        OR created_by = auth.uid()
      )
    )
    OR (scope <> 'household' AND created_by = auth.uid())
  );

-- ── meals ─────────────────────────────────────────────────────────────────────
-- meals INSERT/SELECT/UPDATE policies were created ad hoc via the Supabase
-- dashboard and are not tracked in migrations, so their exact prior names are
-- unknown. Drop plausible prior names defensively (same approach used for the
-- expenses table in add_expenses_rls_policies) before installing canonical
-- Owner/Adult-aware UPDATE/DELETE policies. SELECT/INSERT are left untouched —
-- they're not part of the edit-permission inconsistency being fixed here.

DROP POLICY IF EXISTS "meals_update"                       ON meals;
DROP POLICY IF EXISTS "household members can update"       ON meals;
DROP POLICY IF EXISTS "Users can update their own meals"    ON meals;
DROP POLICY IF EXISTS "Household members can update meals"  ON meals;

CREATE POLICY "meals_update"
  ON meals FOR UPDATE TO authenticated
  USING (
    household_id IN (
      SELECT household_id FROM profiles
      WHERE id = auth.uid() AND role IN ('Owner', 'Adult')
    )
    OR created_by = auth.uid()
  )
  WITH CHECK (
    household_id IN (
      SELECT household_id FROM profiles WHERE id = auth.uid()
    )
  );

-- DELETE: previously any household member could delete any meal
-- (add_meal_date_fix_delete_rls); now Owner/Adult retain full authority,
-- Teen/solo restricted to meals they created.
DROP POLICY IF EXISTS "meals_delete"                       ON meals;
DROP POLICY IF EXISTS "Household members can delete meals" ON meals;
DROP POLICY IF EXISTS "Users can delete their own meals"   ON meals;
DROP POLICY IF EXISTS "Creators can delete meals"          ON meals;
DROP POLICY IF EXISTS "meal_delete_own"                    ON meals;

CREATE POLICY "meals_delete"
  ON meals FOR DELETE TO authenticated
  USING (
    household_id IN (
      SELECT household_id FROM profiles
      WHERE id = auth.uid() AND role IN ('Owner', 'Adult')
    )
    OR created_by = auth.uid()
  );
