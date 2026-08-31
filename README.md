<p align="center">
  <img src="media/icon.png" alt="SpeakStone Narration" width="160">
</p>

<h1 align="center">SpeakStone Narration</h1>

**A World of Warcraft addon that reads quest text out loud — in the voice of
the NPC who's actually speaking.**

Every quest description, progress and completion line is voiced using an AI
voice cloned from that quest giver's own in-game dialogue. Books, letters and
NPC greetings get the same treatment where audio exists.

Quest text appears, the right character reads it to you. That's it.

## Install

You need **two** addons: the main one, and a voice pack for the expansion you
want to hear.

1. Download **SpeakStone Narration** (the main addon) and
   **SpeakStone Narration - Midnight Voices** (the audio).
2. Unzip both into your AddOns folder, usually:
   `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns`
3. Start WoW and make sure both are ticked in the AddOns list.

The main addon contains no audio on its own — it's the player, and the packs
are the records. Install as many packs as you like; they stack.

Pick up a quest and it just starts talking. A **Read Quest** button also
appears at the bottom of the quest window if you'd rather trigger it yourself.

> Using a quest UI addon like **Immersion** or **DialogueUI**? Turn auto-play
> on in SpeakStone's own settings — those addons use their own window, which
> otherwise bypasses the trigger.

## Commands

| Command | What it does |
| --- | --- |
| `/speakstone` | Open settings |
| `/qrauto` | Turn auto-read on or off |
| `/qrtoggle` | Show or hide the minimap button |
| `/qrlibrary` | Browse and replay any voiced quest |
| `/qrmissing` | Export quests that had no audio, so they can be voiced |
| `/ssharvest` | Show and export everything the addon has captured |

Short forms work too: `/ss`, `/ssauto`, `/ssmissing`.

## Heard "no audio for quest"?

That quest hasn't been voiced yet — nothing is broken.

The addon quietly saves that quest's text when it happens. Type `/qrmissing`,
copy what appears, and paste it at
**[speakstone.beanw.co.uk](https://speakstone.beanw.co.uk)** to put it in the
queue to be voiced. That's the single most useful thing you can do to help,
and it takes about ten seconds.

This capture is **on by default** and also picks up NPC greetings and book
text as you go — that content can't be gathered any other way, so playing
normally with it on genuinely helps. Untick *Capture quest text* in the
settings, or type `/ssharvest off`, to stop it.

**Your character's name is never stored.** It's replaced with `$n` — the same
placeholder the server filled in — before anything is written to disk.

## Good to know

- **English only** at the moment.
- **Coverage is partial and growing.** The War Within and Midnight are the
  best covered; older expansions are patchy. You'll hit unvoiced quests.
- **NPC greetings are thin.** Playback works, but very little has been
  recorded yet — that text can't be gathered automatically, so it depends on
  players submitting it.
- These are AI voices. They're good, not perfect.

## Thanks

- **[clhammer89](https://github.com/clhammer89)**, author of the original
  [wow-questreader](https://github.com/clhammer89/wow-questreader) — this
  project is a fork of that addon, and the whole idea, the original playback
  engine and the first voice library are theirs. None of this exists without
  that groundwork.
- **Paratusjv** (CurseForge) for the stop functionality and quest-UI-addon
  support added in an earlier version.
- Everyone who has sent feedback, bug reports and captured quest text —
  thank you, HAQ!

## Support the project

Generating voices takes a lot of GPU time, and the site that collects quest
text costs money to keep running. If you'd like to chip in:

**[buymeacoffee.com/dandwhelane](https://buymeacoffee.com/dandwhelane)**

Never required, always appreciated. Submitting missing quests with
`/qrmissing` helps just as much.

## Links

- Website: https://speakstone.beanw.co.uk
- This project: https://github.com/dandwhelan/SpeakStone-Quest-Reader-Main
- Original addon this was forked from: https://github.com/clhammer89/wow-questreader

---

## Technical deep dive: how the voiceovers actually get made

This section is for anyone who wants to know what's really going on under
the hood, or wants to help regenerate audio for a new patch. Everything
described here lives in `tools/`, which has its own more detailed README.

### The core problem: quest text isn't in the game files

You'd expect quest description/progress/completion text to be sitting in a
client database table somewhere, minable like almost everything else in WoW.
It isn't. The `QuestV2` table carries only an ID, a bit flag, and a UI theme
ID; `QuestObjective` carries short one-line objective strings, not the
narrative text. The actual prose is delivered by the server at runtime and
exists nowhere in the files Blizzard ships.

So getting the text at all means one of two things: reading it live off a
running client, or getting it from somewhere that already collected it from
players. Both are used here — a companion in-game addon
(`QuestReaderHarvester`) for authoritative live capture, and a Wowhead
scraper for bulk coverage of content Wowhead has already indexed.

The base narration addon (`QuestReaderAddon`, this repo's root) also captures
quest text on its own, scoped to exactly the passages it finds no audio for
as you quest normally -- `/qrmissing` exports what it has caught, in the same
shape `QuestReaderHarvester`'s export uses, ready to paste at
speakstone.beanw.co.uk. It is a narrower net than the Harvester (quests only,
not gossip or item text, and only what has no audio yet rather than
everything), but it means a gap gets reported by every player who hits it in
normal play, not only players who separately install and enable the
Harvester.

Gossip text — the greeting an NPC gives when clicked, whether or not they
offer a quest — has the exact same problem, confirmed directly against the
client's actual data definitions for the current build: there is no
gossip-text table either. The nearest thing, `GossipNPCOption`, only carries
structural flags (vendor links, trainer links, LFG queue links), no text
field at all. So gossip audio can *only* come from the harvester; there is no
Wowhead-equivalent shortcut for it. If you want to help, enable
`QuestReaderHarvester` and just play the game — every NPC gossip window you
open gets captured.

### The voice side: NPC audio is fully minable

Unlike quest text, every line of NPC speech in the game is a real file on
Blizzard's CDN, and a community-maintained listfile maps file IDs to their
paths. Creature dialogue lives at predictable paths —
`sound/creature/<npc>/vo_<patch>_<npc>_<nn>.ogg` — so it can be indexed and
searched without touching the game client at all.

Coverage varies a lot by NPC. Named story characters are richly recorded —
Alleria Windrunner alone has over a thousand clips — while many minor quest
givers have only a handful, and about a fifth have none at all. Those get a
stand-in voice instead of their own (see "Filling the gaps" below).

### Turning text + reference audio into a voice clone

The engine is **F5-TTS**, a flow-matching voice cloning model, chosen over
the more commonly used XTTS-v2 after a direct, measured comparison: cloning
the same NPC from identical reference audio, F5's output matched the
reference voice's own frequency balance far more closely — especially in the
800 Hz–2.5 kHz band where speech articulation and emphasis actually live,
where XTTS scooped that band while adding extra bass and treble that reads
as "boomy" and "vague." A listening test agreed with the measurement.

A few things about how a clone is built matter more than they look:

- **How much reference audio to use is a real trade-off, not "more is
  better."** Handing the model everything available makes it average across
  all of it, which flattens delivery. The pipeline defaults to 60 seconds of
  reference audio per voice, chosen by direct A/B listening test — earlier
  defaults used far less on the theory that more reference audio would hurt
  more than it helped, which turned out to be wrong for how closely the
  clone should resemble a specific, recognisable NPC.
- **Which clips get used, not just how many.** Reference clips are ranked to
  prefer ordinary connected dialogue over combat barks and reaction lines —
  though this only works where filenames describe their contents, and modern
  voice-over files (`vo_121_taklejo_7758051.ogg`) carry no such information,
  so for recent content this reduces to picking clips of a sensible length.
- **Loudness is matched to the game, not guessed.** Generated audio is
  normalised to -16 LUFS, measured directly against the game's own dialogue
  (which sits at about -16.1 LUFS) rather than picked arbitrarily.
- **Pronunciation of in-universe names is a real, recurring problem.** No
  model trained on English speech will pronounce "Zul'Aman" correctly on the
  first try. `tools/pronunciations.json` is a small, deliberately
  hand-curated lexicon of respellings for names the model gets wrong,
  applied to text before it reaches the engine. It only grows by listening —
  never by guessing in advance. The current fix is the smallest one that
  works: strip the apostrophe so the name reads as one word
  (`"Zul'Aman"` → `"Zulaman"`). An earlier, more elaborate approach spelled
  names out phonetically with hyphens (`"Zool-Ah-Mahn"`); it was tried and
  rejected on listening — every hyphen invites a small pause, so a
  three-hyphen name comes out as separate stressed pieces instead of one
  word, and it measurably lengthened clips too. The lookup itself has to
  match the *longest* candidate name first (`"Amani'Zar"` before `"Amani"`),
  or a short name that happens to be a prefix of a longer one gets mangled.

### Filling the gaps: NPCs with no voice of their own

Roughly a fifth of NPCs have no recorded speech at all — often generic,
unnamed characters. Rather than pick a voice at random (which produces
things like a dwarf sounding like a tree spirit), those NPCs are grouped by
race and sex, and each group is assigned one donor voice: preferably one of
the ~160 anonymous "generic" voice pools the game itself ships for exactly
this purpose (`generic_blood_elf_citizen_a` and similar), falling back to
the best-recorded named NPC of a matching race and sex where no pool exists.
A handful of groups still have no good match at all — those get an explicit,
deliberate choice, documented as such, rather than a silent guess.

### Keeping the download size sane

The original shipped library looks bigger than it is. Of the 5,238 audio
files, 71% are already MP3 compressed audio wearing a `.wav` file extension
— the game reads file contents rather than trusting the name, so they've
always played correctly, and re-encoding them again would just be a second
lossy pass for no real benefit. Only the remaining 29% is genuine
uncompressed PCM, and that slice — and only that slice — gets re-encoded to
Ogg Vorbis, at a quality setting matched to what the game's own dialogue
already uses. That one change alone removes roughly 340 MB from the
download without touching a single file that didn't need it.

### The pipeline, end to end

For anyone who wants to actually run this:

```
tools/missing_quests.py      Diff the client's quest table against
                              SoundLengths.lua -> quest IDs with no audio

tools/wowhead_quests.py      Fetch quest text + speaker for those IDs
tools/QuestReaderHarvester   ...or capture it live, in-game, instead
tools/harvest_export.py      Convert the harvester's capture into the
                              same format the Wowhead fetch produces

tools/voice_sources.py       Find which NPCs have usable reference audio
tools/npc_traits.py          Resolve an NPC's race/sex from client data
tools/voice_bank.py          Assign a stand-in voice to NPCs with none

tools/synthesize.py          Generate the actual audio (F5-TTS by default)
tools/build_soundlengths.py  Rebuild the index the addon reads
tools/convert_library.py     Shrink the genuine-PCM slice of the library
tools/build_sound_packs.py   Split the library into per-expansion packs
tools/publish_packs.py       Push each pack to its own repo
```

`tools/run_batch.py` wraps most of this into one command for routine use —
fetch new quest text from the companion website, synthesize, install, rebuild
the index, and optionally tell the website what's now voiced — and
`tools/wake_when_work.py` can wake a sleeping GPU machine over LAN when work
shows up. See `docs/walkthrough.md` for the actual step-by-step operator
process, including the safety gates around rebuilding `SoundLengths.lua`.

`tools/README.md` covers all of this in far more depth, including exact
commands, what each generation setting actually does and why, and the
Windows-specific installation quirks (PyTorch version pins, a required
`torchcodec` removal, and similar) that took real trial and error to work
out.
