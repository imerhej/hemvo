-- Migration: add_expenses_rls_policies
-- The expenses table was created via the Supabase dashboard and has no
-- migration-defined policies. Drop any ad-hoc ones and apply the canonical
-- 4-policy set: household members can read/update, only the creator can delete.

-- ── Drop any existing expenses policies ───────────────────────────────────
DROP POLICY IF EXISTS "expenses_delete"                   ON expenses;
DROP POLICY IF EXISTS "expenses_insert"                   ON expenses;
DROP POLICY IF EXISTS "expenses_select"                   ON expenses;
DROP POLICY IF EXISTS "expenses_update"                   ON expenses;
DROP POLICY IF EXISTS "household members can delete"      ON expenses;
DROP POLICY IF EXISTS "household members can insert"      ON expenses;
DROP POLICY IF EXISTS "household members can select"      ON expenses;
DROP POLICY IF EXISTS "household members can update"      ON expenses;
DROP POLICY IF EXISTS "household members manage expenses" ON expenses;
DROP POLICY IF EXISTS "only creator can delete"           ON expenses;
DROP POLICY IF EXISTS "creator_delete_expenses"           ON expenses;

-- ── Ensure RLS is enabled ─────────────────────────────────────────────────
ALTER TABLE expenses ENABLE ROW LEVEL SECURITY;

-- ── Canonical 4-policy set ────────────────────────────────────────────────

-- Household members OR the creator can read expenses.
CREATE POLICY "expenses_select"
  ON expenses FOR SELECT
  TO authenticated
  USING (
    household_id IN (
      SELECT household_id FROM profiles WHERE id = auth.uid()
    )
    OR created_by = auth.uid()
  );

-- Only the creator can insert.
CREATE POLICY "expenses_insert"
  ON expenses FOR INSERT
  TO authenticated
  WITH CHECK (created_by = auth.uid());

-- Any household member can update (needed for marking bills as paid by others).
CREATE POLICY "expenses_update"
  ON expenses FOR UPDATE
  TO authenticated
  USING (
    household_id IN (
      SELECT household_id FROM profiles WHERE id = auth.uid()
    )
    OR created_by = auth.uid()
  )
  WITH CHECK (
    household_id IN (
      SELECT household_id FROM profiles WHERE id = auth.uid()
    )
    OR created_by = auth.uid()
  );

-- Only the creator can delete.
CREATE POLICY "expenses_delete"
  ON expenses FOR DELETE
  TO authenticated
  USING (created_by = auth.uid());
