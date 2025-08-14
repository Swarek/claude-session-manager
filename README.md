# Claude Code Multi-Session Management System

## 🚀 Overview

A complete solution for managing multiple Claude Code instances simultaneously with unique session descriptions, automatic ID assignment, and a beautiful colored status line.

**Problem Solved**: When working with multiple Claude Code instances (4+ terminals), it's hard to track what each instance is working on.

**Solution**: An intelligent session management system with:
- **Automatic session ID assignment** (`cx` command)
- **Custom descriptions** per instance (`/description` command)
- **Colored status line** showing current task
- **No limit** on concurrent sessions

## 📸 What It Looks Like

**Status Line Format**: `~/project • Working on API refactor • Opus 4.1`

Each Claude instance shows:
- Current directory (white)
- Your task description (orange) 
- Model being used (blue)

## 🎯 Key Features

### 1. Smart Session Launcher (`cx`)
```bash
# Just type 'cx' - it handles everything
cx
# → Automatically assigns Session 1
# → Launches Claude with --dangerously-skip-permissions

# In another terminal
cx  
# → Automatically assigns Session 2

# If you close Session 1 and open new terminal
cx
# → Intelligently reuses Session 1
```

### 2. Live Description Updates (`/description`)
Inside any Claude instance:
```
/description Refactoring authentication module
```
Status line immediately updates to show your current task!

### 3. Session Management
```bash
# See all active sessions
cx --list

# Output:
# Session 1 • Refactoring auth module
# Session 2 • Writing unit tests
# Session 3 • Updating documentation
```

## 📦 Complete Installation Guide

### Step 1: Create the Status Line Helper

Create `~/.claude/statusline-helper.sh`:

```bash
#!/bin/bash
# StatusLine helper script for Claude Code
# Displays: path • session description • model

input=$(cat)

# Parse JSON using Python (more reliable than jq)
current_dir=$(echo "$input" | python3 -c "
import sys, json, os
try:
    data = json.load(sys.stdin)
    print(data.get('workspace', {}).get('current_dir', os.path.expanduser('~')))
except:
    print(os.path.expanduser('~'))
" 2>/dev/null)

model=$(echo "$input" | python3 -c "
import sys, json, os
try:
    data = json.load(sys.stdin)
    print(data.get('model', {}).get('display_name', 'Claude'))
except:
    print('Claude')
" 2>/dev/null)

# Convert to relative path
relative_dir=$(echo "$current_dir" | sed "s|^$HOME|~|")

# Get session description if CLAUDE_SESSION is set
session_desc=""
if [[ -n "$CLAUDE_SESSION" ]]; then
    session_file="$current_dir/.claude-project-session-${CLAUDE_SESSION}"
    if [[ -f "$session_file" ]]; then
        session_desc=$(cat "$session_file" 2>/dev/null | head -n1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    fi
fi

# Colors - optimized for dark terminals
GRAY='\033[0;38;5;244m'      # Medium gray for separators
WHITE='\033[0;38;5;252m'     # Soft white for path
ORANGE='\033[0;38;5;215m'    # Soft orange for session description  
BLUE='\033[0;38;5;117m'      # Sky blue for model
RESET='\033[0m'

# Format output - cleaner and simpler
output="${WHITE}$relative_dir${RESET}"

if [[ -n "$session_desc" ]]; then
    output="$output ${GRAY}•${RESET} ${ORANGE}$session_desc${RESET}"
fi

output="$output ${GRAY}•${RESET} ${BLUE}$model${RESET}"

printf "%b" "$output"
```

Make it executable:
```bash
chmod +x ~/.claude/statusline-helper.sh
```

### Step 2: Configure Claude Settings

Add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "$HOME/.claude/statusline-helper.sh"
  }
}
```

### Step 3: Create the Session Manager

Create `~/.claude/claude-project`:

```bash
#!/bin/bash
# Session Manager for Claude Code
SCRIPT_NAME="claude-project"

set_session_description() {
    local session_id="$1"
    local description="$2"
    
    if [[ -z "$session_id" ]] || [[ -z "$description" ]]; then
        echo "Error: ID and description required" >&2
        return 1
    fi
    
    local session_file=".claude-project-session-${session_id}"
    echo "$description" > "$session_file"
    echo "Session $session_id set: $description"
    
    if [[ "$CLAUDE_SESSION" == "$session_id" ]]; then
        echo "→ This session is currently active"
    fi
}

case "$1" in
    --session)
        if [[ -z "$2" ]] || [[ -z "$3" ]]; then
            echo "Usage: $SCRIPT_NAME --session ID \"Description\"" >&2
            exit 1
        fi
        set_session_description "$2" "$3"
        ;;
    *)
        echo "Usage: $SCRIPT_NAME --session ID \"Description\""
        ;;
esac
```

Make it globally accessible:
```bash
chmod +x ~/.claude/claude-project
mkdir -p ~/.local/bin
echo '#!/bin/bash
exec ~/.claude/claude-project "$@"' > ~/.local/bin/claude-project
chmod +x ~/.local/bin/claude-project
```

### Step 4: Create the Smart Launcher

Create `~/.claude/claudex`:

```bash
#!/bin/bash
# Claude Session Auto-Launcher
# Automatically finds available session and launches Claude

# Colors for display
ORANGE='\033[0;38;5;215m'
BLUE='\033[0;38;5;117m'
WHITE='\033[0;38;5;252m'
GRAY='\033[0;38;5;244m'
GREEN='\033[0;32m'
RESET='\033[0m'

# Function to find next available session ID
find_next_session() {
    local session_id=1
    
    while true; do
        # Check if Claude process already uses this session
        if ! ps aux | grep -E "CLAUDE_SESSION=$session_id.*claude" | grep -v grep > /dev/null 2>&1; then
            # Check for lock file
            if [[ ! -f "/tmp/.claude-session-$session_id.lock" ]]; then
                echo "$session_id"
                return
            fi
        fi
        ((session_id++))
        
        # Safety limit (max 20 sessions)
        if [[ $session_id -gt 20 ]]; then
            echo "Error: Too many active sessions (>20)" >&2
            exit 1
        fi
    done
}

# Function to show active sessions
show_active_sessions() {
    echo -e "${WHITE}Active Claude sessions:${RESET}"
    echo "========================"
    
    local found_any=false
    
    for i in {1..20}; do
        if ps aux | grep -E "CLAUDE_SESSION=$i.*claude" | grep -v grep > /dev/null 2>&1; then
            found_any=true
            desc=""
            if [[ -f ".claude-project-session-$i" ]]; then
                desc=$(cat ".claude-project-session-$i" 2>/dev/null)
            fi
            
            if [[ -n "$desc" ]]; then
                echo -e "  ${BLUE}Session $i${RESET} ${GRAY}•${RESET} ${ORANGE}$desc${RESET}"
            else
                echo -e "  ${BLUE}Session $i${RESET} ${GRAY}•${RESET} ${GRAY}(no description)${RESET}"
            fi
        fi
    done
    
    if [[ "$found_any" == "false" ]]; then
        echo -e "  ${GRAY}No active sessions${RESET}"
    fi
}

# Parse options
case "$1" in
    --list|-l)
        show_active_sessions
        exit 0
        ;;
    --clean|-c)
        echo "Cleaning orphaned lock files..."
        rm -f /tmp/.claude-session-*.lock
        echo -e "${GREEN}✓${RESET} Cleaned"
        exit 0
        ;;
    --help|-h)
        echo -e "${WHITE}Usage: claudex [OPTIONS]${RESET}"
        echo ""
        echo "Launch Claude with automatically assigned session"
        echo ""
        echo "Options:"
        echo -e "  ${BLUE}--list, -l${RESET}     Show active sessions"
        echo -e "  ${BLUE}--clean, -c${RESET}    Clean orphaned lock files"
        echo -e "  ${BLUE}--help, -h${RESET}     Show this help"
        echo ""
        echo "Without options, launches Claude with first available session"
        exit 0
        ;;
esac

# Find next available session
SESSION_ID=$(find_next_session)

# Create temporary lock file
touch "/tmp/.claude-session-$SESSION_ID.lock"

# Display info with colors
echo -e "${WHITE}╭────────────────────────────────────────╮${RESET}"
echo -e "${WHITE}│  🚀 Launching Claude - Session ${ORANGE}$SESSION_ID${WHITE}       │${RESET}"
echo -e "${WHITE}╰────────────────────────────────────────╯${RESET}"
echo ""
echo -e "➤ Assigned session ID: ${ORANGE}$SESSION_ID${RESET}"
echo -e "➤ Use ${BLUE}/description${RESET} to set your task"
echo ""

# Launch Claude with session and clean lock on exit
(
    CLAUDE_SESSION=$SESSION_ID claude --dangerously-skip-permissions
    rm -f "/tmp/.claude-session-$SESSION_ID.lock"
)
```

Make it executable and create wrapper:
```bash
chmod +x ~/.claude/claudex
echo '#!/bin/bash
exec ~/.claude/claudex "$@"' > ~/.local/bin/claudex
chmod +x ~/.local/bin/claudex
```

### Step 5: Create the /description Command

Create `~/.claude/commands/description.md`:

```markdown
---
allowed-tools: Bash(claude-project:*), Bash(echo)
argument-hint: <description> - Your task description
description: Sets a description for your current Claude session
---

<task>
Set session description for this Claude instance using claude-project.
</task>

<instructions>
```bash
if [[ -z "$ARGUMENTS" ]]; then
    echo "Error: Description required"
    echo "Usage: /description <your description>"
    exit 1
fi

if [[ -z "$CLAUDE_SESSION" ]]; then
    echo "Error: No active session"
    echo "Launch Claude using: cx"
    exit 1
fi

~/.claude/claude-project --session "$CLAUDE_SESSION" "$ARGUMENTS"

if [[ $? -eq 0 ]]; then
    echo ""
    echo "✓ Description updated"
    echo "Status line will show: $ARGUMENTS"
fi
```
</instructions>
```

### Step 6: Add Aliases to .bashrc

Add to `~/.bashrc`:

```bash
# Smart Claude launcher with auto session assignment
alias cx='claudex'

# Legacy numbered aliases (optional)
alias claude1='CLAUDE_SESSION=1 claude --dangerously-skip-permissions'
alias claude2='CLAUDE_SESSION=2 claude --dangerously-skip-permissions'
alias claude3='CLAUDE_SESSION=3 claude --dangerously-skip-permissions'
alias claude4='CLAUDE_SESSION=4 claude --dangerously-skip-permissions'
```

### Step 7: Activate

```bash
source ~/.bashrc
```

## 🎮 Usage Examples

### Basic Workflow

```bash
# Terminal 1
cx
# → Automatically gets Session 1
# In Claude: /description Building REST API

# Terminal 2  
cx
# → Automatically gets Session 2
# In Claude: /description Writing tests

# Terminal 3
cx
# → Automatically gets Session 3
# In Claude: /description Fixing login bug

# Check all active sessions
cx --list
# Session 1 • Building REST API
# Session 2 • Writing tests
# Session 3 • Fixing login bug
```

### Advanced Features

```bash
# Change description anytime
/description Refactoring database layer

# Session reuse - if you close Terminal 2
cx  # → Automatically reuses Session 2

# Clean up (rarely needed)
cx --clean
```

## 🎨 Customization

### Colors
The status line uses a subtle color scheme optimized for dark terminals:
- **Path**: Soft white (#252)
- **Description**: Soft orange (#215)
- **Model**: Sky blue (#117)
- **Separators**: Medium gray (#244)

To customize, edit the color codes in `~/.claude/statusline-helper.sh`.

### Session Limit
Default max is 20 concurrent sessions. To change, edit the limit in `~/.claude/claudex`.

## 📁 Files Created

```
~/.claude/
├── statusline-helper.sh     # Status line display script
├── claude-project           # Session manager
├── claudex                  # Smart launcher
└── commands/
    └── description.md       # /description command

~/.local/bin/
├── claude-project          # Global wrapper
└── claudex                 # Global wrapper

~/your-project/
├── .claude-project-session-1    # Session 1 description
├── .claude-project-session-2    # Session 2 description
└── ...                          # More as needed

/tmp/
└── .claude-session-*.lock      # Temporary lock files
```

## 🚀 Why This Is Awesome

1. **No More Confusion**: Always know what each Claude is working on
2. **Unlimited Sessions**: Not limited to 4 aliases anymore
3. **Smart Reuse**: Automatically reuses freed session IDs
4. **Zero Configuration**: Just type `cx` and go
5. **Beautiful UI**: Clean, colored status line
6. **Instant Updates**: Description changes reflect immediately

## 🐛 Troubleshooting

### "command not found: cx"
```bash
source ~/.bashrc
```

### Session not showing in status line
Make sure you launched with `cx`, not plain `claude`

### Lock files accumulating
```bash
cx --clean
```

## 💡 Pro Tips

- Keep descriptions short and clear
- Use `/description` immediately after launching
- `cx --list` is your friend when managing many sessions
- The system handles everything automatically - just use `cx`!

---

*Built for developers who juggle multiple Claude Code instances*
*Share your workflow improvements!*