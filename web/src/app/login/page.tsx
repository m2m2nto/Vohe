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

      {error && <p className="error">Wrong password.</p>}

      <form action={login} className="stack card" style={{ marginTop: 20 }}>
        <label htmlFor="password">Password</label>
        <input id="password" name="password" type="password" autoFocus />
        <div>
          <button className="primary" type="submit">
            Sign in
          </button>
        </div>
      </form>
    </>
  );
}
