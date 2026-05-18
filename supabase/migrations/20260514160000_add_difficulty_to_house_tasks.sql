-- Add difficulty level to house_tasks so all household members can see
-- the age-appropriateness of a task set by the creator.
-- Defaults to 'medium' so existing rows are unaffected.

ALTER TABLE house_tasks
  ADD COLUMN IF NOT EXISTS difficulty TEXT NOT NULL DEFAULT 'Medium';

-- Constrain to the three valid Swift enum raw values.
ALTER TABLE house_tasks
  ADD CONSTRAINT house_tasks_difficulty_check
  CHECK (difficulty IN ('Easy', 'Medium', 'Hard'));
