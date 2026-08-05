import type { EntryRow } from "./db";

export type DuplicateGroup = {
  word: string;
  /** Every row carrying this word, in export order. */
  entries: EntryRow[];
  /** The rows disagree, so only a human can say which translation is right. */
  conflicting: boolean;
};

/**
 * Groups the rows that repeat a word.
 *
 * `DictionarySync` keys a card on the word, so a second row for the same word
 * becomes no card at all on the phone — that, and not a parsing difference, is
 * why a 757-row dictionary imports as 637 cards. Duplicates are allowed to
 * exist here; they are surfaced as review work instead.
 *
 * `entries` must arrive in export order (position, id): the first row of a
 * group is the one an exact-copy cleanup keeps.
 */
export function findDuplicates(entries: EntryRow[]): DuplicateGroup[] {
  const byWord = new Map<string, EntryRow[]>();
  for (const entry of entries) {
    const rows = byWord.get(entry.word);
    if (rows) rows.push(entry);
    else byWord.set(entry.word, [entry]);
  }

  const groups: DuplicateGroup[] = [];
  for (const [word, rows] of byWord) {
    if (rows.length < 2) continue;
    const distinct = new Set(rows.map((row) => row.translation));
    groups.push({ word, entries: rows, conflicting: distinct.size > 1 });
  }
  return groups;
}

/**
 * The rows to drop when every copy of a word says the same thing: all but the
 * first. Nothing is lost, so this needs no review.
 */
export function redundantEntryIds(groups: DuplicateGroup[]): number[] {
  return groups
    .filter((group) => !group.conflicting)
    .flatMap((group) => group.entries.slice(1).map((entry) => entry.id));
}
