import type { SupabaseClient } from "@supabase/supabase-js";

export async function recordAdminAudit(
  admin: SupabaseClient,
  actorId: string | null,
  action: string,
  targetType: string,
  targetId: string | null,
  metadata: Record<string, unknown> = {},
) {
  try {
    await admin.from("admin_audit_log").insert({
      actor_id: actorId,
      action,
      target_type: targetType,
      target_id: targetId,
      metadata,
    });
  } catch {
    // Optional audit table is missing or temporarily unavailable.
  }
}

export async function hasAdminAuditRecord(
  admin: SupabaseClient,
  action: string,
  targetType: string,
  targetId: string,
) {
  try {
    const { data, error } = await admin
      .from("admin_audit_log")
      .select("id")
      .eq("action", action)
      .eq("target_type", targetType)
      .eq("target_id", targetId)
      .limit(1);

    if (error) {
      return false;
    }

    return Boolean(data && data.length > 0);
  } catch {
    return false;
  }
}
