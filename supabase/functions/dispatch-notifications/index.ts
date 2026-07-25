import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/http.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.headers.get("x-cron-secret") !== Deno.env.get("CRON_SECRET")) {
    return json({ error: "Unauthorized" }, 401);
  }

  const client = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const now = new Date().toISOString();

  // Publishing the row activates the announcement trigger and its in-app fanout.
  await client.from("announcements")
    .update({ published_at: now })
    .is("published_at", null)
    .lte("scheduled_at", now);

  const { data: reminders } = await client.from("event_reminders")
    .select("id,user_id,event_id,events(title)")
    .is("delivered_at", null)
    .lte("remind_at", now)
    .limit(500);
  for (const reminder of reminders ?? []) {
    await client.from("notifications").insert({
      user_id: reminder.user_id,
      type: "event_reminder",
      title: `Event reminder: ${reminder.events?.title ?? "Upcoming event"}`,
      body: "Your saved event is coming up.",
      data: { event_id: reminder.event_id, reminder_id: reminder.id },
    });
    await client.from("event_reminders")
      .update({ delivered_at: now })
      .eq("id", reminder.id)
      .is("delivered_at", null);
  }

  const endpoint = Deno.env.get("PUSH_PROVIDER_ENDPOINT");
  const apiKey = Deno.env.get("PUSH_PROVIDER_API_KEY");
  if (!endpoint || !apiKey) {
    return json({
      in_app_processed: true,
      push_sent: 0,
      warning: "Push provider is not configured",
    });
  }

  const { data: notifications } = await client.from("notifications")
    .select("id,user_id,title,body,data")
    .is("push_sent_at", null)
    .order("created_at")
    .limit(500);
  let sent = 0;
  for (const notification of notifications ?? []) {
    const { data: preference } = await client.from("notification_preferences")
      .select("push_enabled").eq("user_id", notification.user_id).maybeSingle();
    if (preference?.push_enabled === false) continue;
    const { data: tokens } = await client.from("device_tokens")
      .select("token").eq("user_id", notification.user_id).eq("enabled", true);
    const results = await Promise.all((tokens ?? []).map(({ token }: { token: string }) =>
      fetch(endpoint, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          token,
          title: notification.title,
          body: notification.body,
          data: notification.data,
        }),
      })
    ));
    if (results.some((response: Response) => response.ok)) {
      sent += 1;
      await client.from("notifications")
        .update({ push_sent_at: now })
        .eq("id", notification.id)
        .is("push_sent_at", null);
    }
  }
  return json({ in_app_processed: true, push_sent: sent });
});
