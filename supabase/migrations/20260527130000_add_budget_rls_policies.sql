-- Migration: add_budget_rls_policies
-- budget_settings and budget_categories were created via the Supabase dashboard
-- with no RLS policies, so all app reads/writes were silently blocked.
-- This migration enables RLS and adds the canonical household-scoped policy set.

-- ── budget_settings ───────────────────────────────────────────────────────────

ALTER TABLE budget_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "budget_settings_select"
  ON budget_settings FOR SELECT
  TO authenticated
  USING (
    household_id IN (
      SELECT household_id FROM profiles WHERE id = auth.uid()
    )
  );

CREATE POLICY "budget_settings_insert"
  ON budget_settings FOR INSERT
  TO authenticated
  WITH CHECK (
    household_id IN (
      SELECT household_id FROM profiles WHERE id = auth.uid()
    )
  );

CREATE POLICY "budget_settings_update"
  ON budget_settings FOR UPDATE
  TO authenticated
  USING (
    household_id IN (
      SELECT household_id FROM profiles WHERE id = auth.uid()
    )
  )
  WITH CHECK (
    household_id IN (
      SELECT household_id FROM profiles WHERE id = auth.uid()
    )
  );

CREATE POLICY "budget_settings_delete"
  ON budget_settings FOR DELETE
  TO authenticated
  USING (
    household_id IN (
      SELECT household_id FROM profiles WHERE id = auth.uid()
    )
  );

-- ── budget_categories ─────────────────────────────────────────────────────────

ALTER TABLE budget_categories ENABLE ROW LEVEL SECURITY;

CREATE POLICY "budget_categories_select"
  ON budget_categories FOR SELECT
  TO authenticated
  USING (
    household_id IN (
      SELECT household_id FROM profiles WHERE id = auth.uid()
    )
  );

CREATE POLICY "budget_categories_insert"
  ON budget_categories FOR INSERT
  TO authenticated
  WITH CHECK (
    household_id IN (
      SELECT household_id FROM profiles WHERE id = auth.uid()
    )
  );

CREATE POLICY "budget_categories_update"
  ON budget_categories FOR UPDATE
  TO authenticated
  USING (
    household_id IN (
      SELECT household_id FROM profiles WHERE id = auth.uid()
    )
  )
  WITH CHECK (
    household_id IN (
      SELECT household_id FROM profiles WHERE id = auth.uid()
    )
  );

CREATE POLICY "budget_categories_delete"
  ON budget_categories FOR DELETE
  TO authenticated
  USING (
    household_id IN (
      SELECT household_id FROM profiles WHERE id = auth.uid()
    )
  );

-- ── Realtime ──────────────────────────────────────────────────────────────────
-- Allow the app's budget realtime subscription to receive change events.

ALTER PUBLICATION supabase_realtime ADD TABLE budget_settings;
ALTER PUBLICATION supabase_realtime ADD TABLE budget_categories;
