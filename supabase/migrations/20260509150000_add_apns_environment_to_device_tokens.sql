-- Migration: add_apns_environment_to_device_tokens
-- Debug/Xcode builds produce sandbox APNs tokens; release/TestFlight builds
-- produce production tokens. The edge function must use the correct endpoint
-- (api.sandbox.push.apple.com vs api.push.apple.com) per token or Apple
-- silently drops every push — no error is returned to the sender.
--
-- Existing rows default to 'production'. iOS will re-upsert the correct value
-- on the next launch via PushNotificationService.refreshToken().

ALTER TABLE device_tokens
  ADD COLUMN IF NOT EXISTS apns_environment TEXT NOT NULL DEFAULT 'production';
