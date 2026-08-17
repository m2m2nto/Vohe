# Expanding a dictionary with two chat models

A dictionary grows fastest when a language model writes the candidates and a
second one checks them. Neither model is trusted: everything they produce lands
in **Waiting for review** and joins the dictionary only when you approve it.

No API keys and no per-token cost — both steps run in the ordinary ChatGPT and
Claude chat windows on the subscriptions you already pay for.

## The round trip

1. **Download** the dictionary from its page in the editor (`download .txt`).
2. **Generate** candidates in ChatGPT, pasting that file's contents into the
   chat (prompt 1).
3. **Verify** them in Claude, pasting the candidates (prompt 2).
4. **Paste** Claude's final block into **Paste a list for review**.
5. **Approve** in the review queue — tick what you want, one version bump.

Swap the two services freely; using two different ones is the point, since a
model asked to check its own output mostly agrees with itself.

## Why the checking step earns its keep

A model writing Croatian–Italian pairs unprompted will hand you: translations
that are right in one sense and wrong in the one a flashcard implies, verbs in
the wrong aspect, nouns that quietly shift gender, register mismatches
(a literary word offered for an everyday one), and words already in the list
under a different inflection. The second pass catches most of it, and what
survives both models is worth your review time in a way raw output is not.

## Prompt 1 — generate (ChatGPT)

Paste the exported `.txt` into the chat rather than attaching it. A few hundred
lines fit comfortably, and an attached file is often read through a
file-analysis tool that skims it — which is how a list comes back with half its
words already in the dictionary.

```text
Here is my {LANGUAGE1}–{LANGUAGE2} vocabulary list for flashcards.
Each line is "{LANGUAGE1} word - {LANGUAGE2} translation".

<paste the exported .txt here>

Propose {N} NEW pairs to add to it.

Rules:
- Nothing already in the attached list, in any inflected form.
- Pick by usefulness: frequency first, favouring words that make a good
  flashcard — concrete, unambiguous, worth recalling on their own.
- Dictionary form only: nouns nominative singular, verbs infinitive,
  adjectives masculine singular. No conjugated or declined forms.
- Single words. No phrases, no proper nouns, no abbreviations.
- Match the attached list's house style exactly: no articles, and where two
  translations are genuinely both common, write them as "a / b".
- Neither side may contain " - " (spaced hyphen); hyphens inside a word are
  fine.

Output ONLY the pairs, one per line, in the form "word - translation".
No numbering, no headers, no commentary, no code fence.
```

Ask for 100–150 at a time. Past that, quality falls off and the tail fills with
obscure words — run the prompt again for the next batch instead, pasting the
freshly exported file so the model sees what you have already taken.

Three things to reach for when the plain prompt disappoints:

- the frequency tail runs dry → add *"restricted to the kitchen, cooking and
  food"*, or whatever else you are short of;
- the words come back too hard or too easy → add *"at roughly A2–B1"*;
- the verbs come back in mixed aspect → add *"For verbs, give the imperfective
  unless the perfective is the more common everyday form, and never both
  members of an aspect pair."*

## Prompt 2 — verify (Claude)

Paste ChatGPT's output, then:

```text
Below are {LANGUAGE1}–{LANGUAGE2} vocabulary pairs proposed for a flashcard
deck, one per line as "{LANGUAGE1} word - {LANGUAGE2} translation".

Check each one. You are the second opinion — another model wrote these, so
judge them, do not defend them.

For each pair decide:
- KEEP  — correct and idiomatic as written.
- FIX   — the word is worth having but the translation is wrong, imprecise,
          the wrong register, or the wrong aspect/gender. Give the correction.
- DROP  — not a real word, not dictionary form, a duplicate of another line,
          ambiguous without context, or too obscure to be worth a card.

Then output, in this order:

1. A section "FINAL" containing only the KEEP and FIX lines, corrections
   applied, one per line as "word - translation", nothing else — no numbering,
   no commentary, no code fence.
2. A section "REPORT" listing every FIX and DROP with a one-line reason.

<paste the pairs here>
```

Paste the **FINAL** block into the editor. Keep the REPORT open while you work
the review queue — it is what tells you which entries deserve a second look.

## What the editor does with the paste

`Paste a list for review` does not trust the paste either. Before anything
reaches the queue it:

- drops any pair the dictionary already carries **word for word** — a list
  generated from the export repeats plenty, and re-proposing them is review
  work with nothing to decide;
- queues a word the dictionary carries with a **different** translation as a
  replacement, shown in the queue as `(replaces "…")`;
- keeps the **first** row for a word repeated inside one paste, reporting the
  rest;
- skips malformed lines and names them by line number, rather than rejecting
  the whole paste over one stray hyphen.

It then reports what it did: `42 words sent for review · 18 already in the
dictionary · 3 skipped (line 7 — …)`.

Nothing moves the dictionary's version until you approve. The phone sees no
change, and an unapproved word reaches no device.

## Where this sits

The `Paste a list` box above it is the other half of the pair and has not
changed: it appends straight into the dictionary and bumps the version, which
is right for a list you wrote or already trust. Use it for your own words, and
`Paste a list for review` for anything a model wrote.
