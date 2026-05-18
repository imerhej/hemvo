-- All current device tokens come from debug builds (aps-environment = development).
-- Tokens that were saved before the apns_environment column existed defaulted to
-- 'production', causing BadEnvironmentKeyInToken (403) from production APNs.
-- Reset every existing token to sandbox. When real production builds ship, those
-- devices will call registerToken → saveTokenToSupabase → upsert which will
-- correctly write 'production' for that user+token pair.
UPDATE device_tokens SET apns_environment = 'sandbox';
