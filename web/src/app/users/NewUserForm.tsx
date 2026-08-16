"use client";

import { useActionState } from "react";
import { SubmitButton } from "../SubmitButton";
import { createAccount, type PasswordResult } from "../actions";
import { PasswordNotice } from "./PasswordNotice";

/**
 * A client component only because the generated password has to come back to
 * the page. Every other control here posts and redirects like the rest of the
 * editor — this one cannot, since a redirect would put the password in the URL.
 */
export function NewUserForm() {
  const [result, action] = useActionState<PasswordResult, FormData>(
    createAccount,
    null,
  );

  return (
    <>
      <form action={action} className="card">
        <div className="inline">
          <input
            name="username"
            type="text"
            placeholder="danilo"
            aria-label="Username"
            autoComplete="off"
            style={{ maxWidth: 240 }}
          />
          <select name="role" aria-label="Role" defaultValue="member">
            <option value="member">Member — the app only</option>
            <option value="admin">Admin — the app and this editor</option>
          </select>
          <SubmitButton className="primary">Create</SubmitButton>
        </div>
      </form>

      {result?.ok === false && <p className="error">{result.error}</p>}
      {result?.ok && (
        <PasswordNotice username={result.username} password={result.password} />
      )}
    </>
  );
}
