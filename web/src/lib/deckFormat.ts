// Mirror of Vohe/Services/DeckParser.swift. Any change here must keep the
// exported .txt readable by the iOS app's parser:
//   line 1        -> "language1-language2"
//   lines 2+      -> "word-translation", split on the FIRST hyphen
//   blank lines and lines starting with "#" are ignored
//   both sides are trimmed and must be non-empty

export type Pair = { word: string; translation: string };

export type ParsedDeck = {
  language1: string;
  language2: string;
  pairs: Pair[];
};

function splitOnFirstHyphen(s: string): [string, string] | null {
  const i = s.indexOf("-");
  if (i === -1) return null;
  const left = s.slice(0, i).trim();
  const right = s.slice(i + 1).trim();
  if (!left || !right) return null;
  return [left, right];
}

/** Throws Error with a message meant for display. */
export function parseDeckText(text: string): ParsedDeck {
  const usable: { lineNumber: number; content: string }[] = [];
  text.split("\n").forEach((raw, idx) => {
    const trimmed = raw.trim();
    if (!trimmed || trimmed.startsWith("#")) return;
    usable.push({ lineNumber: idx + 1, content: trimmed });
  });

  const header = usable[0];
  if (!header) throw new Error("The file is empty.");

  const languages = splitOnFirstHyphen(header.content);
  if (!languages) {
    throw new Error(
      `First line must be 'language1-language2'. Got: "${header.content}"`,
    );
  }

  const pairs: Pair[] = [];
  for (const line of usable.slice(1)) {
    const pair = splitOnFirstHyphen(line.content);
    if (!pair) {
      throw new Error(
        `Line ${line.lineNumber} is not 'word-translation': "${line.content}"`,
      );
    }
    pairs.push({ word: pair[0], translation: pair[1] });
  }

  if (pairs.length === 0) {
    throw new Error("No vocabulary entries found after the header.");
  }

  return { language1: languages[0], language2: languages[1], pairs };
}

export function serializeDeck(deck: ParsedDeck): string {
  const lines = [`${deck.language1}-${deck.language2}`];
  for (const pair of deck.pairs) {
    lines.push(`${pair.word} - ${pair.translation}`);
  }
  return lines.join("\n") + "\n";
}

/** Returns an error message, or null when the value is safe to export. */
export function validateLanguage(label: string, value: string): string | null {
  const v = value.trim();
  if (!v) return `${label} is required.`;
  if (v.includes("-")) return `${label} cannot contain a hyphen.`;
  if (v.startsWith("#")) return `${label} cannot start with "#".`;
  if (/[\r\n]/.test(v)) return `${label} cannot span multiple lines.`;
  return null;
}

/**
 * The word is everything before the first hyphen, so a word containing "-"
 * would be silently truncated on re-import. The translation is the remainder
 * of the line and may contain hyphens.
 */
export function validateEntry(word: string, translation: string): string | null {
  const w = word.trim();
  const t = translation.trim();
  if (!w) return "Word is required.";
  if (!t) return "Translation is required.";
  if (w.includes("-")) {
    return `The word "${w}" contains a hyphen; the app's parser splits on the first hyphen, so it is not supported.`;
  }
  if (w.startsWith("#")) return `The word "${w}" cannot start with "#".`;
  if (/[\r\n]/.test(w) || /[\r\n]/.test(t)) {
    return "Entries cannot span multiple lines.";
  }
  return null;
}

export function normalizeName(name: string): string {
  return name.trim().replace(/\.txt$/i, "");
}

/** Filename used for the exported deck, matching the app's "name = filename" rule. */
export function exportFilename(name: string): string {
  const safe = normalizeName(name).replace(/[^\p{L}\p{N} _-]/gu, "_");
  return `${safe || "deck"}.txt`;
}
