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
  echo "Usage: $0 user@domain.com password server:993 ntfy.sh/topic_name"
  exit 1
fi



if [ ! "$user" ]; then

	#Kill all previous process + child

	killpid=$(ps -ef | grep -v grep | grep $0 | grep $1  | awk '{print $2}'| grep -v $$ | xargs)
	if [ ! -z "$killpid" ]; then
		#echo Killing previous process $killpid
		pkill -e -P $(echo $killpid | tr -s ' ' ',')
		kill $killpid
	fi

	
	#Start this script into pipe to hide user password + background + nohup (except user email)
	#echo "Start script"
	echo "$1 $2 $3 $4" | (nohup $0 $1 &)
	exit
fi



PIDopenssl=-1
SENDER=""
SUBJECT=""


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


try_send_ntfy_info_in2s()
{
sleep 2
try_send_ntfy_info
echo ". idle" > /proc/$PIDopenssl/fd/0
}

try_send_ntfy_info()
{
if [ ! -z "$SENDER" ] && [ ! -z "$SUBJECT" ];then
	echo curl -s -H "Tags: envelope" -H "Title: $SENDER" -H "Click: https://test.site/alink" -H "m: $SUBJECT" -d "" $ntfy_topic

	curl -s -H "Tags: envelope" -H "Title: $SENDER" -H "Click: https://test.site/alink" -H "m: $SUBJECT" -d "" $ntfy_topic
	SENDER=""
	SUBJECT=""
fi
}


# Start ssl connection
echo "Starting imap-notify, logging in as $user at $server"
while read -r line ; do
  # Debug info, turn this off for silent operation
  #echo "----------------------------------------"
  #echo "$line"
 [ $PIDopenssl = -1 ]
	PIDopenssl=$(ps -ef | grep -v grep|grep $$ | grep openssl| awk '{print $2}')
	
  if echo "$line" | grep -Eq ". [1-9][0-9]? EXISTS"; then
    #echo "New mail received, executing $command"
	echo "done" > /proc/$PIDopenssl/fd/0
	#Ask for last UID
	echo ". FETCH * (UID)" > /proc/$PIDopenssl/fd/0
  fi

  if echo "$line" | grep "FETCH (UID"; then
	LASTUID=$(echo $line | grep -o -P '(?<=UID ).*(?=\))')
	echo ". uid FETCH $LASTUID (BODY.PEEK[HEADER.FIELDS (FROM SUBJECT)])" > /proc/$PIDopenssl/fd/0
  fi

 




  if echo "$line" | grep "From: "; then
	echo " MAILFrom : $line"
	
	SENDER=$(echo $line| cut -c 6-)
		
	if [[ "$SENDER" == *"<"* ]]; then
		SENDER=$(echo $SENDER | cut -d "<" -f1)
	fi
	
	SENDER=$(echo $SENDER | xargs)

	try_send_ntfy_info
	
  elif echo "$line" | grep "Subject: "; then
	echo "MAILSubject :$line"
	SUBJECT=$(echo $line| cut -c 9- )

	##### TRY SEND EMAIL when subject is full (wait 2s to get all subject) #####
	try_send_ntfy_info_in2s &
	PIDfunc2s=$(echo $!)
  elif [ "$SUBJECT" ] ;then
	 echo "MAILSubject (multiline) : $line"
	 # Fill up rest of subject
	 
	 #line2=$(echo $line | tr -d '\r' )
	 #SUBJECT="$SUBJECT$line2"
	 SUBJECT=$(echo "$SUBJECT$line" | tr -d '\r' )
	 
	 if [ "$PIDfunc2s" ]; then
		 kill $PIDfunc2s
		 echo ". idle" > /proc/$PIDopenssl/fd/0
		 
		try_send_ntfy_info
		PIDfunc2s=""
	 else
		echo "ERROR - NO PIDfunc2s"
	 fi
  fi



done < <(openssl s_client -crlf -quiet -connect "$server" 2>/dev/null < <(start_idle))


