#!/bin/bash

#NEEDS TO BE RUN WITH SUDO

#This is only for the first time to run the programm:
chmod +x storjMailAlert addCron 2>/dev/null #Make the scripts excecutable

old_upd_int=20 #We need this variable defined in a classed scope(will be used below)
#Create a function to update data to use it below
function update() {
        #We will save old data to three variables
        old_receiver=$(cat /bin/storjMailAlert|grep "receiver="|cut -d "=" -f2|xargs)
        old_upd_int=$(cat /bin/storjMailAlert|grep "upd_int="|cut -d"=" -f2|xargs)
        old_min=$(cat /bin/storjMailAlert|grep "min="|cut -d"=" -f2|xargs)

        echo "Press enter to use default prices or if you don't want to change the last one"
        #Gather inputs and add replace values in case we receive something
        read -p "Receiver email: "  receiver
        if  [ -z $receiver ]  && [ -z $old_receiver ];then
                echo "Email not received, don't know where to send the mail"
                exit
        elif ! [ -z $receiver ];then
                #Replace with new receiver
                sed -i "s/receiver=$old_receiver/receiver=$receiver/" /bin/storjMailAlert
        fi
	echo "***if you are updating make sure to delete the old cron task with crontab -e"
        read -p "How often to run the check?[minutes] " upd_int
        if ! [ -z $upd_int ];then
                #Replace with new update interval
                sed -i "s/upd_int=$old_upd_int/upd_int=$upd_int/" /bin/storjMailAlert
		old_upd_int=$upd_int #Change this to use it in the end of the script
        fi
        read -p "Minimum err% to send mail? " min
        if ! [ -z $min ];then
                #Replace with new minimum percentage
                sed -i "s/min=$old_min/min=$min/" /bin/storjMailAlert
        fi
}

#Check if we already have
if ! [ -s storjMailAlert ];then
        #We haven't found a script in the directory we are running the setup
        read -p  "No script found do you want to update the existing one in bin?" ans
        if [ "${ans^^}" = "Y" ]; then
                update
        else
                "You don't have a script in this directory"
                "Doing nothing..."
                exit
        fi
else
        #We have a script in this directory
	echo "Configuring main script..."
        mv -f storjMailAlert /bin
        update
	echo "Command 'storjMailAlert' was created"
	echo "run it whenever you want to run the check"
fi

#I am using another script to add the task to cron
chmod +x addCron && ./addCron $old_upd_int && echo Task added to cron succesfully
