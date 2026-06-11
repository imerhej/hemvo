-- 20260610140000_household_invites_email_check.sql
-- Locks invite codes to the specific recipient: the joining user's email must
-- match the invitee_email stored on the invite row (case-insensitive).

CREATE OR REPLACE FUNCTION public.join_household_with_code(p_code TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_invite      household_invites%ROWTYPE;
    v_user_id     UUID := auth.uid();
    v_user_email  TEXT;
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

    -- Verify the joining user's email matches the intended recipient.
    SELECT email INTO v_user_email FROM auth.users WHERE id = v_user_id;
    IF LOWER(v_user_email) != LOWER(v_invite.invitee_email) THEN
        RAISE EXCEPTION 'EMAIL_MISMATCH';
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
