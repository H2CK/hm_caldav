BEGIN{
  FS=":";
  OFS="\t";
}
$1~/^DTSTART/{DTSTART=$2}
$1~/^DTEND/{DTEND=$2}
$1=="SUMMARY"{SUMMARY=$2}
/^END:VEVENT/ {
  if (SUMMARY ~ NAME) printf "BEGIN:VEVENT\nSUMMARY:%s\nDTSTART:%s\nDTEND:%s\nEND:VEVENT\n", SUMMARY, DTSTART, DTEND;
}          
