-- support_tickets had RLS enabled with zero policies (default-deny for
-- everyone but service_role). Add the two a staff member actually needs:
-- file a ticket for their own gym, and see the tickets they've filed.
-- No update/delete policy — status changes are admin-only (web/service role).
create policy "Staff can create tickets for their own gym"
  on support_tickets for insert
  to authenticated
  with check (gym_id = auth_gym_id());

create policy "Staff can view their own gym's tickets"
  on support_tickets for select
  to authenticated
  using (gym_id = auth_gym_id());
