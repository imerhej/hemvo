-- 20260610130000_household_invites_server_side.sql
-- Moves invite codes from client-side HMAC tokens to a server-side table.
-- The iOS app INSERTs a row when creating an invite and calls
-- join_household_with_code() when a member wants to join.

-- 1. Table

CREATE TABLE IF NOT EXISTS public.household_invites (
    id             UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    code           TEXT         NOT NULL UNIQUE,
    household_id   UUID         NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
    household_name TEXT         NOT NULL,
    inviter_name   TEXT         NOT NULL,
    invitee_email  TEXT         NOT NULL,
    role           TEXT         NOT NULL DEFAULT 'Adult',
    permissions    JSONB,
    created_by     UUID         NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    expires_at     TIMESTAMPTZ  NOT NULL,
    accepted_at    TIMESTAMPTZ,
    accepted_by    UUID         REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- Fast case-insensitive code lookup (used by the RPC with UPPER())
CREATE INDEX IF NOT EXISTS idx_household_invites_code
    ON public.household_invites (UPPER(code));

-- Fast listing of a household's pending invites
CREATE INDEX IF NOT EXISTS idx_household_invites_household_id
    ON public.household_invites (household_id);

-- 2. RLS

ALTER TABLE public.household_invites ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "owner_insert_invite"  ON public.household_invites;
DROP POLICY IF EXISTS "owner_select_invites" ON public.household_invites;
DROP POLICY IF EXISTS "owner_delete_invite"  ON public.household_invites;

-- Owner may insert invites for their own household
CREATE POLICY "owner_insert_invite" ON public.household_invites
    FOR INSERT
    WITH CHECK (
        created_by = auth.uid()
        AND EXISTS (
            SELECT 1 FROM public.households
            WHERE id = household_id
              AND owner_id = auth.uid()
        )
    );

-- Owner may read all invites for their household
CREATE POLICY "owner_select_invites" ON public.household_invites
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.households
            WHERE id = household_id
              AND owner_id = auth.uid()
        )
    );

-- Owner may revoke (delete) invites from their household
CREATE POLICY "owner_delete_invite" ON public.household_invites
    FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.households
            WHERE id = household_id
              AND owner_id = auth.uid()
        )
    );

-- No direct UPDATE policy — join_household_with_code is SECURITY DEFINER

-- 3. join_household_with_code RPC

CREATE OR REPLACE FUNCTION public.join_household_with_code(p_code TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_invite   household_invites%ROWTYPE;
    v_user_id  UUID := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'NOT_AUTHENTICATED';
    END IF;

    SELECT * INTO v_invite
    FROM household_invites
    WHERE UPPER(code) = UPPER(TRIM(p_code))
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'INVALID_CODE';
    END IF;

    IF v_invite.expires_at < now() THEN
        RAISE EXCEPTION 'EXPIRED_CODE';
    END IF;

    IF v_invite.accepted_at IS NOT NULL THEN
        RAISE EXCEPTION 'ALREADY_USED';
    END IF;

    IF EXISTS (
        SELECT 1 FROM profiles
        WHERE id = v_user_id AND household_id IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'ALREADY_MEMBER';
    END IF;

    UPDATE profiles
    SET
        household_id = v_invite.household_id,
        role         = v_invite.role,
        permissions  = v_invite.permissions
    WHERE id = v_user_id;

    UPDATE household_invites
    SET
        accepted_at = now(),
        accepted_by = v_user_id
    WHERE id = v_invite.id;

    RETURN jsonb_build_object(
        'household_id',   v_invite.household_id,
        'household_name', v_invite.household_name,
        'inviter_name',   v_invite.inviter_name,
        'role',           v_invite.role,
        'permissions',    v_invite.permissions
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.join_household_with_code(TEXT) TO authenticated;
