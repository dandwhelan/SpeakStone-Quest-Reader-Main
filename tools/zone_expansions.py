"""
Zone name -> expansion mapping used by infer_expansions.py.

Each entry maps a Wowhead zone name (as it appears in the "A level N <Zone>
Quest" og:description text, or in the page's embedded zone data blob) to
either:

  - a single expansion string, when the zone is exclusive to one expansion, or
  - the sentinel AMBIGUOUS plus a tuple of candidate expansions, when the same
    zone name is reused across expansions (e.g. Nagrand in Outland vs
    Nagrand on Draenor).

This table is deliberately conservative: a zone not listed here is treated as
unknown rather than guessed, and an ambiguous zone is never resolved by
picking one candidate arbitrarily. infer_expansions.py handles ambiguous
zones by looking for corroborating expansion-exclusive zone names elsewhere
on the same cached page; if it finds none, it leaves the quest unlabelled.
"""

CLASSIC = "Classic"
TBC = "The Burning Crusade"
WOTLK = "Wrath of the Lich King"
CATA = "Cataclysm"
MOP = "Mists of Pandaria"
WOD = "Warlords of Draenor"
LEGION = "Legion"
BFA = "Battle for Azeroth"
SL = "Shadowlands"
DF = "Dragonflight"
TWW = "The War Within"
MIDNIGHT = "Midnight"

EXPANSIONS = [
    CLASSIC, TBC, WOTLK, CATA, MOP, WOD, LEGION, BFA, SL, DF, TWW, MIDNIGHT,
]

AMBIGUOUS = "AMBIGUOUS"

# zone name -> expansion string, or (AMBIGUOUS, (candidate1, candidate2, ...))
ZONE_EXPANSIONS = {
    # ---- Classic ----
    "Dun Morogh": CLASSIC, "Elwynn Forest": CLASSIC, "Durotar": CLASSIC,
    "Mulgore": CLASSIC, "Tirisfal Glades": CLASSIC, "Teldrassil": CLASSIC,
    # Blood elf/draenei starting zones shipped with TBC, but -- like the
    # original capitals -- they stay in the world forever and pick up
    # "evergreen" repeatable quests (PvP/profession reward hubs) from any
    # later expansion, so they are not a safe unambiguous TBC signal.
    "Eversong Woods": (AMBIGUOUS, tuple(EXPANSIONS)),
    "Azuremyst Isle": (AMBIGUOUS, tuple(EXPANSIONS)),
    "Loch Modan": CLASSIC, "Westfall": CLASSIC, "Redridge Mountains": CLASSIC,
    "Duskwood": CLASSIC, "Wetlands": CLASSIC, "Stonetalon Mountains": CLASSIC,
    "Ashenvale": CLASSIC, "Thousand Needles": CLASSIC, "Northern Barrens": CLASSIC,
    "Southern Barrens": CATA,  # Cataclysm split/revamp of the Barrens
    "The Barrens": CLASSIC,
    "Hillsbrad Foothills": CLASSIC, "Alterac Mountains": CLASSIC,
    "Arathi Highlands": (AMBIGUOUS, (CLASSIC, BFA)),  # BfA warfront revamp
    "Northern Stranglethorn": CLASSIC, "Stranglethorn Vale": CLASSIC,
    "Cape of Stranglethorn": CLASSIC, "Swamp of Sorrows": CLASSIC,
    "Blasted Lands": (AMBIGUOUS, (CLASSIC, TBC)),  # portal area, quests span both
    "Desolace": CLASSIC, "Feralas": CLASSIC, "Dustwallow Marsh": CLASSIC,
    "Thousand Needles": CLASSIC, "Tanaris": CLASSIC, "Azshara": CLASSIC,
    "Felwood": CLASSIC, "Un'Goro Crater": CLASSIC, "Moonglade": CLASSIC,
    "Silithus": (AMBIGUOUS, (CLASSIC, BFA)),  # BfA Silithus war campaign
    "Winterspring": CLASSIC, "Darkshore": (AMBIGUOUS, (CLASSIC, BFA)),  # BfA warfront
    "Blackrock Mountain": CLASSIC, "Deadwind Pass": CLASSIC,
    "Burning Steppes": CLASSIC, "Searing Gorge": CLASSIC,
    "Badlands": CLASSIC, "Silverpine Forest": CLASSIC, "Darkshore": (AMBIGUOUS, (CLASSIC, BFA)),
    "Ashenvale": CLASSIC, "Stormwind City": (AMBIGUOUS, EXPANSIONS),  # capital, any era
    "Orgrimmar": (AMBIGUOUS, EXPANSIONS),
    "Ironforge": CLASSIC, "Undercity": CLASSIC, "Darnassus": CLASSIC,
    "Thunder Bluff": CLASSIC,
    "Eastern Plaguelands": CLASSIC, "Western Plaguelands": CLASSIC,

    # ---- The Burning Crusade ----
    "Hellfire Peninsula": TBC, "Zangarmarsh": TBC, "Terokkar Forest": TBC,
    "Nagrand": (AMBIGUOUS, (TBC, WOD)),  # Outland vs Draenor
    "Blade's Edge Mountains": TBC, "Netherstorm": TBC,
    "Shadowmoon Valley": (AMBIGUOUS, (TBC, WOD)),  # Outland vs Draenor
    "Shattrath City": TBC, "Isle of Quel'Danas": TBC,
    "Silvermoon City": (AMBIGUOUS, EXPANSIONS),  # capital, appears in Midnight cache too

    # ---- Wrath of the Lich King ----
    "Borean Tundra": WOTLK, "Howling Fjord": WOTLK, "Dragonblight": WOTLK,
    "Grizzly Hills": WOTLK, "Zul'Drak": WOTLK, "Sholazar Basin": WOTLK,
    "The Storm Peaks": WOTLK, "Icecrown": WOTLK, "Wintergrasp": WOTLK,
    "Crystalsong Forest": WOTLK, "Dalaran": (AMBIGUOUS, (WOTLK, LEGION)),

    # ---- Cataclysm ----
    "Mount Hyjal": CATA, "Vashj'ir": CATA, "Deepholm": CATA,
    "Uldum": CATA, "Twilight Highlands": CATA, "Tol Barad": CATA,
    "Gilneas": CATA,

    # ---- Mists of Pandaria ----
    "The Jade Forest": MOP, "Valley of the Four Winds": MOP,
    "Krasarang Wilds": MOP, "Kun-Lai Summit": MOP, "Townlong Steppes": MOP,
    "Dread Wastes": MOP, "Vale of Eternal Blossoms": MOP, "The Wandering Isle": MOP,
    "Isle of Thunder": MOP, "Timeless Isle": MOP,

    # ---- Warlords of Draenor ----
    "Talador": WOD, "Gorgrond": WOD, "Frostfire Ridge": WOD,
    "Spires of Arak": WOD, "Tanaan Jungle": WOD, "Ashran": WOD,
    "Nagrand (Draenor)": WOD, "Shadowmoon Valley (Draenor)": WOD,

    # ---- Legion ----
    "Azsuna": LEGION, "Val'sharah": LEGION, "Highmountain": LEGION,
    "Stormheim": LEGION, "Suramar": LEGION, "Broken Shore": LEGION,
    "Dalaran (Broken Isles)": LEGION, "Argus": LEGION, "Krokuun": LEGION,
    "Mac'Aree": LEGION, "Antoran Wastes": LEGION, "Eye of Azshara": LEGION,

    # ---- Battle for Azeroth ----
    "Tiragarde Sound": BFA, "Drustvar": BFA, "Stormsong Valley": BFA,
    "Zuldazar": BFA, "Nazmir": BFA, "Vol'dun": BFA, "Nazjatar": BFA,
    "Mechagon Island": BFA, "Kul Tiras": BFA, "Zandalar": BFA,

    # ---- Shadowlands ----
    "Bastion": SL, "Maldraxxus": SL, "Ardenweald": SL, "Revendreth": SL,
    "The Maw": SL, "Korthia": SL, "Zereth Mortis": SL,
    # Oribos is Shadowlands' capital hub, so -- like Dalaran/Silvermoon City
    # /Stormwind -- it keeps hosting evergreen repeatable quests (Timewalking
    # badge vendors, weekly reward quests) long after the expansion ended.
    # Two sampled matches were both later Timewalking-event quests, not
    # genuine Shadowlands content, so this is ambiguous rather than trusted.
    "Oribos": (AMBIGUOUS, tuple(EXPANSIONS)),

    # ---- Dragonflight ----
    "The Waking Shores": DF, "Ohn'ahran Plains": DF, "The Azure Span": DF,
    "Thaldraszus": DF, "Forbidden Reach": DF, "Zaralek Cavern": DF,
    "The Forbidden Reach": DF, "Valdrakken": DF, "The Emerald Dream": DF,

    # ---- The War Within ----
    "Isle of Dorn": TWW, "The Ringing Deeps": TWW, "Hallowfall": TWW,
    "Azj-Kahet": TWW, "Dornogal": (AMBIGUOUS, (TWW, MIDNIGHT)),
    "K'aresh": TWW, "Undermine": TWW,

    # ---- Midnight ----
    "The Coiled Isle": MIDNIGHT, "Quel'Thalas": (AMBIGUOUS, (TBC, MIDNIGHT)),
}


def lookup(zone_name):
    """Return (expansion, is_ambiguous, candidates) for a zone name.

    Returns (None, False, None) if the zone is unknown.
    """
    entry = ZONE_EXPANSIONS.get(zone_name)
    if entry is None:
        return None, False, None
    if isinstance(entry, tuple) and entry[0] == AMBIGUOUS:
        return None, True, entry[1]
    return entry, False, None
