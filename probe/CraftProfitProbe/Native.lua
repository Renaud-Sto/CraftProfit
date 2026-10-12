-- /cppn: THROWAWAY showcase of Blizzard's own templates and atlases (see docs/probe-findings.md).
-- Builds one window with several candidate frames and widgets and prints which names exist.
-- Every line starts with "[CPP" so the main probe mirrors it into the SavedVariables log.
local TAG = "|cff66ccff[CPP native]|r "
local function out(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    DEFAULT_CHAT_FRAME:AddMessage(TAG .. table.concat(parts, " "))
end

local ATLASES = {
    "questlog-reward-top-frame", "questlog-reward-header-top", "questlog-reward-bottom", "questlog-frame",
    "friends-frame-toptexbg", "friends-frame-bottomtexbg", "friends-frame-infobg",
    "common-framedivider", "perks-divider-short", "looting_itemcard_bg", "looting_itemcard_stroke_normal",
    "common-button-tertiary-square-normal", "common-search-magnifyingglass", "UI-Frame-TopTileStreaks",
    "_UI-Frame-TopTileStreaks", "UI-Character-Info-General-BG", "UI-Character-Info-Stat-BG",
    "Options_ListExpand_Right", "uiframe-tab-left", "common-dropdown-a-button", "RedButton-Exit",
    "auctionhouse-nav-button", "auctionhouse-rowstripe-1", "auctionhouse-background-index",
    "services-icon-processing", "bags-glow-white", "minimal-scrollbar-thumb-top",
}
local FILES = {
    "Interface\\FrameGeneral\\UI-Background-Rock", "Interface\\FrameGeneral\\UI-Background-Marble",
    "Interface\\QuestFrame\\UI-QuestTitleHighlight", "Interface\\Buttons\\UI-Quickslot2",
}
local TEMPLATES = {
    "ButtonFrameTemplate", "PortraitFrameTemplate", "DefaultPanelTemplate", "DefaultPanelFlatTemplate",
    "BasicFrameTemplateWithInset", "InsetFrameTemplate", "NineSlicePanelTemplate", "UIPanelButtonTemplate",
    "UICheckButtonTemplate", "InputBoxTemplate", "SearchBoxTemplate", "ScrollFrameTemplate",
    "MinimalScrollBar", "WowScrollBoxList", "PanelTabButtonTemplate", "MagicButtonTemplate",
    "UIPanelCloseButton", "TooltipBackdropTemplate", "QuestLogBorderFrameTemplate",
}

local win, atlasWin
local function build()
    local f = CreateFrame("Frame", "CPPNativeWindow", nil, "ButtonFrameTemplate")
    f:SetParent(UIParent)
    f:SetSize(820, 560)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "CPPNativeWindow")
    if ButtonFrameTemplate_HidePortrait then ButtonFrameTemplate_HidePortrait(f) end
    if ButtonFrameTemplate_HideButtonBar then ButtonFrameTemplate_HideButtonBar(f) end
    if f.SetTitle then f:SetTitle("CraftProfit native look test (A: this frame)") end
    local inset = f.Inset or f

    local function label(parent, text, x, y)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", inset, "TOPLEFT", x, y)
        fs:SetText(text)
        return fs
    end

    -- B: a plain frame with a nine-slice border
    label(inset, "B: NineSlice GenericMetal", 10, -8)
    -- NineSlicePanelTemplate reads its parent's layoutType in OnLoad: it needs a parent at creation.
    local b = CreateFrame("Frame", nil, inset, "NineSlicePanelTemplate")
    b:ClearAllPoints()
    b:SetSize(230, 90)
    b:SetPoint("TOPLEFT", inset, "TOPLEFT", 10, -28)
    if NineSliceUtil and NineSliceUtil.ApplyLayoutByName then
        out("ApplyLayoutByName GenericMetal:", pcall(NineSliceUtil.ApplyLayoutByName, b, "GenericMetal"))
    end

    -- C: a plain frame with the Inset template
    label(inset, "C: InsetFrameTemplate", 260, -8)
    local c = CreateFrame("Frame", nil, nil, "InsetFrameTemplate")
    c:SetParent(inset)
    c:SetSize(230, 90)
    c:SetPoint("TOPLEFT", inset, "TOPLEFT", 260, -28)

    -- D: header strips from atlases
    label(inset, "D: header strips (atlas)", 510, -8)
    local y = -28
    for _, name in ipairs({ "questlog-reward-top-frame", "friends-frame-toptexbg", "common-framedivider", "perks-divider-short" }) do
        local t = inset:CreateTexture(nil, "ARTWORK")
        local ok = pcall(t.SetAtlas, t, name, true)
        t:SetPoint("TOPLEFT", inset, "TOPLEFT", 510, y)
        if ok then
            local w, h = t:GetSize()
            if w > 280 then t:SetSize(280, h * 280 / w) end
            y = y - math.min(select(2, t:GetSize()), 60) - 6
        end
    end

    -- E: widgets
    label(inset, "E: widgets", 10, -140)
    local btn = CreateFrame("Button", nil, nil, "UIPanelButtonTemplate")
    btn:SetParent(inset)
    btn:SetSize(120, 22)
    btn:SetPoint("TOPLEFT", inset, "TOPLEFT", 10, -162)
    btn:SetText("Search prices")
    local btn2 = CreateFrame("Button", nil, nil, "UIPanelButtonTemplate")
    btn2:SetParent(inset)
    btn2:SetSize(120, 22)
    btn2:SetPoint("LEFT", btn, "RIGHT", 6, 0)
    btn2:SetText("Disabled")
    btn2:Disable()
    local chk = CreateFrame("CheckButton", nil, nil, "UICheckButtonTemplate")
    chk:SetParent(inset)
    chk:SetPoint("TOPLEFT", inset, "TOPLEFT", 10, -192)
    if chk.Text then chk.Text:SetText("Cost per skill point") end
    local box = CreateFrame("EditBox", nil, nil, "InputBoxTemplate")
    box:SetParent(inset)
    box:SetSize(60, 22)
    box:SetPoint("TOPLEFT", inset, "TOPLEFT", 160, -194)
    box:SetAutoFocus(false)
    box:SetText("1")

    -- F: scroll frame with the game's scroll bar
    label(inset, "F: ScrollFrameTemplate", 260, -140)
    local sf = CreateFrame("ScrollFrame", nil, nil, "ScrollFrameTemplate")
    sf:SetParent(inset)
    sf:SetSize(220, 90)
    sf:SetPoint("TOPLEFT", inset, "TOPLEFT", 260, -162)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(200, 400)
    sf:SetScrollChild(content)
    for i = 1, 20 do
        local fs = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("TOPLEFT", 0, -(i - 1) * 20)
        fs:SetText("Recipe row " .. i)
    end

    -- G: amounts with the game's money formatting and fonts
    label(inset, "G: money and fonts", 510, -140)
    local g = inset:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    g:SetPoint("TOPLEFT", inset, "TOPLEFT", 510, -162)
    local money = GetMoneyString and GetMoneyString(21 * 10000 + 29 * 100 + 5) or "(no GetMoneyString)"
    g:SetText(money)
    local g2 = inset:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    g2:SetPoint("TOPLEFT", inset, "TOPLEFT", 510, -184)
    g2:SetText("NumberFontNormal 1234567")
    local g3 = inset:CreateFontString(nil, "OVERLAY", "QuestTitleFont")
    g3:SetPoint("TOPLEFT", inset, "TOPLEFT", 510, -206)
    g3:SetText("QuestTitleFont Title")

    -- H: atlas gallery (only those that exist)
    label(inset, "H: atlas gallery (small ones)", 10, -250)
    local x, row = 10, -272
    for _, name in ipairs(ATLASES) do
        local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
        if info and info.width and info.width <= 64 and info.height <= 64 then
            local t = inset:CreateTexture(nil, "ARTWORK")
            t:SetAtlas(name, true)
            t:SetPoint("TOPLEFT", inset, "TOPLEFT", x, row)
            x = x + math.max(info.width, 24) + 8
            if x > 700 then x, row = 10, row - 70 end
        end
    end
    return f
end

-- Writes a detail line to the probe's log only (no chat), in the main probe's format.
local function logOnly(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    if type(CraftProfitProbeLog) ~= "table" then CraftProfitProbeLog = {} end
    CraftProfitProbeLog[#CraftProfitProbeLog + 1] = date("%H:%M:%S") .. " [CPP native] " .. table.concat(parts, " ")
end

-- /cppn line: can a plain frame draw Line objects on this client (chart primitives)?
-- A fan of 5 lines, a 7 point polyline, and 7 texture bars for comparison.
local lineWin
local function lineProbe()
    if lineWin then
        lineWin:SetShown(not lineWin:IsShown())
        return
    end
    local f = CreateFrame("Frame", "CPPLineProbe", nil)
    f:SetParent(UIParent)
    f:SetSize(440, 260)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    tinsert(UISpecialFrames, "CPPLineProbe")
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.08, 0.1, 0.95)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -8)
    title:SetText("CPP line probe: fan | polyline | texture bars (Escape closes)")
    lineWin = f

    local failures = {}
    local function step(name, fn, ...)
        local ok, res = pcall(fn, ...)
        logOnly("line", name, ok and "ok" or ("FAILS " .. tostring(res)))
        if not ok then failures[#failures + 1] = name .. ": " .. tostring(res) end
        return ok, res
    end

    logOnly("line", "CreateLine is", type(f.CreateLine))
    local ok, probe = step("CreateLine", f.CreateLine, f, nil, "ARTWORK")
    if ok and type(probe) == "table" then
        local okType, objType = pcall(probe.GetObjectType, probe)
        logOnly("line", "GetObjectType", okType and tostring(objType) or ("FAILS " .. tostring(objType)))
        step("SetThickness(1)", probe.SetThickness, probe, 1)
        step("SetThickness(2)", probe.SetThickness, probe, 2)
        step("SetColorTexture", probe.SetColorTexture, probe, 1, 1, 1, 1)
        step("SetStartPoint", probe.SetStartPoint, probe, "BOTTOMLEFT", f, 0, 0)
        step("SetEndPoint", probe.SetEndPoint, probe, "BOTTOMLEFT", f, 1, 1)
        probe:Hide()

        local function line(x0, y0, x1, y1, r, g, b, thickness, name)
            local l = f:CreateLine(nil, "ARTWORK")
            step(name .. " color", l.SetColorTexture, l, r, g, b, 1)
            step(name .. " start", l.SetStartPoint, l, "BOTTOMLEFT", f, x0, y0)
            step(name .. " end", l.SetEndPoint, l, "BOTTOMLEFT", f, x1, y1)
            step(name .. " thickness", l.SetThickness, l, thickness)
        end
        -- Fan: 5 lines from one point, thickness 1 and 2 alternating.
        local colors = { { 1, 0.2, 0.2 }, { 1, 0.8, 0.2 }, { 0.3, 1, 0.3 }, { 0.3, 0.7, 1 }, { 0.8, 0.4, 1 } }
        for i, c in ipairs(colors) do
            local angle = math.rad(15 + (i - 1) * 37.5)
            line(80, 30, 80 + 90 * math.cos(angle), 30 + 90 * math.sin(angle), c[1], c[2], c[3], i % 2 == 0 and 2 or 1, "fan" .. i)
        end
        -- Polyline through 7 daily averages (the chart's optional connecting line).
        local ys = { 60, 90, 75, 140, 120, 170, 110 }
        for i = 1, #ys - 1 do
            line(180 + (i - 1) * 22, ys[i], 180 + i * 22, ys[i + 1], 1, 0.82, 0, 2, "poly" .. i)
        end
    else
        failures[#failures + 1] = "CreateLine: " .. tostring(probe)
    end
    -- Texture bars, the fallback the chart uses anyway.
    local heights = { 40, 70, 55, 120, 100, 150, 90 }
    for i, h in ipairs(heights) do
        local t = f:CreateTexture(nil, "ARTWORK")
        t:SetColorTexture(0.3, 0.6, 1, i % 2 == 0 and 0.5 or 1)
        t:SetSize(14, h)
        t:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 340 + (i - 1) * 13, 30)
    end
    if #failures == 0 then
        out("lines: ok (details in the log; /reload writes it)")
    else
        out("lines: FAILS " .. failures[1] .. " (" .. #failures .. " failures, see the log)")
    end
end

-- Days since 1970-01-01 of a calendar date (proleptic Gregorian), no time() needed.
local function daysFromCivil(y, m, d)
    if m <= 2 then y = y - 1 end
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local mp = (m + 9) % 12
    local doy = math.floor((153 * mp + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

-- /cppn time: date("*t"), time(table) and the clocks, for the history's local days.
local function timeProbe()
    local year = tonumber(date("%Y")) or 2026
    local okAll, count = true, 0
    logOnly("time", "time()", tostring(time()), "GetServerTime()", tostring(GetServerTime and GetServerTime()),
        "GetTime()", tostring(GetTime()))
    for _, y in ipairs({ year, year - 1 }) do
        for _, md in ipairs({ { 6, 15 }, { 10, 28 }, { 3, 28 } }) do
            count = count + 1
            -- Noon UTC of that date: the same calendar date in any zone from UTC-11 to UTC+11.
            local ts = daysFromCivil(y, md[1], md[2]) * 86400 + 12 * 3600
            local d = date("*t", ts)
            local u = date("!*t", ts)
            logOnly("time", string.format("ts %d (%04d-%02d-%02d 12:00 UTC) local %04d-%02d-%02d %02d:%02d:%02d wday %s yday %s isdst %s",
                ts, y, md[1], md[2], d.year, d.month, d.day, d.hour, d.min, d.sec, tostring(d.wday), tostring(d.yday), tostring(d.isdst)))
            -- UTC offset from the fields only: minutes apart, corrected by the day difference.
            local dayDiff = (d.year * 1000 + d.yday) - (u.year * 1000 + u.yday)
            if dayDiff > 1 then dayDiff = -1 elseif dayDiff < -1 then dayDiff = 1 end
            local offset = ((d.hour * 60 + d.min) - (u.hour * 60 + u.min) + dayDiff * 1440) * 60
            local okRt, rt = pcall(time, d)
            logOnly("time", "offset from date fields", offset, "s; time(date(\"*t\", ts)) - ts =",
                (okRt and type(rt) == "number") and (rt - ts) or ("FAILS " .. tostring(rt)))
            local okTime, midnight = pcall(time, { year = d.year, month = d.month, day = d.day, hour = 0 })
            local good = okTime and type(midnight) == "number"
            local back = good and date("*t", midnight) or nil
            good = good and ts - midnight >= 0 and ts - midnight < 25 * 3600
                and back.year == d.year and back.month == d.month and back.day == d.day and back.hour == 0
            logOnly("time", "time{y,m,d,hour=0}", okTime and tostring(midnight) or ("FAILS " .. tostring(midnight)),
                "type", type(midnight), "noon - midnight", good and (ts - midnight) or "-",
                "round trip", back and string.format("%04d-%02d-%02d %02d:%02d", back.year, back.month, back.day, back.hour, back.min) or "-",
                good and "OK" or "BAD")
            if not good then okAll = false end
        end
    end
    out(okAll and ("time(table): ok (" .. count .. " dates, details in the log)") or "time(table): FAILS (see the log)")
end

SLASH_CPPN1 = "/cppn"
SlashCmdList.CPPN = function(msg)
    if msg == "line" then
        local ok, err = pcall(lineProbe)
        if not ok then out("lines: FAILS " .. tostring(err)) end
        return
    end
    if msg == "time" then
        local ok, err = pcall(timeProbe)
        if not ok then out("time(table): FAILS " .. tostring(err)) end
        return
    end
    if msg == "list" then
        for _, name in ipairs(ATLASES) do
            local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
            out("atlas", name, info and (info.width .. "x" .. info.height) or "MISSING")
        end
        for _, path in ipairs(FILES) do
            out("file", path, GetFileIDFromPath and tostring(GetFileIDFromPath(path)) or "(no GetFileIDFromPath)")
        end
        for _, name in ipairs(TEMPLATES) do
            local ok, err = pcall(CreateFrame, "Frame", nil, nil, name)
            out("template", name, ok and "ok" or ("FAILS: " .. tostring(err)))
        end
        out("clients:", tostring(WOW_PROJECT_ID), tostring(WOW_PROJECT_CAMELOT), select(4, GetBuildInfo()))
        return
    end
    if msg == "btn" then
        -- Where the art of a UIPanelButtonTemplate button sits inside its frame, and where
        -- CraftProfit's header sort button and header sit on screen (numbers, no drawing).
        local b = CreateFrame("Button", nil, nil, "UIPanelButtonTemplate")
        b:SetParent(UIParent)
        b:SetSize(120, 18)
        b:SetPoint("CENTER", UIParent, "CENTER", 0, -300)
        out("button frame size", b:GetWidth(), b:GetHeight())
        local keys = { "Left", "Right", "Middle", "Center", "LeftDisabled", "RightDisabled", "MiddleDisabled" }
        for _, key in ipairs(keys) do
            local r = b[key]
            if type(r) == "table" and r.GetPoint then
                local line = key .. " size " .. tostring(r:GetWidth()) .. "x" .. tostring(r:GetHeight())
                for i = 1, r:GetNumPoints() do
                    local point, rel, relPoint, x, y = r:GetPoint(i)
                    line = line .. " | " .. tostring(point) .. " -> " .. tostring(relPoint) .. " " .. tostring(x) .. "," .. tostring(y)
                end
                out(line)
            end
        end
        for _, key in ipairs({ "Text" }) do
            local r = b[key]
            if type(r) == "table" and r.GetPoint then
                out("Text size", r:GetWidth(), r:GetHeight(), "font height", select(2, r:GetFont()))
            end
        end
        b:Hide()
        local f = EnumerateFrames()
        local found
        while f do
            if f.GetObjectType and f:GetObjectType() == "Button" and f.GetText then
                local ok, text = pcall(f.GetText, f)
                if ok and type(text) == "string" and (text:find("Tri :", 1, true) or text:find("Sort", 1, true) or text:find("Order", 1, true)) and f:GetHeight() == 18 then
                    found = f
                    break
                end
            end
            f = EnumerateFrames(f)
        end
        local line = "no 18 px sort button found (open the pinned list at the AH first)"
        if found then
            local panel = found:GetParent()
            line = string.format("sort top %.1f bottom %.1f height %.1f | panel top %.1f bottom %.1f", found:GetTop(), found:GetBottom(), found:GetHeight(), panel:GetTop(), panel:GetBottom())
            out(line)
            for _, child in ipairs({ panel:GetChildren() }) do
                if child ~= found and child:GetHeight() and child:GetHeight() > 20 and child:GetHeight() < 30 then
                    out(string.format("child %s top %.1f bottom %.1f height %.1f shown %s", tostring(child:GetObjectType()), child:GetTop() or -1, child:GetBottom() or -1, child:GetHeight(), tostring(child:IsShown())))
                end
            end
            return
        end
        out(line)
        return
    end
    if msg == "atlas" then
        -- The three header strips at their native size on a plain background, with a 22 px
        -- ruler on the left (the height of a panel header) and the atlas size printed.
        if not atlasWin then
            local f = CreateFrame("Frame", "CPPAtlasWindow", nil, "BackdropTemplate")
            f:SetParent(UIParent)
            f:SetSize(460, 330)
            f:SetPoint("CENTER")
            f:SetFrameStrata("HIGH")
            f:SetMovable(true)
            f:EnableMouse(true)
            f:RegisterForDrag("LeftButton")
            f:SetScript("OnDragStart", f.StartMoving)
            f:SetScript("OnDragStop", f.StopMovingOrSizing)
            tinsert(UISpecialFrames, "CPPAtlasWindow")
            local bg = f:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.1, 0.1, 0.1, 1)
            local y = -10
            for _, name in ipairs({ "friends-frame-toptexbg", "questlog-reward-header-top", "_UI-Frame-TopTileStreaks", "friends-frame-infobg" }) do
                local info = C_Texture.GetAtlasInfo(name)
                local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                label:SetPoint("TOPLEFT", f, "TOPLEFT", 40, y)
                label:SetText(name .. " " .. (info and (info.width .. "x" .. info.height) or "MISSING"))
                y = y - 14
                local t = f:CreateTexture(nil, "ARTWORK")
                pcall(t.SetAtlas, t, name, true)
                t:SetPoint("TOPLEFT", f, "TOPLEFT", 40, y)
                local ruler = f:CreateTexture(nil, "OVERLAY")
                ruler:SetColorTexture(0, 1, 0, 1)
                ruler:SetSize(4, 22)
                ruler:SetPoint("TOPRIGHT", t, "TOPLEFT", -4, 0)
                y = y - ((info and info.height or 20) + 12)
            end
            atlasWin = f
        end
        atlasWin:SetShown(not atlasWin:IsShown())
        return
    end
    if msg == "money" then
        -- What the game's own money helpers return on this build (21g 29s 5c), and how it renders.
        local copper = 21 * 10000 + 29 * 100 + 5
        for _, name in ipairs({ "GetCoinTextureString", "GetMoneyString", "GetCoinText" }) do
            local fn = _G[name]
            if type(fn) == "function" then
                local ok, res = pcall(fn, copper)
                out(name, ok and ("[" .. tostring(res):gsub("|", "||") .. "]") or ("ERROR " .. tostring(res)))
                if ok and type(res) == "string" then DEFAULT_CHAT_FRAME:AddMessage(TAG .. name .. " renders: " .. res) end
            else
                out(name, "MISSING")
            end
        end
        for _, size in ipairs({ 0, 12, 16 }) do
            local ok, res = pcall(GetCoinTextureString, copper, size)
            if ok and type(res) == "string" then DEFAULT_CHAT_FRAME:AddMessage(TAG .. "size " .. size .. ": " .. res) end
        end
        local fs = UIParent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
        local ok, res = pcall(GetCoinTextureString, copper)
        fs:SetText(ok and res or "?")
        out("font string width of the coin string:", fs:GetStringWidth(), "(hides in 8 s)")
        C_Timer.After(8, function() fs:Hide() end)
        return
    end
    if not win then
        local ok, res = pcall(build)
        if not ok then out("build failed:", res) return end
        win = res
    end
    win:SetShown(not win:IsShown())
    out("window", win:IsShown() and "shown" or "hidden", "- /cppn list prints which names exist; /reload writes the log")
end
out("loaded. /cppn = native look showcase, /cppn list = which atlases/templates exist, /cppn line and /cppn time = chart primitives")
