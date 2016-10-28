<pre>
#            __   __                     
#      |\/| /  \ /__` |__|               
#      |  | \__X .__/ |  |               
#                                        
###############################################
# https://github.com/isdrupter/busybotnet #
###############################################
# Asynchronous, Remote MQTT Driven Shell API
#
#
</pre>
=======
# MqShell
## An Asynchronous, Remote, and MQTT Driven Shell with a Json API

Mqshell (or "mqsh", or simply "mq") is an interactive remote shell written in the bash shell. Commands are run <br>
asynchrously, each in a seperate child process to prevent lockups. It is designed to run on embededd, or busybox=based 
systems, and also to be as posix-compliant as possible, ie, it should run on just about any modern unix system. 


## Requirements:
- Jshon
- Some Coreutils applications like echo, a shell with printf, base64, head, sed, grep, sleep, sha1sum, md5sum, etc
- mosquitto_sub/pub (pubclient/subclient)
- An http server to host the mq-funx files. This is for easy, dynamic, remote updates.
- An mqtt server. I prefer [mosca](https://github.com/mcollina/mosca)
- A **lot** of patience

## Why? 

Because I suck at writing C. And because sometimes you have no choice but to make something work in the shell. <br>
But mostly because the shell is awesome, extreemely powerful, and often under-rated. 
