#!/bin/bash

# DISCLAIMER : This script is provided without any warranty of any kind. Use it at your own risk. 
# DISCLAIMER : Use this script only with media you legally possess.
# BACKUP : Make sure you have a backup of your files.
# This script searches recursively directories and splits .flac or .ape files in separate tracks based on the information provided in the .cue files
#
# Version 1.0 "Does the job"
# Version 1.1 grep text comparison, echo cleanup
#
# Prerequisites: 
# flac
# monkey audio
# cpulimit
# shntool
# cuetools
# imagemagick
# file
# iconv

# gets the script dir and name 
pathsource="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pathsourcescriptname=$(basename $BASH_SOURCE) 

# checks if the script is already running
for pid in $(pidof -x "$pathsourcescriptname"); do
    if [ $pid != $$ ]; then
        echo "[$(date)] : $pathsourcescriptname : Process is already running with PID $pid"
        exit 1
    fi
done

pathinit="$pathsource/init.txt"
if [ ! -f "$pathinit" ] ; then	
	echo "config file missing"
	exit 1
fi

cpulimitpid="$pathsource/cpulimitpid.sh"

# true  : make the script verbose to the console
# false : only writes the log file
switchhelp="true"

# variables
# variables are read from init.txt
pathcueflacsource=$(grep -m 1 "pathcueflacsource=" $pathinit | awk -F'=' '{print $2}')
pathflacdest=$(grep -m 1 "pathflacdest=" $pathinit | awk -F'=' '{print $2}')
valcpulimit=$(grep -m 1 "valcpulimit=" $pathinit | awk -F'=' '{print $2}')
coverlist="tmp-front.jpg;$(grep -m 1 "coverlist=" $pathinit | awk -F'=' '{print $2}')"
coverfolderlist=$(grep -m 1 "coverfolderlist=" $pathinit | awk -F'=' '{print $2}')
filethumbnail=$(grep -m 1 "filethumbnail=" $pathinit | awk -F'=' '{print $2}') ; if [ -z "$filethumbnail" ] ; then filethumbnail="Folder.jpg" ; fi
waittime=$(grep -m 1 "waittime=" $pathinit | awk -F'=' '{print $2}'); if [ -z "$waittime" ] ; then waittime=5 ; fi
pathbase="$pathsource/db/base.txt"
pathbasenoprocess="$pathsource/db/basenoprocess.txt"
pathlog="$pathsource/log"
filelog="$pathlog/cuesplitflac.txt"
pathtmp="$pathsource/tmp"
flaccomplevel=$(grep -m 1 "flaccomplevel=" $pathinit | awk -F'=' '{print $2}') ; if [ -z "$flaccomplevel" ] ; then flaccomplevel=8 ; elif [ $flaccomplevel -gt 8 ] ; then flaccomplevel=8 ;fi
# note : pathexclus-X is read later in the script
# note : smbpattern-X is read later in the script

# function : writelog
writelog(){
	if [ $switchhelp = "true" ] ;then echo "$1" ;fi	
	echo "$1"  >> $filelog		
}

# function : checksizehuman : converts bytes to a human readable unit (mb / gb / tb) and returns the value
checksizehuman()
{
	local retval=$(echo $1 | awk '{ sum=$1 ; hum[1024**3]="Gb";hum[1024**2]="Mb";hum[1024]="Kb"; for (x=1024**3; x>=1024; x/=1024){ if (sum>=x) { printf "%.2f %s\n",sum/x,hum[x];break } }}' )
	echo $retval
}

# function : createfolder and logs it
createfolder(){
if [ ! -d "$1" ]; then
	writelog "creating folder : $1"
	mkdir "$1"
fi
}

# function : limitprocess : limits cpu consuption 
# $1 : process name to limit
limitprocess(){	
	if [ $valcpulimit -gt 0 ]; then
		cpulimit --exe $1 --limit $valcpulimit > /dev/null 2>&1 &
	fi
}

# function : purgeprocess : stops cpu consuption limit for the $1 variable
purgeprocess(){
	if [ $valcpulimit -gt 0 ]; then
		local id1cpulimit="dummy"
		
		while [ -n "$id1cpulimit" ]; do
			id1cpulimit=$(ps aux|grep "cpulimit --exe $1 --limit $valcpulimit" | grep -v grep |head -n 1 | awk '{print $2}')
			
			if [ -n "$id1cpulimit" ]; then 
				#writelog "id : $id1cpulimit"
				kill $id1cpulimit
				wait $id1cpulimit 2>/dev/null
			fi			
		done
	fi
}

# function : purgeprocess2 : stops the cpulimitpid.sh script
purgeprocess2(){
	if [ $valcpulimit -gt 0 ]; then
		local id1cpulimit="dummy"
		
		while [ -n "$id1cpulimit" ]; do
			id1cpulimit=$(ps aux|grep "$1" | grep -v grep |head -n 1 | awk '{print $2}')
			
			if [ -n "$id1cpulimit" ]; then 
				#writelog "id2 : $id1cpulimit"
				kill $id1cpulimit
				wait $id1cpulimit 2>/dev/null
			fi
		done
	fi
}

# function : smbcompatibility : replace the windows incompatible characters in the filename 
smbcompatibility(){
		
	while read fs ; do 
		local tmpbasename=$(basename "$fs")
		local tmpdirname=$(dirname "$fs")
	
		writelog "smb compatibility conversion input : $fs"
		for i in {1..6} ; do
			
			local tmpsmbpattern=$(grep -m 1 "smbpattern-$i=" $pathinit | awk -F'=' '{print $2}')
			local tmpsmbreplace=$(grep -m 1 "smbreplace-$i=" $pathinit | awk -F'=' '{print $2}')
			if [ -n "$tmpsmbpattern" ] && [ -n "$tmpsmbreplace" ] ; then
				tmpsmbpattern="[$tmpsmbpattern]"
				tmpbasename="${tmpbasename//$tmpsmbpattern/$tmpsmbreplace}"
			fi
		done

		writelog "smb compatibility conversion output :  $tmpdirname/$tmpbasename"
		mv "$fs" "$tmpdirname/$tmpbasename"
		
	done < <(find "$1" -maxdepth 1 -type f -name "*[<>:\\|?*]*")
	
}

# function : findcover : searches for cover in folder $1 's subfolder based on variables 
# files   : coverlist 
# folders : coverfolderlist
findcover(){
	#echos are sent return
	foundclres="false"
	IFS=';' read -ra arcovlst <<< "$coverlist"
	for covlst in "${arcovlst[@]}"; do
			
		local clres=$(find "$1" -maxdepth 1 -type f -iname "$covlst"  | head -n1)		
		if [ -n "$clres" ]; then 
			foundclres="true"
			echo "$clres"
			break	
		fi
			
		if [ "$foundclres" = "false" ] && [ -n "$coverfolderlist" ] ; then
			IFS=';' read -ra arcovfldlst <<< "$coverfolderlist"
			for covfldlst in "${arcovfldlst[@]}"; do
				
				local clres=$(find "$1" -type d -iname "$covfldlst" -exec find {} -type f -iname "$covlst" \; | head -n1)		
				
				if [ -n "$clres" ]; then 
					foundclres="true"
					echo "$clres"
					break
				fi
			done
		fi
		
		if [ "$foundclres" = "false" ]; then 
			
			local clres=$(find "$1" -type f -iname "$covlst" | head -n1)		
			
			if [ -n "$clres" ]; then 
				foundclres="true"
				echo "$clres"
				break	
			fi
		fi			
	
	if [ "$foundclres" = "true" ]; then 
		break	
	fi
		
	done
} 

# function : getdetailsDATE : gets the date in the cue file
getdetailsDATE(){

	local valDATE=""

	local lineDATE=$(grep "REM DATE" "$1")
	if [ -n "$lineDATE" ]; then
		valDATE=$(echo "$lineDATE" | awk '{print $3}' | tr -d '\r' )
	fi
	echo "$valDATE"
}

# function : getdetailsGENRE : gets the genre in the cue file
getdetailsGENRE(){
	local tmpvalGENRE=""
	
	local lineGENRE=$(grep "REM GENRE" "$1")
	#with "
	if [ -n "$lineGENRE" ]; then
		 tmpvalGENRE=$(echo "$lineGENRE" | awk -F'"' '{print $2}' | tr -d '\r' )
	fi
	#plain text
	if [ -z "$tmpvalGENRE" ]; then
		 tmpvalGENRE=$(echo "$lineGENRE" | cut -d\  -f3- | tr -d '\r' )
	fi
	
	echo "$tmpvalGENRE"
}

# function : addcuetag2 : runs cuetag on $1 $2
# $1 = cue
# $2 = folder
# also adds tags : Year + Genre
addcuetag2(){
	writelog "adding cuetag2 : $2"
	
	cuetag "$1" "$2/"[0-9]*.flac
	
	local tmpdate=$(getdetailsDATE "$1")
	local tmpgendre=$(getdetailsGENRE "$1")

	writelog "adding custom tag YEAR : $tmpdate :: Genre : $tmpgendre :: Compression : $flaccomplevel" 
	
	while read fs ; do 
		
		if [ -z "$(metaflac --show-tag "Year" "$fs")" ] && [ -n "$tmpdate" ] ; then 	
			metaflac "$fs" --set-tag=Year="$tmpdate" 
		fi
	
		if [ -z "$(metaflac --show-tag "Genre" "$fs")" ] && [ -n "$tmpgendre" ] ; then
			metaflac "$fs" --set-tag=Genre="$tmpgendre"
		fi
		
		if [ $flaccomplevel -ge 0 ] ; then
			metaflac "$fs" --set-tag=Compression="$flaccomplevel"
		fi
		
	done < <(find "$2" -maxdepth 1 -type f -name "*.flac")
}

# function : extractcover : extract the first front cover if available
extractcover(){
	
	if [ "$(echo "$(find "$pathtmp" -maxdepth 1 -type f -iname "block*" -exec echo "isfound" \;)" | head -n1)" = "isfound" ]; then 
		rm "$pathtmp/block"*
	fi
	
	metaflac "$1" --list --block-type=PICTURE > "$pathtmp/block.txt"
	valexit=$?
	
	if [ $valexit -eq 0 ]; then
		#creates a short list of pictures number
		grep "METADATA block #" "$pathtmp/block.txt" > "$pathtmp/block-2.txt"
		
		#iterates the pictures looking for a "type: 3 (Cover (front))"
		while IFS='' read -r varline || [[ -n "$varline" ]]; do
			varnumpicture=$(echo -n "${varline##*\#}")
			
			metaflac "$1" --list --block-number=$varnumpicture > "$pathtmp/block-3.txt"
			
			varcheck=$(grep "type: 3 (Cover (front))" "$pathtmp/block-3.txt")
			if [ -n "$varcheck" ]; then 
				typemime=$(grep "MIME type:" "$pathtmp/block-3.txt")
				typemime="${typemime##*"MIME type: "}"
				typemime=$(echo -n "$typemime")
				
				typew=$(grep "width:" "$pathtmp/block-3.txt")
				typew="${typew##*"width: "}"
				typew=$(echo -n "$typew")
							
				typeh=$(grep "height:" "$pathtmp/block-3.txt")
				typeh="${typeh##*"height: "}"
				typeh=$(echo -n "$typeh")
				writelog "extractcover : $typemime $typeh x $typew"
				
				case "$typemime" in
				"image/jpeg")			 
					metaflac --block-number=$varnumpicture --export-picture-to="$pathtmp/tmp-front.jpg" "$1"
					;;
				"image/png")				
					metaflac --block-number=$varnumpicture --export-picture-to="$pathtmp/tmp-front.png" "$1"
					convert "$pathtmp/tmp-front.png" -quality 95 "$pathtmp/tmp-front.jpg"
					;;
				*)
					writelog "extractcover : Unknown file type" 
					;;
				esac
				
				#keep the iteration ability, but no need to iterate as soon as one is found
				break
				
			fi
		done < "$pathtmp/block-2.txt"
	fi
}

# function : getpicture : iterates to find a cover file 
# is stopped after first success by a break
getpicture(){

	if [ "$(echo "$(find "$pathtmp" -maxdepth 1 -type f -iname "block*" -exec echo "isfound" \;)" | head -n1)" = "isfound" ]; then 
		rm "$pathtmp/block"*
	fi
	local tmpinttype=0
	metaflac "$1" --list --block-type=PICTURE > "$pathtmp/block.txt"
	valexit=$?
	
	if [ $valexit -eq 0 ]; then
		#creates a short list of pictures number
		grep "METADATA block #" "$pathtmp/block.txt" > "$pathtmp/block-2.txt"
		
		#iterates the pictures looking for a "type: 3 (Cover (front))"
		while IFS='' read -r varline || [[ -n "$varline" ]]; do
			varnumpicture=$(echo -n "${varline##*\#}")
			
			metaflac "$1" --list --block-number=$varnumpicture > "$pathtmp/block-3.txt"
			
			varcheck=$(grep "type: 3 (Cover (front))" "$pathtmp/block-3.txt")
			if [ -n "$varcheck" ]; then 
				typemime=$(grep "MIME type:" "$pathtmp/block-3.txt")
				typemime="${typemime##*"MIME type: "}"
				typemime=$(echo -n "$typemime")
				
				typew=$(grep "width:" "$pathtmp/block-3.txt")
				typew="${typew##*"width: "}"
				typew=$(echo -n "$typew")
							
				typeh=$(grep "height:" "$pathtmp/block-3.txt")
				typeh="${typeh##*"height: "}"
				typeh=$(echo -n "$typeh")
				writelog "getpicture : $typemime $typeh x $typew"
				
				case "$typemime" in
				"image/jpeg")			 
					tmpinttype=1
					;;
				"image/png")				
					tmpinttype=2
					;;
				*)
					echo "Unknown file type"
					;;
				esac
				
				#keep the iteration ability, but no need to iterate as soon as one is found
				break
				
			fi
		done < "$pathtmp/block-2.txt"
	fi
	return $tmpinttype
}

# function : addcover : adds cover to all flac in a folder
addcover(){
	writelog "adding cover : folder : $2 : cover : $1"
	if [ -f "$1" ]; then
	
		while read fs ; do 
			
			getpicture "$fs"
			if [ $? -eq 0 ]; then
				metaflac "$fs" --import-picture-from="$1"
			fi
			
		done < <(find "$2" -maxdepth 1 -type f -name "*.flac")
	fi
}

# function : removepregap : removes *pregap*.flac in a folder
removepregap(){
	writelog "remove pregap : $1" 
	while read fs ; do 

		rm "$fs"
		
	done < <(find "$1" -maxdepth 1 -type f -iname "*pregap*.flac")
	
}

# function : checknconvertcuetype : converts file types to utf-8
checknconvertcuetype()
{ 
	
local tmpcheck=0

	if [ -f "$1" ]; then

		local tmpfilename=$(basename "$1")

		if [ -z "$2" ]; then  writelog "check cue type : $1" ;fi	
		tmpft=$(file -b "$1" )	
		if [ -z "$2" ]; then writelog "$tmpft" ; fi
		
		case "$tmpft" in

			"UTF-8 Unicode (with BOM) text, with CRLF line terminators")
			tmpft2=$(file -bi "$1" )
			if [ -z "$2" ]; then writelog "$tmpft2" ; fi
			tmpcheck=1
			
			if [ "$2" = "true" ]; then 
				writelog "converting to utf-8 : $pathtmp/$tmpfilename"
				sed '1s/^\xEF\xBB\xBF//' < "$1" > "$pathtmp/$tmpfilename" 
			fi
			;;

			"ASCII text, with CRLF line terminators")
			tmpft2=$(file -bi "$1" )
			if [ -z "$2" ]; then  writelog "$tmpft2" ; fi
			;;

			"UTF-8 Unicode text, with CRLF line terminators")
			tmpft2=$(file -bi "$1" )
			if [ -z "$2" ]; then  writelog "$tmpft2" ; fi
			;;

			"ISO-8859 text, with CRLF line terminators")
			tmpft2=$(file -bi "$1" )
			if [ -z "$2" ]; then  writelog "$tmpft2" ; fi
			tmpcheck=1
			
			if [ "$2" = "true" ]; then 
				writelog "converting to utf-8 : $pathtmp/$tmpfilename"
				iconv -f ISO-8859-1 -t UTF-8//TRANSLIT "$1" > "$pathtmp/$tmpfilename" 
			fi
			;;
			
			"Non-ISO extended-ASCII text, with CRLF line terminators")
			tmpft2=$(file -bi "$1" )
			if [ -z "$2" ]; then writelog "$tmpft2" ; fi
			#are not processed
			tmpcheck=2
			;;
			
			*)
			writelog "unknown"
			tmpft2=$(file -bi "$1" )
			if [ -z "$2" ]; then writelog "$tmpft2" ; fi
			tmpcheck=2
			;;
		esac

	fi

	return $tmpcheck
}



# function : checkprereq : checks if the prerequisites are available
checkprereq()
{
	varmetaflac=$(which metaflac)
	varcpulimit=$(which cpulimit)
	varshnsplit=$(which shnsplit)
	varcuetag=$(which cuetag)
	varfile=$(which file)
	variconv=$(which iconv)
	varmac=$(which mac)

	go=1
	#testing binaries
	if [ ! -f "$varshnsplit" ] ; then echo "shnsplit missing" ; go=0 ; fi
	if [ ! -f "$varcpulimit" ] ; then echo "cpulimit missing" ; go=0; fi
	if [ ! -f "$varmetaflac" ] ; then echo "flac missing" ; go=0; fi
	if [ ! -f "$varcuetag" ] ; then echo "cuetag missing" ; go=0 ; fi
	if [ ! -f "$varfile" ] ; then echo "program \"file\" missing" ; go=0 ; fi
	if [ ! -f "$varmac" ] ; then echo "Monkey's audio missing" ; go=0 ; fi
	if [ ! -f "$cpulimitpid" ] ; then echo "cpulimit script missing" ; go=0 ; fi
	if [ ! -f "$variconv" ] ; then echo "iconv  missing" ; go=0 ; fi
		
	#testing directories
	if [ ! -d "$pathcueflacsource" ]; then echo "pathcueflacsource missing" ; go=0; fi
	if [ ! -d "$pathflacdest" ]; then echo "pathflacdest missing" ; go=0; fi

	if [ $go -eq 1 ]; then

		if [ ! -d "$pathlog" ]; then
			echo "creating folder : $pathlog"
			mkdir "$pathlog"	
		fi
		createfolder "$pathsource/db"
		createfolder "$pathtmp"

		return 0
		
	else
		echo "prerequisite missing"
		return 1
	fi
}

# function : processingcore : main switcher
processingcore(){
	writelog "processingcore ***********************************************************"	
	
	if [ "$(echo "$(find "$pathtmp" -maxdepth 1 -type f -iname "*.cue" -exec echo "isfound" \;)" | head -n1)" = "isfound" ]; then 
		rm "$pathtmp/"*.cue
	fi

	local tmppicture=0
	origin=$1
	shortpathandfile=$2
	
	local filename=$(basename "$origin/$shortpathandfile")
	local dirname=$(dirname "$origin/$shortpathandfile")
	shortpathanddir=${dirname#${origin}/}
	
	#when there is no subdirectories
	if [ "$dirname" = "$origin" ]; then 
		shortpathanddir=""
		shortpathanddirl=""
		shortpathanddirlr="/"
	else
		shortpathanddirl="/$shortpathanddir"
		shortpathanddirlr="/$shortpathanddir/"
	fi
	
	filenamenoextension=${filename%.*}

	done="false"
	if [ -f $pathbase ]; then
		
		fileinbase=$(grep -F -m 1 "$shortpathandfile" $pathbase)
		if [ ! -z "$fileinbase" ]; then 
			done="true" 
			writelog "already done"
		fi
		
	else
		writelog "database doesn't exist" 
	fi	

	if [ $done = "false" ]; then
		local extensionaudio
		if [ -f "$origin$shortpathanddirlr$filenamenoextension.flac" ] ; then	
			extensionaudio="flac"
		elif [ -f "$origin$shortpathanddirlr$filenamenoextension.ape" ] ; then
			extensionaudio="ape"
		fi 
		
		if [ -f "$origin/$shortpathandfile" ] &&  ([ -f "$origin$shortpathanddirlr$filenamenoextension.flac" ] || [ -f "$origin$shortpathanddirlr$filenamenoextension.ape" ]) ; then
			
			purgeprocess2 "$cpulimitpid"
			sleep 1
			limitprocess shnsplit
			limitprocess mac
			if [ $valcpulimit -gt 0 ]; then 
				"$cpulimitpid" flac $valcpulimit 0.5s > /dev/null 2>&1 &
			fi
			sleep 1
			
			if [ -f "$origin$shortpathanddirlr$filenamenoextension.$extensionaudio" ] ; then	
				actualsize=$(wc -c <"$origin/$shortpathanddir/$filenamenoextension.$extensionaudio")
			fi
		
			actualsizehum=$(checksizehuman $actualsize)
			local temps0=$actualsize
			writelog "Size 0s timestamp : Bytes : $actualsize  :: Readable : $actualsizehum"
			sleep $waittime
			
			if [ -f "$origin$shortpathanddirlr$filenamenoextension.$extensionaudio" ] ; then
				actualsize=$(wc -c <"$origin/$shortpathanddir/$filenamenoextension.$extensionaudio")
			fi
	
			actualsizehum=$(checksizehuman $actualsize)
			local temps1=$actualsize
			writelog "Size $(echo -n $waittime)s timestamp : Bytes : $actualsize  :: Readable : $actualsizehum"

			#file splitting
			if [ $temps0 -eq $temps1 ]; then
				
				tmpcuefile="$origin/$shortpathandfile"
				
				checknconvertcuetype "$origin/$shortpathandfile"
				local tmpchkcue=$?
				if [ $tmpchkcue -lt 2 ] ; then
				
					if [ $tmpchkcue -eq 1 ] ; then
						checknconvertcuetype "$origin/$shortpathandfile" "true"
						if [ -f "$pathtmp/$filename" ] ; then
							tmpcuefile="$pathtmp/$filename" 
						fi
					fi
	
					if [ ! -d "$pathflacdest$shortpathanddirl" ]; then
						mkdir -p "$pathflacdest$shortpathanddirl"
					fi

					writelog "selected cue file : $tmpcuefile"
					cp "$tmpcuefile" "$pathflacdest/$shortpathandfile"
						
					if [ -f "$origin$shortpathanddirlr$filenamenoextension.flac" ] ; then
						getpicture "$origin$shortpathanddirlr$filenamenoextension.flac"		
						
						tmppicture=$?
						if [ $tmppicture -ne 0 ]; then	
							extractcover "$origin$shortpathanddirlr$filenamenoextension.flac"	
						else
							writelog "no picture extracted"
						fi
					fi
					
					
					if [ -f "$origin$shortpathanddirlr$filenamenoextension.$extensionaudio" ] ; then
						writelog "Splitting flac: $origin$shortpathanddirlr$filenamenoextension.$extensionaudio"
						if [ $flaccomplevel -lt 0 ]; then	
							shnsplit -f "$origin/$shortpathandfile" -O always -o flac -t '%n-%t' "$origin$shortpathanddirlr$filenamenoextension.$extensionaudio" -d "$pathflacdest$shortpathanddirl"
						else
							shnsplit -f "$pathflacdest/$shortpathandfile" -O always -o "flac flac -s -$flaccomplevel -o %f -" -t '%n-%t' "$origin$shortpathanddirlr$filenamenoextension.$extensionaudio" -d "$pathflacdest$shortpathanddirl"
						fi
					fi
					
					removepregap "$pathflacdest$shortpathanddirl"
										
					addcuetag2 "$pathflacdest/$shortpathandfile" "$pathflacdest$shortpathanddirl"
					rm "$pathflacdest/$shortpathandfile"
					
					if [ -f "$pathtmp/tmp-front.jpg" ]; then
						filecover="$pathtmp/tmp-front.jpg"
						addcover "$filecover" "$pathflacdest$shortpathanddirl"
						mv "$pathtmp/tmp-front.jpg" "$pathflacdest$shortpathanddirlr$filethumbnail" 
					else
						filecover="$(findcover "$origin$shortpathanddirl")"
						if [ -n "$filecover" ]; then
							writelog "filecover:  $filecover"
							addcover "$filecover" "$pathflacdest$shortpathanddirl"
							cp "$filecover" "$pathflacdest$shortpathanddirlr$filethumbnail"
						fi						
					fi
					
					if [ -n "$(grep -m 1 "smbpattern-1=" $pathinit | awk -F'=' '{print $2}')" ] && [ -n "$(grep -m 1 "smbreplace-1=" $pathinit | awk -F'=' '{print $2}')" ] ; then	
						smbcompatibility "$pathflacdest$shortpathanddirl"
					fi
			
					if [ -f "$origin/$shortpathandfile" ]; then
						echo "$shortpathandfile">>$pathbase
					fi
					
					
				else
					
					writelog "not processed : $origin/$shortpathandfile"
					#reduce the processing load
					echo "$shortpathandfile">>$pathbase
					#keeping an inventory of unprocessed files
					echo "$shortpathandfile">>$pathbasenoprocess
					
				fi #checknconvertcuetype
			fi 
		
			sleep 1
			purgeprocess shnsplit
			purgeprocess mac
			purgeprocess2 "$cpulimitpid"
		
		else
			writelog "there is a cue file, but no audio with same name to split"
			
			if [ ! -f "$origin$shortpathanddirlr$filenamenoextension.flac" ] && [ ! -f "$origin$shortpathanddirlr$filenamenoextension.ape" ] ; then
				writelog "missing : $origin$shortpathanddirlr$filenamenoextension.flac or .ape"
				#reduce the processing load
				echo "$shortpathandfile">>$pathbase
				#keeping an inventory of unprocessed files
				echo "$shortpathandfile">>$pathbasenoprocess
			fi
			
			#improbable, .cue files are tested at each loop of fileprocessing function
			if [ ! -f "$origin/$shortpathandfile" ] ; then
				writelog "missing : $origin/$shortpathandfile"
			fi
		fi
	fi #$done=true
}

# function : fileprocessing : handles a text database to find the differencies between 2 runs
# main loop
fileprocessing()
{
	purgeprocess shnsplit 

	writelog "cleaning temp cache"
	if [ "$(echo "$(find "$pathtmp" -maxdepth 1 -type f -iname "*" -exec echo "isfound" \;)" | head -n1)" = "isfound" ]; then 
		rm "$pathtmp/"*
	fi
	
	
	writelog "searching source for files : $1"
	find "$1" -type f -name "*.cue" > "$pathtmp/listlocalcue.txt"
	
	writelog "destination path : $pathflacdest"

	writelog "db path correction"
	awk -v var="$1/" '{gsub(var, "");print}' "$pathtmp/listlocalcue.txt" > "$pathtmp/listlocalcue-2.txt"

	if [ -f "$pathbase" ]; then
		writelog "database copy"
		cp -f "$pathbase" "$pathtmp/tmpbase.txt"
		writelog "empty lines removal"
		grep -a . "$pathtmp/tmpbase.txt" > "$pathtmp/tmpbase-2.txt"

		writelog "differencies spotting"
		grep -aFvf "$pathtmp/tmpbase-2.txt" "$pathtmp/listlocalcue-2.txt" > "$pathtmp/diff.txt"
	else
		writelog "no database found, every file is processed"
		cp "$pathtmp/listlocalcue-2.txt" "$pathtmp/diff.txt"
	fi

	# path exclusions handling
	writelog "db exclusions handling"
	#removes exclusions from the loop
	#note: increase array size for more exclusion
	for i in {1..10} ; do
		el=$(grep -m 1 "pathexclus-$i=" $pathinit | awk -F'=' '{print $2}')
		if [ -n "$el" ]; then
			writelog "exclusion : $el"
			grep -aEv "^$el" "$pathtmp/diff.txt" > "$pathtmp/diff-2.txt"
			cat "$pathtmp/diff-2.txt" > "$pathtmp/diff.txt"
		fi
	done

	nblines=$(wc -l "$pathtmp/diff.txt" | awk '{print $1}')

	if [ $nblines -gt 0 ]; then

		while IFS='' read -r line || [[ -n "$line" ]]; do
			f="$line"
			if [ -n "$f" ]; then
				if [ -f "$1/$f" ]; then
					processingcore "$1" "$f"
				fi
			fi

		done < "$pathtmp/diff.txt"	
		
	else
		writelog "db no diff, nothing to do"
	fi
}

echo "running script"
if checkprereq ; then
	writelog "=========== Begin: $(date +"%Y-%m-%d--%H-%M-%S")"
	
	fileprocessing "$pathcueflacsource"
	
	if [  -d "$pathtmp" ]; then
		writelog "cleaning temp cache"
		if [ "$(echo "$(find "$pathtmp" -maxdepth 1 -type f -iname "*" -exec echo "isfound" \;)" | head -n1)" = "isfound" ]; then 
			rm "$pathtmp/"*
		fi
	fi
	
	writelog "=========== End  : $(date +"%Y-%m-%d--%H-%M-%S")"
fi

