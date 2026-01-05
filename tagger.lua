--[[
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
    player_numbers = {},
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
        player_numbers = {},
        player_map = {},
    }

    if parsed.player_numbers then
        for _, num in ipairs(parsed.player_numbers) do
            table.insert(result.player_numbers, tonumber(num))
        end
    end

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
    config.player_numbers = user_config.player_numbers or config.player_numbers
    config.player_map = user_config.player_map or config.player_map
end


-- ============================================================================
-- SECTION 2: CONSTANTS & DATA DEFINITIONS
-- ============================================================================

local tag_definitions = {
    goal = {
        prompt = "Goal",
        order = {"scorer", "assists", "other"},
        fields = {
            scorer = { prompt = "Scorer:", type = "player", required = true },
            assists = { prompt = "Assists (Enter to finish):", type = "player", multi = true,
                        min_count = 0, max_count = 2 },
            other = { prompt = "Other players (Enter to finish):", type = "player", multi = true,
                      min_count = 0, max_count = 4 }
        },
        validator = "goal_count"
    },
    penalty = {
        prompt = "Penalty",
        order = {"player", "length", "type"},
        fields = {
            player = { prompt = "Player:", type = "player", required = true },
            length = { prompt = "Length (2, 5, or 10):", type = "enum", values = {"2", "5", "10"}, required = true },
            type = { prompt = "Type:", type = "autocomplete", source = "penalty_types", required = true }
        }
    },
    shot = {
        prompt = "Shot",
        order = {"player", "outcome"},
        fields = {
            player = { prompt = "Shooter:", type = "player", required = true },
            outcome = { prompt = "Outcome (missed/saved/blocked):", type = "enum",
                        values = {"missed", "saved", "blocked"}, required = true }
        }
    },
    block = {
        prompt = "Block",
        order = {"player"},
        fields = {
            player = { prompt = "Blocker:", type = "player", required = true }
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
        order = {"from", "to", "success"},
        fields = {
            from = { prompt = "From:", type = "player", required = true },
            to = { prompt = "To:", type = "player", required = true },
            success = { prompt = "Outcome (success/off-target/missed):", type = "enum",
                        values = {"success", "off-target", "missed"}, required = true }
        }
    },
    takeaway = {
        prompt = "Takeaway",
        order = {"player"},
        fields = {
            player = { prompt = "Player:", type = "player", required = true }
        }
    },
    giveaway = {
        prompt = "Giveaway",
        order = {"player"},
        fields = {
            player = { prompt = "Player:", type = "player", required = true }
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

local shot_outcome_list = {"missed", "saved", "blocked"}
local pass_outcome_list = {"missed", "success", "off-target"}


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
        if data.other and #data.other > 0 then
            local other_list = {}
            for _, v in ipairs(data.other) do if v and v ~= "" then table.insert(other_list, v) end end
            line = line .. "|other:" .. table.concat(other_list, ",")
        end

    elseif tag_type == "penalty" then
        line = string.format("penalty|player:%s|length:%s|type:%s",
                             data.player or "", data.length or "", data.type or "")

    elseif tag_type == "shot" then
        line = string.format("shot|player:%s|outcome:%s",
                             data.player or "", data.outcome or "")

    elseif tag_type == "block" then
        line = "block|player:" .. (data.player or "")

    elseif tag_type == "change" then
        line = string.format("change|out:%s|incoming:%s",
                             data.out or "", data.incoming or "")

    elseif tag_type == "pass" then
        line = string.format("pass|from:%s|to:%s|success:%s",
                             data.from or "", data.to or "", data.success or "")

    elseif tag_type == "takeaway" then
        line = "takeaway|player:" .. (data.player or "")

    elseif tag_type == "giveaway" then
        line = "giveaway|player:" .. (data.player or "")

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
    end

    return line
end

local function format_for_display(tag_type, data)
    if tag_type == "goal" then
        local msg = "GOAL by " .. player_name(data.scorer)
        local assists_list = {}
        if data.assists then
            for _, v in ipairs(data.assists) do if v and v ~= "" then table.insert(assists_list, player_name(v)) end end
        end
        if #assists_list > 0 then
            msg = msg .. " (A: " .. table.concat(assists_list, ", ") .. ")"
        end
        return msg

    elseif tag_type == "penalty" then
        return player_name(data.player) .. " - " .. data.length .. " min " .. data.type

    elseif tag_type == "shot" then
        return player_name(data.player) .. " - " .. data.outcome

    elseif tag_type == "block" then
        return "BLOCK: " .. player_name(data.player)

    elseif tag_type == "change" then
        return "OUT: " .. player_name(data.out) .. "  |  IN: " .. player_name(data.incoming)

    elseif tag_type == "pass" then
        return player_name(data.from) .. " -> " .. player_name(data.to) .. " (" .. data.success .. ")"

    elseif tag_type == "takeaway" then
        return "TAKEAWAY: " .. player_name(data.player)

    elseif tag_type == "giveaway" then
        return "GIVEAWAY: " .. player_name(data.player)

    elseif tag_type == "save" then
        return "SAVE"

    elseif tag_type == "start" then
        local period = data.period or "?"
        local period_ordinal = period:upper() == "OT" and "Overtime"
                            or period .. (period == "1" and "st" or period == "2" and "nd" or "rd")
        local defense_str = ""
        if data.defense and #data.defense > 0 then
            local names = {}
            for _, num in ipairs(data.defense) do table.insert(names, player_name(num)) end
            defense_str = table.concat(names, " | ")
        end
        local forwards_str = ""
        if data.forwards and #data.forwards > 0 then
            local names = {}
            for _, num in ipairs(data.forwards) do table.insert(names, player_name(num)) end
            forwards_str = table.concat(names, " | ")
        end

        local overlay = mp.create_osd_overlay("ass-events")
        if overlay then
            local lines = {
                "Start of " .. period_ordinal .. " Period",
                player_name(data.goalie),
                defense_str,
                forwards_str
            }
            local ass = "{\\an5\\fs28\\bord2\\shad1\\c&H00EEFF00&\\3c&H000000&}"
            ass = ass .. table.concat(lines, "\\N")
            overlay.data = ass
            overlay:update()
            mp.add_timeout(5, function()
                overlay:remove()
            end)
        end
        return nil

    elseif tag_type == "whistle" then
        if data.reason and data.reason ~= "" then
            return "Stoppage - " .. data.reason
        else
            return "Stoppage"
        end

    elseif tag_type == "faceoff" then
        return player_name(data.player) .. (data.win == "y" and " WON" or " LOST")
    end

    return nil
end


-- ============================================================================
-- SECTION 6: VALIDATION
-- ============================================================================

local validators = {
    goal_count = function(data)
        local count = 0
        if data.scorer and data.scorer ~= "" then count = count + 1 end
        if data.assists then
            for _, v in ipairs(data.assists) do if v and v ~= "" then count = count + 1 end end
        end
        if data.other then
            for _, v in ipairs(data.other) do if v and v ~= "" then count = count + 1 end end
        end
        if count < 3 or count > 6 then
            return "Goal requires 3-6 players (got " .. count .. ")"
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
    show_osd(">> TAG MODE <<", 10)
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
