#!/bin/bash

#NEEDS TO BE RUN WITH SUDO

#This is only for the first time to run the programm
chmod +x storjMailAlert #Make the script excecutable

#If you run it without sudo you will have trouble
#with those commands:

#Remove the file in case we are not running setup for 1st time
rm -f /bin/storjMailAlert #Adding -f to avoid error message
mv storjMailAlert /bin #Move it to the bin

#Now you can excecute the command:
#storjMailAlert $your_email
#And run the check manually whenever you want

#I am using another script to add the task to cron
#If you want it to work you have to give the mail
#in which you want to receive the notifications as $1
#Comment it out if you want to run it yourself
#Or you can just add it manually to cron with command:
#crontab -e
chmod +x addCron && ./addCron $1
