import { getDeck, listEntries } from "@/lib/db";
import { currentUser } from "@/lib/session";
import { exportFilename, serializeDeck } from "@/lib/deckFormat";

export const dynamic = "force-dynamic";

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  // A route handler renders no page, so it asks for itself: the download is
  // part of the editor, not something a member's session opens.
  const user = await currentUser();
  if (user?.role !== "admin") return new Response("Forbidden", { status: 403 });

  const { id } = await params;
  const deckId = Number(id);
  if (!Number.isInteger(deckId)) {
    return new Response("Not found", { status: 404 });
  }

  const deck = await getDeck(deckId);
  if (!deck) return new Response("Not found", { status: 404 });

  const entries = await listEntries(deckId);
  const body = serializeDeck({
    language1: deck.language1,
    language2: deck.language2,
    pairs: entries.map((e) => ({ word: e.word, translation: e.translation })),
  });

  const filename = exportFilename(deck.name);
  return new Response(body, {
    headers: {
      "content-type": "text/plain; charset=utf-8",
      "content-disposition": `attachment; filename*=UTF-8''${encodeURIComponent(filename)}`,
      "cache-control": "no-store",
    },
  });
}
