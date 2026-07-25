import { corsHeaders, json } from "../_shared/http.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (!request.headers.get("Authorization")) {
    return json({ error: "Unauthorized" }, 401);
  }
  const { provider } = await request.json();
  const url = provider === "google"
    ? Deno.env.get("GOOGLE_CALENDAR_OAUTH_URL")
    : provider === "apple"
    ? Deno.env.get("APPLE_CALENDAR_CONNECT_URL")
    : null;
  if (!url) return json({ error: "Calendar provider is not configured" }, 503);
  return json({ url });
});
