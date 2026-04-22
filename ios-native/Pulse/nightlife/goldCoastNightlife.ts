/**
 * Starter nightlife seed for Spilltop, focused on the Gold Coast launch market.
 * This is not a guaranteed list of every active venue. Venue inventories shift
 * often, so production should reconcile against Google Places or another live
 * venue source before promoting changes broadly.
 */

export type VenueType =
  | "bar"
  | "bar_club"
  | "beach_club"
  | "club_bar"
  | "live_music"
  | "nightclub"
  | "rooftop_bar";

export interface Venue {
  id: string;
  name: string;
  type: VenueType;
  suburb: string;
  precinct: string;
  address: string;
  vibe: string[];
  priceLevel: number;
  nightlifeScore: number;
  featured: boolean;
}

export interface Precinct {
  id: string;
  name: string;
  description: string;
  priority: number;
}

export const goldCoastNightlifeVenues: Venue[] = [
  {
    id: "the-avenue-surfers",
    name: "The Avenue",
    type: "bar_club",
    suburb: "Surfers Paradise",
    precinct: "Orchid Avenue",
    address: "3-15 Orchid Avenue, Surfers Paradise QLD 4217",
    vibe: ["live music", "party", "late night"],
    priceLevel: 2,
    nightlifeScore: 9,
    featured: true,
  },
  {
    id: "bedroom-lounge-bar",
    name: "Bedroom Lounge Bar",
    type: "nightclub",
    suburb: "Surfers Paradise",
    precinct: "Orchid Avenue",
    address: "26 Orchid Ave, Surfers Paradise QLD 4217",
    vibe: ["vip", "dance", "late night", "rnb", "edm"],
    priceLevel: 3,
    nightlifeScore: 9,
    featured: true,
  },
  {
    id: "havana-rnb",
    name: "Havana RnB Nightclub",
    type: "nightclub",
    suburb: "Surfers Paradise",
    precinct: "Orchid Avenue",
    address: "26 Orchid Ave, Surfers Paradise QLD 4217",
    vibe: ["rnb", "hip hop", "late night"],
    priceLevel: 3,
    nightlifeScore: 8,
    featured: true,
  },
  {
    id: "elsewhere",
    name: "Elsewhere",
    type: "club_bar",
    suburb: "Surfers Paradise",
    precinct: "Cavill Avenue",
    address: "1/23 Cavill Ave, Surfers Paradise QLD 4217",
    vibe: ["indie", "dj", "local scene", "late night"],
    priceLevel: 2,
    nightlifeScore: 8,
    featured: true,
  },
  {
    id: "cali-beach-club",
    name: "Cali Beach Club",
    type: "beach_club",
    suburb: "Surfers Paradise",
    precinct: "Elkhorn Avenue",
    address: "21a Elkhorn Ave, Surfers Paradise QLD 4217",
    vibe: ["day party", "pool club", "upscale", "events"],
    priceLevel: 3,
    nightlifeScore: 8,
    featured: true,
  },
  {
    id: "the-island-rooftop",
    name: "The Island Rooftop",
    type: "rooftop_bar",
    suburb: "Surfers Paradise",
    precinct: "Surfers CBD",
    address: "3128 Surfers Paradise Blvd, Surfers Paradise QLD 4217",
    vibe: ["rooftop", "cocktails", "dj", "social"],
    priceLevel: 3,
    nightlifeScore: 8,
    featured: true,
  },
  {
    id: "skypoint-bistro-bar",
    name: "SkyPoint Bistro + Bar",
    type: "bar",
    suburb: "Surfers Paradise",
    precinct: "Q1",
    address:
      "Level 77, Q1 Building, Corner of Clifford St & Surfers Paradise Blvd, Surfers Paradise QLD 4217",
    vibe: ["views", "cocktails", "date night", "tourist"],
    priceLevel: 3,
    nightlifeScore: 7,
    featured: false,
  },
  {
    id: "nineteen-at-the-star",
    name: "Nineteen at The Star",
    type: "rooftop_bar",
    suburb: "Broadbeach",
    precinct: "The Star",
    address: "Level 19, The Darling, 1 Casino Drive, Broadbeach QLD 4218",
    vibe: ["luxury", "rooftop", "cocktails", "upscale"],
    priceLevel: 4,
    nightlifeScore: 8,
    featured: true,
  },
  {
    id: "atrium-bar",
    name: "Atrium Bar",
    type: "bar",
    suburb: "Broadbeach",
    precinct: "The Star",
    address:
      "Casino Level, The Star Gold Coast, Broadbeach Island, Broadbeach QLD 4218",
    vibe: ["cocktails", "live music", "casino", "social"],
    priceLevel: 3,
    nightlifeScore: 7,
    featured: false,
  },
  {
    id: "burleigh-pavilion",
    name: "Burleigh Pavilion",
    type: "bar",
    suburb: "Burleigh Heads",
    precinct: "Burleigh beachfront",
    address: "3a/43 Goodwin Terrace, Burleigh Heads QLD 4220",
    vibe: ["beachfront", "social", "sunday session", "events"],
    priceLevel: 3,
    nightlifeScore: 8,
    featured: true,
  },
  {
    id: "justin-lane",
    name: "Justin Lane",
    type: "rooftop_bar",
    suburb: "Burleigh Heads",
    precinct: "Gold Coast Highway",
    address: "1708-1710 Gold Coast Highway, Burleigh Heads QLD 4220",
    vibe: ["rooftop", "cocktails", "dining", "social"],
    priceLevel: 3,
    nightlifeScore: 7,
    featured: true,
  },
  {
    id: "miami-marketta",
    name: "Miami Marketta",
    type: "live_music",
    suburb: "Miami",
    precinct: "Miami",
    address: "23 Hillcrest Parade, Miami QLD 4220",
    vibe: ["live music", "street food", "creative", "events"],
    priceLevel: 2,
    nightlifeScore: 7,
    featured: true,
  },
];

export const goldCoastNightlifePrecincts: Precinct[] = [
  {
    id: "surfers-paradise",
    name: "Surfers Paradise",
    description:
      "Main party hub with clubs, bars, rooftops and tourist nightlife.",
    priority: 1,
  },
  {
    id: "broadbeach",
    name: "Broadbeach",
    description: "More upscale nightlife with casino, cocktails and lounges.",
    priority: 2,
  },
  {
    id: "burleigh-heads",
    name: "Burleigh Heads",
    description: "Trendy coastal nightlife with social bars and rooftops.",
    priority: 3,
  },
  {
    id: "miami",
    name: "Miami",
    description: "Creative nightlife, live music and event-driven venues.",
    priority: 4,
  },
];
