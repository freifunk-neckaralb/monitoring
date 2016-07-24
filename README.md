# monitoring
Ein Skript um Freifunk-Stuttgart Nodes mit Nagios zu überwachen. Kann auch mit anderen Monitordiensten verwendet werden.

Für Nagios besteht die Konfiguration aus:

commands.cfg:
```
define command{
        command_name    check_ffsnode_online
        command_line    /usr/local/bin/ffs-monitoring/check_ffsnode_online.sh $ARG1$
}
```

Und für jede zu überwachende Node:

```
define service{
        use                     generic-service
        host_name               freifunk-tuebingen.de
        service_description     ffs-Tuebi-BS31-1043nd-Alf
        check_command 		check_ffsnode_online!ffs-Tuebi-BS31-1043nd-Alf

        contact_groups          ffstue
        contacts                stefan.tzeggai,justin.humm
        notification_options    w,u,c,r
        notifications_enabled   1
}
```
