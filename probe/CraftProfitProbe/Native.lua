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

SLASH_CPPN1 = "/cppn"
SlashCmdList.CPPN = function(msg)
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
out("loaded. /cppn = native look showcase, /cppn list = which atlases/templates exist")
