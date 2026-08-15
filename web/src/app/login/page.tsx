import { SubmitButton } from "../SubmitButton";
import { login } from "../actions";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const { error } = await searchParams;

  return (
    <>
      <header className="bar">
        <h1>Vohe Dictionaries</h1>
      </header>

      {error && <p className="error">Wrong username or password.</p>}

      <form action={login} className="stack card" style={{ marginTop: 20 }}>
        <label htmlFor="username">Username</label>
        <input id="username" name="username" type="text" autoFocus />
        <label htmlFor="password">Password</label>
        <input id="password" name="password" type="password" />
        <div>
          <SubmitButton className="primary">Sign in</SubmitButton>
        </div>
      </form>
    </>
  );
}
