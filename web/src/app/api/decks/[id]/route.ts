import { UNAUTHORIZED, jsonError } from "@/lib/api";
import { getDeck, listEntries } from "@/lib/db";
import { apiUser } from "@/lib/session";

export const dynamic = "force-dynamic";

/** One dictionary with every approved word. Pending proposals are not included. */
export async function GET(
  request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  if (!(await apiUser(request))) return UNAUTHORIZED();

  const { id } = await params;
  const deckId = Number(id);
  if (!Number.isInteger(deckId)) return jsonError(404, "No such dictionary.");

  const deck = await getDeck(deckId);
  if (!deck) return jsonError(404, "No such dictionary.");

  const entries = await listEntries(deckId);
  return Response.json({
    id: deck.id,
    name: deck.name,
    language1: deck.language1,
    language2: deck.language2,
    version: deck.version,
    entries: entries.map((e) => ({ word: e.word, translation: e.translation })),
  });
}
