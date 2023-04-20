#!/usr/bin/bash

for name in $(/bin/ls -1 /var/lib/user_info/lust); 
do 
#    echo $name 
    ../src/lumi-ldap-userinfo.lua $name
done
