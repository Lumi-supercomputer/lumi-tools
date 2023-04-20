#!/usr/bin/bash

for name in $(/bin/ls -1 /var/lib/project_info/lust); 
do 
#    echo $name 
    ../src/lumi-ldap-projectinfo.lua $name
done
