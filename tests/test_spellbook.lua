-- Synthetic spellbook fixtures only; no game input or account data.
local file=assert(arg[1])
local now=100
local secret={}
function GetTime() return now end
function GetServerTime() return 1000+now end
function issecretvalue(value) return value==secret end
local state,requests,requestTimes,reads
local function fresh() dofile(file);return ExporterSpellbook end
local function capture()
    local result=ExporterSpellbook.Capture(1000+now)
    assert(state.liveReads==0,'Current cooldowns and charges must never be queried')
    return result
end
local function reset()
    now=100
    state={locale='enUS',damage=123,ready={},known={},names={},ranks={},book={},liveReads=0}
    requests,requestTimes,reads={},{},{}
    SPELL_RANK='Rank %d'
    Enum={SpellBookSpellBank={Player=0,Pet=1},SpellBookItemType={Spell=1,FutureSpell=2,PetAction=3,Flyout=4}}
    for _,row in ipairs({{100,'Heal','Rank 1'},{101,'Heal','Rank 2'},{102,'Heal','Rank 10'},
        {200,'Passive',''},{210,'Racial',''},{220,'Rage Strike','Rank 1'},{230,'Energy Strike','Rank 1'},
        {240,'Hybrid','Rank 1'},{301,'Portal','Rank 1'},{400,'Unknown','Rank 1'},
        {500,'Offspec Item','Rank 1'},{600,'Future','Rank 1'},{700,'Pet Ability','Rank 1'},
        {800,'Offspec Group','Rank 1'},{901,'Override Strike','Rank 3'},{777,'Temporary','Rank 1'}}) do
        local id=row[1];state.names[id]=row[2];state.ranks[id]=row[3];state.ready[id]=true;state.known[id]=true
    end
    state.known[400]=false
    for _,id in ipairs({200,210,100,101,102,220,230,240,400,500,600,700}) do
        state.book[#state.book+1]={spellID=id,actionID=id,itemType=1,isOffSpec=false,isPassive=id==200,
            name=state.names[id],subName=state.ranks[id]}
    end
    state.book[10].isOffSpec=true;state.book[11].itemType=2;state.book[12].itemType=3
    state.book[13]={actionID=50,itemType=4,isOffSpec=false,isPassive=false,name='Portals',subName=''}
    state.book[14]={spellID=100,actionID=100,itemType=1,isOffSpec=false,isPassive=false,name='Heal',subName='Rank 1'}
    state.book[15]={spellID=901,actionID=900,itemType=1,isOffSpec=false,isPassive=false,name='Override Strike',subName='Rank 3'}
    state.book[16]={spellID=800,actionID=800,itemType=1,isOffSpec=true,isPassive=false,name='Offspec Group',subName='Rank 1'}
    function GetLocale()return state.locale end
    C_SpellBook={
        GetNumSpellBookSkillLines=function()return 3 end,
        GetSpellBookSkillLineInfo=function(index)
            if index==1 then return {name='General',itemIndexOffset=0,numSpellBookItems=2} end
            if index==2 then return {name='Class',itemIndexOffset=2,numSpellBookItems=13} end
            return {name='Inactive',itemIndexOffset=15,numSpellBookItems=1,offSpecID=99}
        end,
        GetSpellBookItemInfo=function(slot,bank)
            assert(bank==0,'Pet spellbooks must not be read');assert(slot~=16,'Inactive skill lines must not be read')
            return state.book[slot]
        end,
        IsSpellKnown=function(id,bank)assert(bank==0);return state.known[id]==true end,
        IsSpellBookItemLowRank=function(slot,bank)
            assert(bank==0);local item=state.book[slot];return item and (item.spellID==100 or item.spellID==101) or false
        end,
    }
    function GetFlyoutInfo(id)assert(id==50);return 'Portals','',2,true end
    function GetFlyoutSlotInfo(id,index)assert(id==50);if index==1 then return 300,301,true end;return 999,nil,false end
    C_Spell={
        GetSpellInfo=function(id)
            assert(type(id)=='number','Look up exact spell IDs, never localized names')
            reads[id]=(reads[id] or 0)+1
            if state.ready[id] then return {name=state.names[id],iconID=1,castTime=id==210 and 0 or 1500,minRange=0,maxRange=40} end
        end,
        GetSpellName=function(id)if state.ready[id]then return state.names[id]end end,
        GetSpellSubtext=function(id)if state.ready[id]then return state.ranks[id]end end,
        GetSpellDescription=function(id)if state.ready[id]then return 'Effect '..id..': '..state.damage end end,
        IsSpellDataCached=function(id)return state.ready[id]==true end,
        IsSpellPassive=function(id)return id==200 end,
        RequestLoadSpellData=function(id)
            requests[id]=(requests[id] or 0)+1;requestTimes[id]=requestTimes[id] or {};table.insert(requestTimes[id],now)
        end,
        GetSpellPowerCost=function(id)
            if id==200 or id==210 then return {} end
            if id==220 then return {{type=1,name='Localized rage',cost=20,minCost=20}} end
            if id==230 then return {{type=3,name='Localized energy',cost=35,minCost=35}} end
            if id==240 then return {{type=0,name='Localized mana',cost=0,minCost=0,costPercent=0},
                {type=3,name='Localized energy',cost=10,minCost=10,requiredAuraID=9000,hasRequiredAura=false}} end
            return {{type=0,name='Localized mana',cost=45,minCost=45,costPercent=0}}
        end,
        GetSpellCooldown=function()state.liveReads=state.liveReads+1;error('Current cooldowns are out of scope')end,
        GetSpellCooldownDuration=function()state.liveReads=state.liveReads+1;error('Current cooldowns are out of scope')end,
        GetSpellCharges=function()state.liveReads=state.liveReads+1;error('Charges are out of scope')end,
    }
    function GetSpellBaseCooldown(id)return id==210 and 0 or 12000 end
    C_TooltipInfo={GetSpellByID=function(id,isPet,showSubtext,dontOverride)
        assert(isPet==false and showSubtext==true and dontOverride==true,'Tooltips must retain exact ranks')
        if state.ready[id]then return {lines={{leftText=state.names[id]},{leftText='Effect '..state.damage,rightText=state.ranks[id]}}}end
    end}
    return fresh()
end
local function find(result,id)
    for _,entry in ipairs(result.entries or {})do if entry.spellID==id then return entry end end
end
local function totalRequests()local n=0;for _,count in pairs(requests)do n=n+count end;return n end

reset()
local s=capture()
assert(s.available and s.status=='available' and s.scanComplete and s.capturedAt==1100)
assert(s.scope=='learned_player_spellbook' and s.spellCount==10 and #s.entries==10 and #s.skillLines==2)
assert(s.skillLines[1].name=='General' and s.skillLines[2].name=='Class')
for _,id in ipairs({100,101,102})do assert(find(s,id))end
assert(find(s,100).rank==1 and find(s,101).rank==2 and find(s,102).rank==10)
assert(find(s,100).highestLearnedRank==10 and find(s,100).highestLearnedRankStatus=='available')
assert(find(s,100).isHighestLearnedRank==false and find(s,102).isHighestLearnedRank==true)
assert(find(s,100).isLowerRank==true and find(s,102).isLowerRank==false)
assert(find(s,901).baseSpellID==900 and find(s,901).spellID==901 and not find(s,900))
assert(find(s,301).flyoutID==50 and not find(s,300))
for _,id in ipairs({400,500,600,700,800,777,999})do assert(not find(s,id),'Excluded entry '..id)end
assert(reads[100]==1,'Duplicate book entries must not duplicate spell details')
assert(find(s,100).spellBookSlot==3 and find(s,100).skillLineIndex==2)
assert(find(s,100).description=='Effect 100: 123' and find(s,100).tooltipLines[2].left=='Effect 123')
assert(find(s,100).castTimeMs==1500 and find(s,100).minRange==0 and find(s,100).maxRange==40 and find(s,100).baseCooldownMs==12000)
assert(find(s,210).castTimeMs==0 and find(s,210).baseCooldownMs==0)
assert(find(s,200).isPassive==true and find(s,200).rank==nil and find(s,200).rankStatus=='not_reported')
assert(find(s,210).powerCostsStatus=='no_cost' and #find(s,210).powerCosts==0)
assert(find(s,220).powerCosts[1].type==1 and find(s,230).powerCosts[1].type==3)
assert(find(s,240).powerCosts[1].cost==0 and #find(s,240).powerCosts==2 and find(s,240).powerCosts[2].hasRequiredAura==false)
assert(state.liveReads==0 and totalRequests()==0)
state.damage=150;state.known[101]=false;now=101;s=capture()
assert(s.capturedAt==1101 and not find(s,101) and find(s,100).tooltipLines[2].left=='Effect 150')
reset();state.known[901]=false;state.known[900]=true;state.known[301]=false;state.known[300]=true;s=capture()
assert(find(s,901).spellID==901 and find(s,901).baseSpellID==900)
assert(find(s,301).spellID==301 and find(s,301).baseSpellID==300,'Known base spells can expose learned overrides')
print('PASS: all learned ranks, exact overrides, player/general/passive scope, flyouts, costs, provenance and fresh captures')

reset();SPELL_RANK='Rang %d';state.locale='deDE'
for _,id in ipairs({100,101,102})do state.ranks[id]=state.ranks[id]:gsub('Rank','Rang');state.book[id==100 and 3 or id==101 and 4 or 5].subName=state.ranks[id]end
s=capture();assert(find(s,100).rank==1 and find(s,100).highestLearnedRank==10)
reset();SPELL_RANK='Rank %s';s=capture();assert(find(s,102).rank==10)
reset();SPELL_RANK=nil;s=capture();assert(find(s,100).rank==1)
reset();state.ranks[101]='Form 2';state.book[4].subName='Form 2';s=capture()
assert(find(s,101).rank==nil and find(s,101).rankText=='Form 2')
assert(find(s,100).highestLearnedRankStatus=='partial','Unknown ranks must not imply a complete rank comparison')
reset();state.locale='frFR';SPELL_RANK=nil;state.ranks[101]='Rang 2';state.book[4].subName='Rang 2';s=capture()
assert(find(s,101).rank==nil,'Do not parse arbitrary numbers without a supported localized rank format')
print('PASS: localized rank formats, rankless spells and incomplete highest-rank comparisons')

reset();local originalInfo=C_Spell.GetSpellInfo
C_Spell.GetSpellInfo=function(id)local info=originalInfo(id);if id==200 then info.castTime=nil;info.minRange=nil;info.maxRange=nil end;return info end
local originalCosts=C_Spell.GetSpellPowerCost
C_Spell.GetSpellPowerCost=function(id)if id==200 then return nil end;return originalCosts(id)end
GetSpellBaseCooldown=function(id)if id~=200 then return 0 end end
s=capture();local passive=find(s,200)
assert(passive.status=='available' and passive.powerCostsStatus=='not_applicable')
assert(passive.castTimeMs==nil and passive.baseCooldownMs==nil and passive.fieldStatus.castTimeMs=='not_applicable' and passive.fieldStatus.baseCooldownMs=='not_applicable')
reset();originalInfo=C_Spell.GetSpellInfo
C_Spell.GetSpellInfo=function(id)local info=originalInfo(id);if id==200 then info.maxRange=nil end;return info end
s=capture();assert(find(s,200).status=='available' and find(s,200).rangeStatus~='partial','A valid passive range endpoint and an absent inapplicable endpoint are not an error')
reset();state.book[1].isPassive=nil;s=capture();assert(find(s,200).isPassive==true,'Missing book metadata must not erase known passive state')
reset();C_Spell.GetSpellPowerCost=function()return nil end;s=capture()
assert(s.status=='partial' and find(s,100).powerCostsStatus=='unavailable' and #find(s,100).powerCosts==0)
for i=1,5 do now=now+31;s=capture()end
assert(totalRequests()==0,'Permanent optional cost gaps must not request spell data repeatedly')
print('PASS: passive operational fields, explicit free abilities and unavailable costs remain distinct')

for _,name in ipairs({'GetNumSpellBookSkillLines','GetSpellBookSkillLineInfo','GetSpellBookItemInfo','IsSpellKnown'})do
    reset();C_SpellBook[name]=nil;s=capture();assert(not s.available and s.status=='unsupported','Missing core API '..name)
end
reset();C_SpellBook=nil;s=capture();assert(not s.available and s.status=='unsupported')
reset();Enum=nil;s=capture();assert(not s.available and s.status=='unsupported')
reset();C_SpellBook.GetNumSpellBookSkillLines=function()return 1.5 end;s=capture();assert(not s.scanComplete and s.status~='available')
reset();C_SpellBook.GetNumSpellBookSkillLines=function()return 0 end;s=capture()
assert(s.available and s.scanComplete and #s.entries==0 and s.spellCount==0)
reset();local originalKnown=C_SpellBook.IsSpellKnown
C_SpellBook.IsSpellKnown=function(id,bank)if id==101 then return secret end;return originalKnown(id,bank)end
s=capture();assert(not s.scanComplete and not find(s,101) and find(s,100).highestLearnedRankStatus=='partial')
reset();state.book[4].isOffSpec='false';s=capture();assert(not s.scanComplete and not find(s,101))
reset();local originalBook=C_SpellBook.GetSpellBookItemInfo
C_SpellBook.GetSpellBookItemInfo=function(slot,bank)if slot==4 then error('Restricted slot')end;return originalBook(slot,bank)end
s=capture();assert(not s.scanComplete and find(s,100) and not find(s,101))
reset();GetFlyoutSlotInfo=function()return 300,301,1 end;s=capture();assert(not s.scanComplete and not find(s,301))
reset();local originalLine=C_SpellBook.GetSpellBookSkillLineInfo
C_SpellBook.GetSpellBookSkillLineInfo=function(index)local info=originalLine(index);if index==2 then info.itemIndexOffset=secret end;return info end
s=capture();assert(not s.scanComplete and find(s,200))
print('PASS: absent APIs, empty books, restricted enumeration and malformed learning/specialization flags')

reset();originalInfo=C_Spell.GetSpellInfo
C_Spell.GetSpellInfo=function(id)local info=originalInfo(id);if id==100 then info.castTime=secret;info.maxRange=math.huge end;return info end
s=capture();assert(s.status=='partial' and find(s,100).castTimeMs==nil and find(s,100).maxRange==nil and find(s,102).status=='available')
for _,invalid in ipairs({-1,'invalid',math.huge})do
    reset();originalInfo=C_Spell.GetSpellInfo
    C_Spell.GetSpellInfo=function(id)local info=originalInfo(id);if id==200 then info.castTime=invalid;info.minRange=invalid end;return info end
    GetSpellBaseCooldown=function(id)return id==200 and invalid or 0 end
    s=capture();passive=find(s,200)
    assert(passive.status=='partial' and passive.castTimeMs==nil and passive.minRange==nil and passive.baseCooldownMs==nil)
    assert(passive.fieldStatus.castTimeMs~='not_applicable' and passive.fieldStatus.minRange~='not_applicable' and passive.fieldStatus.baseCooldownMs~='not_applicable',
        'Malformed present passive metadata must not be mistaken for inapplicable fields')
end
reset();C_Spell.GetSpellDescription=function(id)if id==100 then return secret end;return 'Effect '..id end;s=capture()
assert(find(s,100).description==nil and find(s,100).status=='partial')
reset();C_Spell.GetSpellPowerCost=function()return {{type=0,cost=secret},{type=3,cost=0/0}}end;s=capture()
assert(s.status=='partial' and find(s,100).powerCosts[1].cost==nil and find(s,100).powerCosts[2].cost==nil)
reset();C_Spell.GetSpellPowerCost=function()return {'malformed'}end;s=capture();assert(s.status=='partial')
reset();C_Spell.GetSpellPowerCost=function()return {[2]={type=0,cost=45}}end;s=capture()
assert(find(s,100).powerCostsStatus~='no_cost' and find(s,100).status=='partial','A malformed sparse cost list is not proof of a free spell')
reset();C_TooltipInfo.GetSpellByID=function()return {lines={{leftText=secret},{leftText='Readable effect'}}}end;s=capture()
assert(s.status=='partial' and find(s,100).tooltipLines[1].left=='Readable effect')
reset();C_TooltipInfo.GetSpellByID=function()return {lines={[1]={leftText='Readable'},[3]={leftText='Skipped'}}}end;s=capture()
assert(find(s,100).tooltipStatus=='partial','Sparse tooltip lines must not silently report complete text')
assert(state.liveReads==0)
print('PASS: restricted and malformed metadata is isolated, omitted and marked partial without fabricated values')

reset();state.ready[101]=false;state.book[4].name=nil;state.book[4].subName=nil;s=capture()
assert(s.status=='partial' and requests[101]==1 and find(s,101).name==nil)
for i=1,5 do s=capture()end;assert(requests[101]==1)
now=129;s=capture();assert(requests[101]==1)
now=130;s=capture();assert(requests[101]==2)
now=160;s=capture();assert(requests[101]==3)
for i=1,5 do now=now+31;s=capture()end;assert(requests[101]==3)
state.ready[101]=true;ExporterSpellbook.OnEvent('SPELL_DATA_LOAD_RESULT',101,true);s=capture()
assert(find(s,101).name=='Heal' and find(s,101).rank==2 and find(s,100).highestLearnedRankStatus=='available')
state.known[101]=false;ExporterSpellbook.OnEvent('SPELL_DATA_LOAD_RESULT',101,true);s=capture();assert(not find(s,101))
reset();local originalDescription=C_Spell.GetSpellDescription
C_Spell.GetSpellDescription=function(id)if id==101 then return nil end;return originalDescription(id)end;s=capture()
assert(find(s,101).name=='Heal' and requests[101]==1,'Missing descriptions must request data even when names are loaded')
ExporterSpellbook.OnEvent('SPELL_DATA_LOAD_RESULT',101,false);now=200;s=capture();assert(requests[101]==1)
C_Spell.GetSpellDescription=originalDescription;s=capture();assert(find(s,101).description~=nil)
print('PASS: missing text, bounded retries, load failures, recovery and late callback isolation')

reset();state.book={};state.known={};state.ready={};state.names={};state.ranks={}
for index=1,12 do
    local id=1000+index;state.known[id]=true
    state.book[index]={spellID=id,actionID=id,itemType=1,isOffSpec=false,isPassive=false}
end
C_SpellBook.GetNumSpellBookSkillLines=function()return 1 end
C_SpellBook.GetSpellBookSkillLineInfo=function()return {name='Class',itemIndexOffset=0,numSpellBookItems=12}end
s=capture();assert(#s.entries==12 and totalRequests()==8)
local prior=totalRequests();s=capture();assert(totalRequests()==12 and totalRequests()-prior<=8)
for i=1,8 do now=now+30;prior=totalRequests();s=capture();assert(totalRequests()-prior<=8)end
for id,count in pairs(requests)do
    assert(count==3,'Request attempts must stop after three per spell')
    for i=2,#requestTimes[id]do assert(requestTimes[id][i]-requestTimes[id][i-1]>=30)end
end
assert(state.liveReads==0)
print('PASS: full-book loading respects eight requests per capture and three attempts per spell')
