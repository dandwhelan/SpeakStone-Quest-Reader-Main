# SpeakStone Narration (QuestReaderAddon) — Codex Agent Notes

A WoW addon that plays AI-generated voiceovers for quest text, books/items, and gossip, cloned from each NPC's own in-game dialogue. `tools/` holds the regeneration pipeline. `tools/README.md` is the full pipeline reference — read it before touching the pipeline, not just this file. `docs/walkthrough.md` is the step-by-step operator runbook; `docs/publishing.md`, `docs/expansion_addons_plan.md`, `docs/sound_packs.md` cover the per-expansion pack split.

## Read this before touching any git remote

This checkout's `origin` still points at the **old** `dandwhelan/QuestReaderAddon` repo. That repo is **no longer the published base addon** — do not assume it reflects current work, and do not assume a push from here reaches players.

- **`dandwhelan/SpeakStone-Quest-Reader-Main`** is the new published base-addon repo, with no history carried over from the old one.
- **`dandwhelan/QuestReaderAddon_Pack_<Expansion>`** is a family of separate repos, one per expansion, each an independently-installable pack addon. `tools/publish_packs.py` pushes to these.
- This directory (`questwow`) is the **private build workspace only** — `Sounds/`, `SoundLengths.lua`, `voicebank.json`, the caches, and all tooling live here, but this is not what a player downloads and is not the same repo as either published family member above.

## Layout, in the order you'll touch it

1. `QuestReaderAddon.lua`, `QuestReaderAddon_Settings.lua`, `QuestAudioLibraryUI.lua`, `.toc` — the core addon. The published base addon repo now ships **no audio at all**; it's code plus the sound-pack merge mechanism only.
2. `SoundLengths.lua` — the index the addon reads before playing anything. A clip missing from this file is invisible to the addon even if the audio file exists on disk. **Real user data, not a build artifact.**
3. `Sounds/` — this workspace's audio library (5,000+ files, growing). Most `.wav`-named files are actually MP3 in a `.wav` wrapper (see below); newer files are `.ogg`. Not what ships in the base addon repo — it's split into packs before publishing.
4. `packs/`, `packs_build/` — `QuestReaderAddon_Pack_<Expansion>/` output, each a self-contained addon (own `.toc`, `Register.lua`, `SoundLengths.lua` under its own global, `Sounds/`).
5. `tools/` — the regeneration pipeline, Python 3, stdlib-only except where a script says otherwise.
6. `tools/QuestReaderHarvester/` — companion addon (SpeakStone Harvester) that captures quest, gossip, and item/book text live from a running client, for content that can't be scraped.

## Rules that are load-bearing, not style

- **The index-shrink gate.** Never run `build_soundlengths.py -o` against the real `SoundLengths.lua` directly — use `tools/run_batch.py --install`, which rebuilds into a temp file, backs up the live index unconditionally, and only replaces it if the new entry count is `>=` the old one. A rebuild that comes out smaller than what's live must never be installed: the audio files are still on disk and look fine, the only symptom is a specific clip going silent in-game. This has happened by accident once already; the gate exists specifically because of that.
- **`Sounds/` originals are never auto-deleted**, even after a successful re-encode to Ogg. Deletion is the user's call after in-game confirmation, never part of a "cleanup."
- **`tools/.cache/`, `tools/generated_*`, `tools/regen/` are disposable** — safe to delete, rebuildable from scratch. `Sounds/`, `SoundLengths.lua`, `voicebank.json`, `tools/pronunciations.json`, and a live WoW AddOns install are real data — never treat them the same way.
- **Live WoW install syncs need a timestamped backup first** (`.backup_<timestamp>`) — the live copy under `Interface/AddOns/QuestReaderAddon` or `QuestReaderHarvester` may be a version the user is actively testing.
- **Never guess a donor voice's race/sex without a stated basis.** `tools/npc_traits.py` resolves it from client tables where possible; where it genuinely can't be determined, the owner has explicitly approved spreading those NPCs deterministically across many generic voice pools rather than piling them onto one. Fixed today: 2,671 NPCs with no resolvable race/sex had all shared a single fallback voice — `voicebank.json` now spreads them across 16 `spread_neutral_NN_*` pools, capped at ~200 members each. Don't collapse that back to one bucket.
- **Angle brackets mean two different things depending on context.** Beside dialogue, `<...>` is a stage direction and gets dropped. Wrapping an *entire* passage, it's item/object text — strip the brackets, keep the words. Backwards, either a stage direction gets read aloud, or a passage empties to nothing and crashes the TTS engine outright. Fixed today in `render_tokens` (`tools/synthesize.py`) — don't regress it.
- **The pronunciation lexicon's longest-name-first sort is load-bearing, not cosmetic.** `tools/pronunciations.json` is loaded sorted longest-key-first by `load_lexicon()` in `tools/synthesize.py`, because some names are literal prefixes of longer ones (`Amani` inside `Amani'Zar`) — check the short one first and it matches inside the long one and mangles it.
- **Never fetch Wowhead's listing/search endpoints** (e.g. `wowhead.com/quests/expansion:N`) — confirmed to 403 immediately, even though ordinary per-quest pages fetch fine. Use cached per-quest pages plus zone inference (`tools/zone_expansions.py`, `tools/infer_expansions.py`) instead.
- **Wowhead rate-limit discipline**: serial requests, 1.5s+ apart, stop and report immediately on 403/429, never retry in a tight loop. Two concurrent fetches against the cache roughly halve the effective pacing and have caused a rate-limit incident before.
- **Never run two GPU synthesis processes concurrently.** VRAM is the binding constraint, not compute — measured on the actual RTX 3070 Ti: ~100% utilization most of the time, ~4.5GB/8GB VRAM for one process. A second process OOMs.
- **A non-zero exit from `convert_library.py` for "nothing to do" is not a failure** — it's a normal outcome for a batch with no new genuine-PCM `.wav` files. `run_batch.py` already guards this; don't check its exit code the naive way elsewhere.

## The pipeline, end to end

1. **Harvest text** — `tools/missing_quests.py` + `tools/wowhead_quests.py` (bulk Wowhead scrape) or `tools/QuestReaderHarvester` + `tools/harvest_export.py` (live capture — the *only* source for gossip text; there is no gossip-text table in the client and no Wowhead equivalent).
2. **Map to expansion** — `tools/harvest_by_expansion.py`, `tools/infer_expansions.py`, `tools/zone_expansions.py` build `tools/quest_expansions.json`. Real bug, found and fixed today: the original heuristic treated "no 'Added in World of Warcraft' line" as meaning Classic, which silently mislabeled roughly 2,274 Burning Crusade quests. Fixed via zone-based inference from cached Wowhead pages instead.
3. **Prioritize** — `tools/prioritize_batch.py` orders a batch by detected campaign-quest markers (Wowhead's own `quest-campaign-*` icons, genuine Blizzard signal but thin coverage), falling back to expansion recency.
4. **Synthesize** — `tools/synthesize.py`, F5-TTS by default (`--engine f5`). The module's own top-of-file docstring still says "The default engine is Coqui XTTS-v2" — that line is stale and wrong. Trust the `--engine` argparse default and `tools/README.md`, not that docstring; the same kind of staleness existed in `tools/README.md` itself until it was corrected earlier.
5. **Cap pauses** — `tools/cap_pauses.py`, `MAX_PAUSE_SECONDS = 0.45`, capped not removed (short pauses are real phrasing). Already run once against the full library.
6. **Install + reindex** — `tools/run_batch.py --install` (the index-shrink gate above).
7. **Build + publish packs** — `tools/build_sound_packs.py` splits `Sounds/`/`SoundLengths.lua` into per-expansion packs; `tools/publish_packs.py` pushes each to its own repo, skipping `Unsorted` deliberately. Packs now auto-split at 500MB into sequential, frozen volumes (`tools/pack_split_state.json` — a sealed volume boundary never moves again, so a player who installed Part 1 doesn't silently get different clips next release). Packs' `.toc` now declares `RequiredDeps: QuestReaderAddon`, changed today from `OptionalDeps` (a pack alone does nothing but call a global the base addon defines). The `.toc` files already sitting under `packs/`/`packs_build/` predate that change and still say `OptionalDeps` until rebuilt — don't take them as current.
8. **Tell Speakstone** — `tools/run_batch.py --tell-speakstone` (marks clips voiced immediately) or `--audition` (queues them on Speakstone's `/admin/audition` page for a human to listen first) — mutually exclusive, since they disagree about when a clip counts as checked.

`tools/run_batch.py` flags worth knowing: `--install`, `--tell-speakstone`, `--audition`, `--watch MINUTES` (implies `--install`, loops forever, one bad batch doesn't kill the loop).

`tools/wake_when_work.py` — a separate, Pi-side Wake-on-LAN watcher. Polls Speakstone for pending work (`limit=1`, deliberately without `pull=1` so polling never consumes the batch the GPU machine is about to request) and sends a Wake-on-LAN packet if the GPU machine looks asleep. **Now actually deployed as a systemd service on the Pi** (`speakstone-wake.service`), not just written and left local.

## Already debugged — don't redo this work

- wago.tools returns 403 to a default `urllib` User-Agent; `missing_quests.py`, `npc_traits.py`, `voice_sources.py` all send a real one. Do the same for any new client-table fetch.
- The original `TTS` (Coqui) PyPI package is archived and won't install on Python 3.12+; use the `coqui-tts` fork, same `TTS` module.
- torch ≥2.9 pulls in `torchcodec`, which needs FFmpeg *shared* libraries — the usual Windows ffmpeg builds are static-only, so it fails with a cryptic `WinError 127` after the model has already loaded (looks like a model problem, isn't). Fix: uninstall `torchcodec` (F5-TTS) or pin `torch==2.8.*` (XTTS).
- The two TTS engines don't share a venv well: `.venv/` = XTTS, `.venv-f5/` = F5-TTS (the default). Both gitignored.
- **F5-TTS is the default engine, not XTTS** — chosen after a direct, measured comparison (see `tools/README.md`). Don't trust `synthesize.py`'s own docstring, which still names XTTS as default; that's the stale line.
- Reference budget differs by engine: 60 seconds for XTTS (chosen by A/B listening test), but F5 clips its reference internally and only uses 15 seconds (`F5_REFERENCE_SECONDS`) — don't assume one figure applies to both.
- The apostrophe-stripping lexicon (`Zul'Aman` → `Zulaman`), not phonetic hyphenation. An earlier hyphenated respelling (`Zool-Ah-Mahn`) was tried and rejected on listening — every hyphen invites a micro-pause, making a three-hyphen name sound like separate stressed pieces, and it measurably lengthened clips (~5.8%). Read `_comment`/`_why_not_phonetic` in `tools/pronunciations.json` itself rather than paraphrasing from memory.
- The Lua SavedVariables parser turns array-style Lua tables (`{"a","b"}`) into a Python dict keyed `"1"`, `"2"`, ... , not a list. Check `isinstance(x, dict)` and sort numeric keys.
- Quest text and gossip text are both absent from client data files, verified directly against the DB2 definitions. Quest text has a Wowhead fallback; gossip text does not — harvester-only, no gossip DB2 table exists.
- 71% of the shipped `.wav` library is actually MP3 in a `.wav` wrapper. Only the genuine-PCM slice (29%) should ever be re-encoded — `convert_library.py` checks the `fmt` chunk's format tag, not just the RIFF/WAVE header.
- WoW 12.x returns tagged "secret" values where plain strings used to come back (unit GUIDs and similar). Guard with `issecretvalue()`/`SecretUtil` and wrap `strsplit` on a GUID in `pcall` — `QuestReaderAddon.lua` already does this; don't remove it as dead code, and don't share it with the harvester addon by reference (the two addons never load together).

## Audio naming schemes

- **Quests:** `<questID>_<passage>.<ext>` (`description`, `progress`, `completion`)
- **Gossip:** `npc<npcID>_gossip<n>.<ext>` (e.g., `npc12345_gossip1.ogg`)
- **Items & Books:** `item<itemID>_page<page>.<ext>` or `item_<clean_name>_page<page>.<ext>` or `<clean_name>_page<page>.<ext>`
- Supported extensions: `.ogg` (preferred/new), `.wav`.

## Addon controls

- **Minimap icon (LibDBIcon/DataBroker):** left-click opens Settings (`/ss`, `/speakstone`, `/qr`, `/questreader`); right-click opens the Harvester export window; middle-click toggles chat debug (`/ssdebug`).
- **Slash commands:** `/ssauto [on|off]` toggles autoplay; `/ssmissing` lists missing quest audio for the session; `/qrlibrary` opens the Audio Library UI; `/qrtoggle` toggles the minimap button; `/ssharvest [export|wipe|clear]` manages harvested text.
- **UI hooks:** standard Blizzard QuestFrame/QuestMapFrame/ItemTextFrame, plus DialogueUI (`DUIBookFrame`) via `ScrollToPage`/`ScrollTo`.

## Conventions

- Pronunciation fixes go in `tools/pronunciations.json`, added only after actually hearing a name mispronounced and checking the respelling against the game's own voice-over — never guessed in advance.
- Voice bank donor choices for NPCs with no audio of their own are a judgement call, not something to leave silently unfilled. Document the reasoning in the commit.
- Commit messages in this repo explain *why*, at some length — match that style rather than terse one-liners, especially for a fix whose symptom didn't reveal its cause.
