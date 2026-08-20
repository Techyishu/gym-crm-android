-- Blocks NEW inserts/phone-edits that would duplicate an existing (gym_id, phone)
-- pair. Deliberately a trigger, not a unique constraint: a unique index would
-- validate the whole table at creation time and fail on the historical
-- duplicates that already exist. This only checks going forward, leaves
-- existing duplicate rows untouched.

create or replace function block_duplicate_member_phone()
returns trigger
language plpgsql
as $$
begin
  if new.phone is not null and new.phone <> '' and exists (
    select 1 from public.members
    where gym_id = new.gym_id
      and phone = new.phone
      and id <> new.id
  ) then
    raise exception 'a member with this phone number already exists in this gym';
  end if;
  return new;
end;
$$;

create trigger members_no_duplicate_phone
before insert or update of phone on public.members
for each row execute function block_duplicate_member_phone();
