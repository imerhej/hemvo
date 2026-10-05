-- Enforce name / username minimums when a user edits their profile.
--
-- Sign-up is already validated in the `create-account` Edge Function, but
-- profile edits go straight to `profiles` over PostgREST, so the client was
-- the only gate. This trigger closes that.
--
-- Deliberately NOT a CHECK constraint: two legacy rows already violate the
-- rule (an empty username and a 1-character full_name). A CHECK would make
-- *every* future update to those rows fail — including subscription_status
-- writes from expire_lapsed_trials and verify-subscription. The trigger only
-- validates a column when that column is actually being changed, so legacy
-- rows keep working until their owner edits the offending field.

create or replace function public.validate_profile_name_username()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.full_name is distinct from old.full_name then
    if new.full_name is null or length(trim(new.full_name)) < 3 then
      raise exception 'Name must be at least 3 characters'
        using errcode = 'check_violation';
    end if;
    if length(trim(new.full_name)) > 100 then
      raise exception 'Name is too long' using errcode = 'check_violation';
    end if;
    -- [[:alpha:]] is UTF-8 aware under the database collation, so accented
    -- letters pass. Postgres regex has no \p{L}.
    if trim(new.full_name) !~ '^[[:alpha:] ''-]+$' then
      raise exception 'Name can only contain letters, spaces, hyphens and apostrophes'
        using errcode = 'check_violation';
    end if;
  end if;

  if new.username is distinct from old.username then
    if new.username is null or length(trim(new.username)) < 3 then
      raise exception 'Username must be at least 3 characters'
        using errcode = 'check_violation';
    end if;
    if length(trim(new.username)) > 30 then
      raise exception 'Username is too long' using errcode = 'check_violation';
    end if;
    if trim(new.username) !~ '^[A-Za-z0-9_]+$' then
      raise exception 'Username can only contain letters, numbers and underscores'
        using errcode = 'check_violation';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists validate_profile_name_username_trg on public.profiles;

create trigger validate_profile_name_username_trg
  before update on public.profiles
  for each row
  execute function public.validate_profile_name_username();
