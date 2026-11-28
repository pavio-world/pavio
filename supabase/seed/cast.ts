/**
 * The demo cast for the Pavio seed (Spec 00, Req 27, design "Seed Design").
 *
 * Everything here is invented. Every row has a fixed uuid so the seed can upsert by id and a second run
 * changes nothing. The only rows without a fixed id are the automatic "all followers" circles, which the
 * database creates itself when a business profile is inserted.
 *
 * This file holds data only: no secrets, no database access.
 */

export const DEMO_EMAIL_DOMAIN = "demo.pavio.world";

/** Handle of a cast profile; used to cross reference rows without repeating uuids. */
export type CastHandle =
  | "amina"
  | "brian"
  | "zawadi"
  | "otieno"
  | "wanjiru"
  | "kahawacorner"
  | "shambafresh";

export type DotColour = "terracotta" | "cherry" | "mustard" | "jade" | "lagoon" | "violet";
export type Audience = "public" | "connections" | "circles";

/** Fixed profile ids. */
export const PROFILE_IDS: Readonly<Record<CastHandle, string>> = {
  amina: "00000000-0000-4000-8000-000000000001",
  brian: "00000000-0000-4000-8000-000000000002",
  zawadi: "00000000-0000-4000-8000-000000000003",
  otieno: "00000000-0000-4000-8000-000000000004",
  wanjiru: "00000000-0000-4000-8000-000000000005",
  kahawacorner: "00000000-0000-4000-8000-000000000006",
  shambafresh: "00000000-0000-4000-8000-000000000007",
};

// ---------------------------------------------------------------------------------------------
// Auth users (Req 27.8). One per person; the seed looks them up by email.
// ---------------------------------------------------------------------------------------------

export type PersonHandle = "amina" | "brian" | "zawadi" | "otieno" | "wanjiru";

export const DEMO_EMAILS: Readonly<Record<PersonHandle, string>> = {
  amina: `amina@${DEMO_EMAIL_DOMAIN}`,
  brian: `brian@${DEMO_EMAIL_DOMAIN}`,
  zawadi: `zawadi@${DEMO_EMAIL_DOMAIN}`,
  otieno: `otieno@${DEMO_EMAIL_DOMAIN}`,
  wanjiru: `wanjiru@${DEMO_EMAIL_DOMAIN}`,
};

// ---------------------------------------------------------------------------------------------
// Profiles (Req 27.2, 27.3)
// ---------------------------------------------------------------------------------------------

export interface CastProfile {
  readonly id: string;
  readonly type: "person" | "business";
  readonly handle: CastHandle;
  readonly displayName: string;
  readonly bio: string;
  readonly city: string;
  /** ISO 3166-1 alpha-2, upper case. */
  readonly country: string;
  readonly preferredLanguage: "en" | "sw";
  readonly dotColour: DotColour;
  /** Lower case, trimmed; these drive search. */
  readonly whatIDo: readonly string[];
  /** Email of the owning login for a person; null for a business. */
  readonly ownerEmail: string | null;
}

export const PROFILES: readonly CastProfile[] = [
  {
    id: PROFILE_IDS.amina,
    type: "person",
    handle: "amina",
    displayName: "Amina Wekesa",
    bio: "Nutritionist in Nairobi. I help busy people eat well with food they already love.",
    city: "Nairobi",
    country: "KE",
    preferredLanguage: "en",
    dotColour: "jade",
    whatIDo: ["nutritionist", "meal plans", "gut health"],
    ownerEmail: DEMO_EMAILS.amina,
  },
  {
    id: PROFILE_IDS.brian,
    type: "person",
    handle: "brian",
    displayName: "Brian Kamau",
    bio: "Founder and angel investor. Building small fintech tools for market traders.",
    city: "Nairobi",
    country: "KE",
    preferredLanguage: "en",
    dotColour: "lagoon",
    whatIDo: ["founder", "fintech", "angel investor"],
    ownerEmail: DEMO_EMAILS.brian,
  },
  {
    id: PROFILE_IDS.zawadi,
    type: "person",
    handle: "zawadi",
    displayName: "Zawadi Achieng",
    bio: "Photographer. Portraits, weddings and festivals along the coast.",
    city: "Mombasa",
    country: "KE",
    preferredLanguage: "sw",
    dotColour: "mustard",
    whatIDo: ["photographer", "portraits", "events"],
    ownerEmail: DEMO_EMAILS.zawadi,
  },
  {
    id: PROFILE_IDS.otieno,
    type: "person",
    handle: "otieno",
    displayName: "Otieno Ouma",
    bio: "Plumber in Kisumu. Solar water heaters fitted and repaired.",
    city: "Kisumu",
    country: "KE",
    preferredLanguage: "en",
    dotColour: "cherry",
    whatIDo: ["plumber", "solar water heaters"],
    ownerEmail: DEMO_EMAILS.otieno,
  },
  {
    id: PROFILE_IDS.wanjiru,
    type: "person",
    handle: "wanjiru",
    displayName: "Wanjiru Njeri",
    bio: "Software engineer who mentors people starting out in tech.",
    city: "Nakuru",
    country: "KE",
    preferredLanguage: "en",
    dotColour: "violet",
    whatIDo: ["software engineer", "mentor"],
    ownerEmail: DEMO_EMAILS.wanjiru,
  },
  {
    id: PROFILE_IDS.kahawacorner,
    type: "business",
    handle: "kahawacorner",
    displayName: "Kahawa Corner",
    bio: "Neighbourhood cafe. Single origin coffee, all day breakfast and fast wifi.",
    city: "Nairobi",
    country: "KE",
    preferredLanguage: "en",
    dotColour: "terracotta",
    whatIDo: ["coffee", "breakfast", "wifi"],
    ownerEmail: null,
  },
  {
    id: PROFILE_IDS.shambafresh,
    type: "business",
    handle: "shambafresh",
    displayName: "Shamba Fresh Supplies",
    bio: "Fresh produce from smallholder farms, delivered to cafes and restaurants.",
    city: "Kisumu",
    country: "KE",
    preferredLanguage: "en",
    dotColour: "jade",
    whatIDo: ["fresh produce", "wholesale"],
    ownerEmail: null,
  },
];

// ---------------------------------------------------------------------------------------------
// Business details and managers (Req 27.3)
// ---------------------------------------------------------------------------------------------

export interface CastBusinessDetails {
  readonly id: string;
  readonly profile: CastHandle;
  readonly category: string;
  readonly phone: string;
  readonly website: string;
  /** Keys mon..sun; null means closed. Matches private.opening_hours_valid. */
  readonly openingHours: Readonly<Record<string, { open: string; close: string } | null>>;
  readonly address: string;
}

export const BUSINESS_DETAILS: readonly CastBusinessDetails[] = [
  {
    id: "00000000-0000-4000-8000-0000000000b1",
    profile: "kahawacorner",
    category: "Cafe",
    phone: "+254 700 000 101",
    website: "https://kahawacorner.example.com",
    openingHours: {
      mon: { open: "07:00", close: "19:00" },
      tue: { open: "07:00", close: "19:00" },
      wed: { open: "07:00", close: "19:00" },
      thu: { open: "07:00", close: "19:00" },
      fri: { open: "07:00", close: "21:00" },
      sat: { open: "08:00", close: "21:00" },
      sun: null,
    },
    address: "12 Mwanzi Road, Nairobi",
  },
  {
    id: "00000000-0000-4000-8000-0000000000b2",
    profile: "shambafresh",
    category: "Food supplier",
    phone: "+254 700 000 102",
    website: "https://shambafresh.example.com",
    openingHours: {
      mon: { open: "06:00", close: "17:00" },
      tue: { open: "06:00", close: "17:00" },
      wed: { open: "06:00", close: "17:00" },
      thu: { open: "06:00", close: "17:00" },
      fri: { open: "06:00", close: "17:00" },
      sat: { open: "06:00", close: "13:00" },
      sun: null,
    },
    address: "Kibuye Market Road, Kisumu",
  },
];

export interface CastProfileManager {
  readonly id: string;
  readonly profile: CastHandle;
  /** The person whose login manages the business. */
  readonly user: PersonHandle;
  readonly role: "owner" | "manager";
}

export const PROFILE_MANAGERS: readonly CastProfileManager[] = [
  { id: "00000000-0000-4000-8000-0000000000c1", profile: "kahawacorner", user: "brian", role: "owner" },
  { id: "00000000-0000-4000-8000-0000000000c2", profile: "kahawacorner", user: "wanjiru", role: "manager" },
  { id: "00000000-0000-4000-8000-0000000000c3", profile: "shambafresh", user: "otieno", role: "owner" },
];

// ---------------------------------------------------------------------------------------------
// Relationships (Req 27.4). Inserted with "where not exists" on the unordered pair and type, so
// they carry no fixed id; the pair and type identify them.
// ---------------------------------------------------------------------------------------------

export interface CastRelationship {
  readonly requester: CastHandle;
  readonly target: CastHandle;
  readonly type: "connection" | "follow";
  /** Connections are always inserted as pending; "accepted" makes the seed accept them afterwards. */
  readonly finalStatus: "pending" | "accepted";
}

export const RELATIONSHIPS: readonly CastRelationship[] = [
  // Accepted connections between people
  { requester: "amina", target: "brian", type: "connection", finalStatus: "accepted" },
  { requester: "amina", target: "zawadi", type: "connection", finalStatus: "accepted" },
  { requester: "amina", target: "wanjiru", type: "connection", finalStatus: "accepted" },
  { requester: "brian", target: "zawadi", type: "connection", finalStatus: "accepted" },
  { requester: "brian", target: "otieno", type: "connection", finalStatus: "accepted" },
  // Pending request
  { requester: "wanjiru", target: "otieno", type: "connection", finalStatus: "pending" },
  // Business to business connection
  { requester: "kahawacorner", target: "shambafresh", type: "connection", finalStatus: "accepted" },
  // Follows to the cafe (Brian owns it, so he cannot follow it)
  { requester: "amina", target: "kahawacorner", type: "follow", finalStatus: "accepted" },
  { requester: "zawadi", target: "kahawacorner", type: "follow", finalStatus: "accepted" },
  { requester: "otieno", target: "kahawacorner", type: "follow", finalStatus: "accepted" },
];

// ---------------------------------------------------------------------------------------------
// Circles (Req 27.5). The automatic "all followers" circle of Kahawa Corner is created by the
// database, so it is not listed here and has no fixed id.
// ---------------------------------------------------------------------------------------------

export interface CastCircle {
  readonly id: string;
  readonly owner: CastHandle;
  readonly privateName: string;
  readonly showMemberLabel: boolean;
  /** Null when the switch is off. When on, differs from privateName for at least one circle. */
  readonly memberLabel: string | null;
  readonly members: readonly CastHandle[];
}

export const CIRCLES: readonly CastCircle[] = [
  {
    id: "00000000-0000-4000-8000-0000000000d1",
    owner: "amina",
    privateName: "family",
    showMemberLabel: true,
    memberLabel: "Fam",
    members: ["wanjiru"],
  },
  {
    id: "00000000-0000-4000-8000-0000000000d2",
    owner: "amina",
    privateName: "close friends",
    showMemberLabel: false,
    memberLabel: null,
    members: ["zawadi"],
  },
  {
    id: "00000000-0000-4000-8000-0000000000d3",
    owner: "brian",
    privateName: "the cabal",
    showMemberLabel: true,
    memberLabel: "Inner circle",
    members: ["amina", "zawadi"],
  },
  {
    id: "00000000-0000-4000-8000-0000000000d4",
    owner: "kahawacorner",
    privateName: "suppliers",
    showMemberLabel: false,
    memberLabel: null,
    members: ["shambafresh"],
  },
];

/** Circle id by owner and private name, for the content and vouch tables below. */
export const CIRCLE_IDS = {
  aminaFamily: CIRCLES[0]!.id,
  aminaCloseFriends: CIRCLES[1]!.id,
  brianCabal: CIRCLES[2]!.id,
  kahawaSuppliers: CIRCLES[3]!.id,
} as const;

// ---------------------------------------------------------------------------------------------
// Content items (Req 27.6)
// ---------------------------------------------------------------------------------------------

/**
 * Where the item's circles come from. "circle" links to a hand made circle by id; "all-followers" links
 * to the automatic all followers circle of the owner, which the seed looks up (it has no fixed id).
 */
export type CastItemCircle = { readonly circleId: string } | { readonly allFollowersOf: CastHandle };

export interface CastContentItem {
  readonly id: string;
  readonly owner: CastHandle;
  readonly contentType: "writing" | "gallery" | "status" | "story";
  readonly audience: Audience;
  /** Matches private.content_details_valid; image paths are object paths only, no files are uploaded. */
  readonly details: Readonly<Record<string, string>>;
  readonly circles: readonly CastItemCircle[];
  /**
   * Stories only. Hours before the seed run that the story was created: 0 for an active story
   * (created_at = now(), so it always has about 24 hours left), 30 for an expired one.
   */
  readonly createdHoursAgo?: number;
}

const GALLERY_PATH_AMINA = `${PROFILE_IDS.amina}/gallery/market-breakfast.jpg`;
const GALLERY_PATH_BRIAN = `${PROFILE_IDS.brian}/gallery/team-offsite.jpg`;
const STORY_PATH_AMINA = `${PROFILE_IDS.amina}/story/sunday-lunch.jpg`;
const STORY_PATH_ZAWADI = `${PROFILE_IDS.zawadi}/story/old-town-sunrise.jpg`;
const STORY_PATH_KAHAWA = `${PROFILE_IDS.kahawacorner}/story/new-blend.jpg`;

export const CONTENT_ITEMS: readonly CastContentItem[] = [
  // One status per person, replaced by whatever the owner posts next (Wanjiru's is public)
  {
    id: "00000000-0000-4000-8000-0000000000e1",
    owner: "amina",
    contentType: "status",
    audience: "connections",
    details: { text: "Booking clients for December" },
    circles: [],
  },
  {
    id: "00000000-0000-4000-8000-0000000000e2",
    owner: "brian",
    contentType: "status",
    audience: "connections",
    details: { text: "Raising a seed round" },
    circles: [],
  },
  {
    id: "00000000-0000-4000-8000-0000000000e3",
    owner: "zawadi",
    contentType: "status",
    audience: "connections",
    details: { text: "On a shoot in Lamu" },
    circles: [],
  },
  {
    id: "00000000-0000-4000-8000-0000000000e4",
    owner: "otieno",
    contentType: "status",
    audience: "connections",
    details: { text: "Available weekends" },
    circles: [],
  },
  {
    id: "00000000-0000-4000-8000-0000000000e5",
    owner: "wanjiru",
    contentType: "status",
    audience: "public",
    details: { text: "On leave" },
    circles: [],
  },
  // Public writing (always public)
  {
    id: "00000000-0000-4000-8000-0000000000e6",
    owner: "amina",
    contentType: "writing",
    audience: "public",
    details: {
      title: "Five Kenyan breakfasts under 300 calories",
      body:
        "Breakfast does not need to be heavy to be satisfying. Here are five Kenyan breakfasts that stay under 300 calories: " +
        "uji with a spoon of peanut butter, boiled arrow roots with kachumbari, a small mandazi with plain yoghurt, " +
        "sweet potato with a boiled egg, and a mukimo patty with greens.",
    },
    circles: [],
  },
  // Gallery: connections audience
  {
    id: "00000000-0000-4000-8000-0000000000e7",
    owner: "amina",
    contentType: "gallery",
    audience: "connections",
    details: { image_path: GALLERY_PATH_AMINA, caption: "Saturday market haul" },
    circles: [],
  },
  // Gallery: circle audience (the cabal)
  {
    id: "00000000-0000-4000-8000-0000000000e8",
    owner: "brian",
    contentType: "gallery",
    audience: "circles",
    details: { image_path: GALLERY_PATH_BRIAN, caption: "Team offsite, Naivasha" },
    circles: [{ circleId: CIRCLE_IDS.brianCabal }],
  },
  // Active story shared to family (Wanjiru sees the label "Fam")
  {
    id: "00000000-0000-4000-8000-0000000000e9",
    owner: "amina",
    contentType: "story",
    audience: "circles",
    details: { image_path: STORY_PATH_AMINA, text: "Sunday lunch with the family" },
    circles: [{ circleId: CIRCLE_IDS.aminaFamily }],
    createdHoursAgo: 0,
  },
  // Expired public story (created 30 hours ago, so past its 24 hour life)
  {
    id: "00000000-0000-4000-8000-0000000000ea",
    owner: "zawadi",
    contentType: "story",
    audience: "public",
    details: { image_path: STORY_PATH_ZAWADI, text: "Sunrise over Old Town" },
    circles: [],
    createdHoursAgo: 30,
  },
  // Business story for all followers (followers see "Shared with you")
  {
    id: "00000000-0000-4000-8000-0000000000eb",
    owner: "kahawacorner",
    contentType: "story",
    audience: "circles",
    details: { image_path: STORY_PATH_KAHAWA, text: "New house blend, in from today" },
    circles: [{ allFollowersOf: "kahawacorner" }],
    createdHoursAgo: 0,
  },
];

// ---------------------------------------------------------------------------------------------
// Vouches (Req 27.7). One per author and subject. After the seed, Amina has Search_Trust 2
// (Brian and Zawadi feature her publicly).
// ---------------------------------------------------------------------------------------------

export interface CastVouch {
  readonly id: string;
  readonly author: CastHandle;
  readonly subject: CastHandle;
  readonly body: string;
  readonly audience: Audience;
  /** The author's Top 8 position, or null when the vouch is not featured. */
  readonly top8Position: number | null;
  /** True when the subject hides it from their page. Set by a separate update after the upsert. */
  readonly hiddenBySubject: boolean;
  readonly circles: readonly CastItemCircle[];
}

export const VOUCHES: readonly CastVouch[] = [
  {
    id: "00000000-0000-4000-8000-0000000000f1",
    author: "brian",
    subject: "amina",
    body: "Amina rebuilt my eating habits during a very stressful year. Practical and kind.",
    audience: "public",
    top8Position: 1,
    hiddenBySubject: false,
    circles: [],
  },
  {
    id: "00000000-0000-4000-8000-0000000000f2",
    author: "zawadi",
    subject: "amina",
    body: "The meal plan Amina made for my shoot weeks changed how I work.",
    audience: "public",
    top8Position: 1,
    hiddenBySubject: false,
    circles: [],
  },
  {
    id: "00000000-0000-4000-8000-0000000000f3",
    author: "amina",
    subject: "brian",
    body: "Brian explains money clearly and never wastes your time.",
    audience: "connections",
    top8Position: 1,
    hiddenBySubject: false,
    circles: [],
  },
  {
    id: "00000000-0000-4000-8000-0000000000f4",
    author: "amina",
    subject: "zawadi",
    body: "Zawadi makes everyone look like themselves on a good day.",
    audience: "circles",
    top8Position: null,
    hiddenBySubject: false,
    circles: [{ circleId: CIRCLE_IDS.aminaCloseFriends }],
  },
  {
    id: "00000000-0000-4000-8000-0000000000f5",
    author: "brian",
    subject: "zawadi",
    body: "Zawadi shot our launch in one afternoon and the photos still hold up.",
    audience: "public",
    top8Position: null,
    hiddenBySubject: false,
    circles: [],
  },
  {
    id: "00000000-0000-4000-8000-0000000000f6",
    author: "amina",
    subject: "kahawacorner",
    body: "The best flat white in Nairobi, and the wifi actually works.",
    audience: "public",
    top8Position: 2,
    hiddenBySubject: false,
    circles: [],
  },
  {
    id: "00000000-0000-4000-8000-0000000000f7",
    author: "wanjiru",
    subject: "amina",
    body: "Amina is the first person I call when I want honest advice about food.",
    audience: "connections",
    top8Position: null,
    hiddenBySubject: true,
    circles: [],
  },
];
