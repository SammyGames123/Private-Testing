import { createClient } from "@/lib/supabase/server";

export type Profile = {
  id: string;
  email: string | null;
  username: string | null;
  display_name: string | null;
  avatar_url: string | null;
  bio: string | null;
  interests: string[] | null;
};

export async function getCurrentProfile() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return { user: null, profile: null, profileError: null };
  }

  const { data: profile, error: profileError } = await supabase
    .from("profiles")
    .select("id, email, username, display_name, avatar_url, bio, interests")
    .eq("id", user.id)
    .maybeSingle<Profile>();

  return { user, profile, profileError };
}
