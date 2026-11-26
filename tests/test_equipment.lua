local file=assert(arg[1])
local now=100
function GetTime() return now end
local secret={}
function issecretvalue(value) return value==secret end
local inventory,ready,requests,links,statsByLink={},{},{},{},{}
local defaultStats={ITEM_MOD_INTELLECT_SHORT=4,ITEM_MOD_STAMINA_SHORT=0,RESISTANCE6_NAME=7}
local idFailure,linkFailure,statsFailure,tooltipFailure
local function getID(_,slot)
    assert(slot>=1 and slot<=19,'Bags and bank must not be scanned')
    if slot==idFailure then error('Slot unavailable') end
    return inventory[slot]
end
local function getLink(_,slot)
    if slot==linkFailure then error('Link unavailable') end
    local id=inventory[slot]
    if id==secret then return secret end
    return id and (links[slot] or ('|Hitem:'..id..':42:200:0:0:0|h[Item]|h'))
end
GetInventoryItemID=getID; GetInventoryItemLink=getLink
C_Item={
    GetItemInfo=function(link)
        local id=type(link)=='string' and tonumber(link:match('item:(%d+)')) or link
        if not ready[id] then return end
        return 'Item '..id,link,2,15,10,'Armor','Cloth',1,'INVTYPE_CHEST',123,50,4,1
    end,
    GetDetailedItemLevelInfo=function()return 16 end,
    GetItemStats=function(link)
        if statsFailure then error('Stats unavailable') end
        return statsByLink[link] or defaultStats
    end,
    GetItemGem=function(_,i)if i==1 then return 'Gem','|Hitem:200:0|h[Gem]|h' end end,
    RequestLoadItemDataByID=function(id)requests[id]=(requests[id] or 0)+1 end,
}
C_TooltipInfo={GetInventoryItem=function(_,slot)
    if tooltipFailure then error('Tooltip unavailable') end
    return {lines={{leftText='|cff00ff00Equip: Bonus healing|r',rightText='Speed 2.0'},
        {leftText='12 - 24 Damage'},{leftText='Slot '..slot}}}
end}
local function fresh() dofile(file); return ExporterEquipment end
local function capture()return ExporterEquipment.Capture(1000+now)end
inventory={[1]=100,[11]=101,[12]=101,[16]=102,[17]=103,[18]=104,[19]=105}
for _,id in pairs(inventory)do ready[id]=true end
local q=fresh()
local eq=capture()
assert(eq.available and eq.status=='available' and eq.scanComplete and #eq.slots==19 and eq.equippedCount==7)
assert(eq.capturedAt==1100 and eq.scope=='equipped_items')
assert(eq.slots[2].empty and eq.slots[2].status=='empty')
assert(eq.slots[16].slotName=='Main Hand' and eq.slots[17].slotName=='Off Hand' and eq.slots[18].slotName=='Ranged')
assert(eq.slots[19].slotName=='Tabard' and eq.slots[4].slotName=='Shirt')
local staff=eq.slots[16]
assert(staff.itemID==102 and staff.name=='Item 102' and staff.itemLevel==16 and staff.baseItemLevel==15)
assert(staff.stats.ITEM_MOD_INTELLECT_SHORT==4 and staff.stats.ITEM_MOD_STAMINA_SHORT==0 and staff.stats.RESISTANCE6_NAME==7)
assert(staff.enhancements.enchantID==42 and staff.enhancements.sockets[1].itemID==200)
assert(staff.tooltipLines[1].left=='Equip: Bonus healing' and staff.tooltipLines[1].right=='Speed 2.0')
assert(staff.tooltipLines[2].left=='12 - 24 Damage')
-- Two copies of the same item can have different instance stats.
links[11]='item:101:0:0:0:0:0:0:7'; links[12]='item:101:0:0:0:0:0:0:8'
statsByLink[links[11]]={ITEM_MOD_SPIRIT_SHORT=3}; statsByLink[links[12]]={ITEM_MOD_SPIRIT_SHORT=9}
eq=capture(); assert(eq.slots[11].stats.ITEM_MOD_SPIRIT_SHORT==3 and eq.slots[12].stats.ITEM_MOD_SPIRIT_SHORT==9)
-- A valid empty stat table is different from stats that could not be read.
statsByLink[links[11]]={};eq=capture();assert(eq.slots[11].statsStatus=='available' and next(eq.slots[11].stats)==nil)
print('PASS: all worn slots, instance-specific stats, zero values, item metadata, enchants, gems and effect/weapon tooltips')

inventory[16]=999
eq=capture(); assert(eq.slots[16].name==nil and eq.slots[16].nameStatus=='pending' and requests[999]==1)
for i=1,5 do eq=capture() end
assert(requests[999]==1,'Repeated captures must not spam item load requests')
for i=1,5 do now=now+31;eq=capture()end
assert(requests[999]==3 and eq.slots[16].nameStatus=='unavailable')
ready[999]=true;eq=capture();assert(eq.slots[16].name=='Item 999')
inventory[16]=102;eq=capture();assert(eq.slots[16].name=='Item 102','A late result must not restore old gear')
inventory[16]=nil;eq=capture();assert(eq.slots[16].empty and eq.equippedCount==6)
print('PASS: uncached items, bounded loading, swaps, removals and no stale slot reuse')

idFailure=1;linkFailure=11;inventory[12]=secret
eq=capture()
assert(eq.available and eq.status=='partial' and not eq.scanComplete)
assert(eq.slots[1].status=='unavailable' and eq.slots[1].empty==nil)
assert(eq.slots[11].status=='unavailable' and eq.slots[11].empty==nil)
assert(eq.slots[12].status=='restricted' and eq.slots[12].itemID==nil)
assert(eq.slots[17].name=='Item 103','One slot failure must not hide other gear')
idFailure=nil;linkFailure=nil;inventory[12]=101
defaultStats={ITEM_MOD_INTELLECT_SHORT=secret,ITEM_MOD_SPIRIT_SHORT=0/0,ITEM_MOD_STAMINA_SHORT=math.huge,ARMOR=0}
eq=capture();local armor=eq.slots[1]
assert(armor.statsStatus=='partial' and armor.stats.ITEM_MOD_INTELLECT_SHORT==nil and armor.statStatus.ITEM_MOD_INTELLECT_SHORT=='restricted')
assert(armor.stats.ITEM_MOD_SPIRIT_SHORT==nil and armor.stats.ITEM_MOD_STAMINA_SHORT==nil and armor.stats.ARMOR==0)
statsFailure=true;tooltipFailure=true;eq=capture()
assert(eq.slots[1].name=='Item 100' and eq.slots[1].statsStatus=='unavailable' and eq.slots[1].tooltipStatus=='unavailable')
assert(eq.status=='partial')
statsFailure=false;tooltipFailure=false
inventory={};eq=capture();assert(eq.status=='available' and eq.equippedCount==0 and #eq.slots==19)
GetInventoryItemID=nil;eq=capture();assert(not eq.available and eq.status=='unsupported' and not eq.scanComplete)
GetInventoryItemID=getID;GetInventoryItemLink=nil;eq=capture();assert(eq.status=='unsupported')
GetInventoryItemLink=getLink
print('PASS: per-slot failure isolation, restricted/nonfinite stats, empty slots and missing APIs')

-- Requests are capped per capture, even when every slot needs uncached data.
inventory={};requests={};ready={};fresh()
for slot=1,19 do inventory[slot]=1000+slot end
eq=capture();local count=0;for _,n in pairs(requests)do count=count+n end
assert(count==8 and eq.equippedCount==19)
-- Legacy global item functions work when the namespace is absent.
for name,fn in pairs(C_Item)do _G[name]=fn end
C_Item=nil;inventory={[1]=100};ready[100]=true;defaultStats={ARMOR=3}
eq=capture();assert(eq.slots[1].name=='Item 100' and eq.slots[1].stats.ARMOR==3)
print('PASS: request budget and legacy item API fallback')
