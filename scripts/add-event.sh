#!/usr/bin/env bash
#
# add-event.sh - Inject individual game events into the hockey stats database
#
# Usage:
#   ./scripts/add-event.sh game <date> <opponent> [options]
#   ./scripts/add-event.sh goal-for <game_id> <period> <time> <scorer_jersey> [assists_jerseys] [options]
#   ./scripts/add-event.sh goal-against <game_id> <period> <time> <on_ice_jerseys> [options]
#   ./scripts/add-event.sh penalty <game_id> <period> <time> <player_jersey> <type> <category> [notes]
#   ./scripts/add-event.sh passing <game_id> <period> <attempts> <completed>
#
# Examples:
#   ./scripts/add-event.sh game "2026-01-26" "Seattle Kraken" --our-score 3 --their-score 2
#   ./scripts/add-event.sh goal-for 1 1 "12:34" 8 31,19 --type power_play
#   ./scripts/add-event.sh goal-against 1 2 "05:15" 8,31,6,19,47,88
#   ./scripts/add-event.sh penalty 1 3 "10:00" 47 slashing minor "Hooking on the breakaway"
#   ./scripts/add-event.sh passing 1 1 25 18
#

set -e

DB_FILE="${DB_FILE:-stats.db}"

if ! command -v sqlite3 &> /dev/null; then
    echo "Error: sqlite3 command not found."
    exit 1
fi

usage() {
    echo "Usage: $0 <command> [args]"
    echo ""
    echo "Commands:"
    echo "  game <date> <opponent> [--our-score N] [--their-score N] [--time-mins N]"
    echo "  roster <game_id> [--copy-from <game_id>]"
    echo "  tag <game_id> <tag_name>"
    echo "  goal-for <game_id> <period> <time> <scorer_j> [assist_js] [--type TYPE] [--empty-net] [--extra <extra_js>]"
    echo "  goal-against <game_id> <period> <time> <on_ice_js> [--type TYPE]"
    echo "  penalty <game_id> <period> <time> <player_j> <type> <category> [notes]"
    echo "  passing <game_id> <period> <attempts> <completed>"
    echo ""
    echo "Notes:"
    echo "  - <time> can be MM:SS or raw seconds."
    echo "  - <assist_js>, <on_ice_js>, <extra_js> are comma-separated jersey numbers."
    echo "  - TYPE: even_strength (default), power_play, shorthanded, shootout, penalty_shot"
    echo "  - category: minor, major, misconduct, game_misconduct, match"
    exit 1
}

time_to_seconds() {
    local t=$1
    if [[ $t =~ ^([0-9]+):([0-9]{2})$ ]]; then
        echo $(( 10#${BASH_REMATCH[1]} * 60 + 10#${BASH_REMATCH[2]} ))
    else
        echo "$t"
    fi
}

get_player_id() {
    local j=$1
    local id
    id=$(sqlite3 "$DB_FILE" "SELECT player_id FROM roster WHERE jersey_number = $j;")
    if [ -z "$id" ]; then
        echo "Error: Player with jersey #$j not found in roster." >&2
        exit 1
    fi
    echo "$id"
}

get_penalty_type_id() {
    local name=$1
    local cat=$2
    local id
    id=$(sqlite3 "$DB_FILE" "SELECT penalty_type_id FROM penalty_types WHERE penalty_name = '$name' AND penalty_category = '$cat' LIMIT 1;")
    if [ -z "$id" ]; then
        # Try some fuzzy matching for common variants
        local alt_name="$name"
        [[ "$name" == "high_sticking" ]] && alt_name="high-sticking"
        [[ "$name" == "high-stick" ]] && alt_name="high-sticking"
        [[ "$name" == "cross_check" ]] && alt_name="cross-checking"
        [[ "$name" == "cross-checking" ]] && alt_name="cross-checking"

        id=$(sqlite3 "$DB_FILE" "SELECT penalty_type_id FROM penalty_types WHERE penalty_name = '$alt_name' AND penalty_category = '$cat' LIMIT 1;")
    fi

    if [ -z "$id" ]; then
        echo "Error: Penalty type '$name' with category '$cat' not found." >&2
        echo "Available types for $cat:" >&2
        sqlite3 "$DB_FILE" "SELECT penalty_name FROM penalty_types WHERE penalty_category = '$cat';" >&2
        exit 1
    fi
    echo "$id"
}

cmd_game() {
    local date="$1"; shift
    local opponent="$1"; shift
    local our_score=0
    local their_score=0
    local time_mins=90

    while [[ $# -gt 0 ]]; do
        case $1 in
            --our-score) our_score="$2"; shift 2 ;;
            --their-score) their_score="$2"; shift 2 ;;
            --time-mins) time_mins="$2"; shift 2 ;;
            *) echo "Unknown option: $1"; usage ;;
        esac
    done

    # Default period lengths from ingest script
    local p_len=900 # 15 mins
    [[ "$time_mins" -eq 75 ]] && p_len=780 # 13 mins

    sqlite3 "$DB_FILE" <<EOF
INSERT INTO games (game_date, game_time_minutes, period1_length, period1_clock_type, 
                  period2_length, period2_clock_type, period3_length, period3_clock_type,
                  opponent_name, our_score, their_score)
VALUES ('$date', $time_mins, $p_len, 'stop', $p_len, 'stop', $p_len, 'stop', '$opponent', $our_score, $their_score);
SELECT 'Created game ID: ' || last_insert_rowid();
EOF
}

cmd_tag() {
    local gid="$1"; shift
    local tag_name="$1"; shift

    if [ -z "$gid" ] || [ -z "$tag_name" ]; then usage; fi

    sqlite3 "$DB_FILE" <<EOF
INSERT OR IGNORE INTO game_tags (tag_name) VALUES ('$tag_name');
INSERT OR IGNORE INTO game_tag_mapping (game_id, tag_id) 
SELECT $gid, tag_id FROM game_tags WHERE tag_name = '$tag_name';
EOF
    echo "Tagged game $gid with '$tag_name'."
}

cmd_roster() {
    local gid="$1"; shift
    if [ -z "$gid" ]; then usage; fi

    local copy_from_gid=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --copy-from) copy_from_gid="$2"; shift 2 ;;
            *) echo "Unknown option: $1"; usage ;;
        esac
    done

    # If no copy-from specified, find the previous game
    if [ -z "$copy_from_gid" ]; then
        copy_from_gid=$(sqlite3 "$DB_FILE" "SELECT MAX(game_id) FROM games WHERE game_id < $gid;")
    fi

    local TMP_ROSTER=".tmp_roster_edit.txt"

    # Initialize the file with headers
    cat > "$TMP_ROSTER" <<EOF
# Game Roster Editor
# Move players to the appropriate sections.
# Lines beginning with # are comments (except #Jersey).
# Do not change the Section Headers (e.g. [STARTER]).
EOF

    # Helper function to write players for a specific section
    write_section_players() {
        local section_header="$1"
        local sql_filter="$2"

        echo "" >> "$TMP_ROSTER"
        echo "$section_header" >> "$TMP_ROSTER"

        if [ -n "$copy_from_gid" ]; then
            sqlite3 -separator ' ' "$DB_FILE" "
                SELECT '#' || r.jersey_number, r.player_name, '(' || r.primary_position || ')' 
                FROM game_roster gr
                JOIN roster r ON gr.player_id = r.player_id
                WHERE gr.game_id = $copy_from_gid AND $sql_filter
                ORDER BY r.jersey_number;" >> "$TMP_ROSTER"
        fi
    }

    # Write sections based on previous game data
    write_section_players "[STARTER]" "gr.position = 'goalie' AND gr.code = 's'"
    write_section_players "[BACKUP]" "gr.position = 'goalie' AND gr.code = 'b'"
    write_section_players "[LINE 1]" "gr.position IN ('forward', 'center') AND gr.code = '1'"
    write_section_players "[LINE 2]" "gr.position IN ('forward', 'center') AND gr.code = '2'"
    write_section_players "[LINE 3]" "gr.position IN ('forward', 'center') AND gr.code = '3'"
    write_section_players "[LINE 4]" "gr.position IN ('forward', 'center') AND gr.code = '4'"
    write_section_players "[PAIR 1]" "gr.position = 'defense' AND gr.code = '1'"
    write_section_players "[PAIR 2]" "gr.position = 'defense' AND gr.code = '2'"
    write_section_players "[PAIR 3]" "gr.position = 'defense' AND gr.code = '3'"

    # Scratches: 
    # 1. Players explicitly scratched in source game
    # 2. Players in roster but NOT in source game_roster (new players)
    # 3. If no source game, ALL players go here
    echo "" >> "$TMP_ROSTER"
    echo "[SCRATCHES]" >> "$TMP_ROSTER"

    if [ -n "$copy_from_gid" ]; then
        # Explicit scratches from previous game
        sqlite3 -separator ' ' "$DB_FILE" "
            SELECT '#' || r.jersey_number, r.player_name, '(' || r.primary_position || ')' 
            FROM game_roster gr
            JOIN roster r ON gr.player_id = r.player_id
            WHERE gr.game_id = $copy_from_gid AND gr.position = 'scratch'
            ORDER BY r.jersey_number;" >> "$TMP_ROSTER"

        # Players missing from previous game roster (newly added to team)
        sqlite3 -separator ' ' "$DB_FILE" "
            SELECT '#' || r.jersey_number, r.player_name, '(' || r.primary_position || ')' 
            FROM roster r
            WHERE r.player_id NOT IN (SELECT player_id FROM game_roster WHERE game_id = $copy_from_gid)
            ORDER BY r.jersey_number;" >> "$TMP_ROSTER"
    else
        # No source game, dump everyone here
        sqlite3 -separator ' ' "$DB_FILE" "SELECT '#' || jersey_number, player_name, '(' || primary_position || ')' FROM roster ORDER BY jersey_number;" >> "$TMP_ROSTER"
    fi

    # Open editor
    ${EDITOR:-nano} "$TMP_ROSTER"

    # Parse and Generate SQL
    local current_section=""
    local sql_file=".tmp_roster_update.sql"
    echo "BEGIN TRANSACTION;" > "$sql_file"
    echo "DELETE FROM game_roster WHERE game_id = $gid;" >> "$sql_file"

    while read -r line; do
        # Skip empty lines and comments that don't look like players
        # Player line format: #88 Name (Pos)
        [[ -z "$line" ]] && continue
        if [[ "$line" == \[*\] ]]; then
            current_section="$line"
            continue
        fi

                # Check if line contains a player (starts with #)
                if [[ "$line" =~ ^#([0-9]+) ]]; then
                    local jersey="${BASH_REMATCH[1]}"
                    local pos="scratch"
                    local code="x"

                    # Fetch player info
                    local p_data=$(sqlite3 "$DB_FILE" "SELECT player_id, LOWER(primary_position) FROM roster WHERE jersey_number = $jersey;")
                    local pid=$(echo "$p_data" | cut -d'|' -f1)
                    local p_pos=$(echo "$p_data" | cut -d'|' -f2)

                    if [ -n "$pid" ]; then
                        # Determine Pos/Code based on section
                        case "$current_section" in
                            "[STARTER]")   pos="goalie"; code="s" ;;
                            "[BACKUP]")    pos="goalie"; code="b" ;;
                            "[LINE 1]"|"[LINE 2]"|"[LINE 3]"|"[LINE 4]")
                                code="${current_section:6:1}"
                                if [[ "$p_pos" == "center" ]]; then
                                    pos="center"
                                else
                                    pos="forward"
                                fi
                                ;;
                            "[PAIR 1]"|"[PAIR 2]"|"[PAIR 3]")
                                pos="defense"
                                code="${current_section:6:1}"
                                ;;
                            *)             pos="scratch"; code="x" ;;
                        esac

                        echo "INSERT INTO game_roster (game_id, player_id, position, code) VALUES ($gid, $pid, '$pos', '$code');" >> "$sql_file"
                    else
                        echo "Warning: Player #$jersey not found in DB."
                    fi
                fi
            done < "$TMP_ROSTER"
            echo "COMMIT;" >> "$sql_file"

    # Apply changes
    sqlite3 "$DB_FILE" < "$sql_file"

    # Cleanup
    rm "$TMP_ROSTER" "$sql_file"
    echo "Roster updated for Game $gid."
}

cmd_goal_for() {
    local gid="$1"; shift
    local period="$1"; shift
    local time_str="$1"; shift
    local scorer_j="$1"; shift
    local assists_js="${1:-}"; [[ "$assists_js" == --* ]] && assists_js="" || shift
    local type="even_strength"
    local empty_net=0
    local extra_js=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --type) type="$2"; shift 2 ;;
            --empty-net) empty_net=1; shift ;;
            --extra) extra_js="$2"; shift 2 ;;
            *) echo "Unknown option: $1"; usage ;;
        esac
    done

    local time_secs=$(time_to_seconds "$time_str")
    local scorer_id=$(get_player_id "$scorer_j")
    local a1_id="NULL"
    local a2_id="NULL"

    if [ -n "$assists_js" ]; then
        IFS=',' read -ra A_ARRAY <<< "$assists_js"
        [ -n "${A_ARRAY[0]}" ] && a1_id=$(get_player_id "${A_ARRAY[0]}")
        [ -n "${A_ARRAY[1]}" ] && a2_id=$(get_player_id "${A_ARRAY[1]}")
    fi

    local ex1_id="NULL"
    local ex2_id="NULL"
    local ex3_id="NULL"
    local ex4_id="NULL"

    if [ -n "$extra_js" ]; then
        IFS=',' read -ra E_ARRAY <<< "$extra_js"
        [ -n "${E_ARRAY[0]}" ] && ex1_id=$(get_player_id "${E_ARRAY[0]}")
        [ -n "${E_ARRAY[1]}" ] && ex2_id=$(get_player_id "${E_ARRAY[1]}")
        [ -n "${E_ARRAY[2]}" ] && ex3_id=$(get_player_id "${E_ARRAY[2]}")
        [ -n "${E_ARRAY[3]}" ] && ex4_id=$(get_player_id "${E_ARRAY[3]}")
    fi

    sqlite3 "$DB_FILE" <<EOF
INSERT INTO goals_for (game_id, period, time_seconds, scorer_id, assist1_id, assist2_id, extra_skater1_id, extra_skater2_id, extra_skater3_id, extra_skater4_id, goal_type, empty_net)
VALUES ($gid, $period, $time_secs, $scorer_id, $a1_id, $a2_id, $ex1_id, $ex2_id, $ex3_id, $ex4_id, '$type', $empty_net);
EOF
    echo "Goal injected for game $gid."
}

cmd_goal_against() {
    local gid="$1"; shift
    local period="$1"; shift
    local time_str="$1"; shift
    local on_ice_js="$1"; shift
    local type="even_strength"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --type) type="$2"; shift 2 ;;
            *) echo "Unknown option: $1"; usage ;;
        esac
    done

    local time_secs=$(time_to_seconds "$time_str")
    local oi_ids=("NULL" "NULL" "NULL" "NULL" "NULL" "NULL")

    IFS=',' read -ra OI_ARRAY <<< "$on_ice_js"
    for i in "${!OI_ARRAY[@]}"; do
        if [ $i -lt 6 ]; then
            oi_ids[$i]=$(get_player_id "${OI_ARRAY[$i]}")
        fi
    done

    sqlite3 "$DB_FILE" <<EOF
INSERT INTO goals_against (game_id, period, time_seconds, on_ice1_id, on_ice2_id, on_ice3_id, on_ice4_id, on_ice5_id, on_ice6_id, goal_type)
VALUES ($gid, $period, $time_secs, ${oi_ids[0]}, ${oi_ids[1]}, ${oi_ids[2]}, ${oi_ids[3]}, ${oi_ids[4]}, ${oi_ids[5]}, '$type');
EOF
    echo "Goal against injected for game $gid."
}

cmd_penalty() {
    local gid="$1"; shift
    local period="$1"; shift
    local time_str="$1"; shift
    local player_j="$1"; shift
    local type="$1"; shift
    local cat="$1"; shift
    local notes="${1:-}"

    local time_secs=$(time_to_seconds "$time_str")
    local player_id=$(get_player_id "$player_j")
    local type_id=$(get_penalty_type_id "$type" "$cat")

    sqlite3 "$DB_FILE" <<EOF
INSERT INTO penalties (game_id, period, time_seconds, player_id, penalty_type_id, notes)
VALUES ($gid, $period, $time_secs, $player_id, $type_id, '$notes');
EOF
    echo "Penalty injected for game $gid."
}

cmd_passing() {
    local gid="$1"; shift
    local period="$1"; shift
    local att="$1"; shift
    local comp="$1"; shift

    # Check if table exists, if not, create it (matching ingest script)
    sqlite3 "$DB_FILE" <<EOF
CREATE TABLE IF NOT EXISTS team_passing_stats (
    game_id INTEGER NOT NULL REFERENCES games(game_id),
    period INTEGER NOT NULL CHECK (period BETWEEN 1 AND 4),
    attempts INTEGER NOT NULL,
    completed INTEGER NOT NULL,
    PRIMARY KEY (game_id, period)
);
INSERT OR REPLACE INTO team_passing_stats (game_id, period, attempts, completed)
VALUES ($gid, $period, $att, $comp);
EOF
    echo "Passing stats injected for game $gid, period $period."
}

# Main
[ $# -lt 1 ] && usage

COMMAND="$1"; shift

case "$COMMAND" in
    game)         cmd_game "$@" ;;
    roster)       cmd_roster "$@" ;;
    tag)          cmd_tag "$@" ;;
    goal-for)     cmd_goal_for "$@" ;;
    goal-against) cmd_goal_against "$@" ;;
    penalty)      cmd_penalty "$@" ;;
    passing)      cmd_passing "$@" ;;
    *)            echo "Unknown command: $COMMAND"; usage ;;
esac
