-- One explicit item/spell loading budget for the entire snapshot. Getters may
-- still load data implicitly; this module only coordinates RequestLoad* calls.
ExporterDataRequests = {}
local R=ExporterDataRequests
local requests={item={},spell={}}
local queue,queued,active={},nil,false
local LIMIT,RETRY_SECONDS,MAX_ATTEMPTS=8,30,3

local function clock()
    if type(GetTime)~="function" then return nil end
    local ok,now=pcall(GetTime)
    if ok and type(now)=="number" and now==now and now~=math.huge and now~=-math.huge then return now end
end
local function valid(kind,id,fn)
    return requests[kind]~=nil and type(id)=="number" and id>0 and id<math.huge
        and id==math.floor(id) and type(fn)=="function"
end
local function status(record,now)
    if record and (record.failed or (record.attempts>=MAX_ATTEMPTS and now-record.at>=RETRY_SECONDS)) then
        return "unavailable"
    end
    return "pending"
end
local function eligible(record,now)
    return not record or (not record.failed and record.attempts<MAX_ATTEMPTS and now-record.at>=RETRY_SECONDS)
end
function R.Status(kind,id,fn)
    local now=clock()
    if not valid(kind,id,fn) or not now then return "unavailable" end
    return status(requests[kind][id],now)
end
function R.BeginCapture()
    -- Discard any abandoned pass; never carry a queued request for a category
    -- or item that is no longer present into another capture.
    queue,queued,active={},{item={},spell={}},true
end
function R.Request(kind,id,fn)
    local now=clock()
    if not valid(kind,id,fn) or not now then return "unavailable" end
    local record=requests[kind][id]
    if active and eligible(record,now) and not queued[kind][id] then
        local entry={kind=kind,id=id,fn=fn,order=#queue+1,
            attempts=record and record.attempts or 0,at=record and record.at or -math.huge}
        queue[#queue+1]=entry; queued[kind][id]=true
    end
    -- A deferred request has made no attempt and remains pending.
    return status(record,now)
end
function R.EndCapture()
    if not active then return 0 end
    local pending=queue
    queue,queued,active={},nil,false
    local now=clock()
    if not now then return 0 end
    -- Give unattempted IDs from later collectors a turn before retrying IDs
    -- from earlier collectors. Retries then prefer the oldest actual attempt.
    table.sort(pending,function(a,b)
        if a.attempts~=b.attempts then return a.attempts<b.attempts end
        if a.at~=b.at then return a.at<b.at end
        return a.order<b.order
    end)
    local sent=0
    for _,entry in ipairs(pending) do
        if sent>=LIMIT then break end
        local records=requests[entry.kind]
        local old=records[entry.id]
        if eligible(old,now) then
            local record={attempts=old and old.attempts+1 or 1,at=now}
            records[entry.id]=record; sent=sent+1
            if not pcall(entry.fn,entry.id) then record.failed=true end
        end
    end
    return sent
end
function R.OnEvent(event,id,success)
    if success~=false then return end
    local kind=event=="SPELL_DATA_LOAD_RESULT" and "spell"
        or ((event=="ITEM_DATA_LOAD_RESULT" or event=="GET_ITEM_INFO_RECEIVED") and "item")
    -- Ignore callbacks for IDs this broker never actually requested.
    local record=kind and requests[kind][id]
    if record then record.failed=true end
end
