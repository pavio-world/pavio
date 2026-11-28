/**
 * Idempotent demo seed for the Pavio project (Spec 00, Req 27, design "Seed Design").
 *
 * Run with `npm run seed`. This file may use the Supabase secret key: it is one of the two places
 * allowed to (see privacy.md). It never touches profiles or users outside the cast.
 *
 * Idempotence rules (Req 27.9): upserts by fixed id, `where not exists` for relationships, circle
 * memberships and item circle links, accept only while `status = 'pending'`, a separate hide update,
 * and story times refreshed on every run. The fingerprint printed at the end ignores story times.
 */
import { pathToFileURL } from "node:url";
import { createClient } from "@supabase/supabase-js";
import { config } from "dotenv";
import pg from "pg";
import {
  BUSINESS_DETAILS,
  CIRCLES,
  CONTENT_ITEMS,
  DEMO_EMAILS,
  PROFILES,
  PROFILE_IDS,
  PROFILE_MANAGERS,
  RELATIONSHIPS,
  VOUCHES,
  type CastHandle,
  type CastItemCircle,
  type PersonHandle,
} from "./cast";

/** The only project the seed may write to (Req 27.11). */
const PAVIO_PROJECT_REF = "tmglpalznmyonaynojyy";

export interface Fingerprint {
  readonly counts: Readonly<Record<string, number>>;
  readonly castNotifications: number;
  readonly md5: string;
}

interface Env {
  readonly url: string;
  readonly secretKey: string;
  readonly dbUrl: string;
}

function readEnv(): Env {
  config({ path: ".env.local", quiet: true });
  const need = (name: string): string => {
    const value = process.env[name];
    if (value === undefined || value.trim() === "") {
      throw new Error(`${name} is not set. Add it to .env.local.`);
    }
    return value.trim();
  };
  const url = need("NEXT_PUBLIC_SUPABASE_URL");
  const secretKey = need("SUPABASE_SECRET_KEY");
  const dbUrl = need("SUPABASE_DB_URL");
  // Target guard: stop before any write if either URL points elsewhere.
  if (!url.includes(PAVIO_PROJECT_REF)) {
    throw new Error(`NEXT_PUBLIC_SUPABASE_URL does not target the Pavio project (${PAVIO_PROJECT_REF}). Nothing was written.`);
  }
  if (!dbUrl.includes(PAVIO_PROJECT_REF)) {
    throw new Error(`SUPABASE_DB_URL does not target the Pavio project (${PAVIO_PROJECT_REF}). Nothing was written.`);
  }
  return { url, secretKey, dbUrl };
}

/** Creates the demo logins that are missing and returns the user id of every cast person by handle. */
async function ensureAuthUsers(env: Env): Promise<Record<PersonHandle, string>> {
  const admin = createClient(env.url, env.secretKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const byEmail = new Map<string, string>();
  for (let page = 1; ; page += 1) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 1000 });
    if (error) throw new Error(`auth.admin.listUsers failed: ${error.message}`);
    for (const user of data.users) {
      if (user.email) byEmail.set(user.email.toLowerCase(), user.id);
    }
    if (data.users.length < 1000) break;
  }
  const ids = {} as Record<PersonHandle, string>;
  for (const handle of Object.keys(DEMO_EMAILS) as PersonHandle[]) {
    const email = DEMO_EMAILS[handle];
    let id = byEmail.get(email.toLowerCase());
    if (id === undefined) {
      const { data, error } = await admin.auth.admin.createUser({
        email,
        email_confirm: true,
        user_metadata: { demo: true },
      });
      if (error || !data.user) throw new Error(`auth.admin.createUser failed for ${email}: ${error?.message ?? "no user"}`);
      id = data.user.id;
      console.log(`created auth user ${email}`);
    }
    ids[handle] = id;
  }
  return ids;
}

const castIds = Object.values(PROFILE_IDS);

async function writeData(client: pg.Client, userIds: Record<PersonHandle, string>): Promise<void> {
  const pid = (handle: CastHandle): string => PROFILE_IDS[handle];

  // Profiles (businesses first or last does not matter; the automatic all followers circle is
  // created by the database on the first insert of a business).
  for (const p of PROFILES) {
    const owner = p.ownerEmail === null ? null : userIds[p.handle as PersonHandle];
    await client.query(
      `insert into public.profiles
         (id, type, owner_user_id, handle, display_name, bio, city, country, preferred_language, dot_colour, what_i_do)
       values ($1, $2::public.profile_type, $3, $4, $5, $6, $7, $8, $9, $10::public.dot_colour, $11::text[])
       on conflict (id) do update set
         type = excluded.type, owner_user_id = excluded.owner_user_id, handle = excluded.handle,
         display_name = excluded.display_name, bio = excluded.bio, city = excluded.city,
         country = excluded.country, preferred_language = excluded.preferred_language,
         dot_colour = excluded.dot_colour, what_i_do = excluded.what_i_do`,
      [p.id, p.type, owner, p.handle, p.displayName, p.bio, p.city, p.country, p.preferredLanguage, p.dotColour, [...p.whatIDo]],
    );
  }

  for (const b of BUSINESS_DETAILS) {
    await client.query(
      `insert into public.business_details (id, profile_id, category, phone, website, opening_hours, address)
       values ($1, $2, $3, $4, $5, $6::jsonb, $7)
       on conflict (id) do update set
         profile_id = excluded.profile_id, category = excluded.category, phone = excluded.phone,
         website = excluded.website, opening_hours = excluded.opening_hours, address = excluded.address`,
      [b.id, pid(b.profile), b.category, b.phone, b.website, JSON.stringify(b.openingHours), b.address],
    );
  }

  for (const m of PROFILE_MANAGERS) {
    await client.query(
      `insert into public.profile_managers (id, profile_id, user_id, role)
       values ($1, $2, $3, $4::public.manager_role)
       on conflict (id) do update set
         profile_id = excluded.profile_id, user_id = excluded.user_id, role = excluded.role`,
      [m.id, pid(m.profile), userIds[m.user], m.role],
    );
  }

  // Relationships: the guard raises PT409 before any on conflict clause, so use where not exists.
  for (const r of RELATIONSHIPS) {
    await client.query(
      `insert into public.relationships (requester_profile_id, target_profile_id, type)
       select $1::uuid, $2::uuid, $3::public.relationship_type
       where not exists (
         select 1 from public.relationships x
         where least(x.requester_profile_id, x.target_profile_id) = least($1::uuid, $2::uuid)
           and greatest(x.requester_profile_id, x.target_profile_id) = greatest($1::uuid, $2::uuid)
           and x.type = $3::public.relationship_type)`,
      [pid(r.requester), pid(r.target), r.type],
    );
    if (r.type === "connection" && r.finalStatus === "accepted") {
      // The status guard means a second run changes nothing and creates no notification.
      await client.query(
        `update public.relationships x set status = 'accepted'
         where least(x.requester_profile_id, x.target_profile_id) = least($1::uuid, $2::uuid)
           and greatest(x.requester_profile_id, x.target_profile_id) = greatest($1::uuid, $2::uuid)
           and x.type = 'connection' and x.status = 'pending'`,
        [pid(r.requester), pid(r.target)],
      );
    }
  }

  for (const c of CIRCLES) {
    await client.query(
      `insert into public.circles (id, owner_profile_id, private_name, show_member_label, member_label)
       values ($1, $2, $3, $4, $5)
       on conflict (id) do update set
         owner_profile_id = excluded.owner_profile_id, private_name = excluded.private_name,
         show_member_label = excluded.show_member_label, member_label = excluded.member_label`,
      [c.id, pid(c.owner), c.privateName, c.showMemberLabel, c.memberLabel],
    );
    for (const member of c.members) {
      await client.query(
        `insert into public.circle_members (circle_id, member_profile_id)
         select $1::uuid, $2::uuid
         where not exists (select 1 from public.circle_members m where m.circle_id = $1::uuid and m.member_profile_id = $2::uuid)`,
        [c.id, pid(member)],
      );
    }
  }

  /** Resolves where an item or vouch is shared: a fixed circle id, or the owner's automatic circle. */
  const circleIdFor = async (link: CastItemCircle): Promise<string> => {
    if ("circleId" in link) return link.circleId;
    const { rows } = await client.query<{ id: string }>(
      "select id from public.circles where owner_profile_id = $1 and is_all_followers",
      [pid(link.allFollowersOf)],
    );
    const row = rows[0];
    if (row === undefined) throw new Error(`no all followers circle for ${link.allFollowersOf}`);
    return row.id;
  };

  for (const item of CONTENT_ITEMS) {
    // created_at is only rewritten for stories, so the other rows keep their first run time.
    await client.query(
      `insert into public.content_items (id, owner_profile_id, content_type, audience, details, created_at)
       values ($1, $2, $3::public.content_type, $4::public.audience, $5::jsonb, now() - make_interval(hours => $6::int))
       on conflict (id) do update set
         owner_profile_id = excluded.owner_profile_id, content_type = excluded.content_type,
         audience = excluded.audience, details = excluded.details,
         created_at = case when excluded.content_type = 'story' then excluded.created_at
                           else public.content_items.created_at end`,
      [item.id, pid(item.owner), item.contentType, item.audience, JSON.stringify(item.details), item.createdHoursAgo ?? 0],
    );
    for (const link of item.circles) {
      await client.query(
        `insert into public.item_circles (content_item_id, circle_id)
         select $1::uuid, $2::uuid
         where not exists (select 1 from public.item_circles l where l.content_item_id = $1::uuid and l.circle_id = $2::uuid)`,
        [item.id, await circleIdFor(link)],
      );
    }
  }

  for (const v of VOUCHES) {
    await client.query(
      `insert into public.vouches (id, author_profile_id, subject_profile_id, body, audience, top8_position)
       values ($1, $2, $3, $4, $5::public.audience, $6)
       on conflict (id) do update set
         author_profile_id = excluded.author_profile_id, subject_profile_id = excluded.subject_profile_id,
         body = excluded.body, audience = excluded.audience, top8_position = excluded.top8_position`,
      [v.id, pid(v.author), pid(v.subject), v.body, v.audience, v.top8Position],
    );
    for (const link of v.circles) {
      await client.query(
        `insert into public.item_circles (vouch_id, circle_id)
         select $1::uuid, $2::uuid
         where not exists (select 1 from public.item_circles l where l.vouch_id = $1::uuid and l.circle_id = $2::uuid)`,
        [v.id, await circleIdFor(link)],
      );
    }
    // The insert trigger resets hidden_by_subject, so the hide is a separate update.
    await client.query(
      "update public.vouches set hidden_by_subject = $2 where id = $1 and hidden_by_subject is distinct from $2",
      [v.id, v.hiddenBySubject],
    );
  }
}

/** Row counts, cast notification count and an md5 over the seeded columns (story times excluded). */
async function fingerprint(client: pg.Client): Promise<Fingerprint> {
  const ids = [...castIds];
  const hash = async (sql: string): Promise<string> => {
    const { rows } = await client.query<{ h: string }>(
      `select md5(coalesce(string_agg(r::text, '|' order by r::text), '')) as h from (${sql}) r`,
      [ids],
    );
    return rows[0]?.h ?? "";
  };
  const queries: Record<string, string> = {
    profiles: `select id, type, owner_user_id, handle, display_name, bio, city, country, preferred_language,
                      dot_colour, what_i_do from public.profiles where id = any($1::uuid[])`,
    business_details: `select id, profile_id, category, phone, website, opening_hours, address
                       from public.business_details where profile_id = any($1::uuid[])`,
    profile_managers: `select id, profile_id, user_id, role from public.profile_managers where profile_id = any($1::uuid[])`,
    relationships: `select requester_profile_id, target_profile_id, type, status from public.relationships
                    where requester_profile_id = any($1::uuid[]) and target_profile_id = any($1::uuid[])`,
    // The automatic circle has a generated id, so it is identified by owner and name.
    circles: `select case when is_all_followers then null else id end as id, owner_profile_id, private_name,
                     show_member_label, member_label, is_all_followers
              from public.circles where owner_profile_id = any($1::uuid[])`,
    circle_members: `select c.owner_profile_id, c.private_name, m.member_profile_id
                     from public.circle_members m join public.circles c on c.id = m.circle_id
                     where c.owner_profile_id = any($1::uuid[])`,
    content_items: `select id, owner_profile_id, content_type, audience, details
                    from public.content_items where owner_profile_id = any($1::uuid[])`,
    item_circles: `select l.content_item_id, l.vouch_id, c.owner_profile_id, c.private_name
                   from public.item_circles l join public.circles c on c.id = l.circle_id
                   where c.owner_profile_id = any($1::uuid[])`,
    vouches: `select id, author_profile_id, subject_profile_id, body, audience, top8_position, hidden_by_subject
              from public.vouches where author_profile_id = any($1::uuid[])`,
  };
  const counts: Record<string, number> = {};
  const parts: string[] = [];
  for (const [name, sql] of Object.entries(queries)) {
    const { rows } = await client.query<{ n: string }>(`select count(*) as n from (${sql}) r`, [ids]);
    counts[name] = Number(rows[0]?.n ?? 0);
    parts.push(`${name}:${await hash(sql)}`);
  }
  const { rows } = await client.query<{ n: string }>(
    "select count(*) as n from public.notifications where recipient_profile_id = any($1::uuid[])",
    [ids],
  );
  const castNotifications = Number(rows[0]?.n ?? 0);
  const { rows: all } = await client.query<{ h: string }>("select md5($1::text) as h", [parts.join("|")]);
  return { counts, castNotifications, md5: all[0]?.h ?? "" };
}

/** Runs the whole seed once and returns the fingerprint of the seeded state. */
export async function runSeed(): Promise<Fingerprint> {
  const env = readEnv();
  const userIds = await ensureAuthUsers(env);
  const client = new pg.Client({ connectionString: env.dbUrl });
  await client.connect();
  try {
    await client.query("begin");
    try {
      await writeData(client, userIds);
      await client.query("commit");
    } catch (error) {
      await client.query("rollback");
      throw error;
    }
    const result = await fingerprint(client);
    console.log("seed fingerprint");
    for (const [name, n] of Object.entries(result.counts)) console.log(`  ${name}: ${n}`);
    console.log(`  cast notifications: ${result.castNotifications}`);
    console.log(`  md5: ${result.md5}`);
    return result;
  } finally {
    await client.end();
  }
}

const entry = process.argv[1];
if (entry !== undefined && import.meta.url === pathToFileURL(entry).href) {
  runSeed().catch((error: unknown) => {
    console.error(error instanceof Error ? error.message : error);
    process.exitCode = 1;
  });
}
