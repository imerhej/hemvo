-- A device token identifies exactly one physical device + app install, so it
-- must belong to at most one user. When accounts are switched on a device, the
-- old account's device_tokens row kept pointing at the same token, so household
-- pushes aimed at the old account were delivered to whoever now uses the device
-- (observed as duplicate notifications for the expense creator).
--
-- Fix:
--   1. One-time cleanup — keep only the most recently updated row per token.
--   2. Trigger — writing a token claims it: rows for the same token under any
--      other user are deleted. SECURITY DEFINER because the registering user's
--      RLS ("Users manage own tokens") cannot delete other users' rows.

-- 1. Cleanup existing duplicates (most recent registration wins).
DELETE FROM public.device_tokens dt
WHERE dt.ctid NOT IN (
  SELECT DISTINCT ON (token) ctid
  FROM public.device_tokens
  ORDER BY token, updated_at DESC
);

-- 2. Claim the token on every registration.
CREATE OR REPLACE FUNCTION public.claim_device_token()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.device_tokens
   WHERE token = NEW.token
     AND user_id <> NEW.user_id;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_device_token() FROM PUBLIC;

DROP TRIGGER IF EXISTS claim_device_token_before_write ON public.device_tokens;
CREATE TRIGGER claim_device_token_before_write
BEFORE INSERT OR UPDATE OF token, user_id ON public.device_tokens
FOR EACH ROW EXECUTE FUNCTION public.claim_device_token();
