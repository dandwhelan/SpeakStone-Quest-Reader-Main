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

---

## How the audio is made

Quest text is not in the game files -- it is delivered by the server at
runtime -- so it has to be captured from a live client, which is what this
addon does. The voices are cloned per NPC from that character's own recorded
in-game dialogue using F5-TTS.

The generation pipeline (harvesting, voice matching, synthesis, pack
building) is a separate private workspace and is not part of this repo. This
repo is the addon itself.
