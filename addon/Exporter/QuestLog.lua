-- Read-only active quests and current client completion flags. Never selects quests.
-- Collection/retry helpers adapted from MIT-licensed source; see THIRD_PARTY.md.
ExporterQuestLog = {}
local Q=ExporterQuestLog
local MAX_ROWS,MAX_OBJECTIVES,MAX_REWARDS,MAX_HISTORY=1000,128,256,100000
local revision,budget,historyCursor=0,0,1
local titles,requests,relevant={},{},{}
local cacheLocale
local unpackValues=unpack or table.unpack

local function accessible(value)
    local ok,result=pcall(function()
        return not (issecretvalue and issecretvalue(value)) and (not canaccessvalue or canaccessvalue(value))
    end)
    return ok and result
end
local function valid(value,kind)
    if not accessible(value) then return false end
    if kind=="texture" then return valid(value,"number") or valid(value,"string") end
    if type(value)~=kind then return false end
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
    local values=pack(pcall(fn,...))
    if not values[1] then return nil,"api_error" end
    return pack(unpackValues(values,2,values.n)),"available"
end
local function text(value,allowEmpty)
    if not valid(value,"string") then return nil end
    value=value:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")
        :gsub("|H.-|h(.-)|h","%1"):gsub("|T.-|t",""):gsub("|A.-|a","")
    return (allowEmpty or value~="") and value or nil
end
local function field(out,key,value,kind,status,allowEmpty)
    out.fieldStatus=out.fieldStatus or {}
    if not status or status=="available" then
        status=not accessible(value) and "restricted" or (valid(value,kind) and "available" or "unavailable")
    end
    if status=="available" and kind=="string" then value=text(value,allowEmpty); if value==nil then status="unavailable" end end
    out.fieldStatus[key]=status
    if status=="available" then out[key]=value end
end
local function fields(source,spec,required)
    local out={status="available",fieldStatus={}}
    for key,kind in pairs(spec) do
        local value,status=member(source,key); field(out,key,value,kind,status)
        if out.fieldStatus[key]~="available" and (value~=nil or status~="unavailable" or (required and required[key])) then out.status="partial" end
    end
    return out
end
local function array(value,limit)
    if not valid(value,"table") then return nil,accessible(value) and "unavailable" or "restricted" end
    local count,highest=0,0
    for key in pairs(value) do
        if not integer(key,1,limit) then return nil,"unavailable" end
        count=count+1; highest=math.max(highest,key)
        if count>limit then return nil,"unavailable" end
    end
    if count~=highest then return nil,"unavailable" end
    return count,"available"
end
local function apiTable()
    return valid(C_QuestLog,"table") and C_QuestLog or {}
end
local function requestStatus(id)
    local old=requests[id]
    local now=read(GetTime)
    if type(apiTable().RequestLoadQuestByID)~="function" or not valid(now,"number") then return "unavailable" end
    if old and (old.failed or (old.attempts>=3 and now-old.at>=30)) then return "unavailable" end
    return "pending"
end
local function request(id)
    if not integer(id,1) or requestStatus(id)=="unavailable" then return "unavailable",false end
    local now=read(GetTime); local old=requests[id]
    if budget>0 and (not old or (old.attempts<3 and now-old.at>=30)) then
        old={attempts=old and old.attempts+1 or 1,at=now}; requests[id]=old; budget=budget-1
        if not pcall(apiTable().RequestLoadQuestByID,id) then old.failed=true; return "unavailable",true end
        return requestStatus(id),true
    end
    return requestStatus(id),false
end
function Q.OnEvent(event,id,success)
    if event=="QUEST_LOG_UPDATE" then revision=revision+1
    elseif event=="QUEST_DATA_LOAD_RESULT" and integer(id,1) and relevant[id] and requests[id] and success==false then
        requests[id].failed=true
    end
end
local function titleFor(id,fallback)
    relevant[id]=true
    local title=text(fallback)
    if title then titles[id]=title; return title,"available" end
    if titles[id] then return titles[id],"available" end
    local value,status=read(apiTable().GetTitleForQuestID,id)
    title=text(value)
    if title then titles[id]=title; return title,"available" end
    return nil,status=="available" and "unavailable" or status
end
local function activeFailure(stamp,status,reason)
    return {available=false,status=status,capturedAt=stamp,scanComplete=false,includesStoryText=false,
        entries={},headers={},questCount=0,reason=reason}
end
local function historyFailure(stamp,status,reason)
    return {available=false,status=status,capturedAt=stamp,scanComplete=false,questIDs={},titlesByQuestID={},
        pendingTitleIDs={},unavailableTitleIDs={},questCount=0,titleCount=0,reason=reason}
end

local function enumerateActive()
    local api=apiTable()
    if type(api.GetNumQuestLogEntries)~="function" or type(api.GetInfo)~="function" then return nil,"unsupported" end
    local counts,status=tuple(api.GetNumQuestLogEntries)
    local count=counts and counts[1]; local reported=counts and counts[2]
    if not integer(count,0,MAX_ROWS) then return nil,status=="available" and "unavailable" or status end
    local out={rows={},headers={},complete=true,signature={tostring(count)},reportedQuestCount=nil}
    if integer(reported,0,MAX_ROWS) then out.reportedQuestCount=reported else out.complete=false end
    out.signature[#out.signature+1]=tostring(out.reportedQuestCount)
    local headerIndex,seen=nil,{}
    for index=1,count do
        local info,infoStatus=read(api.GetInfo,index)
        local isHeader,headerStatus=member(info,"isHeader")
        if not valid(info,"table") or not valid(isHeader,"boolean") then
            out.complete=false; out.signature[#out.signature+1]="?:"..index..":"..infoStatus..":"..headerStatus
        elseif isHeader then
            local header=fields(info,{title="string",isCollapsed="boolean"},{title=true,isCollapsed=true})
            header.index=#out.headers+1; header.questLogIndex=index
            out.headers[#out.headers+1]=header; headerIndex=header.index
            local name=header.title or ""
            out.signature[#out.signature+1]="H:"..index..":"..#name..":"..name..":"..tostring(header.isCollapsed)
        else
            local id=member(info,"questID")
            if not integer(id,1) or seen[id] then
                out.complete=false; out.signature[#out.signature+1]="Q?:"..index
            else
                seen[id]=true
                out.rows[#out.rows+1]={questID=id,questLogIndex=index,headerIndex=headerIndex,info=info}
                out.signature[#out.signature+1]="Q:"..index..":"..id
            end
        end
    end
    if out.reportedQuestCount~=nil and #out.rows~=out.reportedQuestCount then out.complete=false end
    out.signature=table.concat(out.signature,"|")
    return out,"available"
end
local function objectiveData(id)
    local value,status=read(apiTable().GetQuestObjectives,id)
    if value==nil then return {},status end
    local count,listStatus=array(value,MAX_OBJECTIVES)
    if not count then return {},listStatus end
    local out={}; status="available"
    for index=1,count do
        local item=fields(value[index],{text="string",type="string",finished="boolean",numFulfilled="number",numRequired="number",objectiveType="number"},
            {text=true,type=true,finished=true,numFulfilled=true,numRequired=true})
        for _,key in ipairs({"numFulfilled","numRequired"}) do
            if item[key]~=nil and item[key]<0 then item[key]=nil; item.fieldStatus[key]="unavailable"; item.status="partial" end
        end
        item.index=index
        out[#out+1]=item
        if item.status~="available" then status="partial" end
    end
    return out,status
end
local function rewardItems(id,choice)
    local count,status
    if choice then count,status=read(GetNumQuestLogChoices,id,false)
    else count,status=read(GetNumQuestLogRewards,id) end
    local out={}
    if not integer(count,0,MAX_REWARDS) then return out,status=="available" and "unavailable" or status end
    status="available"
    for index=1,count do
        local infoFn=GetQuestLogRewardInfo
        if choice then infoFn=GetQuestLogChoiceInfo end
        local values,itemStatus=tuple(infoFn,index,id)
        local item={index=index,status="available",fieldStatus={}}
        local spec={{"name","string"},{"texture","texture"},{"count","number"},{"quality","number"},{"isUsable","boolean"},{"itemID","number"}}
        if not choice then spec[#spec+1]={"itemLevel","number"} end
        for position,entry in ipairs(spec) do
            local value=values and values[position]
            field(item,entry[1],value,entry[2],itemStatus)
            if item.fieldStatus[entry[1]]~="available" then item.status="partial" end
        end
        for key,minimum in pairs({itemID=1,count=0,quality=0,itemLevel=0}) do
            if item[key]~=nil and not integer(item[key],minimum) then item[key]=nil; item.fieldStatus[key]="unavailable"; item.status="partial" end
        end
        out[#out+1]=item
        if item.status~="available" then status="partial" end
    end
    return out,status
end
local currencyFields={currencyID="number",name="string",texture="texture",quality="number",baseRewardAmount="number",
    bonusRewardAmount="number",totalRewardAmount="number",questRewardContextFlags="number"}
local spellFields={texture="texture",name="string",garrFollowerID="number",isTradeskill="boolean",isSpellLearned="boolean",
    hideSpellLearnText="boolean",isBoostSpell="boolean",genericUnlock="boolean",type="number"}
local function rewardList(id,fn,hasFn,spec,required)
    local value,status=read(fn,id)
    if value==nil then
        local has=read(hasFn,id)
        if status=="unavailable" and valid(has,"boolean") and has==false then return {},"available" end
        return {},status
    end
    local count,listStatus=array(value,MAX_REWARDS)
    if not count then return {},listStatus end
    local out={}; status="available"
    for index=1,count do
        local item=fields(value[index],spec,required)
        for _,key in ipairs({"currencyID","factionID"}) do
            if item[key]~=nil and not integer(item[key],1) then item[key]=nil; item.fieldStatus[key]="unavailable"; item.status="partial" end
        end
        out[#out+1]=item
        if item.status~="available" then status="partial" end
    end
    return out,status
end
local function rewardSpells(id,api)
    local ids,status=read(api.GetQuestRewardSpells,id)
    if ids==nil then
        local has=read(api.HasQuestRewardSpells,id)
        if status=="unavailable" and valid(has,"boolean") and has==false then return {},"available" end
        return {},status
    end
    local count,listStatus=array(ids,MAX_REWARDS)
    if not count then return {},listStatus end
    local out={}; status="available"
    for index=1,count do
        local spellID=ids[index]
        if not integer(spellID,1) then status="partial"
        else
            local info,infoStatus=read(api.GetQuestRewardSpellInfo,id,spellID)
            local item=fields(info,spellFields,{name=true,isSpellLearned=true})
            item.spellID=spellID
            if infoStatus~="available" then item.status=infoStatus end
            out[#out+1]=item
            if item.status~="available" then status="partial" end
        end
    end
    return out,status
end
local function rewards(id)
    local api=valid(C_QuestInfoSystem,"table") and C_QuestInfoSystem or {}
    local out={status="available",fieldStatus={}}
    local xp,xpStatus=read(GetQuestLogRewardXP,id); field(out,"xp",xp,"number",xpStatus)
    local money,moneyStatus=read(GetQuestLogRewardMoney,id); field(out,"money",money,"number",moneyStatus)
    out.items,out.itemsStatus=rewardItems(id,false)
    out.choices,out.choicesStatus=rewardItems(id,true)
    out.currencies,out.currenciesStatus=rewardList(id,api.GetQuestRewardCurrencies,api.HasQuestRewardCurrencies,currencyFields,
        {currencyID=true,name=true,texture=true,quality=true,baseRewardAmount=true,bonusRewardAmount=true,totalRewardAmount=true})
    out.spells,out.spellsStatus=rewardSpells(id,api)
    out.majorFactionReputation,out.majorFactionReputationStatus=rewardList(id,apiTable().GetQuestLogMajorFactionReputationRewards,nil,
        {factionID="number",rewardAmount="number"},{factionID=true,rewardAmount=true})
    for _,status in pairs(out.fieldStatus) do if status~="available" then out.status="partial" end end
    for _,status in ipairs({out.itemsStatus,out.choicesStatus,out.currenciesStatus,out.spellsStatus,out.majorFactionReputationStatus}) do
        if status~="available" then out.status="partial" end
    end
    return out
end
local function questDetails(row)
    local id,info=row.questID,row.info
    local out=fields(info,{level="number",difficultyLevel="number",suggestedGroup="number",questClassification="number"},{level=true})
    out.questID=id; out.questLogIndex=row.questLogIndex; out.headerIndex=row.headerIndex
    local title,titleStatus=titleFor(id,member(info,"title"))
    field(out,"title",title,"string",titleStatus)
    local questText,questTextStatus=tuple(GetQuestLogQuestText,row.questLogIndex)
    -- The first return is narrative story text; retain only the objective summary.
    field(out,"objectiveSummary",questText and questText[2],"string",questTextStatus,true)
    out.objectives,out.objectivesStatus=objectiveData(id)
    local api=apiTable()
    local tag,tagStatus=read(api.GetQuestTagInfo,id)
    if tag==nil and tagStatus=="unavailable" then out.tagStatus="not_applicable"
    elseif valid(tag,"table") then
        out.tag=fields(tag,{tagID="number",tagName="string",worldQuestType="number",quality="number",tradeskillLineID="number",
            isElite="boolean",displayExpiration="boolean"},{tagID=true,tagName=true})
        out.tagStatus=out.tag.status
    else out.tagStatus=tagStatus=="available" and "unavailable" or tagStatus end
    out.flags=fields(info,{isTask="boolean",isBounty="boolean",isStory="boolean",isHidden="boolean",isAutoComplete="boolean",frequency="number"})
    for key,fn in pairs({isComplete=api.IsComplete,isFailed=api.IsFailed,isRepeatable=api.IsRepeatableQuest,readyForTurnIn=api.ReadyForTurnIn}) do
        local value,status=read(fn,id); field(out.flags,key,value,"boolean",status)
        if out.flags.fieldStatus[key]~="available" then out.flags.status="partial" end
    end
    -- A missing API must still produce an explicit field status (nil table entries disappear).
    for _,key in ipairs({"isComplete","isFailed","isRepeatable","readyForTurnIn"}) do
        if not out.flags.fieldStatus[key] then out.flags.fieldStatus[key]="unsupported"; out.flags.status="partial" end
    end
    local watchType,watchStatus=read(api.GetQuestWatchType,id)
    if integer(watchType,0,1) then
        field(out.flags,"watchType",watchType,"number","available")
        field(out.flags,"isWatched",true,"boolean","available")
    elseif watchType==nil and watchStatus=="unavailable" then
        out.flags.fieldStatus.watchType="not_applicable"
        field(out.flags,"isWatched",false,"boolean","available")
    else
        field(out.flags,"watchType",nil,"number",watchStatus=="available" and "unavailable" or watchStatus)
        field(out.flags,"isWatched",nil,"boolean",watchStatus=="available" and "unavailable" or watchStatus)
        out.flags.status="partial"
    end
    out.rewards=rewards(id)
    local needsLoad=not out.title or out.fieldStatus.objectiveSummary=="unavailable"
        or out.objectivesStatus=="unavailable"
    if needsLoad then out.questDataStatus=request(id) end
    out.titleStatus=out.title and "available" or (titleStatus=="restricted" and "restricted") or out.questDataStatus or titleStatus
    for _,key in ipairs({"title","objectiveSummary"}) do if out.fieldStatus[key]~="available" then out.status="partial" end end
    if out.objectivesStatus~="available" or out.flags.status~="available" or out.rewards.status~="available" then out.status="partial" end
    if out.tagStatus~="available" and out.tagStatus~="not_applicable" then out.status="partial" end
    return out
end
local function captureActive(stamp,attemptLimit)
    for attempt=1,attemptLimit do
        local beforeRevision=revision
        local before,status=enumerateActive()
        if not before then return activeFailure(stamp,status,"Active quest enumeration unavailable or exceeds bounds") end
        local out={available=true,status=before.complete and "available" or "partial",capturedAt=stamp,
            scanComplete=before.complete,includesStoryText=false,entries={},headers=before.headers,
            questCount=0,reportedQuestCount=before.reportedQuestCount}
        for _,header in ipairs(out.headers) do if header.status~="available" then out.status="partial" end end
        for _,row in ipairs(before.rows) do
            local ok,entry=pcall(questDetails,row)
            if not ok then entry={questID=row.questID,questLogIndex=row.questLogIndex,headerIndex=row.headerIndex,status="unavailable",reason="Quest details could not be read",objectives={}} end
            out.entries[#out.entries+1]=entry
            if entry.status~="available" then out.status="partial" end
        end
        out.questCount=#out.entries
        local after=enumerateActive()
        if after and before.signature==after.signature and beforeRevision==revision then
            return out,{attempts=attempt,signature=before.signature,revision=beforeRevision}
        end
    end
    return activeFailure(stamp,"pending","Quest log changed while reading; no mixed snapshot was retained")
end

local function completedIDs()
    local ids,status=read(apiTable().GetAllCompletedQuestIDs)
    if ids==nil then return nil,status end
    local count,listStatus=array(ids,MAX_HISTORY)
    if not count then return nil,listStatus end
    local out,seen={},{}
    for index=1,count do
        local id=ids[index]
        if not integer(id,1) then return nil,accessible(id) and "unavailable" or "restricted" end
        if not seen[id] then seen[id]=true; out[#out+1]=id end
    end
    table.sort(out)
    return out,"available"
end
local function sameIDs(left,right)
    if not right or #left~=#right then return false end
    for index,id in ipairs(left) do if id~=right[index] then return false end end
    return true
end
local function captureHistory(stamp,attemptLimit)
    for attempt=1,attemptLimit do
        local beforeRevision=revision
        local ids,status=completedIDs()
        if not ids then return historyFailure(stamp,status,"Completed quest flags unavailable or invalid") end
        local out={available=true,status="available",capturedAt=stamp,scanComplete=true,questIDs=ids,titlesByQuestID={},
            pendingTitleIDs={},unavailableTitleIDs={},questCount=#ids,titleCount=0}
        local missing,missingStatus={},{}
        for _,id in ipairs(ids) do
            local title,titleStatus=titleFor(id)
            if title then out.titlesByQuestID[tostring(id)]=title; out.titleCount=out.titleCount+1
            else missing[#missing+1]=id; missingStatus[id]=titleStatus end
        end
        if #missing>0 then
            out.status="partial"
            local start=(historyCursor-1)%#missing+1
            local nextCursor=start
            for offset=0,#missing-1 do
                if budget<=0 then break end
                local index=(start+offset-1)%#missing+1
                local id=missing[index]
                if missingStatus[id]~="restricted" then
                    local _,requested=request(id)
                    if requested then nextCursor=index%#missing+1 end
                end
            end
            historyCursor=nextCursor
            for _,id in ipairs(missing) do
                if missingStatus[id]~="restricted" and requestStatus(id)=="pending" then out.pendingTitleIDs[#out.pendingTitleIDs+1]=id
                else out.unavailableTitleIDs[#out.unavailableTitleIDs+1]=id end
            end
        end
        local after=completedIDs()
        if sameIDs(ids,after) and beforeRevision==revision then return out,{attempts=attempt,revision=beforeRevision} end
    end
    return historyFailure(stamp,"pending","Completed quest flags changed while reading; no mixed snapshot was retained")
end
function Q.Capture(capturedAt)
    local previousRelevant=relevant
    budget=16; relevant={}
    local locale=read(GetLocale)
    if valid(locale,"string") and locale~=cacheLocale then titles={}; cacheLocale=locale end
    local ok,active,activeRead=pcall(captureActive,capturedAt,2)
    if not ok then active=activeFailure(capturedAt,"unavailable","Active quest data could not be read") end
    local historyOK,history,historyRead=pcall(captureHistory,capturedAt,2)
    if not historyOK then history=historyFailure(capturedAt,"unavailable","Completed quest data could not be read") end
    local function activeStable()
        if not activeRead then return true end
        local checked,current=pcall(enumerateActive)
        return checked and current and current.signature==activeRead.signature and revision==activeRead.revision
    end
    local function historyStable()
        if not historyRead then return true end
        local checked,current=pcall(completedIDs)
        return checked and sameIDs(history.questIDs,current) and revision==historyRead.revision
    end
    -- History reads or data-load events can invalidate an active scan that finished earlier.
    if not activeStable() and activeRead.attempts<2 then
        local retryOK,retry,retryRead=pcall(captureActive,capturedAt,1)
        active=retryOK and retry or activeFailure(capturedAt,"unavailable","Active quest data could not be read")
        activeRead=retryRead
        if activeRead then activeRead.attempts=2 end
    end
    if not historyStable() and historyRead.attempts<2 then
        local retryOK,retry,retryRead=pcall(captureHistory,capturedAt,1)
        history=retryOK and retry or historyFailure(capturedAt,"unavailable","Completed quest data could not be read")
        historyRead=retryRead
        if historyRead then historyRead.attempts=2 end
    end
    local stableHistory=historyStable()
    local stableActive=activeStable()
    if activeRead and (not stableActive or revision~=activeRead.revision) then
        active=activeFailure(capturedAt,"pending","Quest log changed during capture; no mixed snapshot was retained")
    end
    if historyRead and (not stableHistory or revision~=historyRead.revision) then
        history=historyFailure(capturedAt,"pending","Completed quest flags changed during capture; no mixed snapshot was retained")
    end
    -- Retain only accepted IDs; incomplete scans cannot prove prior IDs were removed.
    local accepted={}
    for _,entry in ipairs(active.entries) do accepted[entry.questID]=true end
    for _,id in ipairs(history.questIDs) do accepted[id]=true end
    if not active.scanComplete or not history.scanComplete then
        for id in pairs(previousRelevant) do accepted[id]=true end
    end
    relevant=accepted
    for id in pairs(titles) do if not relevant[id] then titles[id]=nil end end
    for id in pairs(requests) do if not relevant[id] then requests[id]=nil end end
    local available=active.available or history.available
    local status=active.status=="available" and history.status=="available" and "available" or (available and "partial" or "unavailable")
    if active.status=="unsupported" and history.status=="unsupported" then status="unsupported" end
    return {available=available,status=status,capturedAt=capturedAt,active=active,completedHistory=history}
end
