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
#

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="${SCRIPT_DIR}/server"
DOCS_DIR="${SCRIPT_DIR}/docs"
SCREEN_NAME="minecraft"
SERVER_JAR="paper.jar"
JAVA_OPTS="-Xms2G -Xmx4G"
PORT=25565
STOP_TIMEOUT=30

# Paper MC version (固定)
PAPER_VERSION="1.21.4"
PAPER_BUILD="232"

# Documentation repository
DOCS_REPO="git@github.com:Krz-Tech/minecraft-project.git"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Check if server is running
is_running() {
    screen -list | grep -q "\.${SCREEN_NAME}[[:space:]]"
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
    if is_running; then
        log_error "Server is already running"
        exit 1
    fi

    if [ ! -f "${SERVER_DIR}/${SERVER_JAR}" ]; then
        log_error "Server JAR not found. Run './mc setup' first"
        exit 1
    fi

    log_info "Starting Minecraft server..."

    cd "${SERVER_DIR}"

    # Start server in screen session
    screen -dmS "${SCREEN_NAME}" java ${JAVA_OPTS} -jar "${SERVER_JAR}" nogui

    # Wait for server to start
    sleep 2

    if is_running; then
        log_info "Server started successfully"
        log_info "Screen session: ${SCREEN_NAME}"
        log_info "Port: ${PORT}"
    else
        log_error "Failed to start server"
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

    # Send stop command
    screen -S "${SCREEN_NAME}" -X stuff "stop\n"

    # Wait for server to stop
    local waited=0
    while is_running && [ ${waited} -lt ${STOP_TIMEOUT} ]; do
        sleep 1
        waited=$((waited + 1))
    done

    if is_running; then
        log_warn "Server did not stop gracefully, forcing..."
        screen -S "${SCREEN_NAME}" -X quit
    fi

    log_info "Server stopped"
}

# Command: attach
cmd_attach() {
    if ! is_running; then
        log_error "Server is not running"
        exit 1
    fi

    log_info "Attaching to server console..."
    log_info "Detach with: Ctrl+A, then D"

    screen -r "${SCREEN_NAME}"
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
    screen -S "${SCREEN_NAME}" -X stuff "${command}\n"

    log_info "Sent: ${command}"
}

# Command: status
cmd_status() {
    if is_running; then
        echo "running"
        exit 0
    else
        echo "stopped"
        exit 1
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
  start     Start the development server
  stop      Stop the development server
  attach    Attach to server console (human only, use Ctrl+A D to detach)
  send      Send a command to the server (agent friendly)
  status    Check if server is running (exit code: 0=running, 1=stopped)
  help      Show this help message

Examples:
  ./mc setup                    # Initial setup
  ./mc start                    # Start server
  ./mc send "sk reload all"     # Reload all Skript scripts
  ./mc send "list"              # List online players
  ./mc status                   # Check server status
  ./mc stop                     # Stop server

For agents:
  Use './mc send <command>' to execute Minecraft commands non-interactively.
  Use './mc status' to check if server is running (check exit code).
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
