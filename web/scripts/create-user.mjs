// Creates an account, or changes an existing one's password and role. This is
// the whole of user management: there is no signup page and no reset flow, so
// resetting a password means running this again.
// Usage: npm run user:create -- <username> <password> [--admin]
import { neon } from "@neondatabase/serverless";
import { hashPassword } from "../src/lib/auth.ts";

const args = process.argv.slice(2);
const admin = args.includes("--admin");
const [rawUsername, password, extra] = args.filter((a) => a !== "--admin");
// Trimmed to match both sign-in paths, which trim what is typed: an account
// stored with a stray space could never be signed into.
const username = rawUsername?.trim();

if (!username || !password || extra) {
  console.error("Usage: npm run user:create -- <username> <password> [--admin]");
  process.exit(1);
}

const url = process.env.DATABASE_URL;
if (!url) {
  console.error("DATABASE_URL is not set. Put it in web/.env.local.");
  process.exit(1);
}
const sql = neon(url);

// Signing needs AUTH_SECRET; hashing does not, so this script never sees it.
const [row] = await sql`
  insert into users (username, password_hash, role)
  values (
    ${username}, ${await hashPassword(password)},
    ${admin ? "admin" : "member"}
  )
  on conflict (username) do update
    set password_hash = excluded.password_hash, role = excluded.role
  returning id, username, role
`;

console.log(`ok: "${row.username}" is user ${row.id} (${row.role}).`);
