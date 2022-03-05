#!/bin/bash

mkdir -p  ~/storjAlerts #Make a dir to work on (if not exists)
cd ~/storjAlerts #Move to this directory

#################################################################################
#As seen in the ./setup we are using sed to assign prices in our varibles,
#but you can also edit those lines manually to add them
receiver=your_email
#This is how often we will check the logs
upd_int=15
#Finally we have the minimum percentage of errors required to send an email
min=5
#################################################################################

#We want to check all logs between two checks
docker logs storagenode --since "$upd_int"m &> out #Save everything to a txt file
n_logs=$(cat out|wc -l) #Count the logs that we saved
grep 'FATAL\|ERROR\|WARN' out  > err #Save errors to err file
#Counting error logs but we will add 00 in the end so will get the percentage
err_logs=$(cat err|wc -l)
#Finally we can count the percentage of errors:
percent=$(bc <<<"scale=2; $err_logs*100 / $n_logs") #Now that is between 0-100

now=$(date +"%T") #get current time

#Check if the percentage is more than the minimum we set:
if (( $(echo "$percent > $min" |bc -l) ));then
        #In this case we will create mail:

        echo "Subject: Storj ERROR Alert" >mail #Add the subject
        echo " " >>mail #Its really important to let a new line after

        #We will save each error seperately to see if we have repetitions
        #To make it easier for operator to understand the problem
        #----------MORE STATS TO BE ADDED----------

        #-f2- is used to remove timestamps to find uniq errors
        #cut -d { is used to remove specifications about piece id etc...
        cut -d "Z" -f2- err|cut -d "{" -f1|sort|uniq -c > uniqerr
        uniq_errors=$(cat uniqerr|wc -l) #Count unique errors
        echo "---------------------------------------------------" >>mail
        echo ">Total errors: $err_logs / $n_logs " >>mail
        echo ">Unique errors: $uniq_errors" >>mail
        echo ">Total errors percentage: $percent %">>mail
        echo "---------------------------------------------------">>mail
        echo "">>mail
        echo "TIMES_ENCOUNTERED     ERROR">>mail
        echo "">>mail
        cat uniqerr >>mail #unique errors and times each appeared
        echo "<------------------------------------------------------>">>mail
         echo "">>mail
        echo "TIMES_ENCOUNTERED     ERROR">>mail
        echo "">>mail
        cat uniqerr >>mail #unique errors and times each appeared
        echo "<------------------------------------------------------>">>mail
        #After this we add all errors so user can see all the data
        echo "ALL ERRORS:">>mail
        echo "">>mail
        cat err>>mail #Add all errors with timestamps
        ssmtp $receiver <mail
        #We will also save logs after every succesful run
        echo "$now : Error encountered with storjNode" >> storjMailAlertlogs
        rm out err uniqerr mail #remove files we no longer need
else
        #Node is running fine
        echo "$now : No errors encountered" >> storjMailAlertlogs
fi

#Uncomment this line if you don't want to save script outputs
#rm -f out err storjMailAlertlogs
