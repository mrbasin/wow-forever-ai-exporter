# Source and development dependencies

- Character collectors, bounded retry handling, XP logic, quest-name handling,
  cache encoding design, installer rollback, and Lua runner were adapted from
  **MIT**-licensed source. The original copyright and license notice is retained
  in LICENSE. These files are included as source; Exporter does not load or depend
  on another project or addon.
- Lua behavior tests use **fengari-node-cli 0.1.0** with the exact transitive
  versions/integrities in package-lock.json. Fengari and fengari-node-cli: MIT;
  readline-sync: MIT; sprintf-js: BSD-3-Clause; tmp: MIT.
- The optional development decoder uses **cbor2 6.2.1**, MIT.
- Node.js and Python are development tools only and are not bundled. The addon
  runs in WoW's Lua environment with no third-party runtime libraries.

API behavior was checked against the Forever branch of the public Blizzard UI
source mirror, including [Settings](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_Settings.lua)
and [CooldownViewer](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/CooldownViewerDocumentation.lua).
Character-stat field ordering and character-panel interpretation follow the
[Forever unit API documentation](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua)
and [Forever character panel](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/PaperDollFrame.lua).
Equipment item metadata and stat reads follow the
[Forever item API documentation](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua).
Carried bag enumeration and slot reads follow the
[Forever container API documentation](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/ContainerDocumentation.lua).
Carried-container IDs, including the optional reagent bag and keyring, follow the
[Forever bag-index constants](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/BagIndexConstantsDocumentation.lua).
Readable bag-item tooltips follow the
[Forever tooltip API documentation](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/TooltipInfoDocumentation.lua).
Talent configuration, tree, rank and point reads follow the
[Forever shared traits API documentation](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/SharedTraitsDocumentation.lua).
Learned spell enumeration and spell details follow the
[Forever spellbook API documentation](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellBookDocumentation.lua)
and [Forever spell API documentation](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellDocumentation.lua).
Active quest enumeration, objectives, completed quest IDs and title loading follow
the [Forever quest-log API documentation](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/QuestLogDocumentation.lua).
Quest reward currency and spell reads follow the
[Forever quest-info API documentation](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/QuestInfoSystemDocumentation.lua).
Quest-log text reads follow the index-based usage in the
[Forever quest map frame](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/QuestMapFrame.lua).
This is an independent community project, not an official Blizzard export API.
