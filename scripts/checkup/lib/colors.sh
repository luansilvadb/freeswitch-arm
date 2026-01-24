#!/bin/bash
# colors.sh - Terminal color definitions for checkup scripts
# Part of FreeSWITCH-ARM Production Readiness Checkup

# ANSI Color Codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly NC='\033[0m' # No Color

# Box drawing characters (UTF-8)
readonly BOX_TL='╔'
readonly BOX_TR='╗'
readonly BOX_BL='╚'
readonly BOX_BR='╝'
readonly BOX_H='═'
readonly BOX_V='║'
readonly BOX_ML='╠'
readonly BOX_MR='╣'

# Status symbols
readonly CHECKMARK='✅'
readonly CROSSMARK='❌'
readonly WARNING='⚠️'
readonly INFO='ℹ️'
readonly ARROW='→'

# Color helper functions
color_red() {
    echo -e "${RED}$*${NC}"
}

color_green() {
    echo -e "${GREEN}$*${NC}"
}

color_yellow() {
    echo -e "${YELLOW}$*${NC}"
}

color_blue() {
    echo -e "${BLUE}$*${NC}"
}

color_cyan() {
    echo -e "${CYAN}$*${NC}"
}

color_bold() {
    echo -e "${BOLD}$*${NC}"
}

color_dim() {
    echo -e "${DIM}$*${NC}"
}

# Status formatting
status_pass() {
    echo -e "${GREEN}${CHECKMARK} PASSED${NC}"
}

status_fail() {
    echo -e "${RED}${CROSSMARK} FAILED${NC}"
}

status_warn() {
    echo -e "${YELLOW}${WARNING} WARNING${NC}"
}

status_skip() {
    echo -e "${DIM}⊘ SKIPPED${NC}"
}
