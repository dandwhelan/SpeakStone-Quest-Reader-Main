# SpeakStone Narration (QuestReaderAddon) — Gemini Agent Guidelines

A World of Warcraft addon that plays AI-generated voiceovers for quest text, books/items, and gossip, cloned from each NPC's in-game dialogue. The regeneration pipeline resides under `tools/`. `docs/walkthrough.md` is the operator runbook; `docs/publishing.md`, `docs/expansion_addons_plan.md`, `docs/sound_packs.md` cover the per-expansion pack split.

## This working directory is not the published repo

This checkout's `origin` still points at the **old** `dandwhelan/QuestReaderAddon` repo, which is **no longer the published base addon**.

- **`dandwhelan/SpeakStone-Quest-Reader-Main`** — the new published base-addon repo, no history carried over.
- **`dandwhelan/QuestReaderAddon_Pack_<Expansion>`** — one repo per expansion, each an independent installable pack, pushed by `tools/publish_packs.py`.
- This directory (`questwow`) is the **private build workspace** — `Sounds/`, `SoundLengths.lua`, `voicebank.json`, caches, tooling. It is not what a player downloads, and pushing from here does not touch either published repo family above.

## Architecture & Layout

- **Core Addon:** `QuestReaderAddon.lua`, `QuestReaderAddon_Settings.lua`, `QuestAudioLibraryUI.lua`, `QuestReaderAddon.toc`. The published base addon (`SpeakStone-Quest-Reader-Main`) now ships **no audio at all** — code plus the sound-pack merge mechanism only.
- **Audio Index:** `SoundLengths.lua` — the index the addon reads before playing any audio file. A clip missing from this file cannot be played even if the file exists on disk. **This file is real user data, not a build artifact.**
- **Audio Assets:** `Sounds/` — this workspace's library (5,000+ files, `.ogg` and legacy `.wav`/MP3 wrapper). Split into per-expansion packs by `tools/build_sound_packs.py` before publishing; not what ships in the base addon repo.
- **Packs:** `packs/`, `packs_build/` — `QuestReaderAddon_Pack_<Expansion>/`, each a self-contained addon (own `.toc`, `Register.lua`, `SoundLengths.lua` under its own global, `Sounds/`).
- **Tooling & TTS Pipeline:** `tools/` (see `tools/README.md`).
- **Harvester Addon:** `tools/QuestReaderHarvester/` — companion addon (SpeakStone Harvester) that captures live quest, gossip, and item/book text from the WoW client.

## Critical Safety Rules

1. **The index-shrink gate.** Never run `build_soundlengths.py -o` against `SoundLengths.lua` directly — use `tools/run_batch.py --install`, which backs up unconditionally and only replaces the live index if `new_count >= old_count`. A rebuild that comes out smaller than what's live is a real, previously-occurred failure mode, not a hypothetical — it must never be installed.
2. **Never delete audio files from `Sounds/` as part of cleanup.** Deletion of real shipped audio is only done after in-game playback confirmation.
3. **Cache files under `tools/.cache/`, `tools/generated_*`, `tools/regen/` are safe to delete/rebuild;** `Sounds/`, `SoundLengths.lua`, `voicebank.json`, `tools/pronunciations.json`, or a live WoW install are not.
4. **Live WoW Addon Sync:** When syncing to `.../Interface/AddOns/QuestReaderAddon` or `QuestReaderHarvester`, **always create a timestamped backup first** (e.g. `.backup_<timestamp>`).
5. **Never guess a donor voice's race/sex without a stated basis.** Where race/sex genuinely can't be resolved, spread those NPCs deterministically across many generic voice pools — never pile them onto one. Fixed today: 2,671 NPCs previously shared a single fallback voice; `voicebank.json` now spreads them across 16 `spread_neutral_NN_*` pools capped at ~200 members each.
6. **Angle brackets mean two different things by context.** Beside dialogue, `<...>` is a stage direction and is dropped. Wrapping an *entire* passage, it's item/object text — strip the brackets, keep the words. Getting this backwards reads a stage direction aloud or empties a passage (which crashes the TTS engine). Fixed today in `render_tokens` (`tools/synthesize.py`) — don't regress it.
7. **The pronunciation lexicon's longest-name-first sort is load-bearing.** `Amani` is a prefix of `Amani'Zar`; check the short key first and it matches inside the long one.
8. **Never fetch Wowhead's listing/search endpoints** — they 403 immediately even though per-quest pages work fine. Use cached per-quest pages plus zone inference (`tools/zone_expansions.py`, `tools/infer_expansions.py`).
9. **Wowhead rate-limit discipline:** serial, 1.5s+ between requests, stop and report on 403/429, never retry in a tight loop.
10. **Never run two GPU synthesis processes concurrently** — VRAM-bound (measured ~4.5GB/8GB on one process on the RTX 3070 Ti), a second process OOMs.
11. **A non-zero exit from `convert_library.py` for "nothing to do" is not a failure** — `run_batch.py` already guards this; don't add a naive exit-code check elsewhere.

## Audio Keying & Naming Conventions

- **Quests:** `<questID>_<passage>.<ext>` (`description`, `progress`, `completion`)
- **Gossip:** `npc<npcID>_gossip<n>.<ext>` (e.g., `npc12345_gossip1.ogg`)
- **Items & Books:** `item<itemID>_page<page>.<ext>` or `item_<clean_name>_page<page>.<ext>` or `<clean_name>_page<page>.<ext>`
- Formats supported: `.ogg` (preferred/new), `.wav`.

## User Interface & Minimap Controls

- **Minimap Button (LibDBIcon / DataBroker):**
  - **Left-Click:** Open Settings panel (`/ss`, `/speakstone`, `/qr`, `/questreader`).
  - **Right-Click:** Export harvested data window (`/ssharvest export`, `/qrharvest export`).
  - **Middle-Click:** Toggle chat debug messages on/off (`/ssdebug`, `/qrdebug`).
- **Slash Commands:**
  - `/ss`, `/speakstone`, `/qr`, `/questreader`: Open Settings UI.
  - `/ssauto`, `/speakstoneauto`, `/qrauto [on|off]`: Toggle quest audio autoplay.
  - `/ssdebug`, `/speakstonedebug`, `/qrdebug [on|off]`: Toggle debug messages in chat.
  - `/ssmissing`, `/speakstonemissing`, `/qrmissing`: Export the text captured for quests with no audio, ready to submit at speakstone.beanw.co.uk. Persisted across sessions in `QuestReaderAddonDB.missingCaptures.quests`.
  - `/qrlibrary`: Open Audio Library UI player.
  - `/qrtoggle`: Toggle minimap button visibility.
  - `/ssharvest`, `/speakstoneharvest`, `/qrharvest [export|wipe|clear]`: Manage harvester data.
- **External UI Hooking:**
  - DialogueUI (`DUIBookFrame`) is hooked via `ScrollToPage` and `ScrollTo` for multi-page book reading.

## The Pipeline, End to End

1. **Harvest**: `tools/missing_quests.py` + `tools/wowhead_quests.py` (bulk scrape), or `tools/QuestReaderHarvester` + `tools/harvest_export.py` (live capture — the only source for gossip text).
2. **Map to expansion**: `tools/harvest_by_expansion.py`, `tools/infer_expansions.py`, `tools/zone_expansions.py`. Fixed today: the original heuristic silently mislabeled ~2,274 Burning Crusade quests as Classic (it treated "no Added-in line" as Classic); replaced with zone-based inference from cached Wowhead pages.
3. **Prioritize**: `tools/prioritize_batch.py` — campaign-quest markers first, expansion recency as fallback.
4. **Synthesize**: `tools/synthesize.py`. **F5-TTS is the default engine** (`--engine f5`) — ignore the module's own top-of-file docstring, which still claims XTTS is default; that line is stale, same pattern `tools/README.md` had before it was corrected.
5. **Cap pauses**: `tools/cap_pauses.py`, `MAX_PAUSE_SECONDS = 0.45` — capped, not removed. Already run once against the full library.
6. **Install + reindex**: `tools/run_batch.py --install` (the index-shrink gate).
7. **Build + publish packs**: `tools/build_sound_packs.py` / `tools/publish_packs.py`. Packs auto-split at 500MB into sequential frozen volumes (`tools/pack_split_state.json`, sealed boundaries never move). Packs' `.toc` now declares `RequiredDeps: QuestReaderAddon` (changed from `OptionalDeps` today) — but `.toc` files already built under `packs/`/`packs_build/` predate that change and still say `OptionalDeps` until rebuilt.
8. **Tell Speakstone**: `--tell-speakstone` (marks voiced immediately) or `--audition` (queues for human review on Speakstone's `/admin/audition`) — mutually exclusive.

`tools/run_batch.py` flags: `--install`, `--tell-speakstone`, `--audition`, `--watch MINUTES` (implies `--install`).

`tools/wake_when_work.py` — Pi-side Wake-on-LAN watcher, polling Speakstone (`limit=1`, no `pull=1`) and waking the GPU machine when work is pending. **Deployed as a systemd service on the Pi** (`speakstone-wake.service`), not just written.

## TTS Engine & Pipeline Rules

- **TTS Engine:** F5-TTS is the default engine (`.venv-f5/`), not XTTS (`.venv/`).
- **Reference Audio Budget:** 60 seconds for XTTS (chosen by A/B listening test); F5 clips its reference internally and only uses 15 seconds (`F5_REFERENCE_SECONDS`) — these are not the same number, don't conflate them.
- **wago.tools:** Always send a custom `User-Agent` header to avoid HTTP 403.
- **SavedVariables Parsing:** Lua array-style tables parse as Python dicts keyed by numeric strings (`"1"`, `"2"`, etc.) — handle with `isinstance(x, dict)` and numeric key sorting.
- **Pronunciations:** `tools/pronunciations.json` strips apostrophes (`Zul'Aman` → `Zulaman`), not phonetic hyphenation — hyphenation was tried and rejected on listening (choppy delivery, ~5.8% longer clips). Read `_comment`/`_why_not_phonetic` in the file itself before changing this approach. Longest-key-first matching is load-bearing (`Amani` vs `Amani'Zar`).
- **Secret values:** WoW 12.x returns tagged "secret" values for unit GUIDs and similar. Guard with `issecretvalue()`/`SecretUtil` and wrap `strsplit` on a GUID in `pcall` — `QuestReaderAddon.lua` already does this, don't remove it.
