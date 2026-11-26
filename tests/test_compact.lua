-- Export-only schema projection: synthetic values, never a game cache write.
function CreateFrame() return {RegisterEvent=function()end,SetScript=function()end} end
C_Timer={NewTicker=function()end};SlashCmdList={}
dofile(assert(arg[1]))
local E=Exporter
local raw={schemaVersion=2,sourceAddon='Exporter',addonVersion=E.version,capturedAt=100,
    character={guid='Player-fictional'},availability={basic=true},export={sections={basic=true}},
    basic={available=true,status='available',capturedAt=100,name='Example',level=0,className='Priest',classID=5,classToken='PRIEST',
        raceName='Night Elf',faction='Alliance',fieldStatus={name='available',level='available',raceName='available',faction='available'}},
    location={available=false,status='unsupported',reason='No map'},
    questLog={available=true,status='partial',capturedAt=100,
        active={available=false,status='unavailable',capturedAt=100,entries={},questCount=0,scanComplete=false},
        completedHistory={available=true,status='available',capturedAt=100,questIDs={11,12},titlesByQuestID={},scanComplete=true,
            pendingTitleIDs={11},unavailableTitleIDs={12}}},
    flags={false,0,true},emptyObjects={}}
local result=E.CompactSnapshot(raw)
assert(result.schemaVersion==5 and result.capturedAt==100 and result.character.guid=='Player-fictional')
assert(result.availability==nil and result.export==nil and result.location==nil)
assert(result.basic.name=='Example' and result.basic.level==0 and result.basic.capturedAt==nil)
assert(result.basic.className=='Priest' and result.basic.classID==nil and result.basic.classToken==nil)
assert(result.basic.raceName=='Night Elf' and result.basic.faction=='Alliance')
local partialBasic=E.CompactSnapshot({capturedAt=100,basic={available=true,name='Example',raceName='Unknown',faction='Unknown',
    fieldStatus={name='available',raceName='unavailable',faction='restricted'}}}).basic
assert(partialBasic.name=='Example' and partialBasic.raceName==nil and partialBasic.faction==nil)
assert(result.basic.available==nil and result.basic.status==nil and result.basic.fieldStatus==nil)
assert(result.questLog.active==nil and result.questLog.completedHistory.scanComplete)
assert(result.questLog.completedHistory.questIDs[1]==11 and result.questLog.completedHistory.questIDs[2]==12)
assert(next(result.questLog.completedHistory.titlesByQuestID)==nil)
assert(result.questLog.completedHistory.pendingTitleIDs==nil and result.questLog.completedHistory.unavailableTitleIDs==nil)
assert(result.flags[1]==false and result.flags[2]==0 and result.flags[3]==true)
assert(raw.schemaVersion==2 and raw.basic.available and raw.basic.capturedAt==100 and raw.location.status=='unsupported',
    'Projection must not mutate collector diagnostics or settings')
assert(E.JSON(result):find('"questIDs":[11,12]',1,true) and E.JSON(result):find('"titlesByQuestID":{}',1,true))
assert(E.JSON({text='"\\\n\r\t\b\f'..string.char(1)..'é'})=='{"text":"\\"\\\\\\n\\r\\t\\b\\f\\u0001é"}')
print('PASS: metadata omission, failed sections, known zero/false/empty values, original state and short JSON escaping')

local contextRaw={capturedAt=100,basic={available=true,capturedAt=100,name='Example',moneyCopper=0,
    xp={available=true,status='partial',current=0,levelTotal=0,rested=99,disabled=false,
        fieldStatus={current='available',levelTotal='available',rested='restricted',disabled='available'}}},
    professions={available=true,capturedAt=100,scanComplete=false,entries={{skillLineID=356,name='Fishing',
        category='secondary',rank=0,maxRank=75,modifier=99,tempPoints=-5,
        fieldStatus={rank='available',maxRank='available',modifier='restricted',tempPoints='available'}}}}}
local context=E.CompactSnapshot(contextRaw)
assert(context.basic.moneyCopper==0 and context.basic.xp.current==0 and context.basic.xp.levelTotal==0
    and context.basic.xp.disabled==false and context.basic.xp.rested==nil)
assert(context.basic.xp.status==nil and context.basic.xp.fieldStatus==nil)
assert(context.professions.scanComplete==false and context.professions.capturedAt==nil)
assert(context.professions.entries[1].rank==0 and context.professions.entries[1].modifier==nil
    and context.professions.entries[1].tempPoints==-5)
assert(contextRaw.basic.xp.rested==99 and contextRaw.professions.entries[1].modifier==99)
for _,available in ipairs({false,true}) do
    local result=E.CompactSnapshot({capturedAt=100,professions={available=available,scanComplete=available,entries={}}})
    if available then assert(E.JSON(result):find('"professions":{"entries":[],"scanComplete":true}',1,true))
    else assert(result.professions==nil) end
end
assert(E.CompactSnapshot({capturedAt=100,professions={available=true,scanComplete=false,entries={}}}).professions.scanComplete==false)
assert(E.CompactSnapshot({capturedAt=100,basic={available=true,name='Example',
    xp={available=false,status='unsupported',fieldStatus={current='unsupported'}}}}).basic.xp==nil)
print('PASS: XP/money/profession known zero/false, omitted unknowns, empty versus incomplete scans and unchanged raw data')

local input={capturedAt=100,equipment={available=true,scanComplete=false,slots={
    {slotID=1,empty=true,status='empty'},
    {slotID=2,status='unavailable'},
    {slotID=3,empty=false,itemID=33,status='partial',stats={ZERO=0,BAD=0},statStatus={ZERO='available',BAD='restricted'},
        statsStatus='partial',tooltipLines={},tooltipStatus='unavailable',
        enhancements={sockets={},emptySockets={},status='unavailable'}},
    {slotID=4,empty=false,itemID=44,classID=4,stats={},statsStatus='available',tooltipLines={},tooltipStatus='available',
        enhancements={enchantID=0,sockets={},emptySockets={},status='available'}},
    {slotID=5,tooltipLines={{left='Known line'}},tooltipStatus='partial',statsStatus='unavailable',
        enhancements={sockets={{index=1,itemID=77,nameStatus='pending'}},emptySockets={},status='partial'}},
}}}
local gear=E.CompactSnapshot(input).equipment
assert(gear.scanComplete==false and gear.bySlot.head==false and next(gear.bySlot.neck)==nil)
assert(gear.bySlot.shoulder.itemID==33 and gear.bySlot.shoulder.empty==nil)
assert(gear.bySlot.shoulder.stats.ZERO==0 and gear.bySlot.shoulder.stats.BAD==nil and gear.bySlot.shoulder.tooltipLines==nil)
assert(gear.bySlot.shoulder.enhancements==nil and gear.bySlot.shoulder.incompleteFields[1]=='stats')
assert(next(gear.bySlot.shirt.stats)==nil and next(gear.bySlot.shirt.tooltipLines)==nil)
assert(gear.bySlot.shirt.classID==4,'Item classification must not be confused with the character class')
assert(gear.bySlot.shirt.enhancements.enchantID==0 and next(gear.bySlot.shirt.enhancements.sockets)==nil)
assert(gear.bySlot.chest.tooltipLines[1]=='Known line' and gear.bySlot.chest.incompleteFields[1]=='tooltipLines')
assert(gear.bySlot.chest.enhancements.sockets[1].itemID==77 and gear.bySlot.chest.enhancements.emptySockets==nil)
print('PASS: unknown slots, per-stat filtering, empty versus failed collections, enhancements and partial collection coverage')

local names={'head','neck','shoulder','shirt','chest','waist','legs','feet','wrist','hands',
    'finger1','finger2','trinket1','trinket2','back','mainHand','offHand','ranged','tabard'}
local equipmentSource={capturedAt=100,equipment={available=true,capturedAt=90,scope='equipped_items',
    scanComplete=true,equippedCount=1,slots={}},items={entries={{stats={ITEM_MOD_INTELLECT_SHORT=9},
    tooltipLines={{left='Bag text'}}}}}}
for slot=1,19 do equipmentSource.equipment.slots[slot]={slotID=slot,slotName='Internal label',empty=true} end
equipmentSource.equipment.slots[16]={slotID=16,slotName='Main Hand',empty=false,itemID=100,
    link='|cffaabbcc|Hitem:100:7:8:0:0:0:-12:345|h[Example]|h|r',
    quality=0,baseItemLevel=20,itemLevel=22,requiredLevel=0,classID=2,subClassID=10,
    stats={ITEM_MOD_INTELLECT_SHORT=9,ITEM_MOD_SPELL_POWER_SHORT=1.234567,UNKNOWN_TOKEN=-2,ZERO=0},
    enhancements={enchantID=7,sockets={{index=1,itemID=8,name='Gem',link='item:8'}},emptySockets={EMPTY_SOCKET_RED=1}},
    tooltipLines={{left='Équip: exact effect\nSecond line'},{left='Damage',right='Speed'},
        {right='Right only'},{left='Keep metadata',extra='value'}}}
local beforeEquipment=E.JSON(equipmentSource)
local equipmentResult=E.CompactSnapshot(equipmentSource)
local compactGear=equipmentResult.equipment
assert(compactGear.capturedAt==90 and compactGear.scanComplete and compactGear.scope==nil and compactGear.equippedCount==nil)
assert(compactGear.slots==nil and compactGear.bySlot.mainHand.empty==nil)
for slot,key in ipairs(names) do
    if slot~=16 then assert(compactGear.bySlot[key]==false,'Wrong named equipment slot: '..key) end
end
local weapon=compactGear.bySlot.mainHand
assert(weapon.slotID==nil and weapon.slotName==nil and weapon.itemID==100)
assert(weapon.link==equipmentSource.equipment.slots[16].link and weapon.quality==0 and weapon.requiredLevel==0)
assert(weapon.baseItemLevel==20 and weapon.itemLevel==22 and weapon.classID==2 and weapon.subClassID==10)
assert(weapon.stats.intellect==9 and weapon.stats.spellPower==1.234567 and weapon.stats.UNKNOWN_TOKEN==-2 and weapon.stats.ZERO==0)
assert(weapon.enhancements.enchantID==7 and weapon.enhancements.sockets[1].link=='item:8'
    and weapon.enhancements.emptySockets.EMPTY_SOCKET_RED==1)
assert(weapon.tooltipLines[1]=='Équip: exact effect\nSecond line' and weapon.tooltipLines[2].right=='Speed'
    and weapon.tooltipLines[3].right=='Right only' and weapon.tooltipLines[4].extra=='value')
assert(E.JSON(equipmentSource)==beforeEquipment,'Projection must not mutate collector state')
assert(equipmentResult.items.entries[1].stats.intellect==9
    and equipmentResult.items.entries[1].tooltipLines[1]=='Bag text','Bag items share the same readable stat/tooltip rules')
local collision=E.CompactSnapshot({equipment={slots={{slotID=1,itemID=1,empty=false,
    stats={ITEM_MOD_INTELLECT_SHORT=5,intellect=99}}}}}).equipment.bySlot.head.stats
assert(collision.ITEM_MOD_INTELLECT_SHORT==5 and collision.intellect==99,'Unknown tokens must not collide with aliases')
local emptyGear=E.CompactSnapshot({equipment={scanComplete=false,slots={}}}).equipment
assert(E.JSON(emptyGear):find('"bySlot":{}',1,true),'Empty named-slot maps must remain objects')
assert(E.CompactSnapshot({capturedAt=100,equipment={available=false,slots={}}}).equipment==nil)
assert(not pcall(E.CompactSnapshot,{equipment={slots={{slotID=20,itemID=1}}}}),'Unexpected slots must not disappear silently')
assert(not pcall(E.CompactSnapshot,{equipment={slots={{slotID=1,empty=true},{slotID=1,itemID=1}}}}),
    'Duplicate slots must not overwrite observations')
print('PASS: schema-5 named slots, exact item details, readable stats, tooltip sides, aliases, timestamps and category isolation')

local tableSource={capturedAt=100,basic={name='Example',level=29,raceName='Night Elf',faction='Alliance'},
    location={zone='Example',x=0.123456789},spellbook={scanComplete=false,entries={}}}
for i=1,4 do
    tableSource.spellbook.entries[i]={spellID=i,name='Same name',learned=true,isPassive=false,castTimeMs=0,
        powerCosts={},tooltipLines={{left='Exact text'}},stats={},capturedAt=100}
end
tableSource.spellbook.entries[2].castTimeMs=nil
tableSource.spellbook.entries[3].powerCosts=nil
local sourceJSON=E.JSON(tableSource)
local tabular=E.CompactSnapshot(tableSource)
local packed=tabular.spellbook.entries
assert(packed.columns and #packed.rows==4 and tabular.spellbook.scanComplete==false)
local column={}
for i,name in ipairs(packed.columns) do
    column[name]=i
    if i>1 then assert(packed.columns[i-1]<name,'Columns must be deterministic') end
end
assert(packed.rows[1][column.spellID]==1 and packed.rows[4][column.spellID]==4,'Row order must be preserved')
assert(packed.rows[1][column.castTimeMs]==0 and packed.rows[1][column.isPassive]==false)
assert(E.JSON(packed.rows[2][column.castTimeMs])=='null','Only missing fields use null cells')
assert(E.JSON(packed.rows[1][column.powerCosts])=='[]','Known empty arrays retain their type inside rows')
assert(E.JSON(packed.rows[1][column.stats])=='{}','Known empty objects retain their type inside rows')
assert(E.JSON(packed.rows[3][column.powerCosts])=='null','Unknown costs must not become free')
assert(packed.rows[1][column.tooltipLines][1]=='Exact text' and column.capturedAt==nil)
assert(tabular.basic.raceName=='Night Elf' and tabular.basic.faction=='Alliance'
    and tabular.location.x==0.123456789,'Small category values remain unchanged')
assert(E.JSON(tableSource)==sourceJSON,'Record packing must not mutate raw observations')
local sparse=E.CompactSnapshot({spellbook={entries={{first=1},{second=2},{third=3},{fourth=4}}}}).spellbook.entries
assert(sparse.columns==nil and sparse[1].first==1,'Sparse lists stay readable without padding')
local small=E.CompactSnapshot({spellbook={entries={{spellID=1,name='A'},{spellID=2,name='B'}}}}).spellbook.entries
assert(small.columns==nil and small[2].spellID==2,'Small lists stay as record arrays')
local nested=E.CompactSnapshot({talents={trees={{nodes={}}}}})
assert(E.JSON(nested):find('"nodes":[]',1,true))
print('PASS: dense record tables, deterministic columns, exact row order, false/zero/null and nested empty collection types')

local spells=E.CompactSnapshot({capturedAt=100,spellbook={available=true,capturedAt=100,entries={
    {spellID=1,powerCosts={},powerCostsStatus='no_cost',rankText='Apprentice',rankStatus='not_numeric',
        minRange=0,rangeStatus='partial',fieldStatus={minRange='available',maxRange='unavailable'},
        highestLearnedRank=2,isHighestLearnedRank=true,highestLearnedRankStatus='partial'},
    {spellID=2,powerCosts={},powerCostsStatus='unavailable',castTimeMs=0,castTimeStatus='available'},
}}}).spellbook.entries
assert(next(spells[1].powerCosts)==nil and spells[1].rankText=='Apprentice' and spells[1].rank==nil)
assert(spells[1].minRange==0 and spells[1].maxRange==nil and spells[1].highestLearnedRank==nil and spells[1].isHighestLearnedRank==nil)
assert(spells[2].powerCosts==nil and spells[2].castTimeMs==0)
print('PASS: free versus unknown costs, nonnumeric ranks, readable range bounds and uncertain highest-rank omission')

local talents={available=true,capturedAt=90,pendingChanges=true,currencies={},
    selectedTalents={{entryID=5,rank=1,status='pending'}},trees={{id=1,currencyStatus='unavailable',currencies={},nodes={
        {id=1,edgesStatus='unavailable',edges={},prerequisites={}},
        {id=2,edgesStatus='available',edges={},prerequisites={{sourceNode=1}}},
    }}}}
local build=E.CompactSnapshot({capturedAt=100,talents=talents}).talents
assert(build.capturedAt==90 and build.pendingChanges and build.selectedTalents[1].entryID==5 and build.selectedTalents[1].rank==1)
assert(build.currencies==nil and build.trees[1].currencies==nil)
assert(build.trees[1].nodes[1].edges==nil and build.trees[1].nodes[1].prerequisites==nil)
assert(build.trees[1].nodes[2].prerequisites[1].sourceNode==1 and build.trees[1].nodes[2].incompleteFields[1]=='prerequisites')
print('PASS: inherited capture times, pending confirmed talent values and coverage of derived prerequisites/currencies')

local statsSource={capturedAt=100,characterStats={available=true,capturedAt=90,
    general={health={maximum=0},mana={maximum=2029},movementSpeed={current=0,run=7,flight=14,swim=4.72222185,
        runPercent=100,currentPercent=0,normalRunSpeed=7,unit='yards_per_second'}},
    primaryAttributes={strength={current=20,effective=29,positiveBonus=3,negativeBonus=0},
        agility={current=12,positiveBonus=2},stamina={effective=0},intellect={effective=20,fieldStatus={effective='restricted'}}},
    weapons={mainHand={minimumDamage=46.528572,maximumDamage=68.528572,attackSpeedSeconds=2.261,
            damagePerSecond=25.443860,positiveBonus=4,negativeBonus=0,damageMultiplier=1},
        ranged={status='not_applicable'},attackPower={melee={base=10,effective=15,positiveBonus=5},ranged={base=20}}},
    modifiers={criticalStrike={melee={value=3.761},ranged={value=0},spell={holy={value=5.5476},shadow={value=6.1234}}},
        haste={melee={value=-1.234},ranged={value=14.999992},spell={value=0.0001}},
        spellDamage={holy={value=93},shadow={value=120}},spellHealing={value=161}},
    defense={armor={base=100,effective=352,armor=300,bonus=252},defense={base=140,effective=148,modifier=8},dodge={value=4.520999}},
    resistances={arcane={base=1,real=2,effective=7,bonus=6},fire={effective=0},shadow={base=10,real=12}},
},location={x=0.123456789,y=0.5},spellbook={entries={{spellID=123,castTimeMs=1.23456789}}}}
local statsResult=E.CompactSnapshot(statsSource)
local stats=statsResult.characterStats
assert(statsResult.schemaVersion==5 and stats.capturedAt==90 and stats.maxHealth==0 and stats.maxMana==2029)
assert(stats.general==nil and stats.primaryAttributes==nil and stats.modifiers==nil)
assert(stats.attributes.strength==29 and stats.attributes.stamina==0 and stats.attributes.agility==nil and stats.attributes.intellect==nil,
    'Never replace an unavailable effective stat with its base/current value')
assert(stats.movementSpeedYardsPerSecond.current==0 and stats.movementSpeedYardsPerSecond.run==7
    and stats.movementSpeedYardsPerSecond.swim==4.72 and stats.movementSpeedYardsPerSecond.runPercent==nil)
assert(stats.weapons.mainHand.minimumDamage==46.53 and stats.weapons.mainHand.maximumDamage==68.53
    and stats.weapons.mainHand.speedSeconds==2.26 and stats.weapons.mainHand.estimatedDps==25.44)
assert(stats.weapons.mainHand.positiveBonus==nil and stats.weapons.mainHand.damageMultiplier==nil and stats.weapons.ranged==nil)
assert(stats.weapons.attackPower.melee==15 and stats.weapons.attackPower.ranged==nil)
assert(stats.critPercent.melee==3.76 and stats.critPercent.ranged==0
    and stats.critPercent.spell.holy==5.55 and stats.critPercent.spell.shadow==6.12)
assert(stats.hastePercent.melee==-1.23 and stats.hastePercent.ranged==15 and stats.hastePercent.spell==0.0001)
assert(stats.spellDamageBonus.holy==93 and stats.spellDamageBonus.shadow==120 and stats.spellHealingBonus==161)
assert(stats.defense.armor==352 and stats.defense.skill==148 and stats.defense.dodgePercent==4.52)
assert(stats.resistances.arcane==7 and stats.resistances.fire==0 and stats.resistances.shadow==nil)
assert(statsSource.characterStats.weapons.mainHand.minimumDamage==46.528572
    and statsSource.characterStats.primaryAttributes.strength.current==20,'Collector values must remain unchanged')
assert(statsResult.location.x==0.123456789 and statsResult.spellbook.entries[1].castTimeMs==1.23456789,
    'Rounding must be scoped to Character Stats')
assert(E.CompactSnapshot({capturedAt=100,characterStats={available=false,capturedAt=90}}).characterStats==nil)
assert(E.CompactSnapshot({capturedAt=100,characterStats={available=true,capturedAt=100,
    primaryAttributes={strength={current=25}},modifiers={haste={melee={value=0/0}}}}}).characterStats==nil,
    'No effective observations means no fabricated empty stats summary')
print('PASS: schema-4 effective stat summary, units, school differences, rounding, missing values and category isolation')
