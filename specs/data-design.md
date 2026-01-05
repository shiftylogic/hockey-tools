# Hockey Stats Database Design Specification

## Overview

SQLite database schema for storing amateur hockey game statistics for a single team (coach use case). Each season is a separate database instance.

---

## Core Tables

### games

Stores game metadata and configuration.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| game_id | INTEGER | PRIMARY KEY | Surrogate key |
| game_date | TEXT | NOT NULL | ISO 8601 date (YYYY-MM-DD) |
| game_time_minutes | INTEGER | NOT NULL | Time slot duration: 60, 75, 90, 105, or 120 |
| period1_length | INTEGER | NOT NULL | Duration in seconds |
| period1_clock_type | TEXT | NOT NULL CHECK('stop' IN ('stop', 'run')) | 'stop' or 'run' |
| period2_length | INTEGER | NOT NULL | Duration in seconds |
| period2_clock_type | TEXT | NOT NULL CHECK('stop' IN ('stop', 'run')) | 'stop' or 'run' |
| period3_length | INTEGER | NOT NULL | Duration in seconds |
| period3_clock_type | TEXT | NOT NULL CHECK('stop' IN ('stop', 'run')) | 'stop' or 'run' |
| period4_length | INTEGER | NULL | Overtime duration in seconds |
| period4_clock_type | TEXT | NULL CHECK('stop' IN ('stop', 'run')) | 'stop' or 'run' (OT/SO) |
| has_shootout | INTEGER | NOT NULL DEFAULT 0 | Boolean (0=false, 1=true) |
| our_score | INTEGER | NOT NULL DEFAULT 0 | Final score for our team |
| their_score | INTEGER | NOT NULL DEFAULT 0 | Final score for opponent |
| opponent_name | TEXT | NULL | Opponent team name (optional) |

### game_tags

Lookup table for game categorization tags.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| tag_id | INTEGER | PRIMARY KEY | Surrogate key |
| tag_name | TEXT | NOT NULL UNIQUE | Tag value: PNAHA, league, tournament, exhibition, Canada, tiering, scrimmage |

**Initial Values**: PNAHA, league, tournament, exhibition, Canada, tiering, scrimmage

### game_tag_mapping

Many-to-many relationship between games and tags.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| game_id | INTEGER | NOT NULL REFERENCES games(game_id) | |
| tag_id | INTEGER | NOT NULL REFERENCES game_tags(tag_id) | |
| PRIMARY KEY | | (game_id, tag_id) | Composite key |

### roster

Team roster information.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| player_id | INTEGER | PRIMARY KEY | Surrogate key |
| jersey_number | INTEGER | NOT NULL UNIQUE | Player number |
| player_name | TEXT | NOT NULL | Full name |
| primary_position | TEXT | NOT NULL CHECK('Forward' IN ('Forward', 'Defense', 'Goalie')) | Primary role |
| secondary_positions | TEXT | NULL | Comma-separated (e.g., "Forward,Defense") |
| birth_year | INTEGER | NOT NULL | 4-digit year |
| handedness | TEXT | NOT NULL CHECK('left' IN ('left', 'right')) | Shooting hand |

### penalty_types

Lookup table for penalty classifications.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| penalty_type_id | INTEGER | PRIMARY KEY | Surrogate key |
| penalty_name | TEXT | NOT NULL | Penalty name (hooking, tripping, slashing, etc.) |
| penalty_category | TEXT | NOT NULL CHECK IN ('minor', 'major', 'misconduct', 'game_misconduct', 'match') | Penalty severity classification |
| penalty_length | INTEGER | NOT NULL | Duration in minutes (derived from category) |

---

## Stat Tables

### goals_for

Goals scored by our team.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| goal_id | INTEGER | PRIMARY KEY | Surrogate key |
| game_id | INTEGER | NOT NULL REFERENCES games(game_id) | |
| period | INTEGER | NOT NULL CHECK(period BETWEEN 1 AND 4) | 1-3 = regulation, 4 = OT/SO |
| time_seconds | INTEGER | NOT NULL | Seconds elapsed in period (0 to period_length-1) |
| scorer_id | INTEGER | NOT NULL REFERENCES roster(player_id) | Goal scorer |
| assist1_id | INTEGER | NULL REFERENCES roster(player_id) | First assist (nullable) |
| assist2_id | INTEGER | NULL REFERENCES roster(player_id) | Second assist (nullable) |
| extra_skater1_id | INTEGER | NULL REFERENCES roster(player_id) | Extra attacker on ice |
| extra_skater2_id | INTEGER | NULL REFERENCES roster(player_id) | Extra attacker on ice |
| extra_skater3_id | INTEGER | NULL REFERENCES roster(player_id) | Extra attacker on ice |
| extra_skater4_id | INTEGER | NULL REFERENCES roster(player_id) | Extra attacker on ice |
| goal_type | TEXT | NOT NULL CHECK IN ('power_play', 'shorthanded', 'even_strength', 'shootout', 'penalty_shot') | |
| empty_net | INTEGER | NOT NULL DEFAULT 0 | Boolean (0=false, 1=true) |

### goals_against

Goals scored by opponents.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| goal_id | INTEGER | PRIMARY KEY | Surrogate key |
| game_id | INTEGER | NOT NULL REFERENCES games(game_id) | |
| period | INTEGER | NOT NULL CHECK(period BETWEEN 1 AND 4) | 1-3 = regulation, 4 = OT/SO |
| time_seconds | INTEGER | NOT NULL | Seconds elapsed in period |
| on_ice1_id | INTEGER | NULL REFERENCES roster(player_id) | Skater on ice |
| on_ice2_id | INTEGER | NULL REFERENCES roster(player_id) | Skater on ice |
| on_ice3_id | INTEGER | NULL REFERENCES roster(player_id) | Skater on ice |
| on_ice4_id | INTEGER | NULL REFERENCES roster(player_id) | Skater on ice |
| on_ice5_id | INTEGER | NULL REFERENCES roster(player_id) | Skater on ice |
| on_ice6_id | INTEGER | NULL REFERENCES roster(player_id) | Skater on ice |
| goal_type | TEXT | NOT NULL CHECK IN ('power_play', 'shorthanded', 'even_strength', 'shootout', 'penalty_shot') | |

### penalties

Penalty infractions.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| penalty_id | INTEGER | PRIMARY KEY | Surrogate key |
| game_id | INTEGER | NOT NULL REFERENCES games(game_id) | |
| period | INTEGER | NOT NULL CHECK(period BETWEEN 1 AND 4) | |
| time_seconds | INTEGER | NOT NULL | Seconds elapsed in period |
| player_id | INTEGER | NOT NULL REFERENCES roster(player_id) | Penalized player |
| penalty_type_id | INTEGER | NOT NULL REFERENCES penalty_types(penalty_type_id) | |
| served_by_id | INTEGER | NULL REFERENCES roster(player_id) | Alternative serving player |
| notes | TEXT | NULL | Optional coach notes |

### shots

Shot attempts by our players.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| shot_id | INTEGER | PRIMARY KEY | Surrogate key |
| game_id | INTEGER | NOT NULL REFERENCES games(game_id) | |
| period | INTEGER | NOT NULL CHECK(period BETWEEN 1 AND 4) | |
| time_seconds | INTEGER | NOT NULL | Seconds elapsed in period |
| player_id | INTEGER | NOT NULL REFERENCES roster(player_id) | Shooter |
| result | TEXT | NOT NULL CHECK IN ('missed', 'saved', 'blocked', 'scored') | |
| origin_zone | INTEGER | NOT NULL CHECK(origin_zone BETWEEN 1 AND 8) | See Zone Mappings |

### passes

Pass attempts by our players.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| pass_id | INTEGER | PRIMARY KEY | Surrogate key |
| game_id | INTEGER | NOT NULL REFERENCES games(game_id) | |
| period | INTEGER | NOT NULL CHECK(period BETWEEN 1 AND 4) | |
| time_seconds | INTEGER | NOT NULL | Seconds elapsed in period |
| player_id | INTEGER | NOT NULL REFERENCES roster(player_id) | Passer |
| target_player_id | INTEGER | NOT NULL REFERENCES roster(player_id) | Intended recipient |
| result | TEXT | NOT NULL CHECK IN ('good', 'off_target', 'missed', 'intercepted') | |
| origin_zone | TEXT | NOT NULL CHECK IN ('defensive', 'offensive', 'neutral') | See Zone Mappings |

### blocks

Blocked shots by our players.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| block_id | INTEGER | PRIMARY KEY | Surrogate key |
| game_id | INTEGER | NOT NULL REFERENCES games(game_id) | |
| period | INTEGER | NOT NULL CHECK(period BETWEEN 1 AND 4) | |
| time_seconds | INTEGER | NOT NULL | Seconds elapsed in period |
| player_id | INTEGER | NOT NULL REFERENCES roster(player_id) | Blocking player |
| origin_zone | INTEGER | NOT NULL CHECK(origin_zone BETWEEN 1 AND 8) | See Zone Mappings |

### takeaways

Puck recoveries by our players.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| takeaway_id | INTEGER | PRIMARY KEY | Surrogate key |
| game_id | INTEGER | NOT NULL REFERENCES games(game_id) | |
| period | INTEGER | NOT NULL CHECK(period BETWEEN 1 AND 4) | |
| time_seconds | INTEGER | NOT NULL | Seconds elapsed in period |
| player_id | INTEGER | NOT NULL REFERENCES roster(player_id) | Player who gained possession |
| origin_zone | TEXT | NOT NULL CHECK IN ('defensive', 'offensive', 'neutral') | See Zone Mappings |

### giveaways

Puck giveaways by our players.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| giveaway_id | INTEGER | PRIMARY KEY | Surrogate key |
| game_id | INTEGER | NOT NULL REFERENCES games(game_id) | |
| period | INTEGER | NOT NULL CHECK(period BETWEEN 1 AND 4) | |
| time_seconds | INTEGER | NOT NULL | Seconds elapsed in period |
| player_id | INTEGER | NOT NULL REFERENCES roster(player_id) | Player who lost possession |
| origin_zone | TEXT | NOT NULL CHECK IN ('defensive', 'offensive', 'neutral') | See Zone Mappings |

### player_changes

Line changes during stoppages.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| change_id | INTEGER | PRIMARY KEY | Surrogate key |
| game_id | INTEGER | NOT NULL REFERENCES games(game_id) | |
| period | INTEGER | NOT NULL CHECK(period BETWEEN 1 AND 4) | |
| time_seconds | INTEGER | NOT NULL | Seconds elapsed in period |
| incoming_id | INTEGER | NOT NULL REFERENCES roster(player_id) | Player entering ice |
| outgoing_id | INTEGER | NOT NULL REFERENCES roster(player_id) | Player leaving ice |

### saves

Goalie saves.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| save_id | INTEGER | PRIMARY KEY | Surrogate key |
| game_id | INTEGER | NOT NULL REFERENCES games(game_id) | |
| period | INTEGER | NOT NULL CHECK(period BETWEEN 1 AND 4) | |
| time_seconds | INTEGER | NOT NULL | Seconds elapsed in period |
| goalie_id | INTEGER | NOT NULL REFERENCES roster(player_id) | Goaltender |

### faceoffs

Faceoff results.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| faceoff_id | INTEGER | PRIMARY KEY | Surrogate key |
| game_id | INTEGER | NOT NULL REFERENCES games(game_id) | |
| period | INTEGER | NOT NULL CHECK(period BETWEEN 1 AND 4) | |
| time_seconds | INTEGER | NOT NULL | Seconds elapsed in period |
| player_id | INTEGER | NOT NULL REFERENCES roster(player_id) | Our player taking faceoff |
| win_loss | TEXT | NOT NULL CHECK IN ('win', 'loss') | Result |
| extra1_id | INTEGER | NULL REFERENCES roster(player_id) | Extra skater on ice |
| extra2_id | INTEGER | NULL REFERENCES roster(player_id) | Extra skater on ice |
| extra3_id | INTEGER | NULL REFERENCES roster(player_id) | Extra skater on ice |
| extra4_id | INTEGER | NULL REFERENCES roster(player_id) | Extra skater on ice |
| extra5_id | INTEGER | NULL REFERENCES roster(player_id) | Extra skater on ice |

---

## Zone Mappings

### Shots and Blocks (Numeric, 1-8)

```
-------+-------
11111 555 22222
1111 55555 2222
111 3 555 4 222
111 33 5 44 222
111 333 444 222
777 6666666 888
7777 66666 8888
---------------
```

| Value | Name |
|-------|------|
| 1 | outside_north_east |
| 2 | outside_north_west |
| 3 | east_outer_slot |
| 4 | west_outer_slot |
| 5 | inner_slot |
| 6 | center_point |
| 7 | east_point |
| 8 | west_point |

### Passes, Takeaways, Giveaways (Text)

| Value | Description |
|-------|-------------|
| defensive | Defensive zone |
| offensive | Offensive zone |
| neutral | Neutral zone |

---

## Indexes

### For Points Queries (Goals + Assists)
```sql
CREATE INDEX idx_goals_for_scorer ON goals_for(scorer_id);
CREATE INDEX idx_goals_for_assist1 ON goals_for(assist1_id);
CREATE INDEX idx_goals_for_assist2 ON goals_for(assist2_id);
CREATE INDEX idx_goals_for_game ON goals_for(game_id);
```

### For Plus/Minus Queries
```sql
CREATE INDEX idx_gf_extra_skater ON goals_for(extra_skater1_id, extra_skater2_id, extra_skater3_id, extra_skater4_id);
CREATE INDEX idx_ga_on_ice ON goals_against(on_ice1_id, on_ice2_id, on_ice3_id, on_ice4_id, on_ice5_id, on_ice6_id);
```

### For Per-Game Stats
```sql
CREATE INDEX idx_shots_player_game ON shots(player_id, game_id);
CREATE INDEX idx_penalties_player_game ON penalties(player_id, game_id);
CREATE INDEX idx_faceoffs_player_game ON faceoffs(player_id, game_id);
```

### General FK Indexes (automatic benefit)
All FK columns are indexed implicitly for JOIN performance.

---

## Seed Data

### penalty_types
| penalty_name | penalty_category | penalty_length |
|--------------|------------------|----------------|
| slashing | minor | 2 |
| slashing | major | 5 |
| tripping | minor | 2 |
| tripping | major | 5 |
| hooking | minor | 2 |
| hooking | major | 5 |
| interference | minor | 2 |
| interference | major | 5 |
| holding | minor | 2 |
| holding | major | 5 |
| high_stick | minor | 2 |
| high_stick | major | 5 |
| cross_check | minor | 2 |
| cross_check | major | 5 |
| charging | minor | 2 |
| charging | major | 5 |
| roughing | minor | 2 |
| roughing | major | 5 |
| delay_of_game | minor | 2 |
| too_many_men | minor | 2 |
| bench_minor | minor | 2 |
| checking_from_behind | major | 5 |
| checking_to_head | major | 5 |
| fighting | major | 5 |
| butt_ending | major | 5 |
| hair_pulling | major | 5 |
| kicking | major | 5 |
| kneeing | major | 5 |
| spearing | major | 5 |
| misconduct | misconduct | 10 |
| game_misconduct | game_misconduct | 10 |
| match | match | 5 |

### game_tags
| tag_name |
|----------|
| PNAHA |
| league |
| tournament |
| exhibition |
| Canada |
| tiering |
| scrimmage |

---

## Notes

1. **Time Storage**: All times stored as INTEGER seconds from period start. Display formatting (MM:SS) handled at UI layer.

2. **Period 4 Handling**: Period 4 is reserved for overtime and shootout. If no overtime, period4_length and period4_clock_type are NULL.

3. **Clock Types**: 'stop' clock stops for whistles; 'run' clock runs continuously (real time).

4. **Boolean Storage**: SQLite has no native BOOLEAN. Use INTEGER with 0/1 values.

5. **Season Isolation**: Each season is a separate database file. No season_id column needed.

6. **FK Behavior**: SQLite enforces foreign keys only when PRAGMA foreign_keys = ON is set.

---

## Example Queries

### Total Points by Player (All Games)
```sql
SELECT
    r.player_name,
    r.jersey_number,
    COUNT(gf.goal_id) AS goals,
    COUNT(gf.assist1_id) + COUNT(gf.assist2_id) AS assists,
    COUNT(gf.goal_id) + COUNT(gf.assist1_id) + COUNT(gf.assist2_id) AS points
FROM roster r
LEFT JOIN goals_for gf ON r.player_id = gf.scorer_id
    OR r.player_id = gf.assist1_id
    OR r.player_id = gf.assist2_id
GROUP BY r.player_id
ORDER BY points DESC;
```

### Plus/Minus by Player
```sql
SELECT
    r.player_name,
    r.jersey_number,
    (SELECT COUNT(*) FROM goals_for gf
     WHERE (gf.extra_skater1_id = r.player_id OR gf.extra_skater2_id = r.player_id
         OR gf.extra_skater3_id = r.player_id OR gf.extra_skater4_id = r.player_id))
        AS plus,
    (SELECT COUNT(*) FROM goals_against ga
     WHERE (ga.on_ice1_id = r.player_id OR ga.on_ice2_id = r.player_id
         OR ga.on_ice3_id = r.player_id OR ga.on_ice4_id = r.player_id
         OR ga.on_ice5_id = r.player_id OR ga.on_ice6_id = r.player_id))
        AS minus,
    plus - minus AS plus_minus
FROM roster r;
```

### Shots by Zone (for a specific game)
```sql
SELECT
    CASE origin_zone
        WHEN 1 THEN 'outside_north_east'
        WHEN 2 THEN 'outside_north_west'
        WHEN 3 THEN 'east_outer_slot'
        WHEN 4 THEN 'west_outer_slot'
        WHEN 5 THEN 'inner_slot'
        WHEN 6 THEN 'center_point'
        WHEN 7 THEN 'east_point'
        WHEN 8 THEN 'west_point'
    END AS zone_name,
    COUNT(*) AS shot_count
FROM shots
WHERE game_id = ?
GROUP BY origin_zone;
```

### Penalties by Category (for a specific player)
```sql
SELECT
    pt.penalty_name,
    pt.penalty_category,
    pt.penalty_length,
    p.period,
    p.time_seconds
FROM penalties p
JOIN penalty_types pt ON p.penalty_type_id = pt.penalty_type_id
WHERE p.player_id = ?
ORDER BY p.game_id, p.period, p.time_seconds;
```

### Penalty Minutes by Category by Player
```sql
SELECT
    r.player_name,
    r.jersey_number,
    pt.penalty_category,
    COUNT(*) AS penalty_count,
    SUM(pt.penalty_length) AS penalty_minutes
FROM penalties p
JOIN roster r ON p.player_id = r.player_id
JOIN penalty_types pt ON p.penalty_type_id = pt.penalty_type_id
GROUP BY r.player_id, pt.penalty_category
ORDER BY penalty_minutes DESC;
```

---

*End of specification*
