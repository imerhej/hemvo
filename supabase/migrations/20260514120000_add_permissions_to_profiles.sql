-- Add per-member notification permissions to profiles.
-- Stored as JSONB so the shape can evolve without schema migrations.
-- NULL means "use role-based defaults" (resolved client-side in MemberPermissions.defaults(for:)).

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS permissions JSONB DEFAULT NULL;
