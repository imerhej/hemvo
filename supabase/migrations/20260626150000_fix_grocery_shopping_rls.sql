-- Fix SELECT RLS for grocery_items, shopping_lists, and shopping_items.
--
-- The original policies only allowed created_by = auth.uid(), but the app
-- queries by household_id (GroceryViewModel, ShoppingListViewModel) so all
-- household members need to see each other's items.
--
-- grocery_items    has: household_id, created_by
-- shopping_lists   has: household_id, created_by
-- shopping_items   has: list_id (no household_id — go through shopping_lists)

-- ── grocery_items ─────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "grocery_items_select" ON grocery_items;

CREATE POLICY "grocery_items_select"
  ON grocery_items FOR SELECT
  TO authenticated
  USING (
    created_by = auth.uid()
    OR (
      household_id IS NOT NULL
      AND household_id IN (
        SELECT household_id FROM profiles
        WHERE id = auth.uid() AND household_id IS NOT NULL
      )
    )
  );

-- ── shopping_lists ────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "shopping_lists_select" ON shopping_lists;

CREATE POLICY "shopping_lists_select"
  ON shopping_lists FOR SELECT
  TO authenticated
  USING (
    created_by = auth.uid()
    OR (
      household_id IS NOT NULL
      AND household_id IN (
        SELECT household_id FROM profiles
        WHERE id = auth.uid() AND household_id IS NOT NULL
      )
    )
  );

-- ── shopping_items ────────────────────────────────────────────────────────────
-- shopping_items has no household_id — access is granted when the parent list
-- is visible to the caller (avoids a redundant household join on every item row).

DROP POLICY IF EXISTS "shopping_items_select" ON shopping_items;

CREATE POLICY "shopping_items_select"
  ON shopping_items FOR SELECT
  TO authenticated
  USING (
    list_id IN (
      SELECT id FROM shopping_lists
      WHERE created_by = auth.uid()
        OR (
          household_id IS NOT NULL
          AND household_id IN (
            SELECT household_id FROM profiles
            WHERE id = auth.uid() AND household_id IS NOT NULL
          )
        )
    )
  );
