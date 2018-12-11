#!/usr/bin/env tclsh
source [file join [file dirname [info script]] inc/settings.tcl]

parseQuery

if { $args(command) == "defaults" } {
  set args(HM_CALDAV_URL) ""
  set args(HM_CALDAV_USER) ""
  set args(HM_CALDAV_SECRET) ""
  set args(HM_CCU_CALDAV_VAR) ""
  set args(HM_INTERVAL_TIME) ""
  set args(HM_DOWNLOAD_INTERVAL) ""
  set args(HM_CCU_EVENT_ACTIVE) ""
  set args(HM_CCU_EVENT_INACTIVE) ""
  set args(HM_EVENT_VAR_MAPPING_LIST) ""
  
  # force save of data
  set args(command) "save"
} 

if { $args(command) == "save" } {
	saveConfigFile
} 

set HM_CALDAV_URL ""
set HM_CALDAV_USER ""
set HM_CALDAV_SECRET ""
set HM_CCU_CALDAV_VAR ""
set HM_INTERVAL_TIME ""
set HM_DOWNLOAD_INTERVAL ""
set HM_CCU_EVENT_ACTIVE ""
set HM_CCU_EVENT_INACTIVE ""
set HM_EVENT_VAR_MAPPING_LIST ""

loadConfigFile
set content [loadFile en.settings.html]
source [file join [file dirname [info script]] inc/settings1.tcl]
