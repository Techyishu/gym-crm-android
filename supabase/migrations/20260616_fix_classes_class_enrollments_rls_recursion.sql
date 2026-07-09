-- Break circular RLS dependency between classes and class_enrollments.
-- classes_select subqueries class_enrollments, whose own policy subqueries
-- classes, causing "infinite recursion detected in policy for relation classes".
-- Use a SECURITY DEFINER helper (same pattern as member_booked_class_ids()) so
-- the classes policy no longer triggers class_enrollments' RLS evaluation.

CREATE OR REPLACE FUNCTION public.member_enrolled_class_ids()
RETURNS SETOF uuid
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT class_id FROM public.class_enrollments WHERE member_id = auth_member_id();
$$;

DROP POLICY IF EXISTS classes_select ON public.classes;
CREATE POLICY classes_select ON public.classes
FOR SELECT
USING (
  gym_id = (SELECT auth_gym_id())
  OR id IN (SELECT member_enrolled_class_ids())
);
