-- Enable Realtime CDC for meals so all household members receive live
-- INSERT/UPDATE/DELETE events via the RealtimeV2 subscription in
-- MealPlanViewModel without polling.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'meals'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE meals;
  END IF;
END $$;

-- Full replica identity so DELETE events carry the old row (household_id filter works).
ALTER TABLE meals REPLICA IDENTITY FULL;
