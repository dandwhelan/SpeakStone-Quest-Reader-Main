# Changelog

## 1.3

First public release.

### Added

- **Per-expansion sound packs.** Audio no longer ships inside the base addon.
  The base addon is code only; voice audio installs alongside it as separate
  pack addons (starting with *SpeakStone Narration - Midnight Voices*), so you
  download only the expansions you care about. Packs self-register with the
  base addon and merge into its lookup, in any load order.
- **Text capture is built in.** What used to be a separate companion addon
  (SpeakStone Harvester) is now part of the main addon and **on by default**.
  It records quest, gossip and book text as you encounter it, so the gaps in
  the voiced library can be filled. Turn it off any time with the
  *Capture quest text* setting, or `/ssharvest off`.
  `/ssharvest` shows what you've collected and exports it; `/qrmissing`
  exports just the quests that had no audio. Your character's name is
  scrubbed to `$n` before anything is stored.
  Anything captured by the old standalone addon is imported automatically.
- **Missing-quest capture.** When no installed pack has audio for a quest
  passage, the addon now records that quest's text, speaker and title locally.
  `/qrmissing` exports what it has collected, ready to paste at
  speakstone.beanw.co.uk so the quest can be voiced. Your character's name is
  substituted back out to `$n` before anything is stored.

### Changed

- `/qrmissing` now exports full quest text rather than listing sound filenames.
- Debug chat output is off by default; `/qrdebug` toggles it.

### Notes

- English (enUS) only for now.
- Gossip playback works, but very little gossip audio has been generated yet.
