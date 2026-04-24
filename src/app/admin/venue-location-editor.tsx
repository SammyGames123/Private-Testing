"use client";

import { updateVenueCoordinatesAction } from "@/app/admin/actions";
import type { PointerEvent } from "react";
import { useEffect, useMemo, useRef, useState } from "react";

export type AdminVenueMapItem = {
  id: string;
  slug: string;
  name: string;
  category: string | null;
  address: string | null;
  latitude: number | null;
  longitude: number | null;
  is_active: boolean;
};

type Point = {
  x: number;
  y: number;
};

const TILE_SIZE = 256;
const DEFAULT_CENTER = {
  latitude: -28.001,
  longitude: 153.4292,
};

function lonToWorldX(longitude: number, zoom: number) {
  return ((longitude + 180) / 360) * TILE_SIZE * 2 ** zoom;
}

function latToWorldY(latitude: number, zoom: number) {
  const sinLatitude = Math.sin((latitude * Math.PI) / 180);
  return (
    (0.5 - Math.log((1 + sinLatitude) / (1 - sinLatitude)) / (4 * Math.PI)) *
    TILE_SIZE *
    2 ** zoom
  );
}

function worldXToLon(x: number, zoom: number) {
  return (x / (TILE_SIZE * 2 ** zoom)) * 360 - 180;
}

function worldYToLat(y: number, zoom: number) {
  const n = Math.PI - (2 * Math.PI * y) / (TILE_SIZE * 2 ** zoom);
  return (180 / Math.PI) * Math.atan(0.5 * (Math.exp(n) - Math.exp(-n)));
}

function coordinateToPoint(
  latitude: number,
  longitude: number,
  center: { latitude: number; longitude: number },
  zoom: number,
  size: { width: number; height: number },
) {
  const centerX = lonToWorldX(center.longitude, zoom);
  const centerY = latToWorldY(center.latitude, zoom);
  const x = lonToWorldX(longitude, zoom) - centerX + size.width / 2;
  const y = latToWorldY(latitude, zoom) - centerY + size.height / 2;
  return { x, y };
}

function pointToCoordinate(
  point: Point,
  center: { latitude: number; longitude: number },
  zoom: number,
  size: { width: number; height: number },
) {
  const centerX = lonToWorldX(center.longitude, zoom);
  const centerY = latToWorldY(center.latitude, zoom);
  const worldX = point.x + centerX - size.width / 2;
  const worldY = point.y + centerY - size.height / 2;
  return {
    latitude: worldYToLat(worldY, zoom),
    longitude: worldXToLon(worldX, zoom),
  };
}

function tileRange(
  center: { latitude: number; longitude: number },
  zoom: number,
  size: { width: number; height: number },
) {
  const centerX = lonToWorldX(center.longitude, zoom);
  const centerY = latToWorldY(center.latitude, zoom);
  const left = centerX - size.width / 2;
  const top = centerY - size.height / 2;
  const right = centerX + size.width / 2;
  const bottom = centerY + size.height / 2;
  const tiles = [];

  for (let x = Math.floor(left / TILE_SIZE); x <= Math.floor(right / TILE_SIZE); x += 1) {
    for (let y = Math.floor(top / TILE_SIZE); y <= Math.floor(bottom / TILE_SIZE); y += 1) {
      tiles.push({
        key: `${zoom}-${x}-${y}`,
        x,
        y,
        left: x * TILE_SIZE - left,
        top: y * TILE_SIZE - top,
      });
    }
  }

  return tiles;
}

function formatCoordinate(value: number | null | undefined) {
  return value == null ? "" : value.toFixed(7);
}

export function VenueLocationEditor({ venues }: { venues: AdminVenueMapItem[] }) {
  const mapRef = useRef<HTMLDivElement | null>(null);
  const backgroundDragRef = useRef<{
    pointerId: number;
    startPoint: Point;
    startCenter: { latitude: number; longitude: number };
  } | null>(null);
  const [zoom, setZoom] = useState(17);
  const [size, setSize] = useState({ width: 860, height: 460 });
  const [selectedVenueId, setSelectedVenueId] = useState(venues[0]?.id ?? "");
  const [mapCenter, setMapCenter] = useState(() => {
    const initialVenue = venues.find((venue) => venue.latitude != null && venue.longitude != null);
    return initialVenue
      ? {
          latitude: initialVenue.latitude ?? DEFAULT_CENTER.latitude,
          longitude: initialVenue.longitude ?? DEFAULT_CENTER.longitude,
        }
      : DEFAULT_CENTER;
  });
  const [draftCoordinates, setDraftCoordinates] = useState<Record<string, { latitude: number; longitude: number }>>({});
  const [draggingVenueId, setDraggingVenueId] = useState<string | null>(null);
  const [isPanningMap, setIsPanningMap] = useState(false);

  const selectedVenue = venues.find((venue) => venue.id === selectedVenueId) ?? venues[0];
  const selectedCoordinate = selectedVenue
    ? draftCoordinates[selectedVenue.id] ?? {
        latitude: selectedVenue.latitude ?? DEFAULT_CENTER.latitude,
        longitude: selectedVenue.longitude ?? DEFAULT_CENTER.longitude,
      }
    : DEFAULT_CENTER;

  const center = mapCenter;
  const tiles = useMemo(() => tileRange(center, zoom, size), [center.latitude, center.longitude, zoom, size]);

  useEffect(() => {
    syncSize();
    const mapElement = mapRef.current;
    if (!mapElement) {
      return;
    }

    const observer = new ResizeObserver(syncSize);
    observer.observe(mapElement);
    return () => observer.disconnect();
  }, []);

  function syncSize() {
    const rect = mapRef.current?.getBoundingClientRect();
    if (!rect) {
      return;
    }
    setSize({ width: rect.width, height: rect.height });
  }

  function mapPointFromEvent(event: PointerEvent) {
    const rect = mapRef.current?.getBoundingClientRect();
    if (!rect) {
      return null;
    }
    return {
      x: event.clientX - rect.left,
      y: event.clientY - rect.top,
    };
  }

  function updateDraggedVenue(event: PointerEvent, venueId: string) {
    const point = mapPointFromEvent(event);
    if (!point) {
      return;
    }
    const coordinate = pointToCoordinate(point, center, zoom, size);
    setDraftCoordinates((current) => ({
      ...current,
      [venueId]: coordinate,
    }));
  }

  function beginMapPan(event: PointerEvent<HTMLDivElement>) {
    const point = mapPointFromEvent(event);
    if (!point) {
      return;
    }

    backgroundDragRef.current = {
      pointerId: event.pointerId,
      startPoint: point,
      startCenter: center,
    };
    event.currentTarget.setPointerCapture(event.pointerId);
    setIsPanningMap(true);
  }

  function updateMapPan(event: PointerEvent<HTMLDivElement>) {
    const drag = backgroundDragRef.current;
    if (!drag || drag.pointerId != event.pointerId) {
      return;
    }

    const point = mapPointFromEvent(event);
    if (!point) {
      return;
    }

    const deltaX = point.x - drag.startPoint.x;
    const deltaY = point.y - drag.startPoint.y;
    const startWorldX = lonToWorldX(drag.startCenter.longitude, zoom);
    const startWorldY = latToWorldY(drag.startCenter.latitude, zoom);

    setMapCenter({
      latitude: worldYToLat(startWorldY - deltaY, zoom),
      longitude: worldXToLon(startWorldX - deltaX, zoom),
    });
  }

  function endMapPan(event: PointerEvent<HTMLDivElement>) {
    if (event.currentTarget.hasPointerCapture(event.pointerId)) {
      event.currentTarget.releasePointerCapture(event.pointerId);
    }
    backgroundDragRef.current = null;
    setIsPanningMap(false);
  }

  return (
    <section className="admin-panel admin-map-panel">
      <div className="admin-section-heading">
        <div>
          <p className="admin-kicker">Drag locations</p>
          <h2>Venue map</h2>
        </div>
        <div className="admin-map-controls">
          <select
            aria-label="Select venue"
            onChange={(event) => {
              const nextVenueId = event.target.value;
              const nextVenue = venues.find((venue) => venue.id === nextVenueId);
              const nextCoordinate = nextVenue
                ? draftCoordinates[nextVenueId] ?? {
                    latitude: nextVenue.latitude ?? DEFAULT_CENTER.latitude,
                    longitude: nextVenue.longitude ?? DEFAULT_CENTER.longitude,
                  }
                : DEFAULT_CENTER;

              setSelectedVenueId(nextVenueId);
              setMapCenter(nextCoordinate);
            }}
            value={selectedVenue?.id ?? ""}
          >
            {venues.map((venue) => (
              <option key={venue.id} value={venue.id}>
                {venue.name}
              </option>
            ))}
          </select>
          <button onClick={() => setZoom((current) => Math.max(14, current - 1))} type="button">
            -
          </button>
          <button onClick={() => setZoom((current) => Math.min(19, current + 1))} type="button">
            +
          </button>
        </div>
      </div>

      <div
        className={`admin-drag-map${isPanningMap ? " panning" : ""}`}
        onPointerDown={(event) => {
          syncSize();
          if (event.target !== event.currentTarget || draggingVenueId) {
            return;
          }
          beginMapPan(event);
        }}
        onPointerMove={(event) => {
          if (backgroundDragRef.current) {
            event.preventDefault();
            updateMapPan(event);
          }
        }}
        onPointerUp={(event) => {
          if (backgroundDragRef.current?.pointerId === event.pointerId) {
            endMapPan(event);
          }
        }}
        onPointerCancel={(event) => {
          if (backgroundDragRef.current?.pointerId === event.pointerId) {
            endMapPan(event);
          }
        }}
        ref={mapRef}
        style={{ touchAction: "none" }}
      >
        {tiles.map((tile) => (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            alt=""
            className="admin-map-tile"
            draggable={false}
            key={tile.key}
            src={`https://tile.openstreetmap.org/${zoom}/${tile.x}/${tile.y}.png`}
            style={{
              left: tile.left,
              top: tile.top,
            }}
          />
        ))}

        {venues.map((venue) => {
          const coordinate = draftCoordinates[venue.id] ?? {
            latitude: venue.latitude,
            longitude: venue.longitude,
          };

          if (coordinate.latitude == null || coordinate.longitude == null) {
            return null;
          }

          const point = coordinateToPoint(
            coordinate.latitude,
            coordinate.longitude,
            center,
            zoom,
            size,
          );
          const selected = selectedVenue?.id === venue.id;

          return (
            <button
              aria-label={`Move ${venue.name}`}
              className={[
                "admin-map-pin",
                selected ? "selected" : "",
                draggingVenueId === venue.id ? "dragging" : "",
              ]
                .filter(Boolean)
                .join(" ")}
              key={venue.id}
              onClick={() => setSelectedVenueId(venue.id)}
              onPointerDown={(event) => {
                event.preventDefault();
                event.stopPropagation();
                event.currentTarget.setPointerCapture(event.pointerId);
                setSelectedVenueId(venue.id);
                setDraggingVenueId(venue.id);
                updateDraggedVenue(event, venue.id);
              }}
              onPointerMove={(event) => {
                if (event.currentTarget.hasPointerCapture(event.pointerId)) {
                  event.preventDefault();
                  updateDraggedVenue(event, venue.id);
                }
              }}
              onPointerUp={(event) => {
                if (event.currentTarget.hasPointerCapture(event.pointerId)) {
                  event.currentTarget.releasePointerCapture(event.pointerId);
                }
                setDraggingVenueId(null);
              }}
              onPointerCancel={(event) => {
                if (event.currentTarget.hasPointerCapture(event.pointerId)) {
                  event.currentTarget.releasePointerCapture(event.pointerId);
                }
                setDraggingVenueId(null);
              }}
              onDragStart={(event) => {
                event.preventDefault();
              }}
              style={{
                left: point.x,
                top: point.y,
                touchAction: "none",
              }}
              type="button"
            >
              <span>{venue.name.slice(0, 1).toUpperCase()}</span>
            </button>
          );
        })}
      </div>

      {selectedVenue ? (
        <form action={updateVenueCoordinatesAction} className="admin-map-save-row">
          <input name="id" type="hidden" value={selectedVenue.id} />
          <label>
            Latitude
            <input
              name="latitude"
              onChange={(event) => {
                const latitude = Number(event.target.value);
                if (Number.isFinite(latitude)) {
                  setDraftCoordinates((current) => ({
                    ...current,
                    [selectedVenue.id]: {
                      latitude,
                      longitude: selectedCoordinate.longitude,
                    },
                  }));
                }
              }}
              step="0.0000001"
              type="number"
              value={formatCoordinate(selectedCoordinate.latitude)}
            />
          </label>
          <label>
            Longitude
            <input
              name="longitude"
              onChange={(event) => {
                const longitude = Number(event.target.value);
                if (Number.isFinite(longitude)) {
                  setDraftCoordinates((current) => ({
                    ...current,
                    [selectedVenue.id]: {
                      latitude: selectedCoordinate.latitude,
                      longitude,
                    },
                  }));
                }
              }}
              step="0.0000001"
              type="number"
              value={formatCoordinate(selectedCoordinate.longitude)}
            />
          </label>
          <button className="admin-primary-button" type="submit">
            Save pin
          </button>
          <a
            className="admin-secondary-link"
            href={`https://www.google.com/maps/search/?api=1&query=${selectedCoordinate.latitude},${selectedCoordinate.longitude}`}
            rel="noreferrer"
            target="_blank"
          >
            Check map
          </a>
        </form>
      ) : null}
    </section>
  );
}
