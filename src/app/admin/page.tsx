/* eslint-disable @next/next/no-img-element */
import {
  archiveReportedVideoAction,
  createFeaturedEventAction,
  createVenueAction,
  deleteReportedVideoAction,
  saveVenueAction,
  sendBroadcastNotificationAction,
  updateEventSuggestionStatusAction,
  updateFeaturedEventStatusAction,
  updateReportStatusAction,
} from "@/app/admin/actions";
import { VenueListEditor } from "@/app/admin/venue-list-editor";
import { VenueLocationEditor, type AdminVenueMapItem } from "@/app/admin/venue-location-editor";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { isAdminEmail } from "@/lib/admin";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Metadata } from "next";
import { redirect } from "next/navigation";

export const metadata: Metadata = {
  title: "Spilltop Admin",
};

type VenueRow = AdminVenueMapItem & {
  area: string;
  city: string;
  vibe_blurb: string | null;
  launch_priority: number | null;
  price_level: number | null;
  nightlife_score: number | null;
  featured: boolean;
  google_place_id: string | null;
  google_place_name: string | null;
  updated_at: string | null;
};

type ReportRow = {
  id: string;
  reporter_id: string;
  target_user_id: string | null;
  target_video_id: string | null;
  target_comment_id: string | null;
  target_live_stream_id: string | null;
  category: string;
  note: string | null;
  status: "open" | "reviewing" | "dismissed" | "actioned";
  created_at: string;
  resolved_at: string | null;
};

type ProfileRow = {
  id: string;
  username: string | null;
  display_name: string | null;
  avatar_url: string | null;
};

type VideoRow = {
  id: string;
  title: string;
  thumbnail_url: string | null;
  playback_url: string | null;
  is_archived: boolean;
  creator_id: string;
  created_at: string;
};

type FeaturedEventRow = {
  id: string;
  title: string;
  subtitle: string | null;
  venue_id: string | null;
  venue_name: string;
  starts_at: string;
  image_url: string | null;
  is_active: boolean;
  created_at: string;
};

type EventSuggestionRow = {
  id: string;
  suggested_by: string | null;
  title: string;
  venue_name: string;
  event_date: string;
  status: "open" | "reviewing" | "approved" | "dismissed";
  admin_note: string | null;
  linked_event_id: string | null;
  created_at: string;
  resolved_at: string | null;
};

const venueCategories = [
  "bar",
  "nightclub",
  "pub",
  "rooftop_bar",
  "bar_club",
  "club_bar",
  "beach_club",
  "lounge_bar",
];

function formatDate(value: string | null) {
  if (!value) {
    return "Never";
  }
  return new Intl.DateTimeFormat("en-AU", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(value));
}

function profileLabel(profile: ProfileRow | undefined, fallbackId: string | null) {
  if (!fallbackId) {
    return "None";
  }
  if (!profile) {
    return fallbackId.slice(0, 8);
  }
  return profile.display_name || profile.username || fallbackId.slice(0, 8);
}

function isMissingRelationError(error: { code?: string | null; message?: string | null } | null | undefined) {
  return error?.code === "42P01" || error?.code === "42703";
}

async function fetchAdminSnapshot(admin: SupabaseClient) {
  const { data: venueData, error: venueError } = await admin
    .from("venues")
    .select(
      `
        id,
        slug,
        name,
        area,
        city,
        category,
        vibe_blurb,
        launch_priority,
        is_active,
        address,
        google_place_id,
        google_place_name,
        price_level,
        nightlife_score,
        featured,
        latitude,
        longitude,
        updated_at
      `,
    )
    .order("is_active", { ascending: false })
    .order("launch_priority", { ascending: false })
    .order("name", { ascending: true })
    .limit(250);

  if (venueError) {
    throw new Error(venueError.message);
  }

  const { data: reportData, error: reportError } = await admin
    .from("content_reports")
    .select(
      `
        id,
        reporter_id,
        target_user_id,
        target_video_id,
        target_comment_id,
        target_live_stream_id,
        category,
        note,
        status,
        created_at,
        resolved_at
      `,
    )
    .order("created_at", { ascending: false })
    .limit(80);

  if (reportError) {
    throw new Error(reportError.message);
  }

  const { data: featuredEventData, error: featuredEventError } = await admin
    .from("featured_events")
    .select("id, title, subtitle, venue_id, venue_name, starts_at, image_url, is_active, created_at")
    .order("starts_at", { ascending: true })
    .limit(60);

  if (featuredEventError && !isMissingRelationError(featuredEventError)) {
    throw new Error(featuredEventError.message);
  }

  const { data: suggestionData, error: suggestionError } = await admin
    .from("event_suggestions")
    .select("id, suggested_by, title, venue_name, event_date, status, admin_note, linked_event_id, created_at, resolved_at")
    .order("created_at", { ascending: false })
    .limit(80);

  if (suggestionError && !isMissingRelationError(suggestionError)) {
    throw new Error(suggestionError.message);
  }

  const venues = ((venueData ?? []) as VenueRow[]).map((venue) => ({
    ...venue,
    is_active: Boolean(venue.is_active),
    featured: Boolean(venue.featured),
  }));
  const reports = (reportData ?? []) as ReportRow[];
  const featuredEvents = ((featuredEventData ?? []) as FeaturedEventRow[]).map((event) => ({
    ...event,
    is_active: Boolean(event.is_active),
  }));
  const eventSuggestions = (suggestionData ?? []) as EventSuggestionRow[];

  const videoIds = Array.from(
    new Set(reports.map((report) => report.target_video_id).filter(Boolean)),
  ) as string[];

  const { data: videoData } = videoIds.length
    ? await admin
        .from("videos")
        .select("id, title, thumbnail_url, playback_url, is_archived, creator_id, created_at")
        .in("id", videoIds)
    : { data: [] };

  const videos = (videoData ?? []) as VideoRow[];
  const profileIds = Array.from(
    new Set(
      [
        ...reports.map((report) => report.reporter_id),
        ...reports.map((report) => report.target_user_id),
        ...videos.map((video) => video.creator_id),
        ...eventSuggestions.map((suggestion) => suggestion.suggested_by),
      ].filter(Boolean),
    ),
  ) as string[];

  const { data: profileData } = profileIds.length
    ? await admin
        .from("profiles")
        .select("id, username, display_name, avatar_url")
        .in("id", profileIds)
    : { data: [] };

  return {
    venues,
    reports,
    featuredEvents,
    eventSuggestions,
    videosById: new Map(videos.map((video) => [video.id, video])),
    profilesById: new Map(((profileData ?? []) as ProfileRow[]).map((profile) => [profile.id, profile])),
  };
}

export default async function AdminPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/auth/login?next=/admin");
  }

  if (!isAdminEmail(user.email)) {
    return (
      <main className="admin-shell">
        <section className="admin-hero compact">
          <p className="admin-kicker">Access denied</p>
          <h1>This account is not on the admin allowlist.</h1>
          <p>Add your email to `ADMIN_EMAILS`, or sign in as `support@spilltop.com`.</p>
        </section>
      </main>
    );
  }

  let admin: SupabaseClient;
  try {
    admin = createAdminClient();
  } catch (error) {
    return (
      <main className="admin-shell">
        <section className="admin-hero compact">
          <p className="admin-kicker">Setup needed</p>
          <h1>Admin needs a server-side Supabase key.</h1>
          <p>{error instanceof Error ? error.message : "Missing admin configuration."}</p>
          <code>SUPABASE_SERVICE_ROLE_KEY=your-service-role-key</code>
        </section>
      </main>
    );
  }

  const { venues, reports, featuredEvents, eventSuggestions, videosById, profilesById } = await fetchAdminSnapshot(admin);
  const activeVenues = venues.filter((venue) => venue.is_active);
  const hiddenVenues = venues.filter((venue) => !venue.is_active);
  const openReports = reports.filter((report) => report.status === "open" || report.status === "reviewing");
  const activeEvents = featuredEvents.filter((event) => event.is_active && new Date(event.starts_at).getTime() >= Date.now() - 12 * 60 * 60 * 1000);
  const openEventSuggestions = eventSuggestions.filter(
    (suggestion) => suggestion.status === "open" || suggestion.status === "reviewing",
  );

  return (
    <main className="admin-shell">
      <section className="admin-hero">
        <div>
          <p className="admin-kicker">Spilltop Admin</p>
          <h1>Clean the map. Keep the app safe.</h1>
          <p>
            Signed in as {user.email}. Use this page to refine venues, drag pins,
            hide bad data, and work through moderation reports.
          </p>
        </div>
        <div className="admin-stat-grid">
          <div>
            <strong>{activeVenues.length}</strong>
            <span>Active venues</span>
          </div>
          <div>
            <strong>{hiddenVenues.length}</strong>
            <span>Hidden venues</span>
          </div>
          <div>
            <strong>{openReports.length}</strong>
            <span>Open reports</span>
          </div>
          <div>
            <strong>{activeEvents.length}</strong>
            <span>Live event cards</span>
          </div>
        </div>
      </section>

      <VenueLocationEditor venues={activeVenues.filter((venue) => venue.latitude != null && venue.longitude != null)} />

      <section className="admin-grid">
        <div className="admin-panel">
          <div className="admin-section-heading">
            <div>
              <p className="admin-kicker">Push everyone</p>
              <h2>Broadcast announcement</h2>
            </div>
          </div>

          <form action={sendBroadcastNotificationAction} className="admin-form-grid">
            <label className="admin-form-wide">
              Title
              <input name="title" maxLength={80} placeholder="Tonight on Spilltop" required />
            </label>
            <label className="admin-form-wide">
              Message
              <textarea
                className="admin-form-textarea"
                name="body"
                maxLength={180}
                placeholder="Tell everyone what’s happening."
                required
                rows={4}
              />
            </label>
            <p className="admin-meta-line admin-form-wide">
              Sends a push announcement to every user with a registered device token. Tapping it opens the notification center in the app.
            </p>
            <button className="admin-primary-button admin-form-wide" type="submit">
              Send broadcast
            </button>
          </form>
        </div>

        <div className="admin-panel">
          <div className="admin-section-heading">
            <div>
              <p className="admin-kicker">Map cards</p>
              <h2>Add event</h2>
            </div>
          </div>

          <form action={createFeaturedEventAction} className="admin-form-grid" encType="multipart/form-data">
            <label>
              Event title
              <input name="title" maxLength={80} placeholder="Friday at Elsewhere" required />
            </label>
            <label>
              Venue
              <select defaultValue="" name="venue_id" required>
                <option disabled value="">
                  Select a venue
                </option>
                {activeVenues.map((venue) => (
                  <option key={venue.id} value={venue.id}>
                    {venue.name}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Event date
              <input name="starts_at" required type="datetime-local" />
            </label>
            <label className="admin-form-wide">
              Event subtitle
              <textarea
                className="admin-form-textarea"
                name="subtitle"
                maxLength={140}
                placeholder="What should users know at a glance?"
                rows={3}
              />
            </label>
            <label className="admin-form-wide">
              Event image
              <input accept="image/*" name="image" required type="file" />
            </label>
            <label className="admin-checkbox">
              <input defaultChecked name="is_active" type="checkbox" />
              Show on app
            </label>
            <p className="admin-meta-line admin-form-wide">
              Event cards automatically stop showing in the app 12 hours after the event time passes.
            </p>
            <button className="admin-primary-button admin-form-wide" type="submit">
              Add event
            </button>
          </form>
        </div>

        <div className="admin-panel">
          <div className="admin-section-heading">
            <div>
              <p className="admin-kicker">User leads</p>
              <h2>Event recommendations</h2>
            </div>
          </div>

          <div className="admin-report-list">
            {openEventSuggestions.length ? (
              openEventSuggestions.map((suggestion) => {
                const suggester = suggestion.suggested_by ? profilesById.get(suggestion.suggested_by) : undefined;

                return (
                  <article className="admin-report-card" key={suggestion.id}>
                    <div className="admin-report-topline">
                      <span className={`admin-status status-${suggestion.status}`}>{suggestion.status}</span>
                      <span>{formatDate(suggestion.created_at)}</span>
                    </div>
                    <h3>{suggestion.title}</h3>
                    <p>
                      {suggestion.venue_name} • {formatDate(suggestion.event_date)}
                    </p>
                    <dl>
                      <div>
                        <dt>Suggested by</dt>
                        <dd>{profileLabel(suggester, suggestion.suggested_by)}</dd>
                      </div>
                      {suggestion.linked_event_id ? (
                        <div>
                          <dt>Linked event</dt>
                          <dd>{suggestion.linked_event_id.slice(0, 8)}</dd>
                        </div>
                      ) : null}
                    </dl>

                    <div className="admin-action-row">
                      <form action={updateEventSuggestionStatusAction}>
                        <input name="id" type="hidden" value={suggestion.id} />
                        <input name="status" type="hidden" value="reviewing" />
                        <button type="submit">Reviewing</button>
                      </form>
                      <form action={updateEventSuggestionStatusAction}>
                        <input name="id" type="hidden" value={suggestion.id} />
                        <input name="status" type="hidden" value="dismissed" />
                        <button type="submit">Dismiss</button>
                      </form>
                      <form action={updateEventSuggestionStatusAction}>
                        <input name="id" type="hidden" value={suggestion.id} />
                        <input name="status" type="hidden" value="approved" />
                        <button type="submit">Mark approved</button>
                      </form>
                    </div>
                  </article>
                );
              })
            ) : (
              <p className="admin-empty">No user-submitted event leads yet.</p>
            )}
          </div>
        </div>

        <div className="admin-panel">
          <div className="admin-section-heading">
            <div>
              <p className="admin-kicker">Add venue</p>
              <h2>New nightlife spot</h2>
            </div>
          </div>

          <form action={createVenueAction} className="admin-form-grid">
            <label>
              Name
              <input name="name" placeholder="Venue name" required />
            </label>
            <label>
              Slug
              <input name="slug" placeholder="venue-slug" required />
            </label>
            <label>
              Category
              <select defaultValue="bar" name="category">
                {venueCategories.map((category) => (
                  <option key={category} value={category}>
                    {category}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Area
              <input defaultValue="Surfers Paradise" name="area" />
            </label>
            <label>
              Latitude
              <input name="latitude" step="0.0000001" type="number" />
            </label>
            <label>
              Longitude
              <input name="longitude" step="0.0000001" type="number" />
            </label>
            <label className="admin-form-wide">
              Address
              <input name="address" placeholder="Street address" />
            </label>
            <label className="admin-form-wide">
              Vibe
              <input name="vibe_blurb" placeholder="Short internal/helper description" />
            </label>
            <label className="admin-checkbox">
              <input name="featured" type="checkbox" />
              Featured
            </label>
            <button className="admin-primary-button admin-form-wide" type="submit">
              Add venue
            </button>
          </form>
        </div>

        <div className="admin-panel">
          <div className="admin-section-heading">
            <div>
              <p className="admin-kicker">Reports</p>
              <h2>Moderation queue</h2>
            </div>
          </div>

          <div className="admin-report-list">
            {reports.length ? (
              reports.map((report) => {
                const video = report.target_video_id ? videosById.get(report.target_video_id) : undefined;
                const reporter = profilesById.get(report.reporter_id);
                const targetUser = report.target_user_id ? profilesById.get(report.target_user_id) : undefined;
                const creator = video ? profilesById.get(video.creator_id) : undefined;

                return (
                  <article className="admin-report-card" key={report.id}>
                    <div className="admin-report-topline">
                      <span className={`admin-status status-${report.status}`}>{report.status}</span>
                      <span>{formatDate(report.created_at)}</span>
                    </div>
                    <h3>{report.category.replaceAll("_", " ")}</h3>
                    <p>{report.note || "No note supplied."}</p>
                    <dl>
                      <div>
                        <dt>Reporter</dt>
                        <dd>{profileLabel(reporter, report.reporter_id)}</dd>
                      </div>
                      <div>
                        <dt>Target</dt>
                        <dd>
                          {video
                            ? `Video: ${video.title}`
                            : report.target_user_id
                              ? `User: ${profileLabel(targetUser, report.target_user_id)}`
                              : report.target_comment_id
                                ? `Comment: ${report.target_comment_id.slice(0, 8)}`
                                : report.target_live_stream_id
                                  ? `Live: ${report.target_live_stream_id.slice(0, 8)}`
                                  : "Unknown"}
                        </dd>
                      </div>
                      {creator ? (
                        <div>
                          <dt>Creator</dt>
                          <dd>{profileLabel(creator, video?.creator_id ?? null)}</dd>
                        </div>
                      ) : null}
                    </dl>

                    {video?.thumbnail_url || video?.playback_url ? (
                      <div className="admin-report-media">
                        <img alt={video.title} src={video.thumbnail_url || video.playback_url || ""} />
                        {video.is_archived ? <span>Archived</span> : null}
                      </div>
                    ) : null}

                    <div className="admin-action-row">
                      <form action={updateReportStatusAction}>
                        <input name="id" type="hidden" value={report.id} />
                        <input name="status" type="hidden" value="reviewing" />
                        <button type="submit">Reviewing</button>
                      </form>
                      <form action={updateReportStatusAction}>
                        <input name="id" type="hidden" value={report.id} />
                        <input name="status" type="hidden" value="dismissed" />
                        <button type="submit">Dismiss</button>
                      </form>
                      {video ? (
                        <>
                          <form action={archiveReportedVideoAction}>
                            <input name="report_id" type="hidden" value={report.id} />
                            <input name="video_id" type="hidden" value={video.id} />
                            <button className="danger" type="submit">
                              Archive video
                            </button>
                          </form>
                          <form action={deleteReportedVideoAction}>
                            <input name="report_id" type="hidden" value={report.id} />
                            <input name="video_id" type="hidden" value={video.id} />
                            <button className="danger" type="submit">
                              Delete post
                            </button>
                          </form>
                        </>
                      ) : (
                        <form action={updateReportStatusAction}>
                          <input name="id" type="hidden" value={report.id} />
                          <input name="status" type="hidden" value="actioned" />
                          <button className="danger" type="submit">
                            Mark actioned
                          </button>
                        </form>
                      )}
                    </div>
                  </article>
                );
              })
            ) : (
              <p className="admin-empty">No reports yet.</p>
            )}
          </div>
        </div>
      </section>

      <section className="admin-panel">
        <div className="admin-section-heading">
          <div>
            <p className="admin-kicker">Events</p>
            <h2>Current event cards</h2>
          </div>
          <p>{activeEvents.length} active in app</p>
        </div>

        <div className="admin-report-list">
          {activeEvents.length ? (
            activeEvents.map((event) => (
              <article className="admin-report-card" key={event.id}>
                <div className="admin-report-topline">
                  <span className={`admin-status ${event.is_active ? "status-actioned" : "status-dismissed"}`}>
                    {event.is_active ? "live" : "hidden"}
                  </span>
                  <span>{formatDate(event.starts_at)}</span>
                </div>
                <h3>{event.title}</h3>
                <p>{event.subtitle || event.venue_name}</p>
                {event.image_url ? (
                  <div className="admin-report-media">
                    <img alt={event.title} src={event.image_url} />
                  </div>
                ) : null}
                <div className="admin-action-row">
                  <form action={updateFeaturedEventStatusAction}>
                    <input name="id" type="hidden" value={event.id} />
                    <input name="is_active" type="hidden" value="false" />
                    <button className="danger" type="submit">
                      Remove from app
                    </button>
                  </form>
                </div>
              </article>
            ))
          ) : (
            <p className="admin-empty">No active event cards yet.</p>
          )}
        </div>
      </section>

      <VenueListEditor venues={venues} venueCategories={venueCategories} />
    </main>
  );
}
