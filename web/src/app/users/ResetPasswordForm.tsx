"use client";

import { useActionState } from "react";
import { SubmitButton } from "../SubmitButton";
import { resetAccountPassword, type PasswordResult } from "../actions";
import { PasswordNotice } from "./PasswordNotice";

/** Same reason as NewUserForm: the new password has to come back to the page. */
export function ResetPasswordForm({ userId }: { userId: number }) {
  const [result, action] = useActionState<PasswordResult, FormData>(
    resetAccountPassword,
    null,
  );

  return (
    <>
      <form action={action}>
        <input type="hidden" name="userId" value={userId} />
        <SubmitButton>Reset password</SubmitButton>
      </form>

      {result?.ok === false && <p className="error">{result.error}</p>}
      {result?.ok && (
        <PasswordNotice username={result.username} password={result.password} />
      )}
    </>
  );
}
