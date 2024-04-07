#!/bin/bash


if [ -p /dev/stdin ]; then
        #echo "Data was piped to this script!"
        # If we want to read the input line by line
        while IFS= read line; do
                #echo "$line"
				
				arrIN=(${line// / })
				user=${arrIN[0]}
				password=${arrIN[1]}
				server=${arrIN[2]}
				ntfy_topic=${arrIN[3]}
        done
        # Or if we want to simply grab all the data, we can simply use cat instead
        # cat
elif [ -z "$4" ]; then
  echo "Imap idle listener"
  echo "Usage: $0 user@domain.com password server:993 ntfy.sh/email_topic"
  exit 1
fi



if [ ! "$user" ]; then

	#Kill all previous process + child
	killpid=$(ps -ef | grep -v grep | grep $0 | grep $1  | awk '{print $2}'| grep -v $$ | xargs)


	#Start this script into pipe to hide user password + background + nohup (except user email)
	echo "Start script"
	echo "$1 $2 $3 $4" | (nohup $0 $1 &)

	
	if [ ! -z "$killpid" ]; then
		echo Killing previous process $killpid
		#pkill -e -P $killpid
		pkill -e -P $(echo $killpid | tr -s ' ' ',')
		kill $killpid
	fi
	
	exit
fi



PIDopenssl=-1
SENDER=""
SUBJECT=""
PREVIOUSUID=""
SUBJECT2=""
SUBJECT2ok=false


start_idle () {
  echo ". login \"$user\" \"$password\""
  echo ". select inbox"
  echo ". idle"
  
  while true; do
    sleep 600;
    echo "done"
    echo ". noop"
    echo ". idle"
  done
}


try_send_notif()
{
if [ "$PIDfunc1s" ]; then
	kill $PIDfunc1s
	PIDfunc1s=""
fi

send_ntfy_info_1s &
PIDfunc1s=$(echo $!)
}

send_ntfy_info_1s()
{
sleep 1
send_ntfy_info
echo ". idle" > /proc/$PIDopenssl/fd/0
}

send_ntfy_info()
{
if  [[ ! "$SUBJECT" ]];then
	SUBJECT="(no subject)"
fi

echo curl -s -H "Tags: envelope" -H "Title: $SENDER" -H "Click: https://test.site/alink" -H "m: $SUBJECT" -d "" $ntfy_topic
curl -s -H "Tags: envelope" -H "Title: $SENDER" -H "Click: https://test.site/alink" -H "m: $SUBJECT" -d "" $ntfy_topic

}


# Start ssl connection
echo "Starting imap-notify"
sleep 3 # wait for VM network
echo "Logging in as $user at $server"

while :
do

	echo "Connection..."
	PIDopenssl=-1

	while read -r line ; do
	  # Debug info, turn this off for silent operation
	  #echo "----------------------------------------"
	  #echo "$line"
	  
	  #echo "NEW mail SUBJECT2ok : $SUBJECT2ok"

	 [ $PIDopenssl = -1 ] && PIDopenssl=$(ps -ef | grep -v grep|grep $$ | grep openssl| awk '{print $2}')
		
	  if echo "$line" | grep -Eq ". [1-9][0-9]? EXISTS"; then
		#echo "New mail received, executing $command"
		echo "done" > /proc/$PIDopenssl/fd/0
		#Ask for last UID
		echo ". FETCH * (UID)" > /proc/$PIDopenssl/fd/0
	  fi

	  if echo "$line" | grep "FETCH (UID"; then
		LASTUID=$(echo $line | grep -o -P '(?<=UID ).*(?=\))' | cut -d ' ' -f 1)
		#echo "NEW LASTUID : $LASTUID"
					
		if [[ "$LASTUID" != "$PREVIOUSUID" ]];then
			echo ". uid FETCH $LASTUID (BODY.PEEK[HEADER.FIELDS (FROM SUBJECT)])" > /proc/$PIDopenssl/fd/0
			SUBJECT=""
			SUBJECT2=""
			SUBJECT2ok=false
			PREVIOUSUID=$LASTUID
		fi
	  fi




	  if echo "$line" | grep "From: "; then
		#echo "MAILFrom : $line"
		
		SENDER=$(echo $line| cut -c 6-)
			
		if [[ "$SENDER" == *"<"* ]]; then
			SENDER=$(echo $SENDER | cut -d "<" -f1)
		fi
		
		SENDER=$(echo $SENDER | xargs)

		try_send_notif
		
	  elif echo "$line" | grep "Subject: "; then
		#echo "MAILSubject :$line"
		SUBJECT=$(echo $line|cut -c 9-|tr -d '\r')
		
		#echo "Subject1 :$SUBJECT"
		
		try_send_notif

	  elif [[ "$SUBJECT" ]] && [[ "$SUBJECT2ok" = false ]]; then
		#echo "MAILSubject (multiline) : $line"

		SUBJECT2=$(echo "$line" | tr -d '\r' )
		SUBJECT2ok=true
		#echo "Subject2 :$SUBJECT2"
		
		try_send_notif

	  fi


	done < <(openssl s_client -crlf -quiet -connect "$server" 2>/dev/null < <(start_idle))


	# Disconnected ? start reconnection

	sleep 60

done
