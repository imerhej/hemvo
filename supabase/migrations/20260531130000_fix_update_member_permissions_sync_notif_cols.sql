-- Fix: update_member_permissions should also write to the flat notif_* columns
-- so that the member's device picks up the owner's permission change on next
-- profile load (UserPreferences.seed(from:) reads those columns, not the JSONB).
--
-- Rule: when the owner DISABLES a permission, force the flat column to false.
--       When the owner ENABLES a permission, leave the flat column unchanged
--       so the member's own toggle preference is preserved.

CREATE OR REPLACE FUNCTION update_member_permissions(
  p_member_id  UUID,
  p_permissions JSONB
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM   profiles AS caller
    JOIN   profiles AS member ON member.id = p_member_id
    WHERE  caller.id            = auth.uid()
      AND  caller.household_id IS NOT NULL
      AND  caller.household_id  = member.household_id
      AND  caller.role          = 'Owner'
  ) THEN
    RAISE EXCEPTION 'update_member_permissions: caller is not the household owner';
  END IF;

  UPDATE profiles
  SET
    permissions = p_permissions,
    notif_bills = CASE
      WHEN NOT (p_permissions->>'receiveExpenseAlerts')::boolean THEN false
      ELSE notif_bills
    END,
    notif_meals = CASE
      WHEN NOT (p_permissions->>'receiveMealAlerts')::boolean THEN false
      ELSE notif_meals
    END,
    notif_schedule = CASE
      WHEN NOT (p_permissions->>'receiveCalendarAlerts')::boolean THEN false
      ELSE notif_schedule
    END,
    notif_maintenance = CASE
      WHEN NOT (p_permissions->>'receiveMaintenanceAlerts')::boolean THEN false
      ELSE notif_maintenance
    END
  WHERE id = p_member_id;
END;
$$;

GRANT EXECUTE ON FUNCTION update_member_permissions(UUID, JSONB) TO authenticated;
