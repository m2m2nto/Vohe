// Run with: npm test
import { test } from "node:test";
import assert from "node:assert/strict";

const { refuseDelete, refuseRoleChange } = await import(
  "../src/lib/accountGuards.ts"
);

const admin = { id: 1, role: "admin" };
const otherAdmin = { id: 2, role: "admin" };
const member = { id: 3, role: "member" };

test("handing out admin is never refused", () => {
  assert.equal(refuseRoleChange(admin, member, "admin", 1), null);
  assert.equal(refuseRoleChange(admin, otherAdmin, "admin", 2), null);
  assert.equal(refuseRoleChange(admin, admin, "admin", 1), null);
});

test("demoting a member is a no-op, not a refusal", () => {
  assert.equal(refuseRoleChange(admin, member, "member", 1), null);
});

test("an admin cannot demote themselves, however many admins there are", () => {
  for (const count of [1, 2, 5]) {
    assert.match(
      refuseRoleChange(admin, admin, "member", count) ?? "",
      /own account/,
      `admins: ${count}`,
    );
  }
});

test("the last admin cannot be demoted", () => {
  assert.match(
    refuseRoleChange(admin, otherAdmin, "member", 1) ?? "",
    /last admin/,
  );
  assert.equal(refuseRoleChange(admin, otherAdmin, "member", 2), null);
});

test("an admin cannot delete themselves", () => {
  for (const count of [1, 2, 5]) {
    assert.match(
      refuseDelete(admin, admin, count) ?? "",
      /signed in with/,
      `admins: ${count}`,
    );
  }
});

test("the last admin cannot be deleted", () => {
  assert.match(refuseDelete(admin, otherAdmin, 1) ?? "", /last admin/);
  assert.equal(refuseDelete(admin, otherAdmin, 2), null);
});

test("a member is always deletable", () => {
  assert.equal(refuseDelete(admin, member, 1), null);
  assert.equal(refuseDelete(admin, member, 2), null);
});

test("no sequence of allowed moves empties the editor of admins", () => {
  // The property the two guards exist for, checked exhaustively over small
  // account sets rather than argued: apply every move the guards permit, and
  // an admin must always remain.
  for (let size = 1; size <= 4; size++) {
    for (let mask = 0; mask < 1 << size; mask++) {
      const accounts = Array.from({ length: size }, (_, i) => ({
        id: i + 1,
        role: mask & (1 << i) ? "admin" : "member",
      }));
      const admins = accounts.filter((a) => a.role === "admin");
      if (admins.length === 0) continue; // nobody could be signed in

      for (const me of admins) {
        const count = admins.length;
        for (const target of accounts) {
          if (!refuseDelete(me, target, count)) {
            const left = accounts.filter(
              (a) => a.id !== target.id && a.role === "admin",
            );
            assert.ok(left.length >= 1, `delete emptied admins: ${mask}`);
          }
          if (!refuseRoleChange(me, target, "member", count)) {
            const left = accounts.filter(
              (a) => a.role === "admin" && a.id !== target.id,
            );
            assert.ok(left.length >= 1, `demote emptied admins: ${mask}`);
          }
        }
      }
    }
  }
});
