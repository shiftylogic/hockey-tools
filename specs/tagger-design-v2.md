# Design Spec: Hockey Tagger Workbench (v2.0)

## 1. Overview
The **Hockey Tagger Workbench** is a professional-grade "sidecar" application designed to run alongside the MPV video player. It replaces the modal, blocking interface of the original Lua plugin with a non-blocking, multi-pane Terminal User Interface (TUI).

## 2. Architecture
- **Controller (Python/Textual):** The primary application that manages state, user input, and the TUI.
- **Engine (MPV):** A slave process launched by the Controller, controlled via the JSON-IPC protocol.
- **Data Layer:** 
    - **Configuration:** JSON-based player rosters and event definitions.
    - **Output:** Structured JSON logs (primary) and flat text logs (legacy/export).

## 3. UI Layout (The "Mission Control" TUI)
The interface is divided into four primary functional zones:

### 3.1 Timeline Pane (Left)
- **Live Feed:** A scrollable list of all events tagged in the current session.
- **Selection Sync:** Highlighting an event sends a `seek` command to MPV to jump to `Timestamp - 5s`.
- **Visual Cues:** Color-coded labels (e.g., Green for Goals, Red for Penalties).

### 3.2 Input Form Pane (Center)
- **Stateful Form:** A dynamic data-entry area that changes based on the active event type.
- **Fields:** Input widgets for Jersey Numbers, Enums (Outcome/Length), and Multi-selects (Assists).
- **Validation:** Real-time feedback on player existence and field requirements.
- **Drafting:** Tags are held in a "Draft" state until explicitly committed.

### 3.3 Roster Pane (Right)
- **Persistent View:** Shows the full jersey-to-name mapping for both teams.
- **Live Highlight:** Typing a jersey number in the Input Form highlights the corresponding player in the roster.

### 3.4 Command Bar (Bottom)
- **Status Indicator:** Shows IPC connection health, current log file path, and MPV playback state.
- **Hotkey Guide:** Dynamic legend for current mode (e.g., `[Space] Play/Pause`, `[Esc] Cancel Tag`).

## 4. Operational Workflows

### 4.1 Event Logging
1. **Trigger:** User hits a hotkey (e.g., `g` for Goal).
2. **Capture:** System captures the exact `time-pos` from MPV.
3. **Entry:** Form focuses the first field (e.g., "Scorer"). User types jersey numbers.
4. **Commit:** User hits `Ctrl+S` or `Enter` on the last field to log the event.
5. **Post-Commit:** Video resumes (if auto-paused) and focus returns to the playback controller.

### 4.2 Review and Edit
1. **Navigate:** User uses arrow keys to select a previous event in the Timeline Pane.
2. **Review:** MPV automatically seeks to the event for visual confirmation.
3. **Modify:** User hits `Enter` to reload the event into the Input Form.
4. **Update:** Modified data is written back to the log file.

## 5. Technical Stack
- **Language:** Python 3.10+
- **TUI Framework:** [Textual](https://textual.textualize.io/)
- **IPC Library:** `python-mpv-jsonipc`
- **Serialization:** Pydantic (Models) and standard JSON.

## 6. Key Features (V2 vs V1)
| Feature | v1.0 (Lua Plugin) | v2.0 (Sidecar TUI) |
| :--- | :--- | :--- |
| **Input Mode** | Modal/Blocking | Non-blocking/Persistent |
| **Validation** | Post-submission | Real-time |
| **Editing** | Manual file edit | Inline TUI editing |
| **Review** | None | Click-to-seek timeline |
| **Roster** | Hidden/Memorized | Always visible |

## 7. Data Format (JSON)
Events are stored as an array of objects:
```json
{
  "timestamp": 124.5,
  "type": "goal",
  "data": {
    "scorer": "97",
    "assists": ["29", "18"],
    "strength": "5v5"
  }
}
```
