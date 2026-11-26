-- Read-only, capture-time observations. Unknown/restricted values never become zero.
ExporterStats = {}
local S=ExporterStats
local unpackValues=unpack or table.unpack

local function safe(value,kind)
    local ok,result=pcall(function()
        if (issecretvalue and issecretvalue(value)) or (canaccessvalue and not canaccessvalue(value)) then
            return "restricted"
        end
        if type(value)~=kind then return "unavailable" end
        if kind=="number" and (value~=value or value==math.huge or value==-math.huge) then return "unavailable" end
        if kind=="string" and value=="" then return "unavailable" end
        return "available"
    end)
    return ok and result or "restricted"
end
local function read(fn,count,...)
    local values,statuses={},{}
    if type(fn)~="function" then
        for i=1,count do statuses[i]="unsupported" end
        return values,statuses
    end
    local args={...}
    local ok=pcall(function() values={fn(unpackValues(args))} end)
    for i=1,count do
        statuses[i]=ok and safe(values[i],"number") or "api_error"
        if statuses[i]~="available" then values[i]=nil end
    end
    return values,statuses
end
local function field(out,key,value,status)
    out.fieldStatus=out.fieldStatus or {}
    out.fieldStatus[key]=status or "unavailable"
    if status=="available" then out[key]=value end
end
local function finish(out)
    local good,total,unsupported=0,0,0
    for _,status in pairs(out.fieldStatus) do
        total=total+1
        if status=="available" then good=good+1 elseif status=="unsupported" then unsupported=unsupported+1 end
    end
    out.available=good>0
    out.status=good==total and "available" or (good>0 and "partial" or (unsupported==total and "unsupported" or "unavailable"))
    return out
end
local function measure(fn,keys,...)
    local values,statuses=read(fn,#keys,...)
    local out={}
    for i,key in ipairs(keys) do field(out,key,values[i],statuses[i]) end
    return finish(out)
end
local function scalar(fn,...)
    return measure(fn,{"value"},...)
end
local function calculated(out,key,dependencies,fn)
    for _,name in ipairs(dependencies) do
        if out.fieldStatus[name]~="available" then field(out,key,nil,"unavailable"); return end
    end
    local ok,value=pcall(fn)
    local status=ok and safe(value,"number") or "unavailable"
    field(out,key,value,status)
end
local function summarize(out)
    local good,total,complete=0,0,0
    for _,child in pairs(out) do
        if type(child)=="table" and child.status then
            total=total+1
            if child.available then good=good+1 end
            if child.status=="available" or child.status=="not_applicable" then complete=complete+1 end
        end
    end
    out.available=good>0
    out.status=complete==total and "available" or (good>0 and "partial" or "unavailable")
    return out
end

function S.Basic(capturedAt)
    local out={capturedAt=capturedAt}
    local function textField(key,fn,...)
        local args={...}; local ok,value=pcall(function() return fn(unpackValues(args)) end)
        field(out,key,value,ok and safe(value,"string") or (type(fn)=="function" and "api_error" or "unsupported"))
    end
    textField("name",UnitName,"player")
    local levels,statuses=read(UnitLevel,1,"player");field(out,"level",levels[1],statuses[1])
    local ok,name,token,id=pcall(function() return UnitClass("player") end)
    local failure=type(UnitClass)=="function" and "api_error" or "unsupported"
    field(out,"className",name,ok and safe(name,"string") or failure)
    field(out,"classToken",token,ok and safe(token,"string") or failure)
    field(out,"classID",id,ok and safe(id,"number") or failure)
    textField("raceName",UnitRace,"player")
    textField("faction",UnitFactionGroup,"player")
    local function integerField(target,key,fn,...)
        local values,statuses=read(fn,1,...)
        local value,status=values[1],statuses[1]
        if status=="available" and (value<0 or value~=math.floor(value)) then status="unavailable" end
        field(target,key,value,status)
    end
    integerField(out,"moneyCopper",GetMoney)
    local xp={}
    integerField(xp,"current",UnitXP,"player")
    integerField(xp,"levelTotal",UnitXPMax,"player")
    integerField(xp,"rested",GetXPExhaustion)
    local disabledOK,disabled=pcall(function() return IsXPUserDisabled() end)
    field(xp,"disabled",disabled,disabledOK and safe(disabled,"boolean")
        or (type(IsXPUserDisabled)=="function" and "api_error" or "unsupported"))
    finish(xp)
    field(out,"xp",xp,xp.available and "available" or xp.status)
    finish(out)
    if out.available and xp.status~="available" then out.status="partial" end
    return out
end

function S.Location(capturedAt)
    local out={capturedAt=capturedAt}
    for _,entry in ipairs({{"zone",GetZoneText},{"subzone",GetSubZoneText}}) do
        local ok,value=pcall(function() return entry[2]() end)
        field(out,entry[1],value,ok and safe(value,"string") or (type(entry[2])=="function" and "api_error" or "unsupported"))
    end
    local maps,statuses=read(C_Map and C_Map.GetBestMapForUnit,1,"player")
    field(out,"mapID",maps[1],statuses[1])
    local positionFn=C_Map and C_Map.GetPlayerMapPosition
    local ok,x,y=pcall(function()
        if not maps[1] or type(positionFn)~="function" then return end
        local position=positionFn(maps[1],"player")
        if position then return position:GetXY() end
    end)
    local failure=type(positionFn)=="function" and "unavailable" or "unsupported"
    field(out,"x",x,ok and type(positionFn)=="function" and safe(x,"number") or failure)
    field(out,"y",y,ok and type(positionFn)=="function" and safe(y,"number") or failure)
    return finish(out)
end

local schools={{"holy",2},{"fire",3},{"nature",4},{"frost",5},{"shadow",6},{"arcane",7}}
local function bySchool(fn)
    local out={}
    for _,school in ipairs(schools) do out[school[1]]=scalar(fn,school[2]) end
    return summarize(out)
end
local function attackPower(fn)
    local out=measure(fn,{"base","positiveBonus","negativeBonus"},"player")
    calculated(out,"effective",{"base","positiveBonus","negativeBonus"},function()
        return math.max(0,out.base+out.positiveBonus+out.negativeBonus)
    end)
    return finish(out)
end
local function weapon(ranged,speeds,speedStatus)
    if ranged then
        local fn=GetInventoryItemID
        if type(fn)=="function" then
            local ok,id=pcall(fn,"player",18)
            if ok and safe(id,"number")=="unavailable" and type(id)=="nil" then
                return {available=false,status="not_applicable",reason="No ranged weapon equipped"}
            end
        end
    end
    local out={}
    if ranged then
        local values,statuses=read(UnitRangedDamage,6,"player")
        for i,key in ipairs({"minimumDamage","maximumDamage","positiveBonus","negativeBonus","damageMultiplier"}) do
            field(out,key,values[i+1],statuses[i+1])
        end
        -- Forever's character panel uses UnitAttackSpeed's third return for ranged.
        local speed,status=speeds[3],speedStatus[3]
        if status~="available" then speed,status=values[1],statuses[1] end
        field(out,"attackSpeedSeconds",speed,status)
    else
        local values,statuses=read(UnitDamage,7,"player")
        for _,entry in ipairs({{"minimumDamage",1},{"maximumDamage",2},{"positiveBonus",5},{"negativeBonus",6},{"damageMultiplier",7}}) do
            field(out,entry[1],values[entry[2]],statuses[entry[2]])
        end
        field(out,"attackSpeedSeconds",speeds[1],speedStatus[1])
    end
    calculated(out,"damagePerSecond",{"minimumDamage","maximumDamage","attackSpeedSeconds"},function()
        if out.attackSpeedSeconds<=0 then return end
        return (out.minimumDamage+out.maximumDamage)/2/out.attackSpeedSeconds
    end)
    return finish(out)
end
function S.Capture(capturedAt)
    local speed=measure(GetUnitSpeed,{"current","run","flight","swim"},"player")
    speed.unit="yards_per_second";speed.normalRunSpeed=7
    calculated(speed,"currentPercent",{"current"},function()return speed.current/7*100 end)
    calculated(speed,"runPercent",{"run"},function()return speed.run/7*100 end)
    local general=summarize({health=measure(UnitHealthMax,{"maximum"},"player"),
        mana=measure(UnitPowerMax,{"maximum"},"player",0),movementSpeed=finish(speed)})
    local primary={}
    for index,name in ipairs({"strength","agility","stamina","intellect","spirit"}) do
        primary[name]=measure(UnitStat,{"current","effective","positiveBonus","negativeBonus"},"player",index)
    end
    local speeds,statuses=read(UnitAttackSpeed,3,"player")
    local weapons=summarize({mainHand=weapon(false,speeds,statuses),ranged=weapon(true,speeds,statuses),
        attackPower=summarize({melee=attackPower(UnitAttackPower),ranged=attackPower(UnitRangedAttackPower)})})
    local modifiers=summarize({criticalStrike=summarize({melee=scalar(GetCritChance),ranged=scalar(GetRangedCritChance),
        spell=bySchool(GetSpellCritChance)}),haste=summarize({melee=scalar(GetMeleeHaste),ranged=scalar(GetRangedHaste),
        spell=scalar(UnitSpellHaste,"player")}),spellDamage=bySchool(GetSpellBonusDamage),spellHealing=scalar(GetSpellBonusHealing)})
    local defenseSkill=measure(UnitDefenseSkill,{"base","modifier"},"player")
    calculated(defenseSkill,"effective",{"base","modifier"},function()return defenseSkill.base+defenseSkill.modifier end)
    local defense=summarize({defense=finish(defenseSkill),dodge=scalar(GetDodgeChance),
        armor=measure(UnitArmor,{"base","effective","armor","bonus"},"player")})
    local resistances={}
    for _,entry in ipairs({{"arcane","Arcane",6},{"fire","Fire",2},{"frost","Frost",4},{"nature","Nature",3},{"shadow","Shadow",5}}) do
        local index=Enum and Enum.Damageclass and Enum.Damageclass[entry[2]] or entry[3]
        resistances[entry[1]]=measure(UnitResistance,{"base","real","effective","bonus"},"player",index)
    end
    local out=summarize({general=general,primaryAttributes=summarize(primary),weapons=weapons,
        modifiers=modifiers,defense=defense,resistances=summarize(resistances)})
    out.capturedAt=capturedAt
    return out
end
