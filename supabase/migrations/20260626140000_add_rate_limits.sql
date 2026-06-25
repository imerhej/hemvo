-- Rate limiting for unauthenticated Edge Functions (create-account,
-- send-password-reset-email) and authenticated ones (send-invite-email).
-- Access is only via the SECURITY DEFINER function; direct table access is
-- denied through RLS with no permissive policies.

CREATE TABLE IF NOT EXISTS rate_limits (
  key          TEXT        NOT NULL,
  action       TEXT        NOT NULL,
  count        INTEGER     NOT NULL DEFAULT 0,
  window_start TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (key, action)
);

ALTER TABLE rate_limits ENABLE ROW LEVEL SECURITY;

-- Returns TRUE when the caller is within the limit, FALSE when exceeded.
-- Atomically upserts the (key, action) row, resetting the window when expired.
CREATE OR REPLACE FUNCTION check_and_increment_rate_limit(
  p_key            TEXT,
  p_action         TEXT,
  p_max_count      INTEGER,
  p_window_minutes INTEGER
)
RETURNS BOOLEAN
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql AS $$
DECLARE
  v_window_cutoff TIMESTAMPTZ;
  v_count         INTEGER;
BEGIN
  v_window_cutoff := NOW() - (p_window_minutes || ' minutes')::INTERVAL;

  INSERT INTO rate_limits (key, action, count, window_start)
  VALUES (p_key, p_action, 1, NOW())
  ON CONFLICT (key, action) DO UPDATE
    SET
      count        = CASE
                       WHEN rate_limits.window_start < v_window_cutoff THEN 1
                       ELSE rate_limits.count + 1
                     END,
      window_start = CASE
                       WHEN rate_limits.window_start < v_window_cutoff THEN NOW()
                       ELSE rate_limits.window_start
                     END
  RETURNING count INTO v_count;

  RETURN v_count <= p_max_count;
END;
$$;
