-- Allow 'biweekly' as a bill recurrence.
--
-- `expenses_recurrence_check` (migration 20260711120000) only permits weekly/monthly/yearly,
-- so a bi-weekly bill is rejected by the INSERT regardless of what the client sends. The
-- constraint has to be dropped and re-added — Postgres has no "alter check constraint".
--
-- Widening a check constraint is safe on existing rows: every stored value is still legal,
-- so the re-add validates without a rewrite.

alter table public.expenses
  drop constraint if exists expenses_recurrence_check;

alter table public.expenses
  add constraint expenses_recurrence_check
  check (recurrence is null or recurrence in ('weekly', 'biweekly', 'monthly', 'yearly'));
