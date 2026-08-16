// Who may not be demoted or deleted. Separate from actions.ts because a
// "use server" file may only export async functions, and this is the one part
// of the accounts page worth deciding without a request behind it: an editor
// with no admin left in it cannot be repaired from the editor.

export type Account = { id: number; role: string };

/**
 * The message refusing a role change, or null to allow it. Only ever refuses
 * taking admin away — handing it out is always safe.
 */
export function refuseRoleChange(
  me: Account,
  target: Account,
  role: string,
  adminCount: number,
): string | null {
  if (role === "admin" || target.role !== "admin") return null;
  if (target.id === me.id) {
    return "You can't take admin away from your own account.";
  }
  if (adminCount <= 1) {
    return "That is the last admin. Make someone else one first.";
  }
  return null;
}

/** The message refusing a deletion, or null to allow it. */
export function refuseDelete(
  me: Account,
  target: Account,
  adminCount: number,
): string | null {
  if (target.id === me.id) {
    return "You can't delete the account you are signed in with.";
  }
  if (target.role === "admin" && adminCount <= 1) {
    return "That is the last admin.";
  }
  return null;
}
