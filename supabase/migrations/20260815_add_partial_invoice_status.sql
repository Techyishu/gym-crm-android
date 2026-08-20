-- Allows an invoice to be partially paid. Previously an invoice was binary
-- paid/unpaid; 'partial' means some payments were recorded against it but
-- the full amount hasn't been collected yet.
ALTER TABLE public.invoices DROP CONSTRAINT invoices_status_check;
ALTER TABLE public.invoices ADD CONSTRAINT invoices_status_check
  CHECK (status = ANY (ARRAY['draft'::text, 'open'::text, 'partial'::text, 'paid'::text, 'failed'::text, 'void'::text]));
