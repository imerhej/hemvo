-- Enable Realtime CDC for the expenses table so that all household members
-- receive live INSERT/UPDATE/DELETE events via the RealtimeV2 subscription
-- in BudgetViewModel without polling.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'expenses'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE expenses;
  END IF;
END $$;
