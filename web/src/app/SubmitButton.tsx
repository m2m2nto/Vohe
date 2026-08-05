"use client";

import { useFormStatus } from "react-dom";

/**
 * A submit button that locks itself and spins while its form's server action
 * runs, so a slow save can neither be sent twice nor look like nothing
 * happened. It reads the state of the form it sits in, so it has to sit in one
 * — two forms in the same row lock independently. With JavaScript off it is an
 * ordinary submit button.
 */
export function SubmitButton({
  children,
  className,
}: {
  children: React.ReactNode;
  className?: string;
}) {
  const { pending } = useFormStatus();

  return (
    <button
      type="submit"
      className={className}
      disabled={pending}
      aria-busy={pending}
      data-pending={pending || undefined}
    >
      <span className="submit-label">{children}</span>
    </button>
  );
}
