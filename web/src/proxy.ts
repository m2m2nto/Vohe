import { NextResponse, type NextRequest } from "next/server";
import { SESSION_COOKIE, isValidSessionCookie } from "@/lib/auth";

// Next 16's "proxy" convention (formerly middleware). Locks the whole app
// behind ADMIN_PASSWORD; only /login is reachable when signed out.
export async function proxy(request: NextRequest) {
  let authorized = false;
  try {
    authorized = await isValidSessionCookie(
      request.cookies.get(SESSION_COOKIE)?.value,
      Date.now(),
    );
  } catch {
    authorized = false; // AUTH_SECRET missing — treat as locked
  }

  if (authorized) return NextResponse.next();

  const url = request.nextUrl.clone();
  url.pathname = "/login";
  url.search = "";
  return NextResponse.redirect(url);
}

export const config = {
  matcher: ["/((?!login|_next/static|_next/image|favicon.ico).*)"],
};
