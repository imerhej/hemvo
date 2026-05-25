-- Fix handle_new_user trigger to:
--   1. Read username from raw_user_meta_data (was missing, causing empty username on signup)
--   2. Leave role NULL for new users (role becomes meaningful only after joining a household)

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email, username)
  VALUES (
    new.id,
    new.raw_user_meta_data->>'full_name',
    new.email,
    new.raw_user_meta_data->>'username'
  )
  ON CONFLICT (id) DO UPDATE
    SET full_name = EXCLUDED.full_name,
        email     = EXCLUDED.email,
        username  = COALESCE(EXCLUDED.username, profiles.username);
  RETURN new;
END;
$$;

-- Re-attach in case the trigger was pointing at the old function body
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
