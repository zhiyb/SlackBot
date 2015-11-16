#!/bin/bash

api='https://slack.com/api'
jq='./jq'
statusfile='status.conf'
configfile='config.conf'

if [ -e "$configfile" ]; then
	. "$configfile"
else
	cat - > "$configfile" <<-CONFIGFILE
		# Bot token
		token='xoxb-xxx-xxx'
		# Team full access token
		ttoken='xoxp-xxx-xxx-xxx-xxx'
		# Webhook
		hook='https://hooks.slack.com/services/Txxx/Bxxx/xxx'

		# Channel
		channel='general'
		# Channel ID
		#chid='xxx'
		# Is it a IM channel?
		#imchannel=1

		# Name of the bot
		botname='I'm a bot'
		# User name of the bot (all lower case)
		botuname='the_bot'
		# Admin premission to shell execution
		admin='admin_account'

		# Refresh interval
		refresh=1
	CONFIGFILE
	echo "No configuration file found."
	exit 1
fi

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
	#echo '{"text": "'"$2"'", "channel": "'"$1"'", "username": "zhiyb-AUTO" '"$3"'}' | $jq >&2
	curl -s "$hook" --data 'payload={"icon_url": "'"$iconurl"'", "text": "'"$2"'", "channel": "'"$1"'", "username": "'"$botname"'" '"$3"'}'
}

# Convert special characters to HTML characters
# Parameter: STRING
text2html()
{
	sed '	s/\&/\&amp;/g
		s/</\&lt;/g
		s/>/\&gt;/g
		s/%/%25/g
		s/\\/%5C%5C/g
		s/\t/\\t/g
		s/"/\\"/g
		s/&/%26/g
		s/+/%2B/g
		s/</%26lt;/g
		s/>/%26gt;/g
		s/%26lt;%26lt;%26lt;%26lt;/</g
		s/%26gt;%26gt;%26gt;%26gt;/>/g'
}

# Convert HTML characters to plain text
# Parameter: STRING
html2text()
{
	sed '	s/&amp;/\&/g
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

# List users
listUsers()
{
	updateUsers
	count="$(echo "$users" | $jq -r ".members | length")"

	# Iteration through messages
	for ((i = 0; i != count; i++)); do
		user="$(echo "$users" | $jq -r ".members[$i]")"
		name="$(echo "$user" | $jq -r ".name")"
		rname="$(echo "$user" | $jq -r ".real_name")"
		userid="$(echo "$user" | $jq -r ".id")"
		email="$(echo "$user" | $jq -r ".profile.email")"
		if [ "$email" != "null" ]; then
			echo "$name($userid|<<<<mailto:$email|$email>>>>): $rname"
		else
			echo "$name($userid): $rname"
		fi
		[ "$name" == "$botuname" ] && iconurl="$(echo "$user" | $jq -r ".profile.image_original")" && echo "Icon get: $iconurl";
	done
	echo "Total: $count users."
}

# Reply to user
# Parameter: USERID USERNAME REPLY
reply()
{
	userid="$1"
	name="$2"
	if [ -n "$4" ]; then
		reply="$3"
	else
		if (($(echo "$3" | wc -l) > 1)); then
			reply="$(echo "<@$userid>:"; echo "\`\`\`$3\`\`\`" | text2html)"
		else
			reply="$(echo -n "<@$userid>: "; echo "$3" | text2html)"
		fi
	fi
	echo -n "Reply to $name($userid): $reply"
	post $chid "$reply" > /dev/null
}

# Get bot API
getapi()
{
	method="$1"
	shift
	get "$method" $token $@
}

# Get team API
gettapi()
{
	method="$1"
	shift
	get "$method" $ttoken $@
}

# Handle specific messages
handler()
{
	userid="$1"
	name="$2"
	text="$(echo "$3" | sed -e 's/^[ \t\s]*//;s/[ \t]*$//')"

	if [ "$4" == "zh_CN" ]; then
		export TZ=Asia/Shanghai
		export LC_ALL=zh_CN.utf8
	fi

	case "${text%%\ *}" in
	date ) date '+%F %A'; return;;
	time ) date '+%H:%M:%S'; return;;
	datetime ) date '+%F %A %H:%M:%S'; return;;
	users ) listUsers; return;;
	get ) getapi ${text##*\ } | $jq -r "."; return;;
	gett ) gettapi ${text##*\ } | $jq -r "."; return;;
	esac

	if [ "$4" == "zh_CN" ]; then
		case "$text" in
		"" ) echo -n "你好, $name! 你的ID是 ${userid}. "; date '+今天是 %x %A, 第%V周, 这一年的第%j天, epoch开始的第%s秒, 时区: %Z(%:z), 现在是%X.';;
		* ) echo "你好, $name! 你的ID是 ${userid}.";;
		esac
	else
		case "$text" in
		"" ) echo -n "Hello, $name! Your ID is ${userid}. "; date '+Today is %A, %x, week %V, day %j of the year, %s seconds since epoch, time zone %Z(%:z), the time now is %X.';;
		* ) echo "Hello, $name! Your user ID is ${userid}.";;
		esac
	fi
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
	'!' ) reply "$userid" "$name" "$(handler "$userid" "$name" "${text:1}")";;
	'！' ) reply "$userid" "$name" "$(handler "$userid" "$name" "${text:1}" zh_CN)";;
	'$' ) reply "$userid" "$name" "$(eval "${text:1}" 2>&1)"
		return
		if [ "$name" == "$admin" ]; then
			reply "$userid" "$name" "$(eval "${text:1}" 2>&1)"
		else
			reply "$userid" "$name" "Insufficient permission."
		fi;;
	'|' ) reply "$userid" "$name" "${text:1}" no;;
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
	((userupdate)) && userupdate=0 && listUsers

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
