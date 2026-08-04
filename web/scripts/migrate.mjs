// Applies db/schema.sql. Idempotent (every statement is "if not exists").
// Usage: npm run db:migrate   (reads DATABASE_URL from .env.local or the env)
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { neon } from "@neondatabase/serverless";

const here = dirname(fileURLToPath(import.meta.url));
const url = process.env.DATABASE_URL;
if (!url) {
  console.error("DATABASE_URL is not set. Put it in web/.env.local.");
  process.exit(1);
}

const sql = neon(url);
const schema = readFileSync(join(here, "..", "db", "schema.sql"), "utf8");
const statements = schema
  .split(";")
  .map((s) => s.trim())
  .filter(Boolean);

for (const statement of statements) {
  await sql.query(statement);
  console.log(`ok: ${statement.split("\n")[0]}...`);
}

console.log(`Applied ${statements.length} statements.`);
