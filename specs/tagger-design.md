================================================================================
                        MPV HOCKEY VIDEO TAGGER
                           Design Specification
================================================================================

Version: 1.1
Date: 2026-01-04
Status: Approved for Implementation

--------------------------------------------------------------------------------
1. OVERVIEW
--------------------------------------------------------------------------------

Purpose: MPV Lua plugin for tagging hockey game videos with structured event
         data based on user keystrokes during playback.

Output:  Tagged event logs suitable for database ingestion by ETL pipelines.

Scope:   Single-user personal tool, potentially shared with small group.

--------------------------------------------------------------------------------
2. CONFIGURATION
--------------------------------------------------------------------------------

Location: Set via TAGGER_CONF environment variable

Format:   JSON

Configuration Parameters:
  - leader_key : Key that triggers tag mode (default: ctrl+t)
  - player_map : JSON object mapping jersey numbers to names

Sample Configuration:
--------------------------------------------------------------------------------
{
  "leader_key": "ctrl+t",
  "player_map": {
    "4": "Viktor LO",
    "5": "Mike Green",
    "7": "Darnell Nurse",
    "8": "Adam Henrique",
    "9": "Jack Campbell",
    "10": "Ryan Nugent-Hopkins",
    "11": "Leon Draisaitl",
    "12": "Corey Perry",
    "13": "Matt Coronato",
    "14": "Sam Carrick",
    "15": "Zach Hyman",
    "16": "Kasperi Kapanen",
    "17": "Jeff Petry",
    "18": "Lane Pederson",
    "19": "Mattias Janmark",
    "20": "Connor Brown",
    "21": "Brandon Tanev",
    "22": "Tyler Benson",
    "23": "Brett Kulak",
    "24": "Philip Broberg",
    "25": "Stuart Skinner",
    "26": "Evander Kane",
    "27": "Brett Connolly",
    "28": "Dylan Holloway",
    "29": "Vincent Desharnais",
    "44": "Cody Ceci",
    "55": "Mark Giordano",
    "61": "Carter Savoie",
    "62": "Brad Malone",
    "71": "Ryan McLeod",
    "77": "Klim Kostin",
    "81": "Philipp Kurashev",
    "88": "Andrei Sviatoshinskiy",
    "91": "Connor McDavid",
    "92": "Warren Foegele",
    "93": "Noah Hanifin"
  }
}
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
3. LOG FILE FORMAT
--------------------------------------------------------------------------------

Location: Same directory as the video file being watched

Filename: {video_filename}_tags_{session_start_timestamp}.log
Example:  "edm_v_nyj_tags_1697324567.log"

Line Format:
  {timestamp_seconds}|{tag_type}|field1|field2|...

Note: Fields are formatted as key:value pairs within the tag type section

Timestamp: Seconds since beginning of video (with decimal precision)

--------------------------------------------------------------------------------
3.1 TAG TYPE DEFINITIONS

TAG: goal
Fields: score:{scorer}|assists:{p1,p2}
Notes:
  - Total players on ice: 3 to 6 (calculated from current roster)
  - scorer: exactly 1 player
  - assists: 0 to 2 players (comma-separated)
  - "other" players are extrapolated from start/change logs
Example Lines:
  1234.5|goal|score:27|assists:19,14
  2345.0|goal|score:91
  3456.7|goal|score:11|assists:23,44

TAG: penalty
Fields: player:{number}|category:{minor|major|match|misconduct|game_misconduct}|type:{penalty_type}
Notes:
  - Category determines length: minor=2min, major=5min, match=5min, misconduct=10min, game_misconduct=10min
  - Type: auto-complete from common penalty types
Example Lines:
  4567.1|penalty|player:44|category:minor|type:hooking
  5678.9|penalty|player:27|category:major|type:fighting

TAG: shot
Fields: player:{number}|outcome:{missed|saved|blocked}|zone:{1-8}
Notes:
  - Zone: 1=outside_north_east, 2=outside_north_west, 3=east_outer_slot, 4=west_outer_slot, 5=inner_slot, 6=center_point, 7=east_point, 8=west_point
Example Lines:
  6789.0|shot|player:8|outcome:missed|zone:5
  7890.1|shot|player:29|outcome:saved|zone:6
  8901.2|shot|player:19|outcome:blocked|zone:3

TAG: block
Fields: player:{number}|zone:{1-8}
Notes:
  - Zone: 1=outside_north_east, 2=outside_north_west, 3=east_outer_slot, 4=west_outer_slot, 5=inner_slot, 6=center_point, 7=east_point, 8=west_point
Example Lines:
  9012.3|block|player:22|zone:5
  10123.4|block|player:18|zone:3

TAG: change
Fields: out:{number}|incoming:{number}
Example Lines:
  10123.4|change|out:18|incoming:29

TAG: pass
Fields: from:{number}|to:{number}|success:{success|off-target|missed}|zone:{defensive|offensive|neutral}
Example Lines:
  11234.5|pass|from:11|to:19|success:success|zone:offensive
  12345.6|pass|from:97|to:12|success:off-target|zone:neutral
  13456.7|pass|from:7|to:91|success:missed|zone:defensive

TAG: takeaway
Fields: player:{number}|zone:{defensive|offensive|neutral}
Example Lines:
  14567.8|takeaway|player:7|zone:defensive
  15678.9|takeaway|player:27|zone:offensive

TAG: giveaway
Fields: player:{number}|zone:{defensive|offensive|neutral}
Example Lines:
  15678.9|giveaway|player:27|zone:defensive
  16789.0|giveaway|player:91|zone:neutral

TAG: save
Fields: (none - assumes current goalie)
Example Lines:
  16789.0|save

TAG: start
Fields: period:{1|2|3|OT}|length:{mm:ss}|goalie:{number}|defense:{d1,d2}|forwards:{f1,f2,f3}
Notes:
  - Period: 1, 2, 3, or OT (overtime)
  - Length: period length in mm:ss format (e.g., 20:00, 3:45)
  - defense: 1 to 2 defensemen (comma-separated)
  - forwards: 1 to 3 forwards (comma-separated)
Example Lines:
  0.0|start|period:1|length:20:00|goalie:25|defense:4,5|forwards:10,11,19
  1200.0|start|period:2|length:3:45|goalie:25|defense:4|forwards:10,11

TAG: whistle
Fields: reason:{optional description}
Notes:
  - reason: Optional text describing the stoppage reason
Example Lines:
  10.5|whistle
  120.0|whistle|reason:offside
  234.5|whistle|reason:icing

TAG: faceoff
Fields: player:{number}|win:{y|n}
Example Lines:
  20000.0|faceoff|player:11|win:y
  20005.5|faceoff|player:29|win:n

TAG: against
Fields: zone:{1-8}|note:{optional description}
Notes:
  - Zone: 1=outside_north_east, 2=outside_north_west, 3=east_outer_slot, 4=west_outer_slot, 5=inner_slot, 6=center_point, 7=east_point, 8=west_point
  - Players on ice are automatically derived from current roster state
Example Lines:
  30000.0|against|zone:5
  30005.5|against|zone:6|note:bad change

--------------------------------------------------------------------------------
4. IMPLEMENTATION ARCHITECTURE
--------------------------------------------------------------------------------

Uses MPV's mp.input API for all user input, eliminating manual key handling.

Flow:
  leader_key → mp.input (tag type) → chain mp.input calls for fields → log

mp.input features utilized:
  - completion: Function-based auto-complete for all fields
  - submit callback: Validation and logging on Enter
  - ESC handling: Built-in cancellation (resumes video)

--------------------------------------------------------------------------------
5. DATA ENTRY FLOWS
--------------------------------------------------------------------------------

5.1 GOAL TAG
   1. Enter "goal" (auto-complete available)
   2. Enter jersey number of goal scorer
   3. Enter jersey number of 1st assist (Enter to skip)
   4. Enter jersey number of 2nd assist (Enter to skip)
   5. Enter on empty line to finish
   Validation: Maximum 2 assists allowed
   Note: "other" players are automatically calculated from current roster state

5.2 PENALTY TAG
   1. Enter "penalty" (auto-complete available)
   2. Enter jersey number of penalized player
   3. Enter penalty category (minor, major, match, misconduct, game_misconduct)
   4. Enter penalty type (auto-complete from common types)
   Note: Length is automatically derived from category

5.3 SHOT TAG
   1. Enter "shot" (auto-complete available)
   2. Enter jersey number of shooter
   3. Enter outcome: missed, saved, or blocked
   4. Enter zone: 1-8 (auto-complete available)

5.4 BLOCK TAG
   1. Enter "block" (auto-complete available)
   2. Enter jersey number of blocker
   3. Enter zone: 1-8 (auto-complete available)

5.5 CHANGE TAG
  1. Enter "change" (auto-complete available)
  2. Enter jersey number of player leaving ice
  3. Enter jersey number of player entering ice

5.6 PASS TAG
   1. Enter "pass" (auto-complete available)
   2. Enter jersey number of passer
   3. Enter jersey number of target receiver
   4. Enter outcome: success, off-target, or missed
   5. Enter zone: defensive, offensive, or neutral (auto-complete)

5.7 TAKEAWAY TAG
   1. Enter "takeaway" (auto-complete available)
   2. Enter jersey number of player who took the puck
   3. Enter zone: defensive, offensive, or neutral (auto-complete)

5.8 GIVEAWAY TAG
   1. Enter "giveaway" (auto-complete available)
   2. Enter jersey number of player who lost the puck
   3. Enter zone: defensive, offensive, or neutral (auto-complete)

5.9 SAVE TAG
   1. Enter "save" (auto-complete available)

5.10 START TAG
  1. Enter "start" (auto-complete available)
  2. Enter jersey number of goaltender
  3. Enter jersey numbers of skaters on ice (Enter after each)
  4. Enter on empty line to finish
  Validation: 3-5 skaters required

5.11 WHISTLE TAG
  1. Enter "whistle" (auto-complete available)
  2. No additional fields - submits immediately

5.12 FACEOFF TAG
   1. Enter "faceoff" (auto-complete available)
   2. Enter jersey number of player taking faceoff
   3. Enter outcome: y/n

5.13 AGAINST TAG
   1. Enter "against" (auto-complete available)
   2. Enter zone: 1-8 (auto-complete available)
   3. Enter note (optional, Enter to skip)

--------------------------------------------------------------------------------
6. AUTO-COMPLETE BEHAVIOR
--------------------------------------------------------------------------------

6.1 TAG TYPE AUTO-COMPLETE
  - Filters from predefined tag types list
  - User types, list filters in real-time

6.2 PLAYER NUMBER AUTO-COMPLETE
  - Filters from player_map keys (jersey numbers)
  - Validates against configured player_map

6.3 PENALTY TYPE AUTO-COMPLETE
   - Filters from common penalty types list:
     hooking, holding, tripping, interference, slashing,
     high-sticking, cross-checking, fighting, delay of game,
     too many men, roughing, boarding, charging, elbowing,
     kneeing, butt-ending, spearing, throwing equipment

6.4 PENALTY CATEGORY AUTO-COMPLETE
   - Filters from category list: minor, major, match, misconduct, game_misconduct

6.5 ZONE AUTO-COMPLETE (SHOT/BLOCK)
   - Filters from numeric zones 1-8

6.6 ZONE AUTO-COMPLETE (PASS/TAKEAWAY/GIVEAWAY)
   - Filters from text zones: defensive, offensive, neutral

--------------------------------------------------------------------------------
7. OSD MESSAGES
--------------------------------------------------------------------------------

Uses mp.osd_message for status updates:

  - ">> TAG MODE <<" when entering tag mode
  - Formatted summary after successful tag (5 second display)
  - "ERROR: {message}" on validation failure

7.1 TAG SUMMARY FORMATS

   Goal:      "GOAL: #27 J. Thompson (A: #19 Ri. Breckterfield, #8 C. Poon)"
   Penalty:   "PENALTY: #97 Ro. Breckterfield - 2 min hooking (minor)"
   Shot:      "SHOT: #8 C. Poon - missed (zone 5)"
   Block:     "BLOCK: #24 R. Latham (zone 3)"
   Change:    "OUT: #18 L. Bacon  |  IN: #22 V. Han"
   Pass:      "PASS: #11 L. Draisaitl -> #97 Ro. Breckterfield (success, neutral)"
   Takeaway:  "TAKEAWAY: #7 K. Garver (offensive)"
   Giveaway:  "GIVEAWAY: #91 R. Nugent-Hopkins (defensive)"
   Save:      "SAVE"
   Whistle:   "WHISTLE: Stoppage" or "WHISTLE: Stoppage - offside"
   Faceoff:   "FACEOFF: #97 Ro. Breckterfield WON"
   Against:   "AGAINST (zone 5)" or "AGAINST (zone 6) - bad change"

7.2 CURRENT ROSTER DISPLAY

   Automatically shown when entering tag mode (along with ">> TAG MODE <<").
   Displayed along the bottom of the screen in large font.

   Format:
   G: #25 GoalieName | D: #4 Name1, #5 Name2 | F: #10 Name3, #11 Name4, #91 Name5

   Example:
   G: #25 Stuart Skinner | D: #4 Viktor LO, #5 Mike Green | F: #10 RN-H, #11 Draisaitl, #91 McDavid

   Notes:
   - Updates automatically after each "change" tag
   - Only shows jersey numbers if player not in player_map
   - Uses short format for names (FirstInitial. LastName)

Player names are formatted as "#<number> <FirstInitial>. <LastName>" when resolved from jersey numbers using player_map.

--------------------------------------------------------------------------------
8. KEY BINDINGS
--------------------------------------------------------------------------------

leader_key  : Enter tag mode (pause video, show input dialog)

ESC (in input): Cancel tagging, resume video
Enter (in input): Submit field value, advance or log

--------------------------------------------------------------------------------
9. LOG FILE OUTPUT
--------------------------------------------------------------------------------

On first tag of session:
  - Determine video file path
  - Extract filename without extension
  - Generate timestamp (seconds since epoch)
  - Create log file: {videoname}_tags_{timestamp}.log
  - Store file handle for duration of session

Each tag logged:
  - Format line according to tag type specification
  - Append to log file
  - Flush to ensure data is written

Session ends:
  - File handle closed automatically when plugin unloaded
  - User can stop MPV player to end session

--------------------------------------------------------------------------------
10. CODE ARCHITECTURE
--------------------------------------------------------------------------------

10.1 FILE STRUCTURE
  - tagger.lua: Main plugin file containing all logic
  - tagger.conf: Sample configuration file

10.2 MODULES
  - Configuration: load_config() parses TAGGER_CONF file
  - Tag Definitions: tag_definitions table with fields and validation
  - Formatters: formatters table for each tag type output
  - Validators: validators table for special validation rules
  - Completion: Generic complete_from_list() + specialized completers
  - Tag Entry: do_next_field() manages field progression

10.3 DEPENDENCIES
  - MPV 0.35+ with Lua scripting support
  - Standard Lua libraries only
  - Uses mp.input API for all input handling

10.4 ERROR HANDLING
  - Invalid player numbers rejected at input
  - Incomplete tag data rejected at validation
  - File I/O errors logged to console
  - Input cancel via ESC handled gracefully

10.5 PERFORMANCE
  - Minimal overhead during normal playback
  - OSD messages only during tag mode
  - Log file flushed after each write

--------------------------------------------------------------------------------
11. FUTURE CONSIDERATIONS (OUT OF SCOPE FOR V1)
--------------------------------------------------------------------------------

  - Tag review UI with individual tag removal
  - Tag editing/modification
  - Multiple tag sessions per video
  - Export to different formats
  - Integration with external databases
  - Team-based player configuration
  - Video position markers in log

================================================================================
                              END OF SPEC
================================================================================
