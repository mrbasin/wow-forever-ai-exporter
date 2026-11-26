-- Equipped items only. Capture fresh slot identities on every export.
-- Item helpers adapted from MIT-licensed source; see LICENSE and THIRD_PARTY.md.
ExporterEquipment = {}
local Q=ExporterEquipment
local unpackValues=unpack or table.unpack
local slotNames={"Head","Neck","Shoulder","Shirt","Chest","Waist","Legs","Feet","Wrist","Hands",
    "Finger 1","Finger 2","Trinket 1","Trinket 2","Back","Main Hand","Off Hand","Ranged","Tabard"}
local requests={}
local budget,seen

local function accessible(value)
    local ok,result=pcall(function()
        return not (issecretvalue and issecretvalue(value)) and (not canaccessvalue or canaccessvalue(value))
    end)
    return ok and result
end
local function valid(value,kind)
    if not accessible(value) or type(value)~=kind then return false end
    if kind=="number" then return value==value and value~=math.huge and value~=-math.huge end
    return true
end
local function text(value)
    if not valid(value,"string") or value=="" then return nil end
    return value:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")
        :gsub("|H.-|h(.-)|h","%1"):gsub("|T.-|t",""):gsub("|A.-|a","")
end
local function read(fn,...)
    if type(fn)~="function" then return nil end
    local values={pcall(fn,...)}
    if values[1] then return unpackValues(values,2,20) end
end
local function itemAPI(name)
    return (C_Item and C_Item[name]) or _G[name]
end
local function idFromLink(link)
    return valid(link,"string") and tonumber(link:match("item:(%d+)")) or nil
end
local function request(id)
    local fn=itemAPI("RequestLoadItemDataByID")
    if not id or type(fn)~="function" then return "unavailable" end
    seen[id]=true
    if ExporterDataRequests then return ExporterDataRequests.Request("item",id,fn) end
    local now=GetTime()
    local old=requests[id]
    if old and (old.failed or (old.attempts>=3 and now-old.at>=30)) then return "unavailable" end
    if budget>0 and (not old or (old.attempts<3 and now-old.at>=30)) then
        old={attempts=old and old.attempts+1 or 1,at=now}
        requests[id]=old; budget=budget-1
        if not pcall(fn,id) then old.failed=true; return "unavailable" end
    end
    return "pending"
end
local function field(out,key,value,kind)
    local status=not accessible(value) and "restricted" or (valid(value,kind) and (kind~="string" or value~="") and "available" or "unavailable")
    out.fieldStatus[key]=status
    if status=="available" then out[key]=kind=="string" and text(value) or value end
end
local function details(slot,id,link)
    local out={slotID=slot,slotName=slotNames[slot],empty=false,itemID=id,link=link,fieldStatus={}}
    local values={read(itemAPI("GetItemInfo"),link or id)}
    for _,entry in ipairs({{"name",1,"string"},{"quality",3,"number"},{"baseItemLevel",4,"number"},
        {"requiredLevel",5,"number"},{"itemType",6,"string"},{"itemSubType",7,"string"},
        {"equipLocation",9,"string"},{"classID",12,"number"},{"subClassID",13,"number"}}) do
        field(out,entry[1],values[entry[2]],entry[3])
    end
    field(out,"itemLevel",read(itemAPI("GetDetailedItemLevelInfo"),link or id),"number")
    if out.name then out.nameStatus="available" else out.nameStatus=request(id) end

    out.stats={}; out.statStatus={}; out.statsStatus="unavailable"
    -- Use the full instance link: suffixes, enchants and gems may differ by item.
    local stats=link and read(itemAPI("GetItemStats"),link)
    if valid(stats,"table") then
        out.statsStatus="available"
        for key,value in pairs(stats) do
            if valid(key,"string") then
                local status=not accessible(value) and "restricted" or (valid(value,"number") and "available" or "unavailable")
                out.statStatus[key]=status
                if status=="available" then out.stats[key]=value else out.statsStatus="partial" end
            else out.statsStatus="partial" end
        end
    elseif not accessible(stats) then out.statsStatus="restricted" end
    if out.statsStatus=="unavailable" then out.itemDataStatus=request(id) end

    out.enhancements={sockets={},emptySockets={},status=link and "available" or "unavailable"}
    out.enhancements.enchantID=link and tonumber(link:match("item:%d+:(%d*)")) or nil
    for key,value in pairs(out.stats) do
        if key:match("^EMPTY_SOCKET_") then out.enhancements.emptySockets[key]=value end
    end
    if link then
        -- Gem IDs in the instance link remain useful when their names are uncached.
        local encoded=link:match("item:([%d:%-]+)") or ""
        local parts={}; for part in (encoded..":"):gmatch("(.-):") do parts[#parts+1]=part end
        for index=1,4 do
            local gemName,gemLink=read(itemAPI("GetItemGem"),link,index)
            if not valid(gemLink,"string") then gemLink=nil end
            local gemID=idFromLink(gemLink) or tonumber(parts[index+2])
            if gemID and gemID>0 then
                local name=text(gemName)
                local status=name and "available" or request(gemID)
                out.enhancements.sockets[#out.enhancements.sockets+1]={index=index,itemID=gemID,name=name,link=gemLink,nameStatus=status}
                if not name then out.enhancements.status="partial" end
            end
        end
    end

    out.tooltipLines={}; out.tooltipStatus="unavailable"
    local tooltip=read(C_TooltipInfo and C_TooltipInfo.GetInventoryItem,"player",slot)
    if valid(tooltip,"table") and valid(tooltip.lines,"table") then
        out.tooltipStatus="available"
        for i,line in ipairs(tooltip.lines) do
            if i>80 then out.tooltipStatus="partial"; break end
            if valid(line,"table") then
                local left,right=text(line.leftText),text(line.rightText)
                if left or right then out.tooltipLines[#out.tooltipLines+1]={left=left,right=right} end
                if not accessible(line.leftText) or not accessible(line.rightText) then out.tooltipStatus="partial" end
            else out.tooltipStatus="partial" end
        end
        if #out.tooltipLines==0 then out.tooltipStatus="unavailable" end
    end
    out.status=out.name and link and out.statsStatus=="available" and out.tooltipStatus=="available"
        and out.enhancements.status=="available" and "available" or "partial"
    for _,status in pairs(out.fieldStatus) do if status~="available" then out.status="partial" end end
    return out
end
local function captureSlot(slot)
    local out={slotID=slot,slotName=slotNames[slot],status="unavailable"}
    local idOK,id=pcall(GetInventoryItemID,"player",slot)
    local linkOK,link=pcall(GetInventoryItemLink,"player",slot)
    if not idOK or not linkOK then return out end
    if not accessible(id) or not accessible(link) then out.status="restricted"; return out end
    if id==nil and link==nil then out.empty=true; out.status="empty"; return out end
    if not valid(link,"string") or link=="" then link=nil end
    if not valid(id,"number") or id<=0 then id=idFromLink(link) end
    if not id then return out end
    seen[id]=true
    return details(slot,id,link)
end
function Q.Capture(capturedAt)
    local out={available=false,status="unavailable",capturedAt=capturedAt,scope="equipped_items",
        slots={},equippedCount=0,scanComplete=true}
    if type(GetInventoryItemID)~="function" or type(GetInventoryItemLink)~="function" then
        out.status="unsupported"; out.scanComplete=false; return out
    end
    budget=8; seen={}
    local known,complete=0,0
    for slot=1,19 do
        local ok,data=pcall(captureSlot,slot)
        if not ok then data={slotID=slot,slotName=slotNames[slot],status="unavailable"} end
        out.slots[#out.slots+1]=data
        if data.empty~=nil then known=known+1 else out.scanComplete=false end
        if data.empty==false then out.equippedCount=out.equippedCount+1 end
        if data.status=="available" or data.status=="empty" then complete=complete+1 end
    end
    for id in pairs(requests) do if not seen[id] then requests[id]=nil end end
    out.available=known>0
    out.status=complete==19 and "available" or (known>0 and "partial" or "unavailable")
    return out
end
