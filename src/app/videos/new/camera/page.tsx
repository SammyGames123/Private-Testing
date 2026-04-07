import { redirect } from "next/navigation";
import { CameraRecorder } from "@/components/camera-recorder";
import { createClient } from "@/lib/supabase/server";

export default async function CameraPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/auth/login");
  }

  return <CameraRecorder userId={user.id} />;
}
