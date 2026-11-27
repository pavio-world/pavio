// fast-check generators and fixture insert helpers for the property suite
// (Requirement 26.1). Design: "Property harness (Requirement 26)".
//
// How a case runs:
//   1. `scenarioArb` generates a whole world as plain data. It holds no ids:
//      every reference between records is a number that the insert helpers
//      resolve with `pick` (modulo the list length), so any number is valid and
//      shrinking never produces a dangling reference.
//   2. `insertScenario(client, scenario)` inserts that world as the TEST OWNER
//      (no `set local role`), inside the transaction of `withRolledBackTx`.
//      Structural triggers still fire. Records that the database rejects
//      (illegal relationships, memberships, vouches) are skipped inside a
//      savepoint and reported in the returned fixture; the legal rules are
//      never re-implemented here.
//   3. The test then calls `asUser` from db.ts with `resolveViewer(...)`.
//
// Names that must never leak (circle private names) are random tokens prefixed
// `priv-`, member labels are prefixed `label-`, so a leak is easy to detect and
// a label can never equal its private name.
import fc from "fast-check";
import type { Client } from "pg";

// ---------------------------------------------------------------------------
// Shared types
// ---------------------------------------------------------------------------

export type ProfileType = "person" | "business";
export type DotColour = "terracotta" | "cherry" | "mustard" | "jade" | "lagoon" | "violet";
export type ContentType = "writing" | "gallery" | "status" | "story";
export type Audience = "public" | "connections" | "circles" | "group";
export type VouchAudience = "public" | "connections" | "circles";

export const DOT_COLOURS: readonly DotColour[] = [
  "terracotta",
  "cherry",
  "mustard",
  "jade",
  "lagoon",
  "violet",
];
export const AUDIENCES: readonly Audience[] = ["public", "connections", "circles", "group"];
export const VOUCH_AUDIENCES: readonly VouchAudience[] = ["public", "connections", "circles"];

/** Largest index the generators emit. Helpers reduce it with `pick`. */
const MAX_INDEX = 1000;

/** Picks `list[index mod length]`, or undefined for an empty list. */
export function pick<T>(list: readonly T[], index: number): T | undefined {
  return list.length === 0 ? undefined : list[index % list.length];
}

// ---------------------------------------------------------------------------
// Specs (plain generated data)
// ---------------------------------------------------------------------------

/** A login in auth.users. The email is made unique at insert time. */
export interface LoginSpec {
  emailTag: string;
}

export interface ProfileSpec {
  type: ProfileType;
  displayName: string;
  bio: string | null;
  dotColour: DotColour;
  whatIDo: string[];
  city: string | null;
}

/** A person profile and the login that owns it. */
export interface PersonSpec extends ProfileSpec {
  type: "person";
  login: LoginSpec;
}

/** A business profile. Its owner is a person, chosen by `ownerPick`. */
export interface BusinessSpec extends ProfileSpec {
  type: "business";
  ownerPick: number;
  category: string | null;
}

/** An extra row in profile_managers, beyond the business owner. */
export interface ManagerSpec {
  businessPick: number;
  personPick: number;
  role: "owner" | "manager";
}

export type RelationshipShape =
  // legal
  | "person_connection"
  | "business_connection"
  | "person_follows_business"
  // illegal
  | "business_to_person"
  | "person_follows_person"
  | "business_follows_business"
  | "connection_person_business"
  | "self"
  | "managed_page";

export const LEGAL_RELATIONSHIP_SHAPES: readonly RelationshipShape[] = [
  "person_connection",
  "business_connection",
  "person_follows_business",
];
export const ILLEGAL_RELATIONSHIP_SHAPES: readonly RelationshipShape[] = [
  "business_to_person",
  "person_follows_person",
  "business_follows_business",
  "connection_person_business",
  "self",
  "managed_page",
];

export interface RelationshipSpec {
  shape: RelationshipShape;
  /** Which profile within the shape's pool is the requester. */
  requesterPick: number;
  /** Which profile within the shape's pool is the target. */
  targetPick: number;
  /** Final status for a connection (a follow is always accepted). */
  status: "pending" | "accepted" | "declined";
}

export interface CircleSpec {
  ownerPick: number;
  /** Never shown to anyone but the owner. Prefixed `priv-`. */
  privateName: string;
  showMemberLabel: boolean;
  /** Prefixed `label-`, so it always differs from the private name. */
  memberLabel: string;
}

export interface MembershipSpec {
  circlePick: number;
  /**
   * `audience`: try the owner's audience first (accepted connections, followers
   * of a business). `any`: try one random profile, which is usually illegal.
   */
  strategy: "audience" | "any";
  memberPick: number;
}

export interface GroupSpec {
  ownerPick: number;
  name: string;
  memberPicks: number[];
}

export type ContentDetailsSpec =
  | { kind: "writing"; title: string; body: string; withCover: boolean }
  | { kind: "gallery"; caption: string | null }
  | { kind: "status"; text: string; emoji: string | null }
  | { kind: "story"; text: string | null; withImage: boolean };

export interface ContentSpec {
  ownerPick: number;
  details: ContentDetailsSpec;
  /** Requested audience. A writing is always public, whatever is asked. */
  audience: Audience;
  /** Which of the owner's circles an item with audience `circles` is shared to. */
  circlePicks: number[];
  /** Which of the owner's groups an item with audience `group` belongs to. */
  groupPick: number;
  /** Age at insert. Stories older than 24 hours are expired (see `isExpiredStory`). */
  ageHours: number;
  /** Index of an earlier item of the same owner to nest under, or null. */
  parentPick: number | null;
}

export interface VouchSpec {
  authorPick: number;
  /** `eligible`: try subjects until the guard accepts one. `any`: try one. */
  strategy: "eligible" | "any";
  subjectPick: number;
  body: string;
  audience: VouchAudience;
  circlePicks: number[];
  /** Ask for a Top 8 slot (positions are assigned in order, at most 8 per author). */
  featured: boolean;
  hiddenBySubject: boolean;
}

export interface ScenarioSpec {
  persons: PersonSpec[];
  businesses: BusinessSpec[];
  managers: ManagerSpec[];
  relationships: RelationshipSpec[];
  circles: CircleSpec[];
  memberships: MembershipSpec[];
  groups: GroupSpec[];
  content: ContentSpec[];
  vouches: VouchSpec[];
}

/** A simulated viewer: a signed out visitor or a profile being acted as. */
export type ViewerSpec = { kind: "anon" } | { kind: "profile"; pick: number };

// ---------------------------------------------------------------------------
// Generators
// ---------------------------------------------------------------------------

const indexArb = fc.nat(MAX_INDEX);
const tokenArb = fc.stringMatching(/^[a-z0-9]{4,12}$/);
const wordArb = fc.stringMatching(/^[a-z][a-z ]{0,20}[a-z]$/);
const textArb = (min: number, max: number) =>
  fc.stringMatching(new RegExp(`^[A-Za-z][A-Za-z0-9 ,.]{${min - 1},${max - 1}}$`));

export const loginArb: fc.Arbitrary<LoginSpec> = fc.record({ emailTag: tokenArb });

export const dotColourArb: fc.Arbitrary<DotColour> = fc.constantFrom(...DOT_COLOURS);

/** Tags must be lower case and trimmed (private.tags_valid). */
const whatIDoArb = fc.array(fc.stringMatching(/^[a-z][a-z]{1,11}$/), { maxLength: 4 });

const profileBase = {
  displayName: textArb(1, 40),
  bio: fc.option(textArb(1, 120), { nil: null }),
  dotColour: dotColourArb,
  whatIDo: whatIDoArb,
  city: fc.option(textArb(2, 20), { nil: null }),
};

export const personArb: fc.Arbitrary<PersonSpec> = fc.record({
  type: fc.constant("person" as const),
  login: loginArb,
  ...profileBase,
});

export const businessArb: fc.Arbitrary<BusinessSpec> = fc.record({
  type: fc.constant("business" as const),
  ownerPick: indexArb,
  category: fc.option(wordArb, { nil: null }),
  ...profileBase,
});

export const managerArb: fc.Arbitrary<ManagerSpec> = fc.record({
  businessPick: indexArb,
  personPick: indexArb,
  role: fc.constantFrom("owner" as const, "manager" as const),
});

export const relationshipShapeArb: fc.Arbitrary<RelationshipShape> = fc.constantFrom(
  ...LEGAL_RELATIONSHIP_SHAPES,
  ...ILLEGAL_RELATIONSHIP_SHAPES,
);

export const legalRelationshipArb: fc.Arbitrary<RelationshipSpec> = fc.record({
  shape: fc.constantFrom(...LEGAL_RELATIONSHIP_SHAPES),
  requesterPick: indexArb,
  targetPick: indexArb,
  status: fc.constantFrom("pending" as const, "accepted" as const, "declined" as const),
});

export const illegalRelationshipArb: fc.Arbitrary<RelationshipSpec> = fc.record({
  shape: fc.constantFrom(...ILLEGAL_RELATIONSHIP_SHAPES),
  requesterPick: indexArb,
  targetPick: indexArb,
  status: fc.constantFrom("pending" as const, "accepted" as const, "declined" as const),
});

/** Legal and illegal shapes, weighted towards legal so worlds are not empty. */
export const relationshipArb: fc.Arbitrary<RelationshipSpec> = fc.oneof(
  { arbitrary: legalRelationshipArb, weight: 3 },
  { arbitrary: illegalRelationshipArb, weight: 1 },
);

export const circleArb: fc.Arbitrary<CircleSpec> = fc.record({
  ownerPick: indexArb,
  privateName: tokenArb.map((t) => `priv-${t}`),
  showMemberLabel: fc.boolean(),
  memberLabel: tokenArb.map((t) => `label-${t}`),
});

export const membershipArb: fc.Arbitrary<MembershipSpec> = fc.record({
  circlePick: indexArb,
  strategy: fc.constantFrom("audience" as const, "audience" as const, "any" as const),
  memberPick: indexArb,
});

export const groupArb: fc.Arbitrary<GroupSpec> = fc.record({
  ownerPick: indexArb,
  name: textArb(1, 30),
  memberPicks: fc.array(indexArb, { maxLength: 3 }),
});

export const contentDetailsArb: fc.Arbitrary<ContentDetailsSpec> = fc.oneof(
  fc.record({
    kind: fc.constant("writing" as const),
    title: textArb(1, 60),
    body: textArb(1, 200),
    withCover: fc.boolean(),
  }),
  fc.record({
    kind: fc.constant("gallery" as const),
    caption: fc.option(textArb(1, 80), { nil: null }),
  }),
  fc.record({
    kind: fc.constant("status" as const),
    text: textArb(1, 60),
    emoji: fc.option(fc.constantFrom("🌴", "☕", "🚀"), { nil: null }),
  }),
  fc.record({
    kind: fc.constant("story" as const),
    text: fc.option(textArb(1, 100), { nil: null }),
    withImage: fc.boolean(),
  }),
);

/** Age in hours: a fresh story is under 24, an expired one well over. */
export const freshAgeHoursArb = fc.integer({ min: 0, max: 23 });
export const expiredAgeHoursArb = fc.integer({ min: 25, max: 240 });

export const contentArb: fc.Arbitrary<ContentSpec> = fc.record({
  ownerPick: indexArb,
  details: contentDetailsArb,
  audience: fc.constantFrom(...AUDIENCES),
  circlePicks: fc.array(indexArb, { minLength: 1, maxLength: 3 }),
  groupPick: indexArb,
  ageHours: fc.oneof(freshAgeHoursArb, expiredAgeHoursArb),
  parentPick: fc.option(indexArb, { nil: null }),
});

/** A story that has already expired: always a story, older than 24 hours. */
export const expiredStoryArb: fc.Arbitrary<ContentSpec> = fc.record({
  ownerPick: indexArb,
  details: fc.record({
    kind: fc.constant("story" as const),
    text: textArb(1, 100).map((t): string | null => t),
    withImage: fc.boolean(),
  }),
  audience: fc.constantFrom(...AUDIENCES),
  circlePicks: fc.array(indexArb, { minLength: 1, maxLength: 3 }),
  groupPick: indexArb,
  ageHours: expiredAgeHoursArb,
  parentPick: fc.constant(null),
});

export const vouchArb: fc.Arbitrary<VouchSpec> = fc.record({
  authorPick: indexArb,
  strategy: fc.constantFrom("eligible" as const, "eligible" as const, "any" as const),
  subjectPick: indexArb,
  body: textArb(1, 120),
  audience: fc.constantFrom(...VOUCH_AUDIENCES),
  circlePicks: fc.array(indexArb, { minLength: 1, maxLength: 3 }),
  featured: fc.boolean(),
  hiddenBySubject: fc.boolean(),
});

export const viewerArb: fc.Arbitrary<ViewerSpec> = fc.oneof(
  { arbitrary: fc.constant<ViewerSpec>({ kind: "anon" }), weight: 1 },
  {
    arbitrary: indexArb.map((pick): ViewerSpec => ({ kind: "profile", pick })),
    weight: 4,
  },
);

/** A whole world: 2 to 5 people, 0 to 2 businesses, and the records between them. */
export const scenarioArb: fc.Arbitrary<ScenarioSpec> = fc.record({
  persons: fc.array(personArb, { minLength: 2, maxLength: 5 }),
  businesses: fc.array(businessArb, { maxLength: 2 }),
  managers: fc.array(managerArb, { maxLength: 3 }),
  relationships: fc.array(relationshipArb, { maxLength: 12 }),
  circles: fc.array(circleArb, { maxLength: 5 }),
  memberships: fc.array(membershipArb, { maxLength: 12 }),
  groups: fc.array(groupArb, { maxLength: 2 }),
  content: fc.array(contentArb, { maxLength: 10 }),
  vouches: fc.array(vouchArb, { maxLength: 8 }),
});

// ---------------------------------------------------------------------------
// Fixture result
// ---------------------------------------------------------------------------

export interface FixtureProfile {
  id: string;
  type: ProfileType;
  /** auth.users id that controls this profile (a person's own login, a business owner's login). */
  userId: string;
  /** Every user id that controls the profile: owner and managers. */
  controllerIds: string[];
  handle: string;
}

export interface FixtureRelationship {
  id: string;
  spec: RelationshipSpec;
  requesterId: string;
  targetId: string;
  type: "connection" | "follow";
  /** The status the row ended with. */
  status: "pending" | "accepted" | "declined";
}

export interface FixtureCircle {
  id: string;
  spec: CircleSpec;
  ownerId: string;
}

export interface FixtureMembership {
  circleId: string;
  memberId: string;
}

export interface FixtureGroup {
  id: string;
  spec: GroupSpec;
  ownerId: string;
  memberIds: string[];
}

export interface FixtureContent {
  id: string;
  spec: ContentSpec;
  ownerId: string;
  contentType: ContentType;
  /** The audience the row was stored with (it differs from the request when downgraded). */
  audience: Audience;
  circleIds: string[];
  groupId: string | null;
  expired: boolean;
}

export interface FixtureVouch {
  id: string;
  spec: VouchSpec;
  authorId: string;
  subjectId: string;
  audience: VouchAudience;
  circleIds: string[];
  top8Position: number | null;
  hiddenBySubject: boolean;
}

export interface Fixture {
  /** Persons first, then businesses. */
  profiles: FixtureProfile[];
  persons: FixtureProfile[];
  businesses: FixtureProfile[];
  relationships: FixtureRelationship[];
  circles: FixtureCircle[];
  memberships: FixtureMembership[];
  groups: FixtureGroup[];
  content: FixtureContent[];
  vouches: FixtureVouch[];
  /** Counts of records the database rejected, by kind. */
  rejected: {
    managers: number;
    relationships: number;
    memberships: number;
    content: number;
    vouches: number;
  };
}

/** A viewer resolved to what `asUser` and `can_view` need. */
export interface ResolvedViewer {
  role: "authenticated" | "anon";
  /** auth.users id for `asUser`; undefined for anon. */
  sub?: string;
  /** The profile being acted as; null for anon. */
  profileId: string | null;
}

/** An expired story is a story created more than 24 hours ago. */
export function isExpiredStory(spec: ContentSpec): boolean {
  return spec.details.kind === "story" && spec.ageHours >= 24;
}

/** Resolves a viewer against an inserted fixture. */
export function resolveViewer(fixture: Fixture, viewer: ViewerSpec): ResolvedViewer {
  if (viewer.kind === "anon") return { role: "anon", profileId: null };
  const profile = pick(fixture.profiles, viewer.pick);
  if (profile === undefined) return { role: "anon", profileId: null };
  return { role: "authenticated", sub: profile.userId, profileId: profile.id };
}

// ---------------------------------------------------------------------------
// Insert helpers. All run as the test owner and never switch role.
// ---------------------------------------------------------------------------

/**
 * Runs `fn` in a savepoint. A rule rejection (PT* custom errors from the
 * guards, or a class 23 constraint error) is swallowed and returns undefined,
 * and the savepoint is rolled back. Any other error is rethrown.
 */
export async function tryInsert<T>(
  client: Client,
  fn: () => Promise<T>,
): Promise<T | undefined> {
  await client.query("savepoint fixture_try");
  try {
    const result = await fn();
    await client.query("release savepoint fixture_try");
    return result;
  } catch (error) {
    await client.query("rollback to savepoint fixture_try");
    await client.query("release savepoint fixture_try");
    const code = (error as { code?: unknown }).code;
    if (typeof code === "string" && (code.startsWith("PT") || code.startsWith("23"))) {
      return undefined;
    }
    throw error;
  }
}

async function insertReturningId(
  client: Client,
  sql: string,
  params: unknown[],
): Promise<string> {
  const res = await client.query<{ id: string }>(sql, params);
  const row = res.rows[0];
  if (row === undefined) throw new Error(`Insert returned no row: ${sql}`);
  return row.id;
}

/** Inserts a login into auth.users. */
export async function insertLogin(client: Client, email: string): Promise<string> {
  return insertReturningId(
    client,
    "insert into auth.users (id, email) values (gen_random_uuid(), $1) returning id",
    [email],
  );
}

/** Inserts a person profile owned by `userId`. */
export async function insertPerson(
  client: Client,
  spec: PersonSpec,
  userId: string,
  handle: string,
): Promise<string> {
  return insertReturningId(
    client,
    `insert into public.profiles
       (type, owner_user_id, handle, display_name, bio, dot_colour, what_i_do, city)
     values ('person', $1, $2, $3, $4, $5, $6, $7) returning id`,
    [userId, handle, spec.displayName, spec.bio, spec.dotColour, spec.whatIDo, spec.city],
  );
}

/**
 * Inserts a business profile (no owner user) and its owner manager row.
 * Without a session `auth.uid()` is null, so the profile trigger adds no
 * manager row itself.
 */
export async function insertBusiness(
  client: Client,
  spec: BusinessSpec,
  ownerUserId: string,
  handle: string,
): Promise<string> {
  const id = await insertReturningId(
    client,
    `insert into public.profiles
       (type, handle, display_name, bio, dot_colour, what_i_do, city)
     values ('business', $1, $2, $3, $4, $5, $6) returning id`,
    [handle, spec.displayName, spec.bio, spec.dotColour, spec.whatIDo, spec.city],
  );
  await client.query(
    "insert into public.profile_managers (profile_id, user_id, role) values ($1, $2, 'owner')",
    [id, ownerUserId],
  );
  if (spec.category !== null) {
    await client.query(
      "insert into public.business_details (profile_id, category) values ($1, $2)",
      [id, spec.category],
    );
  }
  return id;
}

/** Inserts a manager row. Returns false when the database rejects it. */
export async function insertManager(
  client: Client,
  businessId: string,
  userId: string,
  role: "owner" | "manager",
): Promise<boolean> {
  const done = await tryInsert(client, async () => {
    await client.query(
      `insert into public.profile_managers (profile_id, user_id, role) values ($1, $2, $3)
       on conflict (profile_id, user_id) do nothing`,
      [businessId, userId, role],
    );
    return true;
  });
  return done === true;
}

/**
 * Inserts a relationship. The guard fixes the first status (pending for a
 * connection, accepted for a follow); a connection is then moved to the
 * requested final status. Returns the stored row, or undefined when rejected.
 */
export async function insertRelationship(
  client: Client,
  requesterId: string,
  targetId: string,
  type: "connection" | "follow",
  finalStatus: "pending" | "accepted" | "declined",
): Promise<{ id: string; status: "pending" | "accepted" | "declined" } | undefined> {
  return tryInsert(client, async () => {
    const id = await insertReturningId(
      client,
      `insert into public.relationships (requester_profile_id, target_profile_id, type)
       values ($1, $2, $3) returning id`,
      [requesterId, targetId, type],
    );
    if (type === "connection" && finalStatus !== "pending") {
      await client.query("update public.relationships set status = $2 where id = $1", [
        id,
        finalStatus,
      ]);
      return { id, status: finalStatus };
    }
    return { id, status: type === "follow" ? ("accepted" as const) : ("pending" as const) };
  });
}

/** Inserts a circle. Returns its id. */
export async function insertCircle(
  client: Client,
  ownerId: string,
  spec: CircleSpec,
): Promise<string> {
  return insertReturningId(
    client,
    `insert into public.circles (owner_profile_id, private_name, show_member_label, member_label)
     values ($1, $2, $3, $4) returning id`,
    [ownerId, spec.privateName, spec.showMemberLabel, spec.memberLabel],
  );
}

/** Adds a circle member. Returns false when the database rejects it. */
export async function insertCircleMember(
  client: Client,
  circleId: string,
  memberId: string,
): Promise<boolean> {
  const done = await tryInsert(client, async () => {
    await client.query(
      "insert into public.circle_members (circle_id, member_profile_id) values ($1, $2)",
      [circleId, memberId],
    );
    return true;
  });
  return done === true;
}

/** Inserts a group and its members. Group members are not rule checked beyond their keys. */
export async function insertGroup(
  client: Client,
  ownerId: string,
  name: string,
  memberIds: string[],
): Promise<{ id: string; memberIds: string[] }> {
  const id = await insertReturningId(
    client,
    "insert into public.groups (owner_profile_id, name) values ($1, $2) returning id",
    [ownerId, name],
  );
  const stored: string[] = [];
  for (const memberId of memberIds) {
    const done = await tryInsert(client, async () => {
      await client.query(
        "insert into public.group_members (group_id, profile_id) values ($1, $2)",
        [id, memberId],
      );
      return true;
    });
    if (done === true) stored.push(memberId);
  }
  return { id, memberIds: stored };
}

function detailsJson(ownerId: string, details: ContentDetailsSpec, tag: string): object {
  switch (details.kind) {
    case "writing":
      return {
        title: details.title,
        body: details.body,
        ...(details.withCover ? { cover_image_path: `${ownerId}/writing/${tag}.jpg` } : {}),
      };
    case "gallery":
      return {
        image_path: `${ownerId}/gallery/${tag}.jpg`,
        ...(details.caption !== null ? { caption: details.caption } : {}),
      };
    case "status":
      return { text: details.text, ...(details.emoji !== null ? { emoji: details.emoji } : {}) };
    case "story": {
      // A story needs an image or text; fall back to text so it is always valid.
      const text = details.text ?? (details.withImage ? null : "story");
      return {
        ...(details.withImage ? { image_path: `${ownerId}/story/${tag}.jpg` } : {}),
        ...(text !== null ? { text } : {}),
      };
    }
  }
}

/**
 * Inserts one content item and its circle links. A story is back-dated by
 * `ageHours` (allowed for the test owner, so expired stories can be built).
 * Returns undefined when the database rejects the item.
 */
export async function insertContentItem(
  client: Client,
  input: {
    ownerId: string;
    spec: ContentSpec;
    tag: string;
    circleIds: string[];
    groupId: string | null;
    parentId: string | null;
  },
): Promise<FixtureContentRow | undefined> {
  const { ownerId, spec, tag, circleIds, groupId, parentId } = input;
  const contentType = spec.details.kind;
  // Writing is always public. Circles and group need something to point at;
  // without it the item is stored as connections instead.
  let audience: Audience = contentType === "writing" ? "public" : spec.audience;
  if (audience === "circles" && circleIds.length === 0) audience = "connections";
  if (audience === "group" && groupId === null) audience = "connections";
  const links = audience === "circles" ? circleIds : [];
  const group = audience === "group" ? groupId : null;
  return tryInsert(client, async () => {
    const id = await insertReturningId(
      client,
      `insert into public.content_items
         (owner_profile_id, content_type, audience, details, parent_id, group_id, created_at)
       values ($1, $2, $3, $4::jsonb, $5, $6, now() - make_interval(hours => $7::int))
       returning id`,
      [
        ownerId,
        contentType,
        audience,
        JSON.stringify(detailsJson(ownerId, spec.details, tag)),
        parentId,
        group,
        spec.ageHours,
      ],
    );
    for (const circleId of links) {
      await client.query(
        "insert into public.item_circles (content_item_id, circle_id) values ($1, $2)",
        [id, circleId],
      );
    }
    return { id, audience, circleIds: links, groupId: group };
  });
}

export interface FixtureContentRow {
  id: string;
  audience: Audience;
  circleIds: string[];
  groupId: string | null;
}

/** Inserts one vouch and its circle links. Returns undefined when the guard rejects it. */
export async function insertVouch(
  client: Client,
  input: {
    authorId: string;
    subjectId: string;
    body: string;
    audience: VouchAudience;
    circleIds: string[];
    top8Position: number | null;
    hiddenBySubject: boolean;
  },
): Promise<{ id: string; audience: VouchAudience; circleIds: string[] } | undefined> {
  const audience: VouchAudience =
    input.audience === "circles" && input.circleIds.length === 0 ? "connections" : input.audience;
  const links = audience === "circles" ? input.circleIds : [];
  return tryInsert(client, async () => {
    const id = await insertReturningId(
      client,
      `insert into public.vouches (author_profile_id, subject_profile_id, body, audience, top8_position)
       values ($1, $2, $3, $4, $5) returning id`,
      [input.authorId, input.subjectId, input.body, audience, input.top8Position],
    );
    for (const circleId of links) {
      await client.query("insert into public.item_circles (vouch_id, circle_id) values ($1, $2)", [
        id,
        circleId,
      ]);
    }
    if (input.hiddenBySubject) {
      // The insert guard resets the flag; the owner may set it afterwards.
      await client.query("update public.vouches set hidden_by_subject = true where id = $1", [id]);
    }
    return { id, audience, circleIds: links };
  });
}

/**
 * Inserts a whole generated world as the test owner and returns the ids and
 * what the database accepted. Order: logins and profiles, managers,
 * relationships, circles, memberships, groups, content, vouches.
 */
export async function insertScenario(client: Client, spec: ScenarioSpec): Promise<Fixture> {
  const rejected = { managers: 0, relationships: 0, memberships: 0, content: 0, vouches: 0 };
  const persons: FixtureProfile[] = [];
  const businesses: FixtureProfile[] = [];

  for (const [i, person] of spec.persons.entries()) {
    const userId = await insertLogin(client, `${i}-${person.login.emailTag}@pavio-test.invalid`);
    const handle = `person_${i}`;
    const id = await insertPerson(client, person, userId, handle);
    persons.push({ id, type: "person", userId, controllerIds: [userId], handle });
  }
  for (const [i, business] of spec.businesses.entries()) {
    const owner = pick(persons, business.ownerPick);
    if (owner === undefined) continue;
    const handle = `biz_${i}`;
    const id = await insertBusiness(client, business, owner.userId, handle);
    businesses.push({
      id,
      type: "business",
      userId: owner.userId,
      controllerIds: [owner.userId],
      handle,
    });
  }
  const profiles = [...persons, ...businesses];

  for (const manager of spec.managers) {
    const business = pick(businesses, manager.businessPick);
    const person = pick(persons, manager.personPick);
    if (business === undefined || person === undefined) continue;
    if (await insertManager(client, business.id, person.userId, manager.role)) {
      if (!business.controllerIds.includes(person.userId)) business.controllerIds.push(person.userId);
    } else {
      rejected.managers += 1;
    }
  }

  const relationships: FixtureRelationship[] = [];
  for (const rel of spec.relationships) {
    const ends = relationshipEnds(rel, persons, businesses);
    if (ends === undefined) {
      rejected.relationships += 1;
      continue;
    }
    const type = rel.shape === "person_follows_business" ||
      rel.shape === "person_follows_person" ||
      rel.shape === "business_follows_business"
      ? "follow"
      : "connection";
    const stored = await insertRelationship(client, ends.requester.id, ends.target.id, type, rel.status);
    if (stored === undefined) {
      rejected.relationships += 1;
      continue;
    }
    relationships.push({
      id: stored.id,
      spec: rel,
      requesterId: ends.requester.id,
      targetId: ends.target.id,
      type,
      status: stored.status,
    });
  }

  const circles: FixtureCircle[] = [];
  for (const circle of spec.circles) {
    const owner = pick(profiles, circle.ownerPick);
    if (owner === undefined) continue;
    const id = await insertCircle(client, owner.id, circle);
    circles.push({ id, spec: circle, ownerId: owner.id });
  }

  const memberships: FixtureMembership[] = [];
  for (const m of spec.memberships) {
    const circle = pick(circles, m.circlePick);
    if (circle === undefined) continue;
    const candidates =
      m.strategy === "audience"
        ? await audienceCandidates(client, circle.ownerId, profiles)
        : profiles;
    const member = pick(candidates, m.memberPick);
    if (member !== undefined && (await insertCircleMember(client, circle.id, member.id))) {
      memberships.push({ circleId: circle.id, memberId: member.id });
    } else {
      rejected.memberships += 1;
    }
  }

  const groups: FixtureGroup[] = [];
  for (const group of spec.groups) {
    const owner = pick(profiles, group.ownerPick);
    if (owner === undefined) continue;
    const memberIds = [...new Set(group.memberPicks.map((p) => pick(profiles, p)?.id))].filter(
      (id): id is string => id !== undefined,
    );
    const stored = await insertGroup(client, owner.id, group.name, memberIds);
    groups.push({ id: stored.id, spec: group, ownerId: owner.id, memberIds: stored.memberIds });
  }

  const content: FixtureContent[] = [];
  for (const [i, item] of spec.content.entries()) {
    const owner = pick(profiles, item.ownerPick);
    if (owner === undefined) continue;
    const ownCircles = circles.filter((c) => c.ownerId === owner.id);
    const circleIds = [
      ...new Set(item.circlePicks.map((p) => pick(ownCircles, p)?.id)),
    ].filter((id): id is string => id !== undefined);
    const group = pick(
      groups.filter((g) => g.ownerId === owner.id),
      item.groupPick,
    );
    const parent =
      item.parentPick === null
        ? undefined
        : pick(
            content.filter((c) => c.ownerId === owner.id),
            item.parentPick,
          );
    const stored = await insertContentItem(client, {
      ownerId: owner.id,
      spec: item,
      tag: `item${i}`,
      circleIds,
      groupId: group?.id ?? null,
      parentId: parent?.id ?? null,
    });
    if (stored === undefined) {
      rejected.content += 1;
      continue;
    }
    content.push({
      id: stored.id,
      spec: item,
      ownerId: owner.id,
      contentType: item.details.kind,
      audience: stored.audience,
      circleIds: stored.circleIds,
      groupId: stored.groupId,
      expired: isExpiredStory(item),
    });
    // A new status replaces the owner's previous one, and items nested under it cascade.
    if (item.details.kind === "status") {
      const kept = await existingContent(client, content);
      content.splice(0, content.length, ...kept);
    }
  }

  const vouches: FixtureVouch[] = [];
  const featuredCount = new Map<string, number>();
  for (const v of spec.vouches) {
    const author = pick(profiles, v.authorPick);
    if (author === undefined) continue;
    const ownCircles = circles.filter((c) => c.ownerId === author.id);
    const circleIds = [
      ...new Set(v.circlePicks.map((p) => pick(ownCircles, p)?.id)),
    ].filter((id): id is string => id !== undefined);
    const others = profiles.filter((p) => p.id !== author.id);
    // `eligible` walks the other profiles from the picked one until the guard accepts.
    const tries =
      v.strategy === "eligible"
        ? others.map((_, k) => pick(others, v.subjectPick + k))
        : [pick(others, v.subjectPick)];
    const used = featuredCount.get(author.id) ?? 0;
    const position = v.featured && used < 8 ? used + 1 : null;
    let stored: Awaited<ReturnType<typeof insertVouch>>;
    let subject: FixtureProfile | undefined;
    for (const candidate of tries) {
      if (candidate === undefined) continue;
      stored = await insertVouch(client, {
        authorId: author.id,
        subjectId: candidate.id,
        body: v.body,
        audience: v.audience,
        circleIds,
        top8Position: position,
        hiddenBySubject: v.hiddenBySubject,
      });
      if (stored !== undefined) {
        subject = candidate;
        break;
      }
    }
    if (stored === undefined || subject === undefined) {
      rejected.vouches += 1;
      continue;
    }
    if (position !== null) featuredCount.set(author.id, used + 1);
    vouches.push({
      id: stored.id,
      spec: v,
      authorId: author.id,
      subjectId: subject.id,
      audience: stored.audience,
      circleIds: stored.circleIds,
      top8Position: position,
      hiddenBySubject: v.hiddenBySubject,
    });
  }

  return {
    profiles,
    persons,
    businesses,
    relationships,
    circles,
    memberships,
    groups,
    content,
    vouches,
    rejected,
  };
}

/**
 * Returns the content rows the database still holds. Inserting a status
 * deletes the owner's previous status (Req 11.13) and, through the parent
 * foreign key, every item nested under it, so a fixture must drop them.
 */
export async function existingContent(
  client: Client,
  content: readonly FixtureContent[],
): Promise<FixtureContent[]> {
  if (content.length === 0) return [];
  const res = await client.query<{ id: string }>(
    "select id from public.content_items where id = any($1::uuid[])",
    [content.map((c) => c.id)],
  );
  const ids = new Set(res.rows.map((r) => r.id));
  return content.filter((c) => ids.has(c.id));
}

/** Maps a relationship shape to concrete requester and target profiles. */
function relationshipEnds(
  rel: RelationshipSpec,
  persons: FixtureProfile[],
  businesses: FixtureProfile[],
): { requester: FixtureProfile; target: FixtureProfile } | undefined {
  const poolOf = (kind: ProfileType) => (kind === "person" ? persons : businesses);
  const pools: Record<RelationshipShape, [ProfileType, ProfileType]> = {
    person_connection: ["person", "person"],
    business_connection: ["business", "business"],
    person_follows_business: ["person", "business"],
    business_to_person: ["business", "person"],
    person_follows_person: ["person", "person"],
    business_follows_business: ["business", "business"],
    connection_person_business: ["person", "business"],
    self: ["person", "person"],
    managed_page: ["person", "business"],
  };
  const [fromKind, toKind] = pools[rel.shape];
  const requester = pick(poolOf(fromKind), rel.requesterPick);
  if (requester === undefined) return undefined;
  if (rel.shape === "self") return { requester, target: requester };
  if (rel.shape === "managed_page") {
    // A person against a business they control: the owner of some business.
    const managed = businesses.find((b) => b.controllerIds.includes(requester.userId));
    return managed === undefined ? undefined : { requester, target: managed };
  }
  const target = pick(
    poolOf(toKind).filter((p) => p.id !== requester.id),
    rel.targetPick,
  );
  return target === undefined ? undefined : { requester, target };
}

/** Profiles the circle owner may place in a circle, asked of the database, not recomputed. */
async function audienceCandidates(
  client: Client,
  ownerId: string,
  profiles: FixtureProfile[],
): Promise<FixtureProfile[]> {
  const res = await client.query<{ id: string }>(
    "select p.id from public.profiles p where p.id <> $1 and private.in_audience($1, p.id)",
    [ownerId],
  );
  const ids = new Set(res.rows.map((r) => r.id));
  return profiles.filter((p) => ids.has(p.id));
}
