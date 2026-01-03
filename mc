#!/bin/bash
#
# mc - Minecraft Development Server Management Script
#
# Usage: ./mc <command> [args]
#
# Commands:
#   setup   - Initial server setup
#   start   - Start server and port forward
#   stop    - Stop server
#   attach  - Attach to server console (human only)
#   send    - Send command to server (agent friendly)
#   status  - Check server status
#   logs    - View server logs
#

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="${SCRIPT_DIR}/server"
DOCS_DIR="${SCRIPT_DIR}/docs"
TMUX_SESSION="minecraft"
SERVER_JAR="paper.jar"
JAVA_OPTS="-Xms2G -Xmx4G"
PORT=25565
STOP_TIMEOUT=30

# Paper MC version (固定)
PAPER_VERSION="1.21.4"
PAPER_BUILD="232"

# Documentation repository
DOCS_REPO="https://github.com/Krz-Tech/minecraft-project.git"

# Log file
LOG_FILE="${SCRIPT_DIR}/mc.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    local msg="[INFO] $1"
    echo -e "${GREEN}${msg}${NC}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') ${msg}" >> "${LOG_FILE}"
}

log_warn() {
    local msg="[WARN] $1"
    echo -e "${YELLOW}${msg}${NC}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') ${msg}" >> "${LOG_FILE}"
}

log_error() {
    local msg="[ERROR] $1"
    echo -e "${RED}${msg}${NC}" >&2
    echo "$(date '+%Y-%m-%d %H:%M:%S') ${msg}" >> "${LOG_FILE}"
}

log_debug() {
    local msg="[DEBUG] $1"
    echo -e "${BLUE}${msg}${NC}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') ${msg}" >> "${LOG_FILE}"
}

# Check required commands
check_requirements() {
    local missing=()

    if ! command -v tmux &> /dev/null; then
        missing+=("tmux")
    fi

    if ! command -v java &> /dev/null; then
        missing+=("java")
    fi

    if ! command -v git &> /dev/null; then
        missing+=("git")
    fi

    if ! command -v curl &> /dev/null; then
        missing+=("curl")
    fi

    if [ ${#missing[@]} -ne 0 ]; then
        log_error "Missing required commands: ${missing[*]}"
        log_error "Please install them before running this script"
        exit 1
    fi
}

# Check Java version
check_java_version() {
    local java_version
    java_version=$(java -version 2>&1 | head -n 1 | cut -d'"' -f2 | cut -d'.' -f1)

    if [ -z "${java_version}" ]; then
        log_error "Failed to detect Java version"
        return 1
    fi

    if [ "${java_version}" -lt 21 ]; then
        log_error "Java 21 or higher is required (found: ${java_version})"
        return 1
    fi

    log_debug "Java version: ${java_version}"
    return 0
}

# Check if server is running
is_running() {
    tmux has-session -t "${TMUX_SESSION}" 2>/dev/null
}

# Command: setup
cmd_setup() {
    log_info "Starting initial setup..."

    # Clone documentation repository
    if [ ! -d "${DOCS_DIR}" ]; then
        log_info "Cloning documentation repository..."
        if git clone "${DOCS_REPO}" "${DOCS_DIR}"; then
            log_info "Documentation cloned to: ${DOCS_DIR}"
        else
            log_error "Failed to clone documentation repository"
            exit 1
        fi
    else
        log_info "Documentation directory already exists, updating..."
        cd "${DOCS_DIR}"
        git pull origin main || log_warn "Failed to update documentation"
        cd "${SCRIPT_DIR}"
    fi

    # Create server directory
    if [ ! -d "${SERVER_DIR}" ]; then
        mkdir -p "${SERVER_DIR}"
        log_info "Created server directory: ${SERVER_DIR}"
    fi

    cd "${SERVER_DIR}"

    # Download Paper MC (固定バージョン)
    if [ ! -f "${SERVER_JAR}" ]; then
        log_info "Downloading PaperMC ${PAPER_VERSION} build ${PAPER_BUILD}..."

        DOWNLOAD_NAME="paper-${PAPER_VERSION}-${PAPER_BUILD}.jar"
        DOWNLOAD_URL="https://api.papermc.io/v2/projects/paper/versions/${PAPER_VERSION}/builds/${PAPER_BUILD}/downloads/${DOWNLOAD_NAME}"

        if curl -o "${SERVER_JAR}" -L "${DOWNLOAD_URL}"; then
            log_info "Downloaded PaperMC ${PAPER_VERSION} build ${PAPER_BUILD}"
        else
            log_error "Failed to download PaperMC"
            exit 1
        fi
    else
        log_info "Server JAR already exists, skipping download"
    fi

    # Accept EULA
    echo "eula=true" > eula.txt
    log_info "EULA accepted"

    # Create default server.properties if not exists
    if [ ! -f "server.properties" ]; then
        cat > server.properties << 'EOF'
server-port=25565
online-mode=true
max-players=20
motd=Development Server
enable-command-block=true
spawn-protection=0
EOF
        log_info "Created default server.properties"
    fi

    # Create plugins directory
    mkdir -p plugins
    log_info "Created plugins directory"

    # Create logs directory
    mkdir -p logs
    log_info "Created logs directory"

    log_info "Setup complete!"
    log_info "Documentation: ${DOCS_DIR}"
    log_info "Run './mc start' to start the server"
}

# Command: start
cmd_start() {
    log_info "Checking requirements..."
    check_requirements

    if ! check_java_version; then
        exit 1
    fi

    if is_running; then
        log_error "Server is already running"
        exit 1
    fi

    if [ ! -f "${SERVER_DIR}/${SERVER_JAR}" ]; then
        log_error "Server JAR not found: ${SERVER_DIR}/${SERVER_JAR}"
        log_error "Run './mc setup' first"
        exit 1
    fi

    # Check if JAR file is valid (optional - skip if 'file' command not available)
    if command -v file &> /dev/null; then
        if ! file "${SERVER_DIR}/${SERVER_JAR}" | grep -q "Java archive\|Zip archive"; then
            log_error "Server JAR appears to be corrupted or invalid"
            log_error "Try removing it and running './mc setup' again"
            exit 1
        fi
    elif command -v unzip &> /dev/null; then
        if ! unzip -t "${SERVER_DIR}/${SERVER_JAR}" &> /dev/null; then
            log_error "Server JAR appears to be corrupted or invalid"
            log_error "Try removing it and running './mc setup' again"
            exit 1
        fi
    else
        log_warn "Cannot verify JAR file (file/unzip commands not available)"
    fi

    log_info "Starting Minecraft server..."
    log_debug "Server directory: ${SERVER_DIR}"
    log_debug "Java options: ${JAVA_OPTS}"
    log_debug "Server JAR: ${SERVER_JAR}"

    cd "${SERVER_DIR}"

    # Start server in tmux session with error logging
    local start_script="cd ${SERVER_DIR} && java ${JAVA_OPTS} -jar ${SERVER_JAR} nogui 2>&1 | tee -a ${SERVER_DIR}/logs/console.log"

    # Create tmux session with server window
    if ! tmux new-session -d -s "${TMUX_SESSION}" -n "server" "${start_script}"; then
        log_error "Failed to create tmux session"
        log_error "Check if tmux is working correctly: tmux new-session -d -s test"
        exit 1
    fi

    # Start port forward in separate window (Coder environment only)
    if command -v coder &> /dev/null; then
        log_info "Starting port forward..."
        tmux new-window -t "${TMUX_SESSION}" -n "portfwd" "coder port-forward --tcp ${PORT}"
        log_debug "Port forward started on port ${PORT}"
    else
        log_warn "Coder CLI not found, skipping port forward"
        log_warn "You may need to manually configure port forwarding"
    fi

    log_info "Waiting for server to initialize..."

    # Wait for server to start (check multiple times)
    local waited=0
    local max_wait=10
    while [ ${waited} -lt ${max_wait} ]; do
        sleep 1
        waited=$((waited + 1))

        if ! is_running; then
            log_error "Server process terminated unexpectedly"
            log_error "Checking logs for errors..."
            cmd_logs 30
            exit 1
        fi

        # Check if server has started by looking for "Done" in logs
        if [ -f "${SERVER_DIR}/logs/latest.log" ]; then
            if grep -q "Done" "${SERVER_DIR}/logs/latest.log" 2>/dev/null; then
                log_info "Server started successfully"
                log_info "Tmux session: ${TMUX_SESSION}"
                log_info "  - Window 'server': Minecraft server"
                if command -v coder &> /dev/null; then
                    log_info "  - Window 'portfwd': Port forward (${PORT})"
                fi
                log_info "Use './mc logs' to view server logs"
                log_info "Use './mc attach' to access console"
                return 0
            fi
        fi
    done

    if is_running; then
        log_info "Server is starting (may take a moment to fully initialize)"
        log_info "Tmux session: ${TMUX_SESSION}"
        log_info "  - Window 'server': Minecraft server"
        if command -v coder &> /dev/null; then
            log_info "  - Window 'portfwd': Port forward (${PORT})"
        fi
        log_info "Use './mc logs' to monitor startup progress"
    else
        log_error "Failed to start server"
        log_error "Check logs with './mc logs'"
        exit 1
    fi
}

# Command: stop
cmd_stop() {
    if ! is_running; then
        log_error "Server is not running"
        exit 1
    fi

    log_info "Stopping server..."

    # Send stop command to server window
    tmux send-keys -t "${TMUX_SESSION}:server" "stop" Enter

    # Wait for server to stop
    local waited=0
    while is_running && [ ${waited} -lt ${STOP_TIMEOUT} ]; do
        sleep 1
        waited=$((waited + 1))
    done

    if is_running; then
        log_warn "Server did not stop gracefully, forcing..."
        tmux kill-session -t "${TMUX_SESSION}"
    fi

    log_info "Server stopped"
    log_info "Port forward also terminated"
}

# Command: attach
cmd_attach() {
    if ! is_running; then
        log_error "Server is not running"
        exit 1
    fi

    log_info "Attaching to server console..."
    log_info "Detach with: Ctrl+B, then D"
    log_info "Switch windows: Ctrl+B, then N (next) or P (previous)"

    tmux attach-session -t "${TMUX_SESSION}:server"
}

# Command: send
cmd_send() {
    if [ -z "$1" ]; then
        log_error "Usage: ./mc send <command>"
        exit 1
    fi

    if ! is_running; then
        log_error "Server is not running"
        exit 1
    fi

    local command="$*"
    tmux send-keys -t "${TMUX_SESSION}:server" "${command}" Enter

    log_info "Sent: ${command}"
}

# Command: status
cmd_status() {
    if is_running; then
        echo "running"
        # Show window details
        echo ""
        echo "Tmux windows:"
        tmux list-windows -t "${TMUX_SESSION}" -F "  - #{window_name}: #{pane_current_command}" 2>/dev/null || true
        exit 0
    else
        echo "stopped"
        exit 1
    fi
}

# Command: logs
cmd_logs() {
    local lines="${1:-50}"
    local log_file="${SERVER_DIR}/logs/latest.log"
    local console_log="${SERVER_DIR}/logs/console.log"

    echo -e "${BLUE}=== Server Logs (last ${lines} lines) ===${NC}"

    if [ -f "${log_file}" ]; then
        tail -n "${lines}" "${log_file}"
    elif [ -f "${console_log}" ]; then
        log_warn "latest.log not found, showing console.log"
        tail -n "${lines}" "${console_log}"
    else
        log_error "No log files found in ${SERVER_DIR}/logs/"
        log_info "Available files:"
        ls -la "${SERVER_DIR}/logs/" 2>/dev/null || echo "  (logs directory does not exist)"
    fi

    echo ""
    echo -e "${BLUE}=== MC Script Log (last 20 lines) ===${NC}"
    if [ -f "${LOG_FILE}" ]; then
        tail -n 20 "${LOG_FILE}"
    else
        echo "  (no script log yet)"
    fi
}

# Command: help
cmd_help() {
    cat << EOF
mc - Minecraft Development Server Management Script

Server: PaperMC ${PAPER_VERSION} build ${PAPER_BUILD}

Usage: ./mc <command> [args]

Commands:
  setup     Initial setup (clone docs, download Paper, accept EULA, etc.)
  start     Start the development server and port forward
  stop      Stop the development server and port forward
  attach    Attach to server console (human only, use Ctrl+B D to detach)
  send      Send a command to the server (agent friendly)
  status    Check if server is running (exit code: 0=running, 1=stopped)
  logs      View server logs (usage: ./mc logs [lines])
  help      Show this help message

Tmux session structure:
  minecraft (session)
  ├── server   - Minecraft server process
  └── portfwd  - Coder port forward (25565)

Examples:
  ./mc setup                    # Initial setup
  ./mc start                    # Start server and port forward
  ./mc send "sk reload all"     # Reload all Skript scripts
  ./mc send "list"              # List online players
  ./mc status                   # Check server status
  ./mc logs                     # View last 50 lines of logs
  ./mc logs 100                 # View last 100 lines of logs
  ./mc stop                     # Stop server and port forward

For agents:
  Use './mc send <command>' to execute Minecraft commands non-interactively.
  Use './mc status' to check if server is running (check exit code).
  Use './mc logs [lines]' to view server logs.
EOF
}

# Main
case "${1:-}" in
    setup)
        cmd_setup
        ;;
    start)
        cmd_start
        ;;
    stop)
        cmd_stop
        ;;
    attach)
        cmd_attach
        ;;
    send)
        shift
        cmd_send "$@"
        ;;
    status)
        cmd_status
        ;;
    logs)
        shift
        cmd_logs "$@"
        ;;
    help|--help|-h)
        cmd_help
        ;;
    *)
        if [ -n "${1:-}" ]; then
            log_error "Unknown command: $1"
        fi
        cmd_help
        exit 1
        ;;
esac
