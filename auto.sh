#!/bin/bash

api='https://slack.com/api'
jq='./jq'
statusfile='status.conf'

# Bot token
token='<deleted>'
# Team full access token
ttoken='<deleted>'
# Webhook
hook='<deleted>'
# Channel
channel='random'
# Channel ID
#chid='<deleted>'
# Is it a IM channel?
#imchannel=1
# Name of the bot
botname='zhiyb-AUTO'
# Admin premission to shell execution
admin='zhiyb'

# Refresh interval
refresh=1
# Special character to active bot
special='!'

# Access API
# Parameter: METHOD TOKEN ARGUMENTS
get()
{
        #echo "curl -s \"$api/$1?token=$2&$3\"" >&2
        curl -s "$api/$1?token=$2&$3"
}

# Send message
# Parameter: CHANNEL TEXT ARGUMENTS
post()
{
        curl -s "$hook" --data 'payload={"text": "'"$2"'", "channel": "'"$1"'", "username": "'"$botname"'" '"$3"'}'
        echo '{"text": "'"$2"'", "channel": "'"$1"'", "username": "zhiyb-AUTO" '"$3"'}' | $jq
}

# Convert special characters to HTML characters
# Parameter: STRING
text2html()
{
        sed '   s/\&/\&amp;/g
                s/</\&lt;/g
                s/>/\&gt;/g
                s/%/%25/g
                s/\\/%5C%5C/g
                s/\t/\\t/g
                s/"/\\"/g
                s/&/%26/g
                s/+/%2B/g
                s/</%26lt;/g
                s/>/%26gt;/g'
}

# Convert HTML characters to plain text
# Parameter: STRING
html2text()
{
        sed '   s/&amp;/\&/g
                s/&lt;/\</g
                s/&gt;/\>/g'
}

# Update user list
updateUsers()
{
        # Load user list
        echo -n "Updating user list..."
        users="$(get users.list $token)"
        if [ "$(echo "$users" | $jq -r ".ok")" != "true" ]; then
                echo "Update user list failed:"
                echo "$users"
                return 1
        fi
        echo " Done."
}

# Reply to user
# Parameter: USERID USERNAME REPLY
reply()
{
        userid="$1"
        name="$2"
        if (($(echo "$3" | wc -l) > 1)); then
                reply="$((echo "@$name:"; echo "\`\`\`$3\`\`\`") | text2html)"
        else
                reply="$(echo "@$name: $3" | text2html)"
        fi
        echo -n "Reply to $name($userid): $reply: "
        post $chid "$reply"
        #get chat.postMessage $token "channel=$chid&username=$botname&text=$reply" | $jq #-r ".message.text"
}

# Handle specific messages
handler()
{
        userid="$1"
        name="$2"
        text="$(echo "$3" | sed -e 's/^[ \t\s]*//;s/[ \t\s]*$//')"

        case "$text" in
        date ) date '+%Y-%m-%d';;
        time ) date '+%H:%M:%S';;
        datetime ) date '+%Y-%m-%d %H:%M:%S';;
        * ) echo "Hello, $name! Your user ID is ${userid}.";;
        esac
}

# Handle general text messages
genericMessageHandler()
{
        userid="$1"
        text="$(echo "$2" | html2text)"
        msg="$3"
        if [ "$userid" == USLACKBOT ]; then
                namestr="slackbot"
        else
                user="$(echo "$users" | $jq -r ".members[] | select(.id == \"$userid\")")"
                name="$(echo "$user" | $jq -r ".name")"
                rname="$(echo "$user" | $jq -r ".real_name")"
                if [ "$rname" == null ]; then
                        namestr="$name"
                else
                        namestr="$rname($name)"
                fi
        fi
        echo "$namestr: $text"

        case "${text:0:1}" in
        "$special" ) reply "$userid" "$name" "$(handler "$userid" "$name" "${text:1}")";;
        '$' ) reply "$userid" "$name" "$(eval "${text:1}" 2>&1)"
                return
                if [ "$name" == "$admin" ]; then
                        reply "$userid" "$name" "$(eval "${text:1}" 2>&1)"
                else
                        reply "$userid" "$name" "Insufficient permission."
                fi;;
        esac
}

# Handle individual messages
messageHandler()
{
        user="$(echo "$*" | $jq -r ".user")"
        [ "$user" == null ] && user="$(echo "$*" | $jq -r ".username")"
        text="$(echo "$*" | $jq -r ".text")"
        type="$(echo "$*" | $jq -r ".subtype")"
        case "$type" in
        channel_join ) userupdate=1;;
        null ) genericMessageHandler "$user" "$text" "$*";;
        bot_message ) :;;
        * ) echo "$*" | $jq;;
        esac
}

# Update status file
updateStatus()
{
        echo "oldest=$oldest" > $statusfile
}

if [ "$(get rtm.start $token | $jq -r '.ok')" != true ]; then
        echo "rtm.start failed"
        exit 1
fi

[ -e $statusfile ] && . $statusfile
oldest="${oldest:-0}"

# Find channel ID
if [ -z "$chid" ]; then
        chid="$(get channels.list $token | $jq -r ".channels[] | {name, id} | select(.name == \"$channel\") | .id")"

        if [ -z "$chid" ]; then
                echo "Cannot find channel #$channel"
                exit 1
        fi
        echo "Channel $channel ID found: $chid"
else
        echo "Using specified channel ID: $chid"
fi

userupdate=1

while :; do
        # Update user list
        ((userupdate)) && userupdate=0 && updateUsers

        # Load new messages
        if ((imchannel)); then
                msgs="$(get im.history $ttoken "channel=$chid&oldest=$oldest")"
        else
                msgs="$(get channels.history $ttoken "channel=$chid&oldest=$oldest")"
        fi
        if [ "$(echo "$msgs" | $jq -r ".ok")" != "true" ]; then
                echo "Load messages failed:"
                echo "$msgs"
                exit 1
        fi
        count="$(echo "$msgs" | $jq -r ".messages | length")"
        ((count == 0)) && sleep $refresh && continue

        # Iteration through messages
        echo "Found $count message(s)."
        for ((i = count; i != 0; i--)); do
                messageHandler "$(echo "$msgs" | $jq -r ".messages[$((i - 1))]")"
        done

        # Update oldest with the newest message
        oldest="$(echo "$msgs" | $jq -r ".messages[0].ts")"

        # Update status file
        updateStatus
done
