# Claude Code Implementation Guide - Multi-Session Management System

## PROJECT OVERVIEW

This is a multi-session management system for Claude Code CLI that solves the problem of managing multiple Claude instances simultaneously. Each instance gets an automatic session ID, can have a custom description shown in the status line, and supports unlimited concurrent sessions.

**Key Features:**
- `cx` command that auto-assigns session IDs (1, 2, 3...) and reuses freed ones
- `/description` command to set what you're working on in each session
- Status line showing: `~/path • Task description • Model`
- Colored output optimized for dark terminals
- No manual session ID management needed

## SYSTEM REQUIREMENTS

Before implementing, check:
- Claude Code CLI is installed (`claude` command available)
- Python3 is available
- User has a shell config file (.bashrc, .zshrc, or equivalent)
- User has write access to ~/.claude/ and ~/.local/bin/

## CORE COMPONENTS

### 1. Status Line Helper Script
**Location:** `~/.claude/statusline-helper.sh`

```bash
#!/bin/bash
# StatusLine helper script for Claude Code
# Displays: path • session description • model

input=$(cat)

# Parse JSON using Python
current_dir=$(echo "$input" | python3 -c "
import sys, json, os
try:
    data = json.load(sys.stdin)
    print(data.get('workspace', {}).get('current_dir', os.path.expanduser('~')))
except:
    print(os.path.expanduser('~'))
" 2>/dev/null)

model=$(echo "$input" | python3 -c "
import sys, json
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

# Format output
output="${WHITE}$relative_dir${RESET}"

if [[ -n "$session_desc" ]]; then
    output="$output ${GRAY}•${RESET} ${ORANGE}$session_desc${RESET}"
fi

output="$output ${GRAY}•${RESET} ${BLUE}$model${RESET}"

printf "%b" "$output"
```

### 2. Session Manager Script
**Location:** `~/.claude/claude-project`

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

### 3. Smart Session Launcher
**Location:** `~/.claude/claudex`

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

### 4. Description Command
**Location:** `~/.claude/commands/description.md`

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

## IMPLEMENTATION STEPS

1. **Create directories**
   - `~/.claude/commands/`
   - `~/.local/bin/`

2. **Install the scripts**
   - Create all 4 scripts with the code above
   - Make them executable (chmod +x)
   - Create wrappers in ~/.local/bin/ for global access

3. **Configure Claude settings**
   - Update `~/.claude/settings.json` to add statusLine configuration
   - Ensure statusLine command points to the helper script

4. **Add shell alias**
   - Add `alias cx='claudex'` to user's shell config
   - Ensure ~/.local/bin is in PATH

5. **Test the system**
   - Run `cx` to launch Claude with auto-assigned session
   - Use `/description` command inside Claude
   - Verify status line updates

## KEY IMPLEMENTATION NOTES

- **CLAUDE_SESSION** environment variable carries the session ID
- Session descriptions are stored in `.claude-project-session-{ID}` files in the working directory
- Lock files in `/tmp/` prevent session ID conflicts
- The system automatically reuses freed session IDs
- Maximum 20 concurrent sessions (configurable in claudex script)
- Colors use 256-color palette for better terminal compatibility

## CRITICAL SETTINGS

**~/.claude/settings.json must include:**
```json
{
  "statusLine": {
    "type": "command",
    "command": "$HOME/.claude/statusline-helper.sh"
  }
}
```

## USAGE AFTER IMPLEMENTATION

```bash
# Launch Claude with auto-assigned session
cx

# Inside Claude, set description
/description Working on authentication module

# View all active sessions
cx --list

# Clean orphaned locks if needed
cx --clean
```

The system handles everything automatically - users just type `cx` and get a unique session with full tracking capabilities.