import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/http.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (
    request.headers.get("x-payment-webhook-secret") !==
      Deno.env.get("PAYMENT_WEBHOOK_SECRET")
  ) {
    return json({ error: "Unauthorized" }, 401);
  }
  const payload = await request.json();
  const paymentId = payload.reference ?? payload.payment_id;
  const providerStatus = String(payload.status ?? "").toLowerCase();
  const status = providerStatus === "paid" || providerStatus === "captured" ||
      providerStatus === "succeeded"
    ? "paid"
    : providerStatus === "refunded"
    ? "refunded"
    : providerStatus === "failed"
    ? "failed"
    : "pending";
  if (!paymentId) return json({ error: "Missing payment reference" }, 400);

  const client = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { data: payment, error } = await client.from("payments").update({
    status,
    provider_payment_id: payload.provider_payment_id ?? payload.id,
    invoice_url: payload.invoice_url,
    metadata: payload,
  }).eq("id", paymentId).select("registration_id").single();
  if (error) return json({ error: error.message }, 400);
  if (payment.registration_id) {
    await client.from("event_registrations").update({
      payment_status: status,
      ...(status === "paid" ? { status: "approved" } : {}),
    }).eq("id", payment.registration_id);
  }
  return json({ received: true, status });
});
