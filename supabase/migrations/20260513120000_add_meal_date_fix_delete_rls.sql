-- Migration: add meal_date column + fix meals delete RLS
-- Bug fix: meals were scoped to day-of-week only, causing next-week bleed.
-- Bug fix: only the creator could delete, so stale meals got stuck for other members.

-- 1. Add meal_date column (nullable — old rows will be handled by Swift fallback)
ALTER TABLE meals ADD COLUMN IF NOT EXISTS meal_date text;

-- 2. Drop any creator-only delete policy that blocks household members
DROP POLICY IF EXISTS "Users can delete their own meals" ON meals;
DROP POLICY IF EXISTS "Creators can delete meals"        ON meals;
DROP POLICY IF EXISTS "meal_delete_own"                  ON meals;

-- 3. Allow any household member to delete any meal in their household
--    (prevents stale meals from getting stuck when the creator deletes but others still see it)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'meals'
      AND policyname = 'Household members can delete meals'
  ) THEN
    CREATE POLICY "Household members can delete meals"
      ON meals FOR DELETE
      USING (
        household_id IN (
          SELECT household_id FROM profiles WHERE id = auth.uid()
        )
      );
  END IF;
END $$;
