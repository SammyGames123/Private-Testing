"use server";

import { createClient } from "@/lib/supabase/server";
import { getStatusRedirect } from "@/lib/utils";
import { headers } from "next/headers";
import { redirect } from "next/navigation";

export async function signOut() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/auth/login");
}

export async function login(formData: FormData) {
  const email = String(formData.get("email") ?? "");
  const password = String(formData.get("password") ?? "");
  const supabase = await createClient();

  const { error } = await supabase.auth.signInWithPassword({
    email,
    password,
  });

  if (error) {
    redirect(getStatusRedirect("error", "/auth/login", error.message));
  }

  redirect("/dashboard");
}

export async function signup(formData: FormData) {
  const email = String(formData.get("email") ?? "");
  const password = String(formData.get("password") ?? "");
  const origin = (await headers()).get("origin") ?? "";
  const supabase = await createClient();

  const { error } = await supabase.auth.signUp({
    email,
    password,
    options: {
      emailRedirectTo: `${origin}/auth/callback`,
    },
  });

  if (error) {
    redirect(getStatusRedirect("error", "/auth/sign-up", error.message));
  }

  redirect(
    getStatusRedirect(
      "success",
      "/auth/sign-up",
      "Check your email for the confirmation link.",
    ),
  );
}
