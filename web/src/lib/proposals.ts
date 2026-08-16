// The .ts extension keeps `node --test` able to import this module, as api.ts
// does for the same reason.
import type { EntryRow } from "./db";
import { splitPair, validateEntry } from "./deckFormat.ts";

export type ProposalPlan = {
  /** Pairs to send to the review queue: absent words, and words the paste retranslates. */
  queued: { word: string; translation: string }[];
  /** How many pasted pairs the dictionary already carries word for word. */
  unchanged: number;
  /** Lines that reach neither, each with the reason to show the admin. */
  problems: { line: number; text: string; reason: string }[];
};

/** Compares a line to the deck's own header regardless of the spaces around the hyphen. */
function headerForm(s: string): string {
  return s.replace(/\s*-\s*/, "-").toLowerCase();
}

/**
 * Decides what a pasted list means for a dictionary without touching it.
 *
 * Words the dictionary already carries verbatim are dropped — a list generated
 * from the exported .txt repeats plenty of them, and re-proposing a word that
 * is already there is review work with nothing to decide. A word it carries
 * with a *different* translation is kept: the queue renders it as replacing the
 * current one, which is the only place that disagreement can be settled.
 *
 * Unlike `importEntries`, one bad line does not reject the paste. A list this
 * long is machine-written and arrives with the odd malformed row; losing the
 * other two hundred pairs to it would mean pasting again to find the next one.
 *
 * `entries` must arrive in export order (position, id): a word repeated in the
 * dictionary is compared against its first row, which is also the row an
 * approval writes to.
 */
export function planProposals(
  text: string,
  header: string,
  entries: EntryRow[],
): ProposalPlan {
  const known = new Map<string, string>();
  for (const entry of entries) {
    if (!known.has(entry.word)) known.set(entry.word, entry.translation);
  }

  const usable: { line: number; content: string }[] = [];
  text.split("\n").forEach((raw, index) => {
    const content = raw.trim();
    if (!content || content.startsWith("#")) return;
    usable.push({ line: index + 1, content });
  });

  // A whole .txt may be pasted, header and all.
  const first = usable[0];
  const body =
    first && headerForm(first.content) === headerForm(header)
      ? usable.slice(1)
      : usable;

  const queued: ProposalPlan["queued"] = [];
  const problems: ProposalPlan["problems"] = [];
  const seen = new Map<string, number>();
  let unchanged = 0;

  for (const { line, content } of body) {
    const pair = splitPair(content);
    if (!pair) {
      problems.push({
        line,
        text: content,
        reason: "Not a 'word - translation' line.",
      });
      continue;
    }

    const [word, translation] = pair;
    const invalid = validateEntry(word, translation);
    if (invalid) {
      problems.push({ line, text: content, reason: invalid });
      continue;
    }

    // Two rows for one word would be two queue entries proposing different
    // answers to the same question, so the first one asked is the one kept.
    const earlier = seen.get(word);
    if (earlier !== undefined) {
      problems.push({
        line,
        text: content,
        reason: `Repeats the word on line ${earlier}.`,
      });
      continue;
    }
    seen.set(word, line);

    if (known.get(word) === translation) {
      unchanged++;
      continue;
    }
    queued.push({ word, translation });
  }

  return { queued, unchanged, problems };
}
