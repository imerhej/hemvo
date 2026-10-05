-- App icon badge counts for remote pushes.
--
-- APNs has no "increment the badge" payload: whatever number the push carries
-- becomes the icon's number, so the count has to be tracked server-side. Each
-- device_tokens row keeps its own counter; notify-household / process-scheduled-
-- push bump it as they send and put the new value in the aps payload. The app
-- resets its own device's counter every time it clears the badge, so local
-- reminders and remote pushes both start counting from the same baseline.
--
-- The counter is per device, not per user: two devices signed into the same
-- account are opened independently and each has its own visible badge.

ALTER TABLE public.device_tokens
  ADD COLUMN IF NOT EXISTS badge_count integer NOT NULL DEFAULT 0;

-- ── Bump (service-role only; called by the push Edge Functions) ─────────────
-- Returns the tokens to push to along with each one's new badge number, so the
-- caller needs a single round trip. The output columns are deliberately named
-- apart from the table's own columns: in a SQL-language function the output
-- parameter names are in scope in the body, so matching names would make the
-- column references inside the CTE ambiguous.
CREATE OR REPLACE FUNCTION public.bump_device_badges(p_user_ids uuid[])
RETURNS TABLE (device_token text, apns_env text, badge integer)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH bumped AS (
    UPDATE public.device_tokens d
       -- Cap it: iOS renders a very long number as an unreadable blob, and an
       -- unbounded counter on a device nobody opens is just noise.
       SET badge_count = LEAST(d.badge_count + 1, 999)
     WHERE d.user_id = ANY (p_user_ids)
    RETURNING d.token, d.apns_environment, d.badge_count
  )
  SELECT token, apns_environment, badge_count FROM bumped;
$$;

REVOKE ALL ON FUNCTION public.bump_device_badges(uuid[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.bump_device_badges(uuid[]) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.bump_device_badges(uuid[]) TO service_role;

-- ── Reset (called by the app when it clears the badge) ──────────────────────
-- Scoped to the caller's own row for the device they are running on, so one
-- user can never zero another user's (or another device's) count.
CREATE OR REPLACE FUNCTION public.reset_device_badge(p_device_id text)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.device_tokens
     SET badge_count = 0
   WHERE user_id = auth.uid()
     AND device_id = p_device_id
     AND badge_count <> 0;
$$;

REVOKE ALL ON FUNCTION public.reset_device_badge(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reset_device_badge(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.reset_device_badge(text) TO authenticated, service_role;
