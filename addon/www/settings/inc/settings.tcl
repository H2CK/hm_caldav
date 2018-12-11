set ADDONNAME "hm_caldav"
set FILENAME "/usr/local/addons/hm_caldav/etc/hm_caldav.conf"

array set args { command INV HM_CALDAV_URL {} HM_CALDAV_USER {} HM_CALDAV_SECRET {} HM_CCU_CALDAV_VAR {} HM_CCU_EVENT_ACTIVE {} HM_CCU_EVENT_INACTIVE {} HM_DOWNLOAD_INTERVAL {} HM_INTERVAL_TIME {} HM_EVENT_VAR_MAPPING_LIST {} }

proc utf8 {hex} {
    set hex [string map {% {}} $hex]
    return [encoding convertfrom utf-8 [binary format H* $hex]]
}

proc url-decode str {
    # rewrite "+" back to space
    # protect \ from quoting another '\'
    set str [string map [list + { } "\\" "\\\\" "\[" "\\\["] $str]

    # Replace UTF-8 sequences with calls to the utf8 decode proc...
    regsub -all {(%[0-9A-Fa-f0-9]{2})+} $str {[utf8 \0]} str

    # process \u unicode mapped chars and trim whitespaces
    return [string trim [subst -novar  $str]]
}

proc str-escape str {
    set str [string map -nocase { 
              "\"" "\\\""
              "\$" "\\\$"
              "\\" "\\\\"
              "`"  "\\`"
             } $str]

    return $str
}

proc str-unescape str {
    set str [string map -nocase { 
              "\\\"" "\""
              "\\\$" "\$"
              "\\\\" "\\"
              "\\`"  "`"
             } $str]

    return $str
}


proc parseQuery { } {
    global args env
    
    set query [array names env]
    if { [info exists env(QUERY_STRING)] } {
        set query $env(QUERY_STRING)
    }
    
    foreach item [split $query &] {
        if { [regexp {([^=]+)=(.+)} $item dummy key value] } {
            set args($key) $value
        }
    }
}

proc loadFile { fileName } {
    set content ""
    set fd -1
    
    set fd [ open $fileName r]
    if { $fd > -1 } {
        set content [read $fd]
        close $fd
    }
    
    return $content
}

proc loadConfigFile { } {
    global FILENAME HM_CALDAV_URL HM_CALDAV_USER HM_CALDAV_SECRET HM_CCU_CALDAV_VAR HM_CCU_EVENT_ACTIVE HM_CCU_EVENT_INACTIVE HM_DOWNLOAD_INTERVAL HM_INTERVAL_TIME HM_EVENT_VAR_MAPPING_LIST
    set conf ""
    catch {set conf [loadFile $FILENAME]}

    if { [string trim "$conf"] != "" } {
        set HM_INTERVAL_MAX 0

        regexp -line {^HM_CALDAV_URL=\"(.*)\"$} $conf dummy HM_CALDAV_URL
        regexp -line {^HM_CALDAV_USER=\"(.*)\"$} $conf dummy HM_CALDAV_USER
        regexp -line {^HM_CALDAV_SECRET=\"(.*)\"$} $conf dummy HM_CALDAV_SECRET
        regexp -line {^HM_CCU_CALDAV_VAR=\"(.*)\"$} $conf dummy HM_CCU_CALDAV_VAR
        regexp -line {^HM_INTERVAL_MAX=\"(.*)\"$} $conf dummy HM_INTERVAL_MAX
        regexp -line {^HM_INTERVAL_TIME=\"(.*)\"$} $conf dummy HM_INTERVAL_TIME
        regexp -line {^HM_DOWNLOAD_INTERVAL=\"(.*)\"$} $conf dummy HM_DOWNLOAD_INTERVAL
        regexp -line {^HM_CCU_EVENT_ACTIVE=\"(.*)\"$} $conf dummy HM_CCU_EVENT_ACTIVE
        regexp -line {^HM_CCU_EVENT_INACTIVE=\"(.*)\"$} $conf dummy HM_CCU_EVENT_INACTIVE
        regexp -line {^HM_EVENT_VAR_MAPPING_LIST=\((.*)\)$} $conf dummy HM_EVENT_VAR_MAPPING_LIST

        # if HM_INTERVAL_MAX is 1 we have to uncheck the
        # checkbox to signal that the interval stuff is disabled.
        if { $HM_INTERVAL_MAX == 1 } {
          set HM_INTERVAL_TIME 0
        }
        
        # lets replace all spaces with newlines for the
        # textarea fields in the html code.
        regsub -all {\s+\[} $HM_EVENT_VAR_MAPPING_LIST "\n\[" HM_EVENT_VAR_MAPPING_LIST

        # make sure to unescape variable content that was properly escaped
        # due to shell variable regulations
        set HM_CALDAV_USER [str-unescape $HM_CALDAV_USER]
        set HM_CALDAV_SECRET [str-unescape $HM_CALDAV_SECRET]
    }
}

proc saveConfigFile { } {
    global FILENAME args
        
    set fd [open $FILENAME w]

    set HM_CALDAV_URL [url-decode $args(HM_CALDAV_URL)]
    set HM_CALDAV_USER [url-decode $args(HM_CALDAV_USER)]
    set HM_CALDAV_SECRET [url-decode $args(HM_CALDAV_SECRET)]
    set HM_CCU_CALDAV_VAR [url-decode $args(HM_CCU_CALDAV_VAR)]
    set HM_INTERVAL_TIME [url-decode $args(HM_INTERVAL_TIME)]
    set HM_DOWNLOAD_INTERVAL [url-decode $args(HM_DOWNLOAD_INTERVAL)]
    set HM_CCU_EVENT_ACTIVE [url-decode $args(HM_CCU_EVENT_ACTIVE)]
    set HM_CCU_EVENT_INACTIVE [url-decode $args(HM_CCU_EVENT_INACTIVE)]
    set HM_EVENT_VAR_MAPPING_LIST [url-decode $args(HM_EVENT_VAR_MAPPING_LIST)]

    # make sure to that HM_EVENT_VAR_MAPPING_LIST contains a valid associate array
    # expression or otherwise we might run into problems later on.
    # replace double-whitespaces to single ones
    regsub -all {\s+} $HM_EVENT_VAR_MAPPING_LIST " " HM_EVENT_VAR_MAPPING_LIST
    # replace "= " to "="
    regsub -all {=\s+} $HM_EVENT_VAR_MAPPING_LIST "=" HM_EVENT_VAR_MAPPING_LIST
    # replace " =" to "="
    regsub -all {\s+=} $HM_EVENT_VAR_MAPPING_LIST "=" HM_EVENT_VAR_MAPPING_LIST
    # replace " ]" to "]"
    regsub -all {\s+\]} $HM_EVENT_VAR_MAPPING_LIST "\]" HM_EVENT_VAR_MAPPING_LIST
    # replace "[ " to "["
    regsub -all {\[\s+} $HM_EVENT_VAR_MAPPING_LIST "\[" HM_EVENT_VAR_MAPPING_LIST
    
    # make sure to escape variable content that may contain special
    # characters not allowed unescaped in shell variables.
    set HM_CALDAV_USER [str-escape $HM_CALDAV_USER]
    set HM_CALDAV_SECRET [str-escape $HM_CALDAV_SECRET]
    
    # we set config options that should not be changeable on the CCU
    puts $fd "HM_CCU_IP=127.0.0.1"
    puts $fd "HM_CCU_REGAPORT=8183"
    puts $fd "HM_PROCESSLOG_FILE=\"/var/log/hm_caldav.log\""
    puts $fd "HM_DAEMON_PIDFILE=\"/var/run/hm_caldav.pid\""

    # only add the following variables if they are NOT empty
    if { [string length $HM_CALDAV_URL] > 0 }              { puts $fd "HM_CALDAV_URL=\"$HM_CALDAV_URL\"" }
    if { [string length $HM_CALDAV_USER] > 0 }            { puts $fd "HM_CALDAV_USER=\"$HM_CALDAV_USER\"" }
    if { [string length $HM_CALDAV_SECRET] > 0 }          { puts $fd "HM_CALDAV_SECRET=\"$HM_CALDAV_SECRET\"" }
    if { [string length $HM_CCU_CALDAV_VAR] > 0 }      	{ puts $fd "HM_CCU_CALDAV_VAR=\"$HM_CCU_CALDAV_VAR\"" }
    if { [string length $HM_DOWNLOAD_INTERVAL] > 0 }      	{ puts $fd "HM_DOWNLOAD_INTERVAL=\"$HM_DOWNLOAD_INTERVAL\"" }
    if { [string length $HM_CCU_EVENT_ACTIVE] > 0 }      	{ puts $fd "HM_CCU_EVENT_ACTIVE=\"$HM_CCU_EVENT_ACTIVE\"" }
    if { [string length $HM_CCU_EVENT_INACTIVE] > 0 }      	{ puts $fd "HM_CCU_EVENT_INACTIVE=\"$HM_CCU_EVENT_INACTIVE\"" }

    if { $HM_INTERVAL_TIME == 0 } { 
      puts $fd "HM_INTERVAL_MAX=\"1\""
    } else {
      puts $fd "HM_INTERVAL_TIME=\"$HM_INTERVAL_TIME\""
    }
    
    # also add empty variables on purpose
    puts $fd "HM_EVENT_VAR_MAPPING_LIST=($HM_EVENT_VAR_MAPPING_LIST)"

    close $fd

    # we have updated our configuration so lets
    # stop/restart hm_caldav
    if { $HM_INTERVAL_TIME == 0 } { 
      exec /usr/local/etc/config/rc.d/hm_caldav stop &
    } else {
      exec /usr/local/etc/config/rc.d/hm_caldav restart &
    }
}
