-- Void / delete an invoice from the app.
--
-- Deleting an invoice that has payments used to fail with `permission_denied`
-- even for the owner: the payments cascade fires payments_permission_guard,
-- which looks the (already deleted) invoice up to find the gym and finds
-- nothing. delete_invoice_secure() sets the same `gymcrm.delete_actor_id`
-- context secure member delete uses, which the guard already honours.
--
--   invoice_has_paid_twin  — another non-void invoice, same member + amount +
--                            day, that is paid/partial: the money is still on
--                            record there, so removing this one is a correction.
--   void_invoice_secure    — keeps the number and history, drops it from dues.
--   delete_invoice_secure  — unpaid: always. Paid/partial/with payments: only
--                            when a paid twin exists, and only for roles with
--                            payments.delete (owner by default).

create or replace function public.invoice_has_paid_twin(p_invoice_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v public.invoices%rowtype;
begin
  select * into v from public.invoices where id = p_invoice_id;
  if not found then return false; end if;
  if not private.has_gym_permission(v.gym_id, 'payments', 'view') then
    raise exception 'permission_denied';
  end if;
  return exists (
    select 1
    from public.invoices o
    where o.id <> v.id
      and o.gym_id = v.gym_id
      and o.member_id = v.member_id
      and o.amount = v.amount
      and o.created_at::date = v.created_at::date
      and o.status in ('paid', 'partial')
  );
end;
$$;

create or replace function public.void_invoice_secure(
  p_invoice_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.invoices%rowtype;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  select * into v from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'invoice_not_found'; end if;
  if not private.has_gym_permission(v.gym_id, 'payments', 'edit') then
    raise exception 'permission_denied';
  end if;
  if v.status not in ('draft', 'open', 'partial', 'failed') then
    raise exception 'invoice_not_voidable';
  end if;
  if v_reason is null then raise exception 'reason_required'; end if;

  update public.invoices
     set status = 'void',
         notes = btrim(coalesce(notes, '') || E'\nVoided: ' || v_reason, E'\n')
   where id = v.id;
end;
$$;

create or replace function public.delete_invoice_secure(p_invoice_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.invoices%rowtype;
  v_has_money boolean;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  select * into v from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'invoice_not_found'; end if;
  if not private.has_gym_permission(v.gym_id, 'payments', 'delete') then
    raise exception 'permission_denied';
  end if;

  v_has_money := v.status in ('paid', 'partial')
    or exists (select 1 from public.payments p where p.invoice_id = v.id);
  if v_has_money and not public.invoice_has_paid_twin(v.id) then
    raise exception 'only_bill_cannot_delete';
  end if;

  perform set_config('gymcrm.delete_actor_id', auth.uid()::text, true);
  delete from public.invoices where id = v.id;
  perform set_config('gymcrm.delete_actor_id', '', true);
end;
$$;

revoke all on function public.invoice_has_paid_twin(uuid) from public, anon;
revoke all on function public.void_invoice_secure(uuid, text) from public, anon;
revoke all on function public.delete_invoice_secure(uuid) from public, anon;
grant execute on function public.invoice_has_paid_twin(uuid) to authenticated;
grant execute on function public.void_invoice_secure(uuid, text) to authenticated;
grant execute on function public.delete_invoice_secure(uuid) to authenticated;
