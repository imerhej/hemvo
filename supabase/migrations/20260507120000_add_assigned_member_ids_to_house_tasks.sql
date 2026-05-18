-- Add multi-assignee support to house_tasks.
-- assigned_member_ids supersedes assigned_to_id for new writes;
-- the old column is kept for backward-compatibility with older clients.

ALTER TABLE house_tasks
  ADD COLUMN IF NOT EXISTS assigned_member_ids UUID[] DEFAULT NULL;
