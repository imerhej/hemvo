-- rls_policies.sql
-- Run in: Supabase Dashboard → SQL Editor → Run
--
-- Enables Row Level Security on every table the app touches and defines
-- the minimum policies required. auth.uid() returns the JWT sub claim
-- (the authenticated user's UUID).
--
-- Tables covered:
--   profiles, households, events, house_tasks, expenses, meals,
--   grocery_items, shopping_items, shopping_lists, device_tokens

-- ─────────────────────────────────────────────────────────────────────────────
-- profiles
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- Authenticated users may read their own row and their household members' rows.
-- Anon callers cannot read profiles directly; username login uses get_email_for_username() RPC.
-- NOTE: tightened from the original USING (true) by migration 20260625150000.
CREATE POLICY "profiles_select"
  ON profiles FOR SELECT
  TO authenticated
  USING (
    id = auth.uid()
    OR household_id IS NOT NULL AND household_id = (
      SELECT household_id FROM profiles WHERE id = auth.uid() LIMIT 1
    )
  );

-- Users can only update their own profile row.
CREATE POLICY "profiles_update"
  ON profiles FOR UPDATE
  TO authenticated
  USING (id = auth.uid());

-- ─────────────────────────────────────────────────────────────────────────────
-- households
-- Schema: id uuid, name text, owner_id uuid → auth.users(id), created_at
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE households ENABLE ROW LEVEL SECURITY;

-- Members of a household (via profiles.household_id) can read it.
-- Unauthenticated callers get nothing.
CREATE POLICY "households_select"
  ON households FOR SELECT
  TO authenticated
  USING (
    id IN (
      SELECT household_id FROM profiles WHERE id = auth.uid()
    )
    OR owner_id = auth.uid()
  );

-- Any authenticated user can create a household (they become owner_id).
CREATE POLICY "households_insert"
  ON households FOR INSERT
  TO authenticated
  WITH CHECK (owner_id = auth.uid());

-- Only the owner can rename the household.
CREATE POLICY "households_update"
  ON households FOR UPDATE
  TO authenticated
  USING (owner_id = auth.uid());

-- Only the owner can delete the household.
CREATE POLICY "households_delete"
  ON households FOR DELETE
  TO authenticated
  USING (owner_id = auth.uid());

-- ─────────────────────────────────────────────────────────────────────────────
-- events
-- Schema: id, household_id, title, date, end_date, assigned_to_id,
--         is_all_day, notes, category, color_hex, repeat_rule,
--         travel_time, alert_option, created_by uuid, created_at, invitee_ids
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE events ENABLE ROW LEVEL SECURITY;

-- Household members can see all events in their household.
CREATE POLICY "events_select"
  ON events FOR SELECT
  TO authenticated
  USING (
    household_id IN (
      SELECT household_id FROM profiles WHERE id = auth.uid()
    )
    OR created_by = auth.uid()
  );

CREATE POLICY "events_insert"
  ON events FOR INSERT
  TO authenticated
  WITH CHECK (created_by = auth.uid());

CREATE POLICY "events_update"
  ON events FOR UPDATE
  TO authenticated
  USING (created_by = auth.uid());

CREATE POLICY "events_delete"
  ON events FOR DELETE
  TO authenticated
  USING (created_by = auth.uid());

-- ─────────────────────────────────────────────────────────────────────────────
-- house_tasks
-- Schema: id, household_id, title, assigned_to_id, due_date, is_complete,
--         priority, notes, completed_date, created_by uuid, created_at
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE house_tasks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "house_tasks_select"
  ON house_tasks FOR SELECT
  TO authenticated
  USING (
    household_id IN (
      SELECT household_id FROM profiles WHERE id = auth.uid()
    )
    OR created_by = auth.uid()
  );

CREATE POLICY "house_tasks_insert"
  ON house_tasks FOR INSERT
  TO authenticated
  WITH CHECK (created_by = auth.uid());

-- Any household member can update tasks in their household.
-- Role-based write restrictions (owner/adult) are enforced client-side.
CREATE POLICY "house_tasks_update"
  ON house_tasks FOR UPDATE
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

CREATE POLICY "house_tasks_delete"
  ON house_tasks FOR DELETE
  TO authenticated
  USING (created_by = auth.uid());

-- ─────────────────────────────────────────────────────────────────────────────
-- expenses
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE expenses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "expenses_select"
  ON expenses FOR SELECT
  TO authenticated
  USING (
    household_id IN (
      SELECT household_id FROM profiles WHERE id = auth.uid()
    )
    OR created_by = auth.uid()
  );

CREATE POLICY "expenses_insert"
  ON expenses FOR INSERT
  TO authenticated
  WITH CHECK (created_by = auth.uid());

CREATE POLICY "expenses_update"
  ON expenses FOR UPDATE
  TO authenticated
  USING (created_by = auth.uid());

CREATE POLICY "expenses_delete"
  ON expenses FOR DELETE
  TO authenticated
  USING (created_by = auth.uid());

-- ─────────────────────────────────────────────────────────────────────────────
-- meals
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE meals ENABLE ROW LEVEL SECURITY;

CREATE POLICY "meals_select"
  ON meals FOR SELECT
  TO authenticated
  USING (
    household_id IN (
      SELECT household_id FROM profiles WHERE id = auth.uid()
    )
    OR created_by = auth.uid()
  );

CREATE POLICY "meals_insert"
  ON meals FOR INSERT
  TO authenticated
  WITH CHECK (created_by = auth.uid());

CREATE POLICY "meals_update"
  ON meals FOR UPDATE
  TO authenticated
  USING (created_by = auth.uid());

CREATE POLICY "meals_delete"
  ON meals FOR DELETE
  TO authenticated
  USING (created_by = auth.uid());

-- ─────────────────────────────────────────────────────────────────────────────
-- grocery_items
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE grocery_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "grocery_items_select"
  ON grocery_items FOR SELECT
  TO authenticated
  USING (created_by = auth.uid());

CREATE POLICY "grocery_items_insert"
  ON grocery_items FOR INSERT
  TO authenticated
  WITH CHECK (created_by = auth.uid());

CREATE POLICY "grocery_items_update"
  ON grocery_items FOR UPDATE
  TO authenticated
  USING (created_by = auth.uid());

CREATE POLICY "grocery_items_delete"
  ON grocery_items FOR DELETE
  TO authenticated
  USING (created_by = auth.uid());

-- ─────────────────────────────────────────────────────────────────────────────
-- shopping_items
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE shopping_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "shopping_items_select"
  ON shopping_items FOR SELECT
  TO authenticated
  USING (created_by = auth.uid());

CREATE POLICY "shopping_items_insert"
  ON shopping_items FOR INSERT
  TO authenticated
  WITH CHECK (created_by = auth.uid());

CREATE POLICY "shopping_items_update"
  ON shopping_items FOR UPDATE
  TO authenticated
  USING (created_by = auth.uid());

CREATE POLICY "shopping_items_delete"
  ON shopping_items FOR DELETE
  TO authenticated
  USING (created_by = auth.uid());

-- ─────────────────────────────────────────────────────────────────────────────
-- shopping_lists
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE shopping_lists ENABLE ROW LEVEL SECURITY;

CREATE POLICY "shopping_lists_select"
  ON shopping_lists FOR SELECT
  TO authenticated
  USING (created_by = auth.uid());

CREATE POLICY "shopping_lists_insert"
  ON shopping_lists FOR INSERT
  TO authenticated
  WITH CHECK (created_by = auth.uid());

CREATE POLICY "shopping_lists_update"
  ON shopping_lists FOR UPDATE
  TO authenticated
  USING (created_by = auth.uid());

CREATE POLICY "shopping_lists_delete"
  ON shopping_lists FOR DELETE
  TO authenticated
  USING (created_by = auth.uid());

-- ─────────────────────────────────────────────────────────────────────────────
-- device_tokens  (APNs push notification tokens)
-- Schema: user_id uuid, household_id uuid, token text
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY "device_tokens_select"
  ON device_tokens FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "device_tokens_insert"
  ON device_tokens FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "device_tokens_update"
  ON device_tokens FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "device_tokens_delete"
  ON device_tokens FOR DELETE
  TO authenticated
  USING (user_id = auth.uid());

-- ─────────────────────────────────────────────────────────────────────────────
-- Verify: run this after applying to confirm RLS is ON for every table
-- ─────────────────────────────────────────────────────────────────────────────
-- SELECT tablename, rowsecurity
-- FROM pg_tables
-- WHERE schemaname = 'public'
-- ORDER BY tablename;
