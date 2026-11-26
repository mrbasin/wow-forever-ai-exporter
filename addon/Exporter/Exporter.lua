-- Standalone Exporter. Only WoW runs this addon; consumers are separate.
Exporter = {version="1.0.0", ready=false, pending=false, suspended=false, sequence=0}
local E=Exporter
E.displayName="AI Exporter"
E.defaultIntervalMinutes=1
E.maxIntervalMinutes=60
E.categories={{"basic","Basic"},{"location","Location in game"},{"characterStats","Character Stats"},{"equipment","Equipment"},{"talents","Talents"},{"spellbook","Spellbook"},{"questLog","Quest Log"},{"items","Items"},{"professions","Professions"}}
local missingCell={} -- Schema-5 record tables use JSON null only for absent fields.
local arrayMarker={} -- Preserve empty-array type when a field becomes a table cell.
local arrayKeys={columns=true,rows=true,slots=true,tooltipLines=true,sockets=true,trees=true,selectedTalents=true,currencies=true,
    groups=true,nodes=true,groupIDs=true,entries=true,edges=true,prerequisites=true,costs=true,conditions=true,
    skillLines=true,powerCosts=true,headers=true,objectives=true,questIDs=true,pendingTitleIDs=true,
    unavailableTitleIDs=true,items=true,choices=true,spells=true,majorFactionReputation=true,bags=true,incompleteFields=true}
local lastToolbarChange=-math.huge
local shortEscapes={['"']='\\"',["\\"]="\\\\",["\n"]="\\n",["\r"]="\\r",["\t"]="\\t",["\b"]="\\b",["\f"]="\\f"}
local function quote(s)
    return '"'..tostring(s):gsub('[%z\1-\31\\"]',function(c)
        return shortEscapes[c] or string.format('\\u%04x',string.byte(c)) end)..'"'
end
local function json(value,key)
    if value==missingCell then return "null" end
    local kind=type(value)
    if kind=="string" then return quote(value) end
    if kind=="boolean" then return value and "true" or "false" end
    if kind=="number" then
        if value~=value or value==math.huge or value==-math.huge then return "null" end
        return tostring(value)
    end
    if kind~="table" then return "null" end
    local result={}
    if getmetatable(value)==arrayMarker or value[1]~=nil or (arrayKeys[key] and next(value)==nil) then
        for _,v in ipairs(value) do result[#result+1]=json(v) end
        return '['..table.concat(result,',')..']'
    end
    -- Keep repeated record fields together in the same order for compression.
    -- Array order remains the collector's order; only object keys are sorted.
    local keys={}; for k in pairs(value) do keys[#keys+1]=k end
    table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
    for _,k in ipairs(keys) do result[#result+1]=quote(k)..':'..json(value[k],k) end
    return '{'..table.concat(result,',')..'}'
end
E.JSON=json
local function call(fn,...)
    if type(fn)~="function" then return nil end
    local ok,value=pcall(fn,...)
    if ok then return value end
end
local function clone(value)
    if type(value)~="table" then return value end
    local result={}; for k,v in pairs(value) do result[k]=clone(v) end; return result
end
local function unavailable(status,reason)
    return {available=false,status=status,reason=reason}
end
local function readSection(fn)
    local ok,value=pcall(fn)
    return ok and value or unavailable("unavailable","This client could not provide this section")
end

local function normalizeSettings(saved)
    if type(saved)~="table" then saved={} end
    local settings={schemaVersion=5,enabled=saved.enabled~=false,periodic=saved.periodic~=false,
        intervalMinutes=tonumber(saved.intervalMinutes) or E.defaultIntervalMinutes,sections={}}
    if settings.intervalMinutes~=settings.intervalMinutes or settings.intervalMinutes==math.huge
        or settings.intervalMinutes==-math.huge then settings.intervalMinutes=E.defaultIntervalMinutes end
    -- Upgrade previous defaults once; later explicit choices are retained.
    local settingsVersion=tonumber(saved.schemaVersion) or 0
    if (settingsVersion==3 and settings.intervalMinutes==60)
        or (settingsVersion==4 and settings.intervalMinutes==5) then
        settings.intervalMinutes=E.defaultIntervalMinutes
    end
    settings.intervalMinutes=math.max(1,math.min(E.maxIntervalMinutes,math.floor(settings.intervalMinutes)))
    local selected=type(saved.sections)=="table" and saved.sections or {}
    for _,category in ipairs(E.categories) do settings.sections[category[1]]=selected[category[1]]~=false end
    return settings
end
E.NormalizeSettings=normalizeSettings

-- Collectors keep diagnostics for correctness and retries. Only the exported
-- view is compact: absent fields mean unavailable, never zero/false/empty.
local metadata={available=true,status=true,fieldStatus=true,statStatus=true,availability=true,reason=true,
    pendingTitleIDs=true,unavailableTitleIDs=true}
local sections={basic=true,location=true,characterStats=true,equipment=true,talents=true,
    spellbook=true,questLog=true,items=true,professions=true,active=true,completedHistory=true}
local statusFields={tooltipStatus="tooltipLines",statsStatus="stats",powerCostsStatus="powerCosts",
    castTimeStatus="castTimeMs",baseCooldownStatus="baseCooldownMs",objectivesStatus="objectives",
    itemsStatus="items",choicesStatus="choices",currenciesStatus="currencies",spellsStatus="spells",
    majorFactionReputationStatus="majorFactionReputation",tagStatus="tag",conditionsStatus="conditions",
    costsStatus="costs",currencyStatus="currencies",edgesStatus="edges",entriesStatus="entries",
    groupIDsStatus="groupIDs",groupsStatus="groups",nodesStatus="nodes",nameStatus="name",
    descriptionStatus="description",titleStatus="title",rankStatus="rank"}
local function compact(value,key,inheritedStamp,edgesComplete,parent)
    if type(value)~="table" then return value end
    if sections[key] and value.available==false then return nil end
    if next(value)==nil then return {} end -- A known empty container stays empty.
    local stamp=value.capturedAt or inheritedStamp
    local out={}
    if value[1]~=nil then
        for _,entry in ipairs(value) do
            local item=compact(entry,nil,stamp,edgesComplete,value)
            if item==nil then item={} end
            out[#out+1]=item
        end
        return out
    end
    local skip,partial={},{}
    if key=="basic" then skip.classID=true; skip.classToken=true end
    local function availability(field,status)
        if not status or status=="available" or status=="no_cost" then return end
        if status=="partial" and type(value[field])=="table" and next(value[field])~=nil then
            partial[field]=true
        else skip[field]=true end
    end
    for field,status in pairs(value.fieldStatus or {}) do availability(field,status) end
    for statusField,field in pairs(statusFields) do availability(field,value[statusField]) end
    if key=="stats" and parent then
        for field,status in pairs(parent.statStatus or {}) do availability(field,status) end
    end
    if value.highestLearnedRankStatus and value.highestLearnedRankStatus~="available" then
        skip.highestLearnedRank=true; skip.isHighestLearnedRank=true
    end
    if key=="enhancements" then
        availability("sockets",value.status); availability("emptySockets",value.status)
        availability("emptySockets",parent and parent.statsStatus)
    end
    -- Prerequisites are derived from other nodes' outgoing edges, and top-level
    -- talent currencies are aggregated from all trees. Their coverage matters.
    if type(value.nodes)=="table" then
        edgesComplete=true
        for _,node in ipairs(value.nodes) do
            if node.edgesStatus and node.edgesStatus~="available" then edgesComplete=false end
        end
    end
    if value.prerequisites and edgesComplete==false then availability("prerequisites","partial") end
    if key=="talents" then
        for _,tree in ipairs(value.trees or {}) do
            if tree.currencyStatus and tree.currencyStatus~="available" then availability("currencies","partial") end
        end
    end
    for field,child in pairs(value) do
        local isMetadata=metadata[field] or (type(field)=="string" and field:sub(-6)=="Status")
        if not isMetadata and not skip[field] and not (parent==nil and field=="export")
            and not (field=="capturedAt" and child==inheritedStamp) then
            out[field]=compact(child,field,stamp,edgesComplete,value)
        end
    end
    local incomplete={}
    for field in pairs(partial) do
        if out[field]~=nil then incomplete[#incomplete+1]=field end
    end
    if #incomplete>0 then table.sort(incomplete); out.incompleteFields=incomplete end
    return next(out)~=nil and out or nil
end
-- Character Stats is a summary of effective observations for AI input. Keep
-- collection precision and diagnostic breakdowns internally, not in this view.
local function compactStats(stats)
    if type(stats)~="table" then return nil end
    local out={}
    local function get(...)
        local value=stats
        for i=1,select("#",...) do
            if type(value)~="table" then return nil end
            value=value[select(i,...)]
        end
        return value
    end
    local function put(target,key,value)
        if type(value)~="number" or value~=value or value==math.huge or value==-math.huge then return end
        if value~=math.floor(value) then
            local rounded=(value<0 and math.ceil(value*100-0.5) or math.floor(value*100+0.5))/100
            -- A tiny known rate must never become a false zero.
            if rounded~=0 then value=rounded end
        end
        target[key]=value
    end
    local function group(target,key,value)
        if next(value)~=nil then target[key]=value end
    end
    put(out,"maxHealth",get("general","health","maximum"))
    put(out,"maxMana",get("general","mana","maximum"))
    local movement,attributes={},{}
    for _,key in ipairs({"current","run","flight","swim"}) do put(movement,key,get("general","movementSpeed",key)) end
    group(out,"movementSpeedYardsPerSecond",movement)
    for _,key in ipairs({"strength","agility","stamina","intellect","spirit"}) do
        put(attributes,key,get("primaryAttributes",key,"effective"))
    end
    group(out,"attributes",attributes)
    local weapons,power={},{}
    for _,key in ipairs({"mainHand","ranged"}) do
        local weapon={}
        put(weapon,"minimumDamage",get("weapons",key,"minimumDamage"))
        put(weapon,"maximumDamage",get("weapons",key,"maximumDamage"))
        put(weapon,"speedSeconds",get("weapons",key,"attackSpeedSeconds"))
        put(weapon,"estimatedDps",get("weapons",key,"damagePerSecond"))
        group(weapons,key,weapon)
    end
    for _,key in ipairs({"melee","ranged"}) do put(power,key,get("weapons","attackPower",key,"effective")) end
    group(weapons,"attackPower",power); group(out,"weapons",weapons)
    local crit,spellCrit,haste,spellDamage={},{},{},{}
    for _,key in ipairs({"melee","ranged"}) do put(crit,key,get("modifiers","criticalStrike",key,"value")) end
    for _,key in ipairs({"melee","ranged","spell"}) do put(haste,key,get("modifiers","haste",key,"value")) end
    for _,school in ipairs({"holy","fire","nature","frost","shadow","arcane"}) do
        put(spellCrit,school,get("modifiers","criticalStrike","spell",school,"value"))
        put(spellDamage,school,get("modifiers","spellDamage",school,"value"))
    end
    group(crit,"spell",spellCrit); group(out,"critPercent",crit)
    group(out,"hastePercent",haste); group(out,"spellDamageBonus",spellDamage)
    put(out,"spellHealingBonus",get("modifiers","spellHealing","value"))
    local defense,resistances={},{}
    put(defense,"armor",get("defense","armor","effective"))
    put(defense,"skill",get("defense","defense","effective"))
    put(defense,"dodgePercent",get("defense","dodge","value"))
    group(out,"defense",defense)
    for _,school in ipairs({"arcane","fire","frost","nature","shadow"}) do
        put(resistances,school,get("resistances",school,"effective"))
    end
    group(out,"resistances",resistances)
    if next(out)==nil then return nil end
    out.capturedAt=stats.capturedAt -- Retain an older observation when necessary.
    return out
end
-- Equipment keeps exact item observations with less repeated structure.
local equipmentSlotKeys={"head","neck","shoulder","shirt","chest","waist","legs","feet","wrist","hands",
    "finger1","finger2","trinket1","trinket2","back","mainHand","offHand","ranged","tabard"}
local itemStatKeys={
    ITEM_MOD_STRENGTH_SHORT="strength",ITEM_MOD_AGILITY_SHORT="agility",ITEM_MOD_STAMINA_SHORT="stamina",
    ITEM_MOD_INTELLECT_SHORT="intellect",ITEM_MOD_SPIRIT_SHORT="spirit",ITEM_MOD_HEALTH_SHORT="health",
    ITEM_MOD_MANA_SHORT="mana",ITEM_MOD_SPELL_POWER_SHORT="spellPower",
    ITEM_MOD_SPELL_DAMAGE_DONE_SHORT="spellDamage",ITEM_MOD_SPELL_HEALING_DONE_SHORT="spellHealing",
    ITEM_MOD_HEALTH_REGEN_SHORT="healthRegen",ITEM_MOD_MANA_REGENERATION_SHORT="manaRegen",
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT="damagePerSecond",ITEM_MOD_ARCANE_RESISTANCE_SHORT="arcaneResistance",
}
local function compactEquipment(gear)
    if type(gear)~="table" then return nil end
    local out={capturedAt=gear.capturedAt,scanComplete=gear.scanComplete,bySlot={}}
    for _,slot in ipairs(gear.slots or {}) do
        local key=equipmentSlotKeys[slot.slotID]
        assert(key,"Unknown equipment slot in export")
        assert(out.bySlot[key]==nil,"Duplicate equipment slot in export")
        if slot.empty==true then out.bySlot[key]=false
        else
            local item={}
            for field,value in pairs(slot) do
                if field~="slotID" and field~="slotName" and not (field=="empty" and slot.itemID~=nil) then
                    item[field]=value
                end
            end
            out.bySlot[key]=item
        end
    end
    return out
end
-- Keep descriptive columns once for dense repeated records. Small/sparse lists
-- stay as objects; values, row order and absence are retained exactly.
local recordLists={entries=true,nodes=true,selectedTalents=true,powerCosts=true,conditions=true,costs=true,
    objectives=true,items=true,choices=true,currencies=true,spells=true,headers=true,skillLines=true,bags=true,
    edges=true,prerequisites=true,groups=true,sockets=true}
local function compactRecords(value,key)
    if type(value)~="table" then return value end
    local out=value -- This is already a detached export view; avoid another full copy.
    if value[1]~=nil or (arrayKeys[key] and next(value)==nil) then setmetatable(out,arrayMarker) end
    for field,child in pairs(value) do out[field]=compactRecords(child,field) end
    if key=="stats" then
        local stats={}
        for token,child in pairs(out) do
            local name=itemStatKeys[token]
            -- Unknown client tokens must never be overwritten by an alias.
            if not name or out[name]~=nil then name=token end
            stats[name]=child
        end
        return stats
    end
    if key=="tooltipLines" then
        for i,line in ipairs(out) do
            if type(line)=="table" and type(line.left)=="string"
                and next(line)=="left" and next(line,"left")==nil then out[i]=line.left end
        end
        return out
    end
    if not recordLists[key] or #out<4 then return out end
    local columns,seen={},{}
    local present,keyBytes=0,0
    for _,record in ipairs(out) do
        if type(record)~="table" then return out end
        for field in pairs(record) do
            if type(field)~="string" then return out end
            if not seen[field] then seen[field]=true; columns[#columns+1]=field end
            present=present+1; keyBytes=keyBytes+#quote(field)+1
        end
    end
    local cells=#out*#columns
    if #columns<2 or present<cells*0.6 then return out end
    table.sort(columns)
    -- Estimate structural savings without serializing every large subtree.
    if keyBytes-(cells-present)*5<=#json(columns)+40 then return out end
    local rows={}
    for i,record in ipairs(out) do
        local row={}
        for j,field in ipairs(columns) do
            local cell=record[field]
            row[j]=cell==nil and missingCell or cell
        end
        rows[i]=row
    end
    return {columns=columns,rows=rows}
end
function E.CompactSnapshot(state)
    local result=assert(compact(state),"Snapshot has no data")
    result.characterStats=compactStats(result.characterStats)
    result.equipment=compactEquipment(result.equipment)
    result.schemaVersion=5
    return compactRecords(result)
end

local function snapshot()
    local settings=ExporterSettings
    local selected=settings.sections
    local state={schemaVersion=5,sourceAddon="Exporter",addonVersion=E.version,capturedAt=GetServerTime(),
        captureSequence=E.sequence+1,character={guid=call(UnitGUID,"player")},availability={},
        export={mode=settings.periodic and "periodic" or "adhoc",intervalMinutes=settings.intervalMinutes,sections=clone(selected)}}
    assert(type(state.character.guid)=="string" and state.character.guid~="","Character identity is not ready")
    assert(ExporterDataRequests and type(ExporterDataRequests.BeginCapture)=="function"
        and type(ExporterDataRequests.EndCapture)=="function","Shared data-loading limits unavailable")
    ExporterDataRequests.BeginCapture()
    for _,entry in ipairs({{"basic",ExporterStats.Basic},{"location",ExporterStats.Location},{"characterStats",ExporterStats.Capture},
        {"equipment",ExporterEquipment and ExporterEquipment.Capture},{"talents",ExporterTalents and ExporterTalents.Capture},
        {"spellbook",ExporterSpellbook and ExporterSpellbook.Capture},{"questLog",ExporterQuestLog and ExporterQuestLog.Capture},
        {"items",ExporterItems and ExporterItems.Capture},{"professions",ExporterProfessions and ExporterProfessions.Capture}}) do
        local key,fn=entry[1],entry[2]
        state[key]=selected[key] and readSection(function()return fn(state.capturedAt)end) or unavailable("disabled")
        state.availability[key]=state[key].available==true
    end
    ExporterDataRequests.EndCapture()
    local encoded=json(E.CompactSnapshot(state))
    assert(#encoded<=450000,"Snapshot exceeds the export size budget")
    return encoded,state
end

local prefix="EXP1:"
local originalLayout,lastLayout,lastAttempt,nextDue
local function checksum(s)
    local a,b=0,0; for i=1,#s do a=(a+s:byte(i))%255; b=(b+a)%255 end; return b*256+a
end
E.Checksum=checksum
local function owned(marker) return type(marker)=="string" and marker:sub(1,#prefix)==prefix end
local function decode(raw)
    if raw=="" then return {[1]=5,[2]={},[3]={},[4]={}} end
    assert(type(raw)=="string" and #raw<=524288 and raw:sub(1,2)=="1|","Unsupported cooldown cache format")
    local codec=C_EncodingUtil
    local data=codec.DeserializeCBOR(codec.DecompressString(codec.DecodeBase64(raw:sub(3)),Enum.CompressionMethod.Deflate))
    assert(type(data)=="table" and type(data[1])=="number" and data[1]>=1 and data[1]<=5,"Unsupported layout version")
    return data
end
local function encode(data)
    local codec=C_EncodingUtil; local serialized=codec.SerializeCBOR(data)
    assert(type(serialized)=="string" and #serialized<=524288,"Layout exceeds size budget")
    return "1|"..codec.EncodeBase64(codec.CompressString(serialized,Enum.CompressionMethod.Deflate))
end
local function publish()
    assert(C_CooldownViewer and type(C_CooldownViewer.GetLayoutData)=="function"
        and type(C_CooldownViewer.SetLayoutData)=="function" and C_EncodingUtil,"Export APIs unavailable")
    local current=C_CooldownViewer.GetLayoutData(); local data=decode(current)
    assert(data[127]==nil or owned(data[127]),"Another exporter owns the cache slot; disable the conflicting addon first")
    local payload,state=snapshot()
    if current~=lastLayout then
        if owned(data[127]) then data[127]=nil; originalLayout=encode(data) else originalLayout=current end
    end
    data[127]=prefix..string.format("%04X",checksum(payload))..":"..payload
    local encoded=encode(data)
    assert(decode(encoded)[127]==data[127],"Export encoding check failed")
    C_CooldownViewer.SetLayoutData(encoded); lastLayout=encoded
    assert(C_CooldownViewer.GetLayoutData()==encoded,"WoW rejected the export")
    E.lastExportSize={encodedBytes=#encoded,jsonBytes=#payload}
    E.sequence=E.sequence+1; E.lastSnapshot=state; ExporterSnapshotJSON=payload
end
function E.Cleanup()
    if call(InCombatLockdown) then E.cleanupPending=true; return end
    E.cleanupPending=false
    if not lastLayout then return end
    local current=C_CooldownViewer.GetLayoutData()
    if current==lastLayout then C_CooldownViewer.SetLayoutData(originalLayout)
    else local data=decode(current); if owned(data[127]) then data[127]=nil; C_CooldownViewer.SetLayoutData(encode(data)) end end
    originalLayout,lastLayout=nil,nil
end
function E.RequestExport()
    if not E.ready or not ExporterSettings.enabled then return false,"Exporting is disabled" end
    E.suspended=false; E.pending=true; E.status="Export queued"; return true
end
function E.Tick()
    if not E.ready then return end
    if E.cleanupPending and not call(InCombatLockdown) then
        local ok=pcall(E.Cleanup); if not ok then E.cleanupPending=false end
    end
    if not ExporterSettings.enabled or E.suspended then return end
    local now=GetTime()
    if not E.pending and not (ExporterSettings.periodic and (not nextDue or now>=nextDue)) then return end
    if call(InCombatLockdown) then E.status="Waiting until combat ends"; return end
    if now-lastToolbarChange<2 then E.status="Waiting for toolbar edits to finish"; return end
    -- Login can load the addon before the player exists. Wait for that normal
    -- transition instead of treating it as an export failure that needs a retry.
    local guid=call(UnitGUID,"player")
    if type(guid)~="string" or guid=="" then E.status="Waiting for character identity"; return end
    if lastAttempt and now-lastAttempt<30 then E.status="Export queued (30-second minimum interval)"; return end
    lastAttempt=now; nextDue=now+ExporterSettings.intervalMinutes*60; E.pending=false
    local ok,err=pcall(publish)
    if ok then E.status="Snapshot sent to WoW; disk delivery may be delayed"
    else
        -- Require an explicit retry; an unattended timer must not repeat a failed write.
        E.suspended=true; E.pending=false
        E.status="Export failed: "..tostring(err)..". Automatic exports paused; use Export now to retry."
    end
    if E.RefreshOptions then E.RefreshOptions() end
end
local function redact()
    local state=E.lastSnapshot
    if not state then ExporterSnapshotJSON=nil; return end
    for _,category in ipairs(E.categories) do
        local key=category[1]
        if not ExporterSettings.sections[key] then
            state[key]=unavailable("disabled")
            state.availability[key]=false
        end
    end
    state.export.sections=clone(ExporterSettings.sections)
    ExporterSnapshotJSON=json(E.CompactSnapshot(state)) -- Preserve capture time and omit disabled data.
end
function E.ApplySettings()
    ExporterSettings=normalizeSettings(ExporterSettings); redact()
    E.suspended=false
    nextDue=GetTime()+ExporterSettings.intervalMinutes*60
    if ExporterSettings.enabled then E.RequestExport()
    else E.pending=false; pcall(E.Cleanup); E.status="Exporting disabled; existing files may retain earlier snapshots" end
    if E.RefreshOptions then E.RefreshOptions() end
end
function E.OutputPath()
    if type(ExporterLocalPaths)=="table" and type(ExporterLocalPaths.cacheFiles)=="table" then
        if #ExporterLocalPaths.cacheFiles==1 then return ExporterLocalPaths.cacheFiles[1] end
        if #ExporterLocalPaths.cacheFiles>1 then return table.concat(ExporterLocalPaths.cacheFiles,"\n") end
    end
    return "<WoW folder>\\WTF\\Account\\<account>\\<realm folder>\\<character folder>\\cooldownmanager.txt"
end
function E.OnEvent(event,name,success)
    if event=="ADDON_LOADED" and name=="Exporter" then
        -- Do not retain schema-1 snapshots containing categories no longer selected.
        if type(ExporterSettings)~="table" or (ExporterSettings.schemaVersion~=2 and ExporterSettings.schemaVersion~=3
            and ExporterSettings.schemaVersion~=4 and ExporterSettings.schemaVersion~=5) then ExporterSnapshotJSON=nil end
        ExporterSettings=normalizeSettings(ExporterSettings)
        if type(ExporterSnapshotJSON)~="string" then ExporterSnapshotJSON=nil end
        E.ready=true; E.status="Ready"; if E.CreateOptions then E.CreateOptions() end
    elseif event=="SPELL_DATA_LOAD_RESULT" then
        call(ExporterDataRequests and ExporterDataRequests.OnEvent,event,name,success)
        call(ExporterTalents and ExporterTalents.OnEvent,event,name,success)
        call(ExporterSpellbook and ExporterSpellbook.OnEvent,event,name,success)
    elseif event=="QUEST_DATA_LOAD_RESULT" or event=="QUEST_LOG_UPDATE" then
        call(ExporterQuestLog and ExporterQuestLog.OnEvent,event,name,success)
    elseif event=="ITEM_DATA_LOAD_RESULT" or event=="GET_ITEM_INFO_RECEIVED" or event=="BAG_UPDATE"
        or event=="BAG_UPDATE_DELAYED" or event=="ITEM_LOCK_CHANGED" then
        call(ExporterDataRequests and ExporterDataRequests.OnEvent,event,name,success)
        call(ExporterItems and ExporterItems.OnEvent,event,name,success)
    elseif event=="ACTIONBAR_SLOT_CHANGED" or event=="ACTIONBAR_PAGE_CHANGED" then lastToolbarChange=GetTime()
    elseif event=="PLAYER_ENTERING_WORLD" and E.ready and ExporterSettings.periodic then nextDue=GetTime()
    elseif event=="PLAYER_LOGOUT" then
        -- Preserve the last successful snapshot and its timestamp. Do not scan or
        -- request metadata outside the capture gate while the session shuts down.
        pcall(E.Cleanup)
    end
end
local frame=CreateFrame("Frame")
for _,event in ipairs({"ADDON_LOADED","PLAYER_ENTERING_WORLD","PLAYER_LOGOUT","ACTIONBAR_SLOT_CHANGED","ACTIONBAR_PAGE_CHANGED","SPELL_DATA_LOAD_RESULT","QUEST_DATA_LOAD_RESULT","QUEST_LOG_UPDATE","ITEM_DATA_LOAD_RESULT","GET_ITEM_INFO_RECEIVED","BAG_UPDATE","BAG_UPDATE_DELAYED","ITEM_LOCK_CHANGED"}) do frame:RegisterEvent(event) end
frame:SetScript("OnEvent",function(_,...) E.OnEvent(...) end)
C_Timer.NewTicker(2,E.Tick)
SLASH_EXPORTER1="/exporter"
SlashCmdList.EXPORTER=function(message)
    message=(message or ""):lower():match("^%s*(.-)%s*$")
    if not E.ready then print(E.displayName.." is not ready"); return end
    if message=="now" then E.RequestExport(); E.Tick(); print(E.displayName..": "..E.status)
    elseif message=="status" then print(E.displayName.." "..E.version..": "..E.status)
    elseif message=="path" then print(E.displayName.." character export source: "..E.OutputPath())
    elseif message=="off" or message=="on" then ExporterSettings.enabled=message=="on"; E.ApplySettings(); print(E.displayName..": "..E.status)
    elseif E.OpenOptions then E.OpenOptions() end
end
