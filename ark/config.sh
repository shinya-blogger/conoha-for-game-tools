#!/bin/bash
# Copyright (C) 2024 shinya-blogger https://github.com/shinya-blogger
# Licensed under the MIT License. See https://github.com/shinya-blogger/xserver-vps-tools/blob/main/LICENSE

declare -r SYSTEMD_DEFAULT_CONFIG_FILE="/etc/systemd/system/ark-server.service"
declare -r SYSTEMD_OVERRIDE_CONFIG_DIR="/etc/systemd/system/ark-server.service.d"
declare -r SYSTEMD_OVERRIDE_CONFIG_FILE="$SYSTEMD_OVERRIDE_CONFIG_DIR/override.conf"

declare -r SERVER_DIR="/opt/ark"
declare -r SERVER_CONFIG_FILE="$SERVER_DIR/ShooterGame/Saved/Config/LinuxServer/GameUserSettings.ini"

declare -r -a MAPS=("TheIsland" "TheCenter" "Ragnarok" "Valguero" "CrystalIsles" "LostIsland" "Fjordur")


config_updated=false

function die() {
    local message=$1
    echo "ERROR: $1"
    exit 1
}

function check_conoha_for_game() {
    if [ ! -d "$SERVER_DIR" ]; then
        die "This server is not a ARK: Survival Evolved Server built on ConoHa for GAME."
    fi
}

function create_systemd_override_config() {
    mkdir -p "$SYSTEMD_OVERRIDE_CONFIG_DIR"

    if [ ! -f "$SYSTEMD_OVERRIDE_CONFIG_FILE" ]; then
        echo "[Service]" > $SYSTEMD_OVERRIDE_CONFIG_FILE
        echo "ExecStart=" >> $SYSTEMD_OVERRIDE_CONFIG_FILE
        grep -E "^ExecStart=" "$SYSTEMD_DEFAULT_CONFIG_FILE" >> "$SYSTEMD_OVERRIDE_CONFIG_FILE"
    fi
}

function print_current_systemd_map_name() {
    default_config=$(grep -E "^ExecStart=" $SYSTEMD_DEFAULT_CONFIG_FILE)
    override_config=""
    if [ -f "$SYSTEMD_OVERRIDE_CONFIG_FILE" ]; then
        override_config=$(grep -E "^ExecStart=" $SYSTEMD_OVERRIDE_CONFIG_FILE)
    fi

    line=$(echo -e -n "$default_config\n$override_config" | grep -E "^ExecStart=" | tail -1)
    value=$(echo "$line" | sed -E "s/^[^ ]+ ([^ ?]+)\?.+$/\\1/")

    echo -n $value
}

function print_current_systemd_config_param() {
    param="$1"

    default_config=$(grep -E "^ExecStart=" $SYSTEMD_DEFAULT_CONFIG_FILE)
    override_config=""
    if [ -f "$SYSTEMD_OVERRIDE_CONFIG_FILE" ]; then
        override_config=$(grep -E "^ExecStart=" $SYSTEMD_OVERRIDE_CONFIG_FILE)
    fi

    line=$(echo -e -n "$default_config\n$override_config" | grep -E "^ExecStart=" | tail -1)
    value=$(echo "$line" | sed -E "s/^ExecStart=[^ ]+ .*\?$param=(\"([^\"]*)\"|([^ \"\?]*)).*$/\\2\\3/")

    echo -n $value
}

function update_systemd_map_name() {
    value="$1"

    create_systemd_override_config

    sed -i -E "s/^(ExecStart=[^ ]+ )[^ ?]+(\?.+)$/\\1$value\\2/" "$SYSTEMD_OVERRIDE_CONFIG_FILE"

    config_updated=true

    systemctl daemon-reload
}

function update_systemd_config_param() {
    param="$1"
    value="$2"

    value="${value//\//\\/}"
    if [[ "$value" == *" "* ]]; then
        value="\"$value\""
    fi

    create_systemd_override_config

    if grep -q -E "^ExecStart=\/.+ .+\?$param=" "$SYSTEMD_OVERRIDE_CONFIG_FILE"; then
        sed -i -E "s/^(ExecStart=\/.+ .+\?$param=)(\"[^\"]*\"|[^ \"\?]*)/\\1$value/" "$SYSTEMD_OVERRIDE_CONFIG_FILE"
    else
        sed -i -E "s/^(ExecStart=\/.+ .+(\?.+=(\"[^\"]*\"|[^ \"\?]*))*)/\\1\?$param=$value/" "$SYSTEMD_OVERRIDE_CONFIG_FILE"
    fi

    config_updated=true

    systemctl daemon-reload
}


function print_current_server_config_param() {
    local section="$1"
    local option="$2"

    local awk_script="
        BEGIN {section_found=0; option_found=0}
        /^\[$section\]\$/ {section_found=1; next}
        section_found == 1 && /^\[.*\]\$/ {exit}
        section_found == 1 && /^$option=/ {
            print \$0; 
            option_found=1; 
            exit
        }
    "

    awk -F '=' "$awk_script" "$SERVER_CONFIG_FILE" | sed -n "s/^$option=//p"
}

function update_server_config_param() {
    local section="$1"
    local option="$2"
    local value="$3"

    local awk_script=" 
        BEGIN {print_section=0; option_updated=0}
        /^\[$section\]\$/ {print_section=1}
        /^\[.*\]\$/ && !/^\[$section\]\$/ {
            if(print_section && !option_updated) {
                print \"$option=$value\"
                option_updated=1
            }
            print_section=0
        }
        {
            if (print_section && \$0 ~ /^$option=/) {
                print \"$option=$value\"
                option_updated=1
                next
            }
            print
        }
        END {
            if(print_section && !option_updated) {
                print \"$option=$value\"
            }
        }
    "

    local temp_file=$SERVER_CONFIG_FILE.temp
    cp -fp "$SERVER_CONFIG_FILE" "$temp_file" && awk "$awk_script" "$SERVER_CONFIG_FILE" > "$temp_file" && mv "$temp_file" "$SERVER_CONFIG_FILE"

    config_updated=true
}



function change_hostname() {
    echo
    current_val=$(print_current_systemd_config_param "SessionName")
    echo "Current Server Name: $current_val"

    while true; do
        read -p "Input Server Name: " servername
        if [ -z "$servername" ]; then
            break
        else
            update_systemd_config_param "SessionName" "$servername"
            break
        fi
    done
}

function change_map() {
    echo
    current_val=$(print_current_systemd_map_name)
    echo "Current Map: $current_val"

    while true; do
        for i in "${!MAPS[@]}"; do 
            echo "$((i+1)): ${MAPS[i]}"
        done
        read -p "Select Map(1-${#MAPS[@]}): " map_number
        if [ -z "$map_number" ]; then
            break
        elif [[ $map_number =~ ^[0-9]+$ ]] && [ $map_number -ge 1 ] && [ $map_number -le ${#MAPS[@]} ]; then
            map="${MAPS[$((map_number-1))]}"
            update_systemd_map_name "$map"
            break
        fi
        echo "Invalid choice."
    done

}

function change_join_password() {
    echo
    current_val=$(print_current_systemd_config_param "ServerPassword")
    echo "Current Join Password: $current_val"

    while true; do
        read -p "Input New Join Password: " password
        if [ -z "$password" ]; then
            break
        else
            update_systemd_config_param "ServerPassword" "$password"
            break
        fi
    done
}

function change_admin_password() {
    echo
    current_val=$(print_current_systemd_config_param "ServerAdminPassword")
    echo "Current Admin Password: $current_val"

    while true; do
        read -p "Input New Admin Password: " password
        if [ -z "$password" ]; then
            break
        else
            update_systemd_config_param "ServerAdminPassword" "$password"
            break
        fi
    done
}

function toggle_rcon() {
    echo
    current_val=$(print_current_server_config_param "ServerSettings" "RCONEnabled")
    if [ "$current_val" == "True" ]; then
        current_val="On"
    else
        current_val="Off"
    fi
    echo "Current RCON: $current_val"

    while true; do
        read -p "Enable RCON? (y/n): " answer
        if [ -z "$answer" ]; then
            break
        elif [ "$answer" == "y" ] || [ "$answer" == "Y" ]; then
            update_server_config_param "ServerSettings" "RCONEnabled" "True"
            break
        elif [ "$answer" == "n" ] || [ "$answer" == "N"  ]; then
            update_server_config_param "ServerSettings" "RCONEnabled" "False"
            break
        fi
        echo "Invalid choice."
    done
}

function quit() {
    echo

    if [ "$config_updated" == "true" ]; then
        restart_server
    fi

    exit 0
}

function restart_server() {
    local yes_no

    read -p "Restart Server? (y/n): " yes_no

    if [ "$yes_no" == "y" ] || [ "$yes_no" == "Y" ]; then
        echo "Restarting ARK: Survival Evolved Server ..."
        systemctl restart ark-server
    fi
}

function main_menu() {
    echo "ARK: Survival Evolved Server Configutation Tool for 'ConoHa for GAME'"

    while true; do
        echo
        echo "1. Change Server Hostname"
        echo "2. Change Map"
        echo "3. Change Join Password"
        echo "4. Change Admin Password"
        echo "5. Enable/Disable RCON"
        echo "q. Quit"
        read -p "Please enter your choice(1-5,q): " choice

        case $choice in
            1) change_hostname ;;
            2) change_map ;;
            3) change_join_password ;;
            4) change_admin_password ;;
            5) toggle_rcon ;;
            q) quit ;;
            *) echo "Invalid choice. Please try again." ;;
        esac
    done
}

check_conoha_for_game
main_menu
