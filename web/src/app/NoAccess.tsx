import { SubmitButton } from "./SubmitButton";
import { logout } from "./actions";

/**
 * What a member sees instead of the editor. A page rather than a redirect,
 * because bouncing an account that is genuinely signed in back to /login only
 * invites it to sign in again. Sign out stays reachable — it is the one thing
 * this account can still do here.
 */
export function NoAccess({ username }: { username: string }) {
  return (
    <>
      <header className="bar">
        <h1>Vohe Dictionaries</h1>
        <form action={logout}>
          <SubmitButton>Sign out</SubmitButton>
        </form>
      </header>
      <p className="hint">
        Signed in as {username}. This account can&rsquo;t use the editor — it is
        for the app. Ask an admin if you need one here.
      </p>
    </>
  );
}
