-- Migration: rate_limit_username_lookup
--
-- get_email_for_username is callable by anon, which means any caller who
-- knows (or can guess) a username can retrieve the associated email.
-- This is an accepted tradeoff for username-based login: the function must
-- remain anon-callable, but we mitigate bulk enumeration by adding
-- per-username rate limiting via the existing check_and_increment_rate_limit
-- infrastructure.
--
-- Limit: 5 lookups per username per 10-minute window.
-- Exceeding the limit raises SQLSTATE P0001 with message 'rate_limit_exceeded',
-- which the iOS client maps to AuthError.rateLimitExceeded.

CREATE OR REPLACE FUNCTION public.get_email_for_username(p_username TEXT)
RETURNS TABLE(email TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT check_and_increment_rate_limit(
        lower(trim(p_username)), 'username_lookup', 5, 10
    ) THEN
        RAISE EXCEPTION 'rate_limit_exceeded' USING ERRCODE = 'P0001';
    END IF;

    RETURN QUERY
    SELECT p.email
      FROM profiles p
     WHERE p.username = lower(trim(p_username))
     LIMIT 1;
END;
$$;

-- Permissions unchanged: anon and authenticated may still call this function.
REVOKE ALL ON FUNCTION public.get_email_for_username(TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.get_email_for_username(TEXT) TO anon, authenticated;
