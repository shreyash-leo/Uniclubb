import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/http.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  const authorization = request.headers.get("Authorization");
  if (!authorization) return json({ error: "Unauthorized" }, 401);
  const url = Deno.env.get("SUPABASE_URL")!;
  const userClient = createClient(
    url,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authorization } } },
  );
  const { data: authData } = await userClient.auth.getUser();
  if (!authData.user) return json({ error: "Unauthorized" }, 401);
  const { data: profile } = await userClient.from("profiles")
    .select("is_platform_admin,account_state")
    .eq("id", authData.user.id).single();
  if (!profile?.is_platform_admin || profile.account_state !== "active") {
    return json({ error: "Platform administrator required" }, 403);
  }

  const { user_id, action, reason, suspended_until } = await request.json();
  if (!user_id || !["suspend", "restore"].includes(action)) {
    return json({ error: "Invalid request" }, 400);
  }
  if (user_id === authData.user.id) {
    return json({ error: "Administrators cannot suspend themselves" }, 400);
  }
  const admin = createClient(
    url,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const values = action === "suspend"
    ? {
      account_state: "suspended",
      suspension_reason: String(reason ?? "").slice(0, 500),
      suspended_until: suspended_until ?? null,
    }
    : {
      account_state: "active",
      suspension_reason: null,
      suspended_until: null,
    };
  const { error } = await admin.from("profiles").update(values).eq("id", user_id);
  if (error) return json({ error: error.message }, 400);
  return json({ updated: true, action });
});
