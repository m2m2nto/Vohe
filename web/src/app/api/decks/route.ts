import { UNAUTHORIZED } from "@/lib/api";
import { isValidApiToken } from "@/lib/auth";
import { listDecks } from "@/lib/db";

export const dynamic = "force-dynamic";

/** The catalog the iOS app browses. `version` drives its update badge. */
export async function GET(request: Request) {
  if (!isValidApiToken(request.headers.get("authorization"))) {
    return UNAUTHORIZED();
  }

  const decks = await listDecks();
  return Response.json({
    decks: decks.map((deck) => ({
      id: deck.id,
      name: deck.name,
      language1: deck.language1,
      language2: deck.language2,
      version: deck.version,
      wordCount: deck.entry_count,
    })),
  });
}
