-- Reverts migration 20260929120000.
--
-- App icon badges were built on 2026-09-29 and reverted the same day: the
-- client code is gone and both push Edge Functions were redeployed without the
-- badge path, leaving this column and these two functions with no caller. The
-- deciding objection was that the counter sat on the critical path of push
-- delivery — notify-household called bump_device_badges *instead of* selecting
-- device tokens, so a failure there meant no push at all.
--
-- Forward-only rather than deleting 20260929120000: that migration is already
-- recorded as applied on the remote, so removing its file would leave the repo
-- and the database disagreeing about history.
--
-- Nothing else referenced these objects (checked: no views, policies, triggers
-- or other functions).

DROP FUNCTION IF EXISTS public.bump_device_badges(uuid[]);
DROP FUNCTION IF EXISTS public.reset_device_badge(text);

ALTER TABLE public.device_tokens
  DROP COLUMN IF EXISTS badge_count;
