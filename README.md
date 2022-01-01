# storjMailAlert
Simple script to send email alert when storj Node encounters an error

EASY RUN AFTER CLONING:
$ chmod +x setup.sh && sudo ./setup.sh

We have 3 scripts:

1. Setup.sh
  Only needs to be run first time downloading the repo
  but it can also be run to update our parameteres
  Creates the command storjMailAlert and
  Runs addCron 
  
  IF YOUR RUN THIS WITHOUT PROBLEMS YOU DONT NEED TO LOOK ANY OTHER SCRIPT

2. addCron
  Takes update interval as $1
  It creates a crontab task to excecute storjMailAlert every $1 minutes
  
3. storjMailAlert
  aka main script
  Creates a directory in which it runs the checks and saves output in a logs file
  By default it doesn't delete logs but you can uncomment the last line 
  OR manually find and delete them at ~/storjAlerts
