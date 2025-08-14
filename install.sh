#!/bin/bash
# Claude Multi-Session Management System - Installer
# https://github.com/YOUR_USERNAME/claude-multi-session

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
RESET='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════╗${RESET}"
echo -e "${BLUE}║  Claude Multi-Session Installer           ║${RESET}"
echo -e "${BLUE}╚════════════════════════════════════════════╝${RESET}"
echo ""

# Check for required dependencies
echo -e "${YELLOW}Checking dependencies...${RESET}"

if ! command -v claude &> /dev/null; then
    echo -e "${RED}❌ Claude Code CLI not found!${RESET}"
    echo "Please install Claude Code first: npm install -g @anthropic-ai/claude-code"
    exit 1
fi

if ! command -v python3 &> /dev/null; then
    echo -e "${RED}❌ Python3 not found!${RESET}"
    echo "Please install Python3 first"
    exit 1
fi

echo -e "${GREEN}✓ Dependencies OK${RESET}"
echo ""

# Create directories
echo -e "${YELLOW}Creating directories...${RESET}"
mkdir -p ~/.claude/commands
mkdir -p ~/.local/bin
echo -e "${GREEN}✓ Directories created${RESET}"
echo ""

# Download and install scripts
echo -e "${YELLOW}Installing scripts...${RESET}"

# Status Line Helper
cat > ~/.claude/statusline-helper.sh << 'EOF'
#!/bin/bash
# StatusLine helper script for Claude Code
input=$(cat)

# Parse JSON using Python
current_dir=$(echo "$input" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('workspace', {}).get('current_dir', '$HOME'))
except:
    print('$HOME')
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
GRAY='\033[0;38;5;244m'
WHITE='\033[0;38;5;252m'
ORANGE='\033[0;38;5;215m'
BLUE='\033[0;38;5;117m'
RESET='\033[0m'

# Format output
output="${WHITE}$relative_dir${RESET}"
if [[ -n "$session_desc" ]]; then
    output="$output ${GRAY}•${RESET} ${ORANGE}$session_desc${RESET}"
fi
output="$output ${GRAY}•${RESET} ${BLUE}$model${RESET}"
printf "%b" "$output"
EOF

chmod +x ~/.claude/statusline-helper.sh
echo -e "${GREEN}✓ Status line helper installed${RESET}"

# Session Manager
cat > ~/.claude/claude-project << 'EOF'
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
EOF

chmod +x ~/.claude/claude-project
echo -e "${GREEN}✓ Session manager installed${RESET}"

# Smart Launcher
cat > ~/.claude/claudex << 'EOF'
#!/bin/bash
# Claude Session Auto-Launcher

# Colors
ORANGE='\033[0;38;5;215m'
BLUE='\033[0;38;5;117m'
WHITE='\033[0;38;5;252m'
GRAY='\033[0;38;5;244m'
GREEN='\033[0;32m'
RESET='\033[0m'

find_next_session() {
    local session_id=1
    while true; do
        if ! ps aux | grep -E "CLAUDE_SESSION=$session_id.*claude" | grep -v grep > /dev/null 2>&1; then
            if [[ ! -f "/tmp/.claude-session-$session_id.lock" ]]; then
                echo "$session_id"
                return
            fi
        fi
        ((session_id++))
        if [[ $session_id -gt 20 ]]; then
            echo "Error: Too many active sessions (>20)" >&2
            exit 1
        fi
    done
}

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
        exit 0
        ;;
esac

SESSION_ID=$(find_next_session)
touch "/tmp/.claude-session-$SESSION_ID.lock"

echo -e "${WHITE}╭────────────────────────────────────────╮${RESET}"
echo -e "${WHITE}│  🚀 Launching Claude - Session ${ORANGE}$SESSION_ID${WHITE}       │${RESET}"
echo -e "${WHITE}╰────────────────────────────────────────╯${RESET}"
echo ""
echo -e "➤ Assigned session ID: ${ORANGE}$SESSION_ID${RESET}"
echo -e "➤ Use ${BLUE}/description${RESET} to set your task"
echo ""

(
    CLAUDE_SESSION=$SESSION_ID claude --dangerously-skip-permissions
    rm -f "/tmp/.claude-session-$SESSION_ID.lock"
)
EOF

chmod +x ~/.claude/claudex
echo -e "${GREEN}✓ Smart launcher installed${RESET}"

# Create wrappers
echo '#!/bin/bash
exec ~/.claude/claude-project "$@"' > ~/.local/bin/claude-project
chmod +x ~/.local/bin/claude-project

echo '#!/bin/bash
exec ~/.claude/claudex "$@"' > ~/.local/bin/claudex
chmod +x ~/.local/bin/claudex
echo -e "${GREEN}✓ Global wrappers created${RESET}"

# /description command
cat > ~/.claude/commands/description.md << 'EOF'
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
EOF
echo -e "${GREEN}✓ /description command installed${RESET}"

# Update Claude settings
echo ""
echo -e "${YELLOW}Updating Claude settings...${RESET}"
if [[ -f ~/.claude/settings.json ]]; then
    # Backup existing settings
    cp ~/.claude/settings.json ~/.claude/settings.json.backup
    echo -e "${BLUE}Backup created: ~/.claude/settings.json.backup${RESET}"
fi

# Check if jq is available for proper JSON manipulation
if command -v jq &> /dev/null; then
    if [[ -f ~/.claude/settings.json ]]; then
        jq '.statusLine = {"type": "command", "command": "/home/'"$USER"'/.claude/statusline-helper.sh"}' ~/.claude/settings.json > ~/.claude/settings.json.tmp
        mv ~/.claude/settings.json.tmp ~/.claude/settings.json
    else
        echo '{"statusLine": {"type": "command", "command": "/home/'"$USER"'/.claude/statusline-helper.sh"}}' | jq '.' > ~/.claude/settings.json
    fi
else
    echo -e "${YELLOW}⚠ jq not found. Please manually add to ~/.claude/settings.json:${RESET}"
    echo '  "statusLine": {'
    echo '    "type": "command",'
    echo '    "command": "/home/'"$USER"'/.claude/statusline-helper.sh"'
    echo '  }'
fi

# Add aliases to bashrc
echo ""
echo -e "${YELLOW}Adding aliases...${RESET}"

# Check if aliases already exist
if ! grep -q "alias cx=" ~/.bashrc 2>/dev/null; then
    cat >> ~/.bashrc << 'EOF'

# Claude Multi-Session Management
alias cx='claudex'
EOF
    echo -e "${GREEN}✓ Alias 'cx' added to ~/.bashrc${RESET}"
else
    echo -e "${BLUE}Alias 'cx' already exists${RESET}"
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════╗${RESET}"
echo -e "${GREEN}║  ✅ Installation Complete!                 ║${RESET}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "${YELLOW}Next steps:${RESET}"
echo -e "1. Run: ${BLUE}source ~/.bashrc${RESET}"
echo -e "2. Launch Claude: ${BLUE}cx${RESET}"
echo -e "3. Set description: ${BLUE}/description Your task here${RESET}"
echo ""
echo -e "Commands available:"
echo -e "  ${BLUE}cx${RESET}         - Launch Claude with auto session"
echo -e "  ${BLUE}cx --list${RESET}  - Show active sessions"
echo -e "  ${BLUE}cx --clean${RESET} - Clean lock files"
echo -e "  ${BLUE}cx --help${RESET}  - Show help"
echo ""
echo -e "${GREEN}Enjoy managing multiple Claude sessions!${RESET}"