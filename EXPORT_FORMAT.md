# WoW Forever AI Exporter output contract — version 5

This is a technical reference for people writing software that reads exports.
For setup and everyday use, start with the [beginner guide](README.md).
To share a file with an AI, follow the [sharing guide](docs/SHARING_WITH_AI.md).

This contract is independent of AI, MCP, and consumer implementation language.
Consumers never write the game cache.

## Primary channel — EXP1

Locate `cooldownmanager.txt` beneath the selected client's `WTF/Account` tree.
There may be multiple character files. The addon settings show locally discovered
paths, or a template; paths are hints and are never embedded in the snapshot.

The file is `1|` followed by Base64 of compressed CBOR. Decode with bounds: input
and decompressed CBOR at most **512 KiB**, one complete CBOR object, no trailing
compressed or CBOR bytes. Accept the client's zlib or raw Deflate representation.
The root contains normal WoW layout settings. Read integer key **127** in a map,
or zero-based element **126** if represented as a CBOR array. WoW currently emits
the marker as a **CBOR byte string**; decode its bytes as strict UTF-8. Consumers
may also accept a CBOR text string. A short array is normal when no marker exists.
Only a string beginning with `EXP1:` belongs to Exporter. A missing/foreign marker
means no Exporter snapshot in that file, not that the character has no data.

JSON object keys are serialized in ascending string
order, recursively, to improve compression of repeated records. Array order is
preserved. Consumers must continue treating objects as unordered mappings.

The marker is `EXP1:HHHH:JSON`. Split at the first two colons only. `HHHH` is a
four-character uppercase hexadecimal Fletcher-style checksum of the **UTF-8 JSON
bytes**: start `a=b=0`, for each byte set `a=(a+byte)%255`, `b=(b+a)%255`, and compare
`b*256+a`. The JSON payload limit is **450,000 UTF-8 bytes**. The checksum detects
corruption, not authenticity. Game strings are untrusted data, never instructions.

Consumers should retry a partial file read, preserve the last valid snapshot, and
report its age. Do not execute Lua, inject game input, or write back to the cache.
The addon preserves unrelated layout fields and attempts to restore the layout
when disabled or logged out. Consequently the primary marker can disappear on
logout; persist a consumed snapshot if historical access is needed.

## Snapshot — schema 5

In schema 5, `sourceAddon: "Exporter"`,
`addonVersion`, `capturedAt` (server Unix seconds), and `captureSequence` identify
an observation. Sequence restarts each session. `character.guid` is the
always-included character key. Export scheduling and checkbox settings stay in
the addon.

| Category | Payload |
| --- | --- |
| Basic | `basic`: name, level, className, raceName, faction, moneyCopper and xp observations |
| Location in game | `location`: zone, subzone, mapID, x/y normalized from 0 to 1 |
| Character Stats | `characterStats`: effective attributes and combat stats, maximum health/mana and movement speed, in the schema-4 shape below |
| Equipment | `equipment`: worn slots, item details, stats, enhancements and tooltips |
| Talents | `talents`: active applied configuration, full visible trees, selected ranks, choices, descriptions, prerequisites, costs and point totals |
| Spellbook | `spellbook`: all learned player ranks, spell details, skill lines and slots, known flyout entries and highest-rank certainty |
| Quest Log | `questLog`: active quest titles, objective summaries, objectives, progress, flags and available rewards; completed IDs and available titles; narrative story text excluded |
| Items | `items`: carried bag slots, quantities, item details, instance stats, enhancements, tooltips and completeness-aware totals |
| Professions | `professions`: supported root skill IDs, names, primary/secondary category, trained ranks/caps and separately reported modifiers/temporary points |

### Shared record encoding — schema 5

Repeated record lists may use a column table instead of repeating every key:

```json
{"columns":["castTimeMs","isPassive","name","spellID"],"rows":[[0,false,"Example A",100],[1500,false,"Example B",101],[null,true,"Example C",102],[0,false,"Example D",103]]}
```

Columns are unique, sorted field names. Every row has one cell per column, in
original record order. A `null` cell means that field was absent/unavailable;
it is not a zero, false, empty object or empty list. Known `0`, `false`, `[]` and
`{}` remain distinct, including inside nested rows. Reconstruct a record by
pairing columns with cells and omitting only `null` cells. Nested cell values
can themselves contain record tables. Timestamps and `incompleteFields` retain
their meanings and may be columns when they differ between records.

Readers must accept both ordinary record arrays and `{columns, rows}` at these
list fields: `entries`, `nodes`, `selectedTalents`, `powerCosts`, `conditions`,
`costs`, `objectives`, `items`, `choices`, `currencies`, `spells`, `headers`,
`skillLines`, `bags`, `edges`, `prerequisites`, `groups` and `sockets`.
The representation is selected per list: currently at least four records,
two columns, 60% populated cells and an estimated structural saving are required.
Consumers must not depend on these thresholds. Small/sparse lists remain arrays;
known empty lists remain `[]`. Scalar lists such as quest IDs are unchanged.

Basic, Location and Character Stats use descriptive fields. Professions uses
the shared record encoding for its entries.
Talents retains all choices, ranks, conditions, costs and descriptions. Spellbook
retains every learned rank, cost, description and cooldown measurement. Quest Log
retains all active objectives/rewards and completed IDs/titles. Items retains all
bag/slot identities, stacks, flags, totals and per-instance details. Column tables
only remove repeated field names; they never group away distinct observations.

Across categories, a tooltip line containing only `left` text becomes that exact
string. Lines with `right` text or additional fields stay objects, preserving
the original sides and order. `tooltipLines` always remains an array, including
when nested in a record-table cell. No tooltip text is deduplicated or truncated
by this projection, and descriptions are not substituted for tooltip text.

Item `stats` maps use the aliases below. Values and numeric precision are
unchanged. Unknown stat tokens stay unchanged. If an alias already exists as an
original key, the long token is retained too, preventing collisions.

| Original stat token | Schema-5 key |
| --- | --- |
| `ITEM_MOD_STRENGTH_SHORT` | `strength` |
| `ITEM_MOD_AGILITY_SHORT` | `agility` |
| `ITEM_MOD_STAMINA_SHORT` | `stamina` |
| `ITEM_MOD_INTELLECT_SHORT` | `intellect` |
| `ITEM_MOD_SPIRIT_SHORT` | `spirit` |
| `ITEM_MOD_HEALTH_SHORT` | `health` |
| `ITEM_MOD_MANA_SHORT` | `mana` |
| `ITEM_MOD_SPELL_POWER_SHORT` | `spellPower` |
| `ITEM_MOD_SPELL_DAMAGE_DONE_SHORT` | `spellDamage` |
| `ITEM_MOD_SPELL_HEALING_DONE_SHORT` | `spellHealing` |
| `ITEM_MOD_HEALTH_REGEN_SHORT` | `healthRegen` |
| `ITEM_MOD_MANA_REGENERATION_SHORT` | `manaRegen` |
| `ITEM_MOD_DAMAGE_PER_SECOND_SHORT` | `damagePerSecond` |
| `ITEM_MOD_ARCANE_RESISTANCE_SHORT` | `arcaneResistance` |

### Equipment — schema 5

Equipment contains `scanComplete` and a `bySlot` object. It inherits capture time
unless an older `capturedAt` is present. The fixed scope is equipped items; the
redundant `scope` and `equippedCount` fields are removed. Count entries with an
`itemID` for confirmed equipped items; that is not a complete total when
`scanComplete` is false.

```json
{"equipment":{"scanComplete":false,"bySlot":{"head":{"itemID":12345,"name":"Example Hat","stats":{"intellect":8},"tooltipLines":["+8 Intellect"]},"neck":false,"shoulder":{}}}}
```

This excerpt shows three slots. The collector visits all 19. Slot IDs 1 through
19 map in order to `head`, `neck`, `shoulder`, `shirt`, `chest`, `waist`, `legs`,
`feet`, `wrist`, `hands`, `finger1`, `finger2`, `trinket1`, `trinket2`, `back`,
`mainHand`, `offHand`, `ranged`, `tabard`. `bySlot` is always an object.

A slot value of `false` means confirmed empty. An object with `itemID` means
equipped; an empty object or missing slot key means unavailable, never empty.
Per-item `slotID`, `slotName` and redundant `empty: false` are removed. Item links,
IDs, names, quality, classifications, levels, stats, enchant/gem observations,
tooltip text and partial-field markers remain. Unknown or duplicate slot IDs
fail export rather than silently overwriting or dropping data. Failed/disabled
Equipment is omitted entirely, as in earlier compact schemas.

### Basic — schema 5

Basic can include the optional strings `raceName` and `faction`.

```json
{"basic":{"name":"Example","level":29,"className":"Priest","raceName":"Night Elf","faction":"Alliance","moneyCopper":123456,"xp":{"current":1500,"levelTotal":12000,"rested":3000,"disabled":false}}}
```

`raceName` is the localized readable name returned first by `UnitRace("player")`.
`faction` is the locale-independent group tag returned first by
`UnitFactionGroup("player")`, such as `Alliance`, `Horde` or `Neutral`. It is read
directly, never inferred from race. Race IDs/tokens and the duplicate localized
faction label are not included. Missing, empty, restricted or failed API values
are omitted independently. Disabling Basic omits the whole object. Basic inherits
the snapshot's `capturedAt`; `character.guid` remains independent of this category.

Basic can also include the following money and XP observations.

| Field | Type | Meaning and source |
| --- | --- | --- |
| `moneyCopper` | Nonnegative integer | Carried balance from `GetMoney()`, in copper. |
| `xp.current` | Nonnegative integer | XP earned within the current level, from `UnitXP("player")`. |
| `xp.levelTotal` | Nonnegative integer | Total XP required within the current level, from `UnitXPMax("player")`; not XP remaining. |
| `xp.rested` | Nonnegative integer | Reported rested XP from `GetXPExhaustion()`. |
| `xp.disabled` | Boolean | Whether XP gains are disabled, when `IsXPUserDisabled()` reports it. |

Each observation is independent. Valid zero and false remain values; nil rested
XP, missing/throwing APIs, restricted values and invalid/nonfinite numeric values
are omitted. An `xp` object with no readable observations is omitted. A zero
`levelTotal` does not imply a level cap. No inferred cap, XP percentage, remaining
XP or gold/silver breakdown is exported. These reads occur only when Basic is
enabled during the normal capture, without an extra export timer.

### Professions — schema 5

The independently selectable `professions` object
contains `scanComplete` and `entries`, inheriting the snapshot capture time. A
small list may look like:

```json
{"professions":{"scanComplete":true,"entries":[{"skillLineID":356,"name":"Fishing","category":"secondary","rank":75,"maxRank":150,"modifier":0,"tempPoints":25}]}}
```

`entries` uses the ordinary-array or `{columns, rows}` representation described
above. Each entry retains available `skillLineID`, localized `name`, `category`
(`primary` or `secondary`), trained `rank`/`maxRank`, and separately reported
`modifier`/`tempPoints`. Ranks and caps are nonnegative integers. Reported
modifiers/temporary points are finite numbers; signed values and numeric zeros
remain valid. Bonuses are not added into trained rank, and no derived effective
rank, cap flag, points-to-cap, counts or repeated source label is exported.

The supported root skill IDs are 129, 164, 165, 171, 182, 185, 186, 197, 202, 333,
356 and 393: first aid, blacksmithing, leatherworking, alchemy, herbalism, cooking,
mining, tailoring, engineering, enchanting, fishing and skinning. First aid,
cooking and fishing are secondary. Recipes, weapon/riding skills and
expansion-specific child skill trees are outside this category.

Capture prefers `C_SkillInfo.GetSkillLineInfoByID` for those twelve IDs and uses
the read-only skill list as fallback when membership cannot be determined from
direct reads. List enumeration is bounded to 512 rows. The collector does not
expand/collapse headers or open UI, request metadata loads or keep stale cached
ranks between captures. A contradictory readable row is retained with incomplete
coverage rather than erased by a nil lookup.

`scanComplete` describes supported profession membership, not optional metadata
completeness. Missing names or bonuses do not erase readable ranks. An empty
`entries` list confirms no supported professions only with `scanComplete: true`;
a partial empty scan has `scanComplete: false` and must not be interpreted as
proof of none. Wholly unavailable or disabled Professions is omitted. Existing
settings retain their selections; Professions defaults on when unspecified.

### Character Stats — schema 4

`characterStats` exports the following fields when the corresponding measurement
is readable. Numbers are direct values instead of nested `{value: ...}` or
base/current/bonus records. Missing measurements and empty groups are omitted.

| Field | Meaning |
| --- | --- |
| `maxHealth`, `maxMana` | Maximum health and maximum mana. Current health/mana are not collected. |
| `movementSpeedYardsPerSecond` | Available `current`, `run`, `flight` and `swim` speeds in yards per second. |
| `attributes` | Effective `strength`, `agility`, `stamina`, `intellect` and `spirit`. |
| `weapons.mainHand`, `weapons.ranged` | Available `minimumDamage`, `maximumDamage`, `speedSeconds` and `estimatedDps`. The DPS value is a weapon estimate, not measured combat DPS. |
| `weapons.attackPower` | Effective `melee` and `ranged` attack power. |
| `critPercent` | Available `melee`, `ranged` and `spell` critical-strike percentages. `spell` is keyed by school. |
| `hastePercent` | Available `melee`, `ranged` and `spell` haste percentages; negative values remain valid. |
| `spellDamageBonus` | Bonus spell damage by school, not a spell's total damage. |
| `spellHealingBonus` | Bonus spell healing, not a spell's total healing. |
| `defense` | Effective `armor`, effective defense `skill`, and `dodgePercent`. |
| `resistances` | Effective `arcane`, `fire`, `frost`, `nature` and `shadow` resistances. |

Spell-school maps use `holy`, `fire`, `nature`, `frost`, `shadow` and `arcane`.
For attributes, attack power, armor, defense skill and resistances, only the
collector's effective value is eligible. An unreadable effective value is omitted;
base or current values are never substituted for it.

Character Stats decimals are rounded to two decimal places, symmetrically for
positive and negative values (halfway values round away from zero). Integers are
unchanged. A nonzero value that would round to zero retains its original value,
so a small effect is not reported as absent. This rounding is specific to Character
Stats; the other categories retain their existing numeric values.

Base/current/bonus decompositions, weapon multipliers, derived movement percentages
and movement baseline/unit metadata are intentionally excluded from this shape.
The unit is expressed once in the movement field name. An older `capturedAt`, if
present, follows the inheritance rules below. This Character Stats shape remains
unchanged in schema 5; the shared record encoding does not round other categories.

### Missing data and compact metadata

**An absent field or category means its data is unavailable in this snapshot.**
Consumers must not substitute zero, false or a confirmed empty list for absence.
Disabled categories and failed section placeholders are omitted. Basic remains
optional: identity details, money and XP are not duplicated into `character`
when disabled.
Basic identifies the character class by its readable name. Item classification
fields with the same name remain part of Equipment and Items.

The export omits `available`, `availability`, `status`, `fieldStatus`, `statStatus`,
all other `*Status` metadata, diagnostic `reason` strings and the
`pendingTitleIDs`/`unavailableTitleIDs` loading lists. Completed quest IDs remain
in `questIDs`; a missing title is simply absent from `titlesByQuestID`. Collectors still
use this metadata internally for safe reads, retries and completeness checks;
it is removed when preparing the exported JSON. Missing, unsupported, restricted
and failed fields all have the same external representation: absence, or a `null`
cell inside a schema-5 record table.

Valid `0`, `false`, empty strings and confirmed empty arrays/objects remain values.
For example, an observed no-cost spell retains `powerCosts: []`, and an observed
empty bag slot retains `empty: true`. Unavailable placeholder collections are
omitted instead of being emitted as empty. A record can retain a known item,
spell, quest, node or slot ID even when its other details are unavailable.
Uncertain highest-learned-rank comparisons are omitted rather than presented as
confirmed numeric ranks.

Completeness and state flags with gameplay meaning remain, including
`scanComplete`, `totalsComplete`, `pendingChanges` and slot occupancy. Equipment
uses the named-slot representation above; Items retains `empty`. A readable portion
of a collection may be retained with `incompleteFields: ["fieldName"]` on its
parent. For example, a truncated tooltip can keep its readable `tooltipLines`
while listing `"tooltipLines"` in `incompleteFields`. Do not assume the collection
is exhaustive. This exception-only metadata replaces repeated collection status
strings; valid scalar fields in partial records remain useful.

### Capture timestamps

The root always contains `capturedAt`. A nested object inherits the nearest
enclosing capture timestamp when it has no `capturedAt` of its own. Equal nested
timestamps are omitted. An older retained talent build keeps its distinct
timestamp and `pendingChanges: true`; it must not be treated as newly observed
just because the outer snapshot is newer.

### Reader compatibility

Readers must accept schema 5 explicitly and support record arrays or column
tables, named Equipment slots, string/object tooltip lines, and item stat aliases.
Character Stats remains in its schema-4 shape. Apply the absence/timestamp rules
above. Do not require the legacy availability fields or restore them into AI
input. The reference decoder accepts schemas 1, 2, 3, 4 and 5 without altering their
values. It writes compact JSON by default; `--pretty` enables indentation for
human review. Older snapshots retain their original schema and timestamps.
In schema 1, `inventory` has its own format and cannot be read as `items`.
Category coverage varies even within a schema. Read only the fields present.

Schema 3 snapshots use the older nested Character Stats shape
described in the legacy reference, with schema 3's status removal and timestamp
inheritance applied. The reader does not silently convert old stats to schema 4.

The category reference below describes the detailed **schema-2/internal collector
records**. Source semantics and collection bounds continue to apply. Character
Stats field names/decompositions below are legacy forms replaced by the schema-4
shape above. Equipment uses its schema-5 shape and repeated lists may use the
shared schema-5 encoding. The `status`, `available`, `fieldStatus`, `*Status` and per-section
timestamp examples are also legacy/internal forms, not additional current fields;
the current projection rules above take precedence.

## Detailed category reference — legacy schema 2 / internal collectors

### Character Stats — legacy shape / internal collector

- `general.health` and `general.mana`: `maximum` only. Mana always requests
  power type 0, even if the character currently uses rage, energy or another power.
  A returned maximum of zero is valid and is not an API failure. Current exports omit
  current health and mana.
- `general.movementSpeed`: `current`, `run`, `flight`, `swim` in yards per second;
  `currentPercent` and `runPercent` relative to normal run speed 7. A stationary
  character has current speed zero; run speed describes its movement capability.
- `primaryAttributes`: strength, agility, stamina, intellect, spirit. Each holds
  `current`, `effective`, `positiveBonus`, `negativeBonus` from UnitStat.
- `weapons.mainHand` and `weapons.ranged`: `minimumDamage`, `maximumDamage`,
  `attackSpeedSeconds`, `positiveBonus`, `negativeBonus`, `damageMultiplier`,
  and `damagePerSecond` (average observed damage / attack speed). This is a weapon
  estimate, not measured combat DPS. No ranged weapon is `not_applicable`.
- `weapons.attackPower.melee` and `.ranged`: `base`, bonuses and `effective` (sum
  clamped at zero). These are observations of the respective unit APIs.
- `modifiers.criticalStrike`: `melee`, `ranged`, and `spell` by school, in percent.
- `modifiers.haste`: `melee`, `ranged`, `spell`, in percent; negative values are valid.
- `modifiers.spellDamage`: bonus spell damage by school. `spellHealing`: bonus
  healing. Neither is the total damage/healing of a particular spell.
- Spell-school records cover holy, fire, nature, frost, shadow, arcane, preserving
  differences instead of claiming one universal spell value.
- `defense.defense`: `base`, `modifier`, `effective`. `defense.dodge`: percentage.
  `defense.armor`: `base`, `effective`, `armor`, `bonus` in Forever API return order.
- `resistances`: arcane, fire, frost, nature, shadow. Each has `base`, `real`,
  `effective`, `bonus`, matching Forever's UnitResistance API. Consumers should
  use `effective` to compare with the character panel, not the second return.

Single-number records use `value`. Every measurement record includes `fieldStatus`
for its expected fields. Field status is `available`, `unavailable`, `unsupported`,
`restricted`, or `api_error`; unavailable values are omitted, never replaced with
zero. Groups and sections summarize as `available`, `partial`, or `unavailable`.
All stats are captured on export, so bonuses, maximum health/mana and movement reflect
that observation. No additional writes or continuous stat polling are introduced.

Settings changes redact the in-memory saved snapshot immediately and queue one
export to apply the new selection. External copies stay old until a new export arrives. Compute age from the
original capture time; reception/request times must never replace it.

### Equipment

`equipment` contains `capturedAt`, `available`, `status`, `scope: "equipped_items"`,
`scanComplete`, `equippedCount`, and a `slots` array covering slot IDs 1 through 19.
These are Head, Neck, Shoulder, Shirt, Chest, Waist, Legs, Feet, Wrist, Hands,
Finger 1/2, Trinket 1/2, Back, Main Hand, Off Hand, Ranged and Tabard. Bags and bank
items are outside this category. Unsupported inventory APIs produce an empty
`slots` array with `status: "unsupported"` and `scanComplete: false`.

Each slot has `slotID`, `slotName` and `status`. A confirmed empty slot has
`empty: true`; an equipped item has `empty: false`. Unreadable or restricted slots
omit `empty`, so an API failure cannot be mistaken for an unequipped slot.
`scanComplete` means all slot occupancies were readable; item details may still
be partial. If it is false, `equippedCount` counts only confirmed equipped items.

Equipped records contain the available `itemID`, full instance `link`, `name`,
`quality`, `baseItemLevel`, `itemLevel`, `requiredLevel`, `itemType`, `itemSubType`,
`equipLocation`, `classID` and `subClassID`. `fieldStatus` marks metadata availability.
`stats` maps the game's stat tokens to numeric values; `statStatus` marks individual
returned tokens and `statsStatus` summarizes their readability. Stats use the
full item link so copies with different suffixes or enhancements stay distinct.
An empty stats object with `statsStatus: "available"` means no numeric stats were
returned. Missing/restricted stats are omitted, never replaced with zero.

`enhancements` contains `enchantID` when present in the link, `sockets` (gem index,
item ID, available name/link and name status), `emptySockets`, and its own status.
`tooltipLines` holds up to 80 cleaned `{left, right}` text lines with a separate
`tooltipStatus`. These preserve weapon damage/speed, armor, enchant descriptions,
set bonuses and equip/use/proc effects supplied by the game. Text is not parsed
into invented numeric bonuses or added to character totals. Numeric item stats
and tooltip text can overlap; consumers must not blindly sum both.

Slots are reread on every export, so late item loading cannot restore gear that
has been removed. Missing item names/stats can request data loading, with at most
eight explicit item/spell requests per capture shared across Equipment, Talents,
Spellbook and Items. Same-kind IDs share a session-wide retry history: at most
three attempts per ID and at least 30 seconds between attempts. Data that finishes loading appears on a later export;
there are no extra export timers or automatic UI reloads. Disabling Equipment
skips its collector and exports only `{available: false, status: "disabled"}`.

### Talents

`talents` describes only the active applied configuration. A successful capture includes
`capturedAt`, `available`, `status`, `scanComplete`, `configID`, available
`configName`, `pendingChanges`, and arrays named `trees`, `selectedTalents` and
`currencies`. Inactive saved configurations and uncommitted preview builds are
not exported as applied talents.

Each tree preserves its ID, optional API-provided `name`, display groups, visible
nodes and currencies. Nodes include available ranks and maximum ranks, group IDs,
position, selected entry
ID, choices in `entries`, outgoing `edges`, incoming `prerequisites`, conditions
and costs. Entries preserve their IDs, spell IDs, names, descriptions, maximum
ranks, selection state and selected rank. Unselected entries have `selected: false`
and omit `selectedRank`; a selected entry includes its API-reported rank, including
a valid zero. The `selectedTalents` array provides a summary of selected entries
with positive ranks, linked back to the node and
entry IDs. Zero allocated ranks are valid; unselected visible choices remain in
the full tree even when `selectedTalents` is empty.

Tree/group names and spell descriptions are taken from the game API. Prerequisite
links preserve edge types and conditions; consumers must not assume that every
incoming edge represents an AND requirement. Costs and currency records preserve
the API's numeric values. `unspentPoints` reflects the reported currency quantity;
it is not a guessed total or a sum across potentially shared currencies.

Missing or restricted values are omitted with explicit availability/status
information, never replaced with zero. Consult record `status` and `fieldStatus`
before interpreting partial data. Missing optional names, descriptions or currency
data can leave an otherwise readable tree `partial`. A missing active configuration
or incomplete node scan is `pending`, with `scanComplete: false`; it is not a
confirmed complete build. Missing required talent APIs produce `unsupported`.
A restricted active configuration ID or staged-change value produces `restricted`;
other unreadable staged-change states produce `unavailable`. These failures affect
this section only. Tree `groupsStatus`/`currencyStatus` and individual record
statuses distinguish missing metadata from readable empty lists. All list fields
serialize as JSON arrays, including empty lists (`[]`).

Talents are reread at each export, with active configuration and staged-change
state checked again after scanning. If either changes during the read, that scan
is not published as a confirmed build. While edits are staged, a previous confirmed
snapshot for the same configuration may be returned with `pendingChanges: true`,
`status: "pending_changes"` and its original `capturedAt`. If none exists, the
section reports unavailable pending changes; a different configuration's build is
never substituted. Consumers must use the talent section's timestamp when it is
older than the enclosing export.

Missing spell text can request data loading within the shared eight-request
item/spell limit. Duplicate spell IDs share retry history with Spellbook: at most
three attempts per session, at least 30 seconds apart. Loaded text appears on a later export; no additional export timer is
started. Disabling Talents skips its collector and exports only
`{available: false, status: "disabled"}`.

### Spellbook

`spellbook` contains `capturedAt`, `available`, `status`,
`scope: "learned_player_spellbook"`, available `locale`, `scanComplete`,
`spellCount`, `rankGrouping`, and arrays named `skillLines` and `entries`.
It scans the player spellbook afresh at each export, including all learned ranks
of class, general, racial and passive spells and known flyout entries. Pet spells,
unlearned/future spells, off-spec entries and action-bar assignments are excluded.
An incomplete scan is not evidence that omitted spells are unlearned.
Traversal is bounded to 100 skill lines, 2,000 total spellbook slots and 200 slots
per flyout. Exceeding these guards produces `scanComplete: false` with a partial
or unavailable result, rather than claiming a complete spellbook.

Entries preserve their exact `spellID`, available `baseSpellID`, `name`,
`rankText`, numeric `rank`, `rankStatus`, `isPassive`, `isLowerRank`,
`skillLineIndex`, `spellBookSlot` and optional `flyoutID`. Metadata is queried by
the exact spell ID so a lower learned rank is not silently replaced by a higher
rank. Skill-line records retain the spellbook's grouping. Duplicate appearances
of the same spell ID do not require duplicate spell records.

Each entry includes available `description`, `tooltipLines`, `powerCosts`,
`castTimeMs`, `minRange`, `maxRange` and `baseCooldownMs`, with `fieldStatus` and
separate metadata statuses. Cast times and base cooldowns are in milliseconds;
range values retain the game's units. Descriptions and cleaned tooltip text
preserve damage/healing ranges, ticks, conditions and character modifiers instead
of converting them into a guessed single number. `tooltipLines` retains up to 80
lines per spell; a longer tooltip sets `tooltipStatus: "partial"` explicitly.
`baseCooldownMs` is the reported
base duration, not a running cooldown. Current cooldown timers and charges are
neither queried nor exported.

`powerCosts` preserves the game's resource types, values and conditions. An
explicitly empty API list has `powerCostsStatus: "no_cost"`; a missing (`nil`)
result means unavailable, not zero cost. Known passive spells may mark
inapplicable operational fields `not_applicable`. Missing, restricted or failed
numeric reads are omitted and marked explicitly; zero is retained only when
actually reported. Empty lists serialize as `[]`.

`highestLearnedRank` is the highest observed numeric rank among learned entries
with the exact same localized name, and `isHighestLearnedRank` compares an entry
with that observed rank. Consult `highestLearnedRankStatus`: incomplete names,
rank labels or scans can make this conclusion partial or unavailable. Unreported
or nonnumeric ranks are not guessed, and this grouping is not a claim that a
character has learned the highest rank obtainable in the game.

Missing spell data can request loading within the shared eight-request
item/spell limit, with three attempts per spell ID per session and at least
30 seconds between attempts. Talents shares spell IDs and retry history. Later exports reread the
current spellbook and loaded text, so a late callback cannot restore an unlearned
spell. No additional export timer is started. Disabling Spellbook skips collection
and produces only `{available: false, status: "disabled"}`.

All learned ranks found by the scan remain in the payload. The existing 450,000-byte JSON budget
and 512 KiB transport limits still apply. If a complete capture exceeds a limit,
exporting reports the size error and retains the last successful snapshot; it
does not silently truncate ranks or descriptions to fit.

### Quest Log

`questLog` contains `available`, `status`, `capturedAt`, and two independent
subsections: `active` and `completedHistory`. Each subsection has its own
`available`, `status`, `capturedAt` and `scanComplete`. One subsection can remain
readable when the other is unavailable; consumers must inspect both rather than
treating the category-level availability as proof that both are complete.

`active` contains `entries`, `headers`, `questCount`, `includesStoryText: false`
and available `reportedQuestCount`. When `includesStoryText` is false, quest entries omit narrative
`description` text and its `fieldStatus` entry. The subsection flag is present even when capture fails, distinguishing
this choice from an unavailable story field in older exports. Objective summaries
remain included; missing story text alone does not mark a quest partial or request
additional data loading. Headers preserve their ordinal `index`, original
`questLogIndex`, available `title` and `isCollapsed`. Quest entries retain
`questID`, `questLogIndex`, available `headerIndex`, `title`, `level`,
`objectiveSummary`, `objectives`, `flags` and `rewards`.
`headerIndex` refers to the ordinal in the `headers` array, not a quest-log row.
Available `difficultyLevel`, `suggestedGroup`, `questClassification` and `tag`
metadata preserve the client's quest-type/group indicators. `tag` can contain
`tagID`, `tagName`, `worldQuestType`, `quality`, `tradeskillLineID`, `isElite` and
`displayExpiration`, with its own `status` and `fieldStatus`. A successful lookup
with no tag produces `tagStatus: "not_applicable"`; missing, restricted or failed
tag reads remain explicit unknowns. Dungeon/group labels are not guessed from
quest titles.
Objectives preserve the available text, type, completion state and fulfilled /
required counts reported by the game. Flags include available `isComplete`,
`readyForTurnIn`, `isFailed`, `isRepeatable`, `isTask`, `isBounty`, `isStory`,
`isHidden`, `isAutoComplete`, `isWatched`, `watchType` and `frequency`; an unreadable
flag is not false. A successful watch-type lookup returning no watch type means
`isWatched: false`; an unsupported, restricted or failed lookup remains unknown.

Rewards retain available `xp`, `money`, guaranteed `items`, item `choices`,
`currencies`, `spells` and `majorFactionReputation`. Major-faction reputation is
the scope of the supported reputation API; other reputation rewards are not
inferred. Record `fieldStatus` and list/status fields distinguish readable data,
an explicitly empty reward list, and unsupported, restricted or unavailable
values. Missing numeric values are omitted, never replaced with zero. Active
quest objective summaries and progress are observations at capture time, not historical records.
For reward currencies/spells, a missing list plus an explicit `Has...: false`
result is a confirmed empty list. Missing major-faction reputation data remains
unknown because there is no corresponding absence check.

`completedHistory` contains the full reported completed quest-ID set as sorted,
deduplicated `questIDs`, plus `questCount`, `titlesByQuestID`, `titleCount`,
`pendingTitleIDs` and `unavailableTitleIDs`. `titlesByQuestID` is a JSON object
whose keys are decimal quest-ID **strings**, such as `"123"`; an empty map is
`{}`. `titleCount` counts the titles currently available in that map. Missing
titles are partitioned into pending and unavailable ID arrays. All ID lists and
other list fields serialize as arrays, including empty arrays (`[]`). Completed
history does not include past objective progress, old rewards or completion
dates. Its `capturedAt` is the observation time of the current completed-ID set,
not the time any quest was completed.

A readable empty API list is a valid empty log/history. A `nil`, restricted or
failed API result is unknown, with availability/completeness marked accordingly;
empty arrays accompanying a failed subsection must not be interpreted as proof
that no quests exist. Traversal guards allow at most 1,000 active log rows, 128
objectives per quest, 256 entries per reward list and 100,000 completed IDs.
Exceeding a guard reports an unavailable list or subsection rather than silently
truncating it. Missing objective/reward details make an active subsection partial
without necessarily making its quest membership incomplete. Membership and quest
update state are checked after each subsection and again before returning the
combined result, so history loading cannot leave an older active log marked
complete. An affected subsection is retried at most once in total. If it still
cannot be read consistently, it is returned with `available: false`,
`scanComplete: false` and `status: "pending"`; a consistent other subsection is
retained.

Quest membership, flags, progress and rewards are read afresh at each export.
Only titles are cached, and cached titles are used only for IDs in the current
log/history. Quest-data loading uses its own budget of 16 requests per capture,
three attempts per retained quest ID and at least 30 seconds between attempts.
Active quests receive priority; a rotating history queue gives missing completed
titles a chance to load on subsequent captures. A title callback does not restore
a removed quest or refresh a past state snapshot. Disabling Quest Log skips its
collector and produces only `{available: false, status: "disabled"}`.

All reported completed IDs are retained, including IDs whose titles cannot be
loaded. A large completed history, or titles added progressively to that history,
can exceed the unchanged 450,000-byte JSON budget or 512 KiB transport limits.
The export then reports an error and retains the last successful snapshot and
its original timestamp; it does not silently drop history IDs, titles or active
quest objectives to fit. Consumers must continue to check that timestamp for freshness.

### Items

`items` contains `available`, `status`, `capturedAt`, `scope: "carried_bags"`,
`scanComplete`, `totalsComplete`, `fieldStatus`, and arrays named `bags` and
`entries`. It reads the backpack (bag ID 0) and equipped bags 1 through 4. The
reagent bag is included only when `Enum.BagIndex.ReagentBag == 5`, and the keyring
only when `Enum.BagIndex.Keyring == -1`. The client uses other negative IDs for
bank storage; they are never treated as a keyring or scanned. Worn equipment,
banks and mail are outside this category.

Each supported bag has a record with `bagID`, available `name`, `numSlots`,
optional `bagFamily`, `status`, `scanComplete`, `totalsComplete`, `fieldStatus`
and known `freeSlots`/`occupiedSlots`/`itemCount` totals. `entries` contains one
record per enumerated slot, identified by `bagID`
and `slotID`. A confirmed empty slot has `empty: true`; a known occupied slot has
`empty: false`. An unreadable slot omits `empty`, so missing data cannot be
mistaken for unused space. Multiple copies of an item remain separate by location,
including items with the same ID but different stacks, suffixes or enhancements.
Empty list fields serialize as `[]`.

Occupied records preserve available `itemID`, full instance `link`, stack `count`,
`isBound`, `isLocked`, `hasNoValue`, `isReadable`, `hasLoot`, `isFiltered`, `name`,
`quality`, `baseItemLevel`, `itemLevel`,
`requiredLevel`, `itemType`, `itemSubType`, `equipLocation`, `isEquippable`,
`maxStack`, `sellPrice`, `classID`, `subClassID`, `bindType`, `isCraftingReagent`,
`itemDescription` and `iconID`. Optional metadata can be absent; inspect
`fieldStatus` and record status instead of filling in defaults.

`isEquippable` uses the client's item API when available. If that API is absent,
known equipment locations provide a fallback; an empty location or
`INVTYPE_NON_EQUIP_IGNORE` means false. Unknown locations and unreadable API
results remain unknown.

Actual `itemLevel` and per-instance `stats` use the full item link; `baseItemLevel`
is reported separately. A missing link does not permit a
generic item-ID lookup to stand in for that instance. An empty stats object with
`statsStatus: "available"` means no numeric stats were returned; unavailable or
restricted stats remain unknown. Up to 256 stat records are retained, with
`statsStatus: "partial"` if the limit is exceeded. `statStatus` marks individual
values. `enhancements` preserves `enchantID`, `sockets` and `emptySockets`;
readable bag-item tooltips preserve available effect text. These values are
observations, not invented bonuses or totals. Present blank enchant/gem fields in
a valid item link mean zero (no enhancement); missing or malformed fields remain
unknown. `tooltipLines` retains up to 80 cleaned text lines;
longer tooltips are marked partial rather than silently reported as complete.

Known top-level totals are `bagCount`, `totalSlots`, `freeSlots`, `occupiedSlots`
and `itemCount`. `bagCount` counts supported containers with positive known
capacity, including the backpack and keyring when present. `itemCount` sums stack
quantities, not occupied slots. Totals are exact or omitted: unknown bag capacity
omits `bagCount`/`totalSlots` and dependent totals; unknown slot occupancy omits
`freeSlots`, `occupiedSlots` and `itemCount`; an unknown stack count omits
`itemCount`. `fieldStatus` explains omissions, and `totalsComplete` is true only
when every total is known. Per-bag totals follow the same rule. Missing metadata
does not by itself imply that known counts are incomplete.

Bag capacity is bounded to 200 slots per bag; invalid or larger capacities are
reported as unavailable, not shortened. Every export rereads current bag contents
and checks item identity, count and instance link before/after collection. A changed
scan is retried once. Continuing instability produces an explicit partial result
rather than combining different observations of a moved item or changed stack.
An unstable slot omits its uncertain occupancy/details; an unstable bag capacity
omits `numSlots` and that bag's uncertain entries, with `scanComplete: false`.
Late item-load notifications never restore a previous bag position.

Missing item data can request loading within the shared eight-request
item/spell limit, with three attempts per item ID per session and at least 30 seconds
between attempts. Equipment shares item IDs and retry history, including items
moved between the two categories. Deferred IDs progress before retries. Quest
title requests retain their separate sixteen-request limit. These bounds apply
to explicit requests, not implicit loading by getters/tooltips. Disabling Items skips collection
and produces only `{available: false, status: "disabled"}`.

All collected slots and item details remain subject to the unchanged 450,000-byte
JSON budget and 512 KiB transport limits. A large bag export combined with other
categories can exceed these limits; the addon reports an error and retains the
last successful snapshot and its original timestamp. It does not silently drop
items or details to fit.

## Secondary saved-file copy

WoW also serializes the last JSON string in `ExporterSnapshotJSON` to the character's
`SavedVariables/Exporter.lua` on logout/reload. It is a Lua-escaped string, not a raw
JSON file. Decode the string safely and parse its JSON; do not execute the Lua file.
The original capture times remain authoritative. This can be a prior session's
snapshot; opening the game does not make it new. Neither mode captures or requests
metadata during logout. Export errors pause automatic attempts until an explicit
retry/settings change or a new UI session. Consumer filesystem paths and output filenames
are the consumer's responsibility.
