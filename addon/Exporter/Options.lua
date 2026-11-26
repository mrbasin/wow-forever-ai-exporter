local E=Exporter
local panel,host,category,checks,enabled,periodic,minutes,status,exportSize,path
local refreshing=false
local function label(parent,text,x,y,width)
    local f=parent:CreateFontString(nil,"ARTWORK","GameFontNormal")
    f:SetPoint("TOPLEFT",x,y); f:SetWidth(width or 480); f:SetJustifyH("LEFT"); f:SetText(text); return f
end
local function checkbox(parent,text,x,y,changed)
    local box=CreateFrame("CheckButton",nil,parent,"UICheckButtonTemplate")
    box:SetPoint("TOPLEFT",x,y); box:SetSize(26,26)
    local caption=box:CreateFontString(nil,"ARTWORK","GameFontHighlight")
    caption:SetPoint("LEFT",box,"RIGHT",3,0); caption:SetText(text)
    box:SetScript("OnClick",function(self) if not refreshing then changed(self:GetChecked()==true) end end)
    return box
end
local function powerShellLiteral(path)
    -- PowerShell also treats U+2018 through U+201B as single-quote delimiters.
    return "'" .. path:gsub("'", "''"):gsub("\226\128[\152-\155]", "'%0") .. "'"
end
local function aiPrompt()
    local source = E.OutputPath()
    local guid = UnitGUID("player")
    local wowRoot = type(ExporterLocalPaths) == "table" and ExporterLocalPaths.wowRoot
    if not wowRoot and not source:find("<", 1, true) then
        local accountStart = source:lower():find("\\wtf\\account\\", 1, true)
        if accountStart then wowRoot = source:sub(1, accountStart - 1) end
    end
    local decoder = (wowRoot or ".") .. "\\Interface\\AddOns\\Exporter\\Decode-Export.ps1"
    local cacheArgument = "'FULL CACHE PATH'"
    local directions
    if source:find("\n", 1, true) or source:find("<", 1, true) then
        local accountRoot = (wowRoot or ".") .. "\\WTF\\Account"
        directions = "Look for cooldownmanager.txt files under " .. accountRoot .. ". Run the command for each candidate, replacing 'FULL CACHE PATH' with its single-quoted path and doubling any apostrophe in the path."
    else
        cacheArgument = powerShellLiteral(source)
        directions = "Start with the cache path in this command."
    end
    local command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File " .. powerShellLiteral(decoder) .. " -Path " .. cacheArgument
    return table.concat({
        "Read my " .. E.displayName .. " snapshot.",
        wowRoot and "Use PowerShell on my Windows PC." or "Open PowerShell in my WoW _forever_ folder (the one containing Interface and WTF). Ask me for its location if needed.",
        directions,
        "Run this command to print the decoded JSON: `" .. command .. "`.",
        guid and ("Use the newest capturedAt whose character.guid equals " .. guid .. ".") or "Confirm the character with me before using the snapshot.",
        "Report the capture time with its time zone and flag stale or missing data.",
        'If you cannot run the decoder on my PC, help me run the same PowerShell command with `-Output "$env:TEMP\\wow-character.json"` appended and ask me to attach wow-character.json from my %TEMP% folder.',
        "If the snapshot is missing or stale, ask me to click Export now, stay logged in, and allow time for WoW to write it."
    }, " ")
end

function E.RefreshOptions()
    if not panel or not E.ready then return end
    refreshing=true
    enabled:SetChecked(ExporterSettings.enabled); periodic:SetChecked(ExporterSettings.periodic)
    if not minutes:HasFocus() then minutes:SetText(tostring(ExporterSettings.intervalMinutes)) end
    for key,box in pairs(checks) do box:SetChecked(ExporterSettings.sections[key]) end
    local last=E.lastSnapshot and E.lastSnapshot.capturedAt
    local lastText=last and (date and date("%Y-%m-%d %H:%M:%S",last) or tostring(last)) or "No snapshot this session"
    status:SetText("Last capture: "..lastText.."\n"..(E.status or "Ready"))
    local size=E.lastExportSize
    if size then
        exportSize:SetText(string.format("Encoded export: %.1f KiB (%d bytes)\nUncompressed JSON: %.1f KiB (%d bytes)",
            size.encodedBytes/1024,size.encodedBytes,size.jsonBytes/1024,size.jsonBytes))
    else exportSize:SetText("Export size: available after the first export this session") end
    path:SetText(E.OutputPath())
    refreshing=false
end
function E.CreateOptions()
    if panel then return end
    host=CreateFrame("Frame"); host.name=E.displayName
    local scroll=CreateFrame("ScrollFrame",nil,host,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",0,-5); scroll:SetPoint("BOTTOMRIGHT",-28,5)
    panel=CreateFrame("Frame",nil,scroll); panel:SetSize(560,1); scroll:SetScrollChild(panel)
    label(panel,E.displayName.." v"..E.version,18,-18):SetFontObject("GameFontNormalLarge")
    label(panel,"Character metadata export. Reading the file is handled separately.",18,-48)
    enabled=checkbox(panel,"Enable exporting",18,-76,function(v) ExporterSettings.enabled=v; E.ApplySettings() end)
    periodic=checkbox(panel,"Periodic exports",18,-108,function(v) ExporterSettings.periodic=v; E.ApplySettings() end)
    label(panel,"Every",260,-116,50)
    minutes=CreateFrame("EditBox",nil,panel,"InputBoxTemplate"); minutes:SetSize(55,24)
    minutes:SetPoint("TOPLEFT",310,-108); minutes:SetAutoFocus(false); minutes:SetNumeric(true); minutes:SetMaxLetters(4)
    label(panel,"minutes (1-"..E.maxIntervalMinutes..")",375,-116,150)
    local function applyMinutes(self)
        local n=tonumber(self:GetText())
        if not n or n<1 or n>E.maxIntervalMinutes or n~=math.floor(n) then self:SetText(tostring(ExporterSettings.intervalMinutes)); return end
        if n~=ExporterSettings.intervalMinutes then ExporterSettings.intervalMinutes=n; E.ApplySettings() end
    end
    minutes:SetScript("OnEnterPressed",function(self) applyMinutes(self); self:ClearFocus() end)
    minutes:SetScript("OnEditFocusLost",applyMinutes)
    minutes:SetScript("OnEscapePressed",function(self) self:ClearFocus(); E.RefreshOptions() end)
    label(panel,"Uncheck Periodic for ad-hoc exports. Combat delays exports; no automatic UI reloads.",18,-146,530)
    label(panel,"Include in exports",18,-182)
    checks={}
    local y=-207
    for _,item in ipairs(E.categories) do
        local key=item[1]
        checks[key]=checkbox(panel,item[2],18,y,function(v)
            ExporterSettings.sections[key]=v; E.ApplySettings()
        end)
        y=y-32
    end
    label(panel,"Character ID and capture timestamps are always included.",18,y-12,530)
    local now=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate")
    now:SetSize(140,27); now:SetPoint("TOPLEFT",18,y-42); now:SetText("Export now")
    now:SetScript("OnClick",function() applyMinutes(minutes); E.RequestExport(); E.Tick(); E.RefreshOptions() end)
    local prompt = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    prompt:SetSize(510,24); prompt:SetPoint("TOPLEFT",25,y-99)
    prompt:SetAutoFocus(false); prompt:SetFontObject("GameFontHighlightSmall")
    local promptText = aiPrompt()
    prompt:SetText(promptText)
    prompt:SetScript("OnTextChanged",function(self,userInput)
        if userInput then self:SetText(promptText); self:HighlightText() end
    end)
    prompt:SetScript("OnEditFocusGained",function(self)
        promptText = aiPrompt()
        self:SetText(promptText); self:HighlightText()
    end)
    prompt:SetScript("OnMouseUp",function(self) self:HighlightText() end)
    prompt:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    local selectPrompt = CreateFrame("Button",nil,panel,"UIPanelButtonTemplate")
    selectPrompt:SetSize(150,27); selectPrompt:SetPoint("LEFT",now,"RIGHT",10,0)
    selectPrompt:SetText("Select AI prompt")
    selectPrompt:SetScript("OnClick",function()
        prompt:SetFocus(); prompt:HighlightText()
    end)
    label(panel,"Press Ctrl+C to copy the selected prompt, then paste it into ChatGPT or Claude.",18,y-78,530)
    status=label(panel,"",18,y-139,530); status:SetFontObject("GameFontHighlightSmall")
    exportSize=label(panel,"",18,y-139,530); exportSize:SetFontObject("GameFontHighlightSmall")
    exportSize:SetPoint("TOPLEFT",status,"BOTTOMLEFT",0,-14)
    local sourceLabel=label(panel,"Character export source (select and copy)",18,y-189,530)
    sourceLabel:SetPoint("TOPLEFT",exportSize,"BOTTOMLEFT",0,-20)
    path=CreateFrame("EditBox",nil,panel,"InputBoxTemplate"); path:SetPoint("TOPLEFT",sourceLabel,"BOTTOMLEFT",7,-12)
    path:SetSize(510,64); path:SetMultiLine(true); path:SetAutoFocus(false); path:SetFontObject("GameFontHighlightSmall")
    path:SetScript("OnTextChanged",function(self,userInput) if userInput then self:SetText(E.OutputPath()) end end)
    path:SetScript("OnEditFocusGained",function(self) self:HighlightText() end)
    path:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    local note=label(panel,"WoW owns this filename. It contains an encoded snapshot; disk delivery may lag.\nSize is measured before disk delivery and includes the cache envelope.",18,y-297,530)
    note:SetPoint("TOPLEFT",path,"BOTTOMLEFT",-7,-18); note:SetFontObject("GameFontHighlightSmall")
    panel:SetSize(560,414-y)
    host:SetScript("OnShow",E.RefreshOptions)
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        category=Settings.RegisterCanvasLayoutCategory(host,E.displayName); Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then InterfaceOptions_AddCategory(host)
    else
        host:SetSize(600,665); host:SetPoint("CENTER"); host:SetFrameStrata("DIALOG")
        local backdrop=host:CreateTexture(nil,"BACKGROUND"); backdrop:SetAllPoints(); backdrop:SetColorTexture(0.06,0.06,0.06,0.97)
        local close=CreateFrame("Button",nil,host,"UIPanelCloseButton"); close:SetPoint("TOPRIGHT"); close:SetScript("OnClick",function() host:Hide() end)
    end
    host:Hide(); E.RefreshOptions()
    E.optionsPanel=host; E.optionsContent=panel
end
function E.OpenOptions()
    E.CreateOptions()
    if category and Settings.OpenToCategory then Settings.OpenToCategory(category:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then InterfaceOptionsFrame_OpenToCategory(host)
    else host:Show() end
end
