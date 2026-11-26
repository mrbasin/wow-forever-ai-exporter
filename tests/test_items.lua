-- Synthetic carried bags only. No game, account or saved-variable data.
local file=assert(arg[1])
local now=100
local secret={}
function GetTime()return now end
function GetServerTime()return 1000+now end
function issecretvalue(value)return value==secret end
local state,requests,requestTimes
local function copy(value)
    if type(value)~='table' or value==secret then return value end
    local result={};for key,child in pairs(value)do result[key]=copy(child)end;return result
end
local function link(id,enchant,gem,suffix)
    return '|Hitem:'..id..':'..(enchant or 0)..':'..(gem or 0)..':0:0:0:0:'..(suffix or 0)..'|h[Item '..id..']|h'
end
local function item(id,count,bound,enchant,gem,suffix)
    return {itemID=id,stackCount=count,isBound=bound,isLocked=false,quality=2,iconFileID=123,
        isReadable=false,hasLoot=false,isFiltered=false,hasNoValue=false,
        hyperlink=link(id,enchant,gem,suffix)}
end
local function find(out,bag,slot)
    for _,entry in ipairs(out.entries)do if entry.bagID==bag and entry.slotID==slot then return entry end end
    error('Missing bag/slot '..bag..'/'..slot)
end
local function bag(out,id)
    for _,entry in ipairs(out.bags)do if entry.bagID==id then return entry end end
    error('Missing bag '..id)
end
local function requestCount()
    local total=0;for _,count in pairs(requests)do total=total+count end;return total
end
local function fresh()dofile(file);return ExporterItems end
local function capture()
    local result=ExporterItems.Capture(1000+now)
    assert(state.mutations==0,'Items collection must not use, move, equip or split items')
    assert(state.forbiddenReads==0,'Items collection must not inspect banks or worn equipment')
    return result
end
local function reset()
    now=100;requests={};requestTimes={}
    state={sizes={[0]=5,[1]=3,[2]=0,[3]=0,[4]=0,[5]=1},contents={},ready={},mutations=0,
        forbiddenReads=0,bagReads={},slotReads={},infoReads=0,levelReads={},stats={},metadata={},allowed={[0]=true,[1]=true,[2]=true,[3]=true,[4]=true,[5]=true}}
    state.contents={
        [0]={[1]=item(100,1,true,42,500,7),[2]=item(200,20,false),[3]=item(300,3,true),[4]=item(400,5,false)},
        [1]={[1]=item(100,1,true,43,0,8),[2]=item(200,2,false)},[5]={[1]=item(600,7,false)}}
    state.contents[1][2].isLocked=true
    for _,id in ipairs({100,200,300,400,500,600})do state.ready[id]=true end
    state.stats[state.contents[0][1].hyperlink]={ITEM_MOD_INTELLECT_SHORT=5,ITEM_MOD_STAMINA_SHORT=0,EMPTY_SOCKET_RED=0}
    state.stats[state.contents[1][1].hyperlink]={ITEM_MOD_SPIRIT_SHORT=3}
    Enum={BagIndex={ReagentBag=5}}
    local function allowed(id)
        if not state.allowed[id]then state.forbiddenReads=state.forbiddenReads+1;error('Out-of-scope container '..tostring(id))end
    end
    C_Container={
        GetContainerNumSlots=function(id)
            allowed(id);state.bagReads[id]=(state.bagReads[id]or 0)+1
            if state.sizeHook then state.sizeHook(id)end
            if state.sizeFailure==id then error('Container unavailable')end
            return state.sizes[id]
        end,
        GetBagName=function(id)allowed(id);return 'Bag '..id end,
        GetContainerNumFreeSlots=function(id)
            allowed(id);local free=0
            for slot=1,state.sizes[id]or 0 do if not(state.contents[id]and state.contents[id][slot])then free=free+1 end end
            return free,0
        end,
        GetContainerItemInfo=function(id,slot)
            allowed(id);local key=id..'/'..slot;state.slotReads[key]=(state.slotReads[key]or 0)+1
            if state.slotHook then state.slotHook(id,slot)end
            if state.slotFailure==key then error('Slot unavailable')end
            return copy(state.contents[id]and state.contents[id][slot])
        end,
    }
    C_Item={
        GetItemInfo=function(value)
            local id=type(value)=='string'and tonumber(value:match('item:(%d+)'))or value
            state.infoReads=state.infoReads+1
            if state.infoHook then state.infoHook(id,value)end
            if state.infoFailure==id then error('Metadata unavailable')end
            if not state.ready[id]then return end
            local gear=id==100
            local values={'Item '..id,value,2,gear and 20 or 1,0,
                gear and 'Weapon'or(id==300 and 'Quest'or'Consumable'),gear and 'Staves'or'Other',
                gear and 1 or 20,gear and 'INVTYPE_2HWEAPON'or'INVTYPE_NON_EQUIP_IGNORE',123,0,gear and 2 or 0,gear and 10 or 0,0,false,0,id==600,'Description '..id}
            for index,replacement in pairs(state.metadata[id]or{})do values[index]=replacement end
            if state.optionalAbsent then values[14]=nil;values[17]=nil;values[18]=nil end
            return (unpack or table.unpack)(values,1,18)
        end,
        GetDetailedItemLevelInfo=function(value)
            state.levelReads[#state.levelReads+1]=value
            local id=type(value)=='string'and tonumber(value:match('item:(%d+)'))or value
            if state.levelOverride~=nil then return state.levelOverride end
            return id==100 and 21 or 1
        end,
        GetItemStats=function(value)
            assert(type(value)=='string','Instance stats must use the full item link')
            if state.statsFailure then error('Stats unavailable')end
            if state.nilStats then return nil end
            return copy(state.stats[value]or{})
        end,
        GetItemGem=function(value,index)
            if tonumber(value:match('item:%d+:%d*:(%d+)'))==500 and index==1 and state.ready[500]then return 'Gem',link(500)end
        end,
        RequestLoadItemDataByID=function(id)
            assert(type(id)=='number'and id>0 and id%1==0,'Only valid item IDs may be requested')
            requests[id]=(requests[id]or 0)+1;requestTimes[id]=requestTimes[id]or{}
            requestTimes[id][#requestTimes[id]+1]=now
        end,
    }
    C_TooltipInfo={GetBagItem=function(id,slot)
        allowed(id)
        if state.tooltipHook then state.tooltipHook(id,slot)end
        if state.tooltipFailure then error('Tooltip unavailable')end
        return copy(state.tooltip or {lines={{leftText='|cff00ff00Use: Item effect|r',rightText='Stack'},
            {leftText='Bag '..id..' slot '..slot}}})
    end}
    local function mutation()state.mutations=state.mutations+1;error('Mutation forbidden')end
    for _,name in ipairs({'UseContainerItem','PickupContainerItem','SplitContainerItem','SetBagSlotFlag','SortBags'})do C_Container[name]=mutation;_G[name]=mutation end
    for _,name in ipairs({'UseItemByName','EquipItemByName','PutItemInBag','PutItemInBackpack','DeleteCursorItem','AutoEquipCursorItem'})do _G[name]=mutation end
    local function worn()state.forbiddenReads=state.forbiddenReads+1;error('Worn equipment is another category')end
    GetInventoryItemID=worn;GetInventoryItemLink=worn;C_TooltipInfo.GetInventoryItem=worn
    fresh()
end

reset()
local out=capture()
assert(out.available and out.status=='available'and out.scanComplete and out.totalsComplete)
assert(out.scope=='carried_bags'and out.capturedAt==1100)
assert(out.bagCount==3 and out.totalSlots==9 and out.freeSlots==2 and out.occupiedSlots==7 and out.itemCount==39)
assert(#out.entries==9 and bag(out,0).numSlots==5 and bag(out,0).freeSlots==1)
assert(find(out,0,5).empty==true and find(out,1,3).empty==true)
local staff=find(out,0,1);local second=find(out,1,1);local potion=find(out,0,2)
assert(staff.empty==false and staff.itemID==100 and staff.count==1 and staff.isBound==true and staff.isLocked==false)
assert(staff.name=='Item 100'and staff.baseItemLevel==20 and staff.itemLevel==21 and staff.requiredLevel==0)
assert(staff.itemDescription=='Description 100'and staff.isEquippable==true)
assert(staff.stats.ITEM_MOD_INTELLECT_SHORT==5 and staff.stats.ITEM_MOD_STAMINA_SHORT==0)
assert(second.itemID==staff.itemID and second.link~=staff.link and second.stats.ITEM_MOD_SPIRIT_SHORT==3)
assert(staff.enhancements.enchantID==42 and second.enhancements.enchantID==43 and staff.enhancements.sockets[1].itemID==500)
assert(staff.tooltipLines[1].left=='Use: Item effect'and staff.tooltipLines[1].right=='Stack')
assert(potion.count==20 and potion.isBound==false and potion.isLocked==false and potion.equipLocation=='INVTYPE_NON_EQUIP_IGNORE')
assert(potion.isEquippable==false and find(out,0,3).isEquippable==false and find(out,5,1).isEquippable==false,
    'The Forever non-equipment sentinel does not make consumables, quest items or reagents equippable')
assert(potion.maxStack==20 and potion.sellPrice==0 and potion.bindType==0 and potion.isCraftingReagent==false)
assert(find(out,1,2).isLocked==true and find(out,0,3).itemType=='Quest'and find(out,5,1).isCraftingReagent==true)
assert(next(potion.stats)==nil and potion.statsStatus=='available')
assert(requestCount()==0)
state.metadata[200]={[9]=''};out=capture();potion=find(out,0,2)
assert(out.status=='available'and potion.equipLocation==''and potion.isEquippable==false,
    'The legacy empty non-equipment location remains supported')
state.optionalAbsent=true;out=capture()
assert(out.status=='available'and find(out,0,2).bindType==nil and find(out,0,2).isCraftingReagent==nil,'Optional missing metadata is not an unreadable item')
print('PASS: every carried slot, consumables, quest items, reagent bag, exact totals, instance stats and zero/false metadata')

reset();local equippableReads={}
C_Item.IsEquippableItem=function(value)
    assert(type(value)=='string','Equippability uses the full instance link when one is available')
    equippableReads[value]=true
    return tonumber(value:match('item:(%d+)'))==100
end
out=capture();assert(find(out,0,1).isEquippable==true and find(out,0,2).isEquippable==false)
assert(equippableReads[state.contents[0][1].hyperlink]and equippableReads[state.contents[1][1].hyperlink])
C_Item.IsEquippableItem=function()return false end
out=capture();assert(find(out,0,1).isEquippable==false,'An authoritative false must not fall through to the equipment location')
C_Item.IsEquippableItem=function()return true end
out=capture();assert(find(out,0,2).isEquippable==true,'An authoritative API result takes precedence over location fallback')
for _,failure in ipairs({'nil','restricted','malformed','error'})do
    reset();C_Item.IsEquippableItem=function()
        if failure=='restricted'then return secret end
        if failure=='malformed'then return 'false'end
        if failure=='error'then error('Equippability unavailable')end
    end
    out=capture();staff=find(out,0,1)
    assert(staff.isEquippable==nil and staff.fieldStatus.isEquippable~='available'and staff.status=='partial',
        'An unreadable authoritative result cannot become guessed equippability: '..failure)
end
reset();state.metadata[200]={[9]='INVTYPE_FUTURE_CUSTOM'}
out=capture();assert(find(out,0,2).isEquippable==nil and find(out,0,2).status=='partial','An unknown location token is not known equipment')
reset();state.contents[0][2].hyperlink=nil;local queriedID=false
C_Item.IsEquippableItem=function(value)if value==200 then queriedID=true;return false end;return type(value)=='string'and value:match('item:100:')~=nil end
out=capture();assert(queriedID and find(out,0,2).isEquippable==false,'Basic equippability may use a known ID when its full link is unavailable')
print('PASS: authoritative equippability, Forever and legacy non-equipment markers, and unknown API/location results')

reset()
state.contents[0][2].hyperlink='|cnIQ1:|Hitem:200::::::::31:1487::75:::::::|h[Item 200]|h|r'
out=capture();potion=find(out,0,2)
assert(out.status=='available'and potion.status=='available'and potion.enhancements.status=='available')
assert(potion.enhancements.enchantID==0 and potion.enhancements.fieldStatus.enchantID=='available'and #potion.enhancements.sockets==0,
    'Present blank enhancement fields in a canonical item link explicitly mean no enchant or gems')
assert(requestCount()==0,'Known absent enhancements must not request item data')
reset();state.contents[0][1].hyperlink='|Hitem:100::500::::::31:1487::75:::::::|h[Item 100]|h'
out=capture();staff=find(out,0,1)
assert(staff.enhancements.status=='available'and staff.enhancements.enchantID==0 and staff.enhancements.sockets[1].itemID==500,
    'Blank enchant fields must not erase a nonzero socket ID')
for _,encoded in ipairs({'200','200:','200:0:0','200:bogus:0:0:0:0:','200:0:bogus:0:0:0:','200:0:0:0:0:0oops'})do
    reset();state.contents[0][2].hyperlink='|Hitem:'..encoded..'|h[Item 200]|h'
    out=capture();potion=find(out,0,2)
    assert(potion.itemID==200 and potion.enhancements.status=='partial'and potion.status=='partial',
        'Missing or malformed enhancement fields must not become known absence: '..encoded)
    if encoded=='200' or encoded=='200:bogus:0:0:0:0:' then
        assert(potion.enhancements.enchantID==nil,'An absent or malformed enchant field cannot become zero')
    end
end
print('PASS: canonical blank enhancement fields, with malformed and truncated links kept explicitly incomplete')

reset();Enum.BagIndex={};state.allowed[5]=nil
out=capture();assert(out.totalSlots==8 and out.bagCount==2 and state.bagReads[5]==nil)
reset();Enum.BagIndex.Keyring=-1;state.allowed[-1]=true;state.sizes[-1]=2;state.contents[-1]={[1]=item(300,1,true)}
out=capture();assert(out.totalSlots==11 and out.bagCount==4 and find(out,-1,1).itemID==300 and find(out,-1,2).empty)
reset();Enum.BagIndex={ReagentBag=6,Keyring=-2};state.allowed[5]=nil
out=capture();assert(out.totalSlots==8 and state.bagReads[6]==nil and state.bagReads[-2]==nil)
reset();C_Container.GetContainerNumFreeSlots=nil
out=capture();assert(out.status=='available'and out.freeSlots==2,'Free totals come from slots, not an optional bag-family API')
reset();C_Container.GetContainerNumFreeSlots=function()return 99,0 end
out=capture();assert(out.freeSlots==2,'Reported aggregate free space cannot override observed slot occupancy')
reset();state.contents={}
out=capture();assert(out.available and out.status=='available'and out.freeSlots==9 and out.occupiedSlots==0 and out.itemCount==0)
assert(out.totalsComplete and #out.entries==9)
reset();for id in pairs(state.sizes)do state.sizes[id]=0 end;state.contents={}
out=capture();assert(out.status=='available'and out.totalSlots==0 and out.bagCount==0 and out.itemCount==0 and #out.entries==0)
print('PASS: optional containers, exact keyring/reagent IDs, excluded banks/equipment, empty bags and read-only collection')

reset();state.slotFailure='0/2'
out=capture();assert(out.available and out.status=='partial'and not out.scanComplete and not out.totalsComplete)
assert(find(out,0,2).empty==nil and find(out,0,2).status~='empty'and find(out,1,1).name=='Item 100')
assert(out.totalSlots==9 and out.freeSlots==nil and out.occupiedSlots==nil and out.itemCount==nil)
reset();state.sizeFailure=1
out=capture();assert(out.available and out.status=='partial'and not out.scanComplete and out.totalSlots==nil and not out.totalsComplete)
assert(find(out,0,1).itemID==100)
reset();state.contents[0][2]=secret
out=capture();assert(find(out,0,2).empty==nil and find(out,0,2).status=='restricted'and not out.scanComplete)
reset();state.contents[0][2]=false
out=capture();assert(find(out,0,2).empty==nil and not out.scanComplete,'Only a successful nil container result proves an empty slot')
reset();state.contents[0][2].hyperlink=link(300)
out=capture();assert(find(out,0,2).empty==nil and find(out,0,2).itemID==nil and not out.scanComplete,'Conflicting link and item IDs cannot produce mixed details')
reset();state.contents[0][2].stackCount=secret
out=capture();assert(find(out,0,2).itemID==200 and find(out,0,2).empty==false and find(out,0,2).count==nil)
assert(out.freeSlots==2 and out.occupiedSlots==7 and out.itemCount==nil and not out.totalsComplete)
reset();state.contents[0][2].stackCount=-1;state.contents[0][3].stackCount=math.huge
out=capture();assert(find(out,0,2).count==nil and find(out,0,3).count==nil and out.itemCount==nil)
reset();C_Container.GetContainerItemInfo=nil
out=capture();assert(not out.available and out.status=='unsupported'and not out.scanComplete)
reset();C_Container.GetContainerNumSlots=nil
out=capture();assert(not out.available and out.status=='unsupported'and not out.scanComplete)
for _,missingLink in ipairs({false,secret})do
    reset();state.contents[0][2].hyperlink=missingLink
    if missingLink==false then state.contents[0][2].hyperlink=nil end
    out=capture();potion=find(out,0,2)
    assert(potion.empty==false and potion.itemID==200 and potion.count==20 and potion.name=='Item 200')
    assert(potion.itemLevel==nil and potion.statsStatus~='available'and not out.scanComplete,'An item ID cannot identify the actual instance level or stats')
    for _,value in ipairs(state.levelReads)do assert(type(value)=='string','Detailed levels require the full instance link')end
end
print('PASS: unknown slots never become empty, unknown totals stay absent, per-container isolation and missing core APIs')

reset();state.stats[state.contents[0][1].hyperlink]={ITEM_MOD_INTELLECT_SHORT=secret,ITEM_MOD_SPIRIT_SHORT=0/0,ARMOR=0,RESISTANCE1_NAME=math.huge}
state.metadata[100]={[3]=secret,[4]=math.huge,[11]=0/0,[17]='yes'};state.levelOverride=0/0
state.contents[0][1].quality=secret;state.contents[1][1].quality=secret
out=capture();staff=find(out,0,1)
assert(out.status=='partial'and staff.itemID==100 and staff.name=='Item 100')
assert(staff.quality==nil and staff.baseItemLevel==nil and staff.itemLevel==nil and staff.sellPrice==nil and staff.isCraftingReagent==nil)
assert(staff.statsStatus=='partial'and staff.stats.ARMOR==0 and staff.stats.ITEM_MOD_INTELLECT_SHORT==nil and staff.stats.ITEM_MOD_SPIRIT_SHORT==nil)
assert(staff.statStatus.ITEM_MOD_INTELLECT_SHORT=='restricted'and find(out,0,2).name=='Item 200')
reset();state.nilStats=true
out=capture();potion=find(out,0,2)
assert(potion.statsStatus=='unavailable'and next(potion.stats)==nil and potion.name=='Item 200'and out.status=='partial')
reset();state.infoFailure=100
out=capture();assert(find(out,0,1).itemID==100 and find(out,0,1).status~='available'and find(out,0,2).name=='Item 200')
reset();state.tooltip={lines={[1]={leftText='Known'},[3]={leftText='Missing middle'}}}
out=capture();assert(find(out,0,1).tooltipStatus=='partial'and out.status=='partial','Sparse tooltip data is not complete')
reset();state.tooltip={lines={{leftText=secret},{leftText='Visible'}}}
out=capture();assert(find(out,0,1).tooltipStatus=='partial'and find(out,0,1).tooltipLines[1].left=='Visible')
reset();C_TooltipInfo.GetBagItem=nil
out=capture();assert(out.status=='partial'and find(out,0,1).itemID==100 and find(out,0,1).tooltipStatus~='available')
for _,bad in ipairs({{17,'yes'},{14,-1},{18,false}})do
    reset();state.metadata[200]={[bad[1]]=bad[2]}
    out=capture();assert(find(out,0,2).status=='partial'and out.status=='partial','Malformed present optional metadata differs from absent optional metadata')
end
reset();state.contents[0][2].isReadable='false'
out=capture();assert(find(out,0,2).isReadable==nil and find(out,0,2).status=='partial')
print('PASS: restricted/nonfinite metadata, absent consumable stats, tooltip structure and independent readable entries')

reset();local previous=capture()
state.contents[0][2].stackCount=7;state.contents[1][3]=state.contents[0][3];state.contents[0][3]=nil
out=capture();assert(out.itemCount==26 and find(out,0,2).count==7 and find(out,0,3).empty and find(out,1,3).itemID==300)
assert(find(previous,0,2).count==20 and find(previous,0,3).itemID==300,'Later scans must not mutate earlier snapshots')
state.contents[0][2]=item(999,1,false);out=capture();assert(requests[999]==1)
state.contents[0][2]=nil;state.ready[999]=true;ExporterItems.OnEvent('ITEM_DATA_LOAD_RESULT',999,true)
out=capture();assert(find(out,0,2).empty and find(previous,0,2).itemID==200,'Late data cannot restore a removed item')
state.contents[1][3]=item(998,1,false);out=capture();state.contents[0][2]=state.contents[1][3];state.contents[1][3]=nil
state.ready[998]=true;ExporterItems.OnEvent('GET_ITEM_INFO_RECEIVED',998,true)
out=capture();assert(find(out,0,2).name=='Item 998'and find(out,1,3).empty)
print('PASS: fresh stack counts, moves, removals, late callbacks and immutable previous snapshots')

reset();local changed=false
state.infoHook=function(id)if id==200 and not changed then changed=true;state.contents[0][2]=item(300,4,true)end end
out=capture();assert(find(out,0,2).itemID==300 and find(out,0,2).name=='Item 300'and find(out,0,2).count==4,'Identity changes retry fresh metadata')
reset();changed=false
state.infoHook=function(id)if id==200 and not changed then changed=true;state.contents[0][2].stackCount=9 end end
out=capture();assert(find(out,0,2).count==9 and out.itemCount==28,'Stack count is part of slot identity')
reset();changed=false;local replacement=link(100,44,0,99);state.stats[replacement]={ITEM_MOD_SPIRIT_SHORT=17}
state.infoHook=function(id)if id==100 and not changed then changed=true;state.contents[0][1].hyperlink=replacement end end
out=capture();staff=find(out,0,1);assert(staff.link==replacement and staff.stats.ITEM_MOD_SPIRIT_SHORT==17 and staff.enhancements.enchantID==44)
reset();local flips=0
state.infoHook=function(id)
    if id==200 or id==300 then flips=flips+1;state.contents[0][2]=item(id==200 and 300 or 200,flips+1,false)end
end
out=capture();assert(not out.scanComplete and find(out,0,2).empty==nil and out.itemCount==nil)
assert(find(out,0,1).itemID==100 and state.infoReads<100,'An unstable slot must not prevent other slots or retry forever')
reset();changed=false
state.infoHook=function()if not changed then changed=true;state.sizes[0]=6 end end
out=capture();assert((out.totalSlots==10 and #out.entries==10)or(not out.scanComplete and out.totalSlots==nil),'Changed bag size must be recaptured or explicitly incomplete')
reset();changed=false
state.infoHook=function(id)
    if id==300 and not changed then changed=true;state.contents[1][3]=state.contents[0][1];state.contents[0][1]=nil end
end
out=capture();assert(find(out,0,1).empty and find(out,1,3).itemID==100 and out.itemCount==39,'A move later in the scan cannot duplicate an already captured item')
print('PASS: item, count and instance-link race checks, bounded retries and changed bag capacity')

reset();state.contents[0][2]=item(999,1,false)
out=capture();assert(find(out,0,2).nameStatus=='pending'and requests[999]==1)
for i=1,4 do capture()end;assert(requests[999]==1,'Repeated exports do not spam cache requests')
now=129;capture();assert(requests[999]==1)
now=130;capture();assert(requests[999]==2)
now=160;capture();assert(requests[999]==3)
now=190;out=capture();assert(requests[999]==3 and find(out,0,2).nameStatus=='unavailable')
state.ready[999]=true;ExporterItems.OnEvent('ITEM_DATA_LOAD_RESULT',999,true)
out=capture();assert(find(out,0,2).name=='Item 999','Fresh readable metadata can recover after exhausted retries')
reset();state.contents[0][2]=item(999,1,false);local pending=capture();ExporterItems.OnEvent('GET_ITEM_INFO_RECEIVED',999,false)
assert(find(pending,0,2).nameStatus=='pending','Callbacks must not mutate already captured results')
now=131;out=capture();assert(requests[999]==1 and find(out,0,2).nameStatus=='unavailable')
state.ready[999]=true;out=capture();assert(find(out,0,2).name=='Item 999')
reset();state.ready[500]=nil
out=capture();assert(staff~=find(out,0,1)and find(out,0,1).enhancements.sockets[1].nameStatus=='pending'and requests[500]==1)
state.ready[500]=true;ExporterItems.OnEvent('ITEM_DATA_LOAD_RESULT',500,true)
out=capture();assert(find(out,0,1).enhancements.sockets[1].name=='Gem')
reset();state.contents={[0]={}};state.sizes={[0]=13,[1]=0,[2]=0,[3]=0,[4]=0,[5]=0};state.ready={}
for slot=1,12 do state.contents[0][slot]=item(1000+slot,1,false)end
state.contents[0][13]=item(1001,1,false)
local before=0
for pass=1,7 do
    out=capture();local after=requestCount();assert(after-before<=8,'Eight total requests per capture, including retries and duplicate slots')
    before=after;now=now+31
end
for id=1001,1012 do
    assert(requests[id]==3,'Every present item must receive bounded opportunities to load')
    for index=2,#requestTimes[id]do assert(requestTimes[id][index]-requestTimes[id][index-1]>=30)end
end
assert(requestCount()==36)
reset();state.contents={[0]={}};state.sizes={[0]=12,[1]=0,[2]=0,[3]=0,[4]=0,[5]=0};state.ready={}
for slot=1,12 do state.contents[0][slot]=item(2000+slot,1,false)end
changed=false
state.infoHook=function()if not changed then changed=true;state.contents[0][1].stackCount=2 end end
out=capture();assert(out.itemCount==13 and requestCount()<=8,'A capture retry shares the original eight-request budget')
print('PASS: delayed item/gem data, failure callbacks, duplicate-ID deduplication and eight/three/thirty loading limits')

reset();state.sizes[0]=201
out=capture();assert(out.status~='available'and not out.scanComplete and out.totalSlots==nil and #out.entries<=209,'Oversize containers cannot be silently complete')
reset();state.sizes[0]=0/0
out=capture();assert(not out.scanComplete and out.totalSlots==nil and find(out,1,1).itemID==100)
reset();state.sizes[0]=-1
out=capture();assert(not out.scanComplete and out.totalSlots==nil)
reset();state.tooltip={lines={}}
for index=1,81 do state.tooltip.lines[index]={leftText='Line '..index}end
out=capture();assert(#find(out,0,1).tooltipLines<=80 and find(out,0,1).tooltipStatus=='partial')
reset();local manyStats={};for index=1,257 do manyStats['STAT_'..index]=index end
state.stats[state.contents[0][1].hyperlink]=manyStats
out=capture();staff=find(out,0,1);local count=0;for _ in pairs(staff.stats)do count=count+1 end
assert(count<=256 and staff.statsStatus=='partial','Oversize stat maps cannot silently claim complete metadata')
print('PASS: explicit container and tooltip bounds without silent success or invented totals')
