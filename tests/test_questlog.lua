-- Synthetic quest log and completion history. No game or account data.
local file=assert(arg[1])
local now=100
local secret={}
function GetTime()return now end
function GetServerTime()return 1000+now end
function issecretvalue(value)return value==secret end
local state,requests,requestTimes,requestOrder
local function copy(value)
    if type(value)~='table' or value==secret then return value end
    local result={};for key,child in pairs(value)do result[key]=copy(child)end;return result
end
local function fresh()dofile(file);return ExporterQuestLog end
local function capture()
    local result=ExporterQuestLog.Capture(1000+now)
    assert(state.mutations==0 and state.selected==999,'Collection must not change quest selection, headers, watches or quests')
    assert(result.active.includesStoryText==false,'Success and failure states must identify intentional story omission')
    for _,quest in ipairs(result.active.entries)do
        assert(quest.description==nil and (not quest.fieldStatus or quest.fieldStatus.description==nil),
            'Quest narrative and its status must not be exported')
    end
    return result
end
local function reset()
    now=100
    state={rows={},history={202,101,201,202},titles={},ready={},textReady={},mutations=0,selected=999,
        reportedCount=2,objectivesReads=0,historyReads=0,summarySuffix='first'}
    requests,requestTimes,requestOrder={},{},{}
    for _,id in ipairs({101,102,103,201,202})do state.titles[id]='Quest '..id;state.ready[id]=true;state.textReady[id]=true end
    state.rows={
        {questID=0,title='First zone',isHeader=true,isCollapsed=true},
        {questID=101,title='Quest 101',level=20,suggestedGroup=0,frequency=1,isHeader=false,isCollapsed=false,
            isTask=false,isBounty=false,isStory=true,isHidden=false,isAutoComplete=false},
        {questID=0,title='Second zone',isHeader=true,isCollapsed=false},
        {questID=102,title='Quest 102',level=21,suggestedGroup=0,frequency=0,isHeader=false,isCollapsed=false,
            isTask=false,isBounty=false,isStory=false,isHidden=false,isAutoComplete=false},
    }
    state.objectives={
        [101]={{text='Targets defeated: 10/10',type='monster',finished=true,numFulfilled=10,numRequired=10}},
        [102]={{text='Progress: 0/100',type='progressbar',finished=false,numFulfilled=0,numRequired=100}},
        [103]={{text='New objective',type='item',finished=false,numFulfilled=0,numRequired=1}},
    }
    local function mutation()state.mutations=state.mutations+1;error('Quest collection must remain read-only')end
    SelectQuestLogEntry=mutation;SetAbandonQuest=mutation;AbandonQuest=mutation
    ExpandQuestHeader=mutation;CollapseQuestHeader=mutation;AcceptQuest=mutation;CompleteQuest=mutation
    GetQuestReward=mutation;AddQuestWatch=mutation;RemoveQuestWatch=mutation;SetMapForQuestPOIs=mutation
    C_SuperTrack={SetSuperTrackedQuestID=mutation}
    C_QuestLog={
        GetNumQuestLogEntries=function()return #state.rows,state.reportedCount end,
        GetInfo=function(index)return copy(state.rows[index])end,
        GetQuestObjectives=function(id)
            assert(id==101 or id==102 or id==103,'Objectives must use explicit quest IDs')
            state.objectivesReads=state.objectivesReads+1
            if state.onObjectives then state.onObjectives(id)end
            return copy(state.objectives[id])
        end,
        IsComplete=function(id)return id==101 end,
        IsFailed=function(id)return id==102 end,
        IsRepeatableQuest=function(id)return id==101 end,
        ReadyForTurnIn=function(id)assert(id>0);return false end,
        GetQuestWatchType=function(id)if id==101 then return 0 end end,
        GetQuestTagInfo=function(id)assert(id>0);return nil end,
        GetAllCompletedQuestIDs=function()
            state.historyReads=state.historyReads+1
            if state.onHistory then return state.onHistory(state.historyReads)end
            return copy(state.history)
        end,
        GetTitleForQuestID=function(id)if state.ready[id]~=false then return state.titles[id]end end,
        RequestLoadQuestByID=function(id)
            assert(type(id)=='number' and id>0 and id%1==0)
            requests[id]=(requests[id] or 0)+1;requestTimes[id]=requestTimes[id] or {}
            table.insert(requestTimes[id],now);table.insert(requestOrder,id)
        end,
        GetQuestLogMajorFactionReputationRewards=function(id)assert(id>0);return {}end,
        GetSelectedQuest=function()return state.selected end,
        SetSelectedQuest=mutation,SetAbandonQuest=mutation,AbandonQuest=mutation,
        AddQuestWatch=mutation,RemoveQuestWatch=mutation,
    }
    function GetQuestLogQuestText(index)
        local row=assert(state.rows[index]);assert(not row.isHeader,'Quest text must use an active log index')
        if state.textReady[row.questID]then return 'Description '..row.questID,'Summary '..row.questID..' '..state.summarySuffix end
    end
    function GetQuestLogRewardXP(id)assert(id==101 or id==102 or id==103);return 0 end
    function GetQuestLogRewardMoney(id)assert(id==101 or id==102 or id==103);return 500 end
    function GetNumQuestLogRewards(id)assert(id==101 or id==102 or id==103);return 0 end
    function GetNumQuestLogChoices(id,includeHidden)assert(id==101 or id==102 or id==103);assert(includeHidden==false);return 0 end
    function GetQuestLogRewardInfo()error('No fixture item rewards')end
    function GetQuestLogChoiceInfo()error('No fixture choice rewards')end
    C_QuestInfoSystem={
        HasQuestRewardCurrencies=function(id)assert(id>0);return false end,
        GetQuestRewardCurrencies=function(id)assert(id>0);return {}end,
        HasQuestRewardSpells=function(id)assert(id>0);return false end,
        GetQuestRewardSpells=function(id)assert(id>0);return {}end,
        GetQuestRewardSpellInfo=function()error('No fixture spell rewards')end,
    }
    return fresh()
end
local function entry(result,id)
    for _,value in ipairs(result.active.entries or {})do if value.questID==id then return value end end
end
local function contains(values,wanted)for _,value in ipairs(values or {})do if value==wanted then return true end end;return false end
local function totalRequests()local total=0;for _,count in pairs(requests)do total=total+count end;return total end
local function emptyActive()state.rows={};state.reportedCount=0 end

reset()
local q=capture()
assert(q.available and q.status=='available' and q.capturedAt==1100)
assert(q.active.available and q.active.scanComplete and q.active.questCount==2 and q.active.reportedQuestCount==2)
assert(#q.active.headers==2 and q.active.headers[1].isCollapsed==true and q.active.headers[1].title=='First zone')
assert(entry(q,101).headerIndex==1 and entry(q,102).headerIndex==2)
assert(entry(q,101).title=='Quest 101' and entry(q,101).objectiveSummary=='Summary 101 first')
assert(entry(q,101).flags.isComplete==true and entry(q,101).flags.readyForTurnIn==false)
assert(entry(q,102).flags.isFailed==true and entry(q,101).flags.isRepeatable==true)
assert(entry(q,101).flags.isWatched==true and entry(q,101).flags.watchType==0 and entry(q,102).flags.isWatched==false)
assert(entry(q,101).tagStatus=='not_applicable' and entry(q,101).tag==nil)
assert(entry(q,102).objectives[1].type=='progressbar' and entry(q,102).objectives[1].numFulfilled==0)
assert(entry(q,101).objectives[1].finished==true and entry(q,101).rewards.xp==0 and entry(q,101).rewards.money==500)
assert(#entry(q,101).rewards.items==0 and #entry(q,101).rewards.choices==0 and #entry(q,101).rewards.currencies==0)
assert(q.completedHistory.available and q.completedHistory.scanComplete and q.completedHistory.questCount==3 and q.completedHistory.titleCount==3)
assert(q.completedHistory.questIDs[1]==101 and q.completedHistory.questIDs[2]==201 and q.completedHistory.questIDs[3]==202)
assert(q.completedHistory.titlesByQuestID['201']=='Quest 201' and q.completedHistory.titlesByQuestID[201]==nil)
assert(contains(q.completedHistory.questIDs,101) and entry(q,101),'Repeatable quests may be active and completed')
assert(not contains(q.completedHistory.questIDs,102),'Failed or disappeared active quests must not invent completed history')
assert(#q.completedHistory.pendingTitleIDs==0 and #q.completedHistory.unavailableTitleIDs==0 and totalRequests()==0)
state.summarySuffix='second';state.objectives[102][1].numFulfilled=5;now=101;q=capture()
assert(q.active.capturedAt==1101 and entry(q,102).objectives[1].numFulfilled==5 and entry(q,101).objectiveSummary=='Summary 101 second')
print('PASS: active objective summaries, independent completion flags, zero/progress objectives, collapsed headers and compact completed history')

reset();GetQuestLogQuestText=function(index)return nil,'Readable summary' end;q=capture()
assert(entry(q,101).objectiveSummary=='Readable summary' and entry(q,101).status=='available' and totalRequests()==0,
    'Missing story text must not degrade retained quest data or request loading')
reset();GetQuestLogQuestText=function(index)return 'Story text',nil end;q=capture()
assert(entry(q,101).objectiveSummary==nil and entry(q,101).fieldStatus.objectiveSummary=='unavailable'
    and entry(q,101).status=='partial' and requests[101]==1,
    'Missing retained objective summaries must remain partial and request loading')
reset();GetQuestLogQuestText=function(index)return 'Story text',secret end;q=capture()
assert(entry(q,101).objectiveSummary==nil and entry(q,101).fieldStatus.objectiveSummary=='restricted'
    and entry(q,101).status=='partial','Restricted summaries must remain explicit')
print('PASS: intentional story omission preserves summary availability and loading behavior')

reset()
GetNumQuestLogRewards=function(id)assert(id>0);return 1 end
GetQuestLogRewardInfo=function(index,id)assert(index==1 and id>0);return 'Item reward',123,2,3,true,8001,25 end
GetNumQuestLogChoices=function(id,hidden)assert(id>0 and hidden==false);return 1 end
GetQuestLogChoiceInfo=function(index,id)assert(index==1 and id>0);return 'Choice reward',124,1,2,false,8002 end
C_QuestInfoSystem.HasQuestRewardCurrencies=function(id)return true end
C_QuestInfoSystem.GetQuestRewardCurrencies=function(id)return {{currencyID=9,name='Currency',texture=20,quality=1,
    baseRewardAmount=10,bonusRewardAmount=0,totalRewardAmount=10}}end
C_QuestInfoSystem.HasQuestRewardSpells=function(id)return true end
C_QuestInfoSystem.GetQuestRewardSpells=function(id)return {7001}end
C_QuestInfoSystem.GetQuestRewardSpellInfo=function(id,spellID)
    assert(id>0 and spellID==7001);return {name='Reward spell',texture=30,isTradeskill=false,isSpellLearned=true,
        hideSpellLearnText=false,isBoostSpell=false,genericUnlock=false,type=1}
end
C_QuestLog.GetQuestLogMajorFactionReputationRewards=function(id)return {{factionID=12,rewardAmount=250}}end
q=capture();local reward=entry(q,101).rewards
assert(reward.status=='available' and reward.items[1].itemID==8001 and reward.items[1].count==2)
assert(reward.choices[1].itemID==8002 and reward.choices[1].isUsable==false)
assert(reward.currencies[1].currencyID==9 and reward.currencies[1].bonusRewardAmount==0)
assert(reward.spells[1].spellID==7001 and reward.spells[1].name=='Reward spell')
assert(reward.majorFactionReputation[1].factionID==12 and reward.majorFactionReputation[1].rewardAmount==250)
reset();GetNumQuestLogChoices=function(id,hidden)assert(hidden==false);return 1 end
GetQuestLogChoiceInfo=nil
GetQuestLogRewardInfo=function(index,id)return 'Guaranteed only',123,1,2,true,9900,20 end
q=capture();reward=entry(q,101).rewards
assert(reward.status=='partial' and reward.choicesStatus~='available')
assert(not reward.choices[1] or reward.choices[1].itemID==nil,'A missing choice API must not substitute guaranteed reward items')
print('PASS: explicit-ID money, XP, item choices, currency, spell and scoped reputation rewards')

reset();emptyActive();state.history={};q=capture()
assert(q.active.available and q.active.scanComplete and q.active.questCount==0 and #q.active.entries==0)
assert(q.completedHistory.available and q.completedHistory.scanComplete and q.completedHistory.questCount==0 and q.completedHistory.titleCount==0)
reset();state.objectives[101]={};q=capture();assert(entry(q,101).status=='available' and #entry(q,101).objectives==0)
reset();C_QuestLog.GetAllCompletedQuestIDs=function()return nil end;q=capture()
assert(q.active.available and not q.completedHistory.available and not q.completedHistory.scanComplete and q.status~='available')
reset();C_QuestLog.GetAllCompletedQuestIDs=nil;q=capture();assert(q.active.available and not q.completedHistory.available)
reset();C_QuestLog.GetNumQuestLogEntries=nil;q=capture();assert(not q.active.available and q.completedHistory.available)
reset();C_QuestLog.GetInfo=function()return nil end;q=capture();assert(not q.active.scanComplete and q.completedHistory.available)
reset();C_QuestLog=nil;q=capture();assert(not q.active.available and not q.completedHistory.available)
reset();state.history={[1]=201,[3]=202};q=capture()
assert(not q.completedHistory.scanComplete and q.completedHistory.status~='available','Sparse history is not a known complete list')
reset();state.history={201,secret,202};q=capture();assert(not q.completedHistory.scanComplete and q.completedHistory.status~='available')
reset();state.rows[4]=nil;state.rows[3]=nil;state.reportedCount=2;q=capture()
assert(not q.active.scanComplete,'A collapsed/hidden mismatch must not claim every active quest was scanned')
reset();C_QuestLog.GetNumQuestLogEntries=function()return 1001,1001 end;q=capture()
assert(not q.active.scanComplete and q.active.status~='available','Oversized active enumeration must be explicit')
reset();state.objectives[101]={}
for index=1,129 do state.objectives[101][index]={text='Objective '..index,type='item',finished=false,numFulfilled=0,numRequired=1}end
q=capture();assert(entry(q,101).status=='partial','Objective limits must not silently report complete data')
reset();GetNumQuestLogRewards=function(id)return 257 end;q=capture()
assert(entry(q,101).rewards.status~='available','Reward limits must not silently report complete data')
print('PASS: true empty states, independent subsection failures, malformed history and incomplete collapsed logs')

reset();state.objectives[101]=nil;q=capture();assert(entry(q,101).status=='partial' and entry(q,102))
reset();state.objectives[101]={{text='Bad counts',type='monster',finished=false,numFulfilled=secret,numRequired=0/0}};q=capture()
assert(entry(q,101).status=='partial' and entry(q,101).objectives[1].numFulfilled==nil and entry(q,101).objectives[1].numRequired==nil)
reset();state.objectives[101][1].numFulfilled=-1;state.objectives[101][1].numRequired=-10;q=capture()
assert(entry(q,101).status=='partial' and entry(q,101).objectives[1].numFulfilled==nil and entry(q,101).objectives[1].numRequired==nil,
    'Negative objective progress must not be reported as valid counts')
reset();state.objectives[101]={[2]={text='Sparse',type='item',finished=false,numFulfilled=0,numRequired=1}};q=capture()
assert(entry(q,101).status=='partial','A sparse objective list must not be treated as empty/complete')
reset();C_QuestLog.IsComplete=function()return secret end;q=capture();assert(entry(q,101).flags.isComplete==nil and entry(q,101).status=='partial')
reset();C_QuestLog.GetQuestWatchType=function(id)return 1 end;q=capture()
assert(entry(q,101).flags.isWatched==true and entry(q,101).flags.watchType==1)
reset();C_QuestLog.GetQuestWatchType=nil;q=capture();assert(entry(q,101).flags.isWatched==nil and entry(q,101).status=='partial')
reset();C_QuestLog.GetQuestWatchType=function(id)return secret end;q=capture()
assert(entry(q,101).flags.isWatched==nil and entry(q,101).flags.watchType==nil and entry(q,101).status=='partial')
reset();state.rows[2].questClassification=3
C_QuestLog.GetQuestTagInfo=function(id)return {tagID=81,tagName='Dungeon',isElite=true,quality=2}end;q=capture()
assert(entry(q,101).questClassification==3 and entry(q,101).tag.tagID==81 and entry(q,101).tag.tagName=='Dungeon' and entry(q,101).tagStatus=='available')
reset();C_QuestLog.GetQuestTagInfo=nil;q=capture();assert(entry(q,101).tagStatus=='unsupported' and entry(q,101).status=='partial')
reset();C_QuestLog.GetQuestTagInfo=function(id)return secret end;q=capture()
assert(entry(q,101).tag==nil and entry(q,101).tagStatus=='restricted' and entry(q,101).status=='partial')
reset();C_QuestLog.GetQuestTagInfo=function(id)return {tagID=81,tagName=secret}end;q=capture()
assert(entry(q,101).tag.tagName==nil and entry(q,101).tagStatus=='partial')
reset();GetQuestLogQuestText=function(index)return secret,'Readable summary' end;q=capture()
assert(entry(q,101).objectiveSummary=='Readable summary' and entry(q,101).status=='available' and totalRequests()==0,
    'Restricted story text must not degrade retained quest data or request loading')
reset();GetQuestLogRewardXP=function(id)return secret end;q=capture()
assert(entry(q,101).rewards.xp==nil and entry(q,101).rewards.status=='partial')
reset();GetQuestLogQuestText=function(index)if index==2 then error('Text unavailable')end;return 'Second description','Second summary' end;q=capture()
assert(entry(q,101).status=='partial' and entry(q,101).fieldStatus.objectiveSummary=='api_error'
    and entry(q,102).objectiveSummary=='Second summary','A failing quest must not hide other active entries')
reset();GetNumQuestLogRewards=function(id)return 1 end
GetQuestLogRewardInfo=function(index,id)return nil,123,1,2,true,8001,10 end;q=capture()
assert(entry(q,101).rewards.items[1].itemID==8001 and entry(q,101).rewards.items[1].name==nil and entry(q,101).rewards.status=='partial')
reset();C_QuestInfoSystem.HasQuestRewardCurrencies=function(id)return nil end
C_QuestInfoSystem.GetQuestRewardCurrencies=function(id)return nil end;q=capture();assert(entry(q,101).rewards.status=='partial')
reset();C_QuestInfoSystem.GetQuestRewardCurrencies=function(id)return nil end;q=capture()
assert(entry(q,101).rewards.status=='available','An explicit no-currency result may confirm an empty currency list')
reset();C_QuestInfoSystem.GetQuestRewardCurrencies=function(id)return secret end;q=capture()
assert(entry(q,101).rewards.status=='partial','Restricted currency data must not become confirmed empty through another API')
reset();C_QuestInfoSystem.GetQuestRewardSpells=function(id)return secret end;q=capture()
assert(entry(q,101).rewards.status=='partial','Restricted spell rewards must not become confirmed empty through another API')
print('PASS: missing text, unknown objectives/flags, restricted values and unavailable rewards are explicit')

reset()
state.onObjectives=function(id)
    state.onObjectives=nil;state.rows[4].questID=103;state.rows[4].title='Quest 103'
end
q=capture();assert(q.active.scanComplete and entry(q,103) and not entry(q,102),'Same-count identity changes require a fresh scan')
assert(state.objectivesReads<=4,'A changed active log may retry only once')
reset();local changes=0
state.onObjectives=function(id)
    if id==101 then changes=changes+1;state.rows[4].questID=changes%2==1 and 103 or 102;state.rows[4].title='Quest '..state.rows[4].questID end
end
q=capture();assert(not q.active.scanComplete and q.active.status~='available' and q.completedHistory.available)
assert(changes<=2,'Repeatedly changing active logs must not loop indefinitely')
reset();state.onObjectives=function(id)state.onObjectives=nil;ExporterQuestLog.OnEvent('QUEST_LOG_UPDATE')end
q=capture();assert(q.active.scanComplete and state.objectivesReads<=4)
reset();state.onHistory=function(count)return count==1 and {201,202} or {101,202}end
q=capture();assert(q.completedHistory.scanComplete and contains(q.completedHistory.questIDs,101) and not contains(q.completedHistory.questIDs,201))
assert(state.historyReads<=6,'Changed history may retry only once, followed by final consistency checks')
reset();state.onHistory=function(count)return count%2==1 and {201,202} or {101,202}end
q=capture();assert(not q.completedHistory.scanComplete and q.completedHistory.status~='available' and q.active.available)
assert(state.historyReads<=4)
reset();state.onHistory=function(count)
    if count==1 then state.rows[4].questID=103;state.rows[4].title='Quest 103' end
    return copy(state.history)
end
q=capture();assert(q.active.scanComplete and entry(q,103) and not entry(q,102) and q.completedHistory.scanComplete,
    'History reads that change the active log must trigger final active revalidation')
assert(state.objectivesReads<=4,'Cross-subsection changes share the same one-retry limit')
print('PASS: identity/revision changes retry once, reject mixed captures and preserve unaffected subsections')

reset();state.rows[2].title=nil;state.ready[101]=false;state.textReady[101]=false;state.history={101}
for id=1001,1048 do state.history[#state.history+1]=id end
q=capture();assert(totalRequests()==16 and requestOrder[1]==101,'Active quest data has priority in the shared quest-load budget')
assert(entry(q,101).title==nil and entry(q,101).status=='partial')
assert(requests[101]==1,'An active/completed overlap must share its quest load attempt')
reset();state.rows={};state.reportedCount=16;state.history={201};state.ready[201]=false
for index=1,16 do state.rows[index]={questID=3000+index,isHeader=false,isCollapsed=false}end
C_QuestLog.GetQuestObjectives=function(id)return {}end
GetQuestLogRewardXP=function(id)assert(id>0);return 0 end
GetQuestLogRewardMoney=function(id)assert(id>0);return 0 end
GetNumQuestLogRewards=function(id)assert(id>0);return 0 end
GetNumQuestLogChoices=function(id,hidden)assert(id>0 and hidden==false);return 0 end
q=capture();assert(totalRequests()==16 and requests[201]==nil and contains(q.completedHistory.pendingTitleIDs,201),
    'Exhausted active load budget leaves history pending without inventing a failure')
fresh();requests,requestTimes,requestOrder={},{},{};local swapped=false
C_QuestLog.GetQuestObjectives=function(id)
    if not swapped then swapped=true;for index=1,16 do state.rows[index].questID=4000+index end end
    return {}
end
q=capture();assert(q.active.scanComplete and entry(q,4001) and totalRequests()<=16,
    'An internal stable-scan retry must share the original capture request budget')
reset();emptyActive();state.history={}
for id=1001,1048 do state.history[#state.history+1]=id end
for iteration=1,3 do now=100+(iteration-1)*30;local before=totalRequests();q=capture();assert(totalRequests()-before<=16)end
for id=1001,1048 do assert(requests[id]==1,'The history cursor must not starve later IDs behind repeated early requests')end
for iteration=1,9 do now=now+30;local before=totalRequests();q=capture();assert(totalRequests()-before<=16)end
for id,count in pairs(requests)do
    assert(count==3,'Every missing title gets at most three load attempts')
    for index=2,#requestTimes[id]do assert(requestTimes[id][index]-requestTimes[id][index-1]>=30)end
end
now=now+31;q=capture();assert(#q.completedHistory.unavailableTitleIDs==48 and #q.completedHistory.pendingTitleIDs==0)
assert(q.completedHistory.scanComplete and q.completedHistory.questCount==48 and q.completedHistory.titleCount==0)
print('PASS: active-first shared loading, fair completed-title rotation, spacing and bounded attempts')

reset();emptyActive();state.history={201};state.ready[201]=false;q=capture()
assert(contains(q.completedHistory.pendingTitleIDs,201) and requests[201]==1)
local earlier=q
now=129;q=capture();assert(requests[201]==1)
ExporterQuestLog.OnEvent('QUEST_DATA_LOAD_RESULT',201,false);now=200;q=capture()
assert(requests[201]==1 and contains(q.completedHistory.unavailableTitleIDs,201))
state.ready[201]=true;ExporterQuestLog.OnEvent('QUEST_DATA_LOAD_RESULT',201,true);q=capture()
assert(q.completedHistory.titlesByQuestID['201']=='Quest 201' and q.completedHistory.titleCount==1)
assert(earlier.completedHistory.titlesByQuestID['201']==nil,'Load callbacks must not mutate prior snapshots')
state.history={202};ExporterQuestLog.OnEvent('QUEST_DATA_LOAD_RESULT',201,true);q=capture()
assert(not contains(q.completedHistory.questIDs,201) and q.completedHistory.titlesByQuestID['201']==nil)
reset();state.rows={state.rows[1],state.rows[2]};state.reportedCount=1;q=capture()
assert(not entry(q,102) and not contains(q.completedHistory.questIDs,102),'Removing active entries does not create completions')
reset();emptyActive();state.history={1};state.titles[1]='First quest';q=capture()
assert(q.completedHistory.questIDs[1]==1 and q.completedHistory.titlesByQuestID['1']=='First quest' and q.completedHistory.titlesByQuestID[1]==nil,
    'Quest ID one must use a string dictionary key, not an array index')
reset();emptyActive();state.history={}
for id=10001,13000 do state.history[#state.history+1]=id;state.titles[id]='Quest '..id end
q=capture();assert(q.completedHistory.scanComplete and q.completedHistory.questCount==3000 and q.completedHistory.titleCount==3000)
assert(q.completedHistory.questIDs[3000]==13000 and q.completedHistory.titlesByQuestID['13000']=='Quest 13000' and totalRequests()==0)
print('PASS: callbacks, terminal failures, title recovery, removals and large compact histories')
