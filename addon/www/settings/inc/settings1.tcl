regsub -all {<%HM_CALDAV_URL%>} $content [string trim $HM_CALDAV_URL] content
regsub -all {<%HM_CALDAV_USER%>} $content [string trim $HM_CALDAV_USER] content
regsub -all {<%HM_CALDAV_SECRET%>} $content [string trim $HM_CALDAV_SECRET] content
regsub -all {<%HM_CCU_CALDAV_VAR%>} $content [string trim $HM_CCU_CALDAV_VAR] content
regsub -all {<%HM_INTERVAL_TIME%>} $content [string trim $HM_INTERVAL_TIME] content
regsub -all {<%HM_DOWNLOAD_INTERVAL%>} $content [string trim $HM_DOWNLOAD_INTERVAL] content
regsub -all {<%HM_CCU_EVENT_ACTIVE%>} $content [string trim $HM_CCU_EVENT_ACTIVE] content
regsub -all {<%HM_CCU_EVENT_INACTIVE%>} $content [string trim $HM_CCU_EVENT_INACTIVE] content
regsub -all {<%HM_EVENT_VAR_MAPPING_LIST%>} $content [string trim $HM_EVENT_VAR_MAPPING_LIST] content

puts "Content-Type: text/html; charset=utf-8\n\n"
puts $content
