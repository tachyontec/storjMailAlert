storjMailAlert
===

Simple script to send email alert to node operator, when the node exceed the specified error percentage limit.

Requirements
===
<ol>
  <li>Configured ssmtp server</li>
  <li>Crontab installed</li>
</ol>

Permissions
===

When running the setup you need to have permission to:
<ol>
  <li>docker logs</li>
  <li>crontab</li>
</ol>

Installation and setup
===

#### First you need to clone the repository and move into the folder.
```sh
$ git clone https://github.com/tachyontec/storjMailAlert
$ cd storjMailAlert
```
#### Then we will need to make the setup script excecutable and run it
```sh
$ chmod +x setup.sh
$ sudo ./setup.sh
```

Scripts to be used
===

<ol>
  <li> <h4>setup.sh</h4>
  <p>Only needs to be run first time downloading the repo but it can also be run to update our parameteres</p>
    <p>Creates the command storjMailAlert and</p>
  <p>Runs addCron</p> </li>

  <li> <h4>addCron</h4>
    <p>Takes update interval as $1</p>
    <p>It creates a crontab task to excecute storjMailAlert every $1 minutes </p></li>

  <li> <h4>storjMailAlert</h4>
    <p>aka main script</p>
    <p>Creates a directory in which it runs the checks and saves output in a logs file</p>
    <p>By default it doesn't delete logs but you can uncomment the last line </p>
    <p>OR manually find and delete them at ~/storjAlerts</p>
  </li>
</ol>
<br>
+Note that this script will be using the directory ~storjAlerts where it will be saving outputs 
<p>If you don't want to save any output uncomment last line on the main script (storjMailAlert)
