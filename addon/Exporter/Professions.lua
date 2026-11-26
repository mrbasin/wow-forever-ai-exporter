-- Read-only capture of the twelve supported Forever profession roots.
-- Adapted from MIT-licensed source; see LICENSE and THIRD_PARTY.md.
ExporterProfessions = {}
local P=ExporterProfessions
local professionIDs={129,164,165,171,182,185,186,197,202,333,356,393}
local secondary={[129]=true,[185]=true,[356]=true}
local supported={}; for _,id in ipairs(professionIDs) do supported[id]=true end
local MAX_SKILL_LINES=512

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
local function integer(value)
    return valid(value,"number") and value>=0 and value==math.floor(value)
end
local function member(source,key)
    if not valid(source,"table") then return nil,"unavailable" end
    local ok,value=pcall(function() return source[key] end)
    if not ok then return nil,"api_error" end
    if not accessible(value) then return nil,"restricted" end
    return value,"available"
end
local function read(fn,...)
    if type(fn)~="function" then return nil,"unsupported" end
    local ok,value=pcall(fn,...)
    if not ok then return nil,"api_error" end
    if not accessible(value) then return nil,"restricted" end
    return value,"available"
end
local function field(out,key,value,status,kind)
    if status=="available" then
        if not valid(value,kind) or (kind=="string" and value=="") then status="unavailable"
        elseif (key=="rank" or key=="maxRank") and not integer(value) then status="unavailable" end
    end
    if status=="available" and kind=="string" then
        value=value:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")
            :gsub("|H.-|h(.-)|h","%1"):gsub("|T.-|t",""):gsub("|A.-|a","")
        if value=="" then status="unavailable" end
    end
    out.fieldStatus[key]=status
    if status=="available" then out[key]=value else out.status="partial" end
end
local function entry(info,requestedID)
    if not valid(info,"table") then return nil end
    local header=member(info,"isHeader")
    if header~=false then return nil end
    local id,idStatus=member(info,"skillID")
    if id==nil and idStatus=="available" then id=requestedID end
    if not integer(id) or not supported[id] or (requestedID and id~=requestedID) then return nil end
    -- Do not export expansion-specific child rows as supported root skills.
    local parent,parentStatus=member(info,"parentSkillLineID")
    if parentStatus=="available" and integer(parent) and parent>0 and parent~=id then return nil end
    local out={skillLineID=id,category=secondary[id] and "secondary" or "primary",status="available",fieldStatus={}}
    for _,spec in ipairs({{"name","string"},{"rank","number"},{"maxRank","number"},
        {"modifier","number"},{"tempPoints","number"}}) do
        local value,status=member(info,spec[1]); field(out,spec[1],value,status,spec[2])
    end
    return out
end

function P.Capture(capturedAt)
    local out={available=false,status="unavailable",capturedAt=capturedAt,scanComplete=false,entries={}}
    local api=valid(C_SkillInfo,"table") and C_SkillInfo or {}
    local byID=member(api,"GetSkillLineInfoByID")
    local countFn=member(api,"GetNumSkillLines")
    local lineFn=member(api,"GetSkillLineInfo")
    local hasDirect=type(byID)=="function"
    local hasList=type(countFn)=="function" and type(lineFn)=="function"
    if not hasDirect and not hasList then out.status="unsupported"; return out end

    local entries,absent={},{}
    local readable,directComplete=false,hasDirect
    if hasDirect then
        for _,id in ipairs(professionIDs) do
            local info,status=read(byID,id)
            if status~="available" then directComplete=false
            elseif info==nil then absent[id]=true; readable=true
            else
                local value=entry(info,id)
                if value then entries[id]=value; readable=true else directComplete=false end
            end
        end
    end

    local listComplete,conflict=false,false
    if not directComplete and hasList then
        local count,status=read(countFn)
        if status=="available" and integer(count) and count<=MAX_SKILL_LINES then
            listComplete=true; readable=true
            local visible={}
            for index=1,count do
                local info,lineStatus=read(lineFn,index)
                if lineStatus~="available" or not valid(info,"table") then listComplete=false
                else
                    local header=member(info,"isHeader")
                    local id=member(info,"skillID")
                    if header==true then
                        if not integer(id) then listComplete=false
                        elseif id==9 or id==11 then
                            local collapsed=member(info,"isCollapsed")
                            if collapsed~=false then listComplete=false end
                        end
                    elseif header~=false or not integer(id) or id==0 then listComplete=false
                    elseif supported[id] then
                        local value=entry(info)
                        if not value then listComplete=false
                        else
                            if visible[id] then conflict=true end
                            visible[id]=true
                            if absent[id] then conflict=true end
                            -- Prefer readable direct observations; fallback never erases them.
                            if not entries[id] then entries[id]=value end
                        end
                    end
                end
            end
            if listComplete then
                for id in pairs(entries) do if not visible[id] then conflict=true end end
            end
        end
    end

    local partial=false
    for _,id in ipairs(professionIDs) do
        local value=entries[id]
        if value then out.entries[#out.entries+1]=value; if value.status~="available" then partial=true end end
    end
    out.available=readable
    out.scanComplete=(directComplete or listComplete) and not conflict
    out.status=not readable and "unavailable" or ((partial or not out.scanComplete) and "partial" or "available")
    return out
end
