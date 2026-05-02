"use client";

import { saveVenueAction } from "@/app/admin/actions";
import { useEffect, useState } from "react";

type AdminVenueEditorVenue = {
  id: string;
  slug: string;
  name: string;
  area: string;
  city: string;
  category: string | null;
  vibe_blurb: string | null;
  launch_priority: number | null;
  is_active: boolean;
  address: string | null;
  google_place_id: string | null;
  google_place_name: string | null;
  price_level: number | null;
  nightlife_score: number | null;
  featured: boolean;
  latitude: number | null;
  longitude: number | null;
  updated_at: string | null;
};

type VenueSortMode = "name" | "active" | "featured";
type VenueCategoryFilter = "all" | string;

const sortLabels: Record<VenueSortMode, string> = {
  name: "Name",
  active: "Active status",
  featured: "Featured status",
};

function formatDate(value: string | null) {
  if (!value) {
    return "Never";
  }

  return new Intl.DateTimeFormat("en-AU", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(value));
}

function sortVenues(venues: AdminVenueEditorVenue[], sortMode: VenueSortMode) {
  const sorted = [...venues];

  sorted.sort((left, right) => {
    if (sortMode === "active" && left.is_active !== right.is_active) {
      return left.is_active ? -1 : 1;
    }

    if (sortMode === "featured" && left.featured !== right.featured) {
      return left.featured ? -1 : 1;
    }

    return left.name.localeCompare(right.name, undefined, { sensitivity: "base" });
  });

  return sorted;
}

export function VenueListEditor({
  venues,
  venueCategories,
}: {
  venues: AdminVenueEditorVenue[];
  venueCategories: string[];
}) {
  const [sortMode, setSortMode] = useState<VenueSortMode>("name");
  const [categoryFilter, setCategoryFilter] = useState<VenueCategoryFilter>("all");
  const [searchQuery, setSearchQuery] = useState("");
  const [selectedVenueId, setSelectedVenueId] = useState<string | null>(venues[0]?.id ?? null);

  const normalizedQuery = searchQuery.trim().toLowerCase();
  const filteredVenues = venues.filter((venue) => {
    if (categoryFilter !== "all" && (venue.category ?? "bar") !== categoryFilter) {
      return false;
    }

    if (!normalizedQuery) {
      return true;
    }

    const haystack = [
      venue.name,
      venue.slug,
      venue.area,
      venue.city,
      venue.category ?? "",
      venue.address ?? "",
      venue.vibe_blurb ?? "",
    ]
      .join(" ")
      .toLowerCase();

    return haystack.includes(normalizedQuery);
  });

  const sortedVenues = sortVenues(filteredVenues, sortMode);
  const selectedVenue =
    sortedVenues.find((venue) => venue.id == selectedVenueId) ??
    venues.find((venue) => venue.id == selectedVenueId) ??
    sortedVenues[0] ??
    null;

  useEffect(() => {
    if (!sortedVenues.length) {
      if (selectedVenueId !== null) {
        setSelectedVenueId(null);
      }
      return;
    }

    if (!selectedVenueId || !sortedVenues.some((venue) => venue.id === selectedVenueId)) {
      setSelectedVenueId(sortedVenues[0].id);
    }
  }, [selectedVenueId, sortedVenues]);

  return (
    <section className="admin-panel">
      <div className="admin-section-heading">
        <div>
          <p className="admin-kicker">Venues</p>
          <h2>Refine, hide, and repair</h2>
        </div>
        <p>{venues.length} total rows loaded</p>
      </div>

      <div className="admin-venue-workspace">
        <aside className="admin-venue-sidebar">
          <div className="admin-venue-toolbar">
            <label>
              Search venues
              <input
                value={searchQuery}
                onChange={(event) => setSearchQuery(event.target.value)}
                placeholder="Search by name, slug, area…"
              />
            </label>
            <label>
              Venue type
              <select value={categoryFilter} onChange={(event) => setCategoryFilter(event.target.value)}>
                <option value="all">All venue types</option>
                {venueCategories.map((category) => (
                  <option key={category} value={category}>
                    {category}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Sort venues
              <select value={sortMode} onChange={(event) => setSortMode(event.target.value as VenueSortMode)}>
                {Object.entries(sortLabels).map(([value, label]) => (
                  <option key={value} value={value}>
                    {label}
                  </option>
                ))}
              </select>
            </label>
          </div>

          <div className="admin-venue-card-grid">
            {sortedVenues.length ? (
              sortedVenues.map((venue) => {
                const isSelected = venue.id === selectedVenue?.id;

                return (
                  <button
                    key={venue.id}
                    type="button"
                    className={`admin-venue-picker-card${isSelected ? " selected" : ""}`}
                    onClick={() => setSelectedVenueId(venue.id)}
                  >
                    <div className="admin-venue-picker-topline">
                      <strong>{venue.name}</strong>
                      <span className={venue.is_active ? "admin-status status-actioned" : "admin-status status-dismissed"}>
                        {venue.is_active ? "active" : "hidden"}
                      </span>
                    </div>
                    <p>@{venue.slug}</p>
                    <div className="admin-venue-picker-meta">
                      <span>{venue.area}</span>
                      <span>{venue.category ?? "bar"}</span>
                      {venue.featured ? <span className="admin-venue-pill">Featured</span> : null}
                    </div>
                  </button>
                );
              })
            ) : (
              <div className="admin-venue-picker-empty">
                <p>No venues match that search right now.</p>
              </div>
            )}
          </div>
        </aside>

        <div className="admin-venue-editor-shell">
          {selectedVenue ? (
            <form action={saveVenueAction} className="admin-venue-editor-card" key={selectedVenue.id}>
              <input name="id" type="hidden" value={selectedVenue.id} />

              <div className="admin-venue-editor-header">
                <div>
                  <p className="admin-kicker">Editing venue</p>
                  <h3>{selectedVenue.name}</h3>
                  <p className="admin-meta-line">
                    Google: {selectedVenue.google_place_name || selectedVenue.google_place_id || "none"} | Updated{" "}
                    {formatDate(selectedVenue.updated_at)}
                  </p>
                </div>

                <div className="admin-venue-editor-flags">
                  <span
                    className={
                      selectedVenue.is_active ? "admin-status status-actioned" : "admin-status status-dismissed"
                    }
                  >
                    {selectedVenue.is_active ? "active" : "hidden"}
                  </span>
                  {selectedVenue.featured ? <span className="admin-venue-pill">Featured</span> : null}
                </div>
              </div>

              <div className="admin-form-grid compact">
                <label>
                  Name
                  <input name="name" defaultValue={selectedVenue.name} />
                </label>
                <label>
                  Slug
                  <input name="slug" defaultValue={selectedVenue.slug} />
                </label>
                <label>
                  Category
                  <select name="category" defaultValue={selectedVenue.category ?? "bar"}>
                    {venueCategories.map((category) => (
                      <option key={category} value={category}>
                        {category}
                      </option>
                    ))}
                  </select>
                </label>
                <label>
                  Area
                  <input name="area" defaultValue={selectedVenue.area} />
                </label>
                <label>
                  City
                  <input name="city" defaultValue={selectedVenue.city} />
                </label>
                <label>
                  Latitude
                  <input name="latitude" defaultValue={selectedVenue.latitude ?? ""} step="0.0000001" type="number" />
                </label>
                <label>
                  Longitude
                  <input name="longitude" defaultValue={selectedVenue.longitude ?? ""} step="0.0000001" type="number" />
                </label>
                <label>
                  Priority
                  <input name="launch_priority" defaultValue={selectedVenue.launch_priority ?? 0} type="number" />
                </label>
                <label>
                  Price
                  <input name="price_level" defaultValue={selectedVenue.price_level ?? ""} max="4" min="1" type="number" />
                </label>
                <label>
                  Score
                  <input
                    name="nightlife_score"
                    defaultValue={selectedVenue.nightlife_score ?? ""}
                    max="10"
                    min="1"
                    type="number"
                  />
                </label>
                <label className="admin-form-wide">
                  Address
                  <input name="address" defaultValue={selectedVenue.address ?? ""} />
                </label>
                <label className="admin-form-wide">
                  Vibe
                  <input name="vibe_blurb" defaultValue={selectedVenue.vibe_blurb ?? ""} />
                </label>
                <label className="admin-checkbox">
                  <input name="is_active" defaultChecked={selectedVenue.is_active} type="checkbox" />
                  Active
                </label>
                <label className="admin-checkbox">
                  <input name="featured" defaultChecked={selectedVenue.featured} type="checkbox" />
                  Featured
                </label>
                <button className="admin-primary-button" type="submit">
                  Save venue
                </button>
              </div>
            </form>
          ) : (
            <div className="admin-venue-empty">
              <p className="admin-kicker">No venue selected</p>
              <h3>Pick a venue card to edit its fields.</h3>
            </div>
          )}
        </div>
      </div>
    </section>
  );
}
