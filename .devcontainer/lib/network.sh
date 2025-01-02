#!/bin/bash

# https://stackoverflow.com/a/58510109/3535783
[ -n "${NETWORK_LIB_IMPORTED}" ] && return; NETWORK_LIB_IMPORTED=0; # pragma once

_ip4hex2dec () {
  local ip4_1octet="0x${1%???????????}"

  local ip4_2octet="${1%?????????}"
  ip4_2octet="0x${ip4_2octet#??}"

  local ip4_3octet="${1%???????}"
  ip4_3octet="0x${ip4_3octet#????}"

  local ip4_4octet="${1%?????}"
  ip4_4octet="0x${ip4_4octet#??????}"

  local ip4_port="0x${1##*:}"

  # if not used inverse
  #printf "%d.%d.%d.%d:%d" "$ip4_1octet" "$ip4_2octet" "$ip4_3octet" "$ip4_4octet" "$ip4_port"
  printf "%d.%d.%d.%d:%d" "$ip4_4octet" "$ip4_3octet" "$ip4_2octet" "$ip4_1octet" "$ip4_port"
}


# reoder bytes, byte4 is byte1 byte2 is byte3 ...
_reorderByte(){
  if [ ${#1} -ne 8 ]; then echo "missuse of function _reorderByte"; exit; fi

  local byte1="${1%??????}"

  local byte2="${1%????}"
  byte2="${byte2#??}"

  local byte3="${1%??}"
  byte3="${byte3#????}"

  local byte4="${1#??????}"

  echo "$byte4$byte3:$byte2$byte1"
}

# on normal intel platform the byte order of the ipv6 address in /proc/net/*6 has to be reordered.
_ip6hex2dec(){
  local ip_str="${1%%:*}"
  local ip6_port="0x${1##*:}"
  local ipv6="$(_reorderByte ${ip_str%????????????????????????})"
  local shiftmask="${ip_str%????????????????}"
  ipv6="$ipv6:$(_reorderByte ${shiftmask#????????})"
  shiftmask="${ip_str%????????}"
  ipv6="$ipv6:$(_reorderByte ${shiftmask#????????????????})"
  ipv6="$ipv6:$(_reorderByte ${ip_str#????????????????????????})"
  ipv6=$(echo $ipv6 | awk '{ gsub(/(:0{1,3}|^0{1,3})/, ":"); sub(/(:0)+:/, "::");print}')
  printf "%s:%d" "$ipv6" "$ip6_port"
}

# prints all open ports from /proc/net/*
# see: https://github.com/wofwofwof/pentest_scripts/tree/master
showOpenPorts() {
  # set "-c" parameter to include the command in the output
  [[ "$*" =~ ^-c$ ]] && showCommand=true

  for protocol in tcp tcp6 udp udp6 raw raw6;
  do
    #echo "protocol $protocol" ;
    for ipportinode in `cat /proc/net/$protocol | awk '/.*:.*:.*/{print $2"|"$3"|"$10 ;}'` ;
    do
      #echo "#ipportinode=$ipportinode"
      inode=${ipportinode##*|}
      if [ "#$inode" = "#" ] ; then continue ; fi

      lspid=`ls -l /proc/*/fd/* 2>/dev/null | grep "socket:\[$inode\]" 2>/dev/null` ;
      pids=`echo "$lspid" | awk 'BEGIN{FS="/"} /socket/{pids[$3]} END{for (pid in pids) {print pid;}}'` ; # removes duplicats for this pid
      #echo "#lspid:$lspid  #pids:$pids"

      for pid in $pids; do
        if [ "#$pid" = "#" ] ; then continue ; fi
        exefile=`ls -l /proc/$pid/exe | awk 'BEGIN{FS=" -> "}/->/{print $2;}'`;
        # only read the command if we are going to inclue it in the output
        [[ -n $showCommand ]] && cmdline=`tr -d '\0' < /proc/$pid/cmdline`

        local_adr_hex=${ipportinode%%|*}
        remote_adr_hex=${ipportinode#*|}
        remote_adr_hex=${remote_adr_hex%%|*}

        if [ "#${protocol#???}" = "#6" ]; then
          local_adr=$(_ip6hex2dec $local_adr_hex)
          remote_adr=$(_ip6hex2dec $remote_adr_hex)
        else
          local_adr=$(_ip4hex2dec $local_adr_hex)
          remote_adr=$(_ip4hex2dec $remote_adr_hex)
        fi

        echo -e "$protocol\t pid:$pid\t $local_adr\t $remote_adr\t inode:$inode\t $exefile $cmdline"
      done
    done
  done
}

_hexToInt() {
    printf -v $1 "%d\n" 0x${2:6:2}${2:4:2}${2:2:2}${2:0:2}
}
_intToIp() {
    local var=$1 iIp
    shift
    for iIp ;do 
        printf -v $var "%s %s.%s.%s.%s" "${!var}" $(($iIp>>24)) \
            $(($iIp>>16&255)) $(($iIp>>8&255)) $(($iIp&255))
    done
}
_maskLen() {
    local i
    for ((i=0; i<32 && ( 1 & $2 >> (31-i) ) ;i++));do :;done
    printf -v $1 "%d" $i
}

# prints network info for all network interfaces
# see: https://stackoverflow.com/a/14725655/3535783
showNetworks() {
  while read -a rtLine ;do
    if [ ${rtLine[2]} == "00000000" ] && [ ${rtLine[7]} != "00000000" ] ;then
      _hexToInt netInt  ${rtLine[1]}
      _hexToInt maskInt ${rtLine[7]}
      if [ $((netInt&maskInt)) == $netInt ] ;then
        for procConnList in /proc/net/{tcp,udp} ;do
          while IFS=': \t\n' read -a conLine ;do
            if [[ ${conLine[1]} =~ ^[0-9a-fA-F]*$ ]] ;then
              _hexToInt ipInt ${conLine[1]}
              [ $((ipInt&maskInt)) == $netInt ] && break 3
            fi
          done < $procConnList
        done
      fi
    elif [ ${rtLine[1]} == "00000000" ] && [ ${rtLine[7]} == "00000000" ] ;then
      _hexToInt netGw ${rtLine[2]}
    fi
  done < /proc/net/route

  _maskLen maskBits $maskInt
  _intToIp addrLine $ipInt $netInt $netGw $maskInt
  printf -v outForm '%-12s: %%s\\n' \
    Interface Address Network Gateway Netmask MaskLen
  printf "$outForm" $rtLine $addrLine $maskBits\ bits
}

showIP() {
  echo "$(hostname -I)"
}

showPublicIP() {
  echo "$(curl -s ifconfig.me)"
}

# Check if the we received an existing function name as argument and execute it
[[ $(type -t $1) == function ]] && $@
