# SpeakStone Narration (QuestReaderAddon)

A WoW addon that plays AI-generated voiceovers for quest text, books/items, and gossip, cloned from each NPC's own in-game dialogue. `tools/` holds the regeneration pipeline that produces that audio. Read `tools/README.md` before touching the pipeline — it's the authoritative, detailed reference; this file is orientation and safety rules, not a duplicate of it. `docs/walkthrough.md` is the step-by-step operator runbook; `docs/publishing.md`, `docs/expansion_addons_plan.md`, and `docs/sound_packs.md` cover the per-expansion pack split in depth.

## This working directory is not the published repo — read this before touching git remotes

This local checkout (`questwow`) still tracks the **old** `dandwhelan/QuestReaderAddon` repo as its `origin`. That repo is **no longer the published base addon**. As of today:

- **`dandwhelan/SpeakStone-Quest-Reader-Main`** is the new published base-addon repo — no history carried over from the old one.
- **`dandwhelan/QuestReaderAddon_Pack_<Expansion>`** — a family of separate repos, one per expansion, each an independent installable pack addon. `tools/publish_packs.py` pushes to these directly.
- This local directory remains the **private build workspace**: `Sounds/`, `SoundLengths.lua`, `voicebank.json`, the harvest caches, and all the tooling live here, but it is not what a player downloads and it is not the same repo as either published family member above. Do not assume a `git push` from here goes anywhere near what CurseForge or a player's AddOns folder actually sees, and do not assume the old `QuestReaderAddon` repo still reflects current work.

## Layout

- `QuestReaderAddon.lua`, `QuestReaderAddon_Settings.lua`, `QuestAudioLibraryUI.lua`, `.toc` — the core addon. The base addon repo (`SpeakStone-Quest-Reader-Main`) ships **no audio at all** now — all audio moved to `refresh_main_repo`/the per-expansion packs; the base addon is code plus the sound-pack merge mechanism only.
- `SoundLengths.lua` — the index the addon reads before playing anything. A clip missing from this file is invisible to the addon even if the audio file exists on disk. **This file is real user data, not a build artifact.**
- `Sounds/` — the *local build workspace's* audio library (5,000+ files, growing). Most filenames end `.wav` but a majority of those are actually MP3 with a `.wav` extension (see below) — never assume the extension tells you the format. Newer files are `.ogg`. This is not what ships in the base addon repo (see above) — it's split into packs by `tools/build_sound_packs.py` before publishing.
- `packs/`, `packs_build/` — per-expansion pack output directories (`QuestReaderAddon_Pack_<Expansion>/`), each a self-contained addon with its own `.toc`, `Register.lua`, `SoundLengths.lua` (under its own global), and `Sounds/`. `tools/publish_packs.py` pushes each to its own repo.
- `tools/` — the regeneration pipeline (Python 3, stdlib-only except where a script says otherwise). Has its own README with full usage.
- `tools/QuestReaderHarvester/` — a small companion addon (SpeakStone Harvester) that captures quest, gossip, and item/book text live from a running client for content that cannot be scraped.

## Non-negotiable safety rules

- **The index-shrink gate.** Never run `build_soundlengths.py -o` pointed at the real `SoundLengths.lua` directly — use `tools/run_batch.py --install`, which rebuilds into a temp file, backs up the live index unconditionally, and **only replaces it if the new entry count is ≥ the old one**. A rebuild that comes out smaller than what it's replacing must never be installed — the files are still on disk and look fine, the only symptom is a specific clip going silent in-game. This has happened by accident once; the gate exists specifically because of that. If you ever must run `build_soundlengths.py` directly, take your own backup first and verify the count by hand.
- **`Sounds/` originals are not deleted automatically**, even after a successful re-encode to Ogg. Deleting real shipped audio is the user's call after they've confirmed playback in-game — never do it as part of a "cleanup."
- Anything under `tools/.cache/`, `tools/generated_*`, and `tools/regen/` is a rebuildable cache, safe to delete. `Sounds/`, `SoundLengths.lua`, `voicebank.json`, `tools/pronunciations.json`, and a user's live AddOns install are real data, never treated the same way.
- **If syncing changes into a live WoW install (`.../Interface/AddOns/QuestReaderAddon` or `QuestReaderHarvester`), back up whatever's already there first** (`.backup_<timestamp>`) — it may be a version the user is actively testing.
- **Never guess a donor voice's race/sex without a stated basis.** `tools/npc_traits.py` resolves it from client tables where it can; where it genuinely can't be determined, the owner has explicitly approved spreading those NPCs deterministically across *many* generic voice pools rather than piling them onto one. A real bug, found and fixed today: 2,671 NPCs with no resolvable race/sex had all been assigned the same single fallback voice. `voicebank.json` now spreads them across 16 `spread_neutral_NN_*` pools, each holding at most ~200 members. Don't collapse that back down to one bucket for convenience.
- **Angle brackets mean two different things depending on context — do not regress this.** Beside other dialogue, `<...>` is a stage direction and gets dropped (e.g. `<Brek laughs.>`). When the brackets wrap the *entire* passage, it's item/object description text and the brackets must be stripped but the words kept (e.g. `<The idol appears to be a figure of Ohn'ahra...>` must survive as spoken text). Getting this backwards either reads stage directions aloud, or empties a passage to nothing, which crashes the TTS engine outright. This was a real bug fixed today (`render_tokens` in `tools/synthesize.py`) — never let a future change regress it.
- **The pronunciation lexicon's longest-name-first matching is load-bearing, not cosmetic.** `tools/pronunciations.json` is loaded by `load_lexicon()` in `tools/synthesize.py` sorted longest-key-first, because some names are literal prefixes of longer ones (`Amani` inside `Amani'Zar`) — check the short one first and it matches inside the long one and mangles it.
- **Never fetch Wowhead's listing/search endpoints** (e.g. `wowhead.com/quests/expansion:N`) — confirmed to 403 immediately even when ordinary per-quest pages fetch fine. Use cached per-quest pages plus zone-based inference (`tools/zone_expansions.py`, `tools/infer_expansions.py`) instead.
- **Rate-limit discipline for any Wowhead fetching**: serial requests, 1.5s+ between them, stop immediately and report on 403/429, never retry in a tight loop. Running two fetches against the cache concurrently roughly halves the effective pacing and has caused a rate-limit incident before.
- **Never run two GPU synthesis processes concurrently.** VRAM is the binding constraint, not compute — measured on the actual RTX 3070 Ti: ~100% GPU utilization most of the time, ~4.5GB/8GB VRAM used by one process. A second process would OOM.
- **A non-zero exit from `convert_library.py` for "nothing to do" is not a failure.** It's a normal outcome when a batch has no new genuine-PCM `.wav` files to shrink. `run_batch.py` already guards against treating this as fatal; don't reintroduce a naive exit-code check elsewhere.

## Audio Naming Schemes

- **Quests:** `<questID>_<passage>.<ext>` (`description`, `progress`, `completion`)
- **Gossip:** `npc<npcID>_gossip<n>.<ext>` (e.g., `npc12345_gossip1.ogg`)
- **Items & Books:** `item<itemID>_page<page>.<ext>` or `item_<clean_name>_page<page>.<ext>` or `<clean_name>_page<page>.<ext>`
- Supported audio extensions: `.ogg` (preferred/new), `.wav`.

## Addon Controls & Features

- **Minimap Icon (LibDBIcon / DataBroker):**
  - **Left-Click:** Open Settings panel (`/ss`, `/speakstone`, `/qr`, `/questreader`).
  - **Right-Click:** Open Harvester export window (`/ssharvest export`, `/qrharvest export`).
  - **Middle-Click:** Toggle chat debug messages on/off (`/ssdebug`, `/qrdebug`).
- **Slash Commands:**
  - `/ss`, `/speakstone`, `/qr`, `/questreader` — Open Settings interface.
  - `/ssauto`, `/speakstoneauto`, `/qrauto [on|off]` — Toggle autoplay for quests/books.
  - `/ssdebug`, `/speakstonedebug`, `/qrdebug [on|off]` — Toggle chat debug messages.
  - `/ssmissing`, `/speakstonemissing`, `/qrmissing` — Open copyable window exporting the text captured for quests with no audio, ready to submit at speakstone.beanw.co.uk. Persisted across sessions in `QuestReaderAddonDB.missingCaptures.quests`, not session-only like `addon.reportedMissing`.
  - `/qrlibrary` — Open Audio Library UI player.
  - `/qrtoggle` — Toggle minimap button visibility.
  - `/ssharvest`, `/speakstoneharvest`, `/qrharvest [export|wipe|clear]` — Manage harvested quest/gossip/book text.
- **UI Integrations:**
  - Standard Blizzard QuestFrame, QuestMapFrame, and ItemTextFrame.
  - DialogueUI (`DUIBookFrame`) integration hooked via `ScrollToPage` / `ScrollTo`.

## The pipeline, and the per-expansion pack split

`tools/README.md` and `docs/walkthrough.md` have the full detail; this is the shape of it:

1. **Harvest text**: `tools/missing_quests.py` + `tools/wowhead_quests.py` (bulk, Wowhead scrape) or `tools/QuestReaderHarvester` + `tools/harvest_export.py` (live capture — the only source for gossip text, which has no Wowhead equivalent at all).
2. **Map to expansion**: `tools/harvest_by_expansion.py`, `tools/infer_expansions.py`, `tools/zone_expansions.py` build `tools/quest_expansions.json`. A real bug, found and fixed today: the original heuristic treated "no 'Added in World of Warcraft' line on the page" as meaning Classic, which silently mislabeled roughly 2,274 Burning Crusade quests as Classic. Fixed by inferring from the quest's zone (via cached Wowhead pages) instead of trusting the absence of that line.
3. **Prioritize**: `tools/prioritize_batch.py` orders a batch by detected campaign-quest markers (Wowhead's own `quest-campaign-*` icons — genuine Blizzard signal, but thin coverage, ~10% of quests cached and only a fraction of those tagged), falling back to expansion recency when no campaign signal exists.
4. **Synthesize**: `tools/synthesize.py`, F5-TTS by default (`--engine f5`). Note: the module's own docstring at the top of the file still says "The default engine is Coqui XTTS-v2" — that line is stale and wrong; trust the `--engine` argparse default (`f5`) and `tools/README.md`, not that docstring. This is the same kind of staleness `tools/README.md` itself had until it was corrected — check before trusting any single comment.
5. **Cap pauses**: `tools/cap_pauses.py` shrinks internal pauses F5 leaves inside a clip down to `MAX_PAUSE_SECONDS` (0.45s) — capped, not removed, since short pauses are real phrasing. Already run once against the full library.
6. **Install + reindex**: `tools/run_batch.py --install` (see the index-shrink gate above).
7. **Build + publish packs**: `tools/build_sound_packs.py` splits `Sounds/`/`SoundLengths.lua` into per-expansion packs; `tools/publish_packs.py` pushes each to its own repo (skipping `Unsorted` deliberately). Packs now auto-split at 500MB into sequential, frozen volumes (`tools/pack_split_state.json` — once a volume boundary is sealed it never moves, so a player who installed Part 1 doesn't silently get different clips next release). Packs' `.toc` now declares `RequiredDeps: QuestReaderAddon` (changed from `OptionalDeps` today, since a pack alone does nothing but call a global the base addon defines) — the `.toc` files already sitting in `packs/`/`packs_build/` are stale build output from before that change and will say `OptionalDeps` until rebuilt.
8. **Tell Speakstone**: `tools/run_batch.py --tell-speakstone` (marks clips voiced immediately) or `--audition` (queues them for a human to listen to on Speakstone's `/admin/audition` page first — mutually exclusive with `--tell-speakstone`, since they disagree about when a clip counts as checked).

`tools/run_batch.py` flags worth knowing: `--install`, `--tell-speakstone`, `--audition`, `--watch MINUTES` (implies `--install`, loops forever, one bad batch doesn't kill the loop).

`tools/wake_when_work.py` is a separate, Pi-side Wake-on-LAN watcher — polls Speakstone for pending work (`limit=1`, deliberately without `pull=1`, so polling never consumes the batch the GPU machine is about to request) and wakes the GPU machine over LAN if it looks asleep. It is now **actually deployed** as a systemd service on the Pi (`speakstone-wake.service`), not just written and left local.

## What's already been solved (don't rediscover these)

- **wago.tools returns HTTP 403 to urllib's default User-Agent.** Every script that hits it (`missing_quests.py`, `npc_traits.py`, `voice_sources.py`) sends a real one. If you add a new client-table fetch, do the same.
- **The original `TTS` (Coqui) PyPI package is archived and won't install on Python 3.12+.** Use the `coqui-tts` fork, which provides the same `TTS` module.
- **torch ≥2.9 requires `torchcodec`, which needs FFmpeg *shared* libraries.** The usual Windows ffmpeg builds are static-only, so torchcodec fails to load with a cryptic `WinError 127` — after the model has already loaded, which makes it look like a model problem, not a codec one. Fix: uninstall `torchcodec` (F5-TTS) or pin `torch==2.8.*` (XTTS). Both engines fall back to torchaudio cleanly once torchcodec is out of the picture.
- **The two TTS engines don't share a venv well.** `.venv/` = XTTS, `.venv-f5/` = F5-TTS (the default). Both are gitignored.
- **F5-TTS is the default engine, not XTTS**, chosen after a direct measured comparison (see `tools/README.md` and `tools/synthesize.py`'s module constants for the numbers). Don't silently switch it back — and don't trust `synthesize.py`'s own top-of-file docstring, which still names XTTS as the default; that's stale.
- **Reference budget is 60 seconds for XTTS; F5 clips its reference internally so it only uses 15 seconds (`F5_REFERENCE_SECONDS`).** The 60s figure was chosen by direct A/B listening test; don't assume it applies to F5 too — check `tools/synthesize.py`'s module constants, they differ per engine.
- **The apostrophe-stripping lexicon, not phonetic hyphenation.** `tools/pronunciations.json` respells names like `Zul'Aman` → `Zulaman` — dropping the apostrophe so it reads as one word. An earlier, more elaborate phonetic-hyphenation approach (`Zool-Ah-Mahn`) was tried and rejected on listening: every hyphen invites a micro-pause, so a three-hyphen name comes out as separate stressed pieces, and it measurably lengthened clips (~5.8%) too. See `_comment`/`_why_not_phonetic` in the JSON file itself — read those fields rather than paraphrasing from memory, they carry the actual reasoning.
- **The Lua SavedVariables parser turns array-style Lua tables (`{"a","b"}`) into a Python dict keyed `"1","2",...`, not a list.** Code that reads harvester output learned this the hard way — check `isinstance(x, dict)` and sort numeric keys, not `isinstance(x, list)`.
- **Quest text and gossip text are both absent from client data files.** Verified directly against the actual DB2 definitions for the current build, not assumed. Quest text has a Wowhead-scraping fallback; gossip text does not — it can only come from the harvester addon being played with. Don't go looking for a gossip DB2 table; there isn't one.
- **Wowhead rate-limits, and its listing/search endpoints 403 unconditionally.** See the safety rules above — this applies beyond just per-quest fetches.
- **71% of the shipped `.wav` library is actually MP3 in a `.wav` wrapper.** Only the genuine-PCM slice (29%) should ever be re-encoded — `convert_library.py` checks the `fmt` chunk's format tag, not just the RIFF/WAVE header, before touching a file. Re-encoding an already-lossy file is a real quality cost for little to no size benefit.
- **WoW 12.x returns tagged "secret" values** where plain strings used to come back from certain API calls (unit GUIDs and similar). Code touching these guards with `issecretvalue()`/`SecretUtil` and wraps `strsplit` on a GUID in `pcall`. `QuestReaderAddon.lua`'s GUID-parsing helpers already do this — don't remove the guard thinking it's dead code, and don't share it with the harvester addon by reference (the two addons never load together).

## Conventions

- Pronunciation fixes go in `tools/pronunciations.json`, added only after actually hearing a name mispronounced in generated audio and checking the respelling against the game's own voice-over — never guessed in advance.
- Voice bank donor choices for NPCs with no audio of their own are a judgement call, not something to leave silently unfilled. Document the reasoning in the commit when picking one.
- Commit messages in this repo explain *why*, generally at some length — match that style rather than terse one-liners, especially for anything fixing a bug that wasn't obvious from the symptom.
