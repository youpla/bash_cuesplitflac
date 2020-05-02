#!/bin/bash
#this script limits all the pid found to be bound to one process
#with the --exe parameter cpulimit only limits one process

#$1 : process name to watch
#$2 : optional : limit (see cpulimit man)
#$3 : optional : loop delay 
#$4 : optional : verbose 

	localvalcpulimit=$2
	localvaldelay=$3
	if [ -z "$2" ]; then localvalcpulimit=50 ; fi
	if [ -z "$3" ]; then localvaldelay="0.1s" ; fi
	go=1
	arraypid=()
	while [ $go -gt 0 ] ; do
	
		sleep $localvaldelay 
			
		listprocess=$(ps aux | grep "$1" | grep -v grep )
		if [ -n "$listprocess" ]; then
			if [ -n "$4" ]; then echo "new loop" ; fi
			if [ -n "$4" ]; then echo "$listprocess"; fi
			arraypid2=()
			foundpid=0
			
			while IFS= read -r line ; do 
				if [ "$(echo "$line" | awk '{print $11}')" == "$1" ] ; then 
					
					tmppidline="$(echo "$line" | awk '{print $2}')"
					arraypid2+=("$tmppidline")
					
					if [ ${#arraypid[@]} -eq 0 ]; then
						foundpid=$tmppidline
					else
						foundpid=$tmppidline
						for lpid in "${arraypid[@]}"; do
							if [ "$tmppidline" == "$lpid" ] ; then 
								if [ -n "$4" ]; then echo "found : $tmppidline" ; fi
								foundpid=0
								break
							fi
						done
					fi
				
					if [ $foundpid -ne 0 ]; then
						cpulimit --pid=$foundpid --limit $localvalcpulimit > /dev/null 2>&1 &
						#for speed
						echo "limiting : $foundpid"
					else
						if [ -n "$4" ]; then echo "ignoring : $tmppidline" ; fi
					fi
				
				fi
							
			done <<< "$listprocess"
						
			arraypid=("${arraypid2[@]}")
			
		else
			if [ -n "$4" ]; then echo "no process" ; fi
		fi
	   
	done


