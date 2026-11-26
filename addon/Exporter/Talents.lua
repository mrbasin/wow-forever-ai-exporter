-- Applied talents only. Read fresh on every export; never apply preview changes.
-- Talent helpers adapted from MIT-licensed source; see LICENSE and THIRD_PARTY.md.
ExporterTalents = {}
local T=ExporterTalents
local requests,confirmed={},nil
local budget=0

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
local function clean(value,kind)
    if not accessible(value) then return nil,"restricted" end
    if not valid(value,kind) then return nil,"unavailable" end
    if kind=="string" then
        value=value:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")
            :gsub("|H.-|h(.-)|h","%1"):gsub("|T.-|t",""):gsub("|A.-|a","")
        if value=="" then return nil,"unavailable" end
    end
    return value,"available"
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
local function readTable(fn,...)
    local value,status=read(fn,...)
    if valid(value,"table") then return value,"available" end
    return nil,status=="available" and "unavailable" or status
end
local function field(out,key,value,kind,status)
    local cleaned,state=clean(value,kind)
    out.fieldStatus=out.fieldStatus or {}
    out.fieldStatus[key]=status and status~="available" and status or state
    if out.fieldStatus[key]=="available" then out[key]=cleaned end
end
local function fields(source,spec,required)
    local out={fieldStatus={},status="available"}
    for key,kind in pairs(spec) do
        local value,status=member(source,key)
        field(out,key,value,kind,status)
        -- Optional absent scalars are normal; malformed or restricted values are not.
        if out.fieldStatus[key]~="available" and (value~=nil or status~="unavailable" or (required and required[key])) then
            out.status="partial"
        end
    end
    return out
end
local function clone(value)
    if type(value)~="table" then return value end
    local out={}; for key,item in pairs(value) do out[key]=clone(item) end; return out
end
local function id(value)
    return valid(value,"number") and value>0 and value==math.floor(value)
end
local function rank(value)
    return valid(value,"number") and value>=0 and value==math.floor(value)
end
local function numberList(value,status)
    local out={}
    if not valid(value,"table") then return out,status=="available" and "unavailable" or status end
    status="available"
    for _,item in ipairs(value) do
        if id(item) then out[#out+1]=item else status="partial" end
    end
    return out,status
end
local function request(spellID)
    local fn=C_Spell and C_Spell.RequestLoadSpellData
    if not id(spellID) or type(fn)~="function" then return "unavailable" end
    if ExporterDataRequests then return ExporterDataRequests.Request("spell",spellID,fn) end
    local now=read(GetTime)
    if not valid(now,"number") then return "unavailable" end
    local old=requests[spellID]
    if old and (old.failed or (old.attempts>=3 and now-old.at>=30)) then return "unavailable" end
    if budget>0 and (not old or (old.attempts<3 and now-old.at>=30)) then
        old={attempts=old and old.attempts+1 or 1,at=now}
        requests[spellID]=old; budget=budget-1
        if not pcall(fn,spellID) then old.failed=true; return "unavailable" end
    end
    return "pending"
end
function T.OnEvent(event,spellID,success)
    if event=="SPELL_DATA_LOAD_RESULT" and id(spellID) and success==false and requests[spellID] then
        requests[spellID].failed=true
    end
end

local conditionFields={isMet="boolean",isGate="boolean",isSufficient="boolean",type="number",
    playerLevel="number",spentAmountRequired="number",traitCurrencyID="number",questID="number",
    achievementID="number",ranksGranted="number",tooltipFormat="string"}
local function conditions(api,config,value,status)
    local ids; ids,status=numberList(value,status)
    local out={}
    for _,conditionID in ipairs(ids) do
        local info,infoStatus=readTable(api.GetConditionInfo,config,conditionID)
        local data=fields(info,conditionFields,{isMet=true,isGate=true,isSufficient=true,type=true})
        data.id=conditionID; data.available=info~=nil
        if infoStatus~="available" then data.status=infoStatus end
        out[#out+1]=data
        if data.status~="available" then status="partial" end
    end
    return out,status
end
local function entryDetails(api,config,entryID)
    local info,infoStatus=readTable(api.GetEntryInfo,config,entryID)
    local out=fields(info,{definitionID="number",subTreeID="number",maxRanks="number",isAvailable="boolean",type="number"},{maxRanks=true})
    out.id=entryID; out.status=info and out.status or infoStatus
    out.conditions,out.conditionsStatus=conditions(api,config,member(info,"conditionIDs"))
    local definition,definitionStatus
    if id(out.definitionID) then definition,definitionStatus=readTable(api.GetDefinitionInfo,out.definitionID)
    else definitionStatus="unavailable" end
    out.definitionStatus=definitionStatus
    local spellID,spellIDStatus=member(definition,"spellID")
    if spellIDStatus=="available" and not id(spellID) then spellIDStatus="unavailable" end
    field(out,"spellID",spellID,"number",spellIDStatus)
    if spellIDStatus=="restricted" or (spellID~=nil and not out.spellID) then out.status="partial" end
    local spell,spellStatus
    if out.spellID then spell,spellStatus=readTable(C_Spell and C_Spell.GetSpellInfo,out.spellID)
    else spellStatus="unavailable" end
    out.spellInfoStatus=spellStatus
    local name,nameStatus=member(definition,"overrideName")
    if nameStatus~="restricted" and not clean(name,"string") then
        name,nameStatus=member(spell,"name")
        if not spell then nameStatus=spellStatus end
    end
    local description,descriptionStatus=member(definition,"overrideDescription")
    if descriptionStatus~="restricted" and not clean(description,"string") then
        if out.spellID then description,descriptionStatus=read(C_Spell and C_Spell.GetSpellDescription,out.spellID)
        else descriptionStatus="unavailable" end
    end
    if not definition and id(out.subTreeID) then
        local subtree,subtreeStatus=readTable(api.GetSubTreeInfo,config,out.subTreeID)
        out.subTreeStatus=subtreeStatus
        name,nameStatus=member(subtree,"name"); description,descriptionStatus=member(subtree,"description")
    end
    field(out,"name",name,"string",nameStatus); field(out,"description",description,"string",descriptionStatus)
    if not out.name or not out.description then
        local loadable=(not out.name and out.fieldStatus.name~="restricted")
            or (not out.description and out.fieldStatus.description~="restricted")
        out.spellDataStatus=loadable and request(out.spellID) or "restricted"
        out.status=out.spellDataStatus=="pending" and "pending" or "partial"
    elseif out.conditionsStatus~="available" then out.status="partial" end
    return out
end

local nodeFields={type="number",currentRank="number",activeRank="number",ranksPurchased="number",
    ranksIncreased="number",maxRanks="number",totalMaxRanks="number",isAvailable="boolean",
    canPurchaseRank="boolean",meetsEdgeRequirements="boolean",posX="number",posY="number",subTreeID="number"}
local function records(value,status,spec,required)
    local out={}
    if not valid(value,"table") then return out,status=="available" and "unavailable" or status end
    status="available"
    for _,record in ipairs(value) do
        if valid(record,"table") then
            local data=fields(record,spec,required)
            out[#out+1]=data
            if data.status~="available" then status="partial" end
        else status="partial" end
    end
    return out,status
end
local function nodeDetails(api,config,nodeID,node,selected)
    local out=fields(node,nodeFields,{currentRank=true,activeRank=true,maxRanks=true,totalMaxRanks=true})
    out.id=nodeID; out.entries={}; out.prerequisites={}
    out.groupIDs,out.groupIDsStatus=numberList(member(node,"groupIDs"))
    out.conditions,out.conditionsStatus=conditions(api,config,member(node,"conditionIDs"))
    local active,activeStatus=member(node,"activeEntry")
    local selectedID,selectedRank,selectionKnown
    if valid(active,"table") then
        selectedID=member(active,"entryID"); selectedRank=member(active,"rank")
        selectionKnown=id(selectedID) and rank(selectedRank)
        if id(selectedID) then out.selectedEntryID=selectedID end
        out.selectionStatus=selectionKnown and "available" or "unavailable"
    elseif active==nil and activeStatus=="unavailable" and out.currentRank==0 and out.activeRank==0 then
        selectionKnown=true; out.selectionStatus="available"
    else out.selectionStatus=activeStatus=="restricted" and "restricted" or "unavailable" end
    local entryIDs,entryStatus=numberList(member(node,"entryIDs"))
    out.entriesStatus=entryStatus
    local foundSelected=false
    for _,entryID in ipairs(entryIDs) do
        local entry=entryDetails(api,config,entryID)
        if selectionKnown then entry.selected=entryID==selectedID end
        if entry.selected then
            foundSelected=true; entry.selectedRank=selectedRank
            if selectedRank>0 then
                selected[#selected+1]={nodeID=nodeID,entryID=entryID,spellID=entry.spellID,
                    name=entry.name,rank=selectedRank,maxRanks=entry.maxRanks,status=entry.status}
            end
        end
        out.entries[#out.entries+1]=entry
        if entry.status~="available" then out.status="partial" end
    end
    if selectedID and not foundSelected then selectionKnown=false; out.selectionStatus="unavailable" end
    local edges,edgesStatus=member(node,"visibleEdges")
    out.edges,out.edgesStatus=records(edges,edgesStatus,{targetNode="number",type="number",isActive="boolean"},{targetNode=true,type=true,isActive=true})
    local costs,costsStatus=readTable(api.GetNodeCost,config,nodeID)
    out.costs,out.costsStatus=records(costs,costsStatus,{ID="number",amount="number"},{ID=true,amount=true})
    for _,status in ipairs({out.groupIDsStatus,out.conditionsStatus,out.entriesStatus,out.edgesStatus,out.costsStatus,out.selectionStatus}) do
        if status~="available" then out.status="partial" end
    end
    return out,entryStatus=="available" and selectionKnown==true
end
local function failure(capturedAt,status,reason,config)
    return {available=false,status=status,capturedAt=capturedAt,configID=config,scanComplete=false,reason=reason}
end
local function capture(capturedAt)
    local api=valid(C_Traits,"table") and C_Traits or {}
    local classAPI=valid(C_ClassTalents,"table") and C_ClassTalents or {}
    for _,fn in ipairs({"GetConfigInfo","GetTreeNodes","GetNodeInfo","ConfigHasStagedChanges"}) do
        if type(api[fn])~="function" then return failure(capturedAt,"unsupported","Forever talent APIs unavailable") end
    end
    if type(classAPI.GetActiveConfigID)~="function" then return failure(capturedAt,"unsupported","Forever talent APIs unavailable") end
    local config,configStatus=read(classAPI.GetActiveConfigID)
    if not id(config) then return failure(capturedAt,configStatus=="restricted" and "restricted" or "pending","No readable active talent configuration") end
    local staged,stagedStatus=read(api.ConfigHasStagedChanges,config)
    if not valid(staged,"boolean") then
        return failure(capturedAt,stagedStatus=="restricted" and "restricted" or "unavailable","Cannot determine whether talent changes are applied",config)
    end
    if staged then
        if confirmed and confirmed.configID==config then
            local saved=clone(confirmed); saved.pendingChanges=true; saved.status="pending_changes"; return saved
        end
        local out=failure(capturedAt,"pending_changes","No confirmed snapshot for this configuration",config)
        out.pendingChanges=true; return out
    end
    local info=readTable(api.GetConfigInfo,config)
    local treeIDs,treeIDsStatus=numberList(member(info,"treeIDs"))
    if not info or treeIDsStatus~="available" then return failure(capturedAt,"pending","Talent configuration is loading",config) end
    local out={available=true,status="available",capturedAt=capturedAt,configID=config,pendingChanges=false,
        scanComplete=true,trees={},selectedTalents={},currencies={}}
    local name,nameStatus=member(info,"name"); field(out,"configName",name,"string",nameStatus)
    if not out.configName then out.status="partial" end
    local currencySeen={}
    for _,treeID in ipairs(treeIDs) do
        local tree={id=treeID,status="available",groups={},nodes={},currencies={}}
        local treeInfo,treeInfoStatus=readTable(api.GetTreeInfo,config,treeID)
        local treeName,treeNameStatus=member(treeInfo,"titleText")
        if not treeInfo then treeNameStatus=treeInfoStatus end
        field(tree,"name",treeName,"string",treeNameStatus)
        if treeNameStatus=="restricted" or treeNameStatus=="api_error" or (treeName~=nil and not tree.name) then tree.status="partial" end
        local groups,groupsStatus=readTable(api.GetGroupDisplayInfoByTreeID,treeID)
        tree.groups,tree.groupsStatus=records(groups,groupsStatus,{groupID="number",displayName="string",orderIndex="number",skillLineID="number"},{groupID=true,displayName=true})
        local currency,currencyStatus=readTable(api.GetTreeCurrencyInfo,config,treeID,true)
        tree.currencies,tree.currencyStatus=records(currency,currencyStatus,{traitCurrencyID="number",quantity="number",spent="number",spentInTree="number",maxQuantity="number"},{traitCurrencyID=true,quantity=true,spent=true})
        for _,item in ipairs(tree.currencies) do
            item.unspentPoints=item.quantity; item.fieldStatus.unspentPoints=item.fieldStatus.quantity
            if not id(item.traitCurrencyID) or not valid(item.quantity,"number") then tree.currencyStatus="partial" end
            if id(item.traitCurrencyID) and not currencySeen[item.traitCurrencyID] then
                currencySeen[item.traitCurrencyID]=true; out.currencies[#out.currencies+1]=clone(item)
            end
        end
        local nodes,nodesStatus=readTable(api.GetTreeNodes,treeID)
        local nodeIDs; nodeIDs,tree.nodesStatus=numberList(nodes,nodesStatus)
        if tree.nodesStatus~="available" then out.scanComplete=false end
        for _,nodeID in ipairs(nodeIDs) do
            local node=readTable(api.GetNodeInfo,config,nodeID)
            local visible=member(node,"isVisible")
            if not node or not valid(visible,"boolean") then out.scanComplete=false; tree.nodesStatus="partial"
            elseif visible then
                local data,complete=nodeDetails(api,config,nodeID,node,out.selectedTalents)
                tree.nodes[#tree.nodes+1]=data
                if not complete then out.scanComplete=false; tree.nodesStatus="partial" end
                if data.status~="available" then tree.status="partial" end
            end
        end
        -- Keep API edge types; an incoming edge is not necessarily an AND prerequisite.
        local byID={}; for _,node in ipairs(tree.nodes) do byID[node.id]=node end
        for _,node in ipairs(tree.nodes) do
            for _,edge in ipairs(node.edges) do
                if id(edge.targetNode) and byID[edge.targetNode] then
                    local target=byID[edge.targetNode]
                    target.prerequisites[#target.prerequisites+1]={nodeID=node.id,type=edge.type,isActive=edge.isActive}
                end
            end
        end
        if tree.groupsStatus~="available" or tree.currencyStatus~="available" or tree.nodesStatus~="available" then tree.status="partial" end
        if tree.status~="available" then out.status="partial" end
        out.trees[#out.trees+1]=tree
    end
    -- Reject a mixed scan if the active build changed or preview edits began while reading.
    local finalConfig=read(classAPI.GetActiveConfigID)
    local finalStaged=read(api.ConfigHasStagedChanges,config)
    if not id(finalConfig) or finalConfig~=config or not valid(finalStaged,"boolean") or finalStaged~=false then
        return failure(capturedAt,"pending","Talent configuration changed while reading")
    end
    if not out.scanComplete then out.available=false; out.status="pending"
    else confirmed=clone(out) end
    return out
end
function T.Capture(capturedAt)
    budget=8
    local ok,result=pcall(capture,capturedAt)
    if ok then return result end
    return failure(capturedAt,"unavailable","This client could not provide talent data")
end
