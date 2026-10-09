max_line_length = false
exclude_files = { "probe/**" }

-- The addon runs in WoW's sandbox: no io, package/require, dofile/loadfile,
-- and os is limited to time/date/clock.
stds.wowlua = {
    read_globals = {
        "assert", "collectgarbage", "error", "getmetatable", "ipairs",
        "next", "pairs", "pcall", "print", "rawequal", "rawget", "rawset",
        "select", "setmetatable", "tonumber", "tostring", "type", "unpack",
        "xpcall",
        -- Explicit field lists: a bare library name would allow any field and
        -- hide typos such as math.flor or table.unpack (nil-calls in WoW).
        math = { fields = {
            "abs", "acos", "asin", "atan", "atan2", "ceil", "cos", "cosh", "deg",
            "exp", "floor", "fmod", "frexp", "huge", "ldexp", "log", "log10",
            "max", "min", "modf", "pi", "pow", "rad", "random", "randomseed",
            "sin", "sinh", "sqrt", "tan", "tanh",
        } },
        string = { fields = {
            "byte", "char", "find", "format", "gmatch", "gsub", "len", "lower",
            "match", "rep", "reverse", "sub", "upper",
        } },
        table = { fields = {
            "concat", "insert", "maxn", "remove", "sort", "getn", "foreach",
            "foreachi",
        } },
        os = { fields = { "time", "date", "clock" } },
    },
}

-- Tests run on LuaJIT and use io, os, loadfile, dofile and setfenv.
std = "lua51"
files["CraftProfit"] = { std = "wowlua" }

-- Globals the addon itself writes.
globals = {
    "CraftProfitDB",
    "CraftProfitCharDB",
    "SLASH_CRAFTPROFIT1",
    "SLASH_CRAFTPROFIT2",
}

-- WoW API the addon reads. SlashCmdList is read-only as a whole table; the
-- only key the addon may assign is its own slash handler.
read_globals = {
    "CreateFrame", "GetCursorPosition", "IsMouseButtonDown", "GetLocale", "GetTime", "time", "GetCoinTextureString",
    "issecretvalue", "C_Timer", "C_AuctionHouse", "C_TradeSkillUI", "C_Item",
    "Enum", "UIParent", "DEFAULT_CHAT_FRAME", "STANDARD_TEXT_FONT", "CreateColor", "C_Texture",
    "ProfessionsFrame", "TradeSkillFrame", "AuctionHouseFrame", "AuctionFrame",
    "AuctionHouseFrameDisplayMode",
    "GetProfessions", "GetProfessionInfo", "IsPlayerSpell",
    "GetNormalizedRealmName", "GetRealmName", "GetRealmID", "UnitFactionGroup", "C_GameRules",
    "GetTradeSkillSelectionIndex", "GetTradeSkillRecipeLink",
    "GetTradeSkillInfo", "GetTradeSkillItemLink", "GetTradeSkillNumReagents", "GetTradeSkillLine",
    "GetTradeSkillReagentInfo", "GetTradeSkillReagentItemLink",
    "GetTradeSkillNumMade",
    "ButtonFrameTemplate_HidePortrait", "ButtonFrameTemplate_HideButtonBar", "ButtonFrameTemplate_HideAttic",
    "PlaySound", "SOUNDKIT", "NORMAL_FONT_COLOR", "HIGHLIGHT_FONT_COLOR",
    SlashCmdList = {
        other_fields = true,
        fields = { CRAFTPROFIT = { read_only = false } },
    },
}
