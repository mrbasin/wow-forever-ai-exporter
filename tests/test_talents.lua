local file=assert(arg[1])
local now=100
function GetTime() return now end
function GetServerTime() return 1000+now end
local secret={}
function issecretvalue(value) return value==secret end
local state,requests,requestTimes,reads
local function fresh() dofile(file); return ExporterTalents end
local function capture() return ExporterTalents.Capture(1000+now) end
local function reset()
    now=100
    state={config=1,staged=false,rank=2,unspent=0,ready={},nodes={1,2,3},treeIDs={10,20}}
    requests,requestTimes,reads={},{},{}
    for _,id in ipairs({201,202,203}) do state.ready[id]=true end
    C_ClassTalents={GetActiveConfigID=function() return state.config end}
    C_Spell={
        GetSpellInfo=function(id)
            if state.ready[id] then return {name='Talent '..id} end
        end,
        GetSpellDescription=function(id)
            if state.ready[id] then return 'Effect '..id end
        end,
        RequestLoadSpellData=function(id)
            requests[id]=(requests[id] or 0)+1
            requestTimes[id]=requestTimes[id] or {}
            table.insert(requestTimes[id],now)
        end,
    }
    C_Traits={
        ConfigHasStagedChanges=function(config) assert(config==state.config);return state.staged end,
        GetConfigInfo=function(config) return {name='Build '..config,treeIDs=state.treeIDs} end,
        GetTreeNodes=function(treeID) return treeID==10 and state.nodes or {} end,
        GetGroupDisplayInfoByTreeID=function(treeID)
            return treeID==10 and {{groupID=5,displayName='Discipline',orderIndex=1,skillLineID=613}} or {}
        end,
        GetTreeCurrencyInfo=function(config,treeID,excludeStaged)
            assert(config==state.config and excludeStaged==true,'Point totals must describe the applied build')
            return {{traitCurrencyID=7,quantity=state.unspent,spent=state.rank,spentInTree=state.rank,maxQuantity=51}}
        end,
        GetNodeInfo=function(config,id)
            reads[id]=(reads[id] or 0)+1
            assert(config==state.config)
            local rank=id==2 and state.rank or 0
            return {ID=id,type=0,isVisible=id~=3,isAvailable=true,currentRank=rank,
                activeRank=rank,ranksPurchased=rank,ranksIncreased=0,maxRanks=5,totalMaxRanks=5,
                canPurchaseRank=false,meetsEdgeRequirements=true,posX=id*10,posY=id*20,
                activeEntry=id==2 and {entryID=12,rank=rank} or nil,
                entryIDs=id==2 and {12,13} or {11},groupIDs={5},conditionIDs={9},
                visibleEdges=id==1 and {{targetNode=2,type=1,isActive=true}} or {}}
        end,
        GetEntryInfo=function(config,id)
            return {definitionID=id,maxRanks=5,isAvailable=true,type=0,conditionIDs={}}
        end,
        GetDefinitionInfo=function(id) return {spellID=id==11 and 201 or (id==12 and 202 or 203)} end,
        GetConditionInfo=function() return {isGate=true,isMet=true,isSufficient=true,type=0,
            spentAmountRequired=5,playerLevel=10,traitCurrencyID=7} end,
        GetNodeCost=function() return {{ID=7,amount=1}} end,
        PurchaseRank=function() error('The exporter must never spend talent points') end,
        CommitConfig=function() error('The exporter must never commit talent previews') end,
        ResetTree=function() error('The exporter must never reset talents') end,
    }
    return fresh()
end
local function entry(result,nodeIndex,entryIndex)
    return result.trees[1].nodes[nodeIndex].entries[entryIndex]
end
local function totalRequests()
    local count=0;for _,value in pairs(requests)do count=count+value end;return count
end

reset()
local t=capture()
assert(t.available and t.status=='available' and t.scanComplete and t.capturedAt==1100)
assert(t.configID==1 and t.configName=='Build 1' and t.pendingChanges==false)
assert(#t.trees==2 and #t.trees[1].nodes==2 and #t.trees[2].nodes==0)
assert(t.trees[1].groups[1].displayName=='Discipline' and #t.trees[2].groups==0)
assert(#t.currencies==1 and t.currencies[1].unspentPoints==0 and t.currencies[1].spent==2)
assert(#t.selectedTalents==1 and t.selectedTalents[1].nodeID==2 and t.selectedTalents[1].entryID==12)
assert(t.selectedTalents[1].rank==2 and t.selectedTalents[1].maxRanks==5 and t.selectedTalents[1].spellID==202)
assert(entry(t,1,1).name=='Talent 201' and entry(t,1,1).description=='Effect 201')
assert(entry(t,1,1).selected==false and t.trees[1].nodes[1].currentRank==0)
assert(entry(t,2,1).selected and not entry(t,2,2).selected and entry(t,2,2).spellID==203)
assert(t.trees[1].nodes[2].prerequisites[1].nodeID==1 and t.trees[1].nodes[2].prerequisites[1].type==1)
assert(t.trees[1].nodes[1].costs[1].amount==1 and t.trees[1].nodes[2].conditions[1].playerLevel==10)
assert(totalRequests()==0)
-- Capture rereads the active tree even without a talent-change event.
state.rank=0;state.unspent=2;now=101;t=capture()
assert(t.capturedAt==1101 and #t.selectedTalents==0 and t.currencies[1].unspentPoints==2)
assert(t.trees[1].nodes[2].currentRank==0 and t.trees[1].nodes[2].activeRank==0 and reads[2]==2)
print('PASS: full visible trees, choices, names/effects, points, prerequisites, fresh captures and zero ranks')

reset();t=capture();local originalTime=t.capturedAt
state.staged=true;state.rank=4;now=105;t=capture()
assert(t.available and t.status=='pending_changes' and t.pendingChanges and t.capturedAt==originalTime)
assert(t.selectedTalents[1].rank==2 and t.currencies[1].spent==2)
-- Returned results must not allow a consumer to mutate the retained confirmed build.
t.selectedTalents[1].rank=99;t=capture();assert(t.selectedTalents[1].rank==2)
state.config=2;t=capture()
assert(not t.available and t.pendingChanges and t.status=='pending_changes')
assert(not t.trees or #t.trees==0,'A different configuration must not borrow an old build')
state.staged=false;now=110;t=capture()
assert(t.available and t.configID==2 and t.selectedTalents[1].rank==4 and t.capturedAt==1110)
state.staged=true;fresh();t=capture()
assert(not t.available and t.pendingChanges,'A preview on initial capture has no confirmed build')
print('PASS: staged previews retain applied ranks and timestamps, cloning and configuration isolation')

reset()
local originalNode=C_Traits.GetNodeInfo
C_Traits.GetNodeInfo=function(config,id)
    local result=originalNode(config,id)
    if id==3 then state.config=2 end
    return result
end
t=capture();assert(not t.available and t.status~='available','A configuration switch during scanning must reject the snapshot')
reset();originalNode=C_Traits.GetNodeInfo
C_Traits.GetNodeInfo=function(config,id)
    local result=originalNode(config,id)
    if id==3 then state.staged=true end
    return result
end
t=capture();assert(not t.available and t.status~='available','Staged changes during scanning must reject the snapshot')
state.staged=true;t=capture();assert(not t.available,'Rejected scans must not become a confirmed build')
print('PASS: configuration and staged-state changes during scans never publish mixed builds')

for _,name in ipairs({'GetConfigInfo','GetTreeNodes','GetNodeInfo','ConfigHasStagedChanges'})do
    reset();C_Traits[name]=nil;t=capture()
    assert(not t.available and t.status=='unsupported','Missing required API: '..name)
end
reset();C_ClassTalents=nil;t=capture();assert(not t.available and t.status=='unsupported')
reset();C_Traits=nil;t=capture();assert(not t.available and t.status=='unsupported')
reset();state.config=nil;t=capture();assert(not t.available and t.status~='available')
reset();state.config=secret;t=capture();assert(not t.available and t.configID~=secret)
reset();state.staged=secret;t=capture();assert(not t.available)
reset();C_Traits.GetConfigInfo=function()error('Config not ready')end;t=capture();assert(not t.available)
reset();C_Traits.GetTreeNodes=function()return nil end;t=capture();assert(not t.available and not t.scanComplete)
reset();originalNode=C_Traits.GetNodeInfo
C_Traits.GetNodeInfo=function(config,id) if id==2 then error('Node not ready')end;return originalNode(config,id)end
t=capture();assert(not t.available and not t.scanComplete and t.status~='available')
assert(t.trees[1].nodes[1].entries[1].name=='Talent 201','A failed node must not discard readable neighboring nodes')
print('PASS: unsupported APIs, absent/restricted configuration, and incomplete graph handling')

reset();C_Traits.GetTreeCurrencyInfo=function()return nil end;t=capture()
assert(t.available and t.status=='partial' and #t.currencies==0)
assert(entry(t,2,1).name=='Talent 202','Missing point totals must not hide readable talents')
reset();C_Traits.GetTreeCurrencyInfo=function()return {{traitCurrencyID=7,quantity=secret,spent=0/0}}end;t=capture()
assert(t.status=='partial' and t.currencies[1].unspentPoints==nil and t.currencies[1].spent==nil)
reset();C_Traits.GetTreeCurrencyInfo=function()return {{traitCurrencyID=7,quantity=0,spent=secret}}end;t=capture()
assert(t.status=='partial' and t.currencies[1].unspentPoints==0 and t.currencies[1].spent==nil)
reset();C_Traits.GetTreeCurrencyInfo=function()return {{traitCurrencyID=7,quantity=0,spent=2}}end;t=capture()
assert(t.status=='available','Absent optional currency capacity/per-tree totals must not hide complete points data')
for _,name in ipairs({'missing','restricted'})do
    reset();C_Traits.GetGroupDisplayInfoByTreeID=function()
        return {{groupID=5,displayName=name=='restricted' and secret or nil,orderIndex=1}}
    end
    t=capture();assert(t.available and t.status=='partial' and t.trees[1].groups[1].displayName==nil)
end
reset();C_Traits.GetConditionInfo=function()error('Condition unavailable')end;t=capture()
assert(t.status=='partial' and t.trees[1].nodes[2].conditions[1].available==false)
reset();C_Traits.GetConditionInfo=function()return {} end;t=capture()
assert(t.status=='partial','An empty condition record must not imply known gate requirements')
reset();C_Traits.GetConditionInfo=function()return {isMet=secret,isGate=true}end;t=capture()
assert(t.status=='partial' and t.trees[1].nodes[1].conditions[1].isMet==nil)
reset();C_Traits.GetNodeCost=function()return nil end;t=capture();assert(t.status=='partial')
reset();C_Traits.GetNodeCost=function()return {{ID=7,amount=secret}}end;t=capture()
assert(t.status=='partial' and t.trees[1].nodes[1].costs[1].amount==nil)
reset();C_Spell.GetSpellDescription=function(id)if id==202 then return secret end;return 'Effect '..id end;t=capture()
assert(t.available and t.status=='partial' and entry(t,2,1).description==nil)
assert(entry(t,2,2).description=='Effect 203')
reset();originalNode=C_Traits.GetNodeInfo
C_Traits.GetNodeInfo=function(config,id)
    local result=originalNode(config,id)
    if id==2 then result.activeRank=secret;result.currentRank=math.huge end
    return result
end
t=capture();assert(t.status~='available' and t.trees[1].nodes[2].activeRank==nil and t.trees[1].nodes[2].currentRank==nil)
reset();originalNode=C_Traits.GetNodeInfo
C_Traits.GetNodeInfo=function(config,id)
    local result=originalNode(config,id)
    if id==2 then result.activeEntry.rank=secret end
    return result
end
t=capture();assert(not t.available and not t.scanComplete and #t.selectedTalents==0)
reset();originalNode=C_Traits.GetNodeInfo
C_Traits.GetNodeInfo=function(config,id)
    local result=originalNode(config,id)
    if id==1 then result.visibleEdges={{targetNode=secret,type=1,isActive=true}} end
    return result
end
t=capture();assert(t.status=='partial' and #t.trees[1].nodes[2].prerequisites==0)
reset();local originalEntry=C_Traits.GetEntryInfo
C_Traits.GetEntryInfo=function(config,id)
    local result=originalEntry(config,id);result.maxRanks=secret;return result
end
t=capture();assert(t.status=='partial' and entry(t,2,1).maxRanks==nil)
reset();C_Traits.GetEntryInfo=function()return nil end;t=capture()
assert(t.status~='available' and entry(t,1,1).name==nil)
print('PASS: partial optional metadata, isolated errors, restricted/nonfinite values and no fabricated zeros')

reset();state.ready[202]=false;t=capture()
assert(t.available and t.status=='partial' and requests[202]==1 and entry(t,2,1).name==nil)
for i=1,5 do t=capture()end;assert(requests[202]==1)
now=129;t=capture();assert(requests[202]==1,'Retries must wait at least 30 seconds')
now=130;t=capture();assert(requests[202]==2)
now=160;t=capture();assert(requests[202]==3)
for i=1,5 do now=now+31;t=capture()end
assert(requests[202]==3,'Permanently missing data must have bounded requests')
state.ready[202]=true;ExporterTalents.OnEvent('SPELL_DATA_LOAD_RESULT',202,true);t=capture()
assert(t.status=='available' and entry(t,2,1).name=='Talent 202')
-- A late spell result cannot restore an old configuration or allocated rank.
state.config=2;state.rank=0;ExporterTalents.OnEvent('SPELL_DATA_LOAD_RESULT',202,true);t=capture()
assert(t.configID==2 and #t.selectedTalents==0)
reset();state.ready[202]=false;t=capture();ExporterTalents.OnEvent('SPELL_DATA_LOAD_RESULT',202,false)
now=200;t=capture();assert(requests[202]==1,'Explicit spell-load failure must not cause retry storms')
state.ready[202]=true;t=capture();assert(entry(t,2,1).name=='Talent 202','Fresh API data must recover after a prior load failure')
print('PASS: asynchronous descriptions, retry spacing/limits, explicit failures and late-result isolation')

reset();state.nodes={1};state.ready={}
originalNode=C_Traits.GetNodeInfo
C_Traits.GetNodeInfo=function(config,id)
    local result=originalNode(config,id);result.entryIDs={};result.visibleEdges={}
    for index=1,12 do result.entryIDs[index]=1000+index end
    return result
end
C_Traits.GetDefinitionInfo=function(id)return {spellID=id+1000}end
t=capture();assert(totalRequests()==8 and #t.trees[1].nodes[1].entries==12)
local previous=totalRequests();t=capture();assert(totalRequests()-previous<=8 and totalRequests()==12)
for i=1,8 do
    now=now+30;previous=totalRequests();t=capture()
    assert(totalRequests()-previous<=8,'One capture must respect the spell request budget')
end
for id,count in pairs(requests)do
    assert(count==3,'Every permanently uncached spell must stop after three requests')
    for index=2,#requestTimes[id]do assert(requestTimes[id][index]-requestTimes[id][index-1]>=30)end
end
print('PASS: full-tree spell loading respects per-capture and per-spell budgets')
