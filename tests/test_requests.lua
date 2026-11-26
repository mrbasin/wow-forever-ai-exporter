-- Synthetic request APIs only. No game, account or network access.
local file=assert(arg[1])
local directory=file:match("^(.*[/\\])") or ""
local now,calls,counts=100,{},{}
function GetTime()return now end
local function loader(kind)
    return function(id)
        local key=kind..":"..id
        counts[key]=(counts[key] or 0)+1
        calls[#calls+1]={kind=kind,id=id,at=now}
    end
end
local itemLoad,spellLoad=loader("item"),loader("spell")
local function fresh()
    now,calls,counts=100,{},{}
    dofile(file)
    return ExporterDataRequests
end
local r=fresh()
r.BeginCapture()
for id=1,12 do
    assert(r.Request("item",id,itemLoad)=="pending")
    r.Request("item",id,itemLoad) -- same item found in two collectors
end
assert(#calls==0,"Requests must wait until all collectors have contributed")
assert(r.EndCapture()==8 and #calls==8)
assert(r.EndCapture()==0 and #calls==8,"Ending a capture twice must not refill the budget")
for id=1,8 do assert(counts["item:"..id]==1) end
for id=9,12 do assert(counts["item:"..id]==nil and r.Status("item",id,itemLoad)=="pending") end
now=130;r.BeginCapture()
for id=1,12 do r.Request("item",id,itemLoad) end
assert(r.EndCapture()==8)
for id=9,12 do assert(counts["item:"..id]==1,"Deferred IDs must progress before early retries") end
for id=1,4 do assert(counts["item:"..id]==2) end
print("PASS: one eight-load budget, duplicate suppression, deferred status and progress before retries")

r=fresh();r.BeginCapture()
r.Request("item",7,itemLoad);r.Request("spell",7,spellLoad)
assert(r.EndCapture()==2 and counts["item:7"]==1 and counts["spell:7"]==1)
now=129;r.BeginCapture();r.Request("item",7,itemLoad);assert(r.EndCapture()==0)
now=130;r.BeginCapture();r.Request("item",7,itemLoad);assert(r.EndCapture()==1)
now=160;r.BeginCapture();r.Request("item",7,itemLoad);assert(r.EndCapture()==1)
assert(r.Status("item",7,itemLoad)=="pending")
now=190;r.BeginCapture()
assert(r.Request("item",7,itemLoad)=="unavailable" and r.EndCapture()==0)
assert(counts["item:7"]==3,"Moving an ID between callers must not restart its retry allowance")
print("PASS: separate item/spell identity, 30-second retry spacing and session-wide three-attempt ceiling")

r=fresh();r.OnEvent("GET_ITEM_INFO_RECEIVED",99,false)
r.BeginCapture();r.Request("item",99,itemLoad);assert(r.EndCapture()==1)
r.OnEvent("ITEM_DATA_LOAD_RESULT",99,false)
now=140;r.BeginCapture();assert(r.Request("item",99,itemLoad)=="unavailable");assert(r.EndCapture()==0)
r.BeginCapture();r.Request("spell",99,spellLoad);assert(r.EndCapture()==1)
r.OnEvent("SPELL_DATA_LOAD_RESULT",99,false)
now=180;r.BeginCapture();assert(r.Request("spell",99,spellLoad)=="unavailable");assert(r.EndCapture()==0)
r.BeginCapture();r.Request("item",100,function()error("Request API unavailable")end)
assert(r.EndCapture()==1 and r.Status("item",100,itemLoad)=="unavailable")
-- A failed callback for a deferred ID cannot consume an attempt or fail it.
r.BeginCapture();for id=200,208 do r.Request("item",id,itemLoad) end;assert(r.EndCapture()==8)
r.OnEvent("GET_ITEM_INFO_RECEIVED",208,false)
assert(r.Status("item",208,itemLoad)=="pending")
now=220;r.BeginCapture();r.Request("item",208,itemLoad);assert(r.EndCapture()==1)
assert(counts["item:208"]==1)
print("PASS: item/spell failure callbacks, request errors and ignored callbacks for never-sent IDs")

r=fresh();r.BeginCapture();r.Request("item",1,itemLoad)
r.BeginCapture();r.Request("spell",2,spellLoad)
assert(r.EndCapture()==1 and counts["item:1"]==nil and counts["spell:2"]==1)
assert(r.Request("item",3,itemLoad)=="pending" and r.EndCapture()==0)
for _,invalid in ipairs({0,-1,0/0,math.huge,1.5,"1"}) do
    assert(r.Request("item",invalid,itemLoad)=="unavailable")
end
assert(r.Request("quest",1,itemLoad)=="unavailable" and r.Request("item",1,nil)=="unavailable")
local realClock=GetTime
for _,clock in ipairs({function()return nil end,function()return 0/0 end,function()error("No clock")end}) do
    r.BeginCapture();GetTime=clock
    assert(r.Request("item",1,itemLoad)=="unavailable" and r.EndCapture()==0)
    GetTime=realClock
end
r.BeginCapture();r.Request("item",1,itemLoad);GetTime=nil
assert(r.EndCapture()==0);GetTime=realClock
assert(counts["item:1"]==nil)
print("PASS: abandoned queues, inactive captures, invalid requests and missing/broken clocks fail closed")

-- Load the real collectors together. All metadata is deliberately uncached.
r=fresh()
local equipmentIDs,bagIDs,talentIDs,spellIDs={},{},{},{}
for i=1,8 do equipmentIDs[i]=100+i;talentIDs[i]=200+i;bagIDs[i]=300+i end
bagIDs[9]=101 -- same item ID in Equipment and Items
for i=1,16 do spellIDs[i]=200+i end -- first eight also occur in Talents
function GetInventoryItemID(_,slot)return equipmentIDs[slot]end
local function link(id)return "item:"..id..":0:0:0:0:0:0:0"end
function GetInventoryItemLink(_,slot)local id=equipmentIDs[slot];return id and link(id)end
C_Item={GetItemInfo=function()end,GetItemStats=function()return {}end,
    RequestLoadItemDataByID=itemLoad,IsEquippableItem=function()return true end}
C_Spell={GetSpellInfo=function()end,GetSpellDescription=function()end,
    IsSpellDataCached=function()return false end,RequestLoadSpellData=spellLoad}
C_Container={GetContainerNumSlots=function(bag)return bag==0 and #bagIDs or 0 end,
    GetContainerItemInfo=function(bag,slot)
        local id=bag==0 and bagIDs[slot]
        if id then return {itemID=id,hyperlink=link(id),stackCount=1,isLocked=false,isBound=false} end
    end}
C_ClassTalents={GetActiveConfigID=function()return 1 end}
C_Traits={ConfigHasStagedChanges=function()return false end,
    GetConfigInfo=function()return {name="Build",treeIDs={1}}end,
    GetTreeNodes=function()return talentIDs end,
    GetNodeInfo=function(_,id)return {isVisible=true,currentRank=0,activeRank=0,maxRanks=1,totalMaxRanks=1,
        entryIDs={id},groupIDs={},conditionIDs={},visibleEdges={}}end,
    GetEntryInfo=function(_,id)return {definitionID=id,conditionIDs={}}end,
    GetDefinitionInfo=function(id)return {spellID=id}end}
Enum={SpellBookSpellBank={Player=0},SpellBookItemType={Spell=1,Flyout=4}}
C_SpellBook={GetNumSpellBookSkillLines=function()return 1 end,
    GetSpellBookSkillLineInfo=function()return {name="Class",itemIndexOffset=0,numSpellBookItems=#spellIDs}end,
    GetSpellBookItemInfo=function(slot)return {spellID=spellIDs[slot],actionID=spellIDs[slot],itemType=1,isOffSpec=false}end,
    IsSpellKnown=function()return true end}
for _,name in ipairs({"Equipment","Talents","Spellbook","Items"})do dofile(directory..name..".lua")end
local function allCollectors()
    local before=#calls
    r.BeginCapture()
    local eq=ExporterEquipment.Capture(now)
    local talents=ExporterTalents.Capture(now)
    local spells=ExporterSpellbook.Capture(now)
    local items=ExporterItems.Capture(now)
    assert(eq.equippedCount==#equipmentIDs and #talents.trees[1].nodes==#talentIDs)
    assert(spells.spellCount==#spellIDs and items.occupiedSlots==#bagIDs)
    -- Repeating a collector within one snapshot must share the same queue.
    ExporterEquipment.Capture(now);ExporterItems.Capture(now)
    assert(#calls==before,"Collectors must route every explicit load through the broker")
    assert(r.EndCapture()==8 and #calls-before==8)
end
for pass=1,4 do allCollectors();now=now+30 end
assert(#calls==32)
for key,count in pairs(counts)do assert(count==1,"Every unique ID must get one turn before a second attempt: "..key)end
assert(counts["item:101"]==1 and counts["item:308"]==1 and counts["spell:201"]==1 and counts["spell:216"]==1)
-- Move a requested item out of Equipment into Items, with captures in between.
equipmentIDs={};talentIDs={};spellIDs={};bagIDs={101}
for pass=1,2 do
    r.BeginCapture();ExporterEquipment.Capture(now);ExporterItems.Capture(now)
    assert(r.EndCapture()==1);now=now+30
end
r.BeginCapture();ExporterItems.Capture(now);assert(r.EndCapture()==0)
assert(counts["item:101"]==3 and r.Status("item",101,itemLoad)=="unavailable")
print("PASS: all four real collectors share eight loads, duplicates and recaptures dedupe, moved items retain retry history")
