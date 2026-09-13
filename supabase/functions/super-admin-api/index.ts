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

function can(admin: Admin, _allowed: string[]): boolean {
  return admin.role === "admin" || admin.role === "superadmin";
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
      const gyms = await directory();
      const now = Date.now();
      const inThirtyDays = now + 30 * 86400000;
      return json({
        activeGyms: gyms.filter((g: Record<string, unknown>) =>
          g.status === "active"
        ).length,
        mrr: gyms
          .filter((g: Record<string, unknown>) => g.status === "active")
          .reduce(
            (sum: number, g: Record<string, unknown>) =>
              sum + Number(g.price ?? 0),
            0,
          ),
        renewalsDue: gyms.filter((g: Record<string, unknown>) => {
          const expiry = Date.parse(String(g.expiry ?? ""));
          return Number.isFinite(expiry) && expiry >= now &&
            expiry <= inThirtyDays;
        }).length,
        newGymsThisMonth: gyms.filter((g: Record<string, unknown>) => {
          const created = new Date(String(g.created_at ?? ""));
          const today = new Date();
          return created.getUTCFullYear() === today.getUTCFullYear() &&
            created.getUTCMonth() === today.getUTCMonth();
        }).length,
      });
    }

    if (action === "gymDetail") {
      const gymId = requiredUuid(body.gymId);
      const gyms = await directory();
      const gym = gyms.find((item: { id: string }) => item.id === gymId);
      if (!gym) return json({ error: "Gym not found" }, 404);

      const [notes, events] = await Promise.all([
        adminClient.from("customer_notes")
          .select("id,body,pinned,created_at,platform_admins(full_name,email)")
          .eq("gym_id", gymId).order("created_at", { ascending: false }).limit(
            50,
          ),
        adminClient.from("platform_admin_audit_log")
          .select(
            "id,action,reason,created_at,platform_admins(full_name,email)",
          )
          .eq("gym_id", gymId).order("created_at", { ascending: false }).limit(
            50,
          ),
      ]);
      if (notes.error) throw notes.error;
      if (events.error) throw events.error;
      return json({ gym, notes: notes.data, audit: events.data });
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
