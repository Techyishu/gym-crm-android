-- Per-branch invoice configuration, immutable issue-time snapshots, and an
-- atomic monotonically increasing invoice number.

create table public.gym_invoice_settings (
  gym_id uuid primary key references public.gyms(id) on delete cascade,
  gym_name text,
  logo_url text,
  owner_name text,
  contact_email text,
  contact_phone text,
  address text,
  gstin text,
  invoice_prefix text not null default 'INV'
    check (invoice_prefix ~ '^[A-Z0-9][A-Z0-9/-]{0,15}$'),
  number_padding smallint not null default 6 check (number_padding between 3 and 10),
  show_invoice_date boolean not null default true,
  show_generated_date boolean not null default true,
  show_membership_id boolean not null default true,
  show_admission_fee boolean not null default true,
  show_discount boolean not null default true,
  show_gst_breakup boolean not null default false,
  gst_percent numeric(6,3) not null default 0 check (gst_percent between 0 and 100),
  refund_policy text,
  terms_and_conditions text,
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);

create table public.gym_invoice_counters (
  gym_id uuid primary key references public.gyms(id) on delete cascade,
  next_number bigint not null default 1 check (next_number > 0),
  updated_at timestamptz not null default now()
);

alter table public.gym_invoice_settings enable row level security;
alter table public.gym_invoice_counters enable row level security;
revoke all on table public.gym_invoice_settings from anon, authenticated;
revoke all on table public.gym_invoice_counters from anon, authenticated;
grant select on table public.gym_invoice_settings to authenticated;

-- Invoice logos live in the existing public gym-logos bucket. Object writes
-- follow the same fine-grained Settings permission as the configuration RPC.
drop policy if exists "gym staff can upload logo" on storage.objects;
drop policy if exists "gym staff can update logo" on storage.objects;
drop policy if exists "gym staff can delete logo" on storage.objects;
create policy invoice_logo_read on storage.objects for select to authenticated
using (
  bucket_id = 'gym-logos'
  and private.has_gym_permission(
    case when (storage.foldername(name))[1] ~
      '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
      then ((storage.foldername(name))[1])::uuid end,
    'settings', 'view'
  )
);
create policy invoice_logo_insert on storage.objects for insert to authenticated
with check (
  bucket_id = 'gym-logos'
  and private.has_gym_permission(
    case when (storage.foldername(name))[1] ~
      '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
      then ((storage.foldername(name))[1])::uuid end,
    'settings', 'edit'
  )
);
create policy invoice_logo_update on storage.objects for update to authenticated
using (
  bucket_id = 'gym-logos'
  and private.has_gym_permission(
    case when (storage.foldername(name))[1] ~
      '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
      then ((storage.foldername(name))[1])::uuid end,
    'settings', 'edit'
  )
)
with check (
  bucket_id = 'gym-logos'
  and private.has_gym_permission(
    case when (storage.foldername(name))[1] ~
      '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
      then ((storage.foldername(name))[1])::uuid end,
    'settings', 'edit'
  )
);
create policy invoice_logo_delete on storage.objects for delete to authenticated
using (
  bucket_id = 'gym-logos'
  and private.has_gym_permission(
    case when (storage.foldername(name))[1] ~
      '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
      then ((storage.foldername(name))[1])::uuid end,
    'settings', 'edit'
  )
);

-- PDF objects are named <invoice UUID>.pdf. Replace the legacy bucket-wide
-- write policies so an authenticated user cannot overwrite another gym's PDF.
drop policy if exists "Staff can upload invoice PDFs" on storage.objects;
drop policy if exists "Staff can update invoice PDFs" on storage.objects;
create policy invoice_pdf_insert on storage.objects for insert to authenticated
with check (
  bucket_id = 'invoice-pdfs' and exists (
    select 1
    from public.invoices i
    join public.members m on m.id = i.member_id
    where i.id = case
      when replace(storage.filename(name), '.pdf', '') ~
        '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
      then replace(storage.filename(name), '.pdf', '')::uuid
    end
      and (
        private.has_gym_permission(i.gym_id, 'payments', 'view')
        or m.user_id = auth.uid()
      )
  )
);
create policy invoice_pdf_update on storage.objects for update to authenticated
using (
  bucket_id = 'invoice-pdfs' and exists (
    select 1
    from public.invoices i
    join public.members m on m.id = i.member_id
    where i.id = case
      when replace(storage.filename(name), '.pdf', '') ~
        '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
      then replace(storage.filename(name), '.pdf', '')::uuid
    end
      and (
        private.has_gym_permission(i.gym_id, 'payments', 'view')
        or m.user_id = auth.uid()
      )
  )
)
with check (bucket_id = 'invoice-pdfs');

create policy gym_invoice_settings_read
on public.gym_invoice_settings for select to authenticated
using (
  (select private.has_gym_permission(gym_id, 'settings', 'view'))
  or (select private.has_gym_permission(gym_id, 'payments', 'view'))
);

insert into public.gym_invoice_settings (
  gym_id, gym_name, logo_url, owner_name, contact_email, contact_phone,
  address, gstin, invoice_prefix, refund_policy, terms_and_conditions
)
select
  g.id,
  g.name,
  nullif(g.settings ->> 'logo_url', ''),
  nullif(g.settings ->> 'owner_name', ''),
  nullif(g.settings ->> 'email', ''),
  nullif(coalesce(g.settings ->> 'phone', ''), ''),
  nullif(g.settings ->> 'address', ''),
  nullif(g.settings ->> 'gstin', ''),
  coalesce(nullif(upper(regexp_replace(g.settings ->> 'invoice_prefix', '[^A-Za-z0-9/-]', '', 'g')), ''), 'INV'),
  nullif(g.settings ->> 'refund_policy', ''),
  nullif(g.settings ->> 'terms_and_conditions', '')
from public.gyms g
on conflict (gym_id) do nothing;

insert into public.gym_invoice_counters (gym_id, next_number)
select id, 1 from public.gyms
on conflict (gym_id) do nothing;

alter table public.invoices
  add column invoice_number text,
  add column issued_at timestamptz,
  add column generated_at timestamptz,
  add column settings_snapshot jsonb,
  add column member_snapshot jsonb,
  add column membership_id_snapshot text,
  add column admission_fee numeric not null default 0 check (admission_fee >= 0),
  add column taxable_amount numeric,
  add column gst_amount numeric not null default 0 check (gst_amount >= 0),
  add column cgst_amount numeric not null default 0 check (cgst_amount >= 0),
  add column sgst_amount numeric not null default 0 check (sgst_amount >= 0),
  add column igst_amount numeric not null default 0 check (igst_amount >= 0);

-- Existing invoices receive deterministic historical numbers ordered by their
-- original creation time. Their snapshots are frozen at migration time.
with numbered as (
  select i.id,
         row_number() over (partition by i.gym_id order by i.created_at, i.id) as seq
  from public.invoices i
)
update public.invoices i
set invoice_number = s.invoice_prefix || '-' || lpad(n.seq::text, s.number_padding, '0'),
    issued_at = i.created_at,
    generated_at = i.created_at,
    membership_id_snapshot = coalesce(m.custom_id, m.id::text),
    member_snapshot = jsonb_strip_nulls(jsonb_build_object(
      'name', trim(m.first_name || ' ' || coalesce(m.last_name, '')),
      'email', m.email,
      'phone', m.phone,
      'membership_id', coalesce(m.custom_id, m.id::text),
      'joined_at', m.joined_at
    )),
    settings_snapshot = jsonb_strip_nulls(jsonb_build_object(
      'gym_name', coalesce(s.gym_name, g.name),
      'logo_url', s.logo_url,
      'owner_name', s.owner_name,
      'contact_email', s.contact_email,
      'contact_phone', s.contact_phone,
      'address', s.address,
      'gstin', s.gstin,
      'invoice_prefix', s.invoice_prefix,
      'show_invoice_date', s.show_invoice_date,
      'show_generated_date', s.show_generated_date,
      'show_membership_id', s.show_membership_id,
      'show_admission_fee', s.show_admission_fee,
      'show_discount', s.show_discount,
      'show_gst_breakup', s.show_gst_breakup,
      'gst_percent', s.gst_percent,
      'refund_policy', s.refund_policy,
      'terms_and_conditions', s.terms_and_conditions
    ))
from numbered n, public.gyms g, public.gym_invoice_settings s, public.members m
where i.id = n.id
  and g.id = i.gym_id
  and s.gym_id = i.gym_id
  and m.id = i.member_id;

update public.gym_invoice_counters c
set next_number = counts.invoice_count + 1,
    updated_at = now()
from (
  select gym_id, count(*)::bigint as invoice_count
  from public.invoices group by gym_id
) counts
where counts.gym_id = c.gym_id;

alter table public.invoices
  alter column invoice_number set not null,
  alter column issued_at set not null,
  alter column generated_at set not null,
  alter column settings_snapshot set not null,
  alter column member_snapshot set not null;

create unique index invoices_gym_invoice_number_key
  on public.invoices (gym_id, invoice_number);

create or replace function private.seed_gym_invoice_settings()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.gym_invoice_settings (gym_id, gym_name)
  values (new.id, new.name)
  on conflict (gym_id) do nothing;
  insert into public.gym_invoice_counters (gym_id, next_number)
  values (new.id, 1)
  on conflict (gym_id) do nothing;
  return new;
end;
$$;

drop trigger if exists gyms_seed_invoice_settings on public.gyms;
create trigger gyms_seed_invoice_settings
after insert on public.gyms
for each row execute function private.seed_gym_invoice_settings();

create or replace function private.assign_invoice_identity_and_snapshot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_settings public.gym_invoice_settings%rowtype;
  v_gym_name text;
  v_number bigint;
  v_member public.members%rowtype;
  v_taxable numeric;
  v_gst numeric;
begin
  select * into v_settings from public.gym_invoice_settings where gym_id = new.gym_id;
  if not found then
    insert into public.gym_invoice_settings (gym_id)
    values (new.gym_id) returning * into v_settings;
  end if;

  select g.name into v_gym_name from public.gyms g where g.id = new.gym_id;
  select * into v_member from public.members m
  where m.id = new.member_id and m.gym_id = new.gym_id;
  if not found then raise exception 'member_not_in_gym'; end if;

  insert into public.gym_invoice_counters (gym_id, next_number)
  values (new.gym_id, 2)
  on conflict (gym_id) do update set
    next_number = public.gym_invoice_counters.next_number + 1,
    updated_at = now()
  returning next_number - 1 into v_number;

  new.invoice_number := v_settings.invoice_prefix || '-' || lpad(v_number::text, v_settings.number_padding, '0');
  new.issued_at := coalesce(new.issued_at, new.created_at, now());
  new.generated_at := coalesce(new.generated_at, now());
  new.membership_id_snapshot := coalesce(new.membership_id_snapshot, v_member.custom_id, v_member.id::text);
  new.member_snapshot := jsonb_strip_nulls(jsonb_build_object(
    'name', trim(v_member.first_name || ' ' || coalesce(v_member.last_name, '')),
    'email', v_member.email,
    'phone', v_member.phone,
    'membership_id', new.membership_id_snapshot,
    'joined_at', v_member.joined_at
  ));
  new.settings_snapshot := jsonb_strip_nulls(jsonb_build_object(
    'gym_name', coalesce(v_settings.gym_name, v_gym_name),
    'logo_url', v_settings.logo_url,
    'owner_name', v_settings.owner_name,
    'contact_email', v_settings.contact_email,
    'contact_phone', v_settings.contact_phone,
    'address', v_settings.address,
    'gstin', v_settings.gstin,
    'invoice_prefix', v_settings.invoice_prefix,
    'show_invoice_date', v_settings.show_invoice_date,
    'show_generated_date', v_settings.show_generated_date,
    'show_membership_id', v_settings.show_membership_id,
    'show_admission_fee', v_settings.show_admission_fee,
    'show_discount', v_settings.show_discount,
    'show_gst_breakup', v_settings.show_gst_breakup,
    'gst_percent', v_settings.gst_percent,
    'refund_policy', v_settings.refund_policy,
    'terms_and_conditions', v_settings.terms_and_conditions
  ));

  if v_settings.show_gst_breakup and v_settings.gst_percent > 0 then
    v_taxable := round(new.amount / (1 + v_settings.gst_percent / 100), 2);
    v_gst := greatest(round(new.amount - v_taxable, 2), 0);
    new.taxable_amount := v_taxable;
    new.gst_amount := v_gst;
    new.cgst_amount := round(v_gst / 2, 2);
    new.sgst_amount := v_gst - new.cgst_amount;
    new.igst_amount := 0;
  else
    new.taxable_amount := new.amount;
    new.gst_amount := 0;
    new.cgst_amount := 0;
    new.sgst_amount := 0;
    new.igst_amount := 0;
  end if;
  return new;
end;
$$;

drop trigger if exists invoices_assign_identity_snapshot on public.invoices;
create trigger invoices_assign_identity_snapshot
before insert on public.invoices
for each row execute function private.assign_invoice_identity_and_snapshot();

create or replace function private.protect_invoice_history()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.gym_id is distinct from old.gym_id
     or new.member_id is distinct from old.member_id
     or new.invoice_number is distinct from old.invoice_number
     or new.issued_at is distinct from old.issued_at
     or new.generated_at is distinct from old.generated_at
     or new.settings_snapshot is distinct from old.settings_snapshot
     or new.member_snapshot is distinct from old.member_snapshot
     or new.membership_id_snapshot is distinct from old.membership_id_snapshot then
    raise exception 'issued_invoice_history_is_immutable';
  end if;
  return new;
end;
$$;

drop trigger if exists invoices_history_guard on public.invoices;
create trigger invoices_history_guard
before update on public.invoices
for each row execute function private.protect_invoice_history();

create or replace function public.get_invoice_settings(p_gym_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_settings jsonb;
begin
  if not private.has_gym_permission(p_gym_id, 'settings', 'view')
     and not private.has_gym_permission(p_gym_id, 'payments', 'view') then
    raise exception 'permission_denied';
  end if;
  select to_jsonb(s) into v_settings from public.gym_invoice_settings s where s.gym_id = p_gym_id;
  return coalesce(v_settings, '{}'::jsonb);
end;
$$;
revoke all on function public.get_invoice_settings(uuid) from public, anon;
grant execute on function public.get_invoice_settings(uuid) to authenticated;

create or replace function public.update_invoice_settings(
  p_gym_id uuid,
  p_settings jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text;
  v_result jsonb;
  v_prefix text;
begin
  select sga.role into v_role from public.staff_gym_access sga
  where sga.profile_id = auth.uid() and sga.gym_id = p_gym_id;
  if v_role not in ('owner', 'manager')
     or not private.has_gym_permission(p_gym_id, 'settings', 'edit') then
    raise exception 'permission_denied';
  end if;

  v_prefix := upper(coalesce(nullif(trim(p_settings ->> 'invoice_prefix'), ''), 'INV'));
  if v_prefix !~ '^[A-Z0-9][A-Z0-9/-]{0,15}$' then
    raise exception 'invalid_invoice_prefix';
  end if;

  insert into public.gym_invoice_settings (
    gym_id, gym_name, logo_url, owner_name, contact_email, contact_phone,
    address, gstin, invoice_prefix, number_padding, show_invoice_date,
    show_generated_date, show_membership_id, show_admission_fee,
    show_discount, show_gst_breakup, gst_percent, refund_policy,
    terms_and_conditions, updated_by, updated_at
  ) values (
    p_gym_id,
    nullif(trim(p_settings ->> 'gym_name'), ''),
    nullif(trim(p_settings ->> 'logo_url'), ''),
    nullif(trim(p_settings ->> 'owner_name'), ''),
    nullif(trim(p_settings ->> 'contact_email'), ''),
    nullif(trim(p_settings ->> 'contact_phone'), ''),
    nullif(trim(p_settings ->> 'address'), ''),
    nullif(upper(trim(p_settings ->> 'gstin')), ''),
    v_prefix,
    coalesce((p_settings ->> 'number_padding')::smallint, 6),
    coalesce((p_settings ->> 'show_invoice_date')::boolean, true),
    coalesce((p_settings ->> 'show_generated_date')::boolean, true),
    coalesce((p_settings ->> 'show_membership_id')::boolean, true),
    coalesce((p_settings ->> 'show_admission_fee')::boolean, true),
    coalesce((p_settings ->> 'show_discount')::boolean, true),
    coalesce((p_settings ->> 'show_gst_breakup')::boolean, false),
    coalesce((p_settings ->> 'gst_percent')::numeric, 0),
    nullif(trim(p_settings ->> 'refund_policy'), ''),
    nullif(trim(p_settings ->> 'terms_and_conditions'), ''),
    auth.uid(), now()
  ) on conflict (gym_id) do update set
    gym_name = excluded.gym_name,
    logo_url = excluded.logo_url,
    owner_name = excluded.owner_name,
    contact_email = excluded.contact_email,
    contact_phone = excluded.contact_phone,
    address = excluded.address,
    gstin = excluded.gstin,
    invoice_prefix = excluded.invoice_prefix,
    number_padding = excluded.number_padding,
    show_invoice_date = excluded.show_invoice_date,
    show_generated_date = excluded.show_generated_date,
    show_membership_id = excluded.show_membership_id,
    show_admission_fee = excluded.show_admission_fee,
    show_discount = excluded.show_discount,
    show_gst_breakup = excluded.show_gst_breakup,
    gst_percent = excluded.gst_percent,
    refund_policy = excluded.refund_policy,
    terms_and_conditions = excluded.terms_and_conditions,
    updated_by = excluded.updated_by,
    updated_at = excluded.updated_at;

  perform private.write_activity_log(
    p_gym_id, 'settings', 'invoice_settings_changed', 'gym', p_gym_id,
    'Invoice settings', null,
    jsonb_build_object(
      'invoice_prefix', v_prefix,
      'show_gst_breakup', coalesce((p_settings ->> 'show_gst_breakup')::boolean, false),
      'gst_percent', coalesce((p_settings ->> 'gst_percent')::numeric, 0)
    )
  );
  select to_jsonb(s) into v_result from public.gym_invoice_settings s where s.gym_id = p_gym_id;
  return v_result;
end;
$$;
revoke all on function public.update_invoice_settings(uuid, jsonb) from public, anon;
grant execute on function public.update_invoice_settings(uuid, jsonb) to authenticated;

create or replace function public.create_invoice_secure(
  p_gym_id uuid,
  p_member_id uuid,
  p_membership_amount numeric,
  p_discount_amount numeric default 0,
  p_admission_fee numeric default 0,
  p_description text default null,
  p_due_at timestamptz default null,
  p_notes text default null
) returns public.invoices
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_invoice public.invoices%rowtype;
  v_original numeric;
  v_total numeric;
begin
  if not private.has_gym_permission(p_gym_id, 'payments', 'add') then
    raise exception 'permission_denied';
  end if;
  if not exists (select 1 from public.members m where m.id = p_member_id and m.gym_id = p_gym_id) then
    raise exception 'member_not_in_gym';
  end if;
  if p_membership_amount is null or p_membership_amount < 0
     or coalesce(p_discount_amount, 0) < 0
     or coalesce(p_admission_fee, 0) < 0 then
    raise exception 'invalid_invoice_amount';
  end if;

  v_original := p_membership_amount;
  v_total := greatest(
    v_original + coalesce(p_admission_fee, 0) - coalesce(p_discount_amount, 0),
    0
  );
  if v_total <= 0 then raise exception 'invoice_total_must_be_positive'; end if;

  insert into public.invoices (
    gym_id, member_id, original_amount, discount_amount, admission_fee,
    amount, description, due_at, notes, status
  ) values (
    p_gym_id, p_member_id, v_original, coalesce(p_discount_amount, 0),
    coalesce(p_admission_fee, 0), v_total, nullif(trim(p_description), ''),
    p_due_at, nullif(trim(p_notes), ''), 'open'
  ) returning * into v_invoice;
  return v_invoice;
end;
$$;
revoke all on function public.create_invoice_secure(uuid, uuid, numeric, numeric, numeric, text, timestamptz, text)
  from public, anon;
grant execute on function public.create_invoice_secure(uuid, uuid, numeric, numeric, numeric, text, timestamptz, text)
  to authenticated;
