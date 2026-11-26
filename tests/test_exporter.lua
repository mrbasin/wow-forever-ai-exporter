local core,options=assert(arg[1]),assert(arg[2])
local function copy(v) if type(v)~="table" then return v end local out={}; for k,x in pairs(v) do out[k]=copy(x) end; return out end
local widgets={}
local registeredEvents={}
local methods={}
function methods:SetScript(k,v) self.scripts[k]=v end
function methods:GetText() return self.text or "" end
function methods:SetText(v) self.text=v end
function methods:GetChecked() return self.checked end
function methods:SetChecked(v) self.checked=v end
function methods:HasFocus() return false end
function methods:CreateFontString() return setmetatable({scripts={}}, {__index=methods}) end
function methods:CreateTexture() return setmetatable({scripts={}}, {__index=methods}) end
function methods:Hide() self.shown=false end
function methods:Show() self.shown=true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
for _,key in ipairs({"SetPoint","SetSize","SetWidth","SetJustifyH","SetFontObject","SetAutoFocus","SetNumeric",
    "SetMaxLetters","SetMultiLine","HighlightText","ClearFocus","SetFrameStrata","SetAllPoints","SetColorTexture","SetScrollChild"}) do methods[key]=function() end end
function methods:RegisterEvent(event) registeredEvents[event]=true end
function CreateFrame(kind,name,parent,template)
    local f=setmetatable({kind=kind,parent=parent,template=template,scripts={}}, {__index=methods});widgets[#widgets+1]=f;return f
end
Settings={RegisterCanvasLayoutCategory=function(panel,name) assert(name=="AI Exporter" and panel.name==name); return {GetID=function()return 123 end}end,
    RegisterAddOnCategory=function()end,OpenToCategory=function(id) assert(id==123)end}
local now,combat,quiet=100,false,true
function GetTime() return now end
function GetServerTime() return 1000+now end
function InCombatLockdown() return combat end
function UnitName() return 'Example "é"' end
function GetRealmName() return 'Fictional realm' end
function UnitGUID() return 'Player-fictional' end
function UnitLevel() return 23 end
function UnitXP() return 150 end
function UnitXPMax() return 1000 end
function GetXPExhaustion() return 250 end
function GetZoneText() return 'Example zone' end
function GetSubZoneText() return 'Example district' end
local activeReads,completedReads=0,0
C_QuestLog={GetNumQuestLogEntries=function()activeReads=activeReads+1;return 0 end,
    GetAllCompletedQuestIDs=function()completedReads=completedReads+1;return {3,1}end,
    GetTitleForQuestID=function(id) return 'Example quest '..id end}
SlashCmdList={}; C_Timer={NewTicker=function(_,fn) _G.ticker=fn end}
local codec,n,current,writes={},0,'',0
local function encode(v) n=n+1;local key=tostring(n);codec[key]=copy(v);return key end
local function decode(v) return copy(assert(codec[v])) end
local function same(v)return v end
C_EncodingUtil={SerializeCBOR=encode,DeserializeCBOR=decode,CompressString=same,DecompressString=same,EncodeBase64=same,DecodeBase64=same}
Enum={CompressionMethod={Deflate=0}}
C_CooldownViewer={GetLayoutData=function()return current end,SetLayoutData=function(v)writes=writes+1;current=v end}
ExporterLocalPaths={cacheFiles={'C:\\Games\\WoW\\WTF\\Account\\EXAMPLE\\Realm\\Hero\\cooldownmanager.txt'}}
local budgetCaptures,budgetFinishes,budgetOpen,budgetEvents=0,0,false,{}
ExporterDataRequests={
    BeginCapture=function()
        assert(not budgetOpen,'Nested request budgets must not reset a capture limit')
        budgetOpen=true;budgetCaptures=budgetCaptures+1
    end,
    EndCapture=function()
        assert(budgetOpen,'Request budget ended without a capture')
        budgetOpen=false;budgetFinishes=budgetFinishes+1
    end,
    OnEvent=function(event,id,success)
        assert(event=='ITEM_DATA_LOAD_RESULT' or event=='GET_ITEM_INFO_RECEIVED' or event=='SPELL_DATA_LOAD_RESULT')
        budgetEvents[#budgetEvents+1]={event=event,id=id,success=success}
    end,
}
local reads={basic=0,location=0,characterStats=0,equipment=0,talents=0,spellbook=0,questLog=0,items=0,professions=0}
ExporterEquipment={Capture=function(stamp)
    assert(budgetOpen,'Equipment ran without the shared request budget')
    reads.equipment=reads.equipment+1
    return {available=true,status='available',capturedAt=stamp,slots={{slotID=16,empty=false,itemID=100,name='Example staff',stats={ITEM_MOD_INTELLECT_SHORT=4},tooltipLines={},enhancements={sockets={}}}}}
end}
local talentFailure,talentOversize=false,false
local talentPadding=0
local talentEvents=0
ExporterTalents={Capture=function(stamp)
    assert(budgetOpen,'Talents ran without the shared request budget')
    reads.talents=reads.talents+1
    if talentFailure then error('Synthetic talent API failure') end
    if talentOversize then return {available=true,description=string.rep('x',450001)} end
    return {available=true,status='pending_changes',capturedAt=stamp-10,configID=1,configName='Example build',
        description=string.rep('t',talentPadding),pendingChanges=true,selectedTalents={},currencies={},trees={{id=10,groups={},currencies={},nodes={{id=1,
        groupIDs={},entries={},edges={},prerequisites={},costs={},conditions={}}}}}}
end,OnEvent=function(event,id,success)
    assert(event=='SPELL_DATA_LOAD_RESULT' and id==202 and success==false);talentEvents=talentEvents+1
end}
local spellbookFailure,spellbookPadding=false,0
local spellbookEvents=0
ExporterSpellbook={Capture=function(stamp)
    assert(budgetOpen,'Spellbook ran without the shared request budget')
    reads.spellbook=reads.spellbook+1
    if spellbookFailure then error('Synthetic spellbook API failure') end
    return {available=true,status='available',capturedAt=stamp,scope='learned_player_spellbook',scanComplete=true,
        skillLines={},spellCount=2,entries={{spellID=100,name='Example spell',rank=1,highestLearnedRank=2,
            description=string.rep('s',spellbookPadding),tooltipLines={},powerCosts={}},
            {spellID=101,name='Example spell',rank=2,highestLearnedRank=2,tooltipLines={},powerCosts={}}}}
end,OnEvent=function(event,id,success)
    assert(event=='SPELL_DATA_LOAD_RESULT' and id==202 and success==false);spellbookEvents=spellbookEvents+1
end}
local questFailure,questPadding,questUnicode=false,0,false
local questEvents=0
ExporterQuestLog={Capture=function(stamp)
    assert(budgetOpen,'Quest Log ran outside the capture boundary')
    reads.questLog=reads.questLog+1
    if questFailure then error('Synthetic quest API failure') end
    return {available=true,status='available',capturedAt=stamp,
        active={available=true,status='available',capturedAt=stamp,scanComplete=true,includesStoryText=false,headers={},questCount=1,
            entries={{questID=10,title='Example active quest',objectiveSummary=string.rep(questUnicode and 'é' or 'q',questPadding),objectives={},
                rewards={items={},choices={},currencies={},spells={},majorFactionReputation={}}}}},
        completedHistory={available=true,status='available',capturedAt=stamp,scanComplete=true,
            questIDs={1},titlesByQuestID={['1']='Example completed quest'},pendingTitleIDs={},unavailableTitleIDs={}}}
end,OnEvent=function(event,id,success)
    assert(event=='QUEST_LOG_UPDATE' or (event=='QUEST_DATA_LOAD_RESULT' and id==10 and success==false))
    questEvents=questEvents+1
end}
local itemsFailure,itemsPadding=false,0
local itemsEvents=0
ExporterItems={Capture=function(stamp)
    assert(budgetOpen,'Items ran without the shared request budget')
    reads.items=reads.items+1
    if itemsFailure then error('Synthetic bag API failure') end
    return {available=true,status='available',capturedAt=stamp,scope='carried_bags',scanComplete=true,
        bags={{bagID=0,numSlots=3,freeSlots=1,occupiedSlots=2}},bagCount=1,totalSlots=3,freeSlots=1,occupiedSlots=2,itemCount=7,
        entries={{bagID=0,slotID=1,empty=false,itemID=500,link='item:500:1',name='Example bag item',count=3,
            description=string.rep('i',itemsPadding),stats={},tooltipLines={},enhancements={sockets={},emptySockets={}}},
            {bagID=0,slotID=2,empty=false,itemID=500,link='item:500:2',name='Example bag item',count=4},
            {bagID=0,slotID=3,empty=true,status='empty'}}}
end,OnEvent=function(event)
    assert(event=='ITEM_DATA_LOAD_RESULT' or event=='GET_ITEM_INFO_RECEIVED' or event=='BAG_UPDATE'
        or event=='BAG_UPDATE_DELAYED' or event=='ITEM_LOCK_CHANGED')
    itemsEvents=itemsEvents+1
end}
local professionsFailure=false
ExporterProfessions={Capture=function(stamp)
    assert(budgetOpen,'Professions ran outside the capture boundary')
    reads.professions=reads.professions+1
    if professionsFailure then error('Synthetic professions API failure') end
    return {available=true,status='available',capturedAt=stamp,scanComplete=true,
        entries={{skillLineID=356,name='Fishing',category='secondary',rank=75,maxRank=150,modifier=0,tempPoints=0}}}
end}
ExporterStats={}
for _,entry in ipairs({{'Basic','basic'},{'Location','location'},{'Capture','characterStats'}}) do
    local name,key=entry[1],entry[2]
    ExporterStats[name]=function(stamp)
        assert(budgetOpen,'Stats ran outside the capture boundary')
        reads[key]=reads[key]+1
        if key=='basic' then return {available=true,status='available',capturedAt=stamp,name='Example é',level=23,className='Priest',raceName='Night Elf',faction='Alliance'} end
        return {available=true,status='available',capturedAt=stamp}
    end
end
local function boot(saved)
    ExporterSettings=saved; dofile(core); dofile(options); Exporter.OnEvent('ADDON_LOADED','Exporter')
end
local function advance(seconds) now=now+seconds;ticker()end
boot({schemaVersion=1,intervalMinutes=2,sections={equipment=true,inventory=true,location=true}})
assert(registeredEvents.QUEST_LOG_UPDATE and registeredEvents.QUEST_DATA_LOAD_RESULT)
assert(registeredEvents.ITEM_DATA_LOAD_RESULT and registeredEvents.GET_ITEM_INFO_RECEIVED and registeredEvents.BAG_UPDATE
    and registeredEvents.BAG_UPDATE_DELAYED and registeredEvents.ITEM_LOCK_CHANGED)
assert(ExporterSettings.schemaVersion==5 and ExporterSettings.sections.basic and not ExporterSettings.sections.inventory)
assert(#Exporter.categories==9 and Exporter.categories[8][2]=='Items' and Exporter.categories[9][2]=='Professions' and ExporterSettings.sections.characterStats and ExporterSettings.sections.equipment and ExporterSettings.sections.talents and ExporterSettings.sections.spellbook and ExporterSettings.sections.questLog and ExporterSettings.sections.items and ExporterSettings.sections.professions)
assert(ExporterSettings.intervalMinutes==2 and ExporterSettings.periodic)
assert(Exporter.OutputPath()==ExporterLocalPaths.cacheFiles[1]);SlashCmdList.EXPORTER('')
ticker();assert(writes==1 and reads.basic==1 and reads.characterStats==1 and reads.equipment==1 and reads.talents==1 and reads.spellbook==1 and reads.questLog==1 and reads.items==1 and reads.professions==1)
assert(budgetCaptures==1 and budgetFinishes==1 and not budgetOpen)
local first=Exporter.lastSnapshot
local orderedA={z=false,a={z=0,a='Example é'},entries={{id=2},{id=1}}}
local orderedB={};orderedB.entries={{id=2},{id=1}};orderedB.a={a='Example é',z=0};orderedB.z=false
local orderedJSON=Exporter.JSON(orderedA)
assert(orderedJSON==Exporter.JSON(orderedB),'Object insertion order must not affect serialized bytes')
assert(orderedJSON=='{"a":{"a":"Example é","z":0},"entries":[{"id":2},{"id":1}],"z":false}',
    'Sort nested object keys without reordering arrays or changing zero/false/Unicode values')
assert(Exporter.JSON({titlesByQuestID={[20]='Twenty',[3]='Three'}})=='{"titlesByQuestID":{"20":"Twenty","3":"Three"}}')
assert(first.sourceAddon=='Exporter' and first.schemaVersion==5 and first.basic.level==23)
assert(ExporterSnapshotJSON:find('"schemaVersion":5',1,true))
assert(ExporterSnapshotJSON:find('"bySlot":{"mainHand":',1,true) and ExporterSnapshotJSON:find('"stats":{"intellect":4}',1,true))
assert(ExporterSnapshotJSON:find('"raceName":"Night Elf"',1,true) and ExporterSnapshotJSON:find('"faction":"Alliance"',1,true))
assert(not ExporterSnapshotJSON:find('"available":',1,true) and not ExporterSnapshotJSON:find('"status":',1,true))
assert(not ExporterSnapshotJSON:find('"availability":',1,true) and not ExporterSnapshotJSON:find('"export":',1,true))
assert(first.character.guid=='Player-fictional' and first.character.name==nil)
assert(first.equipment.slots[1].stats.ITEM_MOD_INTELLECT_SHORT==4 and first.equipment.capturedAt==first.capturedAt)
assert(ExporterSnapshotJSON:find('"tooltipLines":[]',1,true) and ExporterSnapshotJSON:find('"sockets":[]',1,true))
assert(first.talents.configName=='Example build' and first.talents.capturedAt==first.capturedAt-10 and first.talents.pendingChanges)
for _,key in ipairs({'selectedTalents','currencies','groups','groupIDs','entries','edges','prerequisites','costs','conditions'}) do
    assert(ExporterSnapshotJSON:find('"'..key..'":[]',1,true),'Empty talent list must be a JSON array: '..key)
end
assert(Exporter.JSON({trees={},nodes={}}):find('"trees":[]',1,true))
assert(Exporter.JSON({trees={},nodes={}}):find('"nodes":[]',1,true))
assert(first.spellbook.capturedAt==first.capturedAt and first.spellbook.entries[1].rank==1 and first.spellbook.entries[2].rank==2)
assert(ExporterSnapshotJSON:find('"skillLines":[]',1,true) and ExporterSnapshotJSON:find('"powerCosts":[]',1,true))
assert(Exporter.JSON({spellbook={entries={}}}):find('"entries":[]',1,true))
assert(first.questLog.capturedAt==first.capturedAt and first.questLog.active.entries[1].questID==10)
assert(first.questLog.active.includesStoryText==false and first.questLog.active.entries[1].description==nil)
assert(first.questLog.active.entries[1].objectiveSummary=='')
assert(first.questLog.completedHistory.questIDs[1]==1 and first.availability.questLog)
assert(ExporterSnapshotJSON:find('"titlesByQuestID":{"1":"Example completed quest"}',1,true))
for _,key in ipairs({'headers','objectives','items','choices','spells','majorFactionReputation'}) do
    assert(ExporterSnapshotJSON:find('"'..key..'":[]',1,true),'Empty quest list must be an array: '..key)
end
assert(not ExporterSnapshotJSON:find('"pendingTitleIDs":',1,true) and not ExporterSnapshotJSON:find('"unavailableTitleIDs":',1,true))
assert(Exporter.JSON({questIDs={},titlesByQuestID={}}):find('"questIDs":[]',1,true))
assert(Exporter.JSON({questIDs={},titlesByQuestID={}}):find('"titlesByQuestID":{}',1,true))
assert(first.items.capturedAt==first.capturedAt and first.items.entries[1].count==3 and first.items.entries[2].count==4)
assert(first.items.entries[1].link~=first.items.entries[2].link and first.items.entries[3].empty and first.availability.items)
local emptyItems=Exporter.JSON({items={available=true,bags={},entries={},stats={},enhancements={emptySockets={}}}})
assert(emptyItems:find('"items":{',1,true) and emptyItems:find('"bags":[]',1,true) and emptyItems:find('"entries":[]',1,true))
assert(emptyItems:find('"stats":{}',1,true) and emptyItems:find('"emptySockets":{}',1,true))
assert(first.activeQuests==nil and first.inventory==nil and first.experience==nil)
Exporter.OnEvent('SPELL_DATA_LOAD_RESULT',202,false);assert(talentEvents==1 and spellbookEvents==1)
assert(#budgetEvents==1 and budgetEvents[1].event=='SPELL_DATA_LOAD_RESULT' and budgetEvents[1].id==202 and budgetEvents[1].success==false)
local eventWrites,eventReads=writes,reads.questLog
Exporter.OnEvent('QUEST_DATA_LOAD_RESULT',10,false);Exporter.OnEvent('QUEST_LOG_UPDATE')
assert(questEvents==2 and writes==eventWrites and reads.questLog==eventReads and not Exporter.pending)
local itemsReads=reads.items
for _,event in ipairs({'ITEM_DATA_LOAD_RESULT','GET_ITEM_INFO_RECEIVED','BAG_UPDATE','BAG_UPDATE_DELAYED','ITEM_LOCK_CHANGED'}) do
    Exporter.OnEvent(event,500,false)
end
assert(itemsEvents==5 and reads.items==itemsReads and writes==eventWrites and not Exporter.pending)
assert(#budgetEvents==3 and budgetEvents[2].event=='ITEM_DATA_LOAD_RESULT' and budgetEvents[3].event=='GET_ITEM_INFO_RECEIVED')
assert(budgetEvents[2].id==500 and budgetEvents[2].success==false and budgetEvents[3].id==500 and budgetEvents[3].success==false)
assert(budgetCaptures==1 and budgetFinishes==1 and not budgetOpen)
assert(activeReads==0 and completedReads==0)
assert(ExporterSnapshotJSON:find('Example é',1,true))
assert(decode(current:sub(3))[127]:sub(1,5)=='EXP1:')
advance(119);assert(writes==1 and budgetCaptures==1);advance(1);assert(writes==2 and budgetCaptures==2 and budgetFinishes==2)
assert(Exporter.lastSnapshot.capturedAt>first.capturedAt)
advance(1);Exporter.RequestExport();ticker();assert(writes==2 and Exporter.pending and budgetCaptures==2)
advance(29);assert(writes==3)
combat=true;advance(120);assert(writes==3 and budgetCaptures==3);combat=false;Exporter.OnEvent('ACTIONBAR_SLOT_CHANGED');advance(1);assert(writes==3 and budgetCaptures==3)
advance(1);assert(writes==4)
print('PASS: periodic intervals, ad-hoc request coalescing, combat/toolbar delays, nine-category schema and capture timestamps')

ExporterSettings.periodic=false;Exporter.ApplySettings();advance(30);local adhocWrites=writes
advance(600);assert(writes==adhocWrites)
Exporter.RequestExport();ticker();assert(writes==adhocWrites+1)
local beforeLogout=ExporterSnapshotJSON
Exporter.OnEvent('PLAYER_LOGOUT');assert(ExporterSnapshotJSON==beforeLogout)
local original=current
boot({schemaVersion=2,periodic=false});assert(ExporterSnapshotJSON==beforeLogout)
advance(600);assert(current==original)
Exporter.RequestExport();ticker();assert(Exporter.lastSnapshot)
-- Every category can be disabled, and quest APIs must not be queried when disabled.
for _,item in ipairs(Exporter.categories) do ExporterSettings.sections[item[1]]=false end
local readsBefore=copy(reads)
Exporter.ApplySettings()
assert(not ExporterSnapshotJSON:find('Example é',1,true))
assert(not ExporterSnapshotJSON:find('Example staff',1,true))
assert(not ExporterSnapshotJSON:find('Example build',1,true))
assert(not ExporterSnapshotJSON:find('Example spell',1,true))
assert(not ExporterSnapshotJSON:find('Example active quest',1,true) and not ExporterSnapshotJSON:find('Example completed quest',1,true))
assert(not ExporterSnapshotJSON:find('Example bag item',1,true))
advance(30)
for _,item in ipairs(Exporter.categories) do assert(Exporter.lastSnapshot.availability[item[1]]==false) end
for key,count in pairs(reads) do assert(count==readsBefore[key]) end
assert(Exporter.lastSnapshot.basic.status=='disabled')
assert(not ExporterSnapshotJSON:find('"basic":',1,true),'Disabled categories must be omitted, including redaction')
assert(Exporter.lastSnapshot.character.guid=='Player-fictional')
print('PASS: ad-hoc mode, last saved snapshot retention, category redaction and disabled query suppression')

-- Real UI checkbox and button handlers apply settings and enqueue an export.
local panel=Exporter.optionsContent
local boxes={};local nowButton,minutesBox
for _,w in ipairs(widgets) do
    if w.parent==panel and w.kind=='CheckButton' then boxes[#boxes+1]=w end
    if w.parent==panel and w.kind=='Button' and w.text=='Export now' then nowButton=w end
    if w.parent==panel and w.kind=='EditBox' and w.scripts.OnEnterPressed then minutesBox=w end
end
assert(#boxes==11 and nowButton)
boxes[3]:SetChecked(true);boxes[3].scripts.OnClick(boxes[3]);assert(ExporterSettings.sections.basic)
advance(30);nowButton.scripts.OnClick(nowButton);assert(Exporter.pending)
advance(30);assert(Exporter.lastSnapshot.basic.available)
boxes[6]:SetChecked(true);boxes[6].scripts.OnClick(boxes[6]);assert(ExporterSettings.sections.equipment)
advance(30);assert(Exporter.lastSnapshot.equipment.available)
boxes[6]:SetChecked(false);boxes[6].scripts.OnClick(boxes[6])
local equipmentReads=reads.equipment
advance(30);assert(Exporter.lastSnapshot.equipment.status=='disabled' and reads.equipment==equipmentReads)
boxes[7]:SetChecked(true);boxes[7].scripts.OnClick(boxes[7]);assert(ExporterSettings.sections.talents)
advance(30);assert(Exporter.lastSnapshot.talents.available)
talentFailure=true;Exporter.RequestExport();advance(30)
assert(Exporter.lastSnapshot.talents.status=='unavailable' and not Exporter.lastSnapshot.availability.talents)
assert(Exporter.lastSnapshot.basic.available and not Exporter.pending)
talentFailure=false;Exporter.RequestExport();advance(30)
assert(Exporter.lastSnapshot.talents.available)
local validPayload,validLayout,validWrites=ExporterSnapshotJSON,current,writes
talentOversize=true;Exporter.RequestExport();advance(30)
assert(Exporter.status:find('Snapshot exceeds the export size budget',1,true))
assert(ExporterSnapshotJSON==validPayload and current==validLayout and writes==validWrites)
talentOversize=false;Exporter.RequestExport();advance(30)
assert(Exporter.lastSnapshot.talents.available and writes==validWrites+1)
boxes[8]:SetChecked(true);boxes[8].scripts.OnClick(boxes[8]);assert(ExporterSettings.sections.spellbook)
advance(30);assert(Exporter.lastSnapshot.spellbook.available)
spellbookFailure=true;Exporter.RequestExport();advance(30)
assert(Exporter.lastSnapshot.spellbook.status=='unavailable' and not Exporter.lastSnapshot.availability.spellbook)
assert(Exporter.lastSnapshot.basic.available and Exporter.lastSnapshot.talents.available)
spellbookFailure=false;talentPadding=150000;spellbookPadding=250000
Exporter.RequestExport();advance(30)
assert(Exporter.lastSnapshot.talents.available and Exporter.lastSnapshot.spellbook.available)
assert(#ExporterSnapshotJSON>400000 and #ExporterSnapshotJSON<=450000)
validPayload,validLayout,validWrites=ExporterSnapshotJSON,current,writes
spellbookPadding=350000;Exporter.RequestExport();advance(30)
assert(Exporter.status:find('Snapshot exceeds the export size budget',1,true))
assert(ExporterSnapshotJSON==validPayload and current==validLayout and writes==validWrites)
talentPadding,spellbookPadding=0,0;Exporter.RequestExport();advance(30)
assert(Exporter.lastSnapshot.spellbook.available and writes==validWrites+1)
boxes[9]:SetChecked(true);boxes[9].scripts.OnClick(boxes[9]);assert(ExporterSettings.sections.questLog)
advance(30);assert(Exporter.lastSnapshot.questLog.available)
questFailure=true;Exporter.RequestExport();advance(30)
assert(Exporter.lastSnapshot.questLog.status=='unavailable' and not Exporter.lastSnapshot.availability.questLog)
assert(Exporter.lastSnapshot.basic.available and Exporter.lastSnapshot.spellbook.available)
questFailure=false
local questCollector=ExporterQuestLog;ExporterQuestLog=nil;Exporter.RequestExport();advance(30)
assert(Exporter.lastSnapshot.questLog.status=='unavailable' and Exporter.lastSnapshot.talents.available)
ExporterQuestLog=questCollector
talentPadding,spellbookPadding,questPadding=100000,150000,150000
Exporter.RequestExport();advance(30)
assert(Exporter.lastSnapshot.questLog.available and #ExporterSnapshotJSON>400000 and #ExporterSnapshotJSON<450000)
validPayload,validLayout,validWrites=ExporterSnapshotJSON,current,writes
local validStamp=Exporter.lastSnapshot.capturedAt
questPadding=250000;Exporter.RequestExport();advance(30)
assert(Exporter.status:find('Snapshot exceeds the export size budget',1,true))
assert(ExporterSnapshotJSON==validPayload and current==validLayout and writes==validWrites and Exporter.lastSnapshot.capturedAt==validStamp)
questUnicode,questPadding=true,100000;Exporter.RequestExport();advance(30)
assert(Exporter.status:find('Snapshot exceeds the export size budget',1,true),'Size budget must count UTF-8 bytes')
assert(ExporterSnapshotJSON==validPayload and current==validLayout and writes==validWrites)
questUnicode=false
talentPadding,spellbookPadding,questPadding=0,0,0;Exporter.RequestExport();advance(30)
assert(Exporter.lastSnapshot.questLog.available and writes==validWrites+1)
boxes[10]:SetChecked(true);boxes[10].scripts.OnClick(boxes[10]);assert(ExporterSettings.sections.items)
advance(30);assert(Exporter.lastSnapshot.items.available)
itemsFailure=true;Exporter.RequestExport();advance(30)
assert(Exporter.lastSnapshot.items.status=='unavailable' and not Exporter.lastSnapshot.availability.items)
assert(Exporter.lastSnapshot.basic.available and Exporter.lastSnapshot.questLog.available)
itemsFailure=false
local itemsCollector=ExporterItems;ExporterItems=nil;Exporter.RequestExport();advance(30)
assert(Exporter.lastSnapshot.items.status=='unavailable' and Exporter.lastSnapshot.questLog.available)
ExporterItems=itemsCollector
talentPadding,spellbookPadding,questPadding,itemsPadding=100000,150000,150000,30000
Exporter.RequestExport();advance(30)
assert(Exporter.lastSnapshot.items.available and #ExporterSnapshotJSON>430000 and #ExporterSnapshotJSON<=450000)
validPayload,validLayout,validWrites=ExporterSnapshotJSON,current,writes
validStamp=Exporter.lastSnapshot.capturedAt
itemsPadding=80000;Exporter.RequestExport();advance(30)
assert(Exporter.status:find('Snapshot exceeds the export size budget',1,true))
assert(ExporterSnapshotJSON==validPayload and current==validLayout and writes==validWrites and Exporter.lastSnapshot.capturedAt==validStamp)
talentPadding,spellbookPadding,questPadding,itemsPadding=0,0,0,0
Exporter.RequestExport();advance(30);assert(Exporter.lastSnapshot.items.available and writes==validWrites+1)
boxes[10]:SetChecked(false);boxes[10].scripts.OnClick(boxes[10])
assert(not ExporterSnapshotJSON:find('Example bag item',1,true) and not ExporterSnapshotJSON:find('item:500:',1,true))
itemsReads=reads.items
Exporter.OnEvent('ITEM_DATA_LOAD_RESULT',500,true);Exporter.OnEvent('BAG_UPDATE',0)
advance(30);assert(Exporter.lastSnapshot.items.status=='disabled' and reads.items==itemsReads)
boxes[9]:SetChecked(false);boxes[9].scripts.OnClick(boxes[9])
assert(not ExporterSnapshotJSON:find('Example active quest',1,true) and not ExporterSnapshotJSON:find('Example completed quest',1,true))
local questReads=reads.questLog
Exporter.OnEvent('QUEST_DATA_LOAD_RESULT',10,false);Exporter.OnEvent('QUEST_LOG_UPDATE')
advance(30);assert(Exporter.lastSnapshot.questLog.status=='disabled' and reads.questLog==questReads)
boxes[8]:SetChecked(false);boxes[8].scripts.OnClick(boxes[8])
assert(not ExporterSnapshotJSON:find('Example spell',1,true))
local spellbookReads=reads.spellbook
advance(30);assert(Exporter.lastSnapshot.spellbook.status=='disabled' and reads.spellbook==spellbookReads)
boxes[7]:SetChecked(false);boxes[7].scripts.OnClick(boxes[7])
assert(not ExporterSnapshotJSON:find('Example build',1,true))
local talentReads=reads.talents
advance(30);assert(Exporter.lastSnapshot.talents.status=='disabled' and reads.talents==talentReads)
ExporterSettings.intervalMinutes=0;Exporter.ApplySettings();assert(ExporterSettings.intervalMinutes==1)
boxes[11]:SetChecked(true);boxes[11].scripts.OnClick(boxes[11]);advance(30)
assert(Exporter.lastSnapshot.professions.available and ExporterSnapshotJSON:find('"professions":',1,true))
assert(Exporter.lastSnapshot.professions.capturedAt==Exporter.lastSnapshot.capturedAt)
professionsFailure=true;Exporter.RequestExport();advance(30)
assert(Exporter.lastSnapshot.professions.status=='unavailable' and not ExporterSnapshotJSON:find('"professions":',1,true))
assert(Exporter.lastSnapshot.basic.available)
professionsFailure=false
local professionsCollector=ExporterProfessions;ExporterProfessions=nil;Exporter.RequestExport();advance(30)
assert(not Exporter.lastSnapshot.professions.available and Exporter.lastSnapshot.basic.available)
ExporterProfessions=professionsCollector
Exporter.RequestExport();advance(30)
local professionsReads=reads.professions
boxes[11]:SetChecked(false);boxes[11].scripts.OnClick(boxes[11])
assert(not ExporterSnapshotJSON:find('"professions":',1,true),'Disabling professions must redact immediately')
advance(30)
assert(reads.professions==professionsReads and Exporter.lastSnapshot.professions.status=='disabled')
assert(Exporter.NormalizeSettings({intervalMinutes=1440}).intervalMinutes==60)
for _,limit in ipairs({60,1}) do
    minutesBox:SetText(tostring(limit))
    minutesBox.scripts.OnEnterPressed(minutesBox)
    assert(ExporterSettings.intervalMinutes==limit)
end
for _,invalid in ipairs({'0','61','2.5'}) do
    minutesBox:SetText(invalid)
    minutesBox.scripts.OnEditFocusLost(minutesBox)
    assert(ExporterSettings.intervalMinutes==1 and minutesBox:GetText()=='1')
end
print('PASS: settings registration, category checkbox, export button, interval bounds and copyable path')

-- Concurrent layout edits survive; an unrelated exporter is never overwritten.
local layout=decode(current:sub(3));layout[2]={value=987};current='1|'..encode(layout)
Exporter.RequestExport();advance(30);assert(decode(current:sub(3))[2].value==987)
Exporter.Cleanup();assert(decode(current:sub(3))[2].value==987 and not decode(current:sub(3))[127])
current='1|'..encode({[1]=5,[127]='OTHER1:foreign'});local foreign=current;local before=writes
Exporter.RequestExport();advance(30);assert(current==foreign and writes==before)
assert(Exporter.status:find('Another exporter',1,true))
for i=1,10 do advance(2) end;assert(writes==before)
current='';Exporter.RequestExport();advance(30);assert(writes==before+1)
ExporterSettings.enabled=false;Exporter.ApplySettings();local stopped=writes;advance(300);assert(writes==stopped)
assert(not Exporter.RequestExport())
print('PASS: foreign marker rejection, no retry storm, recovery, disable, cleanup and concurrent layout preservation')

-- Migrating ad-hoc users does not retain obsolete category data or start a timer.
ExporterSnapshotJSON='old equipment and quest data'
boot({schemaVersion=1,periodic=false,sections={location=false,equipment=true}})
assert(ExporterSnapshotJSON==nil and not ExporterSettings.periodic and not ExporterSettings.sections.location)
assert(ExporterSettings.sections.basic and ExporterSettings.sections.characterStats)
assert(ExporterSettings.sections.equipment)
assert(ExporterSettings.sections.talents)
assert(ExporterSettings.sections.spellbook)
assert(ExporterSettings.sections.questLog)
assert(ExporterSettings.sections.items)
local migrated=Exporter.NormalizeSettings({schemaVersion=2,periodic=false,sections={basic=false,location=false,characterStats=true}})
assert(migrated.sections.equipment and not migrated.periodic and not migrated.sections.basic and not migrated.sections.location)
assert(not Exporter.NormalizeSettings({schemaVersion=2,sections={equipment=false}}).sections.equipment)
local fourCategories=Exporter.NormalizeSettings({schemaVersion=2,periodic=false,intervalMinutes=7,
    sections={basic=false,location=true,characterStats=false,equipment=false}})
assert(fourCategories.sections.talents and fourCategories.intervalMinutes==7 and not fourCategories.periodic)
assert(not fourCategories.sections.basic and fourCategories.sections.location and not fourCategories.sections.characterStats and not fourCategories.sections.equipment)
assert(not Exporter.NormalizeSettings({schemaVersion=2,sections={talents=false}}).sections.talents)
local fiveCategories=Exporter.NormalizeSettings({schemaVersion=2,periodic=false,intervalMinutes=9,
    sections={basic=false,location=true,characterStats=false,equipment=true,talents=false}})
assert(fiveCategories.sections.spellbook and fiveCategories.intervalMinutes==9 and not fiveCategories.periodic)
assert(not fiveCategories.sections.basic and fiveCategories.sections.location and not fiveCategories.sections.characterStats)
assert(fiveCategories.sections.equipment and not fiveCategories.sections.talents)
assert(not Exporter.NormalizeSettings({schemaVersion=2,sections={spellbook=false}}).sections.spellbook)
local sixCategories=Exporter.NormalizeSettings({schemaVersion=2,periodic=false,intervalMinutes=11,
    sections={basic=false,location=true,characterStats=false,equipment=true,talents=false,spellbook=false}})
assert(sixCategories.sections.questLog and sixCategories.intervalMinutes==11 and not sixCategories.periodic)
assert(not sixCategories.sections.basic and sixCategories.sections.location and not sixCategories.sections.characterStats)
assert(sixCategories.sections.equipment and not sixCategories.sections.talents and not sixCategories.sections.spellbook)
assert(not Exporter.NormalizeSettings({schemaVersion=2,sections={questLog=false}}).sections.questLog)
local sevenCategories=Exporter.NormalizeSettings({schemaVersion=2,periodic=false,intervalMinutes=13,
    sections={basic=false,location=true,characterStats=false,equipment=true,talents=false,spellbook=false,questLog=false}})
assert(sevenCategories.sections.items and sevenCategories.intervalMinutes==13 and not sevenCategories.periodic)
assert(not sevenCategories.sections.basic and sevenCategories.sections.location and not sevenCategories.sections.characterStats)
assert(sevenCategories.sections.equipment and not sevenCategories.sections.talents and not sevenCategories.sections.spellbook and not sevenCategories.sections.questLog)
assert(not Exporter.NormalizeSettings({schemaVersion=2,sections={items=false}}).sections.items)
local eightCategories=Exporter.NormalizeSettings({schemaVersion=2,periodic=false,intervalMinutes=17,
    sections={basic=false,location=true,characterStats=false,equipment=true,talents=false,spellbook=false,questLog=false,items=false}})
assert(eightCategories.sections.professions and not eightCategories.sections.basic and not eightCategories.sections.items
    and eightCategories.sections.equipment and not eightCategories.periodic and eightCategories.intervalMinutes==17)
assert(not Exporter.NormalizeSettings({schemaVersion=2,sections={professions=false}}).sections.professions)
print('PASS: old settings migrate to nine categories, retain prior selections, and default new categories on')

-- Fresh installs and earlier defaults use a one-minute timer. Migration
-- must preserve user choices and must run only once, across reloads as well.
do
    assert(Exporter.NormalizeSettings(nil).intervalMinutes==1)
    for _,value in ipairs({math.huge,-math.huge,0/0,'invalid'}) do
        assert(Exporter.NormalizeSettings({schemaVersion=5,intervalMinutes=value}).intervalMinutes==1)
    end
    for _,fixture in ipairs({{false,1},{1,1},{2,1},{3,60},{4,5}}) do
        local settings=Exporter.NormalizeSettings({schemaVersion=fixture[1] or nil,intervalMinutes=fixture[2],
            enabled=false,periodic=false,sections={basic=false,location=true,professions=false}})
        assert(settings.schemaVersion==5 and settings.intervalMinutes==1)
        assert(not settings.enabled and not settings.periodic and not settings.sections.basic
            and settings.sections.location and not settings.sections.professions)
    end
    for _,fixture in ipairs({{2,2},{2,60},{3,1},{3,5},{3,17},{4,1},{4,60},{5,5},{5,60}}) do
        assert(Exporter.NormalizeSettings({schemaVersion=fixture[1],intervalMinutes=fixture[2]}).intervalMinutes==fixture[2],
            'Migration must preserve intervals that were not an earlier default')
    end
    current='';combat=false
    for _,saved in ipairs({false,{schemaVersion=2,intervalMinutes=1},{schemaVersion=3,intervalMinutes=60},
        {schemaVersion=4,intervalMinutes=5}}) do
        local previousPayload=ExporterSnapshotJSON
        boot(saved or nil)
        assert(ExporterSettings.schemaVersion==5 and ExporterSettings.intervalMinutes==1)
        if saved then assert(ExporterSnapshotJSON==previousPayload,'Interval migration must retain the saved observation') end
        local beforePeriodic=writes
        Exporter.OnEvent('PLAYER_ENTERING_WORLD');ticker()
        assert(writes==beforePeriodic+1,'Login must still produce the initial snapshot')
        advance(59);assert(writes==beforePeriodic+1,'Periodic export must wait the full interval')
        advance(1);assert(writes==beforePeriodic+2,'Periodic export must run at 60 seconds')
        Exporter.RequestExport();advance(30)
        assert(writes==beforePeriodic+3,'Manual exports must remain available between periodic exports')
        Exporter.Cleanup()
    end
    for _,interval in ipairs({5,60}) do
        ExporterSettings.intervalMinutes=interval;Exporter.ApplySettings()
        local customSettings,customPayload=copy(ExporterSettings),ExporterSnapshotJSON
        boot(customSettings)
        assert(ExporterSettings.schemaVersion==5 and ExporterSettings.intervalMinutes==interval,
            'A newly chosen interval must survive reload without being migrated again')
        assert(ExporterSnapshotJSON==customPayload,'Current settings must retain the saved observation on reload')
    end
    ExporterSettings.intervalMinutes=1;Exporter.ApplySettings()
    local savedSettings,savedPayload=copy(ExporterSettings),ExporterSnapshotJSON
    boot(savedSettings)
    assert(ExporterSettings.schemaVersion==5 and ExporterSettings.intervalMinutes==1,
        'A newly chosen one-minute interval must survive reload without being migrated again')
    assert(ExporterSnapshotJSON==savedPayload,'Current settings must retain the saved observation on reload')
    local beforeMinute=writes
    ticker();assert(writes==beforeMinute+1)
    advance(59);assert(writes==beforeMinute+1)
    advance(1);assert(writes==beforeMinute+2)
    Exporter.Cleanup()
end
print('PASS: one-minute defaults and legacy migration, exact timer boundaries, manual exports, and retained reload choices')

-- Logout must never start another scan or metadata-loading burst. The most
-- recent successful observation keeps its original capture timestamp.
current='';combat=false
boot({schemaVersion=3,enabled=true,periodic=true,intervalMinutes=1})
advance(2)
local logoutPayload,logoutStamp,logoutReads,logoutWrites=ExporterSnapshotJSON,Exporter.lastSnapshot.capturedAt,copy(reads),writes
local logoutBudgets=budgetCaptures
assert(current~='')
now=now+5;Exporter.OnEvent('PLAYER_LOGOUT')
assert(ExporterSnapshotJSON==logoutPayload and Exporter.lastSnapshot.capturedAt==logoutStamp)
for key,count in pairs(reads) do assert(count==logoutReads[key],'Logout rescanned '..key) end
assert(current=='' and writes==logoutWrites+1,'Logout should only restore the original layout')
assert(budgetCaptures==logoutBudgets and budgetFinishes==logoutBudgets and not budgetOpen)

-- A quick logout after login must also retain the previously saved observation,
-- even when the first periodic capture has not happened in this session.
boot({schemaVersion=3,enabled=true,periodic=true,intervalMinutes=1})
now=now+10;Exporter.OnEvent('PLAYER_LOGOUT')
assert(ExporterSnapshotJSON==logoutPayload and Exporter.lastSnapshot==nil)
for key,count in pairs(reads) do assert(count==logoutReads[key],'Early logout rescanned '..key) end
assert(current=='' and writes==logoutWrites+1)
assert(budgetCaptures==logoutBudgets and budgetFinishes==logoutBudgets and not budgetOpen)

boot({schemaVersion=3,enabled=true,periodic=true,intervalMinutes=1})
advance(2)
logoutPayload,logoutStamp,logoutReads,logoutWrites=ExporterSnapshotJSON,Exporter.lastSnapshot.capturedAt,copy(reads),writes
logoutBudgets=budgetCaptures
local combatLayout=current
combat=true;now=now+60;Exporter.OnEvent('PLAYER_LOGOUT')
assert(ExporterSnapshotJSON==logoutPayload and Exporter.lastSnapshot.capturedAt==logoutStamp)
for key,count in pairs(reads) do assert(count==logoutReads[key],'Combat logout rescanned '..key) end
assert(current==combatLayout and writes==logoutWrites and Exporter.cleanupPending)
assert(budgetCaptures==logoutBudgets and budgetFinishes==logoutBudgets and not budgetOpen)
combat=false;Exporter.Cleanup();assert(current=='' and writes==logoutWrites+1)
print('PASS: periodic logout never rescans, retains original payload/timestamps, and cleans up only when safe')

-- A publishing failure suspends this session. Timer ticks and data callbacks
-- must not keep capturing/retrying while the user is playing.
boot({schemaVersion=3,enabled=true,periodic=true,intervalMinutes=1})
advance(2)
local failurePayload,failureLayout,failureStamp=ExporterSnapshotJSON,current,Exporter.lastSnapshot.capturedAt
talentOversize=true;advance(60)
assert(Exporter.suspended and not Exporter.pending and ExporterSettings.enabled)
assert(Exporter.status:find('Snapshot exceeds the export size budget',1,true))
local failureStatus,failureReads,failureWrites=Exporter.status,copy(reads),writes
local failureBudgets=budgetCaptures
assert(ExporterSnapshotJSON==failurePayload and current==failureLayout and Exporter.lastSnapshot.capturedAt==failureStamp)
talentOversize=false
Exporter.OnEvent('QUEST_LOG_UPDATE');Exporter.OnEvent('BAG_UPDATE_DELAYED')
advance(60);advance(600)
assert(Exporter.suspended and not Exporter.pending and Exporter.status==failureStatus)
assert(writes==failureWrites and ExporterSnapshotJSON==failurePayload and current==failureLayout)
for key,count in pairs(reads) do assert(count==failureReads[key],'Suspended timer rescanned '..key) end
assert(budgetCaptures==failureBudgets and budgetFinishes==failureBudgets and not budgetOpen)
assert(Exporter.RequestExport() and not Exporter.suspended and Exporter.pending)
ticker()
assert(writes==failureWrites+1 and not Exporter.pending and not Exporter.suspended)
assert(Exporter.lastSnapshot.capturedAt>failureStamp and ExporterSettings.enabled)

-- A transport exception follows the same policy; an explicit settings apply
-- can retry, without changing the user's category selections or timing mode.
local setLayout=C_CooldownViewer.SetLayoutData
C_CooldownViewer.SetLayoutData=function() error('Synthetic layout write failure') end
advance(60)
assert(Exporter.suspended and not Exporter.pending and ExporterSettings.enabled)
assert(Exporter.status:find('Synthetic layout write failure',1,true))
failureReads,failureWrites,failureStatus=copy(reads),writes,Exporter.status
C_CooldownViewer.SetLayoutData=setLayout
advance(600)
assert(writes==failureWrites and Exporter.status==failureStatus)
for key,count in pairs(reads) do assert(count==failureReads[key]) end
local selected=copy(ExporterSettings.sections)
Exporter.ApplySettings()
assert(not Exporter.suspended and Exporter.pending and ExporterSettings.periodic)
for key,value in pairs(selected) do assert(ExporterSettings.sections[key]==value) end
ticker();assert(writes==failureWrites+1 and not Exporter.suspended)

talentOversize=true;advance(60);assert(Exporter.suspended)
ExporterSettings.enabled=false;Exporter.ApplySettings()
failureReads,failureWrites=copy(reads),writes
failureBudgets=budgetCaptures
talentOversize=false
assert(not Exporter.RequestExport() and not ExporterSettings.enabled and not Exporter.pending)
advance(600)
for key,count in pairs(reads) do assert(count==failureReads[key]) end
assert(writes==failureWrites and not ExporterSettings.enabled)
assert(budgetCaptures==failureBudgets and budgetFinishes==failureBudgets and not budgetOpen)
ExporterSettings.enabled=true;Exporter.ApplySettings();ticker()
assert(not Exporter.suspended and not Exporter.pending and writes==failureWrites+1)
print('PASS: export errors suspend automatic attempts, retain settings/data, and allow explicit recovery')

-- A missing request coordinator is an installation error, never permission to
-- call collectors with four independent loading budgets.
local requestCoordinator=ExporterDataRequests
ExporterDataRequests=nil
failureReads,failureWrites,failureBudgets=copy(reads),writes,budgetCaptures
Exporter.RequestExport();advance(30)
assert(Exporter.suspended and not Exporter.pending)
for key,count in pairs(reads) do assert(count==failureReads[key],'Missing coordinator allowed collector '..key) end
assert(writes==failureWrites and budgetCaptures==failureBudgets and not budgetOpen)
ExporterDataRequests=requestCoordinator
Exporter.RequestExport();advance(30)
assert(not Exporter.suspended and not Exporter.pending and writes==failureWrites+1)
assert(budgetCaptures==failureBudgets+1 and budgetFinishes==budgetCaptures and not budgetOpen)
print('PASS: shared request budget brackets each allowed capture, receives data callbacks, and fails closed if missing')

-- ADDON_LOADED can precede character identity during login. Waiting for that
-- normal lifecycle transition must not latch the publishing-error pause or
-- consume a request budget/minimum-interval attempt.
Exporter.Cleanup()
local unitGUID=UnitGUID
UnitGUID=function() return nil end
boot({schemaVersion=3,enabled=true,periodic=true,intervalMinutes=1})
local loginReads,loginWrites,loginBudgets=copy(reads),writes,budgetCaptures
advance(2);advance(60)
assert(not Exporter.suspended and not Exporter.pending and ExporterSettings.enabled)
assert(Exporter.status:find('Waiting',1,true))
for key,count in pairs(reads) do assert(count==loginReads[key],'Login without identity scanned '..key) end
assert(writes==loginWrites and budgetCaptures==loginBudgets and budgetFinishes==loginBudgets)
UnitGUID=unitGUID
Exporter.OnEvent('PLAYER_ENTERING_WORLD');ticker()
assert(writes==loginWrites+1 and budgetCaptures==loginBudgets+1 and not Exporter.suspended)
assert(Exporter.lastSnapshot.character.guid=='Player-fictional')

Exporter.Cleanup()
UnitGUID=function() return nil end
boot({schemaVersion=3,enabled=true,periodic=false,intervalMinutes=1})
loginReads,loginWrites,loginBudgets=copy(reads),writes,budgetCaptures
assert(Exporter.RequestExport());ticker()
assert(Exporter.pending and not Exporter.suspended)
for key,count in pairs(reads) do assert(count==loginReads[key]) end
assert(writes==loginWrites and budgetCaptures==loginBudgets)
UnitGUID=unitGUID
Exporter.OnEvent('PLAYER_ENTERING_WORLD');ticker()
assert(writes==loginWrites+1 and not Exporter.pending and not Exporter.suspended and not ExporterSettings.periodic)
assert(budgetCaptures==loginBudgets+1 and budgetFinishes==budgetCaptures and not budgetOpen)
print('PASS: login identity delays wait without errors or requests and retain queued ad-hoc work')

-- Exercise actual new collectors through the production category gates.
Exporter.Cleanup()
dofile((core:gsub('Exporter%.lua$','CharacterStats.lua')))
dofile((core:gsub('Exporter%.lua$','Professions.lua')))
local contextReads={money=0,current=0,total=0,rested=0,disabled=0,professions=0}
GetMoney=function()contextReads.money=contextReads.money+1;return 123456 end
UnitXP=function(unit)assert(unit=='player');contextReads.current=contextReads.current+1;return 0 end
UnitXPMax=function(unit)assert(unit=='player');contextReads.total=contextReads.total+1;return 1000 end
GetXPExhaustion=function()contextReads.rested=contextReads.rested+1;return nil end
IsXPUserDisabled=function()contextReads.disabled=contextReads.disabled+1;return false end
local professionFixture={}
for _,id in ipairs({129,165,185,356}) do
    professionFixture[id]={skillID=id,isHeader=false,name='Example '..id,rank=0,maxRank=75,modifier=0,tempPoints=0}
end
C_SkillInfo={GetSkillLineInfoByID=function(id)
    contextReads.professions=contextReads.professions+1;return professionFixture[id]
end}
local selection={}
for _,entry in ipairs(Exporter.categories) do selection[entry[1]]=false end
selection.basic=true;selection.professions=true
boot({schemaVersion=2,enabled=true,periodic=false,sections=selection})
Exporter.RequestExport();advance(30)
assert(contextReads.money==1 and contextReads.current==1 and contextReads.total==1 and contextReads.rested==1
    and contextReads.disabled==1 and contextReads.professions==12)
assert(ExporterSnapshotJSON:find('"moneyCopper":123456',1,true)
    and ExporterSnapshotJSON:find('"xp":{"current":0,"disabled":false,"levelTotal":1000}',1,true))
local projected=Exporter.CompactSnapshot(Exporter.lastSnapshot)
assert(projected.schemaVersion==5 and projected.professions.scanComplete and projected.professions.entries.columns)
assert(#projected.professions.entries.rows==4 and projected.professions.capturedAt==nil)
local contextBefore=copy(contextReads)
ExporterSettings.sections.basic=false;ExporterSettings.sections.professions=false;Exporter.ApplySettings();advance(30)
for key,count in pairs(contextReads) do assert(count==contextBefore[key],'Disabled category queried '..key) end
assert(not ExporterSnapshotJSON:find('"basic":',1,true) and not ExporterSnapshotJSON:find('"professions":',1,true))
assert(ExporterSnapshotJSON:find('"guid":"Player-fictional"',1,true))
print('PASS: real Basic/Professions collectors, compact tables, inherited timestamps and disabled-query suppression')

-- Folder names need not match the character or realm shown in game.
local promptBox,promptButton
for _,widget in ipairs(widgets) do
    if widget:GetText()=="Select AI prompt" then promptButton=widget end
    if widget:GetText():find("Read my AI Exporter snapshot.",1,true) then promptBox=widget end
end
assert(promptBox and promptButton)
function promptBox:SetFocus() self.focused=true; self.scripts.OnEditFocusGained(self) end
function promptBox:HighlightText() self.selected=true end
local function selectedPrompt(files,wowRoot)
    ExporterLocalPaths={cacheFiles=files,wowRoot=wowRoot}
    promptBox.focused=false; promptBox.selected=false
    promptButton.scripts.OnClick(promptButton)
    assert(promptBox.focused and promptBox.selected)
    local prompt=promptBox:GetText()
    assert(prompt:find(UnitGUID("player"),1,true))
    assert(prompt:find([[-Output "$env:TEMP\wow-character.json"]],1,true))
    return prompt
end
local actual=[[C:\Hero's Games\_forever_\WTF\Account\TEST\91\Hero-One\cooldownmanager.txt]]
local command=[[powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\Hero''s Games\_forever_\Interface\AddOns\Exporter\Decode-Export.ps1' -Path ]]
assert(selectedPrompt({actual}):find(command..[['C:\Hero''s Games\_forever_\WTF\Account\TEST\91\Hero-One\cooldownmanager.txt']],1,true))
local typographic=actual:gsub("'","’")
assert(selectedPrompt({typographic}):find([[C:\Hero'’s Games\_forever_\Interface]],1,true))
local multiple=selectedPrompt({actual,[[C:\Hero's Games\_forever_\WTF\Account\TEST\91\Alt-Two\cooldownmanager.txt]]})
assert(multiple:find(command.."'FULL CACHE PATH'",1,true))
assert(multiple:find([[C:\Hero's Games\_forever_\WTF\Account]],1,true) and not multiple:find("Alt-Two",1,true))
assert(selectedPrompt({},[[C:\Hero's Games\_forever_]]):find(command.."'FULL CACHE PATH'",1,true))
local manual=selectedPrompt({})
assert(manual:find("Open PowerShell in my WoW _forever_ folder",1,true))
assert(manual:find([[-File '.\Interface\AddOns\Exporter\Decode-Export.ps1' -Path 'FULL CACHE PATH']],1,true))
print('PASS: prompt selection, GUID verification, native decoder paths, PowerShell quoting, and manual installs')
