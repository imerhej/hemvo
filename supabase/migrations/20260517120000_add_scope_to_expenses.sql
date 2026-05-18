-- Migration: add_scope_to_expenses
-- Adds a `scope` column ('household' | 'personal') to the expenses table.
-- Household expenses are visible to all household members.
-- Personal expenses are private — only the creator can see or modify them.
--
-- RLS changes:
--   SELECT — household: any household member; personal: creator only.
--   UPDATE — household: any household member; personal: creator only.
--   INSERT/DELETE — unchanged (creator only).

-- ── 1. Add column ─────────────────────────────────────────────────────────────
ALTER TABLE expenses
  ADD COLUMN IF NOT EXISTS scope TEXT NOT NULL DEFAULT 'household';

-- ── 2. Rebuild SELECT policy ──────────────────────────────────────────────────
DROP POLICY IF EXISTS "expenses_select" ON expenses;

CREATE POLICY "expenses_select"
  ON expenses FOR SELECT TO authenticated
  USING (
    -- Household expenses are visible to all household members.
    (
      scope = 'household'
      AND household_id IN (
        SELECT household_id FROM profiles WHERE id = auth.uid()
      )
    )
    -- Personal expenses are visible only to the creator.
    OR (scope = 'personal' AND created_by = auth.uid())
    -- Fallback: expenses with no household are visible to their creator.
    OR (household_id IS NULL AND created_by = auth.uid())
  );

-- ── 3. Rebuild UPDATE policy ──────────────────────────────────────────────────
DROP POLICY IF EXISTS "expenses_update" ON expenses;

CREATE POLICY "expenses_update"
  ON expenses FOR UPDATE TO authenticated
  USING (
    (
      scope = 'household'
      AND household_id IN (
        SELECT household_id FROM profiles WHERE id = auth.uid()
      )
    )
    OR created_by = auth.uid()
  )
  WITH CHECK (
    (
      scope = 'household'
      AND household_id IN (
        SELECT household_id FROM profiles WHERE id = auth.uid()
      )
    )
    OR created_by = auth.uid()
  );
