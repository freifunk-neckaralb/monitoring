#!/bin/bash

# Authors: Stefan Tzeggai, Justin Humm
# Version 0.8
# Dieses Skript liest über eine JSON Datei des Freifunk Stuttgart den Zeitpunkt des letzten Kontakts jeder Node aus. Ist diese älter als die für WARNING oder CRITICAL übergebenen Schwellenwerte, so wird ungleich 0 zurückgegeben.
# Passend zu NAGIOS steht EXIT-Code 0 für OK, 1 für WARNING, 2 für CRITICAL.
# Wenn die erste URL nicht zu funktionieren scheint, dann verwende die 2. URL

JSONURL1=http://hg.albi.info/json/nodes.json
JSONURL2=http://karte.freifunk-stuttgart.de/json/nodesdb.json

# Diese Datei (und weitere Dateien in dem Verzeichnis) müssen für den Monitoring-User schreibbar sein
TMPFILE=/tmp/freifunk_json_extract.txt

warningMinutes=90
criticalMinutes=300

usage()
{
        echo "Verwendung: ./check_ffsnode_online.sh [OPTION] [nodename]"
        echo "Optionen:"
        echo "	[nodename]			Kompletter Name des Freifunkrouters"
        echo ""
        echo "	-w [warning age]		Minuten bis WARNUNG, das Router nicht gesehen wurde. Default 45. Werte kleiner 10 machen keine Sinn, da die JSON Datei nur alle 5 bis 10 Minuten neu geholt wird."
        echo "	-c [critical age]		Minuten bis CRITICAL, das Router verschwunden wurde. Default 180. Werte kleiner 10 machen keine Sinn, da die JSON Datei nur alle 5 bis 10 Minuten neu geholt wird."
        echo ""
        echo "Beispiele: ./check_ffsnode_online.sh ffs-Tue-BS31-1043nd-Alf" 
        echo "           ./check_ffsnode_online.sh -w 30 -c 90 ffs-Tue-Snackhouse"        
        exit 3
}


if [ "$1" == "--help" ]; then
    usage; exit 0
fi

while getopts w:c: OPTNAME; do
        case "$OPTNAME" in
        w)      warningMinutes="$OPTARG";;
        c)      criticalMinutes="$OPTARG";;
        *)      usage;;
        esac
done

NODENAME="${@: -1}"

if [ "$warningMinutes" -gt "$criticalMinutes" ] ; then
    echo "CRITICAL Minuten muss mehr sein als WARNING Minuten"
    echo "Warning Minuten: $warningMinutes"
    echo "Critical Minuten: $criticalMinutes"
    echo ""
    echo "For more information:  ./${0##*/} --help" 
    exit 1
fi

if [ -s $TMPFILE ]; then
	AGE=$(( (`date +%s` - `stat -L --format %Y $TMPFILE`) ))	
else
	#echo "DEBUG: Die Datei $TMPFILE existiert nicht oder ist leer. Setze AGE auf 9999s damit die Datei neu erstelle wird" 
	AGE=9999
fi

#echo "DEBUG: Datei $TMPFILE hat ein Alter von $AGE Sekunden."

if [ $AGE -gt 333 ]; then
	rm -f $TMPFILE $TMPFILE.$NODENAME
	#echo "DEBUG: Aelter als 333s. Hole neu $JSONURL1 ..."
	curl -f -s $JSONURL1 -H 'User-Agent: Tuebingen Freifunk Monitoring' | sed s/},{\"nodeinfo\"/},\\n{\"nodeinfo\"/g | sed -r 's/^.*hostname.:.(.*).,.hardware.*lastseen.:.(2.*).,.first.*$/\1\t\2/g' > $TMPFILE.$NODENAME

	ERROR=0
	if [ $? -ne 0 ] ; then
		echo "WARNING: curl auf $JSONURL1 liefert EXITCODE ungleich 0"
		ERROR=1
	fi

	if [ ! -e $TMPFILE.$NODENAME ] ; then
		echo "WARNING: $TMPFILE.$NODENAME existiert nicht"
		ERROR=2
	fi

	if [ ! -s $TMPFILE.$NODENAME ] ; then
		echo "WARNING: $TMPFILE.$NODENAME hat SIZE=0"
		ERROR=3
	fi

	if [ $ERROR -ne 0 ] ; then
		rm -f $TMPFILE $TMPFILE.$NODENAME
		echo "WARNING: $JSONURL1 ist down oder andere Probleme beim Abruf. Probiere über $JSONURL2"

    	curl -f -s $JSONURL2 -H 'User-Agent: Tuebingen Freifunk Monitoring' | sed s/\"hostname\"/\\n\"hostname\"/g | sed -r 's/^.*hostname.:.([^\"]*)..*.last_online.:(1[0-9]*),.*$/\1\t\2/g' > $TMPFILE.$NODENAME

    	# Bei der Fallback-URL wird aktuell nicht so genau getestet, ob das fehlschlug
	    if [ $? -ne 0 ]; then
	      echo "WARNING: $JSONURL2 ist auch down oder andere Probleme beim Abruf! Giveup!"
	      exit -1
	    fi

	fi

	mv $TMPFILE.$NODENAME $TMPFILE
	
	# Falls man das Skript mal als root startet, muss Nagios später die Datei überschreiben dürfen
	# Wenn man das Skript nie als root startet, oder kein Nagios verwendet, kann man die 
	# Zeile auch einfach auskommentieren.
	chown -f nagios:nagios $TMPFILE
fi

# LastSeen aus 2. Spalte auslesen. Nodename ist Case-Sensitive und trifft nur komplette Namen.
LSDATE=`cat $TMPFILE | grep -P "^$NODENAME\t" | sed -r 's/.*\t(.*)$/\1/g'`

if [[ -z $LSDATE ]];
then
   echo "CRITICAL: Node $NODENAME ist nicht bekannt"
   exit 2;
fi

# Zeitpunkt JETZT in Sekunden seit Epochenbeginn.
NOW=`date +'%s'`

# Zeitpunkt LASTSEEN der Node in Sekunden seit Epochenbeginn. Das klappt nur bei JSONURL1...
LS=`date -d ${LSDATE} +'%s'`
if [ $? -ne 0 ] || [ $LS -lt 1451656367 ] || [ $LS -gt 1577886767 ]; then
	 #echo "WARNING: ${LSDATE} scheint kein Datum zu sein. Das ist bei $JSONURL2 der Fall. Mache weiter und erwarte Sekunden seit EPOCHE"
	 LS=${LSDATE}
fi

# Wieviele Sekunden/Minuten/Stunden ist LASTSEEN her?
DIFF=`expr $NOW - $LS`
DIFFM=`expr $DIFF / 60`
DIFFH=`expr $DIFF / 60 / 60`

if [ "$DIFFM" -ge "$criticalMinutes" ]
then
   echo "CRITICAL: $NODENAME seit $DIFFH h offline, lastseen $LSDATE"
   exit 2;
fi

if [ "$DIFFM" -ge "$warningMinutes" ]
then
   echo "WARNING: $NODENAME seit $DIFFM m offline. lastseen $LSDATE"
   exit 1;
fi

echo "OK: Node $NODENAME wurde vor $DIFFM Minuten gesehen. lastseen $LSDATE"
exit 0;

