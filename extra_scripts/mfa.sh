#!/bin/bash

# need dialog google-authenticator qrencode oathtool

CHOICES=$(dialog --clear --title "Security Configuration" --separate-output --checklist "Select desired options with the spacebar:" 15 70 4 \
    "TOTP" "Time-based tokens (Standard)" ON \
    "REUSE" "Prohibit reuse of the same code" ON \
    "RATE" "Limit to 3 attempts every 30 seconds" ON \
    "SKEW" "Allow a larger time buffer" OFF \
2>&1 >/dev/tty)

if [ $? -ne 0 ]; then
    clear
    exit 1
fi

ARGS="-f"
[[ $CHOICES == *"TOTP"* ]] && ARGS="$ARGS -t" || ARGS="$ARGS -c"
[[ $CHOICES == *"REUSE"* ]] && ARGS="$ARGS -d" || ARGS="$ARGS -D"
[[ $CHOICES == *"RATE"* ]] && ARGS="$ARGS -r 3 -R 30" || ARGS="$ARGS -u"
[[ $CHOICES == *"SKEW"* ]] && ARGS="$ARGS -w 17" || ARGS="$ARGS -w 3"

TEMP_OUT=$(mktemp)
echo "-1" | google-authenticator $ARGS > "$TEMP_OUT" 2>&1

CONF_FILE="$HOME/.google_authenticator"
if [ ! -f "$CONF_FILE" ]; then
    dialog --title "Erreur" --msgbox "The generation has failed.\nLogs:\n$(cat $TEMP_OUT)" 15 60
    rm -f "$TEMP_OUT"
    exit 1
fi
rm -f "$TEMP_OUT"

SECRET=$(head -n 1 "$CONF_FILE")
SCRATCH_CODES=$(grep -E "^[0-9]{8}$" "$CONF_FILE")

HOST=$(hostname)
URI="otpauth://totp/${USER}@${HOST}?secret=${SECRET}&issuer=${HOST}"

while true; do
    ACTION=$(dialog --clear --title "Generation Successful" --menu "Your 2FA is ready. What do you want to do?" 15 65 5 \
        "1" "Scan QR Code" \
        "2" "View Secret Key (Manual Entry)" \
        "3" "View Backup Codes" \
        "4" "Finish and Exit" \
    2>&1 >/dev/tty)
    if [ $? -ne 0 ]; then break; fi

    case $ACTION in
        1)
            clear
            echo -e "\n=== Scan this QR code with your app (Google Authenticator, Proton...) ===\n"
            qrencode -t ANSIUTF8 "$URI" 2>/dev/null || qrencode -t ANSI "$URI"
            echo -e "\n========================================================================="
            read -p "Press Enter to return to the menu..."
            ;;
        2)
            dialog --title "Secret key" --msgbox "If the Qr Code doesn't work, enter this :\n\n  ---> $SECRET <---" 10 50
            ;;
        3)
            dialog --title "Backup codes" --msgbox "Store these codes carefully :\n\n$SCRATCH_CODES" 15 40
            ;;
        4)
            break
            ;;
    esac
done

USER_CODE=$(dialog --title "Verification Test" --inputbox "Enter your 6-digit application code:" 8 50 2>&1 >/dev/tty)

if [ $? -eq 0 ] && [ -n "$USER_CODE" ]; then
    CURRENT_CODE=$(oathtool --totp -b "$SECRET")
    PREV_CODE=$(oathtool --totp -b --time="-30s" "$SECRET")
    NEXT_CODE=$(oathtool --totp -b --time="+30s" "$SECRET")
    
    if [ "$USER_CODE" = "$CURRENT_CODE" ] || [ "$USER_CODE" = "$PREV_CODE" ] || [ "$USER_CODE" = "$NEXT_CODE" ]; then
        dialog --title "Success!" --msgbox "Congratulations! The code is VALID. Your 2FA is working perfectly." 8 50
    else
        dialog --title "Error" --msgbox "INVALID code. Check your phone's time or try the next code." 8 50
        exit 1
    fi
fi

exit 0