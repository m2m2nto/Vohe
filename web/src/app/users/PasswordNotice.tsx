/**
 * The one moment a password is legible. It is rendered from an action's return
 * value rather than a redirect, so it never reaches the address bar — but it is
 * still on a screen, which is why the wording pushes the admin to hand it over
 * now rather than leave the tab open.
 */
export function PasswordNotice({
  username,
  password,
}: {
  username: string;
  password: string;
}) {
  return (
    <div className="card" style={{ marginTop: 10 }}>
      <p style={{ marginTop: 0 }}>
        Temporary password for <strong>{username}</strong>:
      </p>
      <p>
        <code style={{ fontSize: 20, letterSpacing: "0.04em" }}>{password}</code>
      </p>
      <p className="hint" style={{ marginBottom: 0 }}>
        Shown once. Only its hash is stored, so this cannot be read again — pass
        it on now, and reset it here if it is lost.
      </p>
    </div>
  );
}
