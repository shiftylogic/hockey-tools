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
      - TAGGER_CONF: Path to config file (required)

    Output: {video}_tags_{timestamp}.log next to source video
]]

local msg = require 'mp.msg'
local utils = require 'mp.utils'
local options = require 'mp.options'
local input = require 'mp.input'


-- ============================================================================
-- CONFIGURATION
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

    local result = {player_numbers = {}, player_map = {}}

    local lua_start, lua_end = content:find("player_map%s*=%s*{")
    if lua_start and lua_end then
        local lua_block = content:sub(lua_end + 1)
        local depth = 1
        local block_end = 0
        for i = 1, #lua_block do
            local c = lua_block:sub(i, i)
            if c == "{" then depth = depth + 1 end
            if c == "}" then depth = depth - 1 end
            if depth == 0 then
                block_end = i
                break
            end
        end
        if block_end > 0 then
            lua_block = lua_block:sub(1, block_end - 1)
            for num, name in lua_block:gmatch("(%d+)%s*=%s*[\"]([^\"]+)[\"]") do
                result.player_map[tonumber(num)] = name
            end
        end
    end

    for line in content:gmatch("[^\r\n]+") do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line == "" or line:find("^player_map") then goto continue end

        local key, value = line:match("^(%w+)%s*=%s*(.+)")
        if not key or not value then goto continue end

        if key == "leader_key" then
            result.leader_key = value
        elseif key == "player_numbers" then
            result.player_numbers = {}
            for num in value:gmatch("(%d+)") do
                table.insert(result.player_numbers, tonumber(num))
            end
        end

        ::continue::
    end

    return result
end

local env_config_path = os.getenv("TAGGER_CONF")
if not env_config_path then
    msg.fatal("TAGGER_CONF environment variable is not set. Please set it to the path of your config file.")
    return
end

local user_config = load_config(env_config_path)
if user_config then
    config.leader_key = user_config.leader_key or config.leader_key
    config.player_numbers = user_config.player_numbers or config.player_numbers
    config.player_map = user_config.player_map or config.player_map
else
    msg.warn("tagger.conf not found, using defaults")
end

local function is_valid_player(num)
    num = tonumber(num)
    return num ~= nil and config.player_map[num] ~= nil
end


-- ============================================================================
-- TAG DEFINITIONS
-- ============================================================================

local tag_definitions = {
    goal = {
        prompt = "Goal",
        fields = {
            {name = "scorer", prompt = "Scorer:", required = true, player = true},
            {name = "assist1", prompt = "Assist 1 (Enter to skip):", required = false, player = true},
            {name = "assist2", prompt = "Assist 2 (Enter to skip):", required = false, player = true},
            {name = "other", prompt = "Other players (Enter to finish):", required = false, player = true, multi = true},
        }
    },
    penalty = {
        prompt = "Penalty",
        fields = {
            {name = "player", prompt = "Player:", required = true, player = true},
            {name = "length", prompt = "Length (2, 5, or 10):", required = true, validate = function(v) return v == "2" or v == "5" or v == "10" end, error = "Use: 2, 5, or 10"},
            {name = "type", prompt = "Type:", required = true, autocomplete = "penalty"},
        }
    },
    shot = {
        prompt = "Shot",
        fields = {
            {name = "player", prompt = "Shooter:", required = true, player = true},
            {name = "outcome", prompt = "Outcome (missed/saved/blocked):", required = true, validate = function(v) return v == "missed" or v == "saved" or v == "blocked" end, error = "Use: missed, saved, or blocked"},
        }
    },
    block = {
        prompt = "Block",
        fields = {
            {name = "player", prompt = "Blocker:", required = true, player = true},
        }
    },
    change = {
        prompt = "Change",
        fields = {
            {name = "out", prompt = "Outgoing:", required = true, player = true},
            {name = "incoming", prompt = "Incoming:", required = true, player = true},
        }
    },
    pass = {
        prompt = "Pass",
        fields = {
            {name = "from", prompt = "From:", required = true, player = true},
            {name = "to", prompt = "To:", required = true, player = true},
            {name = "success", prompt = "Outcome (success/off-target/missed):", required = true, validate = function(v) return v == "success" or v == "off-target" or v == "missed" end, error = "Use: success, off-target, or missed"},
        }
    },
    takeaway = {
        prompt = "Takeaway",
        fields = {
            {name = "player", prompt = "Player:", required = true, player = true},
        }
    },
    giveaway = {
        prompt = "Giveaway",
        fields = {
            {name = "player", prompt = "Player:", required = true, player = true},
        }
    },
    save = {
        prompt = "Save",
        fields = {
            {name = "player", prompt = "Goaltender:", required = true, player = true},
        }
    },
    start = {
        prompt = "Start",
        fields = {
            {name = "period", prompt = "Period (1, 2, 3, OT):", required = true, validate = function(v) return v == "1" or v == "2" or v == "3" or v:upper() == "OT" end, error = "Use: 1, 2, 3, or OT"},
            {name = "length", prompt = "Length (mm:ss):", required = true, validate = function(v) return v:match("^%d+:%d%d$") ~= nil end, error = "Use: mm:ss"},
            {name = "goalie", prompt = "Goaltender:", required = true, player = true},
            {name = "defense", prompt = "Defensemen (Enter to finish):", required = false, player = true, multi = true, min_count = 1, max_count = 2},
            {name = "forwards", prompt = "Forwards (Enter to finish):", required = false, player = true, multi = true, min_count = 1, max_count = 3},
        }
    },
    whistle = {
        prompt = "Whistle",
        fields = {
            {name = "reason", prompt = "Reason (optional):", required = false},
        }
    },
    faceoff = {
        prompt = "Faceoff",
        fields = {
            {name = "player", prompt = "Player:", required = true, player = true},
            {name = "win", prompt = "Win (y/n):", required = true, validate = function(v) return v:lower():match("^[ywn]") ~= nil end, error = "Use: y/n"},
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
-- LOG FILE HANDLING
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


-- ============================================================================
-- COMPLETION FUNCTIONS
-- ============================================================================

local function complete_from_list(input_text, list)
    local input_lower = input_text:lower()
    local matches = {}
    for _, item in ipairs(list) do
        if item:lower():find(input_lower, 1, true) == 1 then
            table.insert(matches, item)
        end
    end
    if #matches == 0 then return nil end
    return matches, 1, ""
end

local function complete_tag_type(t) return complete_from_list(t, tag_types_list) end
local function complete_penalty_type(t) return complete_from_list(t, penalty_types_list) end
local function complete_shot_outcome(t) return complete_from_list(t, shot_outcome_list) end
local function complete_pass_outcome(t) return complete_from_list(t, pass_outcome_list) end

local function complete_player(num)
    local matches = {}
    for n, _ in pairs(config.player_map) do
        local s = tostring(n)
        if s:find(num, 1, true) == 1 then
            table.insert(matches, s)
        end
    end
    if #matches == 0 then return nil end
    return matches, 1, ""
end


-- ============================================================================
-- OSD HELPERS
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

local function player_name(num)
    local name = config.player_map[tonumber(num)]
    if name then
        return "#" .. num .. " " .. name
    end
    return "Player " .. num
end

local function update_tag_preview(tag_type, fields, data)
    hide_tag_preview()

    if not fields or not tag_type or not data then return end
    if type(tag_type) ~= "string" then return end
    if type(fields) ~= "table" then return end
    if type(data) ~= "table" then return end

    local lines = {"[" .. tag_type:upper() .. "]"}

    for i, field in ipairs(fields) do
        local value = data[field.name]
        if field.multi then
            local values = {}
            for _, entry in ipairs(data) do
                if entry.name == field.name and entry.value ~= "" then
                    table.insert(values, player_name(entry.value))
                end
            end
            if #values > 0 then
                table.insert(lines, field.prompt:gsub(":", "") .. ": " .. table.concat(values, ", "))
            end
        elseif value and value ~= "" then
            local display_value = value
            if field.player then
                display_value = player_name(value)
            elseif field.name == "win" then
                display_value = value == "y" and "WON" or "LOST"
            elseif field.name == "length" then
                display_value = value .. " min"
            end
            table.insert(lines, field.prompt:gsub(":", "") .. ": " .. display_value)
        end
    end

    local ass = "{\\an3\\fs24\\bord1\\shad1\\c&H00EEEEFF&\\3c&H000000&}" .. table.concat(lines, "\\N")

    tag_preview_overlay = mp.create_osd_overlay("ass-events")
    if not tag_preview_overlay then return end
    tag_preview_overlay.data = ass
    tag_preview_overlay:update()
end

local function show_tag_summary(tag_type, data)
    local msg = tag_type:upper() .. " by "

    if tag_type == "goal" then
        msg = msg .. player_name(data.scorer)
        if data.assist1 and data.assist1 ~= "" then
            msg = msg .. " (A: " .. player_name(data.assist1)
            if data.assist2 and data.assist2 ~= "" then
                msg = msg .. ", " .. player_name(data.assist2)
            end
            msg = msg .. ")"
        end
    elseif tag_type == "penalty" then
        msg = msg .. player_name(data.player) .. " - " .. data.length .. " min " .. data.type
    elseif tag_type == "shot" then
        msg = msg .. player_name(data.player) .. " - " .. data.outcome
    elseif tag_type == "block" then
        msg = msg .. player_name(data.player)
    elseif tag_type == "change" then
        msg = "OUT: " .. player_name(data.out) .. "  |  IN: " .. player_name(data.incoming)
    elseif tag_type == "pass" then
        msg = msg .. player_name(data.from) .. " -> " .. player_name(data.to) .. " (" .. data.success .. ")"
    elseif tag_type == "takeaway" then
        msg = msg .. player_name(data.player)
    elseif tag_type == "giveaway" then
        msg = msg .. player_name(data.player)
    elseif tag_type == "save" then
        msg = msg .. player_name(data.player)
    elseif tag_type == "start" then
        local period = data.period or "?"
        local period_ordinal = period:upper() == "OT" and "Overtime" or period .. (period == "1" and "st" or period == "2" and "nd" or "rd")
        local defense = {}
        for _, entry in ipairs(data) do
            if entry.name == "defense" and entry.value ~= "" then
                table.insert(defense, player_name(entry.value))
            end
        end
        local forwards = {}
        for _, entry in ipairs(data) do
            if entry.name == "forwards" and entry.value ~= "" then
                table.insert(forwards, player_name(entry.value))
            end
        end

        local overlay = mp.create_osd_overlay("ass-events")
        if overlay then
            local lines = {
                "Start of " .. period_ordinal .. " Period",
                player_name(data.goalie),
                #defense > 0 and table.concat(defense, " | ") or "",
                #forwards > 0 and table.concat(forwards, " | ") or ""
            }
            local ass = "{\\an5\\fs28\\bord2\\shad1\\c&H00EEFF00&\\3c&H000000&}"
            ass = ass .. table.concat(lines, "\\N")
            overlay.data = ass
            overlay:update()
            mp.add_timeout(5, function()
                overlay:remove()
            end)
        end
        return
    elseif tag_type == "whistle" then
        if data.reason and data.reason ~= "" then
            msg = "Stoppage - " .. data.reason
        else
            msg = "Stoppage"
        end
    elseif tag_type == "faceoff" then
        msg = msg .. player_name(data.player) .. (data.win == "y" and " WON" or " LOST")
    end

    local overlay = mp.create_osd_overlay("ass-events")
    if overlay then
        overlay.data = "{\\an5\\fs30\\bord2\\shad1\\c&H00EEFF00&\\3c&H000000&}" .. msg
        overlay:update()
        mp.add_timeout(5, function()
            overlay:remove()
        end)
    end
end


-- ============================================================================
-- TAG FORMATTERS
-- ============================================================================

local formatters = {
    goal = function(data)
        local line = "goal"
        if data.scorer and data.scorer ~= "" then
            line = line .. "|score:" .. data.scorer
        end
        local assists = {}
        if data.assist1 and data.assist1 ~= "" then table.insert(assists, data.assist1) end
        if data.assist2 and data.assist2 ~= "" then table.insert(assists, data.assist2) end
        if #assists > 0 then line = line .. "|assists:" .. table.concat(assists, ",") end

        local others = {}
        for _, entry in ipairs(data) do
            if entry.name == "other" and entry.value ~= "" then
                table.insert(others, entry.value)
            end
        end
        if #others > 0 then line = line .. "|other:" .. table.concat(others, ",") end

        return line
    end,

    penalty = function(data)
        return string.format("penalty|player:%s|length:%s|type:%s", data.player, data.length, data.type)
    end,

    shot = function(data)
        return string.format("shot|player:%s|outcome:%s", data.player, data.outcome)
    end,

    block = function(data)
        return "block|player:" .. data.player
    end,

    change = function(data)
        return string.format("change|out:%s|incoming:%s", data.out, data.incoming)
    end,

    pass = function(data)
        return string.format("pass|from:%s|to:%s|success:%s", data.from, data.to, data.success)
    end,

    takeaway = function(data)
        return "takeaway|player:" .. data.player
    end,

    giveaway = function(data)
        return "giveaway|player:" .. data.player
    end,

    save = function(data)
        return "save|player:" .. data.player
    end,

    start = function(data)
        local period = data.period or "?"
        local length = data.length or "?"
        local line = string.format("start|period:%s|length:%s|goalie:%s", period, length, data.goalie)

        local defense = {}
        for _, entry in ipairs(data) do
            if entry.name == "defense" and entry.value ~= "" then
                table.insert(defense, entry.value)
            end
        end
        if #defense > 0 then line = line .. "|defense:" .. table.concat(defense, ",") end

        local forwards = {}
        for _, entry in ipairs(data) do
            if entry.name == "forwards" and entry.value ~= "" then
                table.insert(forwards, entry.value)
            end
        end
        if #forwards > 0 then line = line .. "|forwards:" .. table.concat(forwards, ",") end

        return line
    end,

    whistle = function(data)
        if data.reason and data.reason ~= "" then
            return "whistle|reason:" .. data.reason
        end
        return "whistle"
    end,

    faceoff = function(data)
        return string.format("faceoff|player:%s|win:%s", data.player, data.win)
    end,
}


-- ============================================================================
-- VALIDATION AND LOGGING
-- ============================================================================

local validators = {
    goal = function(data)
        local count = 0
        if data.scorer and data.scorer ~= "" then count = count + 1 end
        if data.assist1 and data.assist1 ~= "" then count = count + 1 end
        if data.assist2 and data.assist2 ~= "" then count = count + 1 end
        for _, entry in ipairs(data) do
            if entry.name == "other" and entry.value ~= "" then count = count + 1 end
        end
        if count < 3 or count > 6 then
            return "Goal requires 3-6 players (got " .. count .. ")"
        end
        return nil
    end,

    start = function(data)
        if not data.goalie or data.goalie == "" then
            return "Goalie required"
        end

        local defense_count = 0
        for _, entry in ipairs(data) do
            if entry.name == "defense" and entry.value ~= "" then
                defense_count = defense_count + 1
            end
        end
        if defense_count < 1 or defense_count > 2 then
            return "Start requires 1-2 defensemen (got " .. defense_count .. ")"
        end

        local forward_count = 0
        for _, entry in ipairs(data) do
            if entry.name == "forwards" and entry.value ~= "" then
                forward_count = forward_count + 1
            end
        end
        if forward_count < 1 or forward_count > 3 then
            return "Start requires 1-3 forwards (got " .. forward_count .. ")"
        end

        return nil
    end,
}

local function validate_and_log(tag_type, data)
    hide_tag_preview()
    local timestamp = mp.get_property_number("time-pos", 0)

    if validators[tag_type] then
        local err = validators[tag_type](data)
        if err then
            show_error(err)
            mp.set_property_bool("pause", false)
            return
        end
    end

    local formatter = formatters[tag_type]
    if not formatter then return end

    local line = string.format("%.1f", timestamp)
    local tag_line = formatter(data)
    line = line .. "|" .. tag_line

    if write_log_line(line) then
        show_tag_summary(tag_type, data)
    else
        show_error("Failed to write log")
    end

    mp.set_property_bool("pause", false)
end


-- ============================================================================
-- TAG ENTRY
-- ============================================================================

local pending_field = nil
local pending_data = nil

local function do_next_field()
    if not pending_field then return end

    local tag_type = pending_field.tag_type
    local fields = pending_field.fields
    local data = pending_data
    local index = pending_field.index

    pending_field = nil
    pending_data = nil

    if index > #fields then
        hide_tag_preview()
        validate_and_log(tag_type, data)
        return
    end

    local field = fields[index]

    update_tag_preview(tag_type, fields, data)

    local completion = nil
    if field.player then
        completion = complete_player
    elseif field.autocomplete then
        if field.autocomplete == "penalty" then
            completion = complete_penalty_type
        elseif field.autocomplete == "tag_type" then
            completion = complete_tag_type
        end
    elseif field.name == "outcome" then
        completion = complete_shot_outcome
    elseif field.name == "success" then
        completion = complete_pass_outcome
    end

    input.get({
        prompt = field.prompt,
        complete = completion,
        submit = function(value)
            hide_tag_preview()
            if not value or value == "" then
                if field.required and not field.multi then
                    show_error("Field required")
                    mp.add_timeout(0.1, function()
                        pending_field = {tag_type = tag_type, fields = fields, index = index}
                        pending_data = data
                        do_next_field()
                    end)
                    return
                end

                if field.multi then
                    local count = 0
                    for _, entry in ipairs(data) do if entry.name == field.name then count = count + 1 end end
                    if field.min_count and count < field.min_count then
                        show_error(field.name .. " requires at least " .. field.min_count .. " (got " .. count .. ")")
                        mp.add_timeout(0.1, function()
                            pending_field = {tag_type = tag_type, fields = fields, index = index}
                            pending_data = data
                            do_next_field()
                        end)
                        return
                    end
                    if field.max_count and count > field.max_count then
                        show_error(field.name .. " allows at most " .. field.max_count .. " (got " .. count .. ")")
                        mp.add_timeout(0.1, function()
                            pending_field = {tag_type = tag_type, fields = fields, index = index}
                            pending_data = data
                            do_next_field()
                        end)
                        return
                    end
                end

                pending_field = {tag_type = tag_type, fields = fields, index = index + 1}
                pending_data = data
                mp.add_timeout(0.1, do_next_field)
                return
            end

            if field.player and not is_valid_player(value) then
                show_error("Invalid player: " .. value)
                mp.add_timeout(0.1, function()
                    pending_field = {tag_type = tag_type, fields = fields, index = index}
                    pending_data = data
                    do_next_field()
                end)
                return
            end

            if field.validate and not field.validate(value) then
                show_error(field.error or "Invalid")
                mp.add_timeout(0.1, function()
                    pending_field = {tag_type = tag_type, fields = fields, index = index}
                    pending_data = data
                    do_next_field()
                end)
                return
            end

            if field.name == "win" then
                value = value:lower():match("^[y]") and "y" or "n"
            end

            if field.multi then
                table.insert(data, {name = field.name, value = value})
                pending_field = {tag_type = tag_type, fields = fields, index = index}
            else
                data[field.name] = value
                pending_field = {tag_type = tag_type, fields = fields, index = index + 1}
            end
            pending_data = data
            mp.add_timeout(0.1, do_next_field)
        end,
        cancel = function()
            hide_tag_preview()
            mp.set_property_bool("pause", false)
        end,
    })
end

local function start_tagging()
    local vid = mp.get_property("video")
    if not vid then return end

    mp.set_property_bool("pause", true)
    show_osd(">> TAG MODE <<", 10)

    input.get({
        prompt = "Tag type:",
        complete = complete_tag_type,
        submit = function(tag_type)
            if not tag_type or tag_type == "" then
                mp.set_property_bool("pause", false)
                return
            end

            local tag = tag_definitions[tag_type]
            if not tag then
                show_error("Invalid tag type: " .. tag_type)
                mp.set_property_bool("pause", false)
                return
            end

            pending_field = {tag_type = tag_type, fields = tag.fields, index = 1}
            pending_data = {}
            update_tag_preview(tag_type, tag.fields, pending_data)
            mp.add_timeout(0.1, do_next_field)
        end,
        cancel = function()
            hide_tag_preview()
            mp.set_property_bool("pause", false)
        end,
    })
end


-- ============================================================================
-- KEY BINDINGS
-- ============================================================================

mp.add_key_binding(config.leader_key, "tagger-enter", start_tagging)


-- ============================================================================
-- CLEANUP
-- ============================================================================

mp.register_event("shutdown", close_log_file)
mp.register_event("end-file", close_log_file)

msg.info("Hockey Video Tagger loaded. Press " .. config.leader_key .. " to tag events.")
