# Todoist — Noctalia v5 Plugin

A lightweight, keyboard-driven todo list that lives in your desktop shell. Manage tasks directly from the bar widget and side panel with multi-page organization and priority levels — no context switching required.

## Features

- **Bar Widget** — Active todo count in your bar; click to open the panel
- **Side Panel** — Full-height panel with inline add, edit, toggle, and delete
- **Multi-Page** — Organize todos across pages (General, Work, Ideas, etc.)
- **Priority System** — High / Medium / Low with colored indicators
- **Crash-Safe** — JSON persistence with atomic writes (survives restarts)
- **Inline Editing** — Edit todos in-place without modals
- **Settings** — Show/hide completed todos, custom priority colors

---

## Installation

### Quick Install (Plugin Manager)

```bash
noctalia msg plugins enable 2SSK/todoist
```

### Manual Install (Local Development)

#### Step 1: Clone to plugins directory

```bash
git clone https://github.com/2SSK/todoist ~/.local/share/noctalia/plugins/todoist
```

> **Note**: Plugins in `~/.local/share/noctalia/plugins/` are discovered automatically as a **local** source — no need to add a source manually.

#### Step 2: Enable the plugin

**Option A: Via Settings GUI**

1. Open **Settings → Plugins**
2. Find **Todoist** in the list
3. Toggle it **ON**

**Option B: Via CLI**

```bash
noctalia msg plugins enable 2SSK/todoist
```

#### Step 3: Add widget to bar

Edit `~/.config/noctalia/config.toml` and add the widget to your bar:

```toml
[widget.todo]
type = "2SSK/todoist:todo"

# Add "todo" to your bar's start or end list
start = [ "workspaces", "cpu", "mem", "temp", "cat", "todo" ]
# or
end = [ "clock", "tray", "todo" ]
```

#### Step 4: Restart Noctalia

```bash
noctalia restart
```

### Source Management (Alternative)

If you prefer managing via a git source:

```bash
# Add your repo as a source
noctalia msg plugins source add todoist git https://github.com/2SSK/todoist

# Enable the plugin
noctalia msg plugins enable 2SSK/todoist

# Update from source
noctalia msg plugins update todoist
```

---

## Usage

### Quick Toggle (IPC Command)

Open or close the todo panel from anywhere — bind this to a key in your compositor:

```bash
noctalia msg panel-toggle 2SSK/todoist:panel
```

**Example Hyprland keybind:**

```ini
bind = $mainMod SHIFT, T, exec, noctalia msg panel-toggle 2SSK/todoist:panel
```

**Example Sway keybind:**

```
bindsym $mod+Shift+t exec noctalia msg panel-toggle 2SSK/todoist:panel
```

### IPC Commands

```bash
# Toggle the panel (open if closed, close if open)
noctalia msg panel-toggle 2SSK/todoist:panel

# Open the panel (no-op if already open)
noctalia msg panel-open 2SSK/todoist:panel

# Close the panel
noctalia msg panel-close
```

### Bar Widget

- **Left-click** — Toggle the side panel
- **Tooltip** — Shows "Todo List"

### Panel

#### Adding a Todo

1. Click the text input at the bottom of the panel
2. Type your todo text
3. Select priority by clicking **H**, **M**, or **L** (defaults to Medium)
4. Press **Enter** or click the **+** button

#### Editing a Todo

1. Click the **pencil** icon on a todo row
2. Edit the text in the inline input
3. Press **Enter** or click the **✓** button to save
4. Press **Escape** or click the **✕** button to cancel

#### Toggling Completion

- Click the **checkbox** (toggle) on a todo row
- Completed items move to the bottom with strikethrough text

#### Deleting a Todo

- Click the **trash** icon on a todo row
- Todo is removed immediately (no confirmation)

#### Switching Pages

- Click a page tab at the top of the panel
- Current page is highlighted

#### Managing Pages

1. Click the **⚙** (gear) icon in the tab bar
2. **Add page**: Type a name and press Enter or click **+**
3. **Rename page**: Click the **pencil** icon, edit, press Enter
4. **Delete page**: Click the **trash** icon (disabled for default/last page)
5. Click the **←** arrow to return to todos

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Enter` | Submit input (add todo, save edit) |
| `Escape` | Cancel edit |
| `Tab` | Navigate between inputs |
| `Space` | Toggle checkbox (when focused) |

---

## Configuration

### Plugin Settings

Access via **Settings → Plugins → Todoist**:

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| Show Completed Todos | bool | `true` | Display completed items in the panel list |
| Use Custom Priority Colors | bool | `false` | Override theme colors for priority indicators |
| High Priority Color | color | `#f44336` | Color for high priority (when custom colors enabled) |
| Medium Priority Color | color | `#2196f3` | Color for medium priority (when custom colors enabled) |
| Low Priority Color | color | `#9e9e9e` | Color for low priority (when custom colors enabled) |

### Data Storage

Todos are stored in:

```
~/.local/state/noctalia/plugins/todoist/todos.json
```

The file is automatically created on first use and updated on every mutation.

#### Schema

```json
{
  "todos": [
    {
      "id": 1783068811213,
      "text": "Buy groceries",
      "completed": false,
      "createdAt": "2026-07-03T08:53:31Z",
      "pageId": 0,
      "priority": "medium",
      "details": ""
    }
  ],
  "pages": [
    { "id": 0, "name": "General" },
    { "id": 1, "name": "Work" }
  ],
  "currentPageId": 0
}
```

---

## Development

### Project Structure

```
todoist/
├── plugin.toml              # Plugin manifest
├── data.luau                # Service: data management, persistence
├── panel.luau               # Panel: full UI
├── widget.luau              # Widget: bar tile
├── translations/
│   └── en.json              # English translations
├── PRD.md                   # Product Requirements Document
└── README.md                # This file
```

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Plugin: 2SSK/todoist                     │
├──────────────┬──────────────────┬───────────────────────────┤
│  [[service]] │   [[panel]]      │     [[widget]]            │
│  data.luau   │   panel.luau     │     widget.luau           │
│              │                  │                           │
│  Owns data   │  Full UI with    │  Shows active count       │
│  Persists    │  tabs, list,     │  Click opens panel        │
│  Commands    │  inline input    │                           │
│  Publishes   │  Reads state     │  Watches count from       │
│  state       │  Sends commands  │  service                  │
└──────┬───────┴────────┬─────────┴──────────┬────────────────┘
       │                │                    │
       ▼                ▼                    ▼
  noctalia.state   noctalia.state     noctalia.state
  "todos"          reads "todos"      reads "count"
  "count"          sends "command"    sends "command"
  "command"        watches "todos"    togglePanel()
```

### Hot Reload

Edits to `.luau` files hot-reload automatically. Manifest changes (`plugin.toml`) are picked up on the next config reload.

### Testing

1. Install the plugin locally
2. Enable via Settings → Plugins
3. Add todos, toggle, edit, delete
4. Verify persistence across restarts
5. Test edge cases (empty input, duplicate pages, etc.)

---

## Troubleshooting

### Plugin doesn't appear in bar

1. Verify the plugin is enabled:
   ```bash
   noctalia msg plugins list | grep todoist
   ```

2. Verify files exist:
   ```bash
   ls ~/.local/share/noctalia/plugins/todoist/
   ```

3. Check Noctalia logs:
   ```bash
   journalctl -u noctalia --user -f
   ```

### Panel doesn't open

1. Try IPC command directly:
   ```bash
   noctalia msg panel-toggle 2SSK/todoist:panel
   ```

2. Check for errors in logs

### Data not persisting

1. Check file permissions:
   ```bash
   ls -la ~/.local/state/noctalia/plugins/todoist/todos.json
   ```

2. Check disk space:
   ```bash
   df -h ~/.local/state/noctalia/
   ```

### Wrong priority colors

1. Verify custom colors are enabled in settings
2. Check color values are valid hex codes
3. Restart Noctalia after changing settings

---

## Requirements

- **Noctalia v5.0.0+**
- Linux desktop environment
- File system access to `~/.local/state/noctalia/plugins/todoist/`

## Translations

Currently supported languages:

- English (default)

To contribute translations, add a JSON file in `translations/` following the structure of `en.json`.

## License

MIT License

```
MIT License

Copyright (c) 2026 Saurav Singh Karmwar

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
```

## Acknowledgments

- Built for [Noctalia](https://github.com/noctalia-dev/noctalia) v5 shell
- Inspired by the official [noctalia-plugins](https://github.com/noctalia-dev/noctalia-plugins) repository
- Uses the v5 Luau plugin system with declarative UI

## Links

- [GitHub Repository](https://github.com/2SSK/todoist)
- [Issue Tracker](https://github.com/2SSK/todoist/issues)
- [Noctalia Documentation](https://docs.noctalia.dev/v5/)
