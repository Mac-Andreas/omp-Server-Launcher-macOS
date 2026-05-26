increase button size of restart, fix the button as well, it looks like a circle 
reduce size of open log.txt

move the app from c++ or something to macos native swift or something and run from there

modernise the config, license and all, like total rebuild with modernise design

start server, stop server, restart server add buton open server folder and also add button to launch open.mp multiplyer

the logs - > reduce size of timestamp

decrease fontsize a bit, provide option of cmd + to increase fontsize in log, cmd - to decrease and cmd 0 to reset default, server log title to have icon with it

logs to be saved as snapshot after each run and hidden in .server_launcher in the directory with a copy in /libarary/app sppo and etc, add tab of view logs - it will list down all with snapshot 1,2,3,4,56 (right align date dd-mm-yyyy and time tt:mm when it created (when server closed))


make sure the re-made app is optimised to the max and efficient so that people with poor hardware can run it as well

version to be v1.0

in footer - made with (heart- no emoji) by Mac Andreas Team | <github icon> repository https://github.com/Mac-Andreas/open.mp-Server-Launcher-macOS | v1.0 (Update Available - <version> from github)

introduce in-app-update which will download and show update available - install once downoaded,  put it next to version pill on top right and show in footer as well), do a ticker of checking once per day gmt 0, once user to install, install the update - show popup that this update requires app to be restarted, continue? add a toggle option in the pop up - start my server after update, if toggled yes then - if user say yes continue to close server (hold 5 seconds on button to confirm) then stop the server and show popup of installing with progress bar and % complete, once done, close app and restart and start the server if user toggled it

config to show config json not detected in folder if it is not available and not show anything of config editing fields (this will be modernised anyway - you have to see what are the limits of each, what can be a drop down, what can be a slider (with max limitt) - also do not let my cursor on number field to scroll to increase or decrese number, also no negative numbers unless specifically allowed (research)

some examples- filterscripts and gamemodes can be a dropdown of available files; max players can be 1k ig in same, unless open.mp bypassed it so it can be a slider? with number box on right side in case someone want to type the number; password to be Server Password renamed (only in app) if it is putting password on server - if you want you can add sub mini tabs for each section as well - as you find suitable then you can add a tab of cron jobs - list all the cron jobs that a hosting provider gives or that can be done with field to put number, at the end provide a custom cron job option (if it can do that - it should be doable else throw error of what is wrong)

put guard rails on input boxes ig along with cron jobs? so it can't be hacked? (if any you see is avaialble)