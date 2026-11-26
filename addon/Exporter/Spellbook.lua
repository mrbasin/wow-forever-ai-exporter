-- Learned player spellbook, read fresh at export time. No casting or UI actions.
-- Spell helpers adapted from MIT-licensed source; see LICENSE and THIRD_PARTY.md.
ExporterSpellbook = {}
local S=ExporterSpellbook
local requests,budget={},0

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
local function readTuple(fn,...)
    if type(fn)~="function" then return nil,"unsupported" end
    local ok,a,b,c,d=pcall(fn,...)
    if not ok then return nil,"api_error" end
    return {a,b,c,d},"available"
end
local function readTable(fn,...)
    local value,status=read(fn,...)
    if valid(value,"table") then return value,"available" end
    return nil,status=="available" and "unavailable" or status
end
local function text(value)
    if not valid(value,"string") then return nil end
    value=value:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")
        :gsub("|H.-|h(.-)|h","%1"):gsub("|T.-|t",""):gsub("|A.-|a","")
    return value~="" and value or nil
end
local function field(out,key,value,kind,status)
    out.fieldStatus=out.fieldStatus or {}
    if not status or status=="available" then
        status=not accessible(value) and "restricted" or (valid(value,kind) and "available" or "unavailable")
    end
    if status=="available" and kind=="string" then value=text(value); if not value then status="unavailable" end end
    out.fieldStatus[key]=status
    if status=="available" then out[key]=value end
end
local function sourceField(out,key,source,sourceKey,kind)
    local value,status=member(source,sourceKey or key); field(out,key,value,kind,status)
end
local function request(id)
    local fn=C_Spell and C_Spell.RequestLoadSpellData
    if not integer(id,1) or type(fn)~="function" then return "unavailable" end
    if ExporterDataRequests then return ExporterDataRequests.Request("spell",id,fn) end
    local now=read(GetTime)
    if not valid(now,"number") then return "unavailable" end
    local old=requests[id]
    if old and (old.failed or (old.attempts>=3 and now-old.at>=30)) then return "unavailable" end
    if budget>0 and (not old or (old.attempts<3 and now-old.at>=30)) then
        old={attempts=old and old.attempts+1 or 1,at=now}; requests[id]=old; budget=budget-1
        if not pcall(fn,id) then old.failed=true; return "unavailable" end
    end
    return "pending"
end
function S.OnEvent(event,id,success)
    if event=="SPELL_DATA_LOAD_RESULT" and integer(id,1) and success==false and requests[id] then requests[id].failed=true end
end

local function rankNumber(label,locale)
    if not text(label) then return nil end
    local format=text(SPELL_RANK)
    local function escape(value) return (value:gsub("(%W)","%%%1")) end
    if format then
        for _,token in ipairs({"%d","%1$d","%s","%1$s"}) do
            local first,last=format:find(token,1,true)
            if first then
                local number=tonumber(label:match("^"..escape(format:sub(1,first-1)).."(%d+)"..escape(format:sub(last+1)).."$"))
                if integer(number,1) then return number end
            end
        end
    end
    if locale=="enUS" or locale=="enGB" then
        local number=tonumber(label:match("^Rank (%d+)$"))
        if integer(number,1) then return number end
    end
end
local function arrayStatus(value)
    local count,highest=0,0
    for key in pairs(value) do
        if not integer(key,1) then return "partial" end
        count=count+1; highest=math.max(highest,key)
    end
    return count==highest and "available" or "partial"
end
local function tooltip(id)
    local info,status=readTable(C_TooltipInfo and C_TooltipInfo.GetSpellByID,id,false,true,true)
    local lines,lineStatus=member(info,"lines")
    if not info then return {},status end
    if not valid(lines,"table") then return {},lineStatus=="available" and "unavailable" or lineStatus end
    local out={}; status=arrayStatus(lines)
    for index,line in ipairs(lines) do
        if index>80 then status="partial"; break end
        if not valid(line,"table") then status="partial"
        else
            local left,leftStatus=member(line,"leftText")
            local right,rightStatus=member(line,"rightText")
            local cleanLeft,cleanRight=text(left),text(right)
            if cleanLeft or cleanRight then out[#out+1]={left=cleanLeft,right=cleanRight} end
            if leftStatus=="restricted" or rightStatus=="restricted" or leftStatus=="api_error" or rightStatus=="api_error"
                or (left~=nil and not valid(left,"string")) or (right~=nil and not valid(right,"string")) then status="partial" end
        end
    end
    if #out==0 and status=="available" then status="unavailable" end
    return out,status
end
local costFields={type="number",name="string",cost="number",minCost="number",costPercent="number",
    costPerSec="number",requiredAuraID="number",hasRequiredAura="boolean"}
local function powerCosts(id,passive)
    local costs,status=read(C_Spell and C_Spell.GetSpellPowerCost,id)
    local out={}
    if not valid(costs,"table") then
        if passive and costs==nil and (status=="unavailable" or status=="unsupported") then status="not_applicable"
        elseif status=="available" then status="unavailable" end
        return out,status
    end
    status=arrayStatus(costs)
    for _,cost in ipairs(costs) do
        if not valid(cost,"table") then status="partial"
        else
            local data={status="available",fieldStatus={}}
            for key,kind in pairs(costFields) do
                local value,valueStatus=member(cost,key); field(data,key,value,kind,valueStatus)
                if data.fieldStatus[key]~="available" and (key=="type" or key=="cost" or value~=nil or valueStatus~="unavailable") then data.status="partial" end
            end
            if data.type~=nil and not integer(data.type,0) then data.type=nil; data.fieldStatus.type="unavailable"; data.status="partial" end
            out[#out+1]=data
            if data.status~="available" then status="partial" end
        end
    end
    if #out==0 and status=="available" then status="no_cost" end
    return out,status
end
local function operational(out,key,value,status,passive)
    field(out,key,value,"number",status)
    if out[key] and out[key]<0 then out[key]=nil; out.fieldStatus[key]="unavailable" end
    if out[key]==nil and value==nil and passive and (status=="unavailable" or status=="unsupported") then
        out.fieldStatus[key]="not_applicable"
    end
end
local function complete(status)
    return status=="available" or status=="not_applicable" or status=="no_cost" or status=="not_reported" or status=="not_numeric"
end
local function details(api,id,baseID,lineIndex,slot,bookInfo,flyoutID,bank,locale)
    local spellAPI=valid(C_Spell,"table") and C_Spell or {}
    local info,infoStatus=readTable(spellAPI.GetSpellInfo,id)
    local out={spellID=id,learned=true,skillLineIndex=lineIndex,spellBookSlot=slot,flyoutID=flyoutID,fieldStatus={}}
    if integer(baseID,1) then out.baseSpellID=baseID end
    sourceField(out,"name",info,nil,"string")
    if not info then out.fieldStatus.name=infoStatus end
    local restrictedName=out.fieldStatus.name=="restricted"
    if not out.name then
        local value,status=read(spellAPI.GetSpellName,id); field(out,"name",value,"string",status)
        restrictedName=restrictedName or out.fieldStatus.name=="restricted"
    end
    if not out.name and bookInfo then
        sourceField(out,"name",bookInfo,nil,"string")
        restrictedName=restrictedName or out.fieldStatus.name=="restricted"
    end
    if not out.name and restrictedName then out.fieldStatus.name="restricted" end
    local passive,passiveStatus=read(spellAPI.IsSpellPassive,id)
    local bookPassive,bookPassiveStatus=member(bookInfo,"isPassive")
    if valid(bookPassive,"boolean") then passive,passiveStatus=bookPassive,bookPassiveStatus end
    field(out,"isPassive",passive,"boolean",passiveStatus)
    local subtext,subtextStatus=read(spellAPI.GetSpellSubtext,id)
    local bookSubtext,bookSubtextStatus=member(bookInfo,"subName")
    if not text(subtext) and text(bookSubtext) then subtext,subtextStatus=bookSubtext,bookSubtextStatus end
    out.rankText=text(subtext); out.rank=rankNumber(out.rankText,locale)
    local cached=read(spellAPI.IsSpellDataCached,id)
    out.rankStatus=out.rank and "available" or (out.rankText and "not_numeric")
        or (valid(subtext,"string") and subtext=="" and cached~=false and "not_reported")
        or (subtextStatus=="restricted" and "restricted") or "unavailable"
    local description,descriptionStatus=read(spellAPI.GetSpellDescription,id)
    field(out,"description",description,"string",descriptionStatus)
    local loading
    if cached==false or (not out.name and out.fieldStatus.name~="restricted")
        or (not out.description and out.fieldStatus.description~="restricted") then loading=request(id) end
    out.spellDataStatus=loading or (cached==true and "available") or "unavailable"
    out.nameStatus=out.name and "available" or (out.fieldStatus.name=="restricted" and "restricted") or loading or out.fieldStatus.name
    out.descriptionStatus=out.description and "available" or (out.fieldStatus.description=="restricted" and "restricted") or loading or out.fieldStatus.description
    if out.rankStatus=="unavailable" and loading then out.rankStatus=loading end
    if bookInfo then
        local lower,lowerStatus=read(api.IsSpellBookItemLowRank,slot,bank)
        field(out,"isLowerRank",lower,"boolean",lowerStatus)
    end
    out.tooltipLines,out.tooltipStatus=tooltip(id)
    out.powerCosts,out.powerCostsStatus=powerCosts(id,out.isPassive==true)
    for _,pair in ipairs({{"castTimeMs","castTime"},{"minRange","minRange"},{"maxRange","maxRange"}}) do
        local value,status=member(info,pair[2]); if not info then status=infoStatus end
        operational(out,pair[1],value,status,out.isPassive==true)
    end
    local baseCooldown,baseStatus=read(GetSpellBaseCooldown,id)
    operational(out,"baseCooldownMs",baseCooldown,baseStatus,out.isPassive==true)
    out.castTimeStatus=out.fieldStatus.castTimeMs; out.baseCooldownStatus=out.fieldStatus.baseCooldownMs
    local minStatus,maxStatus=out.fieldStatus.minRange,out.fieldStatus.maxRange
    out.rangeStatus=minStatus==maxStatus and minStatus or (complete(minStatus) and complete(maxStatus) and "available") or "partial"
    out.status="available"
    for _,status in ipairs({out.nameStatus,out.descriptionStatus,out.rankStatus,out.fieldStatus.isPassive,
        out.tooltipStatus,out.powerCostsStatus,out.castTimeStatus,out.rangeStatus,out.baseCooldownStatus}) do
        if not complete(status) then out.status="partial" end
    end
    if out.fieldStatus.isLowerRank=="restricted" or out.fieldStatus.isLowerRank=="api_error" then out.status="partial" end
    if loading and loading~="available" then out.status="partial" end
    return out
end
local function failed(capturedAt,status,reason)
    return {available=false,status=status,capturedAt=capturedAt,scope="learned_player_spellbook",
        scanComplete=false,entries={},skillLines={},spellCount=0,reason=reason}
end
local function capture(capturedAt)
    local api=valid(C_SpellBook,"table") and C_SpellBook or {}
    for _,name in ipairs({"GetNumSpellBookSkillLines","GetSpellBookSkillLineInfo","GetSpellBookItemInfo","IsSpellKnown"}) do
        if type(api[name])~="function" then return failed(capturedAt,"unsupported","Learned player spellbook APIs unavailable") end
    end
    local banks=member(Enum,"SpellBookSpellBank"); local bank=member(banks,"Player")
    local kinds=member(Enum,"SpellBookItemType"); local spellKind=member(kinds,"Spell"); local flyoutKind=member(kinds,"Flyout")
    if not integer(bank,0) or not integer(spellKind,0) or not integer(flyoutKind,0) then
        return failed(capturedAt,"unsupported","Spellbook enums unavailable")
    end
    local count=read(api.GetNumSpellBookSkillLines)
    if not integer(count,0,100) then return failed(capturedAt,"unavailable","Spellbook skill lines unavailable") end
    local locale=text(read(GetLocale))
    local out={available=true,status="available",capturedAt=capturedAt,scope="learned_player_spellbook",
        locale=locale,scanComplete=true,entries={},skillLines={}}
    local seen,readableLines,slotsScanned={},0,0
    local function incomplete() out.scanComplete=false; out.status="partial" end
    local function add(id,baseID,lineIndex,slot,bookInfo,flyoutID)
        if not integer(id,1) then incomplete(); return end
        local known=read(api.IsSpellKnown,id,bank)
        -- A learned base spell can be represented by an overriding ID in the book.
        if known~=true and integer(baseID,1) and baseID~=id then
            local baseKnown=read(api.IsSpellKnown,baseID,bank)
            if valid(baseKnown,"boolean") and baseKnown then known=true end
        end
        if not valid(known,"boolean") then incomplete(); return end
        if not known or seen[id] then return end
        seen[id]=true
        local entry=details(api,id,baseID,lineIndex,slot,bookInfo,flyoutID,bank,locale)
        out.entries[#out.entries+1]=entry
        if entry.status~="available" then out.status="partial" end
    end
    for lineIndex=1,count do
        local line=readTable(api.GetSpellBookSkillLineInfo,lineIndex)
        local offSpec,offSpecStatus=member(line,"offSpecID")
        if not line or (offSpecStatus~="unavailable" and not integer(offSpec,0)) then incomplete()
        elseif offSpec==nil or offSpec==0 then
            local offset=member(line,"itemIndexOffset"); local size=member(line,"numSpellBookItems")
            local lineOut={index=lineIndex}; sourceField(lineOut,"name",line,nil,"string")
            lineOut.status=lineOut.name and "available" or "partial"; out.skillLines[#out.skillLines+1]=lineOut
            if not lineOut.name then out.status="partial" end
            if not integer(offset,0) or not integer(size,0,2000) then incomplete()
            else
                readableLines=readableLines+1
                for slot=offset+1,offset+size do
                    slotsScanned=slotsScanned+1
                    if slotsScanned>2000 then incomplete(); break end
                    local item=readTable(api.GetSpellBookItemInfo,slot,bank)
                    local itemType=member(item,"itemType"); local isOffSpec=member(item,"isOffSpec")
                    if not item or not valid(isOffSpec,"boolean") or not integer(itemType,0) then incomplete()
                    elseif not isOffSpec and itemType==spellKind then
                        add(member(item,"spellID"),member(item,"actionID"),lineIndex,slot,item)
                    elseif not isOffSpec and itemType==flyoutKind then
                        local flyoutID=member(item,"actionID")
                        if not integer(flyoutID,1) then incomplete()
                        else
                            local flyout=readTuple(GetFlyoutInfo,flyoutID)
                            local size=flyout and flyout[3]; local known=flyout and flyout[4]
                            if not integer(size,0,200) or not valid(known,"boolean") then incomplete()
                            elseif known then
                                for index=1,size do
                                    local values=readTuple(GetFlyoutSlotInfo,flyoutID,index)
                                    local baseID=values and values[1]; local override=values and values[2]; local learned=values and values[3]
                                    if not valid(learned,"boolean") then incomplete()
                                    elseif learned then
                                        if not accessible(override) or (override~=nil and not integer(override,0)) then incomplete()
                                        else add(override and override>0 and override or baseID,baseID,lineIndex,slot,nil,flyoutID) end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        else readableLines=readableLines+1 end
        if slotsScanned>2000 then break end
    end
    table.sort(out.entries,function(a,b) return a.spellID<b.spellID end)
    local groups,namesComplete={},true
    for _,entry in ipairs(out.entries) do
        if entry.name then
            local group=groups[entry.name] or {complete=true}; groups[entry.name]=group
            if entry.rank then group.highest=math.max(group.highest or 0,entry.rank) else group.complete=false end
        else namesComplete=false end
    end
    for _,entry in ipairs(out.entries) do
        local group=entry.name and groups[entry.name]
        entry.highestLearnedRank=group and group.highest
        entry.highestLearnedRankStatus=group and group.highest and
            (group.complete and namesComplete and out.scanComplete and "available" or "partial") or "unavailable"
        if entry.rank and group then entry.isHighestLearnedRank=entry.rank==group.highest end
    end
    out.spellCount=#out.entries
    out.rankGrouping="Highest numeric rank observed among learned entries with the same localized spell name; unreported ranks are not guessed."
    if count>0 and readableLines==0 then out.available=false; out.status="unavailable" end
    return out
end
function S.Capture(capturedAt)
    budget=8
    local ok,result=pcall(capture,capturedAt)
    if ok then return result end
    return failed(capturedAt,"unavailable","This client could not provide spellbook data")
end
