-- Carried containers only. Every capture reads slot identity afresh; no item actions.
-- Item helpers adapted from MIT-licensed source; see LICENSE and THIRD_PARTY.md.
ExporterItems = {}
local I=ExporterItems
local MAX_SLOTS,MAX_TOOLTIP_LINES,MAX_STATS=200,80,256
local equipLocations={INVTYPE_HEAD=true,INVTYPE_NECK=true,INVTYPE_SHOULDER=true,INVTYPE_BODY=true,INVTYPE_CHEST=true,
    INVTYPE_WAIST=true,INVTYPE_LEGS=true,INVTYPE_FEET=true,INVTYPE_WRIST=true,INVTYPE_HAND=true,INVTYPE_FINGER=true,
    INVTYPE_TRINKET=true,INVTYPE_WEAPON=true,INVTYPE_SHIELD=true,INVTYPE_RANGED=true,INVTYPE_CLOAK=true,
    INVTYPE_2HWEAPON=true,INVTYPE_BAG=true,INVTYPE_TABARD=true,INVTYPE_ROBE=true,INVTYPE_WEAPONMAINHAND=true,
    INVTYPE_WEAPONOFFHAND=true,INVTYPE_HOLDABLE=true,INVTYPE_AMMO=true,INVTYPE_THROWN=true,INVTYPE_RANGEDRIGHT=true,
    INVTYPE_QUIVER=true,INVTYPE_RELIC=true,INVTYPE_PROFESSION_TOOL=true,INVTYPE_PROFESSION_GEAR=true}
local requests,seen,budget={},{},0
local unpackValues=unpack or table.unpack

local function accessible(value)
    local ok,result=pcall(function()
        return not (issecretvalue and issecretvalue(value)) and (not canaccessvalue or canaccessvalue(value))
    end)
    return ok and result
end
local function valid(value,kind)
    if not accessible(value) or type(value)~=kind then return false end
    return kind~="number" or (value==value and value~=math.huge and value~=-math.huge)
end
local function integer(value,minimum,maximum)
    return valid(value,"number") and value>=minimum and value==math.floor(value) and (not maximum or value<=maximum)
end
local function member(source,key)
    if not valid(source,"table") then return nil,accessible(source) and "unavailable" or "restricted" end
    local ok,value=pcall(function() return source[key] end)
    if not ok then return nil,"api_error" end
    if not accessible(value) then return nil,"restricted" end
    return value,value~=nil and "available" or "unavailable"
end
local function read(fn,...)
    if type(fn)~="function" then return nil,"unsupported" end
    local ok,value=pcall(fn,...)
    if not ok then return nil,"api_error" end
    if not accessible(value) then return nil,"restricted" end
    return value,value~=nil and "available" or "unavailable"
end
local function pack(...) return {n=select("#",...),...} end
local function tuple(fn,...)
    if type(fn)~="function" then return nil,"unsupported" end
    local result=pack(pcall(fn,...))
    if not result[1] then return nil,"api_error" end
    return pack(unpackValues(result,2,result.n)),"available"
end
local function clean(value,allowEmpty)
    if not valid(value,"string") then return nil end
    value=value:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")
        :gsub("|H.-|h(.-)|h","%1"):gsub("|T.-|t",""):gsub("|A.-|a","")
    return (allowEmpty or value~="") and value or nil
end
local function field(out,key,value,kind,status,allowEmpty,raw)
    out.fieldStatus=out.fieldStatus or {}
    if not status or status=="available" then
        status=not accessible(value) and "restricted" or (valid(value,kind) and "available" or "unavailable")
    end
    if status=="available" and kind=="string" then
        if not raw then value=clean(value,allowEmpty)
        elseif not allowEmpty and value=="" then value=nil end
        if value==nil then status="unavailable" end
    end
    out.fieldStatus[key]=status
    if status=="available" then out[key]=value end
end
local function numericField(out,key,value,status,minimum)
    field(out,key,value,"number",status)
    if out[key]~=nil and not integer(out[key],minimum or 0) then out[key]=nil; out.fieldStatus[key]="unavailable" end
end
local function itemAPI(name)
    local fn=valid(C_Item,"table") and C_Item[name]
    if type(fn)=="function" then return fn end
    return _G[name]
end
local function idFromLink(link)
    if not valid(link,"string") then return nil end
    local id=tonumber(link:match("item:(%d+)"))
    return integer(id,1) and id or nil
end
local function requestStatus(id)
    if ExporterDataRequests then return ExporterDataRequests.Status("item",id,itemAPI("RequestLoadItemDataByID")) end
    local now=read(GetTime); local old=requests[id]
    if type(itemAPI("RequestLoadItemDataByID"))~="function" or not valid(now,"number") then return "unavailable" end
    if old and (old.failed or (old.attempts>=3 and now-old.at>=30)) then return "unavailable" end
    return "pending"
end
local function request(id)
    if not integer(id,1) then return "unavailable" end
    seen[id]=true
    if ExporterDataRequests then return ExporterDataRequests.Request("item",id,itemAPI("RequestLoadItemDataByID")) end
    if requestStatus(id)=="unavailable" then return "unavailable" end
    local old=requests[id]; local now=read(GetTime)
    if budget>0 and (not old or (old.attempts<3 and now-old.at>=30)) then
        old={attempts=old and old.attempts+1 or 1,at=now}; requests[id]=old; budget=budget-1
        if not pcall(itemAPI("RequestLoadItemDataByID"),id) then old.failed=true end
    end
    return requestStatus(id)
end
function I.OnEvent(event,id,success)
    if (event=="GET_ITEM_INFO_RECEIVED" or event=="ITEM_DATA_LOAD_RESULT") and integer(id,1)
        and seen[id] and requests[id] and success==false then requests[id].failed=true end
end
local function bagIDs()
    local ids={0,1,2,3,4}
    local enum=member(Enum,"BagIndex")
    local reagent=member(enum,"ReagentBag"); local keyring=member(enum,"Keyring")
    if reagent==5 then ids[#ids+1]=5 end
    if keyring==-1 then ids[#ids+1]=-1 end
    return ids
end
local function unknown(bagID,slot,status)
    return {bagID=bagID,slotID=slot,status=status or "unavailable",fieldStatus={}}
end
local function identity(api,bagID,slot)
    local info,status=read(api.GetContainerItemInfo,bagID,slot)
    if info==nil and status=="unavailable" then return {bagID=bagID,slotID=slot,empty=true,status="empty",fieldStatus={}} end
    if not valid(info,"table") then return unknown(bagID,slot,status=="restricted" and "restricted" or "unavailable") end
    local out={bagID=bagID,slotID=slot,status="partial",fieldStatus={}}
    local link,linkStatus=member(info,"hyperlink"); field(out,"link",link,"string",linkStatus,false,true)
    local id,idStatus=member(info,"itemID")
    if not integer(id,1) then
        local linked=idFromLink(out.link)
        if linked then id,idStatus=linked,"available" end
    end
    numericField(out,"itemID",id,idStatus,1)
    local linked=idFromLink(out.link)
    if linked and out.itemID and linked~=out.itemID then
        out.itemID=nil; out.link=nil; out.fieldStatus.itemID="unavailable"; out.fieldStatus.link="unavailable"
        return out
    end
    if not out.itemID then return out end
    out.empty=false; seen[out.itemID]=true
    local invalidOptional=false
    local count,countStatus=member(info,"stackCount"); numericField(out,"count",count,countStatus,1)
    for _,key in ipairs({"isBound","isLocked","hasNoValue","isReadable","hasLoot","isFiltered"}) do
        local value,valueStatus=member(info,key); field(out,key,value,"boolean",valueStatus)
        if key~="isBound" and key~="isLocked" and out.fieldStatus[key]~="available"
            and (value~=nil or valueStatus=="restricted" or valueStatus=="api_error") then invalidOptional=true end
    end
    local quality,qualityStatus=member(info,"quality"); numericField(out,"quality",quality,qualityStatus,0)
    local icon,iconStatus=member(info,"iconFileID"); numericField(out,"iconID",icon,iconStatus,0)
    if out.fieldStatus.iconID~="available" and (icon~=nil or iconStatus=="restricted" or iconStatus=="api_error") then invalidOptional=true end
    local name,nameStatus=member(info,"itemName"); field(out,"name",name,"string",nameStatus)
    return out,invalidOptional
end
local function sameIdentity(left,right)
    if left.empty~=right.empty or left.itemID~=right.itemID or left.count~=right.count or left.link~=right.link then return false end
    for _,key in ipairs({"itemID","count","link","isBound","isLocked"}) do
        if left[key]~=right[key] or left.fieldStatus[key]~=right.fieldStatus[key] then return false end
    end
    return true
end
local function tooltip(bagID,slot)
    local info,status=read(C_TooltipInfo and C_TooltipInfo.GetBagItem,bagID,slot)
    if not valid(info,"table") then return {},status=="available" and "unavailable" or status end
    local lines,lineStatus=member(info,"lines")
    if not valid(lines,"table") then return {},lineStatus=="available" and "unavailable" or lineStatus end
    local highest,count=0,0; status="available"
    for key in pairs(lines) do
        if integer(key,1) then highest=math.max(highest,key); count=count+1 else status="partial" end
    end
    if highest~=count or highest>MAX_TOOLTIP_LINES then status="partial" end
    local out={}
    for index=1,math.min(highest,MAX_TOOLTIP_LINES) do
        local line=lines[index]
        if not valid(line,"table") then status="partial"
        else
            local left,leftStatus=member(line,"leftText"); local right,rightStatus=member(line,"rightText")
            local cleanLeft,cleanRight=clean(left),clean(right)
            if cleanLeft or cleanRight then out[#out+1]={left=cleanLeft,right=cleanRight} end
            if leftStatus=="restricted" or rightStatus=="restricted" or leftStatus=="api_error" or rightStatus=="api_error"
                or (left~=nil and not valid(left,"string")) or (right~=nil and not valid(right,"string")) then status="partial" end
        end
    end
    if #out==0 and status=="available" then status="unavailable" end
    return out,status
end
local function stats(out)
    out.stats={}; out.statStatus={}; out.statsStatus="unavailable"
    if not out.link then return end
    local values,status=read(itemAPI("GetItemStats"),out.link)
    if not valid(values,"table") then out.statsStatus=status=="available" and "unavailable" or status; return end
    out.statsStatus="available"
    local count=0
    for key,value in pairs(values) do
        count=count+1
        if count>MAX_STATS then out.statsStatus="partial"; break end
        if valid(key,"string") and key~="" then
            local state=not accessible(value) and "restricted" or (valid(value,"number") and "available" or "unavailable")
            out.statStatus[key]=state
            if state=="available" then out.stats[key]=value else out.statsStatus="partial" end
        else out.statsStatus="partial" end
    end
end
local function enhancements(out)
    local data={sockets={},emptySockets={},status=out.link and "available" or "unavailable",fieldStatus={}}
    out.enhancements=data
    for key,value in pairs(out.stats) do if key:match("^EMPTY_SOCKET_") then data.emptySockets[key]=value end end
    if not out.link then return end
    -- Parse the complete payload: a numeric-prefix match would hide malformed tokens.
    local encoded=out.link:match("|Hitem:([^|]*)|h") or out.link:match("^item:(.*)$")
    local parts={}
    if encoded then for part in (encoded..":"):gmatch("(.-):") do parts[#parts+1]=part end end
    for _,part in ipairs(parts) do
        if part~="" and not part:match("^%-?%d+$") then data.status="partial" end
    end
    local function enhancementID(position)
        local part=parts[position]
        if part=="" then return 0 end -- An existing blank field is the canonical zero value.
        if part and part:match("^%d+$") then
            local value=tonumber(part)
            if integer(value,0) then return value end
        end
    end
    local enchant=enhancementID(2); numericField(data,"enchantID",enchant,nil,0)
    if data.fieldStatus.enchantID~="available" then data.status="partial" end
    for index=1,4 do
        local gemID=enhancementID(index+2)
        if gemID==nil then data.status="partial"
        elseif gemID>0 then
            local values,gemStatus=tuple(itemAPI("GetItemGem"),out.link,index)
            local gemName=values and values[1]; local gemLink=values and values[2]
            local reportedID=idFromLink(gemLink)
            if reportedID and reportedID~=gemID then gemName=nil; gemLink=nil; gemStatus="unavailable" end
            seen[gemID]=true
            local socket={index=index,itemID=gemID,fieldStatus={}}
            field(socket,"name",gemName,"string",gemStatus)
            field(socket,"link",gemLink,"string",gemStatus,false,true)
            socket.nameStatus=socket.name and "available" or (socket.fieldStatus.name=="restricted" and "restricted") or request(gemID)
            socket.status=socket.name and "available" or "partial"
            data.sockets[#data.sockets+1]=socket
            if socket.status~="available" then data.status="partial" end
        end
    end
end
local function details(source,invalidOptional)
    local out={}; for key,value in pairs(source) do
        if key=="fieldStatus" then out.fieldStatus={}; for name,state in pairs(value) do out.fieldStatus[name]=state end
        else out[key]=value end
    end
    local values,valueStatus=tuple(itemAPI("GetItemInfo"),out.link or out.itemID)
    local spec={{"name",1,"string"},{"quality",3,"number"},{"baseItemLevel",4,"number"},{"requiredLevel",5,"number"},
        {"itemType",6,"string"},{"itemSubType",7,"string"},{"maxStack",8,"number"},{"equipLocation",9,"string",true},
        {"sellPrice",11,"number"},{"classID",12,"number"},{"subClassID",13,"number"},{"bindType",14,"number"},
        {"isCraftingReagent",17,"boolean"},{"itemDescription",18,"string",true}}
    for _,entry in ipairs(spec) do
        local value=values and values[entry[2]]
        local temporary={fieldStatus={}}
        field(temporary,entry[1],value,entry[3],valueStatus,entry[4])
        if (entry[1]=="bindType" or entry[1]=="isCraftingReagent" or entry[1]=="itemDescription")
            and temporary.fieldStatus[entry[1]]~="available" and (not accessible(value) or value~=nil) then invalidOptional=true end
        -- Container metadata remains useful while item-info metadata is loading.
        if temporary.fieldStatus[entry[1]]=="available" or out[entry[1]]==nil then
            out[entry[1]]=temporary[entry[1]]; out.fieldStatus[entry[1]]=temporary.fieldStatus[entry[1]]
        end
    end
    for key,minimum in pairs({quality=0,baseItemLevel=0,requiredLevel=0,maxStack=1,sellPrice=0,classID=0,subClassID=0,bindType=0}) do
        if out[key]~=nil and not integer(out[key],minimum) then
            out[key]=nil; out.fieldStatus[key]="unavailable"
            if key=="bindType" then invalidOptional=true end
        end
    end
    local itemLevel,levelStatus
    if out.link then itemLevel,levelStatus=read(itemAPI("GetDetailedItemLevelInfo"),out.link)
    else levelStatus=out.fieldStatus.link or "unavailable" end
    numericField(out,"itemLevel",itemLevel,levelStatus,0)
    local equippableAPI=itemAPI("IsEquippableItem")
    if type(equippableAPI)=="function" then
        local equippable,equippableStatus=read(equippableAPI,out.link or out.itemID)
        field(out,"isEquippable",equippable,"boolean",equippableStatus)
    elseif out.equipLocation=="" or out.equipLocation=="INVTYPE_NON_EQUIP_IGNORE" then
        field(out,"isEquippable",false,"boolean","available")
    elseif out.equipLocation and equipLocations[out.equipLocation] then
        field(out,"isEquippable",true,"boolean","available")
    else out.fieldStatus.isEquippable=out.fieldStatus.equipLocation=="restricted" and "restricted" or "unavailable" end
    if not out.name or not (values and clean(values[1])) then out.itemDataStatus=request(out.itemID) end
    out.nameStatus=out.name and "available" or (out.fieldStatus.name=="restricted" and "restricted") or out.itemDataStatus or "unavailable"
    stats(out); enhancements(out)
    out.tooltipLines,out.tooltipStatus=tooltip(out.bagID,out.slotID)
    out.status="available"
    if invalidOptional then out.status="partial" end
    for _,key in ipairs({"itemID","link","count","isBound","isLocked","name","quality","baseItemLevel","itemLevel","requiredLevel",
        "itemType","itemSubType","maxStack","equipLocation","isEquippable","sellPrice","classID","subClassID"}) do
        if out.fieldStatus[key]~="available" then out.status="partial" end
    end
    for _,key in ipairs({"bindType","isCraftingReagent","itemDescription","hasNoValue","isReadable","hasLoot","isFiltered","iconID"}) do
        local status=out.fieldStatus[key]
        if status=="restricted" or status=="api_error" then out.status="partial" end
    end
    if out.statsStatus~="available" or out.tooltipStatus~="available" or out.enhancements.status~="available" then out.status="partial" end
    return out
end
local function bagHeader(api,id)
    local out={bagID=id,fieldStatus={},status="available",scanComplete=true}
    local slots,slotStatus=read(api.GetContainerNumSlots,id)
    numericField(out,"numSlots",slots,slotStatus,0)
    if out.numSlots and out.numSlots>MAX_SLOTS then out.numSlots=nil; out.fieldStatus.numSlots="unavailable" end
    local name,nameStatus=read(api.GetBagName,id); field(out,"name",name,"string",nameStatus)
    if out.numSlots==0 and out.name==nil and (nameStatus=="unavailable" or nameStatus=="unsupported") then out.fieldStatus.name="not_applicable" end
    local free=tuple(api.GetContainerNumFreeSlots,id)
    local family=free and free[2]
    if family~=nil then numericField(out,"bagFamily",family,nil,0) end
    if out.numSlots==nil then out.status="unavailable"; out.scanComplete=false
    elseif out.fieldStatus.name~="available" and out.fieldStatus.name~="not_applicable" then out.status="partial" end
    return out
end
local function sameBag(left,right)
    return left.numSlots==right.numSlots and left.fieldStatus.numSlots==right.fieldStatus.numSlots
        and left.name==right.name and left.fieldStatus.name==right.fieldStatus.name
end
local function summarizeBag(bag,entries)
    local free,occupied,items=0,0,0
    local occupancyKnown=bag.numSlots~=nil
    local countsKnown=occupancyKnown
    bag.scanComplete=occupancyKnown
    for _,entry in ipairs(entries) do
        if entry.empty==true then free=free+1
        elseif entry.empty==false then
            occupied=occupied+1
            if integer(entry.count,1) then items=items+entry.count else countsKnown=false; bag.scanComplete=false end
            if not integer(entry.itemID,1) or not valid(entry.link,"string") then bag.scanComplete=false end
        else occupancyKnown=false; countsKnown=false; bag.scanComplete=false end
        if entry.status~="empty" and entry.status~="available" then bag.status="partial" end
    end
    bag.fieldStatus.freeSlots=occupancyKnown and "available" or "unavailable"
    bag.fieldStatus.occupiedSlots=bag.fieldStatus.freeSlots
    bag.fieldStatus.itemCount=occupancyKnown and countsKnown and "available" or "unavailable"
    if occupancyKnown then bag.freeSlots=free; bag.occupiedSlots=occupied end
    if occupancyKnown and countsKnown then bag.itemCount=items end
    bag.totalsComplete=occupancyKnown and countsKnown
end
local function scan(api,ids,stamp)
    local bags,entriesByBag,observations={},{},{}
    local changed=false
    for _,id in ipairs(ids) do
        local bag=bagHeader(api,id); bags[#bags+1]=bag
        local entries={}; entriesByBag[id]=entries; observations[id]={}
        if bag.numSlots~=nil then
            for slot=1,bag.numSlots do
                local ok,before,invalidOptional=pcall(identity,api,id,slot)
                if not ok then before=unknown(id,slot,"unavailable") end
                observations[id][slot]=before
                local entry=before
                if before.empty==false then
                    local detailOK,data=pcall(details,before,invalidOptional)
                    entry=detailOK and data or before
                    if not detailOK then entry.status="partial"; entry.reason="Item metadata could not be read" end
                end
                local afterOK,after=pcall(identity,api,id,slot)
                if not afterOK then after=unknown(id,slot,"unavailable") end
                if not sameIdentity(before,after) then changed=true; entry=unknown(id,slot,"unstable") end
                entries[#entries+1]=entry
            end
        end
    end
    -- Recheck all locations after all detail reads to catch moves between bags.
    for _,bag in ipairs(bags) do
        local id=bag.bagID
        local after=bagHeader(api,id)
        if not sameBag(bag,after) then
            changed=true; bag.status="unstable"; bag.numSlots=nil; bag.fieldStatus.numSlots="unavailable"
            entriesByBag[id]={}
        elseif bag.numSlots~=nil then
            for slot=1,bag.numSlots do
                local ok,current=pcall(identity,api,id,slot)
                if not ok then current=unknown(id,slot,"unavailable") end
                if not sameIdentity(observations[id][slot],current) then
                    changed=true; entriesByBag[id][slot]=unknown(id,slot,"unstable")
                end
            end
        end
    end
    local out={available=false,status="available",capturedAt=stamp,scope="carried_bags",bags=bags,entries={},
        scanComplete=true,totalsComplete=true,fieldStatus={}}
    local sums={bagCount=0,totalSlots=0,freeSlots=0,occupiedSlots=0,itemCount=0}
    local known={bagCount=true,totalSlots=true,freeSlots=true,occupiedSlots=true,itemCount=true}
    for _,bag in ipairs(bags) do
        local entries=entriesByBag[bag.bagID]
        summarizeBag(bag,entries)
        if bag.numSlots~=nil then
            out.available=true; sums.totalSlots=sums.totalSlots+bag.numSlots
            if bag.numSlots>0 then sums.bagCount=sums.bagCount+1 end
        else known.bagCount=false; known.totalSlots=false end
        for _,key in ipairs({"freeSlots","occupiedSlots","itemCount"}) do
            if bag[key]~=nil then sums[key]=sums[key]+bag[key] else known[key]=false end
        end
        if not bag.scanComplete then out.scanComplete=false end
        if bag.status~="available" then out.status="partial" end
        for _,entry in ipairs(entries) do out.entries[#out.entries+1]=entry end
    end
    for key,value in pairs(sums) do
        out.fieldStatus[key]=known[key] and "available" or "unavailable"
        if known[key] then out[key]=value else out.totalsComplete=false end
    end
    if not out.available then out.status="unavailable" end
    return out,changed
end
function I.Capture(capturedAt)
    budget=8; seen={}
    local api=valid(C_Container,"table") and C_Container or {}
    if type(api.GetContainerNumSlots)~="function" or type(api.GetContainerItemInfo)~="function" then
        return {available=false,status="unsupported",capturedAt=capturedAt,scope="carried_bags",scanComplete=false,
            totalsComplete=false,bags={},entries={},fieldStatus={}}
    end
    local ids=bagIDs()
    local result
    for attempt=1,2 do
        local ok,value,changed=pcall(scan,api,ids,capturedAt)
        if not ok then
            return {available=false,status="unavailable",capturedAt=capturedAt,scope="carried_bags",scanComplete=false,
                totalsComplete=false,bags={},entries={},fieldStatus={},reason="Carried items could not be read"}
        end
        result=value
        if not changed then break end
    end
    for id in pairs(requests) do if not seen[id] then requests[id]=nil end end
    return result
end
