-- change_user_password called crypt()/gen_salt() unqualified, but its pinned
-- search_path (= public) can't see them: Supabase installs pgcrypto in the
-- "extensions" schema. Every call failed with
-- "function crypt(text, text) does not exist" — the RPC never worked.
-- Schema-qualify the pgcrypto calls; the hardened search_path stays.

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
    IF stored_hash <> extensions.crypt(current_pw, stored_hash) THEN
        RAISE EXCEPTION 'Current password is incorrect' USING ERRCODE = 'P0001';
    END IF;

    UPDATE auth.users
       SET encrypted_password = extensions.crypt(new_pw, extensions.gen_salt('bf'))
     WHERE id = caller_id;
END;
$$;
