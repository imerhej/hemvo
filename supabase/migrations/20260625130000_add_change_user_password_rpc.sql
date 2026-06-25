-- change_user_password: allows an authenticated user to change their own password
-- by verifying the current password before writing the new one.
-- SECURITY DEFINER so it can read and write auth.users directly.
-- search_path is pinned to prevent search-path injection.

CREATE OR REPLACE FUNCTION public.change_user_password(
    current_pw TEXT,
    new_pw     TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    caller_id     UUID;
    stored_hash   TEXT;
BEGIN
    caller_id := auth.uid();
    IF caller_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'P0001';
    END IF;

    IF length(new_pw) < 8 THEN
        RAISE EXCEPTION 'Password must be at least 8 characters' USING ERRCODE = 'P0001';
    END IF;

    SELECT encrypted_password
      INTO stored_hash
      FROM auth.users
     WHERE id = caller_id;

    IF stored_hash IS NULL THEN
        RAISE EXCEPTION 'User not found' USING ERRCODE = 'P0001';
    END IF;

    -- Verify current password against the stored bcrypt hash.
    IF stored_hash <> crypt(current_pw, stored_hash) THEN
        RAISE EXCEPTION 'Current password is incorrect' USING ERRCODE = 'P0001';
    END IF;

    UPDATE auth.users
       SET encrypted_password = crypt(new_pw, gen_salt('bf'))
     WHERE id = caller_id;
END;
$$;

-- Only authenticated users may call this; revoke from public and anon.
REVOKE ALL ON FUNCTION public.change_user_password(TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.change_user_password(TEXT, TEXT) FROM anon;
GRANT  EXECUTE ON FUNCTION public.change_user_password(TEXT, TEXT) TO authenticated;
