import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info",
};

const url = Deno.env.get("SUPABASE_URL")!;
const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const adminClient = createClient(url, serviceKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});

type Admin = {
  id: string;
  email: string | null;
  full_name: string | null;
  role: "admin" | "superadmin";
  is_active: boolean;
  require_mfa: boolean;
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function jwtAal(token: string): string {
  try {
    const raw = token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    const padded = raw.padEnd(Math.ceil(raw.length / 4) * 4, "=");
    return JSON.parse(atob(padded)).aal ?? "aal1";
  } catch {
    return "aal1";
  }
}

async function authenticate(req: Request): Promise<
  | { token: string; admin: Admin; aal: string }
  | Response
> {
  const authorization = req.headers.get("Authorization") ?? "";
  const token = authorization.startsWith("Bearer ")
    ? authorization.slice(7)
    : "";
  if (!token) return json({ error: "Authentication required" }, 401);

  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: { user }, error: userError } = await userClient.auth.getUser(
    token,
  );
  if (userError || !user) return json({ error: "Invalid session" }, 401);

  const { data: admin, error: adminError } = await adminClient
    .from("platform_admins")
    .select("id,email,full_name,role,is_active,require_mfa")
    .eq("id", user.id)
    .eq("is_active", true)
    .maybeSingle();
  if (adminError || !admin) {
    return json({ error: "Super-admin access denied" }, 403);
  }

  return { token, admin: admin as Admin, aal: jwtAal(token) };
}

function can(admin: Admin, allowed: string[]): boolean {
  if (admin.role === "superadmin") return true;
  return allowed.includes("support") || allowed.includes("viewer");
}

function requireSuperadmin(admin: Admin): Response | null {
  return admin.role === "superadmin"
    ? null
    : json({ error: "Super-admin permission required" }, 403);
}

function requiredText(value: unknown, name: string, min = 1): string {
  if (typeof value !== "string" || value.trim().length < min) {
    throw new Error(`${name} is required`);
  }
  return value.trim();
}

function requiredUuid(value: unknown, name = "gymId"): string {
  const text = requiredText(value, name);
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(text)
  ) {
    throw new Error(`${name} is invalid`);
  }
  return text;
}

async function audit(
  admin: Admin,
  gymId: string | null,
  action: string,
  reason: string | null,
  beforeState: unknown,
  afterState: unknown,
) {
  const { error } = await adminClient.from("platform_admin_audit_log").insert({
    admin_id: admin.id,
    gym_id: gymId,
    action,
    reason,
    before_state: beforeState,
    after_state: afterState,
  });
  if (error) throw new Error(`Audit write failed: ${error.message}`);
}

async function directory() {
  const { data, error } = await adminClient.rpc("platform_admin_gym_directory");
  if (error) throw error;
  return data ?? [];
}

async function listAllUsers() {
  const users: Record<string, any>[] = [];
  for (let page = 1; page <= 100; page++) {
    const { data, error } = await adminClient.auth.admin.listUsers({
      page,
      perPage: 1000,
    });
    if (error) throw error;
    users.push(...data.users);
    if (data.users.length < 1000) break;
  }
  return users;
}

function startOfMonth(value = new Date()) {
  return new Date(Date.UTC(value.getUTCFullYear(), value.getUTCMonth(), 1));
}

function monthKey(value: Date) {
  return `${value.getUTCFullYear()}-${String(value.getUTCMonth() + 1).padStart(2, "0")}`;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const auth = await authenticate(req);
  if (auth instanceof Response) return auth;

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const action = body.action;
  if (typeof action !== "string") {
    return json({ error: "Action is required" }, 400);
  }

  if (action === "me") {
    return json({
      admin: auth.admin,
      aal: auth.aal,
      requiresMfa: auth.admin.require_mfa && auth.aal !== "aal2",
    });
  }
  if (auth.admin.require_mfa && auth.aal !== "aal2") {
    return json(
      { error: "MFA verification required", code: "mfa_required" },
      403,
    );
  }

  try {
    if (action === "listGyms") {
      if (!can(auth.admin, ["operations", "support", "finance", "viewer"])) {
        return json({ error: "Permission denied" }, 403);
      }
      return json({ gyms: await directory() });
    }

    if (action === "dashboard") {
      if (!can(auth.admin, ["operations", "support", "finance", "viewer"])) {
        return json({ error: "Permission denied" }, 403);
      }
      const now = new Date();
      const nowIso = now.toISOString();
      const monthStart = startOfMonth(now).toISOString();
      const sixMonthsAgo = new Date(Date.UTC(
        now.getUTCFullYear(),
        now.getUTCMonth() - 5,
        1,
      )).toISOString();
      const dayAgo = new Date(now.getTime() - 86400000).toISOString();
      const [
        gymsResult,
        membersResult,
        newMembersResult,
        invoicesResult,
        ticketsResult,
        errorsResult,
      ] = await Promise.all([
        adminClient.from("gyms").select(
          "id,name,plan,plan_price,plan_expires_at,trial_ends_at,status,created_at",
        ).order("created_at", { ascending: false }),
        adminClient.from("members").select("id", { count: "exact", head: true })
          .eq("is_demo_data", false),
        adminClient.from("members").select("id", { count: "exact", head: true })
          .eq("is_demo_data", false).gte("joined_at", monthStart),
        adminClient.from("invoices").select("amount,paid_at")
          .eq("status", "paid").eq("is_demo_data", false)
          .gte("paid_at", sixMonthsAgo),
        adminClient.from("support_tickets").select("id", {
          count: "exact",
          head: true,
        }).in("status", ["new", "in_progress"]),
        adminClient.from("error_logs").select("id", {
          count: "exact",
          head: true,
        }).gte("created_at", dayAgo),
      ]);
      for (const result of [
        gymsResult,
        membersResult,
        newMembersResult,
        invoicesResult,
        ticketsResult,
        errorsResult,
      ]) if (result.error) throw result.error;

      const gyms = gymsResult.data ?? [];
      const payingGyms = gyms.filter((gym) =>
        gym.plan === "pro" && gym.status === "active" &&
        (!gym.plan_expires_at || gym.plan_expires_at > nowIso)
      );
      const revenueByMonth = Array.from({ length: 6 }, (_, index) => {
        const date = new Date(Date.UTC(
          now.getUTCFullYear(),
          now.getUTCMonth() - (5 - index),
          1,
        ));
        return { month: monthKey(date), revenue: 0 };
      });
      for (const invoice of invoicesResult.data ?? []) {
        if (!invoice.paid_at) continue;
        const key = monthKey(new Date(invoice.paid_at));
        const bucket = revenueByMonth.find((item) => item.month === key);
        if (bucket) bucket.revenue += Number(invoice.amount ?? 0);
      }
      const lapsedThisMonth = gyms.filter((gym) =>
        gym.plan_expires_at && gym.plan_expires_at >= monthStart &&
        gym.plan_expires_at < nowIso
      ).length;
      return json({
        gyms: gyms.length,
        members: membersResult.count ?? 0,
        paidGyms: payingGyms.length,
        trialGyms: gyms.filter((gym) =>
          gym.plan !== "pro" && gym.trial_ends_at && gym.trial_ends_at > nowIso
        ).length,
        newGymsThisMonth: gyms.filter((gym) => gym.created_at >= monthStart)
          .length,
        newMembersThisMonth: newMembersResult.count ?? 0,
        lapsedThisMonth,
        mrr: payingGyms.reduce(
          (sum, gym) => sum + Number(gym.plan_price ?? 0),
          0,
        ),
        revenueByMonth,
        openTickets: ticketsResult.count ?? 0,
        errors24h: errorsResult.count ?? 0,
        recentGyms: gyms.slice(0, 5),
      });
    }

    if (action === "gymDetail") {
      const gymId = requiredUuid(body.gymId);
      const [directoryRows, gymResult, membersResult] = await Promise.all([
        directory(),
        adminClient.from("gyms").select(
          "id,name,slug,owner_id,plan,plan_price,plan_started_at,plan_expires_at,trial_ends_at,status,settings,whatsapp_monthly_quota_used,whatsapp_credits,created_at",
        ).eq("id", gymId).single(),
        adminClient.from("members").select(
          "id,first_name,last_name,email,phone,status,joined_at,is_demo_data",
        ).eq("gym_id", gymId).order("joined_at", { ascending: false }),
      ]);
      if (gymResult.error || !gymResult.data) {
        return json({ error: "Gym not found" }, 404);
      }
      if (membersResult.error) throw membersResult.error;
      const gym = directoryRows.find((item: { id: string }) =>
        item.id === gymId
      );
      const rawGym = gymResult.data;
      const members = membersResult.data ?? [];
      const memberIds = members.map((member) => member.id);
      const monthStart = startOfMonth().toISOString();

      const [
        memberships,
        invoices,
        checkIns,
        ownerProfile,
        ownerAuth,
        notes,
        events,
        overrides,
        tickets,
        staff,
        branches,
      ] = await Promise.all([
        memberIds.length
          ? adminClient.from("memberships").select(
            "id,member_id,status,starts_at,ends_at,cancelled_at,membership_plans(name,price,billing_interval)",
          ).in("member_id", memberIds).order("starts_at", { ascending: false })
          : Promise.resolve({ data: [], error: null }),
        adminClient.from("invoices").select(
          "id,member_id,amount,status,due_at,paid_at,created_at,description",
        ).eq("gym_id", gymId).eq("is_demo_data", false)
          .order("created_at", { ascending: false }).limit(100),
        adminClient.from("check_ins").select(
          "id,member_id,checked_in_at,checked_out_at,method",
        ).eq("gym_id", gymId).eq("is_demo_data", false)
          .order("checked_in_at", { ascending: false }).limit(100),
        adminClient.from("profiles").select(
          "id,first_name,last_name,phone",
        ).eq("id", rawGym.owner_id).maybeSingle(),
        adminClient.auth.admin.getUserById(rawGym.owner_id),
        adminClient.from("customer_notes")
          .select("id,body,pinned,created_at,platform_admins(full_name,email)")
          .eq("gym_id", gymId).order("created_at", { ascending: false }).limit(
            50,
          ),
        adminClient.from("activity_events")
          .select("id,action,metadata,user_id,created_at")
          .eq("gym_id", gymId).order("created_at", { ascending: false }).limit(
            50,
          ),
        adminClient.from("feature_flag_overrides").select("flag_key,enabled")
          .eq("gym_id", gymId),
        adminClient.from("support_tickets").select(
          "id,title,status,type,created_at",
        ).eq("gym_id", gymId).order("created_at", { ascending: false }),
        adminClient.from("profiles").select(
          "id,first_name,last_name,role,gym_id",
        ).eq("gym_id", gymId),
        adminClient.from("gyms").select(
          "id,name,status,settings,created_at",
        ).eq("owner_id", rawGym.owner_id).order("created_at"),
      ]);
      for (const result of [
        memberships,
        invoices,
        checkIns,
        ownerProfile,
        notes,
        events,
        overrides,
        tickets,
        staff,
        branches,
      ]) if (result.error) throw result.error;

      const membershipRows = memberships.data ?? [];
      const membersWithMembership = members.map((member) => {
        const rows = membershipRows.filter((item: Record<string, unknown>) =>
          item.member_id === member.id
        );
        return {
          ...member,
          membership: rows.find((item: Record<string, unknown>) =>
            item.status === "active"
          ) ?? rows[0] ?? null,
        };
      });
      const invoiceRows = invoices.data ?? [];
      const realMembers = members.filter((member) => !member.is_demo_data);
      return json({
        gym: { ...gym, ...rawGym },
        owner: {
          name: ownerProfile.data
            ? `${ownerProfile.data.first_name ?? ""} ${ownerProfile.data.last_name ?? ""}`
              .trim()
            : null,
          email: ownerAuth.data.user?.email ?? null,
          phone: ownerProfile.data?.phone ?? null,
        },
        members: membersWithMembership,
        invoices: invoiceRows,
        checkIns: checkIns.data ?? [],
        notes: notes.data ?? [],
        activity: events.data ?? [],
        flagOverrides: overrides.data ?? [],
        tickets: tickets.data ?? [],
        staff: staff.data ?? [],
        branches: branches.data ?? [],
        stats: {
          totalMembers: realMembers.length,
          activeMembers: realMembers.filter((member) =>
            member.status === "active"
          ).length,
          activeMemberships: membershipRows.filter((membership: Record<string, unknown>) =>
            membership.status === "active"
          ).length,
          totalRevenue: invoiceRows.filter((invoice) =>
            invoice.status === "paid"
          ).reduce((sum, invoice) => sum + Number(invoice.amount ?? 0), 0),
          outstandingDues: invoiceRows.filter((invoice) =>
            invoice.status === "pending" || invoice.status === "partial"
          ).reduce((sum, invoice) => sum + Number(invoice.amount ?? 0), 0),
          checkInsThisMonth: (checkIns.data ?? []).filter((item) =>
            item.checked_in_at >= monthStart
          ).length,
          staff: (staff.data ?? []).length,
        },
      });
    }

    if (action === "createGym") {
      if (!can(auth.admin, ["operations"])) {
        return json({ error: "Permission denied" }, 403);
      }
      const gymName = requiredText(body.gymName, "Gym name", 2);
      const ownerEmail = requiredText(body.ownerEmail, "Owner email", 5)
        .toLowerCase();
      const ownerName = requiredText(body.ownerName, "Owner name", 2);
      const city = typeof body.city === "string" ? body.city.trim() : "";
      const plan = typeof body.plan === "string"
        ? body.plan.toLowerCase()
        : "starter";
      const parts = ownerName.split(/\s+/);

      const { data: invited, error: inviteError } = await adminClient.auth.admin
        .inviteUserByEmail(ownerEmail, { data: { full_name: ownerName } });
      if (inviteError || !invited.user) {
        throw inviteError ?? new Error("Owner invitation failed");
      }

      const { data: gymId, error: createError } = await adminClient.rpc(
        "create_platform_gym",
        {
          p_owner_id: invited.user.id,
          p_gym_name: gymName,
          p_owner_first_name: parts.shift() ?? ownerName,
          p_owner_last_name: parts.join(" "),
          p_city: city,
          p_plan: plan,
        },
      );
      if (createError) {
        await adminClient.auth.admin.deleteUser(invited.user.id);
        throw createError;
      }
      await audit(
        auth.admin,
        gymId,
        "gym.created",
        "Created from Super Admin",
        null,
        {
          gymName,
          ownerEmail,
          city,
          plan,
        },
      );
      return json({ gymId, invitationSent: true }, 201);
    }

    if (action === "renewGym") {
      if (!can(auth.admin, ["operations", "finance"])) {
        return json({ error: "Permission denied" }, 403);
      }
      const gymId = requiredUuid(body.gymId);
      const reason = requiredText(body.reason, "Reason", 5);
      const expiry = new Date(requiredText(body.expiresAt, "Expiry date"));
      if (
        !Number.isFinite(expiry.getTime()) || expiry.getTime() <= Date.now()
      ) {
        throw new Error("Expiry date must be in the future");
      }
      const plan = requiredText(body.plan, "Plan");
      if (!["starter", "pro"].includes(plan)) {
        throw new Error("Invalid plan");
      }
      const price = Number(body.price);
      if (!Number.isFinite(price) || price < 0) {
        throw new Error("Invalid price");
      }

      const { data: before, error: readError } = await adminClient.from("gyms")
        .select("id,plan,plan_price,plan_expires_at,status").eq("id", gymId)
        .single();
      if (readError) throw readError;
      const { data: after, error: updateError } = await adminClient.from("gyms")
        .update({
          plan,
          plan_price: price,
          plan_expires_at: expiry.toISOString(),
          plan_started_at: new Date().toISOString(),
          status: "active",
        }).eq("id", gymId).select("id,plan,plan_price,plan_expires_at,status")
        .single();
      if (updateError) throw updateError;
      await audit(
        auth.admin,
        gymId,
        "gym.subscription.renewed",
        reason,
        before,
        after,
      );
      return json({ gym: after });
    }

    if (action === "setGymStatus") {
      if (!can(auth.admin, ["operations", "support"])) {
        return json({ error: "Permission denied" }, 403);
      }
      const gymId = requiredUuid(body.gymId);
      const reason = requiredText(body.reason, "Reason", 5);
      const status = requiredText(body.status, "Status");
      if (!["active", "suspended", "cancelled"].includes(status)) {
        throw new Error("Invalid status");
      }
      const { data: before, error: readError } = await adminClient.from("gyms")
        .select("id,status").eq("id", gymId).single();
      if (readError) throw readError;
      const { data: after, error: updateError } = await adminClient.from("gyms")
        .update({ status }).eq("id", gymId).select("id,status").single();
      if (updateError) throw updateError;
      await audit(
        auth.admin,
        gymId,
        `gym.status.${status}`,
        reason,
        before,
        after,
      );
      return json({ gym: after });
    }

    if (action === "addGymNote") {
      if (!can(auth.admin, ["operations", "support"])) {
        return json({ error: "Permission denied" }, 403);
      }
      const gymId = requiredUuid(body.gymId);
      const note = requiredText(body.note, "Note");
      const { data, error } = await adminClient.from("customer_notes")
        .insert({
          gym_id: gymId,
          admin_id: auth.admin.id,
          body: note,
        }).select("id,body,created_at").single();
      if (error) throw error;
      await audit(auth.admin, gymId, "gym.note.added", null, null, {
        noteId: data.id,
      });
      return json({ note: data }, 201);
    }

    if (action === "grantTrial") {
      const denied = requireSuperadmin(auth.admin);
      if (denied) return denied;
      const gymId = requiredUuid(body.gymId);
      const days = Number(body.days);
      if (!Number.isInteger(days) || days < 1 || days > 365) {
        throw new Error("Invalid trial length");
      }
      const { data: before, error: readError } = await adminClient.from("gyms")
        .select("id,plan,trial_ends_at,plan_expires_at").eq("id", gymId)
        .single();
      if (readError) throw readError;
      if (before.plan === "pro") {
        return json({ error: "Pro gyms cannot receive a trial" }, 422);
      }
      const expiresAt = new Date(Date.now() + days * 86400000).toISOString();
      const { data: after, error } = await adminClient.from("gyms").update({
        trial_ends_at: expiresAt,
        plan_expires_at: expiresAt,
        status: "active",
      }).eq("id", gymId).select("id,plan,trial_ends_at,plan_expires_at,status")
        .single();
      if (error) throw error;
      await audit(auth.admin, gymId, "gym.trial.granted", `${days} days`, before, after);
      return json({ gym: after });
    }

    if (action === "setGymPlan") {
      const denied = requireSuperadmin(auth.admin);
      if (denied) return denied;
      const gymId = requiredUuid(body.gymId);
      const plan = requiredText(body.plan, "Plan").toLowerCase();
      if (!["free", "starter", "pro"].includes(plan)) {
        throw new Error("Invalid plan");
      }
      const price = body.price == null ? null : Number(body.price);
      if (price != null && (!Number.isFinite(price) || price < 0)) {
        throw new Error("Invalid price");
      }
      const months = body.months == null ? null : Number(body.months);
      if (months != null && (!Number.isInteger(months) || months < 1 || months > 120)) {
        throw new Error("Invalid duration");
      }
      const expiry = plan === "pro" && months
        ? new Date(Date.UTC(
          new Date().getUTCFullYear(),
          new Date().getUTCMonth() + months,
          new Date().getUTCDate(),
        )).toISOString()
        : null;
      const { data: before, error: readError } = await adminClient.from("gyms")
        .select("id,plan,plan_price,plan_expires_at,trial_ends_at,status")
        .eq("id", gymId).single();
      if (readError) throw readError;
      const { data: after, error } = await adminClient.from("gyms").update({
        plan,
        plan_price: plan === "pro" ? price : null,
        plan_expires_at: expiry,
        trial_ends_at: null,
        status: "active",
        plan_started_at: new Date().toISOString(),
      }).eq("id", gymId)
        .select("id,plan,plan_price,plan_expires_at,trial_ends_at,status")
        .single();
      if (error) throw error;
      await audit(auth.admin, gymId, "gym.plan.changed", "Admin change", before, after);
      return json({ gym: after });
    }

    if (action === "deleteGym") {
      const denied = requireSuperadmin(auth.admin);
      if (denied) return denied;
      const gymId = requiredUuid(body.gymId);
      const confirmation = requiredText(body.confirmation, "Confirmation");
      const reason = requiredText(body.reason, "Reason", 5);
      const { data: gym, error: readError } = await adminClient.from("gyms")
        .select("id,name,owner_id").eq("id", gymId).single();
      if (readError) throw readError;
      if (confirmation !== gym.name) {
        return json({ error: "Gym name confirmation does not match" }, 422);
      }
      await audit(auth.admin, null, "gym.deleted", reason, gym, null);
      const { error } = await adminClient.from("gyms").delete().eq("id", gymId);
      if (error) throw error;
      const { error: userError } = await adminClient.auth.admin.deleteUser(gym.owner_id);
      return json({ deleted: true, ownerDeleted: !userError });
    }

    if (action === "listBilling") {
      const status = typeof body.status === "string" && body.status.length > 0
        ? body.status
        : null;
      let invoiceQuery = adminClient.from("invoices").select(
        "id,gym_id,member_id,amount,status,created_at,paid_at,due_at,description",
      ).eq("is_demo_data", false).order("created_at", { ascending: false })
        .limit(200);
      if (status) invoiceQuery = invoiceQuery.eq("status", status);
      const [invoiceResult, gymResult] = await Promise.all([
        invoiceQuery,
        adminClient.from("gyms").select("id,name,plan,plan_price"),
      ]);
      if (invoiceResult.error) throw invoiceResult.error;
      if (gymResult.error) throw gymResult.error;
      const gyms = gymResult.data ?? [];
      const names = new Map(gyms.map((gym) => [gym.id, gym.name]));
      const invoices = (invoiceResult.data ?? []).map((invoice) => ({
        ...invoice,
        gym_name: names.get(invoice.gym_id) ?? null,
      }));
      const tiers = new Map<number, number>();
      for (const gym of gyms.filter((item) => item.plan === "pro")) {
        const price = Number(gym.plan_price ?? 0);
        tiers.set(price, (tiers.get(price) ?? 0) + 1);
      }
      return json({
        invoices,
        revenueByTier: [...tiers.entries()].sort(([a], [b]) => a - b).map(
          ([price, count]) => ({ price, count, total: price * count }),
        ),
        failedCount: invoices.filter((invoice) => invoice.status === "failed").length,
        pendingTotal: invoices.filter((invoice) =>
          invoice.status === "pending" || invoice.status === "partial"
        ).reduce((sum, invoice) => sum + Number(invoice.amount ?? 0), 0),
      });
    }

    if (action === "analytics") {
      const [users, profiles, gymsResult, membersResult, invoicesResult, checkInsResult] =
        await Promise.all([
          listAllUsers(),
          adminClient.from("profiles").select("id,gym_id"),
          adminClient.from("gyms").select("id,plan,created_at"),
          adminClient.from("members").select("gym_id").eq("is_demo_data", false),
          adminClient.from("invoices").select("gym_id").eq("status", "paid")
            .eq("is_demo_data", false),
          adminClient.from("check_ins").select("gym_id,checked_in_at")
            .eq("is_demo_data", false)
            .gte("checked_in_at", new Date(Date.now() - 30 * 86400000).toISOString()),
        ]);
      for (const result of [profiles, gymsResult, membersResult, invoicesResult, checkInsResult]) {
        if (result.error) throw result.error;
      }
      const gyms = gymsResult.data ?? [];
      const profileRows = profiles.data ?? [];
      const signedUp = users.filter((user) => !user.app_metadata?.super_admin);
      const confirmed = signedUp.filter((user) => user.email_confirmed_at);
      const userGym = new Map(profileRows.map((row) => [row.id, row.gym_id]));
      const gymIds = new Set(gyms.map((gym) => gym.id));
      const gymsWithMembers = new Set((membersResult.data ?? []).map((row) => row.gym_id));
      const gymsWithPayment = new Set((invoicesResult.data ?? []).map((row) => row.gym_id));
      const setup = confirmed.filter((user) => gymIds.has(userGym.get(user.id)));
      const firstMember = setup.filter((user) => gymsWithMembers.has(userGym.get(user.id)));
      const firstPayment = firstMember.filter((user) => gymsWithPayment.has(userGym.get(user.id)));
      const activeGymIds = new Set((checkInsResult.data ?? []).map((row) => row.gym_id));
      const cohorts = new Map<string, { total: number; active: number }>();
      for (const gym of gyms) {
        const key = monthKey(new Date(gym.created_at));
        const bucket = cohorts.get(key) ?? { total: 0, active: 0 };
        bucket.total++;
        if (activeGymIds.has(gym.id)) bucket.active++;
        cohorts.set(key, bucket);
      }
      const planMix = new Map<string, number>();
      for (const gym of gyms) planMix.set(gym.plan, (planMix.get(gym.plan) ?? 0) + 1);
      return json({
        funnel: [
          { label: "Signed up", count: signedUp.length },
          { label: "Email confirmed", count: confirmed.length },
          { label: "Gym set up", count: setup.length },
          { label: "Added a member", count: firstMember.length },
          { label: "Collected a payment", count: firstPayment.length },
        ],
        cohorts: [...cohorts.entries()].sort(([a], [b]) => a.localeCompare(b))
          .map(([month, value]) => ({
            month,
            ...value,
            retentionPct: value.total ? Math.round(value.active / value.total * 100) : 0,
          })),
        planMix: [...planMix.entries()].map(([plan, count]) => ({ plan, count })),
      });
    }

    if (action === "listAccounts") {
      const users = await listAllUsers();
      const [profiles, linkedMembers] = await Promise.all([
        adminClient.from("profiles").select("id,gym_id"),
        adminClient.from("members").select("user_id").not("user_id", "is", null),
      ]);
      if (profiles.error) throw profiles.error;
      if (linkedMembers.error) throw linkedMembers.error;
      const profileIds = new Set((profiles.data ?? []).map((row) => row.id));
      const memberIds = new Set((linkedMembers.data ?? []).map((row) => row.user_id));
      return json({
        accounts: users.filter((user) =>
          !user.app_metadata?.super_admin && !memberIds.has(user.id)
        ).map((user) => ({
          id: user.id,
          email: user.email ?? "",
          created_at: user.created_at,
          email_confirmed: !!user.email_confirmed_at,
          has_gym: profileIds.has(user.id),
          banned: !!user.banned_until && new Date(user.banned_until) > new Date(),
          last_sign_in_at: user.last_sign_in_at ?? null,
        })).sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at)),
      });
    }

    if (action === "accountAction") {
      const denied = requireSuperadmin(auth.admin);
      if (denied) return denied;
      const userId = requiredUuid(body.userId, "userId");
      const operation = requiredText(body.operation, "Operation");
      if (operation === "confirm") {
        const { error } = await adminClient.auth.admin.updateUserById(userId, {
          email_confirm: true,
        });
        if (error) throw error;
      } else if (operation === "suspend" || operation === "unsuspend") {
        const { error } = await adminClient.auth.admin.updateUserById(userId, {
          ban_duration: operation === "suspend" ? "876000h" : "none",
        });
        if (error) throw error;
      } else if (operation === "magicLink") {
        const target = await adminClient.auth.admin.getUserById(userId);
        if (target.error || !target.data.user?.email) {
          return json({ error: "User not found" }, 404);
        }
        const { data, error } = await adminClient.auth.admin.generateLink({
          type: "magiclink",
          email: target.data.user.email,
        });
        if (error) throw error;
        await audit(auth.admin, null, "account.magic_link.generated", null, null, { userId });
        return json({ link: data.properties?.action_link ?? null });
      } else if (operation === "setupGym") {
        const gymName = requiredText(body.gymName, "Gym name", 2);
        const target = await adminClient.auth.admin.getUserById(userId);
        if (target.error || !target.data.user) return json({ error: "User not found" }, 404);
        const metadata = target.data.user.user_metadata ?? {};
        const fullName = String(metadata.full_name ?? metadata.name ?? "").trim();
        const parts = fullName.split(/\s+/).filter(Boolean);
        const { data: gymId, error } = await adminClient.rpc("create_platform_gym", {
          p_owner_id: userId,
          p_gym_name: gymName,
          p_owner_first_name: String(metadata.first_name ?? parts[0] ?? "Owner"),
          p_owner_last_name: String(metadata.last_name ?? parts.slice(1).join(" ")),
          p_city: typeof body.city === "string" ? body.city.trim() : "",
          p_plan: "starter",
        });
        if (error) throw error;
        await audit(auth.admin, gymId, "account.gym.setup", null, null, { userId });
        return json({ gymId });
      } else {
        throw new Error("Invalid account operation");
      }
      await audit(auth.admin, null, `account.${operation}`, null, null, { userId });
      return json({ updated: true });
    }

    if (action === "createAccount") {
      const denied = requireSuperadmin(auth.admin);
      if (denied) return denied;
      const email = requiredText(body.email, "Email", 5).toLowerCase();
      const password = requiredText(body.password, "Password", 8);
      const gymName = requiredText(body.gymName, "Gym name", 2);
      const firstName = typeof body.firstName === "string" ? body.firstName.trim() : "";
      const lastName = typeof body.lastName === "string" ? body.lastName.trim() : "";
      const plan = body.plan === "pro" ? "pro" : "starter";
      const { data, error } = await adminClient.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: { first_name: firstName, last_name: lastName },
      });
      if (error || !data.user) throw error ?? new Error("Account creation failed");
      const created = await adminClient.rpc("create_platform_gym", {
        p_owner_id: data.user.id,
        p_gym_name: gymName,
        p_owner_first_name: firstName || "Owner",
        p_owner_last_name: lastName,
        p_city: typeof body.city === "string" ? body.city.trim() : "",
        p_plan: plan,
      });
      if (created.error) {
        await adminClient.auth.admin.deleteUser(data.user.id);
        throw created.error;
      }
      await audit(auth.admin, created.data, "account.created", null, null, { email, plan });
      return json({ userId: data.user.id, gymId: created.data }, 201);
    }

    if (action === "upsertAdmin") {
      const denied = requireSuperadmin(auth.admin);
      if (denied) return denied;
      const email = requiredText(body.email, "Email", 5).toLowerCase();
      const role = body.role === "admin" ? "admin" : "superadmin";
      const users = await listAllUsers();
      const target = users.find((user) => user.email?.toLowerCase() === email);
      if (!target) return json({ error: "No account exists with this email" }, 404);
      const { error: authError } = await adminClient.auth.admin.updateUserById(
        target.id,
        { app_metadata: { ...target.app_metadata, super_admin: true } },
      );
      if (authError) throw authError;
      const { error } = await adminClient.from("platform_admins").upsert({
        id: target.id,
        email,
        full_name: typeof body.fullName === "string" ? body.fullName.trim() || null : null,
        role,
        is_active: true,
      }, { onConflict: "id" });
      if (error) throw error;
      await audit(auth.admin, null, "admin.upserted", null, null, { email, role });
      return json({ updated: true });
    }

    if (action === "removeAdmin") {
      const denied = requireSuperadmin(auth.admin);
      if (denied) return denied;
      const userId = requiredUuid(body.userId, "userId");
      if (userId === auth.admin.id) return json({ error: "You cannot revoke your own access" }, 422);
      const target = await adminClient.auth.admin.getUserById(userId);
      if (target.error || !target.data.user) return json({ error: "User not found" }, 404);
      const { error: authError } = await adminClient.auth.admin.updateUserById(
        userId,
        { app_metadata: { ...target.data.user.app_metadata, super_admin: false } },
      );
      if (authError) throw authError;
      const { error } = await adminClient.from("platform_admins").update({
        is_active: false,
      }).eq("id", userId);
      if (error) throw error;
      await audit(auth.admin, null, "admin.removed", null, null, { userId });
      return json({ updated: true });
    }

    if (action === "listAudit") {
      if (!can(auth.admin, ["operations", "support", "finance", "viewer"])) {
        return json({ error: "Permission denied" }, 403);
      }
      const { data, error } = await adminClient.from("platform_admin_audit_log")
        .select(
          "id,gym_id,action,reason,before_state,after_state,metadata,created_at,platform_admins(full_name,email),gyms(name)",
        )
        .order("created_at", { ascending: false }).limit(200);
      if (error) throw error;
      return json({ events: data });
    }

    if (action === "listSupportTickets") {
      if (!can(auth.admin, ["operations", "support", "viewer"])) {
        return json({ error: "Permission denied" }, 403);
      }
      const { data, error } = await adminClient.from("support_tickets")
        .select(
          "id,gym_id,type,title,description,status,reporter_email,created_at,gyms(name)",
        )
        .order("created_at", { ascending: false }).limit(200);
      if (error) throw error;
      return json({ tickets: data });
    }

    if (action === "updateSupportTicket") {
      if (!can(auth.admin, ["operations", "support"])) {
        return json({ error: "Permission denied" }, 403);
      }
      const ticketId = requiredUuid(body.ticketId, "ticketId");
      const reason = requiredText(body.reason, "Reason", 3);
      const status = requiredText(body.status, "Status");
      if (!["new", "in_progress", "fixed", "closed"].includes(status)) {
        throw new Error("Invalid status");
      }
      const { data: before, error: readError } = await adminClient.from(
        "support_tickets",
      )
        .select("id,gym_id,status").eq("id", ticketId).single();
      if (readError) throw readError;
      const { data: after, error: updateError } = await adminClient.from(
        "support_tickets",
      )
        .update({ status }).eq("id", ticketId).select("id,gym_id,status")
        .single();
      if (updateError) throw updateError;
      await audit(
        auth.admin,
        before.gym_id,
        `support.${status}`,
        reason,
        before,
        after,
      );
      return json({ ticket: after });
    }

    if (action === "systemHealth") {
      if (!can(auth.admin, ["operations", "support", "viewer"])) {
        return json({ error: "Permission denied" }, 403);
      }
      const { data, error } = await adminClient.from("error_logs")
        .select("id,gym_id,source,message,page,created_at,gyms(name)")
        .order("created_at", { ascending: false }).limit(200);
      if (error) throw error;
      return json({ errors: data });
    }

    if (action === "listAdmins") {
      if (auth.admin.role !== "superadmin") {
        return json({ error: "Permission denied" }, 403);
      }
      const { data, error } = await adminClient.from("platform_admins")
        .select(
          "id,email,full_name,role,is_active,require_mfa,created_at,updated_at",
        )
        .order("created_at");
      if (error) throw error;
      return json({ admins: data });
    }

    if (action === "listEmailHistory") {
      const { data, error } = await adminClient.from("admin_comms_log")
        .select(
          "id,sent_by_email,segment,subject,recipient_count,sent_count,failed_count,created_at",
        ).order("created_at", { ascending: false }).limit(100);
      if (error) throw error;
      return json({ messages: data ?? [] });
    }

    if (action === "listEmailRecipients" || action === "sendEmail") {
      const segment = typeof body.segment === "string" ? body.segment : "all";
      if (!["all", "trial_active", "trial_expired", "no_activity"].includes(segment)) {
        throw new Error("Invalid segment");
      }
      const { data: gyms, error: gymError } = await adminClient.from("gyms")
        .select("id,owner_id,name,trial_ends_at,plan")
        .order("created_at", { ascending: false });
      if (gymError) throw gymError;
      let filtered = gyms ?? [];
      const now = new Date();
      if (segment === "trial_active") {
        filtered = filtered.filter((gym) =>
          gym.plan !== "pro" && gym.trial_ends_at &&
          new Date(gym.trial_ends_at) > now
        );
      } else if (segment === "trial_expired") {
        filtered = filtered.filter((gym) =>
          gym.plan !== "pro" && gym.trial_ends_at &&
          new Date(gym.trial_ends_at) <= now
        );
      } else if (segment === "no_activity" && filtered.length) {
        const { data: checkIns, error } = await adminClient.from("check_ins")
          .select("gym_id").in("gym_id", filtered.map((gym) => gym.id));
        if (error) throw error;
        const active = new Set((checkIns ?? []).map((row) => row.gym_id));
        filtered = filtered.filter((gym) => !active.has(gym.id));
      }
      const users = await listAllUsers();
      const emails = new Map(users.map((user) => [user.id, user.email ?? ""]));
      let recipients = filtered.map((gym) => ({
        gym: gym.name,
        email: emails.get(gym.owner_id) ?? "",
      })).filter((recipient) => recipient.email.length > 0);
      if (action === "listEmailRecipients") {
        return json({ recipients, total: recipients.length });
      }

      const denied = requireSuperadmin(auth.admin);
      if (denied) return denied;
      const subject = requiredText(body.subject, "Subject", 2);
      const message = requiredText(body.message, "Message", 2);
      if (Array.isArray(body.selectedEmails)) {
        const selected = new Set(body.selectedEmails.map((value) =>
          String(value).trim().toLowerCase()
        ));
        recipients = recipients.filter((recipient) =>
          selected.has(recipient.email.toLowerCase())
        );
      }
      if (!recipients.length) return json({ sent: 0, failed: 0, recipientCount: 0 });
      const apiKey = Deno.env.get("RESEND_API_KEY");
      const from = Deno.env.get("ADMIN_FROM_EMAIL") ?? "GymCRM <noreply@gymcrm.in>";
      if (!apiKey) return json({ error: "Email delivery is not configured" }, 503);
      const escape = (value: string) => value.replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;").replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;");
      const html = `<div style="font-family:Arial,sans-serif;max-width:560px;margin:auto;padding:28px;background:#111;color:#fff"><h2>${escape(subject)}</h2><div style="white-space:pre-wrap;line-height:1.6;color:#d1d5db">${escape(message)}</div><p style="margin-top:28px;color:#6b7280;font-size:12px">GymCRM · gymcrm.in</p></div>`;
      let sent = 0;
      let failed = 0;
      for (let index = 0; index < recipients.length; index += 100) {
        const batch = recipients.slice(index, index + 100).map((recipient) => ({
          from,
          to: recipient.email,
          subject,
          html,
        }));
        const response = await fetch("https://api.resend.com/emails/batch", {
          method: "POST",
          headers: {
            Authorization: `Bearer ${apiKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify(batch),
        });
        if (response.ok) sent += batch.length;
        else failed += batch.length;
      }
      const { error: logError } = await adminClient.from("admin_comms_log").insert({
        sent_by: auth.admin.id,
        sent_by_email: auth.admin.email,
        segment,
        subject,
        message,
        recipient_count: recipients.length,
        sent_count: sent,
        failed_count: failed,
      });
      if (logError) throw logError;
      await audit(auth.admin, null, "email.sent", null, null, {
        segment,
        sent,
        failed,
      });
      return json({ sent, failed, recipientCount: recipients.length });
    }

    if (action === "listActivity") {
      const gymId = typeof body.gymId === "string"
        ? requiredUuid(body.gymId)
        : null;
      let query = adminClient.from("activity_events")
        .select("id,gym_id,user_id,action,metadata,created_at,gyms(name)")
        .order("created_at", { ascending: false }).limit(200);
      if (gymId) query = query.eq("gym_id", gymId);
      const { data, error } = await query;
      if (error) throw error;
      return json({ events: data });
    }

    if (action === "listFeatureFlags") {
      const { data, error } = await adminClient.from("feature_flags")
        .select(
          "key,label,description,enabled_globally,feature_flag_overrides(gym_id,enabled)",
        )
        .order("label");
      if (error) throw error;
      return json({ flags: data });
    }

    if (action === "setFeatureFlag") {
      if (auth.admin.role !== "superadmin") {
        return json({ error: "Permission denied" }, 403);
      }
      const key = requiredText(body.key, "Flag key");
      if (typeof body.enabled !== "boolean") {
        throw new Error("Enabled value is required");
      }
      const gymId = typeof body.gymId === "string"
        ? requiredUuid(body.gymId)
        : null;
      if (gymId) {
        const { error } = await adminClient.from("feature_flag_overrides")
          .upsert({ flag_key: key, gym_id: gymId, enabled: body.enabled });
        if (error) throw error;
      } else {
        const { error } = await adminClient.from("feature_flags")
          .update({ enabled_globally: body.enabled }).eq("key", key);
        if (error) throw error;
      }
      await audit(
        auth.admin,
        gymId,
        "feature_flag.updated",
        "Admin change",
        null,
        {
          key,
          enabled: body.enabled,
        },
      );
      return json({ updated: true });
    }

    if (action === "clearFeatureOverride") {
      const denied = requireSuperadmin(auth.admin);
      if (denied) return denied;
      const gymId = requiredUuid(body.gymId);
      const key = requiredText(body.key, "Flag key");
      const { error } = await adminClient.from("feature_flag_overrides")
        .delete().eq("gym_id", gymId).eq("flag_key", key);
      if (error) throw error;
      await audit(auth.admin, gymId, "feature_flag.override.cleared", null, null, { key });
      return json({ updated: true });
    }

    if (action === "listAnnouncements") {
      const { data, error } = await adminClient.from("announcements")
        .select(
          "id,title,body,audience,audience_gym_ids,created_at,expires_at,platform_admins(full_name,email)",
        )
        .order("created_at", { ascending: false }).limit(200);
      if (error) throw error;
      return json({ announcements: data });
    }

    if (action === "createAnnouncement") {
      const title = requiredText(body.title, "Title", 2);
      const message = requiredText(body.body, "Message", 2);
      const audience = typeof body.audience === "string"
        ? body.audience
        : "all";
      if (!["all", "selected", "trial", "expiring"].includes(audience)) {
        throw new Error("Invalid audience");
      }
      const gymIds = Array.isArray(body.gymIds)
        ? body.gymIds.map((id) => requiredUuid(id))
        : null;
      if (audience === "selected" && (!gymIds || gymIds.length === 0)) {
        throw new Error("Selected gyms are required");
      }
      const { data, error } = await adminClient.from("announcements").insert({
        admin_id: auth.admin.id,
        title,
        body: message,
        audience,
        audience_gym_ids: gymIds,
        expires_at: typeof body.expiresAt === "string" ? body.expiresAt : null,
      }).select("id,title,audience,created_at").single();
      if (error) throw error;
      await audit(
        auth.admin,
        null,
        "announcement.created",
        "Admin broadcast",
        null,
        data,
      );
      return json({ announcement: data }, 201);
    }

    if (action === "deleteAnnouncement") {
      const denied = requireSuperadmin(auth.admin);
      if (denied) return denied;
      const announcementId = requiredUuid(body.announcementId, "announcementId");
      const { error } = await adminClient.from("announcements").delete()
        .eq("id", announcementId);
      if (error) throw error;
      await audit(auth.admin, null, "announcement.deleted", null, null, {
        announcementId,
      });
      return json({ deleted: true });
    }

    if (action === "listPushNotifications") {
      const { data, error } = await adminClient.from("push_notifications")
        .select(
          "id,title,body,url,segment,scheduled_at,status,sent_at,recipient_count,error,created_at",
        )
        .order("created_at", { ascending: false }).limit(200);
      if (error) throw error;
      return json({ notifications: data });
    }

    if (action === "schedulePushNotification") {
      const title = requiredText(body.title, "Title", 2);
      const message = requiredText(body.body, "Message", 2);
      const segment = typeof body.segment === "string" ? body.segment : "all";
      if (
        !["all", "trial_active", "trial_expired", "no_activity"].includes(
          segment,
        )
      ) {
        throw new Error("Invalid segment");
      }
      const scheduledAt = typeof body.scheduledAt === "string"
        ? new Date(body.scheduledAt)
        : new Date();
      if (!Number.isFinite(scheduledAt.getTime())) {
        throw new Error("Invalid schedule");
      }
      const { data, error } = await adminClient.from("push_notifications")
        .insert({
          admin_id: auth.admin.id,
          title,
          body: message,
          url: typeof body.url === "string" ? body.url : null,
          segment,
          scheduled_at: scheduledAt.toISOString(),
          status: "scheduled",
        }).select("id,title,segment,scheduled_at,status").single();
      if (error) throw error;
      await audit(
        auth.admin,
        null,
        "push.scheduled",
        "Admin notification",
        null,
        data,
      );
      return json({ notification: data }, 201);
    }

    if (action === "listBackups") {
      const { data, error } = await adminClient.from("backup_log")
        .select("id,triggered_at,status,note,platform_admins(full_name,email)")
        .order("triggered_at", { ascending: false }).limit(100);
      if (error) throw error;
      return json({ backups: data });
    }

    if (action === "requestBackup") {
      if (auth.admin.role !== "superadmin") {
        return json({ error: "Permission denied" }, 403);
      }
      const note = requiredText(body.note, "Reason", 5);
      const { data, error } = await adminClient.from("backup_log").insert({
        admin_id: auth.admin.id,
        status: "pending",
        note,
      }).select("id,triggered_at,status,note").single();
      if (error) throw error;
      await audit(auth.admin, null, "backup.requested", note, null, data);
      return json({ backup: data }, 202);
    }

    return json({ error: "Unknown action" }, 404);
  } catch (error) {
    console.error("[super-admin-api]", action, error);
    const message = error instanceof Error ? error.message : "Operation failed";
    const status =
      message.includes("required") || message.startsWith("Invalid") ||
        message.includes("future")
        ? 400
        : 500;
    return json({ error: message }, status);
  }
});
