"use server";

import { createClient } from "@/lib/supabase/server";
import { getAuthSiteUrl } from "@/lib/site-url";
import { getStatusRedirect } from "@/lib/utils";
import { redirect } from "next/navigation";

export async function signOut() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/auth/login");
}

export async function login(formData: FormData) {
  const email = String(formData.get("email") ?? "");
  const password = String(formData.get("password") ?? "");
  const next = String(formData.get("next") ?? "");
  const safeNext = next.startsWith("/") && !next.startsWith("//") ? next : "/dashboard";
  const supabase = await createClient();

  const { error } = await supabase.auth.signInWithPassword({
    email,
    password,
  });

  if (error) {
    redirect(getStatusRedirect("error", "/auth/login", error.message));
  }

  redirect(safeNext);
}

export async function requestPasswordReset(formData: FormData) {
  const email = String(formData.get("email") ?? "");
  const next = String(formData.get("next") ?? "");
  const safeNext = next.startsWith("/") && !next.startsWith("//") ? next : "/dashboard";
  const supabase = await createClient();
  const authSiteUrl = await getAuthSiteUrl();
  const resetPath = `/auth/reset-password?next=${encodeURIComponent(safeNext)}`;

  const { error } = await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: `${authSiteUrl}/auth/callback?next=${encodeURIComponent(resetPath)}`,
  });

  if (error) {
    redirect(getStatusRedirect("error", `/auth/forgot-password?next=${encodeURIComponent(safeNext)}`, error.message));
  }

  redirect(
    getStatusRedirect(
      "success",
      `/auth/forgot-password?next=${encodeURIComponent(safeNext)}`,
      "Check your email for the password reset link.",
    ),
  );
}

export async function updatePassword(formData: FormData) {
  const password = String(formData.get("password") ?? "");
  const confirmPassword = String(formData.get("confirmPassword") ?? "");
  const next = String(formData.get("next") ?? "");
  const safeNext = next.startsWith("/") && !next.startsWith("//") ? next : "/dashboard";

  if (password.length < 8) {
    redirect(
      getStatusRedirect(
        "error",
        `/auth/reset-password?next=${encodeURIComponent(safeNext)}`,
        "Password must be at least 8 characters.",
      ),
    );
  }

  if (password !== confirmPassword) {
    redirect(
      getStatusRedirect(
        "error",
        `/auth/reset-password?next=${encodeURIComponent(safeNext)}`,
        "Passwords do not match.",
      ),
    );
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.updateUser({ password });

  if (error) {
    redirect(getStatusRedirect("error", `/auth/reset-password?next=${encodeURIComponent(safeNext)}`, error.message));
  }

  redirect(getStatusRedirect("success", safeNext, "Password updated."));
}

export async function signup(formData: FormData) {
  const email = String(formData.get("email") ?? "");
  const password = String(formData.get("password") ?? "");
  const authSiteUrl = await getAuthSiteUrl();
  const supabase = await createClient();

  const { error } = await supabase.auth.signUp({
    email,
    password,
    options: {
      emailRedirectTo: `${authSiteUrl}/auth/confirm`,
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
