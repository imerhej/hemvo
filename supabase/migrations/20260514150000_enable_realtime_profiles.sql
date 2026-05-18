-- Enable Realtime CDC for the profiles table so HouseholdService can receive
-- live role/permissions changes. This lets a member's device update its local
-- household state immediately when the owner changes their role, without waiting
-- for the next manual refreshMembers() call.
--
-- REPLICA IDENTITY FULL is required so UPDATE events carry the full old+new row,
-- which the Supabase Realtime filter (.eq("household_id", …)) can match on.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'profiles'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE profiles;
  END IF;
END $$;

ALTER TABLE profiles REPLICA IDENTITY FULL;
