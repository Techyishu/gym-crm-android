-- Secure RPC for adding purchased WhatsApp credits (used by the Dodo webhook
-- after a credit-pack payment succeeds). Avoids needing a read-then-write
-- round trip from the webhook handler.
create or replace function increment_whatsapp_credits(p_gym_id uuid, p_amount integer)
returns void
language sql
security definer
set search_path = public
as $$
  update gyms set whatsapp_credits = whatsapp_credits + p_amount where id = p_gym_id;
$$;
