import { NextResponse, type NextRequest } from "next/server";
import { SESSION_COOKIE, readToken } from "@/lib/auth";

// Next 16's "proxy" convention (formerly middleware). Locks the whole app
// behind a signed-in account; only /login is reachable when signed out. /api is
// exempt because the iOS app authenticates per-request with its own token —
// every route under it checks that itself.
//
// Signature, audience and expiry only: no database query, so this stays cheap
// and edge-safe. Whether the account may use the editor at all is decided
// against the database by the pages and the actions.
export async function proxy(request: NextRequest) {
  let audience: string | undefined;
  try {
    const token = await readToken(
      request.cookies.get(SESSION_COOKIE)?.value,
      Date.now(),
    );
    audience = token?.audience;
  } catch {
    audience = undefined; // AUTH_SECRET missing — treat as locked
  }

  // An app token is deliberately not a browser session, however valid it is.
  if (audience === "web") return NextResponse.next();

  const url = request.nextUrl.clone();
  url.pathname = "/login";
  url.search = "";
  return NextResponse.redirect(url);
}

export const config = {
  matcher: ["/((?!api|login|_next/static|_next/image|favicon.ico).*)"],
};
