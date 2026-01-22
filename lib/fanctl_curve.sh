#!/bin/bash
set -e

# =========================================
# HomePinas Fan Control - Curve Management
# =========================================

FANCTL_CONF="/usr/local/bin/homepinas-fanctl.conf"

# -----------------------------------------
# Main menu
# -----------------------------------------

fanctl_curve_menu() {

    while true; do
        CHOICE=$(whiptail --title "Fan PWM Curve Adjustment" --menu \
"Adjust how your fans behave based on temperature." \
20 75 10 \
            "1" "Edit PWM curves" \
            "2" "View current PWM configuration" \
            "3" "Apply SILENT preset (quiet)" \
            "4" "Apply BALANCED preset (recommended)" \
            "5" "Apply PERFORMANCE preset (cooling first)" \
            "6" "Delete custom config (restore defaults)" \
            "7" "Back" \
            3>&1 1>&2 2>&3)

        [ $? -ne 0 ] && break

        case "$CHOICE" in
            1) edit_pwm_curves ;;
            2) view_pwm_config ;;
            3) apply_preset "silent" ;;
            4) apply_preset "balanced" ;;
            5) apply_preset "performance" ;;
            6) delete_custom_config ;;
            7) break ;;
        esac
    done
}

# -----------------------------------------
# Actions
# -----------------------------------------

edit_pwm_curves() {

    if [ ! -f "$FANCTL_CONF" ]; then
        if whiptail --yesno \
"No custom fan configuration exists.

The system is currently using the DEFAULT curves
hardcoded in the fan control script.

Do you want to create a custom configuration file
based on those default values?" \
        14 70; then
            create_default_curve
        else
            return
        fi
    fi

    whiptail --msgbox \
"EDIT MODE

You are editing the custom fan PWM configuration.

• Only numeric values should be changed
• PWM range: 0–255
• Higher PWM = louder but cooler

Deleting this file will restore default curves." \
    15 70

    ${EDITOR:-nano} "$FANCTL_CONF"
}

view_pwm_config() {

    if [ ! -f "$FANCTL_CONF" ]; then
        whiptail --msgbox \
"No custom fan configuration found.

The system is currently using the DEFAULT
fan curves defined inside the fan control script." \
        10 65
        return
    fi

    whiptail --textbox "$FANCTL_CONF" 25 80
}

delete_custom_config() {

    if [ ! -f "$FANCTL_CONF" ]; then
        warning_msg "No custom configuration exists."
        return
    fi

    if whiptail --yesno \
"Are you sure you want to delete the custom fan curve?

The system will immediately revert to the
default curves defined in the script." \
    12 65; then
        rm -f "$FANCTL_CONF"
        success_msg "Custom fan configuration removed. Defaults restored."
    fi
}

# -----------------------------------------
# Presets
# -----------------------------------------

apply_preset() {
    local preset="$1"

    case "$preset" in
        silent)
            cat > "$FANCTL_CONF" <<EOF
# =========================================
# HomePinas Fan Control - SILENT preset
# Quiet operation, higher temperatures allowed
# =========================================

PWM1_T30=60
PWM1_T35=80
PWM1_T40=110
PWM1_T45=150
PWM1_TMAX=200

PWM2_T40=70
PWM2_T50=100
PWM2_T60=140
PWM2_TMAX=200

MIN_PWM1=60
MIN_PWM2=70
MAX_PWM=255

CPU_FAILSAFE_C=80
FAST_FAILSAFE_C=70

HYST_PWM=20
EOF
            ;;
        balanced)
            create_default_curve
            ;;
        performance)
            cat > "$FANCTL_CONF" <<EOF
# =========================================
# HomePinas Fan Control - PERFORMANCE preset
# Cooling first, louder fans
# =========================================

PWM1_T30=80
PWM1_T35=120
PWM1_T40=170
PWM1_T45=220
PWM1_TMAX=255

PWM2_T40=120
PWM2_T50=170
PWM2_T60=220
PWM2_TMAX=255

MIN_PWM1=80
MIN_PWM2=120
MAX_PWM=255

CPU_FAILSAFE_C=80
FAST_FAILSAFE_C=70

HYST_PWM=5
EOF
            ;;
        *)
            error_msg "Unknown preset: $preset"
            return
            ;;
    esac

    success_msg "Preset '$preset' applied successfully."
}

# -----------------------------------------
# Helpers
# -----------------------------------------

create_default_curve() {

    cat > "$FANCTL_CONF" <<EOF
# =========================================
# HomePinas Fan Control - Custom curve
# Based on built-in default values
# =========================================

# PWM1 (HDD / SSD)
PWM1_T30=65
PWM1_T35=90
PWM1_T40=130
PWM1_T45=180
PWM1_TMAX=230

# PWM2 (NVMe + CPU)
PWM2_T40=80
PWM2_T50=120
PWM2_T60=170
PWM2_TMAX=255

# Safety limits
MIN_PWM1=65
MIN_PWM2=80
MAX_PWM=255

CPU_FAILSAFE_C=80
FAST_FAILSAFE_C=70

HYST_PWM=10
EOF
}
