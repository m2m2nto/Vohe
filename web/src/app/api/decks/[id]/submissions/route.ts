import { UNAUTHORIZED, jsonError, parseSubmissionsBody } from "@/lib/api";
import { getDeck, insertSubmissions } from "@/lib/db";
import { apiUser } from "@/lib/session";

export const dynamic = "force-dynamic";

/**
 * Words the app wants added or re-translated. They land in the review queue —
 * nothing here changes the dictionary or its version until it is approved in
 * the editor.
 */
export async function POST(
  request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const user = await apiUser(request);
  if (!user) return UNAUTHORIZED();

  const { id } = await params;
  const deckId = Number(id);
  if (!Number.isInteger(deckId)) return jsonError(404, "No such dictionary.");
  if (!(await getDeck(deckId))) return jsonError(404, "No such dictionary.");

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return jsonError(400, "Body is not valid JSON.");
  }

  const parsed = parseSubmissionsBody(body);
  if ("error" in parsed) return jsonError(400, parsed.error);

  const accepted =
    parsed.entries.length > 0
      ? await insertSubmissions(deckId, parsed.entries, user.id)
      : 0;

  return Response.json({
    accepted,
    alreadyPending: parsed.entries.length - accepted,
    invalid: parsed.invalid,
  });
}
