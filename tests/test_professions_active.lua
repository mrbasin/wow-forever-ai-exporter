-- Active collector contract: fresh, bounded profession observations with no UI mutations.
local source=assert(arg[1])
local directReads,listReads,countReads=0,0,0
local function info(id,name,rank,maximum,modifier,temporary)
    return {skillID=id,name=name,isHeader=false,rank=rank,maxRank=maximum,modifier=modifier,tempPoints=temporary}
end
local function row(data,id)
    for _,value in ipairs(data.entries) do if value.skillLineID==id then return value end end
end
local function forbidden() error('Collector must never mutate the UI, request metadata or register timers') end
CreateFrame=forbidden; C_Timer={NewTicker=forbidden,After=forbidden}
local data={
    [165]=info(165,'|cff00ff00Travail du cuir "é"|r',142,150,0,0),
    [393]=info(393,'Skinning',148,150,5,10),
    [129]=info(129,'First Aid',0,75,0,0),
    [185]=info(185,'Cooking',75,75,-2,0),
    [356]=info(356,'Fishing',60,150,20,75),
}
local visible={}
local api={
    GetSkillLineInfoByID=function(id) directReads=directReads+1; return data[id] end,
    GetNumSkillLines=function()countReads=countReads+1;return #visible end,
    GetSkillLineInfo=function(index)listReads=listReads+1;return visible[index] end,
    ExpandSkillHeader=forbidden,CollapseSkillHeader=forbidden,AbandonSkill=forbidden,
}
C_SkillInfo=api
dofile(source)
local P=ExporterProfessions
local first=P.Capture(100)
assert(first.available and first.scanComplete and first.status=='available' and first.capturedAt==100)
assert(#first.entries==5 and directReads==12 and countReads==0 and listReads==0)
assert(row(first,165).name=='Travail du cuir "é"' and row(first,165).category=='primary')
assert(row(first,129).rank==0 and row(first,129).category=='secondary' and row(first,185).modifier==-2)
assert(row(first,393).rank==148 and row(first,393).maxRank==150 and row(first,393).tempPoints==10)
assert(row(first,393).effectiveSkillLevel==nil and row(first,393).isCapped==nil and row(first,393).pointsToCap==nil)
assert(first.scope==nil and first.professionCount==nil and row(first,165).source==nil)
data[165].rank=150; data[165].maxRank=225; data[393].tempPoints=20; data[129]=nil
local nextCapture=P.Capture(101)
assert(nextCapture.capturedAt==101 and row(nextCapture,165).rank==150 and row(nextCapture,165).maxRank==225)
assert(row(nextCapture,393).tempPoints==20 and not row(nextCapture,129) and directReads==24)
assert(row(first,165).rank==142 and row(first,393).tempPoints==10 and row(first,129).rank==0)
print('PASS: fresh ranks/caps/bonuses, localization, primary/secondary professions and unlearning without stale data')

local secret={}
function issecretvalue(value)return value==secret end
data[165].modifier=secret;data[165].name='';data[165].parentSkillLineID=secret;data[393].rank=-1;data[393].maxRank=0/0
data[185].tempPoints=math.huge;data[356].rank=1.5
local partial=P.Capture(102)
assert(partial.available and partial.scanComplete and partial.status=='partial' and countReads==0)
assert(row(partial,165).name==nil and row(partial,165).modifier==nil and row(partial,165).rank==150)
assert(row(partial,165).fieldStatus.modifier=='restricted' and row(partial,165).fieldStatus.name=='unavailable')
assert(row(partial,393).rank==nil and row(partial,393).maxRank==nil and row(partial,393).modifier==5)
assert(row(partial,185).tempPoints==nil and row(partial,356).rank==nil)
data[165]=info(165,'Leatherworking',150,225,0,0)
data[393]=info(393,'Skinning',148,150,5,20)
data[185]=info(185,'Cooking',75,75,0,0);data[356]=info(356,'Fishing',60,150,20,75)
print('PASS: optional missing/restricted fields preserve membership and valid ranks; invalid numeric fields are omitted')

api.GetSkillLineInfoByID=function(id)directReads=directReads+1;if id==185 then error('unavailable') end;return data[id]end
visible={data[165],data[393],data[185],data[356],info(43,'Swords',50,100,0,0),info(762,'Riding',75,75,0,0),
    info(2947,'Child Skinning',148,150,5,20)}
visible[7].parentSkillLineID=393
local recovered=P.Capture(103)
assert(recovered.scanComplete and recovered.status=='available' and #recovered.entries==4)
assert(row(recovered,185).rank==75 and not row(recovered,43) and not row(recovered,762) and not row(recovered,2947))
assert(row(recovered,393).skillLines==nil and countReads==1 and listReads==7)
-- A visible supported row contradicting an explicit direct absence is useful but incomplete.
visible[#visible+1]=info(129,'First Aid',1,75,0,0)
local inconsistent=P.Capture(104)
assert(inconsistent.available and not inconsistent.scanComplete and row(inconsistent,129).rank==1)
-- A complete list cannot erase a direct observation that is absent from that list.
visible={data[185]}
inconsistent=P.Capture(105)
assert(inconsistent.available and not inconsistent.scanComplete and row(inconsistent,165))
print('PASS: bounded fallback restores failed IDs, excludes unrelated/child skills and flags contradictory membership')

api.GetSkillLineInfoByID=nil
visible={{skillID=11,isHeader=true,isCollapsed=true},{skillID=9,isHeader=true,isCollapsed=true}}
local hidden=P.Capture(106)
assert(hidden.available and not hidden.scanComplete and hidden.status=='partial' and #hidden.entries==0)
visible={{skillID=11,isHeader=true,isCollapsed=false},data[165],{skillID=9,isHeader=true,isCollapsed=false},data[356]}
local listed=P.Capture(107)
assert(listed.available and listed.scanComplete and #listed.entries==2)
visible={}
local empty=P.Capture(108)
assert(empty.available and empty.scanComplete and empty.status=='available' and #empty.entries==0)
visible={data[165],data[165]}
assert(not P.Capture(109).scanComplete,'Duplicate root rows must not appear complete')
visible={secret,data[165]}
local restricted=P.Capture(110)
assert(restricted.available and not restricted.scanComplete and #restricted.entries==1)
local before=listReads
api.GetNumSkillLines=function()return 513 end
local oversized=P.Capture(111)
assert(not oversized.available and not oversized.scanComplete and listReads==before)
api.GetNumSkillLines=function()error('unavailable')end
assert(not P.Capture(112).available)
print('PASS: collapsed/readable/empty list distinctions, duplicate/restricted rows, bounded traversal and failed enumeration')

api.GetSkillLineInfoByID=function()return nil end
local directEmpty=P.Capture(113)
assert(directEmpty.available and directEmpty.scanComplete and #directEmpty.entries==0)
api.GetSkillLineInfoByID=function(id)if id==129 then return secret end;return nil end
local unknown=P.Capture(114)
assert(unknown.available and not unknown.scanComplete and #unknown.entries==0)
api.GetSkillLineInfoByID=function()error('all failed')end
assert(not P.Capture(115).available)
api.GetSkillLineInfoByID=function(id)
    if id==129 then return info(185,'Wrong ID',1,75,0,0) end
    return nil
end
assert(not P.Capture(116).scanComplete)
api.GetSkillLineInfoByID=function(id)
    if id==129 then
        local value=info(129,'Child row',1,75,0,0); value.parentSkillLineID=185; return value
    end
    return nil
end
assert(not P.Capture(117).scanComplete)
api.GetSkillLineInfoByID=function(id)
    if id==129 then return setmetatable({},{__index=function()error('unreadable row')end}) end
    return nil
end
assert(not P.Capture(118).scanComplete)
C_SkillInfo=nil
local unsupported=P.Capture(119)
assert(not unsupported.available and not unsupported.scanComplete and unsupported.status=='unsupported')
print('PASS: supported empty set, unknown membership, malformed identity/children, protected row access and unsupported APIs')
