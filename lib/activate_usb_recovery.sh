#!/bin/bash

activate_usb_recovery() {

    info_msg "Checking current boot order on CM5..."

    # Comprobar que estamos en Raspberry Pi
    if ! command -v vcgencmd &>/dev/null; then
        error_msg "vcgencmd not found. This does not look like a Raspberry Pi."
        return 1
    fi

    # Leer configuración EEPROM
    if ! BOOTCONF=$(rpi-eeprom-config 2>/dev/null); then
        error_msg "Unable to read EEPROM configuration."
        return 1
    fi

    CURRENT_ORDER=$(echo "$BOOTCONF" | grep "^BOOT_ORDER=" | cut -d= -f2)

    if [ -z "$CURRENT_ORDER" ]; then
        error_msg "BOOT_ORDER not found in EEPROM config."
        return 1
    fi

    info_msg "Current BOOT_ORDER: ${CURRENT_ORDER}"

    echo
    echo "Boot order meaning:"
    echo "  1 = SD Card"
    echo "  4 = USB"
    echo "  Example: 0x41 → USB first, then SD"
    echo

    # Comprobar si ya está en USB primero
    if [[ "$CURRENT_ORDER" == *"41"* ]]; then
        success_msg "USB is already set as the first boot device."
        return 0
    fi

    warning_msg "This will change the boot order so USB is tried before microSD."

    if ! whiptail --yesno "Do you want to set USB as the first boot device?\n\nCurrent BOOT_ORDER=${CURRENT_ORDER}" 12 70; then
        info_msg "Operation cancelled by user."
        return 0
    fi

    info_msg "Updating EEPROM boot order..."

    # Crear config temporal con nuevo BOOT_ORDER
    TMPFILE=$(mktemp)

    rpi-eeprom-config > "$TMPFILE"

    # Reemplazar o añadir BOOT_ORDER
    if grep -q "^BOOT_ORDER=" "$TMPFILE"; then
        sed -i 's/^BOOT_ORDER=.*/BOOT_ORDER=0x41/' "$TMPFILE"
    else
        echo "BOOT_ORDER=0x41" >> "$TMPFILE"
    fi

    # Aplicar configuración
    if rpi-eeprom-config --apply "$TMPFILE"; then
        success_msg "EEPROM updated successfully."
        warning_msg "A reboot is required for changes to take effect."
    else
        error_msg "Failed to apply EEPROM configuration."
        rm -f "$TMPFILE"
        return 1
    fi

    rm -f "$TMPFILE"

    if whiptail --yesno "Reboot now to apply the new boot order?" 10 60; then
        info_msg "Rebooting system..."
        reboot
    else
        info_msg "Please reboot manually later."
    fi
}
