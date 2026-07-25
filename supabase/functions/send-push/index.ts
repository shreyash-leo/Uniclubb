import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/http.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  if (request.headers.get("x-webhook-secret") !== Deno.env.get("PUSH_WEBHOOK_SECRET")) {
    return json({ error: "Unauthorized" }, 401);
  }
  const { user_id, title, body, data } = await request.json();
  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, serviceRole);
  const { data: tokens } = await supabase.from("device_tokens")
    .select("token").eq("user_id", user_id).eq("enabled", true);
  const endpoint = Deno.env.get("PUSH_PROVIDER_ENDPOINT");
  const apiKey = Deno.env.get("PUSH_PROVIDER_API_KEY");
  if (!endpoint || !apiKey) return json({ error: "Push provider is not configured" }, 503);
  const results = await Promise.all((tokens ?? []).map(({ token }) =>
    fetch(endpoint, {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ token, title, body, data }),
    }).then((response) => response.ok)
  ));
  return json({ sent: results.filter(Boolean).length, attempted: results.length });
});
