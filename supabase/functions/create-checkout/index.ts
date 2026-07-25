import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/http.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  const authorization = request.headers.get("Authorization");
  if (!authorization) return json({ error: "Unauthorized" }, 401);
  const client = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authorization } } },
  );
  const { data: authData } = await client.auth.getUser();
  if (!authData.user) return json({ error: "Unauthorized" }, 401);
  const { registration_id } = await request.json();
  const { data: registration, error } = await client
    .from("event_registrations")
    .select("id,user_id,amount_due,events(title,currency)")
    .eq("id", registration_id)
    .eq("user_id", authData.user.id)
    .single();
  if (error || !registration) return json({ error: "Registration not found" }, 404);
  if (Number(registration.amount_due) <= 0) {
    return json({ error: "No payment is required" }, 400);
  }

  const endpoint = Deno.env.get("PAYMENT_CHECKOUT_ENDPOINT");
  const secret = Deno.env.get("PAYMENT_PROVIDER_SECRET");
  if (!endpoint || !secret) {
    return json({ error: "Payment provider is not configured" }, 503);
  }
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const invoiceNumber = `UC-${new Date().getUTCFullYear()}-${registration.id.slice(0, 8).toUpperCase()}`;
  const { data: paymentRow, error: paymentError } = await admin.from("payments")
    .upsert({
      registration_id: registration.id,
      user_id: authData.user.id,
      provider: Deno.env.get("PAYMENT_PROVIDER") ?? "configured-provider",
      amount: registration.amount_due,
      currency: registration.events?.currency ?? "INR",
      invoice_number: invoiceNumber,
    }, { onConflict: "invoice_number" }).select("id").single();
  if (paymentError) return json({ error: paymentError.message }, 500);

  const paymentResponse = await fetch(endpoint, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${secret}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      reference: paymentRow.id,
      amount: registration.amount_due,
      currency: registration.events?.currency ?? "INR",
      description: registration.events?.title ?? "UniClub event",
      customer_reference: authData.user.id,
    }),
  });
  const payment = await paymentResponse.json();
  if (!paymentResponse.ok) return json({ error: "Checkout creation failed" }, 502);
  await admin.from("payments").update({
    provider_payment_id: payment.payment_id ?? payment.id ?? null,
    metadata: payment,
  }).eq("id", paymentRow.id);
  return json({
    checkout_url: payment.checkout_url,
    payment_id: paymentRow.id,
    invoice_number: invoiceNumber,
  });
});
