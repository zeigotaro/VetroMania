# The Roster

[Back to the implementation plan](../implementation-plan.md)

> **Decision (2026-09-29): keep the *Fighting Baseball* names.** The plan's
> open question was whether to keep the exact fake baseball names behind
> "Sleve Bonzalez" or write new ones in the same style. We keep them, as
> found. Ledger entry [#1](reference-ledger.md#a-core-identity) tracks the
> risk.

## Where the names come from

The names are the famous roster from *Fighting Baseball* (Super Famicom,
1994), the Japanese release of *MLBPA Baseball*. It had no license for real
players, so the developers made up American-sounding names. The results
became a long-running internet joke. Our hero's name is a mashup of two of
them: **Sleve** McDichael and Todd **Bonzalez**.

In the fiction, they are the *Vetro Fighting Spaceballers '94* trading card
set that the Vetrans printed the Gravity Organ's score on (see
[Story and tone](story-and-tone.md#the-macguffin-makes-sense-technically)).
Each player is a holographic ex-athlete scattered across VetroMania.

## Rules for using the names

1. **Names only.** No text, art, code, data, or sound from the original game
   is used. Every character here is ours.
2. **Spell them as found.** *Dwigt* has no H, and Sernandez is not
   Hernandez. Nobody in the game explains why (except Dwigt, who asks you
   not to ask).
3. **Never name the real athletes** the originals were distorted from, in
   the game, the marketing, or these docs. The joke is that the names are
   nonsense.
4. **One source of truth.** Every name lives in
   [`game/data/roster.json`](../../game/data/roster.json). Nothing else in
   the game hard-codes one, so replacing a name after legal review is a
   data change.
5. **Credit the source.** The credits thank *Fighting Baseball* for the
   names, and the ledger keeps the entry at risk level M until legal review.
6. **Punch sideways.** The holograms joke about their own jobs and
   circumstances. They never joke about real people.

## The set

Card numbers are ours. "Slice" marks the ten holograms who speak in the
vertical slice; the rest are placed in later areas.

| # | Player | Position | Role in the game | Slice |
| --- | --- | --- | --- | --- |
| 1 | **Sleve McDichael** | Captain | Hall of Famer, Sleve Bonzalez's namesake. Appears in the Loser Colosseum | |
| 2 | **Onson Sweemey** | Batting Coach | Teaches the bat | Crash Site |
| 3 | **Darryl Archideld** | Catcher | Teaches the Mitt Cannon | Crash Site |
| 4 | **Anatoli Smorin** | Launcher | Points at the Koozie Statue | Hull Cathedral |
| 5 | **Rey McSriff** | Bullpen | Explains the Wall Kick ("it's called friendship") | Outer Hull |
| 6 | **Glenallen Mixon** | Concessions | Explains save pods and upgrades | Hull Cathedral |
| 7 | **Mario McRlwain** | Short Circuit | Server Chapel regular | |
| 8 | **Raul Chamgerlain** | Third Bass | Cryo Caverns lounge act | |
| 9 | **Kevin Nogilny** | Groundskeeper | Blames the crater on Sleve | Crash Site |
| 10 | **Tony Smehrik** | Bat Boy (age 52) | Keeps the bats shiny | |
| 11 | **Bobson Dugnutt** | Rookie | The face on the card. Referees the Loser Colosseum. Playable in Bobson Mode | |
| 12 | **Willie Dustice** | Umpire | Calls the hollow wall | Hull Cathedral |
| 13 | **Jeromy Gride** | Utility | Duct-tape solutions | |
| 14 | **Scott Dourque** | Announcer | Announces bosses | Outer Hull |
| 15 | **Shown Furcotte** | Team Doc | Diagnoses everything as space dysentery | |
| 16 | **Dean Wesrey** | Manager | Explains Autograph Seals ("I'm 40% thumb") | Outer Hull |
| 17 | **Mike Truk** | Team Truck | Refuses to carry the crate | Outer Hull |
| 18 | **Dwigt Rortugal** | First Bass | Has no H. Don't ask | |
| 19 | **Tim Sandaele** | Right Field | Left behind | |
| 20 | **Karl Dandleton** | Left Field | Right behind | |
| 21 | **Mike Sernandez** | Scout | Explains Kill Tallies | Hull Cathedral |
| 22 | **Todd Bonzalez** | Owner | Sleve's uncle. Runs Todd's Card & Bait in Cyber-Mall 1996 | |

## Where they show up

- **Holograms.** Talk to one with Up. Each stands on a hologram pad, flickers,
  and delivers hints in character. Hints are real, delivered badly.
- **Loser Colosseum.** *The Entire Roster* boss fight has all 22 cards on
  the field at once, with Bobson Dugnutt refereeing.
- **The Roster set.** The Ainamortev set's full-set bonus summons hologram
  teammates. Their names are drawn from this table.
- **Bobson Mode.** A post-game mode where you play as Bobson Dugnutt.
- **Credits.** They thank *Fighting Baseball* for the names.
