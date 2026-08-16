"use client";

/**
 * Ticks or clears every checkbox of one name in the surrounding form. A pasted
 * batch is reviewed as a batch — reading the list once and approving it whole
 * is the common case, and doing that a hundred checkboxes at a time is not.
 *
 * An enhancement, not a control: with JavaScript off it simply does nothing,
 * and the checkboxes it would have ticked are still there to tick.
 */
export function SelectAll({ name, label }: { name: string; label: string }) {
  return (
    <label className="inline">
      <input
        type="checkbox"
        onChange={(event) => {
          const { form, checked } = event.currentTarget;
          if (!form) return;
          const boxes = form.querySelectorAll<HTMLInputElement>(
            `input[type="checkbox"][name="${name}"]`,
          );
          for (const box of boxes) box.checked = checked;
        }}
      />
      <span className="meta">{label}</span>
    </label>
  );
}
