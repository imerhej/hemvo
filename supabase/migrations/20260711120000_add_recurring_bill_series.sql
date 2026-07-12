-- Recurring bill series.
--
-- Before this, `is_recurring` only labelled a row as a bill: the reminder fired once
-- on the due date and the bill never rolled forward. These three columns turn it into
-- a real schedule:
--
--   recurrence    — how often the bill repeats. NULL means it does not repeat, which
--                   is every bill that already exists, so they keep their current
--                   one-shot behaviour untouched.
--   series_id     — groups every occurrence of the same bill.
--   series_anchor — the series' original due date. Every future occurrence is computed
--                   as anchor + N periods rather than by adding one period to the
--                   previous occurrence: repeatedly adding a month to Jan 31 walks to
--                   Feb 28 and then sticks on the 28th forever, whereas anchoring keeps
--                   the bill on the 31st in every month long enough to have one.

alter table public.expenses
  add column if not exists recurrence    text,
  add column if not exists series_id     uuid,
  add column if not exists series_anchor timestamptz;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'expenses_recurrence_check') then
    alter table public.expenses
      add constraint expenses_recurrence_check
      check (recurrence is null or recurrence in ('weekly', 'monthly', 'yearly'));
  end if;
end $$;

-- Two household members can roll the same series forward at the same moment. The client
-- derives each occurrence's id deterministically from (series_id, due date), so both
-- devices mint the identical row and the upsert on the primary key collapses them. This
-- index is the database-level guarantee that duplicate rent can never land even if that
-- derivation is ever changed or a client is out of date.
create unique index if not exists expenses_series_occurrence_unique
  on public.expenses (series_id, due_date)
  where series_id is not null;

create index if not exists expenses_series_id_idx
  on public.expenses (series_id)
  where series_id is not null;
