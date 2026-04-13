import { MyPostsFeed } from "@/components/my-posts-feed";
import { createClient } from "@/lib/supabase/server";
import { getCurrentUserVideos } from "@/lib/videos";
import { redirect } from "next/navigation";

type PostDetailPageProps = {
  params: Promise<{ id: string }>;
};

export default async function PostDetailPage({ params }: PostDetailPageProps) {
  const { id } = await params;

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/auth/login");
  }

  const { videos } = await getCurrentUserVideos(user.id);

  const exists = videos.some((v) => v.id === id);
  const initialVideoId = exists ? id : (videos[0]?.id ?? "");

  return <MyPostsFeed initialVideoId={initialVideoId} videos={videos} />;
}
