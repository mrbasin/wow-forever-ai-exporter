# Collection details

This optional reference explains exactly what the addon collects and how it saves
the result. For installation and everyday use, start with the [main guide](../README.md).

## Export categories

| Category | Included information |
| --- | --- |
| **Basic** | Character name, level, class, race, faction, carried money and available XP/rested-XP observations. |
| **Location in game** | Zone, subzone, map ID and coordinates. |
| **Character Stats** | Effective character stats and combat measurements listed below. |
| **Equipment** | Every worn slot: armor, jewelry, main hand, off hand, ranged weapon, shirt and tabard. Item identity, quality, levels, type, numeric item stats, enchants, gems and readable effect/weapon tooltips. Bag and bank contents are excluded. |
| **Talents** | The full visible tree for the active talent configuration: tree/group names, selected talents and ranks, maximum ranks, unselected choices, spell IDs and descriptions, prerequisites, costs and available unspent point totals. |
| **Spellbook** | All learned player spell ranks, including class, general, racial and passive spells and known flyout entries. Spell/base IDs, spellbook groups and slots, names, ranks, descriptions, tooltip text, power costs, cast times, ranges and base cooldowns. |
| **Quest Log** | Active quest titles, objective summaries, objectives and progress, quest flags and available rewards; completed-quest history with every reported quest ID and titles where available. Narrative story text is excluded. |
| **Items** | Every readable carried bag slot, with confirmed empty slots identified; item quantities, identities, binding/lock state, names, quality, levels, types, stack limits, sell prices, per-instance stats, enchants, gems and readable bag-item tooltips. |
| **Professions** | Known Forever primary professions plus cooking, first aid and fishing: skill IDs, names, trained ranks/caps and separately reported modifiers/temporary points. Recipes, weapon/riding skills and expansion-specific child trees are excluded. |

Character Stats includes these measurements:

| Group | Included information |
| --- | --- |
| **General** | Maximum health, maximum mana and movement speed in yards per second. |
| **Primary** | Effective strength, agility, stamina, intellect and spirit. |
| **Weapons** | Main-hand and ranged weapon damage, speed, estimated weapon DPS and effective attack power. |
| **Modifiers** | Critical strike, haste, spell damage and spell healing. |
| **Defense** | Effective defense skill, dodge percentage and effective armor. |
| **Resistances** | Effective arcane, fire, frost, nature and shadow resistances. |

Schema 4 stores these stats as direct numbers with meaningful field names, such
as `maxHealth`, `attributes.intellect` and `hastePercent.spell`. It omits repeated
base/current/bonus decompositions and derived movement percentages. Unavailable
effective values stay absent; base values are never used as substitutes. Decimals
are rounded to two places, symmetrically for negative values, while integers and
tiny nonzero values that would round to zero are preserved. Other categories'
numeric precision is unchanged. See [the format contract](../EXPORT_FORMAT.md#character-stats--schema-4)
for exact keys and units.

Character GUID, schema/version and the snapshot capture timestamp are always
included. Disabling Basic removes identity details, carried money and XP from the next snapshot.
Schemas 3 through 5 optimize the decoded JSON for AI tokens: missing fields or categories
mean unavailable, without repeated availability/status labels. In schema-5 record
tables, a `null` cell represents an absent field. Valid zero,
false and confirmed empty values remain. Nested timestamps inherit from the
enclosing snapshot unless an older observation needs its own timestamp.
`scanComplete`, `totalsComplete` and exception-only `incompleteFields` preserve
the meaning of partial collections. Current health and mana are not queried or
exported.

Basic stores carried money once as integer `moneyCopper`. The optional `xp`
object contains `current`, `levelTotal`, `rested` and boolean `disabled` when
reported by the player APIs. `levelTotal` is the total required within the level,
not XP remaining. Valid zero and false values are preserved. Nil rested XP stays
unknown, and a zero level total does not imply a level cap. Missing, restricted,
invalid or failed observations are omitted independently; no percentages or
gold/silver breakdowns are duplicated.

Talents exports the applied build, including visible choices with no points spent.
Descriptions and point totals come from the game API; Exporter does not calculate
talent recommendations or effects for hypothetical ranks. During uncommitted
talent edits, it retains the last confirmed build for that same configuration,
marks pending changes and preserves that build's original capture time. If no
confirmed build is available, that unavailable section is omitted. Inactive saved
builds are excluded. Missing talent fields are omitted, and delayed spell text can
appear in a later export.

Spellbook keeps every learned rank instead of replacing lower ranks with the
highest one. It reports the highest observed numeric rank among entries with the
same localized name when that comparison is reliable; uncertain comparisons are
omitted. Descriptions and tooltips preserve the game's damage/healing
text; Exporter does not invent a single damage/healing number from that text.
Missing costs remain unknown, an explicitly empty cost list means no listed
costs, and inapplicable passive-spell fields are omitted. Pet spells,
unlearned or off-spec entries, action bars, current cooldown timers and charges
are excluded. Spellbook shares the data-loading budget described below with
Equipment, Talents and Items. The full set of learned ranks must fit the existing export size limits;
an oversized capture reports an error and retains the last snapshot rather than
silently dropping ranks or descriptions.

Quest Log rereads active quests and the completed-ID list on each export. Narrative
story descriptions are excluded; titles and objective summaries are retained. Active
quest details and completed history are independent subsections, so one can remain
useful when the other cannot be read and is omitted. Available rewards include
XP, money, guaranteed and choice items, currencies, spells and major-faction
reputation reported by the client; other reputation rewards are not inferred.
Completed history contains
IDs and available titles, not past objective/reward details or invented completion
dates. Missing API data is omitted; it is not treated as an empty log or
history. Only titles are cached, and they are attached to quests still present in
the current active log or completed history. Title loading is progressive, with
bounded requests and active quests prioritized. A large history or additional
loaded titles can exceed the export size limit; the addon then reports an error
and retains the last successful snapshot and its original capture time.

Items reads the current contents of carried bags on every export. Copies of an
item remain separate by bag and slot, including different stacks or enhancements.
This includes the backpack, four equipped bags, and the reagent bag/keyring when
the client explicitly supports those carried containers.
Worn equipment, bank contents and mail are excluded from this category. Missing
or restricted slot data is unavailable, not empty; unreadable fields and totals are
omitted. Bag/slot and total completeness indicators describe what was
read successfully. Item movement or
stack changes during a scan trigger one retry, then an explicit incomplete result
if the contents remain unstable. Item-data loading shares its budget with
Equipment, Talents and Spellbook. A large combined snapshot reports an export-size error and retains
the last successful snapshot and its timestamp instead of silently dropping items.

Professions reads the twelve supported root skill IDs on each enabled capture.
It prefers direct ID queries and uses a read-only skill-list fallback bounded to
512 rows when needed. It never expands/collapses skill headers, opens profession
windows or requests metadata loads. `scanComplete` describes membership coverage;
missing names or bonus fields do not erase readable ranks. An empty `entries`
list confirms no supported professions only when `scanComplete` is true.
Incomplete enumeration stays explicitly incomplete; wholly unreadable data is
omitted. Trained `rank`/`maxRank` remain separate from `modifier`/`tempPoints`, so
equipment or temporary bonuses do not imply permanent skill progress. Professions
uses the existing record-table encoding and inherited capture timestamp.

Equipment, Talents, Spellbook and Items share at most **eight explicit item/spell
loading requests per capture**. Duplicate IDs of the same kind share a request
and retry history, including items moved between equipment and bags. Deferred
IDs progress before retries; each ID allows at most three attempts per session,
at least 30 seconds apart. Quest title loading retains its separate limit of
sixteen requests. These limits cover explicit loading calls, not implicit work
performed by the game's metadata getters or tooltips.

## Where the data goes

The primary output is a tagged JSON snapshot inside this WoW-owned file:

```text
<WoW folder>\WTF\Account\<account>\<realm folder>\<character folder>\cooldownmanager.txt
```

That filename belongs to WoW's cooldown manager; Exporter cannot rename or redirect
it. The file includes unrelated game settings and is encoded. It must be decoded,
not treated as plain JSON or overwritten by a consumer. The last snapshot JSON
string is also saved as `ExporterSnapshotJSON` in the character's
`SavedVariables\Exporter.lua` on logout/reload. Account-wide options are in the
account's separate `SavedVariables\Exporter.lua` file.

Any separate process can consume the exported data. See [EXPORT_FORMAT.md](../EXPORT_FORMAT.md)
for the envelope, checksum, JSON schema, inherited timestamps, omitted unavailable data,
and consumer rules. Exporter contains no background importer or MCP tools.

## Capture timing

Exports wait during combat and toolbar editing, with at least 30 seconds between
attempts. The interval schedules export attempts, **not guaranteed disk arrival**.
WoW controls when its cache reaches disk. An ad-hoc request may therefore queue.
There are no automatic UI reloads. A periodic capture occurs shortly after login;
ad-hoc mode waits for a user request. Logout saves the last successful snapshot
with its original timestamps and cleans up the cache marker; it does not scan or
request more metadata. If an export fails, automatic attempts pause for the
session. Review the status and use **Export now** or change settings to retry.

## Controls and status details

All nine categories and periodic exporting are enabled by default. The default
interval is 1 minute, and the available range is 1 to 60 minutes. Settings
schema 5 migrates the schema-3 60-minute default and schema-4 5-minute default to
1 minute once, preserving other custom intervals and category selections.
Later interval choices are remembered normally. Turning off
**Periodic exports** leaves manual **Export now** requests available. Settings
changes queue one export without restarting periodic mode. Settings are saved
across game sessions.

The **Encoded export** and **Uncompressed JSON** readings show bytes and KiB.
The encoded size includes the cache envelope and is measured in memory. Neither
size reading confirms that the result has reached disk.

The **Character export source** path hint is generated locally during scripted
installation. It is not part of the public source or exported character data.

WoW controls delivery through its cooldown-layout cache. If the game disconnects
during an export, disable AI Exporter in the AddOns menu before logging back in.
