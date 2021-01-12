#!/usr/bin/env bash
#
# A HomeMatic script which can be regularly executed (e.g. via cron on a separate
# Linux system) and queries a CalDAV calendar.
#
# This script can be found at https://github.com/H2CK/hm_caldav
#
# The script will set several system variables for the current status of the
# meetings in the calendar. The events are selected by the summary.
#
# Copyright (C) 2018-2020 Thorsten Jagel <dev@jagel.net>
#
# This script is based on similar functionality:
#
# https://github.com/jens-maus/hm_pdetect
#

VERSION="0.5"
VERSION_DATE="Jan 19 2020"

#####################################################
# Main script starts here, don't modify from here on

# before we read in default values we have to find
# out which HM_* variables the user might have specified
# on the command-line himself
USERVARS=$(set -o posix; set | grep "HM_.*=" 2>/dev/null)

# URL of valdav calendar
HM_CALDAV_URL=${HM_CALDAV_URL:-"http://localhost/calendar.ics"}

# IP address/hostname of CCU2
HM_CCU_IP=${HM_CCU_IP:-"homematic-raspi"}

# Port settings for ReGa communications
HM_CCU_REGAPORT=${HM_CCU_REGAPORT:-"8181"}

# Name of the CCU variable prefix used
HM_CCU_CALDAV_VAR=${HM_CCU_CALDAV_VAR:-"Calendar"}

# download interval of calendar (in minutes) - new file will be fetched when last download is older than x minutes
HM_DOWNLOAD_INTERVAL=${HM_DOWNLOAD_INTERVAL:-1440}

# number of seconds to wait between iterations
# (will run hm_caldav in an endless loop)
HM_INTERVAL_TIME=${HM_INTERVAL_TIME:-}

# maximum number of iterations if running in interval mode
# (default: 0=unlimited)
HM_INTERVAL_MAX=${HM_INTERVAL_MAX:-0}

#where the caldav calendar is cached
HM_CALDAV_FILE=${HM_CALDAV_FILE:-"/tmp/hm_caldav.ics"}

# where to save the process ID in case hm_caldav runs as
# a daemon
HM_DAEMON_PIDFILE=${HM_DAEMON_PIDFILE:-"/var/run/hm_caldav.pid"}

# Processing logfile output name
# (default: no output)
HM_PROCESSLOG_FILE=${HM_PROCESSLOG_FILE:-}

# maximum number of lines the logfile should contain
# (default: 500 lines)
HM_PROCESSLOG_MAXLINES=${HM_PROCESSLOG_MAXLINES:-500}

# used names within variables
HM_CCU_EVENT_ACTIVE=${HM_CCU_EVENT_ACTIVE:-"active"}
HM_CCU_EVENT_INACTIVE=${HM_CCU_EVENT_INACTIVE:-"inactive"}

# the config file path
# (default: 'hm_caldav.conf' in path where hm_caldav.sh script resists)
CONFIG_FILE=${CONFIG_FILE:-"$(cd "${0%/*}"; pwd)/hm_caldav.conf"}

AWK_FILE=${AWK_FILE:-"$(cd "${0%/*}"; pwd)/ics.awk"}

# global return status variables
RETURN_FAILURE=1
RETURN_FAILURE_AWK=2
RETURN_SUCCESS=0

###############################
# now we check all dependencies first. That means we
# check that we have the right bash version and third-party tools
# installed
#

# bash check
if [[ $(echo ${BASH_VERSION} | cut -d. -f1) -lt 4 ]]; then
  echo "ERROR: this script requires a bash shell of version 4 or higher. Please install."
  exit ${RETURN_FAILURE}
fi

# wget check
if [[ ! -x $(which wget) ]]; then
  echo "ERROR: 'wget' tool missing. Please install."
  exit ${RETURN_FAILURE}
fi

# iconv check
if [[ ! -x $(which awk) ]]; then
  echo "ERROR: 'iconv' tool missing. Please install."
  exit ${RETURN_FAILURE}
fi

# md5sum check
if [[ ! -x $(which md5sum) ]]; then
  echo "ERROR: 'md5sum' tool missing. Please install."
  exit ${RETURN_FAILURE}
fi

# declare associative arrays first (bash v4+ required)
declare -A HM_EVENT_VAR_MAPPING_LIST     # VarName<>EventName tuple
unset HM_EVENT_STATUS_LIST
declare -A HM_EVENT_STATUS_LIST

###############################
# lets check if config file was specified as a cmdline arg
if [[ ${#} -gt 0        && \
      ${!#} != "child"  && \
      ${!#} != "daemon" && \
      ${!#} != "start"  && \
      ${!#} != "stop" ]]; then
  CONFIG_FILE="${!#}"
fi

if [[ ! -e ${CONFIG_FILE} ]]; then
  echo "WARNING: config file '${CONFIG_FILE}' doesn't exist. Using default values."
  CONFIG_FILE=
fi

# lets source the config file a first time
if [[ -n ${CONFIG_FILE} ]]; then
  source "${CONFIG_FILE}"
  if [[ $? -ne 0 ]]; then
    echo "ERROR: couldn't source config file '${CONFIG_FILE}'. Please check config file syntax."
    exit ${RETURN_FAILURE}
  fi

  # lets eval the user overridden variables
  # so that they take priority
  eval ${USERVARS}
fi

###############################
# run hm_caldav as a real daemon by using setsid
# to fork and deattach it from a terminal.
PROCESS_MODE=normal
if [[ ${#} -gt 0 ]]; then
  FILE=${0##*/}
  DIR=$(cd "${0%/*}"; pwd)

  # lets check the supplied command
  case "${1}" in

    start) # 1. lets start the child
      shift
      exec "${DIR}/${FILE}" child "${CONFIG_FILE}" &
      exit 0
    ;;

    child) # 2. We are the child. We need to fork the daemon now
      shift
      umask 0
      echo
      echo "Starting hm_caldav in daemon mode."
      exec setsid ${DIR}/${FILE} daemon "${CONFIG_FILE}" </dev/null >/dev/null 2>/dev/null &
      exit 0
    ;;

    daemon) # 3. We are the daemon. Lets continue with the real stuff
      shift
      # save the PID number in the specified PIDFILE so that we 
      # can kill it later on using this file
      if [[ -n ${HM_DAEMON_PIDFILE} ]]; then
        echo $$ >${HM_DAEMON_PIDFILE}
      fi

      # if we end up here we are in daemon mode and
      # can continue normally but make sure we don't allow any
      # input
      exec 0</dev/null

      # make sure PROCESS_MODE is set to daemon
      PROCESS_MODE=daemon
    ;;

    stop) # 4. stop the daemon if requested
      if [[ -f ${HM_DAEMON_PIDFILE} ]]; then
        echo "Stopping hm_caldav (pid: $(cat ${HM_DAEMON_PIDFILE}))"
        kill $(cat ${HM_DAEMON_PIDFILE}) >/dev/null 2>&1
        rm -f ${HM_DAEMON_PIDFILE} >/dev/null 2>&1
        rm -f ${HM_CALDAV_FILE} >/dev/null 2>&1
      fi
      exit 0
    ;;

  esac
fi
 
###############################
# function returning the current state of a homematic variable
# and returning success/failure if the variable was found/not
function getVariableState()
{
  local name="$1"

  local result=$(wget -q -O - "http://${HM_CCU_IP}:${HM_CCU_REGAPORT}/rega.exe?state=dom.GetObject(ID_SYSTEM_VARIABLES).Get('${name}').Value()")
  if [[ ${result} =~ \<state\>(.*)\</state\> ]]; then
    result="${BASH_REMATCH[1]}"
    if [[ ${result} != "null" ]]; then
      echo ${result}
      return ${RETURN_SUCCESS}
    fi
  fi

  echo ${result}
  return ${RETURN_FAILURE}
}

# function setting the state of a homematic variable in case it
# it different to the current state and the variable exists
function setVariableState()
{
  local name="$1"
  local newstate="$2"

  # before we going to set the variable state we
  # query the current state and if the variable exists or not
  curstate=$(getVariableState "${name}")
  if [[ ${curstate} == "null" ]]; then
    return ${RETURN_FAILURE}
  fi

  # only continue if the current state is different to the new state
  if [[ ${curstate} == ${newstate//\'} ]]; then
    return ${RETURN_SUCCESS}
  fi

  # the variable should be set to a new state, so lets do it
  echo -n "  Setting CCU variable '${name}': '${newstate//\'}'... "
  local result=$(wget -q -O - "http://${HM_CCU_IP}:${HM_CCU_REGAPORT}/rega.exe?state=dom.GetObject(ID_SYSTEM_VARIABLES).Get('${name}').State(${newstate})")
  if [[ ${result} =~ \<state\>(.*)\</state\> ]]; then
    result="${BASH_REMATCH[1]}"
  else
    result=""
  fi

  # if setting the variable succeeded the result will be always
  # 'true'
  if [[ ${result} == "true" ]]; then
    echo "ok."
    return ${RETURN_SUCCESS}
  fi

  echo "ERROR."
  return ${RETURN_FAILURE}
}

# function to check if a certain boolean system variable exists
# at a CCU and if not creates it accordingly
function createVariable()
{
  local vaname=$1
  local vatype=$2
  local comment=$3
  local valist=$4

  # first we find out if the variable already exists and if
  # the value name/list it contains matches the value name/list
  # we are expecting
  local postbody=""
  if [[ ${vatype} == "enum" ]]; then
    local result=$(wget -q -O - "http://${HM_CCU_IP}:${HM_CCU_REGAPORT}/rega.exe?valueList=dom.GetObject(ID_SYSTEM_VARIABLES).Get('${vaname}').ValueList()")
    if [[ ${result} =~ \<valueList\>(.*)\</valueList\> ]]; then
      result="${BASH_REMATCH[1]}"
    fi

    # make sure result is not empty and not null
    if [[ -n ${result} && ${result} != "null" ]]; then
      if [[ ${result} != ${valist} ]]; then
        echo -n "  Modifying CCU variable '${vaname}' (${vatype})... "
        postbody="string v='${vaname}';dom.GetObject(ID_SYSTEM_VARIABLES).Get(v).ValueList('${valist}')"
      fi
    else
      echo -n "  Creating CCU variable '${vaname}' (${vatype})... "
      postbody="string v='${vaname}';boolean f=true;string i;foreach(i,dom.GetObject(ID_SYSTEM_VARIABLES).EnumUsedIDs()){if(v==dom.GetObject(i).Name()){f=false;}};if(f){object s=dom.GetObject(ID_SYSTEM_VARIABLES);object n=dom.CreateObject(OT_VARDP);n.Name(v);s.Add(n.ID());n.ValueType(ivtInteger);n.ValueSubType(istEnum);n.DPInfo('${comment}');n.ValueList('${valist}');n.State(0);dom.RTUpdate(false);}"
    fi
  elif [[ ${vatype} == "string" ]]; then
    getVariableState "${vaname}" >/dev/null
    if [[ $? -eq 1 ]]; then
      echo -n "  Creating CCU variable '${vaname}' (${vatype})... "
      postbody="string v='${vaname}';boolean f=true;string i;foreach(i,dom.GetObject(ID_SYSTEM_VARIABLES).EnumUsedIDs()){if(v==dom.GetObject(i).Name()){f=false;}};if(f){object s=dom.GetObject(ID_SYSTEM_VARIABLES);object n=dom.CreateObject(OT_VARDP);n.Name(v);s.Add(n.ID());n.ValueType(ivtString);n.ValueSubType(istChar8859);n.DPInfo('${comment}');n.State('');dom.RTUpdate(false);}"
    fi
  elif [[ ${vatype} == "integer" ]]; then
    getVariableState "${vaname}" >/dev/null
    if [[ $? -eq 1 ]]; then
      echo -n "  Creating CCU variable '${vaname}' (${vatype})... "
      postbody="string v='${vaname}';boolean f=true;string i;foreach(i,dom.GetObject(ID_SYSTEM_VARIABLES).EnumUsedIDs()){if(v==dom.GetObject(i).Name()){f=false;}};if(f){object s=dom.GetObject(ID_SYSTEM_VARIABLES);object n=dom.CreateObject(OT_VARDP);n.Name(v);s.Add(n.ID());n.ValueType(ivtInteger);n.ValueSubType(istGeneric);n.ValueMin(0);n.ValueMax(65000);n.DPInfo('${comment}');n.State('');dom.RTUpdate(false);}"
    fi
  else
    local result=$(wget -q -O - "http://${HM_CCU_IP}:${HM_CCU_REGAPORT}/rega.exe?valueName0=dom.GetObject(ID_SYSTEM_VARIABLES).Get('${vaname}').ValueName0()&valueName1=dom.GetObject(ID_SYSTEM_VARIABLES).Get('${vaname}').ValueName1()")
    local valueName0="null"
    local valueName1="null"
    if [[ ${result} =~ \<valueName0\>(.*)\</valueName0\>\<valueName1\>(.*)\</valueName1\> ]]; then
      valueName0="${BASH_REMATCH[1]}"
      valueName1="${BASH_REMATCH[2]}"
    fi

    # make sure result is not empty and not null
    if [[ -n ${result} && \
          ${valueName0} != "null" && ${valueName1} != "null" ]]; then

       if [[ ${valueName0} != ${HM_CCU_EVENT_INACTIVE} || \
             ${valueName1} != ${HM_CCU_EVENT_ACTIVE} ]]; then
         echo -n "  Modifying CCU variable '${vaname}' (${vatype})... "
         postbody="string v='${vaname}';dom.GetObject(ID_SYSTEM_VARIABLES).Get(v).ValueName0('${HM_CCU_EVENT_INACTIVE}');dom.GetObject(ID_SYSTEM_VARIABLES).Get(v).ValueName1('${HM_CCU_EVENT_ACTIVE}')"
       fi
    else
      echo -n "  Creating CCU variable '${vaname}' (${vatype})... "
      postbody="string v='${vaname}';boolean f=true;string i;foreach(i,dom.GetObject(ID_SYSTEM_VARIABLES).EnumUsedIDs()){if(v==dom.GetObject(i).Name()){f=false;}};if(f){object s=dom.GetObject(ID_SYSTEM_VARIABLES);object n=dom.CreateObject(OT_VARDP);n.Name(v);s.Add(n.ID());n.ValueType(ivtBinary);n.ValueSubType(istBool);n.DPInfo('${comment}');n.ValueName1('${HM_CCU_EVENT_ACTIVE}');n.ValueName0('${HM_CCU_EVENT_INACTIVE}');n.State(false);dom.RTUpdate(false);}"
    fi
  fi

  # if postbody is empty there is nothing to do
  # and the variable exists with correct value name/list
  if [[ -z ${postbody} ]]; then
    return ${RETURN_SUCCESS}
  fi

  # use wget to post the tcl script to tclrega.exe
  local result=$(wget -q -O - --post-data "${postbody}" "http://${HM_CCU_IP}:${HM_CCU_REGAPORT}/tclrega.exe")
  if [[ ${result} =~ \<v\>${vaname}\</v\> ]]; then
    echo "ok."
    return ${RETURN_SUCCESS}
  else
    echo "ERROR: could not create system variable '${vaname}'."
    return ${RETURN_FAILURE}
  fi
}

# function that logs into a caldav server and download the caldav file based on the file the events are parsed
function retrieveCalDavInfo()
{
  local ip=$1
  local user=$2
  local secret=$3
  local uri=${ip}

  # check if "ip" starts with a "http(s)://" URL scheme
  # identifier or if we have to add it ourself
  if [[ ! ${ip} =~ ^http(s)?:\/\/ ]]; then
    uri="http://${ip}"
  fi
  
  #check if locally available version of caldav (is it out of date? if yes, delete the file)
  if [ -f ${HM_CALDAV_FILE} ]; then
    HM_CALDAV_DIR=${HM_CALDAV_FILE%/*}
    HM_CALDAV_F=${HM_CALDAV_FILE##*/}
    find ${HM_CALDAV_DIR} -maxdepth 1 -name ${HM_CALDAV_F} -type f -mmin +${HM_DOWNLOAD_INTERVAL} -exec rm {} \;
  fi
  
  #check if locally available version of caldav is available
  if [ ! -f ${HM_CALDAV_FILE} ]; then
    echo "Requesting caldav data from server ..."
    # retrieve the ics file from the caldav server
    data=$(wget -q -O - --max-redirect=0 --no-check-certificate --user="${user}" --password="${secret}" "${uri}")
    if [[ $? -ne 0 || -z ${data} ]]; then
      return ${RETURN_FAILURE}
    fi
    printf "%s" "${data}" > ${HM_CALDAV_FILE}
    #Optimize ics file to relevant events using awk - necessary for performance reasons
    re_names=""
    first=true
    for sysVariable in "${!HM_EVENT_VAR_MAPPING_LIST[@]}"; do
      if [ "$first" = true ]; then
        first=false
        re_names="${HM_EVENT_VAR_MAPPING_LIST[${sysVariable}]}"
      else
        re_names+="|${HM_EVENT_VAR_MAPPING_LIST[${sysVariable}]}"
      fi
    done
    
    awk -v NAME="${re_names}" -f ${AWK_FILE} ${HM_CALDAV_FILE} > /tmp/hm_caldav.tmp && rm -f ${HM_CALDAV_FILE} && mv /tmp/hm_caldav.tmp ${HM_CALDAV_FILE}
    if [[ $? -ne 0 ]]; then
      return ${RETURN_FAILURE_AWK}
    fi
  fi
  
  # read exiting file
  data=$(<${HM_CALDAV_FILE})  
  #echo "CalDav data:"
  #printf "%s\n" "${data}"
  
  # initialize associative array
  for sysVariable in "${!HM_EVENT_VAR_MAPPING_LIST[@]}"; do
    createVariable "${HM_CCU_CALDAV_VAR}.${sysVariable}" bool "Event: ${HM_EVENT_VAR_MAPPING_LIST[${sysVariable}]}"
    createVariable "${HM_CCU_CALDAV_VAR}.${sysVariable}-TODAY" bool "Event: ${HM_EVENT_VAR_MAPPING_LIST[${sysVariable}]}-TODAY"
    createVariable "${HM_CCU_CALDAV_VAR}.${sysVariable}-TOMORROW" bool "Event: ${HM_EVENT_VAR_MAPPING_LIST[${sysVariable}]}-TOMORROW"
    HM_EVENT_STATUS_LIST[$sysVariable]="inactive"
    HM_EVENT_STATUS_LIST["$sysVariable-TODAY"]="inactive"
    HM_EVENT_STATUS_LIST["$sysVariable-TOMORROW"]="inactive"
  done
  
  # analyse caldav
  STARTFLAG="false"
  local re_event_start="^BEGIN\:VEVENT.*"
  local re_event_stop="^END\:VEVENT.*"
  local re_event_summary="^SUMMARY\:(.*)"
  local re_event_start_date="^DTSTART\:([0-9]+)"
  local re_event_start_time="^DTSTART\:([0-9]+)T([0-9]+)"
  local re_event_stop_date="^DTEND\:([0-9]+)"
  local re_event_stop_time="^DTEND\:([0-9]+)T([0-9]+)"
  
  local summary=""
  local start_date="20000101"
  local start_time="000000"
  local stop_date="20000101"
  local stop_time="000000"
  
  while IFS= read -r line
  do
   if [ $STARTFLAG == "true" ]; then
            if [[ $line =~ $re_event_stop ]]; then
                    #find variable name for event summary
                    curVariable=""
                    for sysVariable in "${!HM_EVENT_VAR_MAPPING_LIST[@]}"; do
                      if [[ $summary =~ ${HM_EVENT_VAR_MAPPING_LIST[${sysVariable}]} ]]; then
                        curVariable=$sysVariable
                        break
                      fi
                    done
                    
                    #check if event matters at this time
                    curr_datetime="$(date +'+%Y%m%d%H%M%S')"
                    start_datetime="$start_date$start_time"
                    stop_datetime="$stop_date$stop_time"
                    if [ $curr_datetime -ge $start_datetime ] && [ $stop_datetime -ge $curr_datetime ]; then
                      printf "Ongoning event: %s" "$summary"
                      printf " from: %s" "$start_date" 
                      printf " T: %s" "$start_time"
                      printf " until: %s" "$stop_date" 
                      printf " T: %s\n" "$stop_time"
                      
                      HM_EVENT_STATUS_LIST[$curVariable]="active"
                    fi

                    #check if event is active today
                    today_date="$(date +'+%Y%m%d')"
                    if [ $stop_date -ge $tomorrow_date ] && [ $start_date -le $tomorrow_date ]; then
                      printf "Today event: %s" "$summary"
                      printf " from: %s" "$start_date" 
                      printf " T: %s" "$start_time"
                      printf " until: %s" "$stop_date" 
                      printf " T: %s\n" "$stop_time"
                      
                      HM_EVENT_STATUS_LIST["$curVariable-TODAY"]="active"
                    fi

                    #check if event is active tomorrow
                    tomorrow_date="$(date -v+1d +'+%Y%m%d')"
                    if [ $stop_date -ge $tomorrow_date ] && [ $start_date -le $tomorrow_date ]; then
                      printf "Tomorrow event: %s" "$summary"
                      printf " from: %s" "$start_date" 
                      printf " T: %s" "$start_time"
                      printf " until: %s" "$stop_date" 
                      printf " T: %s\n" "$stop_time"
                      
                      HM_EVENT_STATUS_LIST["$curVariable-TOMORROW"]="active"
                    fi
                    
                    # Reset parameters for further scan
                    STARTFLAG="false"
                    summary=""
                    start_date="20000101"
                    start_time="000000"
                    stop_date="20000101"
                    stop_time="000000"
                    continue
            else
                    if [[ $line =~ $re_event_summary ]]; then
                      summary="${BASH_REMATCH[1]}"
                    fi
                    if [[ $line =~ $re_event_start_date ]]; then
                      start_date="${BASH_REMATCH[1]}"
                    fi
                    if [[ $line =~ $re_event_start_time ]]; then
                      start_time="${BASH_REMATCH[2]}"
                    fi
                    if [[ $line =~ $re_event_stop_date ]]; then
                      stop_date="${BASH_REMATCH[1]}"
                    fi
                    if [[ $line =~ $re_event_stop_time ]]; then
                      stop_time="${BASH_REMATCH[2]}"
                    fi
                    continue
            fi
    elif [[ $line =~ $re_event_start ]]; then
            STARTFLAG="true"
            continue
    fi
  done <<<"$data"
  
  # set CCU system variables based on associative array
  for sysVariable in "${!HM_EVENT_STATUS_LIST[@]}"; do
    #echo -n "$sysVariable:"
    #echo "${HM_EVENT_STATUS_LIST[${sysVariable}]}"
    if [ "${HM_EVENT_STATUS_LIST[${sysVariable}]}" = "active" ]; then
      setVariableState "${HM_CCU_CALDAV_VAR}.${sysVariable}" "true"
    else
      setVariableState "${HM_CCU_CALDAV_VAR}.${sysVariable}" "false"
    fi
  done
  
  echo "Finished processing."
  
  return ${RETURN_SUCCESS}
}

function run_caldav()
{
  # output time/date of execution
  echo "== $(date) ==================================="

  echo -n "Processing CalDav:"
  i=0
  for ip in ${HM_CALDAV_URL[@]}; do
    echo " ${ip}"
    retrieveCalDavInfo ${ip} "${HM_CALDAV_USER}" "${HM_CALDAV_SECRET}"
    if [[ $? -eq 0 ]]; then
      ((i = i + 1))
    fi
  done
  
  # check that we were able to connect to at least one device
  if [[ ${i} -eq 0 ]]; then
    echo "ERROR: couldn't connect or process data"
    return ${RETURN_FAILURE}
  fi
  
  echo "== $(date) ==================================="
  echo
  
  return ${RETURN_SUCCESS}
}

################################################
# main processing starts here
#
echo "hm_caldav ${VERSION} - a HomeMatic script to query current events from a caldav server"
echo "(${VERSION_DATE}) Copyright (C) 2018-2020 Thorsten Jagel <dev@jagel.net>"
echo

# lets enter an endless loop to implement a
# daemon-like behaviour
result=-1
iteration=0
while true; do

  # lets source the config file again
  if [[ -n ${CONFIG_FILE} ]]; then
    source "${CONFIG_FILE}"
    if [[ $? -ne 0 ]]; then
      echo "ERROR: couldn't source config file '${CONFIG_FILE}'. Please check config file syntax."
      result=${RETURN_FAILURE}
    fi

    # lets eval the user overridden variables
    # so that they take priority
    eval ${USERVARS}
  fi

  # lets wait until the next execution round in case
  # the user wants to run it as a daemon
  if [[ ${result} -ge 0 ]]; then
    ((iteration = iteration + 1))
    if [[ -n ${HM_INTERVAL_TIME}    && \
          ${HM_INTERVAL_TIME} -gt 0 && \
          ( -z ${HM_INTERVAL_MAX} || ${HM_INTERVAL_MAX} -eq 0 || ${iteration} -lt ${HM_INTERVAL_MAX} ) ]]; then
      sleep ${HM_INTERVAL_TIME}
      if [[ $? -eq 1 ]]; then
        result=${RETURN_FAILURE}
        break
      fi
    else 
      break
    fi
  fi

  # perform one hm_caldav run and in case we are running in daemon
  # mode and having the processlogfile enabled output to the logfile instead.
  if [[ -n ${HM_PROCESSLOG_FILE} ]]; then
    output=$(run_caldav)
    result=$?
    echo "${output}" | cat - ${HM_PROCESSLOG_FILE} | head -n ${HM_PROCESSLOG_MAXLINES} >/tmp/hm_caldav-$$.tmp && mv /tmp/hm_caldav-$$.tmp ${HM_PROCESSLOG_FILE}
  else
    # run caldav with normal stdout processing
    run_caldav
    result=$?
  fi

done

exit ${result}
