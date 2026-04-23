import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import { redirect } from "next/navigation";

export type AdminUser = {
  id: string;
  email: string;
};

export function adminEmails() {
  const raw = process.env.ADMIN_EMAILS ?? "support@spilltop.com";
  return new Set(
    raw
      .split(",")
      .map((email) => email.trim().toLowerCase())
      .filter(Boolean),
  );
}

export function isAdminEmail(email: string | null | undefined) {
  return Boolean(email && adminEmails().has(email.toLowerCase()));
}

export async function getAdminUser(): Promise<AdminUser | null> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return null;
  }

  const email = user.email?.toLowerCase();
  if (!email || !isAdminEmail(email)) {
    return null;
  }

  return {
    id: user.id,
    email,
  };
}

export async function requireAdminUser(): Promise<AdminUser> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/auth/login?next=/admin");
  }

  const email = user.email?.toLowerCase();
  if (!email || !isAdminEmail(email)) {
    throw new Error("You are signed in, but this account is not allowed to access Spilltop Admin.");
  }

  return {
    id: user.id,
    email,
  };
}

export async function requireAdminClient() {
  const user = await requireAdminUser();
  return {
    user,
    admin: createAdminClient(),
  };
}
