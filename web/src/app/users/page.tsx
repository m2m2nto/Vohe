import Link from "next/link";
import { redirect } from "next/navigation";
import { listUsers } from "@/lib/db";
import { currentUser } from "@/lib/session";
import { NoAccess } from "../NoAccess";
import { SubmitButton } from "../SubmitButton";
import { deleteAccount, logout, setAccountRole } from "../actions";
import { NewUserForm } from "./NewUserForm";
import { ResetPasswordForm } from "./ResetPasswordForm";

export const dynamic = "force-dynamic";

export default async function UsersPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const user = await currentUser();
  if (!user) redirect("/login");
  if (user.role !== "admin") return <NoAccess username={user.username} />;

  const { error } = await searchParams;
  const users = await listUsers();

  return (
    <>
      <header className="bar">
        <h1>Accounts</h1>
        <span className="inline">
          <Link href="/">All dictionaries</Link>
          <form action={logout}>
            <SubmitButton>Sign out</SubmitButton>
          </form>
        </span>
      </header>
      <p className="hint">
        One account signs in to both the phone app and this editor. A{" "}
        <strong>member</strong> can pull dictionaries and send words for review;
        only an <strong>admin</strong> can open the editor. Passwords are
        generated here and stored as hashes, so a forgotten one is reset, never
        looked up.
      </p>

      {error && <p className="error">{error}</p>}

      <h2>Accounts ({users.length})</h2>
      {users.map((account) => {
        const isSelf = account.id === user.id;
        return (
          <div className="card" key={account.id}>
            <div className="inline" style={{ justifyContent: "space-between" }}>
              <span>
                <strong>{account.username}</strong>{" "}
                {account.role === "admin" && <span className="badge">admin</span>}
                {isSelf && <span className="meta"> — you</span>}
                <span className="meta">
                  {" "}
                  · {account.proposal_count}{" "}
                  {account.proposal_count === 1 ? "proposal" : "proposals"}
                </span>
              </span>
              <span className="inline">
                <ResetPasswordForm userId={account.id} />
                {!isSelf && (
                  <>
                    <form action={setAccountRole}>
                      <input type="hidden" name="userId" value={account.id} />
                      <input
                        type="hidden"
                        name="role"
                        value={account.role === "admin" ? "member" : "admin"}
                      />
                      <SubmitButton>
                        {account.role === "admin"
                          ? "Make member"
                          : "Make admin"}
                      </SubmitButton>
                    </form>
                    <form action={deleteAccount}>
                      <input type="hidden" name="userId" value={account.id} />
                      <SubmitButton className="danger">Delete</SubmitButton>
                    </form>
                  </>
                )}
              </span>
            </div>
            {!isSelf && account.proposal_count > 0 && (
              <p className="hint" style={{ marginBottom: 0 }}>
                Deleting keeps those proposals in the review queue, without a
                name against them.
              </p>
            )}
          </div>
        );
      })}

      <h2>Add an account</h2>
      <NewUserForm />
    </>
  );
}
