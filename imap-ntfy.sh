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


PREVIOUSUID=""
FROMSUBJECTgo=0
FROMSUBJECT=""


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


clean_temp()
{
TEMP=$(echo "$TEMP" | xargs)

[[ ! $TEMP == "=?"* ]] && return

# ntfy doesnt support some encoding, lets convert it
TEMPlower=$(echo "$TEMP" | tr '[:upper:]' '[:lower:]')

# utf-8 is ok for ntfy
[[ $TEMPlower == "=?utf-8?"* ]] && return

charset=$( echo "$TEMPlower" | cut -d'?' -f 2 )
encoding=$(echo "$TEMPlower" | cut -d'?' -f 3 )
string=$(  echo "$TEMP"      | cut -d'?' -f 4 )



[[ $charset == "utf-16" ]] && charset="UTF-16be"

# "iconv" must be after "base64 -d" else buggy with utf16 decoding
[[ $encoding == "b" ]] && TEMP=$(echo "$string" | base64 -d | iconv -f $charset -t UTF-8)
[[ $encoding == "q" ]] && TEMP=$(echo "$string" | tr _ ' ' | perl -MMIME::QuotedPrint -pe '$_=MIME::QuotedPrint::decode($_);' | iconv -f $charset -t UTF-8)
}

send_ntfy_info()
{

#echo $FROMSUBJECT
FROMSUBJECT=$(echo $FROMSUBJECT | sed $'s/\'/\x1F/g') # replace ' by x1F, crash for xargs command



SENDERfull=$(echo $FROMSUBJECT | awk -F'From:' '{print $2}'| awk -F'Subject:' '{print $1}')
SUBJECT=$(echo $FROMSUBJECT | awk -F'Subject:' '{print $2}'| awk -F'From:' '{print $1}')


SENDER=$(echo $SENDERfull | cut -d "<" -f1 | xargs)

[ -z "$SENDER" ] && SENDER=$(echo $SENDERfull | cut -d "<" -f2|cut -d ">" -f1 | xargs)


[[ ! "$SUBJECT" ]] && SUBJECT="(no subject)"

TEMP=$SENDER
clean_temp
SENDER=$(echo "$TEMP" | sed $'s/\x1F/\'/g')

TEMP=$SUBJECT
clean_temp
SUBJECT=$(echo "$TEMP" | sed $'s/\x1F/\'/g')


echo curl -s -H "Tags: envelope" -H "Title:  $SENDER" -H "Click: https://test.site/alink" -H "m: $SUBJECT" -d "" $ntfy_topic
curl -s -H "Tags: envelope" -H "Title:  $SENDER" -H "Click: https://test.site/alink" -H "m: $SUBJECT" -d "" $ntfy_topic

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
	  #echo "IMAP: $line"
	  

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
			#echo "> . uid FETCH $LASTUID (BODY.PEEK[HEADER.FIELDS (FROM SUBJECT)])"
			SUBJECT=""

			PREVIOUSUID=$LASTUID
			
			FROMSUBJECT=""
			FROMSUBJECTgo=1
		fi
else

		  if [[ "$FROMSUBJECTgo" -eq 1  ]]; then
		  
			lineclean=$(echo $line | tr -d '\r'| xargs -0)
			[[ $lineclean == ")" ]] && lineclean=""
			
			if [[ $line == ". OK Fetch completed"* && $FROMSUBJECT == *"From:"* ]]; then
			
				send_ntfy_info
				echo ". idle" > /proc/$PIDopenssl/fd/0
				FROMSUBJECTgo=0
			fi
			
			FROMSUBJECT+=$lineclean
		  fi
	fi  




	done < <(openssl s_client -crlf -quiet -connect "$server" 2>/dev/null < <(start_idle))


	# Disconnected ? start reconnection

	sleep 60

done
