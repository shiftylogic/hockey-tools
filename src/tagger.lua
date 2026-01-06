--[[

    MIT License

    Copyright (c) 2025-present Robert Anderson

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.

    ---

    MPV Hockey Video Tagger
    Watches hockey game videos and logs structured tag data based on user input.

    Usage:
      - Press configured leader_key to enter tag mode (video pauses)
      - Select tag type from auto-complete list
      - Enter required data for each field with validation
      - Press Enter to submit tag when complete
      - Press ESC to cancel and resume playback

    Environment:
      - TAGGER_CONF: Path to config file (required, falls back to ~/.tagger.json)

    Output: {video}_tags_{timestamp}.log next to source video
]]


local msg = require 'mp.msg'
local utils = require 'mp.utils'
local options = require 'mp.options'
local input = require 'mp.input'


-- ============================================================================
-- SECTION 1: CONFIGURATION
-- ============================================================================

local config = {
    leader_key = "ctrl+t",
    player_map = {},
}

local function load_config(path)
    local file = io.open(path, "r")
    if not file then return nil end

    local content = file:read("*a")
    file:close()

    local parsed, err = utils.parse_json(content)
    if not parsed then
        msg.warn("Failed to parse config: " .. tostring(err))
        return nil
    end

    local result = {
        leader_key = parsed.leader_key or "ctrl+t",
        player_map = {},
    }

    if parsed.player_map then
        for num, name in pairs(parsed.player_map) do
            result.player_map[tonumber(num)] = name
        end
    end

    return result
end

local function get_default_config_path()
    local home = os.getenv("HOME") or os.getenv("USERPROFILE")
    if home then
        return home .. "/.tagger.json"
    end
    return nil
end

local function load_effective_config()
    local env_path = os.getenv("TAGGER_CONF")
    local default_path = get_default_config_path()

    local env_config = env_path and load_config(env_path)
    if env_config then
        msg.info("Loaded config from " .. env_path)
        return env_config
    end

    local default_config = default_path and load_config(default_path)
    if default_config then
        msg.info("Loaded default config from " .. default_path)
        return default_config
    end

    msg.warn("No config file found, using defaults")
    return nil
end

local user_config = load_effective_config()
if user_config then
    config.leader_key = user_config.leader_key or config.leader_key
    config.player_map = user_config.player_map or config.player_map
end


-- ============================================================================
-- SECTION 2: CONSTANTS & DATA DEFINITIONS
-- ============================================================================

local zone_numbers = {"1", "2", "3", "4", "5", "6", "7", "8"}
local zone_text = {"defensive", "offensive", "neutral"}

local penalty_category_length = {
    minor = "2",
    major = "5",
    match = "5",
    misconduct = "10",
    game_misconduct = "10"
}

local tag_definitions = {
    goal = {
        prompt = "Goal",
        order = {"scorer", "assists"},
        fields = {
            scorer = { prompt = "Scorer:", type = "player", required = true },
            assists = { prompt = "Assists (Enter to finish):", type = "player", multi = true,
                        min_count = 0, max_count = 2 }
        },
        validator = "goal_count"
    },
    penalty = {
        prompt = "Penalty",
        order = {"player", "category", "type"},
        fields = {
            player = { prompt = "Player:", type = "player", required = true },
            category = { prompt = "Category (minor/major/match/misconduct/game_misconduct):", type = "enum",
                        values = {"minor", "major", "match", "misconduct", "game_misconduct"}, required = true },
            type = { prompt = "Type:", type = "autocomplete", source = "penalty_types", required = true }
        }
    },
    shot = {
        prompt = "Shot",
        order = {"player", "outcome", "zone"},
        fields = {
            player = { prompt = "Shooter:", type = "player", required = true },
            outcome = { prompt = "Outcome (missed/saved/blocked):", type = "enum",
                        values = {"missed", "saved", "blocked"}, required = true },
            zone = { prompt = "Zone (1-8):", type = "enum", values = zone_numbers, required = true }
        }
    },
    block = {
        prompt = "Block",
        order = {"player", "zone"},
        fields = {
            player = { prompt = "Blocker:", type = "player", required = true },
            zone = { prompt = "Zone (1-8):", type = "enum", values = zone_numbers, required = true }
        }
    },
    change = {
        prompt = "Change",
        order = {"out", "incoming"},
        fields = {
            out = { prompt = "Outgoing:", type = "player", required = true },
            incoming = { prompt = "Incoming:", type = "player", required = true }
        }
    },
    pass = {
        prompt = "Pass",
        order = {"from", "to", "success", "zone"},
        fields = {
            from = { prompt = "From:", type = "player", required = true },
            to = { prompt = "To:", type = "player", required = true },
            success = { prompt = "Outcome (success/off-target/missed):", type = "enum",
                        values = {"success", "off-target", "missed"}, required = true },
            zone = { prompt = "Zone (defensive/offensive/neutral):", type = "enum",
                     values = zone_text, required = true }
        }
    },
    takeaway = {
        prompt = "Takeaway",
        order = {"player", "zone"},
        fields = {
            player = { prompt = "Player:", type = "player", required = true },
            zone = { prompt = "Zone (defensive/offensive/neutral):", type = "enum",
                     values = zone_text, required = true }
        }
    },
    giveaway = {
        prompt = "Giveaway",
        order = {"player", "zone"},
        fields = {
            player = { prompt = "Player:", type = "player", required = true },
            zone = { prompt = "Zone (defensive/offensive/neutral):", type = "enum",
                     values = zone_text, required = true }
        }
    },
    save = {
        prompt = "Save",
        order = {},
        fields = {}
    },
    start = {
        prompt = "Start",
        order = {"period", "length", "goalie", "defense", "forwards"},
        fields = {
            period = { prompt = "Period (1, 2, 3, OT):", type = "enum",
                       values = {"1", "2", "3", "OT"}, required = true },
            length = { prompt = "Length (mm:ss):", type = "pattern", pattern = "^%d+:%d%d$",
                       error = "Use: mm:ss", required = true },
            goalie = { prompt = "Goaltender:", type = "player", required = true },
            defense = { prompt = "Defensemen (Enter to finish):", type = "player", multi = true,
                        min_count = 1, max_count = 2 },
            forwards = { prompt = "Forwards (Enter to finish):", type = "player", multi = true,
                         min_count = 1, max_count = 3 }
        },
        validator = "start_lineup"
    },
    whistle = {
        prompt = "Whistle",
        order = {"reason"},
        fields = {
            reason = { prompt = "Reason (optional):", type = "text", required = false }
        }
    },
    faceoff = {
        prompt = "Faceoff",
        order = {"player", "win"},
        fields = {
            player = { prompt = "Player:", type = "player", required = true },
            win = { prompt = "Win (y/n):", type = "yn", required = true }
        }
    },
    against = {
        prompt = "Against",
        order = {"zone", "note"},
        fields = {
            zone = { prompt = "Zone (1-8):", type = "enum", values = zone_numbers, required = true },
            note = { prompt = "Note (optional):", type = "text", required = false }
        }
    },
}

local tag_types_list = {}
for k, _ in pairs(tag_definitions) do
    table.insert(tag_types_list, k)
end
table.sort(tag_types_list)

local penalty_types_list = {
    "hooking", "holding", "tripping", "interference", "slashing",
    "high-sticking", "cross-checking", "fighting", "delay of game",
    "too many men", "roughing", "boarding", "charging", "elbowing",
    "kneeing", "butt-ending", "spearing", "throwing equipment"
}

local zone_numbers = {"1", "2", "3", "4", "5", "6", "7", "8"}
local zone_text = {"defensive", "offensive", "neutral"}

local penalty_category_length = {
    minor = "2",
    major = "5",
    match = "5",
    misconduct = "10",
    game_misconduct = "10"
}


-- ============================================================================
-- SECTION 3: STATE MANAGEMENT
-- ============================================================================

local TaggerState = {
    mode = "idle",        -- idle, selecting_type, entering_fields
    tag_type = nil,
    tag_def = nil,
    data = {},
    current_field = nil,
    field_order = {},
    field_finished = {}   -- tracks which fields user has finished (both multi and optional single)
}

local RosterState = {
    goalie = nil,         -- current goalie jersey number
    defense = {},         -- set of defense jersey numbers on ice
    forwards = {},        -- set of forward jersey numbers on ice
    all_on_ice = {}       -- combined set of all skaters on ice (for quick lookup)
}

local function reset_state()
    TaggerState = {
        mode = "idle",
        tag_type = nil,
        tag_def = nil,
        data = {},
        current_field = nil,
        field_order = {},
        field_finished = {}
    }
end


-- ============================================================================
-- SECTION 4: UTILITY FUNCTIONS
-- ============================================================================

local function player_name(num)
    local name = config.player_map[tonumber(num)]
    if name then
        return "#" .. num .. " " .. name
    end
    return "Player " .. num
end

local function is_valid_player(num)
    num = tonumber(num)
    return num ~= nil and config.player_map[num] ~= nil
end

local function roster_add_player(num)
    num = tonumber(num)
    if not num then return end
    RosterState.all_on_ice[num] = true
end

local function roster_remove_player(num)
    num = tonumber(num)
    if not num then return end
    RosterState.all_on_ice[num] = nil
end

local function roster_is_on_ice(num)
    num = tonumber(num)
    if not num then return false end
    return RosterState.all_on_ice[num] == true
end

local function roster_get_other_players(exclude_list)
    local others = {}
    for num, _ in pairs(RosterState.all_on_ice) do
        local excluded = false
        if exclude_list then
            for _, ex in ipairs(exclude_list) do
                if tonumber(ex) == num then
                    excluded = true
                    break
                end
            end
        end
        if not excluded then
            table.insert(others, tostring(num))
        end
    end
    return others
end

local function roster_format_osd()
    local parts = {}

    if RosterState.goalie then
        table.insert(parts, "G: #" .. RosterState.goalie .. " " .. player_name(RosterState.goalie))
    else
        table.insert(parts, "G: --")
    end

    local defense_list = {}
    for num, _ in pairs(RosterState.defense) do
        table.insert(defense_list, "#" .. num)
    end
    if #defense_list > 0 then
        table.insert(parts, "D: " .. table.concat(defense_list, ", "))
    else
        table.insert(parts, "D: --")
    end

    local forwards_list = {}
    for num, _ in pairs(RosterState.forwards) do
        table.insert(forwards_list, "#" .. num)
    end
    if #forwards_list > 0 then
        table.insert(parts, "F: " .. table.concat(forwards_list, ", "))
    else
        table.insert(parts, "F: --")
    end

    return table.concat(parts, " | ")
end

local function roster_show_osd()
    local msg = roster_format_osd()
    mp.osd_message(msg, 10)
end

local function roster_clear()
    RosterState.goalie = nil
    RosterState.defense = {}
    RosterState.forwards = {}
    RosterState.all_on_ice = {}
end

local function roster_set_lineup(goalie, defense_list, forwards_list)
    roster_clear()
    RosterState.goalie = tonumber(goalie)
    for _, num in ipairs(defense_list or {}) do
        num = tonumber(num)
        if num then
            RosterState.defense[num] = true
            roster_add_player(num)
        end
    end
    for _, num in ipairs(forwards_list or {}) do
        num = tonumber(num)
        if num then
            RosterState.forwards[num] = true
            roster_add_player(num)
        end
    end
end

local function roster_change(out_num, in_num)
    roster_remove_player(out_num)
    roster_add_player(in_num)
end

local function complete_factory(source_type, source)
    if source_type == "list" then
        return function(text)
            local input_lower = text:lower()
            local matches = {}
            for _, item in ipairs(source) do
                if item:lower():find(input_lower, 1, true) == 1 then
                    table.insert(matches, item)
                end
            end
            if #matches == 0 then return nil end
            return matches, 1, ""
        end
    elseif source_type == "players" then
        return function(text)
            local matches = {}
            for n, _ in pairs(config.player_map) do
                local s = tostring(n)
                if s:find(text, 1, true) == 1 then
                    table.insert(matches, s)
                end
            end
            if #matches == 0 then return nil end
            return matches, 1, ""
        end
    elseif source_type == "tag_types" then
        return function(text)
            local input_lower = text:lower()
            local matches = {}
            for _, item in ipairs(tag_types_list) do
                if item:lower():find(input_lower, 1, true) == 1 then
                    table.insert(matches, item)
                end
            end
            if #matches == 0 then return nil end
            return matches, 1, ""
        end
    elseif source_type == "penalty_types" then
        return function(text)
            local input_lower = text:lower()
            local matches = {}
            for _, item in ipairs(penalty_types_list) do
                if item:lower():find(input_lower, 1, true) == 1 then
                    table.insert(matches, item)
                end
            end
            if #matches == 0 then return nil end
            return matches, 1, ""
        end
    end
    return nil
end


-- ============================================================================
-- SECTION 5: LOGGING & OUTPUT
-- ============================================================================

local log_file = nil
local log_filename = nil

local function get_log_filename()
    local path = mp.get_property("path", "")
    if path == "" then
        msg.error("No video loaded")
        return nil
    end

    local ext = path:match("%.(%w+)$") or ""
    local basename = path:match("([^/\\]+)$") or path

    local timestamp = os.time()
    local name_without_ext = basename:gsub("%." .. ext .. "$", "")

    return name_without_ext .. "_tags_" .. timestamp .. ".log"
end

local function open_log_file()
    if log_file then return true end

    local video_path = mp.get_property("path", "")
    if video_path == "" then
        msg.error("No video loaded")
        return false
    end

    local video_dir = video_path:match("^(.+)/[^/]*$") or "."
    local filename = get_log_filename()
    if not filename then return false end

    local full_path = video_dir .. "/" .. filename
    log_file = io.open(full_path, "a")

    if log_file then
        log_filename = filename
        return true
    else
        msg.error("Failed to open log file: " .. full_path)
        return false
    end
end

local function close_log_file()
    if log_file then
        log_file:close()
        log_file = nil
    end
end

local function write_log_line(line)
    if not open_log_file() then return false end
    log_file:write(line, "\n")
    log_file:flush()
    return true
end

local function format_for_log(tag_type, data)
    local line = tag_type

    if tag_type == "goal" then
        if data.scorer and data.scorer ~= "" then
            line = line .. "|score:" .. data.scorer
        end
        local assists_list = {}
        if data.assists then
            for _, v in ipairs(data.assists) do if v and v ~= "" then table.insert(assists_list, v) end end
        end
        if #assists_list > 0 then line = line .. "|assists:" .. table.concat(assists_list, ",") end

    elseif tag_type == "penalty" then
        local length = penalty_category_length[data.category] or ""
        line = string.format("penalty|player:%s|category:%s|type:%s",
                             data.player or "", data.category or "", data.type or "")

    elseif tag_type == "shot" then
        line = string.format("shot|player:%s|outcome:%s|zone:%s",
                             data.player or "", data.outcome or "", data.zone or "")

    elseif tag_type == "block" then
        line = string.format("block|player:%s|zone:%s",
                             data.player or "", data.zone or "")

    elseif tag_type == "change" then
        line = string.format("change|out:%s|incoming:%s",
                             data.out or "", data.incoming or "")

    elseif tag_type == "pass" then
        line = string.format("pass|from:%s|to:%s|success:%s|zone:%s",
                             data.from or "", data.to or "", data.success or "", data.zone or "")

    elseif tag_type == "takeaway" then
        line = string.format("takeaway|player:%s|zone:%s",
                             data.player or "", data.zone or "")

    elseif tag_type == "giveaway" then
        line = string.format("giveaway|player:%s|zone:%s",
                             data.player or "", data.zone or "")

    elseif tag_type == "save" then
        line = "save"

    elseif tag_type == "start" then
        local period = data.period or "?"
        local length = data.length or "?"
        line = string.format("start|period:%s|length:%s|goalie:%s",
                             period, length, data.goalie or "")
        if data.defense and #data.defense > 0 then
            line = line .. "|defense:" .. table.concat(data.defense, ",")
        end
        if data.forwards and #data.forwards > 0 then
            line = line .. "|forwards:" .. table.concat(data.forwards, ",")
        end

    elseif tag_type == "whistle" then
        if data.reason and data.reason ~= "" then
            line = "whistle|reason:" .. data.reason
        else
            line = "whistle"
        end

    elseif tag_type == "faceoff" then
        line = string.format("faceoff|player:%s|win:%s",
                             data.player or "", data.win or "")

    elseif tag_type == "against" then
        line = "against|zone:" .. (data.zone or "")
        if data.note and data.note ~= "" then
            line = line .. "|note:" .. data.note
        end
    end

    return line
end

local function format_for_display(tag_type, data)
    if tag_type == "goal" then
        local msg = "GOAL: " .. player_name(data.scorer)
        local assists_list = {}
        if data.assists then
            for _, v in ipairs(data.assists) do if v and v ~= "" then table.insert(assists_list, player_name(v)) end end
        end
        if #assists_list > 0 then
            msg = msg .. " (A: " .. table.concat(assists_list, ", ") .. ")"
        end
        return msg

    elseif tag_type == "penalty" then
        local length = penalty_category_length[data.category] or ""
        return "PENALTY: " .. player_name(data.player) .. " - " .. length .. " min " .. data.type .. " (" .. data.category .. ")"

    elseif tag_type == "shot" then
        return "SHOT: " .. player_name(data.player) .. " - " .. data.outcome .. " (zone " .. data.zone .. ")"

    elseif tag_type == "block" then
        return "BLOCK: " .. player_name(data.player) .. " (zone " .. data.zone .. ")"

    elseif tag_type == "change" then
        return "OUT: " .. player_name(data.out) .. "  |  IN: " .. player_name(data.incoming)

    elseif tag_type == "pass" then
        return "PASS: " .. player_name(data.from) .. " -> " .. player_name(data.to) .. " (" .. data.success .. ", " .. data.zone .. ")"

    elseif tag_type == "takeaway" then
        return "TAKEAWAY: " .. player_name(data.player) .. " (" .. data.zone .. ")"

    elseif tag_type == "giveaway" then
        return "GIVEAWAY: " .. player_name(data.player) .. " (" .. data.zone .. ")"

    elseif tag_type == "save" then
        return "SAVE"

    elseif tag_type == "start" then
        roster_set_lineup(data.goalie, data.defense, data.forwards)
        roster_show_osd()
        return nil

    elseif tag_type == "whistle" then
        if data.reason and data.reason ~= "" then
            return "WHISTLE: Stoppage - " .. data.reason
        else
            return "WHISTLE: Stoppage"
        end

    elseif tag_type == "faceoff" then
        return "FACEOFF: " .. player_name(data.player) .. (data.win == "y" and " WON" or " LOST")

    elseif tag_type == "against" then
        local msg = "AGAINST (zone " .. data.zone .. ")"
        if data.note and data.note ~= "" then
            msg = msg .. " - " .. data.note
        end
        return msg
    end

    return nil
end


-- ============================================================================
-- SECTION 6: VALIDATION
-- ============================================================================

local validators = {
    goal_count = function(data)
        if not data.scorer or data.scorer == "" then
            return "Scorer is required"
        end

        local assist_count = 0
        if data.assists then
            for _, v in ipairs(data.assists) do if v and v ~= "" then assist_count = assist_count + 1 end end
        end
        if assist_count > 2 then
            return "Maximum 2 assists allowed (got " .. assist_count .. ")"
        end
        return nil
    end,

    start_lineup = function(data)
        if not data.goalie or data.goalie == "" then
            return "Goalie required"
        end

        local defense_count = 0
        if data.defense then
            for _, v in ipairs(data.defense) do if v and v ~= "" then defense_count = defense_count + 1 end end
        end
        if defense_count < 1 or defense_count > 2 then
            return "Start requires 1-2 defensemen (got " .. defense_count .. ")"
        end

        local forward_count = 0
        if data.forwards then
            for _, v in ipairs(data.forwards) do if v and v ~= "" then forward_count = forward_count + 1 end end
        end
        if forward_count < 1 or forward_count > 3 then
            return "Start requires 1-3 forwards (got " .. forward_count .. ")"
        end

        return nil
    end
}

local function validate_tag(tag_type, data)
    local tag = tag_definitions[tag_type]
    if not tag then return nil end

    if tag.validator and validators[tag.validator] then
        local err = validators[tag.validator](data)
        if err then return err end
    end

    for field_name, field_def in pairs(tag.fields) do
        local value = data[field_name]

        -- Skip validation for optional single fields that are empty
        if not field_def.multi and not field_def.required and (not value or value == "") then
            -- Optional single field with no value: skip validation
        else
            if field_def.required then
                if field_def.multi then
                    local count = value and #value or 0
                    if count == 0 then
                        return field_name .. " is required"
                    end
                else
                    if not value or value == "" then
                        return field_name .. " is required"
                    end
                end
            end

            -- For optional multi-fields, skip validation if no entries
            if field_def.multi then
                local has_entries = value and #value > 0
                if not field_def.required and not has_entries then
                    -- Optional multi-field with no entries: skip validation
                elseif has_entries then
                    -- Has entries, validate count
                    local count = 0
                    for _, v in ipairs(value) do if v and v ~= "" then count = count + 1 end end
                    if field_def.min_count and field_def.min_count > 0 and count < field_def.min_count then
                        return field_name .. " requires at least " .. field_def.min_count .. " (got " .. count .. ")"
                    end
                    if field_def.max_count and count > field_def.max_count then
                        return field_name .. " allows at most " .. field_def.max_count .. " (got " .. count .. ")"
                    end
                end
            end
        end
    end

    return nil
end


-- ============================================================================
-- SECTION 7: INPUT HANDLING
-- ============================================================================

local tag_preview_overlay = nil

local function hide_tag_preview()
    if tag_preview_overlay then
        tag_preview_overlay:remove()
        tag_preview_overlay = nil
    end
end

local function show_osd(text, timeout)
    mp.osd_message(text, timeout or 3)
end

local function show_error(message)
    show_osd("ERROR: " .. message, 5)
end

local function get_completion_for_field(field_def)
    if field_def.type == "player" then
        return complete_factory("players")
    elseif field_def.type == "autocomplete" then
        if field_def.source == "penalty_types" then
            return complete_factory("penalty_types")
        end
    elseif field_def.type == "enum" then
        return complete_factory("list", field_def.values)
    elseif field_def.type == "yn" then
        return complete_factory("list", {"y", "n"})
    end
    return nil
end

local function update_tag_preview()
    hide_tag_preview()

    if TaggerState.mode ~= "entering_fields" then return end

    local tag = TaggerState.tag_def
    local data = TaggerState.data
    if not tag or not data then return end

    local lines = {"[" .. TaggerState.tag_type:upper() .. "]"}

    for _, field_name in ipairs(TaggerState.field_order) do
        local field_def = tag.fields[field_name]
        local value = data[field_name]

        if field_def.multi then
            if value and #value > 0 then
                local display_values = {}
                for _, num in ipairs(value) do
                    table.insert(display_values, player_name(num))
                end
                local prompt = field_def.prompt:gsub(":", "")
                table.insert(lines, prompt .. ": " .. table.concat(display_values, ", "))
            end
        elseif value and value ~= "" then
            local display_value = value
            if field_def.type == "player" then
                display_value = player_name(value)
            elseif field_name == "win" then
                display_value = value == "y" and "WON" or "LOST"
            elseif field_name == "length" then
                display_value = value .. " min"
            end
            local prompt = field_def.prompt:gsub(":", "")
            table.insert(lines, prompt .. ": " .. display_value)
        end
    end

    local ass = "{\\an3\\fs24\\bord1\\shad1\\c&H00EEEEFF&\\3c&H000000&}" .. table.concat(lines, "\\N")

    tag_preview_overlay = mp.create_osd_overlay("ass-events")
    if not tag_preview_overlay then return end
    tag_preview_overlay.data = ass
    tag_preview_overlay:update()
end

local function do_next_field()
    if TaggerState.mode ~= "entering_fields" then return end

    local tag = TaggerState.tag_def
    local data = TaggerState.data

    local field_idx = 1
    local field_name = nil

    for i, fname in ipairs(TaggerState.field_order) do
        local field_def = tag.fields[fname]
        local value = data[fname]

        if field_def.multi then
            -- Check if user has started entering (data[field_name] exists)
            local has_started = data[fname] ~= nil
            local value_count = 0
            local is_finished = false
            if has_started then
                for _, v in ipairs(data[fname]) do if v and v ~= "" then value_count = value_count + 1 end end
                -- Check if user marked this field as finished
                is_finished = TaggerState.field_finished and TaggerState.field_finished[fname]
            end

            if not has_started then
                -- Never started: prompt for this field
                field_idx = i
                field_name = fname
                break
            elseif value_count == 0 then
                -- Started but no entries: user pressed Enter to finish with 0 entries, skip
            elseif is_finished then
                -- User finished this field, skip
            else
                -- Has entries and not finished: check if can add more
                local can_add_more = not field_def.max_count or value_count < field_def.max_count
                if can_add_more then
                    field_idx = i
                    field_name = fname
                    break
                end
                -- At max or user wants to stop, skip to next
            end
        else
            -- Single field (non-multi)
            local is_finished = TaggerState.field_finished and TaggerState.field_finished[fname]
            if is_finished then
                -- Already prompted, skip
            elseif not value or value == "" then
                -- Empty: prompt at least once
                field_idx = i
                field_name = fname
                break
            end
        end
    end

    if not field_name then
        hide_tag_preview()
        local timestamp = mp.get_property_number("time-pos", 0)
        local err = validate_tag(TaggerState.tag_type, data)
        if err then
            show_error(err)
            mp.set_property_bool("pause", false)
            reset_state()
            return
        end

        local line = string.format("%.1f", timestamp)
        local tag_line = format_for_log(TaggerState.tag_type, data)
        line = line .. "|" .. tag_line

        if write_log_line(line) then
            if TaggerState.tag_type == "change" then
                roster_change(TaggerState.data.out, TaggerState.data.incoming)
            elseif TaggerState.tag_type == "start" then
                roster_set_lineup(TaggerState.data.goalie, TaggerState.data.defense, TaggerState.data.forwards)
            end

            local display = format_for_display(TaggerState.tag_type, data)
            if display then
                show_osd(display, 5)
            end
        else
            show_error("Failed to write log")
        end

        mp.set_property_bool("pause", false)
        reset_state()
        return
    end

    local field_def = tag.fields[field_name]
    update_tag_preview()

    input.get({
        prompt = field_def.prompt,
        complete = get_completion_for_field(field_def),
        submit = function(value)
            hide_tag_preview()
            if not value or value == "" then
                if field_def.multi then
                    local current = data[field_name] or {}
                    local count = 0
                    for _, v in ipairs(current) do if v and v ~= "" then count = count + 1 end end
                    if count == 0 then
                        -- No entries yet
                        if field_def.required then
                            show_error(field_name .. " required")
                            mp.add_timeout(0.1, do_next_field)
                            return
                        end
                        -- Mark as started with no entries
                        data[field_name] = {}
                        TaggerState.field_finished[field_name] = true
                    else
                        -- Has entries and user pressed Enter: finish this field
                        TaggerState.field_finished[field_name] = true
                    end
                else
                    -- Single field (non-multi)
                    if field_def.required then
                        show_error(field_name .. " required")
                        mp.add_timeout(0.1, do_next_field)
                        return
                    end
                    -- Optional single field: mark as finished, value remains nil/empty
                    TaggerState.field_finished[field_name] = true
                end
                mp.add_timeout(0.1, do_next_field)
                return
            end

            if field_def.type == "player" and not is_valid_player(value) then
                show_error("Invalid player: " .. value)
                mp.add_timeout(0.1, do_next_field)
                return
            end

            if field_def.type == "yn" then
                value = value:lower():match("^[y]") and "y" or "n"
            end

            if field_def.multi then
                if not data[field_name] then data[field_name] = {} end
                table.insert(data[field_name], value)

                local count = 0
                for _, v in ipairs(data[field_name]) do if v and v ~= "" then count = count + 1 end end
                if field_def.max_count and count >= field_def.max_count then
                    TaggerState.field_finished[field_name] = true
                end
            else
                data[field_name] = value
                TaggerState.field_finished[field_name] = true
            end

            mp.add_timeout(0.1, do_next_field)
        end,
        cancel = function()
            hide_tag_preview()
            mp.set_property_bool("pause", false)
            reset_state()
        end,
    })
end

local function start_tagging()
    local vid = mp.get_property("video")
    if not vid then return end

    mp.set_property_bool("pause", true)
    roster_show_osd()
    TaggerState.mode = "selecting_type"

    input.get({
        prompt = "Tag type:",
        complete = complete_factory("tag_types"),
        submit = function(tag_type)
            if not tag_type or tag_type == "" then
                mp.set_property_bool("pause", false)
                reset_state()
                return
            end

            local tag = tag_definitions[tag_type]
            if not tag then
                show_error("Invalid tag type: " .. tag_type)
                mp.set_property_bool("pause", false)
                reset_state()
                return
            end

            TaggerState.mode = "entering_fields"
            TaggerState.tag_type = tag_type
            TaggerState.tag_def = tag
            TaggerState.data = {}

            TaggerState.field_order = tag.order

            update_tag_preview()
            mp.add_timeout(0.1, do_next_field)
        end,
        cancel = function()
            hide_tag_preview()
            mp.set_property_bool("pause", false)
            reset_state()
        end,
    })
end


-- ============================================================================
-- SECTION 8: KEY BINDINGS & EVENTS
-- ============================================================================

mp.add_key_binding(config.leader_key, "tagger-enter", start_tagging)

mp.register_event("shutdown", close_log_file)
mp.register_event("end-file", close_log_file)

msg.info("Hockey Video Tagger loaded. Press " .. config.leader_key .. " to tag events.")
