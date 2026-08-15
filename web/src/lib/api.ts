// Shapes and validation for the JSON API the iOS app talks to. Kept free of
// database and Next.js imports so it can be unit-tested directly.
// The .ts extension keeps `node --test` (which strips types without resolving
// extensions) able to import this module, exactly as the tests do.
import { validateEntry, type Pair } from "./deckFormat.ts";

/** One request cannot carry more than a large deck's worth of proposals. */
export const MAX_SUBMISSION_ENTRIES = 2000;

export type InvalidEntry = { word: string; reason: string };

export type ParsedSubmissions =
  | { error: string }
  | { entries: Pair[]; invalid: InvalidEntry[] };

/**
 * Reads `{ "entries": [{ "word": "...", "translation": "..." }] }`.
 * Individually invalid entries are reported back rather than failing the whole
 * request: the app submits whatever the user typed, and one unsupported word
 * must not block the rest.
 */
export function parseSubmissionsBody(body: unknown): ParsedSubmissions {
  if (typeof body !== "object" || body === null) {
    return { error: "Body must be a JSON object." };
  }
  const raw = (body as { entries?: unknown }).entries;
  if (!Array.isArray(raw)) {
    return { error: "Body must contain an 'entries' array." };
  }
  if (raw.length === 0) return { error: "'entries' is empty." };
  if (raw.length > MAX_SUBMISSION_ENTRIES) {
    return { error: `At most ${MAX_SUBMISSION_ENTRIES} entries per request.` };
  }

  const entries: Pair[] = [];
  const invalid: InvalidEntry[] = [];
  const seen = new Set<string>();

  for (const item of raw) {
    const word =
      typeof (item as { word?: unknown })?.word === "string"
        ? (item as { word: string }).word.trim()
        : "";
    const translation =
      typeof (item as { translation?: unknown })?.translation === "string"
        ? (item as { translation: string }).translation.trim()
        : "";

    const reason = validateEntry(word, translation);
    if (reason) {
      invalid.push({ word, reason });
      continue;
    }
    const key = `${word}${translation}`;
    if (seen.has(key)) continue;
    seen.add(key);
    entries.push({ word, translation });
  }

  return { entries, invalid };
}

export function jsonError(status: number, message: string): Response {
  return Response.json({ error: message }, { status });
}

export const UNAUTHORIZED = () =>
  jsonError(401, "Missing or invalid session token.");
