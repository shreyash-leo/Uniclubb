import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/http.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  const authHeader = request.headers.get("Authorization");
  if (!authHeader) return json({ error: "Unauthorized" }, 401);

  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const userClient = createClient(url, anon, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: authData, error: authError } =
    await userClient.auth.getUser();
  if (authError || !authData.user) return json({ error: "Unauthorized" }, 401);

  const admin = createClient(url, serviceRole);
  const userId = authData.user.id;
  const anonymizedEmail = `deleted-${userId}@invalid.uniclub`;
  const { error: profileError } = await admin.from("profiles").update({
    email: anonymizedEmail,
    full_name: "Deleted user",
    username: null,
    avatar_url: null,
    cover_url: null,
    bio: "",
    college_id: null,
    department: null,
    academic_year: null,
    skills: [],
    interests: [],
    social_links: {},
    account_state: "deleted",
  }).eq("id", userId);
  if (profileError) return json({ error: profileError.message }, 500);

  // Soft deletion prevents sign-in while retaining an anonymized auth row so
  // mandatory financial/audit foreign keys remain referentially valid.
  const { error: deleteError } =
    await admin.auth.admin.deleteUser(userId, true);
  if (deleteError) return json({ error: deleteError.message }, 500);
  return json({ deleted: true });
});
