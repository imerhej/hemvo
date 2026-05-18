-- Enable Realtime CDC for events and house_tasks so all household members
-- receive live INSERT/UPDATE/DELETE events via the RealtimeV2 subscription
-- in ScheduleViewModel without polling.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'events'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE events;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'house_tasks'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE house_tasks;
  END IF;
END $$;
