-- Migration: rate_limit_join_household_with_code
--
-- join_household_with_code had no rate limiting, unlike every other
-- sensitive RPC/Edge Function in the codebase (get_email_for_username,
-- send-invite-email, send-password-reset-email, create-account). Invite
-- codes are 8 chars from a 32-symbol alphabet (~40 bits of entropy), so
-- brute force is impractical, but an authenticated caller could still
-- hammer the RPC with no cost. Add per-caller rate limiting via the
-- existing check_and_increment_rate_limit infrastructure for
-- defense-in-depth, consistent with the rest of the codebase.
--
-- Limit: 10 attempts per caller per 10-minute window.
-- Exceeding the limit raises SQLSTATE P0001 with message 'rate_limit_exceeded',
-- matching the pattern used by get_email_for_username.

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

    IF NOT check_and_increment_rate_limit(
        v_user_id::text, 'join_household', 10, 10
    ) THEN
        RAISE EXCEPTION 'rate_limit_exceeded' USING ERRCODE = 'P0001';
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
