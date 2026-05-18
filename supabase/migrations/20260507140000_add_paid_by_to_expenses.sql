-- Add paid_by to track which household member marked a bill as paid.
ALTER TABLE expenses
  ADD COLUMN IF NOT EXISTS paid_by UUID REFERENCES auth.users(id) ON DELETE SET NULL;
