# storjMailAlert
Simple script to send email alert when storj Node encounters an error

EASY RUN AFTER CLONING:
$ chmod +x setup.sh && sudo ./setup.sh receiver@email.xxx

We have 3 scripts:

1. Setup.sh
  Only needs to be run first time downloading the repo
  Takes receiver email as $1 and :
  Creates the command storjMailAlert and
  Runs addCron 
  
  IF YOU INPUT RECEIVERS EMAIL AS AN ARGUMENT YOU DON'T NEED TO LOOK IN ANY OTHER SCRIPT

2. addCron
  Takes an email as $1
  It creates a crontab task to excecute storjMailAlert every 10 minutes
  But you can customize it by changing this script yourself
  
3. storjMailAlert
  Created a directory in which it runs the checks and saves output in a logs file
  By default it is deleting everything  but you can uncomment the last line to save everything
