import { config } from "dotenv";
import { Client } from "pg";

config({ path: ".env.local", quiet: true });

/** The only roles a simulated API caller may take. */
export type ApiRole = "authenticated" | "anon";

/** Thrown when the simulated caller is not the caller that was asked for. */
export class CanaryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "CanaryError";
  }
}

function connectionString(): string {
  const url = process.env["SUPABASE_DB_URL"];
  if (url === undefined || url === "") {
    throw new Error(
      "SUPABASE_DB_URL is not set. Add it to .env.local (the Postgres connection string of the pavio project).",
    );
  }
  return url;
}

/**
 * Runs `fn` inside one transaction on its own connection and always rolls
 * back, so no test leaves data behind.
 */
export async function withRolledBackTx<T>(
  fn: (client: Client) => Promise<T>,
): Promise<T> {
  const client = new Client({ connectionString: connectionString() });
  // Without a listener, a connection error while the client is idle is an
  // unhandled event and crashes the worker. An error during the test is kept
  // and fails that test; one after the test has finished is ignored.
  let finished = false;
  let connectionError: Error | undefined;
  client.on("error", (err: Error) => {
    if (!finished) connectionError ??= err;
  });
  await client.connect();
  try {
    await client.query("begin");
    try {
      const result = await fn(client);
      if (connectionError !== undefined) throw connectionError;
      return result;
    } finally {
      await client.query("rollback").catch((err: unknown) => {
        if (connectionError === undefined) throw err;
      });
    }
  } finally {
    finished = true;
    await client.end().catch(() => undefined);
  }
}

function assertApiRole(role: string): asserts role is ApiRole {
  if (role !== "authenticated" && role !== "anon") {
    throw new CanaryError(
      `Only the roles authenticated and anon can be simulated, got ${JSON.stringify(role)}`,
    );
  }
}

/**
 * Sets the request claims and reads `private.is_api_caller()` as the test
 * owner. This must run BEFORE `set local role`, because the API roles have no
 * USAGE on schema `private` (D-8, DR-1). Returns the captured value.
 */
export async function readCanary(
  client: Client,
  role: ApiRole,
  sub?: string,
): Promise<boolean> {
  assertApiRole(role);
  const claims: { role: ApiRole; sub?: string } =
    role === "authenticated" && sub !== undefined ? { sub, role } : { role };
  await client.query("select set_config($1, $2, true)", [
    "request.jwt.claims",
    JSON.stringify(claims),
  ]);
  const res = await client.query<{ caller: boolean | null }>(
    "select private.is_api_caller() as caller",
  );
  return res.rows[0]?.caller === true;
}

/**
 * Run after `set local role`: asserts the session user, `auth.uid()` (null for
 * anon) and the value captured by `readCanary`; throws CanaryError otherwise.
 */
export async function checkCanary(
  client: Client,
  role: ApiRole,
  sub: string | undefined,
  captured: boolean,
): Promise<void> {
  assertApiRole(role);
  const res = await client.query<{ who: string; uid: string | null }>(
    "select current_user::text as who, auth.uid()::text as uid",
  );
  const row = res.rows[0];
  if (row === undefined || row.who !== role) {
    throw new CanaryError(
      `Expected current_user ${role}, got ${String(row?.who)}`,
    );
  }
  const expectedUid = role === "authenticated" ? (sub ?? null) : null;
  if (row.uid !== expectedUid) {
    throw new CanaryError(
      `Expected auth.uid() ${String(expectedUid)}, got ${String(row.uid)}`,
    );
  }
  if (captured !== true) {
    throw new CanaryError("private.is_api_caller() was not true for the simulated caller");
  }
}

/**
 * Simulates an API caller inside the current transaction: claims, canary
 * read as the owner, `set local role`, then the canary check. Call
 * `resetRole` before simulating another caller or running owner queries.
 */
export async function asUser(
  client: Client,
  role: ApiRole,
  sub?: string,
): Promise<void> {
  const captured = await readCanary(client, role, sub);
  // `role` is validated by readCanary, so interpolating it is safe.
  await client.query(`set local role ${role}`);
  await checkCanary(client, role, sub, captured);
}

/** Returns the session to the test owner. */
export async function resetRole(client: Client): Promise<void> {
  await client.query("reset role");
}
