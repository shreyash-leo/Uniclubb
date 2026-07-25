import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/http.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  const authorization = request.headers.get("Authorization");
  if (!authorization) return json({ error: "Unauthorized" }, 401);
  const url = Deno.env.get("SUPABASE_URL")!;
  const client = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authorization } },
  });
  const { data: authData } = await client.auth.getUser();
  if (!authData.user) return json({ error: "Unauthorized" }, 401);
  const { payment_id, amount, reason } = await request.json();
  const { data: payment } = await client.from("payments")
    .select("id,amount,status,provider_payment_id,registration_id")
    .eq("id", payment_id).single();
  if (!payment || payment.status !== "paid") {
    return json({ error: "Paid payment not found or unauthorized" }, 404);
  }
  const refundAmount = Number(amount ?? payment.amount);
  if (!(refundAmount > 0) || refundAmount > Number(payment.amount)) {
    return json({ error: "Invalid refund amount" }, 400);
  }
  const endpoint = Deno.env.get("PAYMENT_REFUND_ENDPOINT");
  const secret = Deno.env.get("PAYMENT_PROVIDER_SECRET");
  if (!endpoint || !secret) {
    return json({ error: "Refund provider is not configured" }, 503);
  }
  const providerResponse = await fetch(endpoint, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${secret}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      payment_id: payment.provider_payment_id,
      reference: payment.id,
      amount: refundAmount,
      reason,
    }),
  });
  const providerRefund = await providerResponse.json();
  if (!providerResponse.ok) return json({ error: "Refund failed" }, 502);

  const admin = createClient(
    url,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const partial = refundAmount < Number(payment.amount);
  const { data: refund, error } = await admin.from("refunds").insert({
    payment_id: payment.id,
    amount: refundAmount,
    reason,
    provider_refund_id: providerRefund.refund_id ?? providerRefund.id,
    status: providerRefund.status ?? "submitted",
  }).select().single();
  if (error) return json({ error: error.message }, 500);
  await admin.from("payments").update({
    status: partial ? "partially_refunded" : "refunded",
  }).eq("id", payment.id);
  await admin.from("event_registrations").update({
    payment_status: partial ? "partially_refunded" : "refunded",
    ...(!partial ? { status: "cancelled" } : {}),
  }).eq("id", payment.registration_id);
  return json({ refund, partial });
});
