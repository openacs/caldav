ad_library {

    Tests for the CalDAV package.

}

aa_register_case -cats {
    smoke production_safe
} -procs {
    util::which
} caldav_exec_dependencies {
    Test external command dependencies for this package.
} {
    foreach cmd [list \
                     [::util::which date] \
                     [::util::which zdump] \
                    ] {
        aa_true "'$cmd' is executable" [file executable $cmd]
    }
}

namespace eval ::caldav::test {

    ad_proc -private basic_setup {
        {-user_id ""}
        {-once:boolean}
        {-private:boolean false}
        {calendar_name test_calendar}
    } {

	Create a simple calendar with a few items for testing
	purposes.

    } {

        if {$user_id eq ""} {
            #
            # We use here a password to be able to connect to this
            # client also via caldav from external clients.
            #
            set email caldav-test-user@test.test
            set user_info [::acs::test::user::create \
                               -email $email \
                               -password cal789dav]
            aa_log "USER created: $user_info"
            set user_id [dict get $user_info user_id]
            set calendar_name "private calendar of $email"

            #
            # Check, if this user has already a private calendar
            #
            set priv_calendar_id [::xo::dc get_value get_calendar {
                select calendar_id from calendars
                where  calendar_name = :calendar_name
                and    private_p = true
                and    owner_id = :user_id
            } 0]
            aa_log "select calendar $calendar_name for user $user_id returns $priv_calendar_id"

            if {$priv_calendar_id == 0} {
                #
                # This user does not have a private calendar, create
                # one with a simple item.
                #
                set priv_calendar_id [calendar::create $user_id true $calendar_name]
                aa_log "created private calendar $priv_calendar_id "
                aa_true "valid calendar id" {$priv_calendar_id > 0}
            } else  {
                set priv_cal_item_ids [::xo::dc list get_calitems {
                    select c.cal_item_id from cal_items c where on_which_calendar = :priv_calendar_id
                }]
                aa_log "initial calitems for $priv_calendar_id: $priv_cal_item_ids"
                foreach cal_item_id $priv_cal_item_ids {
                    calendar::item::delete -cal_item_id $cal_item_id
                }
            }

            #
            # add private calendar items
            #
            set cal_item_id1 [calendar::item::new \
                                  -start_date "2019-04-20 13:19:33.264032+02" \
                                  -end_date   "2019-04-20 14:19:33.264032+02" \
                                  -name "remember!" \
                                  -description "my first private entry" \
                                  -calendar_id $priv_calendar_id]

            #
            # recurring item
            #
            set cal_item_id2 [calendar::item::new \
                                  -start_date "2019-01-01 16:00:00.0+02" \
                                  -end_date   "2019-01-01 17:00:00.0+02" \
                                  -name "My recurring entry" \
                                  -description "This is a private recurring entry" \
                                  -calendar_id $priv_calendar_id]
            set recurrence_id [calendar::item::add_recurrence \
                                   -cal_item_id $cal_item_id2 \
                                   -interval_type "day" \
                                   -every_n 1 \
                                   -days_of_week "" \
                                   -recur_until "2019-01-31"]
            #
            # all-day event
            #
            set cal_item_id3 [calendar::item::new \
                                  -start_date "2019-01-02 00:00:00" \
                                  -end_date   "2019-01-02 00:00:00" \
                                  -name "Private All day long" \
                                  -description "private all day long entry" \
                                  -calendar_id $priv_calendar_id]

        }
        set priv_cal_item_ids [::xo::dc list get_calitems {
            select c.cal_item_id from cal_items c where on_which_calendar = :priv_calendar_id
        }]
        aa_log "found [llength $priv_cal_item_ids] calendar items in private calendar $priv_calendar_id"

        #
        # If we have such a test calendar already, just get the cal_items.
        #
        set calendar_name "test_calendar"

        set calendar_id [::xo::dc get_value get_calendar {
            select calendar_id from calendars
            where  calendar_name = :calendar_name
            and    private_p = :private_p
            and    owner_id = :user_id
        } 0]

        if {$calendar_id > 0} {

            set cal_item_ids [::xo::dc list get_calitems {
                select c.cal_item_id from cal_items c where on_which_calendar = :calendar_id
            }]
            aa_log "found [llength $cal_item_ids] calendar items in calendar $calendar_id"
            foreach cal_item_id $cal_item_ids {
                calendar::item::delete -cal_item_id $cal_item_id
            }

        } else {
            #
            # Create test calendar
            #
            set calendar_id [calendar::create $user_id false $calendar_name]
            aa_log "created calendar $calendar_id "
            aa_true "valid calendar id" {$calendar_id > 0}
        }
        #
        # Add calendar items
        #
        set cal_item_ids {}

        # make a longer description, add a newline to it.
        set description [string repeat "This is a sample entry. " 10]
        set description $description\n$description

        # simple example from rfc5545
        set summary "Project XYZ Final Review\nConference Room - 3B\nCome Prepared."

        # a name containing characters which have to be escaped
        set name {Chars needing escaping are \ ; , (see rfc5545 Page 45)}

        #
        # simple item
        #
        set cal_item_id1 [calendar::item::new \
                              -start_date "2019-01-01 13:19:33.264032+02" \
                              -end_date   "2019-01-01 14:19:33.264032+02" \
                              -name $name \
                              -description $description \
                              -calendar_id $calendar_id]
        lappend cal_item_ids $cal_item_id1

        #
        # recurring item
        #
        set cal_item_id2 [calendar::item::new \
                              -start_date "2019-01-01 16:00:00.0+02" \
                              -end_date   "2019-01-01 17:00:00.0+02" \
                              -name "My recurring entry" \
                              -description "This is a sample recurring entry" \
                              -calendar_id $calendar_id]
        set recurrence_id [calendar::item::add_recurrence \
                               -cal_item_id $cal_item_id2 \
                               -interval_type "day" \
                               -every_n 1 \
                               -days_of_week "" \
                               -recur_until "2019-01-31"]
        lappend cal_item_ids $cal_item_id2

        #
        # all-day event
        #
        set cal_item_id3 [calendar::item::new \
                              -start_date "2019-01-02 00:00:00" \
                              -end_date   "2019-01-02 00:00:00" \
                              -name "All day long" \
                              -description $summary \
                              -calendar_id $calendar_id]
        lappend cal_item_ids $cal_item_id3

	return [list \
		    calendar_id $calendar_id \
		    calendar_name $calendar_name \
		    user_id $user_id \
                    user_info $user_info \
		    cal_item_ids $cal_item_ids \
                    priv_calendar_id $priv_calendar_id \
                    priv_cal_item_ids $priv_cal_item_ids]
    }

    ad_proc -private ::caldav::test::get_lowest_uid {-user_info } {

        Get from the private calendar of the provided user the
        lowest uid.

    } {
        set user_id [dict get $user_info user_id]
	set private_calendar_id [::caldav::get_sync_calendar -user_id $user_id]
        set url /caldav/calendar/$private_calendar_id
        set d [::acs::test::http -user_info $user_info $url]
        set ical_response [dict get $d body]
        set ical_summary [::caldav::test::ical_stats $ical_response]
        #aa_log <pre>$ical_response</pre>
        return [lindex [lsort -integer [dict get $ical_summary uids]] 0]
    }


    ad_proc -private ::caldav::test::item_stats {event_list} {

	Check the provided items and return a dict with descriptive
	statistics.

    } {
	foreach c {integer_uid recurrence uid} {
	    set entries($c) 0
	}
	foreach o $event_list {
	    set recurrences [$o formatted_recurrences get]
	    if {$recurrences ne ""} {
		incr entries(recurrence)
		aa_log "Recurrence rule: [::aa_test::visualize_control_chars $recurrences]"
		aa_equals "expected recurrence" $recurrences "RRULE:FREQ=DAILY;INTERVAL=1;UNTIL=20190130T230000Z\r\n"
	    }
	    #if {[$o etag] ne ""} {
            #incr entries(etag)
	    #}
	    set uid [$o uid get]
	    if {$uid ne ""} {
		incr entries(uid)
		if {[string is integer -strict $uid]} {
		    incr entries(integer_uid)
		}
	    }
	    #aa_log "[$o serialize]"
	}
	return [array get entries]
    }

    ad_proc -private ::caldav::test::render_items {
	{-name ""} event_list
    } {
	Render a full calendar and destroy the objects in the event_list.
    } {
	set resp [::caldav::calendars header -calendar_name $name]
	foreach o $event_list {
	    append resp [$o as_ical_event]
	    $o destroy
	}
	append resp [::caldav::calendars footer]
	return $resp
    }

    ad_proc -private ::caldav::test::ical_stats {
        {-require_crlf:boolean true}
        ical_text
    } {
	Check the ical text for validity and return a dict with
	descriptive statistics.
    } {
    	#set F [open [ad_tmpdir]/dump.ics w]; puts -nonewline $F $resp; close $F

	array set count {
	    lines 0 lines_without_crlf 0 overlong_lines 0 continuation_lines 0
	    nr_uids 0 uids {}
	}
	foreach line [split $ical_text \n] {
	    incr count(lines)
	    if {$require_crlf_p && [string index $line end] ne "\r"} {
		incr count(lines_without_crlf)
		#ns_log notice "line_without_crlf: $line"
	    }
	    if {[string index $line 0] eq " "} {
		incr count(continuation_lines)
	    }

	    if {[string length $line] > 76} {
		incr count(overlong_lines)
		ns_log warning "overlong_line (chars [string length $line]): <$line>"
	    }
	    if {[regexp {^UID:(.*)\r$} $line . uid]} {
		incr count(nr_uids)
		lappend count(uids) $uid
	    }
	}
	return [array get count]
    }

    ad_proc -private ::caldav::test::ical_valid {
        {-require_crlf:boolean true}
        ical_text
    } {
	Check the ical "object" and return detected issues as as a dict.
	If not issues are detected, return ""
    } {
	set result {}
	set d [ical_stats -require_crlf=$require_crlf_p $ical_text]
	foreach key {overlong_lines lines_without_crlf} {
	    if {![dict exists $d $key]} {
		continue
	    }
	    set value [dict get $d $key]
	    if {
		($key eq "lines_without_crlf" && $value <= 1)
		|| ($value == 0)
	    } {
		continue
	    }
	    lappend result $key $value
	}
	return $result
    }

    ad_proc -private ::caldav::test::ical_extract {
        ical_text
        tag
    } {
	extract tags from the ical text
        # TODO: could go into ical procs
    } {

        regsub -all "\n " $ical_text "" ical_text
        regsub -all "\r" $ical_text "" ical_text
        set result {}

        foreach line [split $ical_text \n] {
            if {[regexp "^${tag}(\;\[^:\]+|):(.*)$" $line . params value]} {
                if {$params ne ""} {
                    lappend result [list $params $value]
                } else {
                    lappend result $value
                }
            }
        }
	return $result
    }


    ad_proc -private ::caldav::test::propfind_body {props} {
        append result \
            {<?xml version="1.0" encoding="UTF-8"?>} \n\
            {<D:propfind xmlns:D="DAV:" xmlns:CS="http://calendarserver.org/ns/" xmlns:C="urn:ietf:params:xml:ns:caldav">} \n\
            <D:prop> $props </D:prop> \n\
            </D:propfind>
        return $result
    }

    ad_proc -private ::caldav::test::foreach_response {var xml body} {
        upvar $var response
	dom parse -- $xml doc
	$doc documentElement root
        try {
            set responses [$root selectNodes //d:response]
        } on error {errorMsg} {
            aa_true "XPAth exception during evaluation of selector '//d:response': $errorMsg" 0
            throw {XPATH {xpath triggered exception}} $errorMsg
        }
        foreach response $responses {
            uplevel $body
        }
    }

    ad_proc -private ::caldav::test::proppatch {
        {-user_info:required}
        {-prefix ""}
        url
        property
        ical
    } {
        set body "<?xml version='1.0' encoding='UTF-8'?>\n"
        append body \
            {<A:propertyupdate xmlns:A="DAV:"><A:set>} \
            [subst {<A:prop><C:$property xmlns:C="urn:ietf:params:xml:ns:caldav">}] \
            $ical \
            [subst {</C:$property></A:prop></A:set></A:propertyupdate>}]
	set d [::acs::test::http -prefix $prefix \
		   -user_info $user_info \
                   -method PROPPATCH \
                   -headers {Content-Type text/xml Depth 0} \
                   -body $body \
		   $url]
	aa_equals "Status code valid" [dict get $d status] 207
        return $d
    }


}

# the following is transitional code, until acs-automated-testing is updated.
if {[info commands aa_test::visualize_control_chars] eq ""} {
    proc ::aa_test::visualize_control_chars {lines} {
	set output $lines
	regsub -all {\\} $output {\\\\} output
	regsub -all {\r} $output {\\r} output
	regsub -all {\n} $output "\\n\n" output
	return [ns_quotehtml $output]
    }
}

aa_register_case -cats {api} -procs {
    calendar::create
    calendar::item::new
    ::caldav::get_sync_calendar
    "::caldav::calendars proc get_calitems"

    "::caldav::calitem instproc as_ical_event"
    "::ad_change_password"
} get_calitems {

    API test for [calendars get_calitems] used in different calls.

    The query can be constraint via -user_id, -start_date, and -end_date
} {
    #
    # The API test can run basic_setup and tests in a single
    # transaction, which is finally rolled back
    #
    aa_run_with_teardown -rollback -test_code {
	set info [::caldav::test::basic_setup]
	#aa_log $info

	set event_list [::caldav::calendars get_calitems \
			    -user_id [dict get $info user_id] \
			    -start_date "2019-01-01 00:00:00.0+02" \
			    -end_date   "2019-01-07 23:59:00.0+02" \
			    -calendar_ids [dict get $info calendar_id]]
	#
	# The items created via basic_setup can be retrieved within
	# the transaction over this interface.
	#
	aa_log "found [llength $event_list] cal items in calendar [dict get $info calendar_id] for check period"
	aa_true "number retrieved times is the same as in setup dict" {
	    [llength [dict get $info cal_item_ids]] == [llength $event_list]
	}
	set item_summary [::caldav::test::item_stats $event_list]

	aa_equals "Calendar entries:" \
	    {integer_uid 3 recurrence 1 uid 3} \
	    [lsort -stride 2 $item_summary]

	set ical_text [::caldav::test::render_items -name [dict get $info calendar_name] $event_list]
        aa_log "Result body:<pre>\n[::aa_test::visualize_control_chars $ical_text]</pre>"

	aa_equals "Ical valid" [::caldav::test::ical_valid $ical_text] ""
	set ical_summary [::caldav::test::ical_stats $ical_text]
	foreach {key value} {continuation_lines 7 lines 45 lines_without_crlf 1 nr_uids 3} {
	    aa_equals "Ical text has $key $value"  [dict get $ical_summary $key] $value
	}

	#
	# Get the full private calendar
	#
        set user_id [dict get $info user_id]
        aa_section "Get private calendar of user $user_id"
	set private_calendar_id [::caldav::get_sync_calendar -user_id $user_id]
        aa_true "caldav::get_sync_calendar returns same calendar_id as setup" {
            $private_calendar_id eq [dict get $info priv_calendar_id]
        }
	aa_log "user $user_id: Private calendar $private_calendar_id vs. [dict get $info priv_calendar_id]"
	calendar::get -calendar_id $private_calendar_id -array calInfo

	set event_list [::caldav::calendars get_calitems \
			    -user_id [dict get $info user_id] \
			    -calendar_ids $private_calendar_id]
	set item_summary [::caldav::test::item_stats $event_list]
	aa_equals "Calendar entries of calendar $private_calendar_id:" \
            [lsort -stride 2 $item_summary] \
	    {integer_uid 3 recurrence 1 uid 3}

	set ical_text [::caldav::test::render_items -name $calInfo(calendar_name) $event_list]
        aa_log "Result body:<pre>\n[::aa_test::visualize_control_chars $ical_text]</pre>"

	aa_equals "Ical valid" [::caldav::test::ical_valid $ical_text] ""
	set ical_summary [::caldav::test::ical_stats $ical_text]
        aa_log $ical_summary
	foreach {key value} {continuation_lines 0 lines_without_crlf 1 nr_uids 3} {
	    aa_equals "Ical text has $key $value" [dict get $ical_summary $key] $value
	}
        aa_true "have at least 17 lines " {[dict get $ical_summary lines]  >= 17}
    }
}

aa_register_case -cats {web} -procs {
    caldav::test::basic_setup
} basic_caldav_web_request {
    Run a basic caldav request via protocol handler,
    which requires HTTP basic authorization headers.
} {
    set info [::caldav::test::basic_setup]
    set d [::acs::test::http -user_info [dict get $info user_info]  /caldav/calendar]

    aa_log "Headers: [ns_set array [dict get $d headers]]"
    aa_log "Result body:<pre>\n[::aa_test::visualize_control_chars [dict get $d body]]</pre>"

    acs::test::reply_has_status_code $d 200
}


aa_register_case -cats {web} -procs {
    "::caldav::CalDAV instproc GET"

    "::xo::ProtocolHandler instproc preauth"
    "::xo::ProtocolHandler instproc initialize"
    "::xo::ProtocolHandler instproc set_user_id"
    "::xo::ProtocolHandler instproc handle_request"
    "::dt_no_time_p"
    "::xo::ical::VCALITEM instproc ical_body"

} GET {

    GET method over the web interface (no OS-specific differences)

} {
    try {
	set info [::caldav::test::basic_setup]
	set user_id [dict get $info user_id]
        set user_info [dict get $info user_info]
	set temp_calendar_id [dict get $info calendar_id]
	set temp_calendar_items [llength [dict get $info cal_item_ids]]
	set personal_calendar_id 0
	set personal_calendar_id [::caldav::get_sync_calendar -user_id $user_id]
        aa_log "temp_calendar_id $temp_calendar_id, personal_calendar_id $personal_calendar_id"

	foreach {calendar_id nr_uids label} [subst {
	    $temp_calendar_id $temp_calendar_items "testing calendar"
	    $personal_calendar_id 3 "private calendar"
	}] {
	    if {$calendar_id == 0} continue

            foreach template {
                {/caldav/calendar/?calendar_ids=$calendar_id}
                {/caldav/calendar/$calendar_id}
            } {
                set URL [subst $template]
                aa_section "$label $URL"

                set d [::acs::test::http -user_info $user_info $URL]
                #ns_log notice "run returns $d"
                #ns_log notice "... [ns_set array [dict get $d headers]]"

                set ical_text [dict get $d body]
                set ical_stats [::caldav::test::ical_stats $ical_text]
                aa_log "Result body:<pre>\n[::aa_test::visualize_control_chars $ical_text]</pre>"
                acs::test::reply_has_status_code $d 200

                set content_length [ns_set iget [dict get $d headers] content-length]
                aa_true "Content-Length $content_length plausible" {$content_length > 200}
                aa_equals "Ical valid" [::caldav::test::ical_valid $ical_text] ""
                aa_equals "Expect $nr_uids items with uids ([dict get $ical_stats uids])" \
                    [dict get $ical_stats nr_uids] \
                    $nr_uids

                #
                # Retrieve every single uid from calendar
                #
                foreach uid [dict get $ical_stats uids] {
                    aa_section "Retrieve single uid $uid from $label $calendar_id"
                    set URL /caldav/calendar/$calendar_id/$uid.ics
                    aa_log "Get ical for single uid $uid from calendar $calendar_id: $URL"
                    set d [::acs::test::http -user_info $user_info $URL]
                    #ns_log notice "run returns $d"
                    #ns_log notice "... [ns_set array [dict get $d headers]]"

                    aa_equals "Status code valid" [dict get $d status] 200
                    set ical_text [dict get $d body]
                    set ical_stats [::caldav::test::ical_stats $ical_text]
                    set content_length [ns_set iget [dict get $d headers] content-length]
                    aa_true "Content-Length $content_length plausible" {$content_length > 200}
                    aa_equals "Ical valid" [::caldav::test::ical_valid $ical_text] ""
                    aa_log <pre>[::aa_test::visualize_control_chars $ical_text]</pre>
                    aa_equals "Expect 1 item with uids ([dict get $ical_stats uids])" [dict get $ical_stats nr_uids] 1
                }
            }
	}

    } on error {errorMsg} {
	aa_true "Error msg: $errorMsg" 0
    } finally {
	calendar::delete -calendar_id $temp_calendar_id
    }
}

########################################################################
# iOS
########################################################################

aa_register_case -cats {web} -procs {
    "::caldav::CalDAV instproc PROPFIND"
    "::caldav::CalDAV instproc generateResponse"

    "::caldav::CalDAV instproc returnXMLelement"
    "::caldav::CalDAV instproc property=cs-getctag"

} PROPFIND_ios {

    PROPFIND method over the web interface under iOS.

} {
    set info [::caldav::test::basic_setup]
    set user_info [dict get $info user_info]

    try {
	#
	# Checks functionality of the CalDAV server
	# Example from https://github.com/seiyanuta/busybook/blob/master/Documentation/caldav-request-examples.md
	#
	set body_xml {<?xml version="1.0" encoding="UTF-8"?>
	    <A:propfind xmlns:A="DAV:">
	    <A:prop>
	    <B:calendar-home-set xmlns:B="urn:ietf:params:xml:ns:caldav"/>
	    <B:calendar-user-address-set xmlns:B="urn:ietf:params:xml:ns:caldav"/>
	    <A:current-user-principal/>
	    <A:displayname/>
	    <C:dropbox-home-URL xmlns:C="http://calendarserver.org/ns/"/>
	    <C:email-address-set xmlns:C="http://calendarserver.org/ns/"/>
	    <C:notification-URL xmlns:C="http://calendarserver.org/ns/"/>
	    <A:principal-collection-set/>
	    <A:principal-URL/>
	    <A:resource-id/>
	    <B:schedule-inbox-URL xmlns:B="urn:ietf:params:xml:ns:caldav"/>
	    <B:schedule-outbox-URL xmlns:B="urn:ietf:params:xml:ns:caldav"/>
	    <A:supported-report-set/>
	    </A:prop>
	    </A:propfind>
	}

	set d [::acs::test::http \
		   -user_info $user_info \
		   -method PROPFIND \
                   -headers {Content-Type text/xml} \
                   -body $body_xml \
		   /caldav]
	aa_equals "Status code valid" [dict get $d status] 207
	set xml [dict get $d body]
        aa_log "Result body:<pre>\n[::aa_test::visualize_control_chars $xml]</pre>"

        ::caldav::test::foreach_response response $xml {
            ::acs::test::xpath::non_empty $response {
                d:href
            }
            ::acs::test::xpath::equals $response {
                d:href                                       /caldav/
                d:propstat/d:prop/d:current-user-principal   /caldav/principal
                d:propstat/d:prop/d:displayname              ""
                d:propstat/d:prop/d:principal-collection-set /caldav/principal
                d:propstat/d:prop/d:principal-URL            /caldav/principal
                d:propstat/d:prop/d:supported-report-set     ""

            }
            set principal_url [::acs::test::xpath::get_text $response d:propstat/d:prop/d:current-user-principal]
        }

	#
	# Principal query from iOS/11.2.6.
	# Note that the principal query for iOS ends with a "/"
	#
	set d [::acs::test::http \
		   -user_info $user_info \
		   -method OPTIONS \
		   $principal_url/]

	#ns_log notice "run returns $d"
	#ns_log notice "... [ns_set array [dict get $d headers]]"

	aa_equals "Status code valid" [dict get $d status] 200
	aa_equals "Allowed: " [ns_set iget [dict get $d headers] Allow] "OPTIONS,GET,DELETE,PROPFIND,PUT,REPORT"


	set d [::acs::test::http \
		   -user_info $user_info \
		   -method PROPFIND \
		   -headers {Content-Type text/xml} \
		   -body {<?xml version="1.0" encoding="UTF-8"?>
		       <A:propfind xmlns:A="DAV:">
		       <A:prop>
		       <B:calendar-home-set xmlns:B="urn:ietf:params:xml:ns:caldav"/>
		       <B:calendar-user-address-set xmlns:B="urn:ietf:params:xml:ns:caldav"/>
		       <A:current-user-principal/>
		       <A:displayname/>
		       <C:dropbox-home-URL xmlns:C="http://calendarserver.org/ns/"/>
		       <C:email-address-set xmlns:C="http://calendarserver.org/ns/"/>
		       <C:notification-URL xmlns:C="http://calendarserver.org/ns/"/>
		       <A:principal-collection-set/>
		       <A:principal-URL/>
		       <A:resource-id/>
		       <B:schedule-inbox-URL xmlns:B="urn:ietf:params:xml:ns:caldav"/>
		       <B:schedule-outbox-URL xmlns:B="urn:ietf:params:xml:ns:caldav"/>
		       <A:supported-report-set/>
		       </A:prop>
		       </A:propfind>
		   } \
		   $principal_url/]

	aa_equals "Status code valid" [dict get $d status] 207
	set xml [dict get $d body]
        aa_log "Result body:<pre>\n[::aa_test::visualize_control_chars $xml]</pre>"

        ::caldav::test::foreach_response response $xml {
            ::acs::test::xpath::equals $response {
                d:propstat/d:prop/d:principal-URL      /caldav/principal
                d:propstat/d:prop/c:calendar-home-set  /caldav/calendar
                d:propstat/d:prop/d:resource-id        ""
            }
            set calendar_url [::acs::test::xpath::get_text $response d:propstat/d:prop/c:calendar-home-set]
        }

	#
	# Calendar Query
	#
	set d [::acs::test::http \
		   -user_info $user_info \
		   -method PROPFIND \
		   -headers {Content-Type text/xml} \
		   -body {<?xml version="1.0" encoding="UTF-8"?>
                       <A:propfind xmlns:A="DAV:">
                       <A:prop>
                       <A:add-member/>
                       <C:allowed-sharing-modes xmlns:C="http://calendarserver.org/ns/"/>
                       <E:autoprovisioned xmlns:E="http://apple.com/ns/ical/"/>
                       <F:bulk-requests xmlns:F="http://me.com/_namespace/"/>
                       <B:calendar-alarm xmlns:B="urn:ietf:params:xml:ns:caldav"/>
                       <E:calendar-color xmlns:E="http://apple.com/ns/ical/"/>
                       <B:calendar-description xmlns:B="urn:ietf:params:xml:ns:caldav"/>
                       <B:calendar-free-busy-set xmlns:B="urn:ietf:params:xml:ns:caldav"/>
                       <E:calendar-order xmlns:E="http://apple.com/ns/ical/"/>
                       <B:calendar-timezone xmlns:B="urn:ietf:params:xml:ns:caldav"/>
                       <A:current-user-privilege-set/>
                       <B:default-alarm-vevent-date xmlns:B="urn:ietf:params:xml:ns:caldav"/>
                       <B:default-alarm-vevent-datetime xmlns:B="urn:ietf:params:xml:ns:caldav"/>
                       <A:displayname/>
                       <C:getctag xmlns:C="http://calendarserver.org/ns/"/>
                       <E:language-code xmlns:E="http://apple.com/ns/ical/"/>
                       <E:location-code xmlns:E="http://apple.com/ns/ical/"/>
                       <A:owner/>
                       <C:pre-publish-url xmlns:C="http://calendarserver.org/ns/"/>
                       <C:publish-url xmlns:C="http://calendarserver.org/ns/"/>
                       <C:push-transports xmlns:C="http://calendarserver.org/ns/"/>
                       <C:pushkey xmlns:C="http://calendarserver.org/ns/"/>
                       <A:quota-available-bytes/>
                       <A:quota-used-bytes/>
                       <E:refreshrate xmlns:E="http://apple.com/ns/ical/"/>
                       <A:resource-id/>
                       <A:resourcetype/>
                       <B:schedule-calendar-transp xmlns:B="urn:ietf:params:xml:ns:caldav"/>
                       <B:schedule-default-calendar-URL xmlns:B="urn:ietf:params:xml:ns:caldav"/>
                       <C:source xmlns:C="http://calendarserver.org/ns/"/>
                       <C:subscribed-strip-alarms xmlns:C="http://calendarserver.org/ns/"/>
                       <C:subscribed-strip-attachments xmlns:C="http://calendarserver.org/ns/"/>
                       <C:subscribed-strip-todos xmlns:C="http://calendarserver.org/ns/"/>
                       <B:supported-calendar-component-set xmlns:B="urn:ietf:params:xml:ns:caldav"/>
                       <B:supported-calendar-component-sets xmlns:B="urn:ietf:params:xml:ns:caldav"/>
                       <A:supported-report-set/>
                       <A:sync-token/>
                       </A:prop>
                       </A:propfind>
		   } \
		   $calendar_url]

	aa_equals "Status code valid" [dict get $d status] 207
	set xml [dict get $d body]
        aa_log "Result body:<pre>\n[::aa_test::visualize_control_chars $xml]</pre>"

        ::caldav::test::foreach_response response $xml {
            ::acs::test::xpath::non_empty $response {
                d:href
                d:propstat/d:prop/d:displayname
                d:propstat/d:prop/cs:getctag
                d:propstat/d:prop/ical:calendar-color
                d:propstat/d:prop/c:calendar-description
            }
            ::acs::test::xpath::equals $response {
                d:href                                 /caldav/calendar/
                d:propstat/d:prop/ical:calendar-order  1
            }
        }

    } on error {errorMsg} {
	aa_true "Error msg: $errorMsg" 0
    } finally {
	#calendar::delete -calendar_id $temp_calendar_id
    }
}

aa_register_case -cats {web} -procs {
    "::caldav::CalDAV instproc REPORT"
    "::caldav::CalDAV instproc calendar-query"
    "::caldav::CalDAV instproc calendar-multiget"
    "::caldav::CalDAV instproc sync-collection"

} REPORT_ios {

    REPORT method over the web interface under iOS.

} {
    set info [::caldav::test::basic_setup]
    set user_info [dict get $info user_info]

    try {
	# Test REPORT functionality of the CalDAV server
	# iOS/11.2.6 (15D100) dataaccessd/1.0
        #
	set d [::acs::test::http \
		   -user_info $user_info \
		   -method REPORT \
		   -headers {Content-Type text/xml} \
		   -body {<?xml version="1.0" encoding="UTF-8"?>
                       <B:calendar-query xmlns:B="urn:ietf:params:xml:ns:caldav">
                       <A:prop xmlns:A="DAV:">
                       <A:getetag/>
                       <A:getcontenttype/>
                       </A:prop>
                       <B:filter>
                       <B:comp-filter name="VCALENDAR">
                       <B:comp-filter name="VEVENT">
                       <B:time-range start="20180221T000000Z"/>
                       </B:comp-filter>
                       </B:comp-filter>
                       </B:filter>
                       </B:calendar-query>
		   } \
		   /caldav/calendar/]

	aa_equals "Status code valid" [dict get $d status] 207
	set xml [dict get $d body]
        aa_log "Result body:<pre>\n[::aa_test::visualize_control_chars $xml]</pre>"

        ::caldav::test::foreach_response response $xml {
            ::acs::test::xpath::non_empty $response {
                d:href
                d:propstat/d:prop/d:getetag
                d:propstat/d:prop/d:getcontenttype
            }
            set href [::acs::test::xpath::get_text $response d:href]
            aa_true "href for calitem ends with .ics" [string match *ics $href]
        }

        #
	# Test with calendar-query with calendar-data
        #
	set d [::acs::test::http \
		   -user_info $user_info \
		   -method REPORT \
		   -headers {Content-Type text/xml} \
		   -body {<?xml version="1.0" encoding="UTF-8"?>
                       <B:calendar-query xmlns:B="urn:ietf:params:xml:ns:caldav">
                       <A:prop xmlns:A="DAV:">
                       <A:getetag/>
                       <B:calendar-data/>
                       </A:prop>
                       <B:filter>
                       <B:comp-filter name="VCALENDAR">
                       <B:comp-filter name="VEVENT">
                       <B:time-range start="20180221T000000Z"/>
                       </B:comp-filter>
                       </B:comp-filter>
                       </B:filter>
                       </B:calendar-query>
		   } \
		   /caldav/calendar/]

	aa_equals "Status code valid" [dict get $d status] 207
	set xml [dict get $d body]
        aa_log "Result body:<pre>\n[::aa_test::visualize_control_chars $xml]</pre>"

        ::caldav::test::foreach_response response $xml {
            ::acs::test::xpath::non_empty $response {
                d:href
                d:propstat/d:prop/d:getetag
                d:propstat/d:prop/c:calendar-data
            }
            set href     [::acs::test::xpath::get_text $response d:href]
            set icalText [::acs::test::xpath::get_text $response d:propstat/d:prop/c:calendar-data]
            #aa_log CHECK=[::aa_test::visualize_control_chars $icalText]

            aa_true "href for calitem ends with .ics" [string match *ics $href]
            aa_equals "Ical of $href valid" [::caldav::test::ical_valid -require_crlf=0 $icalText] ""
        }

        #############################################################################
        # test calendar-multiget in two steps
        #  1) run PROPFIND to return valid hrefs
        #  2) run REPORT to obtain calendar-multiget data
        #############################################################################
        #
	# Run PROFIND with Depth 1 to obtain hrefs
        #
	set d [::acs::test::http \
		   -user_info $user_info \
		   -method PROPFIND \
		   -headers {Content-Type text/xml Depth 1} \
		   -body [::caldav::test::propfind_body "<D:getetag/>"] \
		   /caldav/calendar]
	aa_equals "Status code valid" [dict get $d status] 207
	set xml [dict get $d body]
        aa_log "Result body:<pre>\n[::aa_test::visualize_control_chars $xml]</pre>"

        set nr_hrefs 0
        set href_xml ""
        ::caldav::test::foreach_response response $xml {
            set href [::acs::test::xpath::get_text $response d:href]
            if {![string match *.ics $href]} continue
            append href_xml <d:href> $href </d:href> \n
            incr nr_hrefs
        }
        aa_log "run calendar-multiget REPORT on the following hrefs:\n$href_xml"

        #
	# now run REPORT over the returned hrefs
        #
	set d [::acs::test::http \
		   -user_info $user_info \
		   -method REPORT \
		   -headers {Content-Type text/xml} \
		   -body [subst {<?xml version="1.0" encoding="UTF-8"?>
                       <c:calendar-multiget xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:d="DAV:">
                       <d:prop><d:getetag/><c:calendar-data/></d:prop>
                       $href_xml
                       </c:calendar-multiget>
                   }] \
		   /caldav/calendar/]

	aa_equals "Status code valid" [dict get $d status] 207
	set xml [dict get $d body]
        #aa_log "Result body:<pre>\n[::aa_test::visualize_control_chars $xml]</pre>"

        set nr_responses 0
        ::caldav::test::foreach_response response $xml {
            set icalText [::acs::test::xpath::get_text $response d:propstat/d:prop/c:calendar-data]
            set href     [::acs::test::xpath::get_text $response d:href]
            #aa_log CHECK=[::aa_test::visualize_control_chars $icalText]
            aa_equals "Ical of $href valid" [::caldav::test::ical_valid -require_crlf=0 $icalText] ""
            incr nr_responses
        }
        aa_equals "there is a response for every href" $nr_responses $nr_hrefs


        #############################################################################
        # test sync-collection REPORT
        #############################################################################
        #
	# Example from https://tools.ietf.org/html/rfc6578
        #
	set d [::acs::test::http \
		   -user_info $user_info \
		   -method REPORT \
		   -headers {Content-Type text/xml} \
		   -body {<?xml version="1.0" encoding="utf-8" ?>
                       <D:sync-collection xmlns:D="DAV:">
                       <D:sync-token/>
                       <D:sync-level>1</D:sync-level>
                       <D:prop xmlns:R="urn:ns.example.com:boxschema">
                       <D:getetag/>
                       <R:bigbox/>
                       </D:prop>
                       </D:sync-collection>} \
		   /caldav/calendar]
	aa_equals "Status code valid" [dict get $d status] 207
	set xml [dict get $d body]
        aa_log "Result body:<pre>\n[::aa_test::visualize_control_chars $xml]</pre>"

        set nr_responses 0
        ::caldav::test::foreach_response response $xml {
            set href [::acs::test::xpath::get_text $response d:href]
            ::acs::test::xpath::non_empty $response {
                d:propstat/d:prop/d:getetag
            }

            incr nr_responses
        }
        dom parse -- $xml doc
	$doc documentElement root
        ::acs::test::xpath::non_empty $root {
            d:sync-token
        }
        set sync_token [::acs::test::xpath::get_text $root d:sync-token]

        aa_true "there are multiple etags" {$nr_responses > 1}

    } on error {errorMsg} {
	aa_true "Error msg: $errorMsg" 0
    } finally {
	#calendar::delete -calendar_id $temp_calendar_id
    }

}


########################################################################
# Android
########################################################################

aa_register_case -cats {web} -procs {
    "::caldav::CalDAV instproc PROPFIND"
    "::caldav::CalDAV instproc generateResponse"

    "::caldav::CalDAV instproc returnXMLelement"
    "::caldav::CalDAV instproc property=cs-getctag"
} PROPFIND_android {

    PROPFIND method over the web interface under Android.

} {
    set info [::caldav::test::basic_setup]
    set user_info [dict get $info user_info]

    try {
        #
	# Checks functionality of the CalDAV server
	# CalDAV Sync Adapter (Android) https://github.com/gggard/AndroidCaldavSyncAdapater Version:0.1.1
	#
	set d [::acs::test::http \
		   -user_info $user_info \
		   -method PROPFIND \
		   -headers {Content-Type text/xml} \
		   -body {<?xml version="1.0" encoding="UTF-8"?>
		       <d:propfind xmlns:d="DAV:"><d:prop><d:current-user-principal /><d:principal-URL />
		       </d:prop></d:propfind>
		   } \
		   /caldav]
	#ns_log notice "run returns $d"
	#ns_log notice "... [ns_set array [dict get $d headers]]"
	aa_equals "Status code valid" [dict get $d status] 207
	set xml [dict get $d body]
        aa_log "Result body:<pre>\n[::aa_test::visualize_control_chars $xml]</pre>"

        ::caldav::test::foreach_response response $xml {
            ::acs::test::xpath::equals $response {
                d:propstat/d:prop/d:current-user-principal /caldav/principal
            }
            set principal_url [::acs::test::xpath::get_text $response d:propstat/d:prop/d:current-user-principal]
        }

	#
	# Principal query
	#
	set d [::acs::test::http \
		   -user_info $user_info \
		   -method PROPFIND \
		   -headers {Content-Type text/xml} \
		   -body {<?xml version="1.0" encoding="UTF-8"?>
		       <d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:prop><c:calendar-home-set/>
		       </d:prop></d:propfind>
		   } \
		   $principal_url]
	#ns_log notice "run returns $d"
	#ns_log notice "... [ns_set array [dict get $d headers]]"
	aa_equals "Status code valid" [dict get $d status] 207
	set xml [dict get $d body]
        aa_log "Result body:<pre>\n[::aa_test::visualize_control_chars $xml]</pre>"

        ::caldav::test::foreach_response response $xml {
            ::acs::test::xpath::equals $response {
                d:propstat/d:prop/c:calendar-home-set /caldav/calendar
            }
            set calendar_url [::acs::test::xpath::get_text $response d:propstat/d:prop/c:calendar-home-set]
        }

	#
	# Calendar Query from CalDAV Sync Adapter (Android)
	#
	set d [::acs::test::http \
		   -user_info $user_info \
		   -method PROPFIND \
		   -headers {Content-Type text/xml} \
		   -body {<?xml version="1.0" encoding="UTF-8"?>
		       <d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"
		       xmlns:cs="http://calendarserver.org/ns/" xmlns:ic="http://apple.com/ns/ical/">
		       <d:prop><d:displayname /><d:resourcetype /><ic:calendar-color /><cs:getctag /></d:prop>
		       </d:propfind>
		   } \
		   $calendar_url]
	#ns_log notice "run returns $d"
	#ns_log notice "... [ns_set array [dict get $d headers]]"
	aa_equals "Status code valid" [dict get $d status] 207
	set xml [dict get $d body]
        aa_log "Result body:<pre>\n[::aa_test::visualize_control_chars $xml]</pre>"

        ::caldav::test::foreach_response response $xml {

            ::acs::test::xpath::non_empty $response {
                d:propstat/d:prop/d:displayname
                d:propstat/d:prop/cs:getctag
            }
            ::acs::test::xpath::equals $response {
                d:href /caldav/calendar/
            }

	}
    } on error {errorMsg} {
	aa_true "Error msg: $errorMsg" 0
    } finally {
	#calendar::delete -calendar_id $temp_calendar_id
    }
}



########################################################################
# Thunderbird
########################################################################

aa_register_case -cats {web} -procs {
    "::caldav::CalDAV instproc PROPFIND"

    "::caldav::CalDAV instproc property=cs-getctag"
} PROPFIND_thunderbird {

    PROPFIND method over the web interface for Thunderbird.

} {
    set info [::caldav::test::basic_setup]
    set user_info [dict get $info user_info]

    try {
        #
        # Tests based on user-agent Mozilla/5.0 (X11; Linux x86_64;
        # rv:52.0) Gecko/20100101 Thunderbird/52.6.0 Lightning/5.4.6)
        #
        aa_log "PROFIND /caldav/calendar with Depth 0"
	set d [::acs::test::http \
		   -user_info $user_info \
		   -method PROPFIND \
		   -headers {Content-Type text/xml Depth 0} \
		   -body [::caldav::test::propfind_body <CS:getctag/>] \
		   /caldav/calendar]
	aa_equals "Status code valid" [dict get $d status] 207
	set xml [dict get $d body]
        aa_log "Result body:<pre>\n[::aa_test::visualize_control_chars $xml]</pre>"

        ::caldav::test::foreach_response response $xml {
            ::acs::test::xpath::non_empty $response {
                d:propstat/d:prop/cs:getctag
            }
        }

        #
	# Run PROFIND to check ctag with Depth 1
        #
        aa_log "PROFIND /caldav/calendar with Depth 1"

	set d [::acs::test::http \
		   -user_info $user_info \
		   -method PROPFIND \
		   -headers {Content-Type text/xml Depth 1} \
		   -body [::caldav::test::propfind_body "<D:getcontenttype/><D:resourcetype/><D:getetag/>"] \
		   /caldav/calendar]
	aa_equals "Status code valid" [dict get $d status] 207
	set xml [dict get $d body]
        aa_log "Result body:<pre>\n[::aa_test::visualize_control_chars $xml]</pre>"

        ::caldav::test::foreach_response response $xml {
            set href [::acs::test::xpath::get_text $response d:href]
            aa_log "href: $href"
            if {$href eq "/caldav/calendar/"} {
                ::acs::test::xpath::non_empty $response {
                    d:propstat/d:prop/d:getcontenttype
                }
                ::acs::test::xpath::equals $response {
                    d:propstat/d:prop/d:getetag ""
                }
            } else {
                aa_true "href for calitem ends with .ics" [string match *ics $href]
                ::acs::test::xpath::non_empty $response {
                    d:propstat/d:prop/d:getcontenttype
                    d:propstat/d:prop/d:getetag
                }
            }
        }

    } on error {errorMsg} {
	aa_true "Error msg: $errorMsg" 0
    } finally {
	#calendar::delete -calendar_id $temp_calendar_id
    }
}


aa_register_case -cats {web} -procs {
    "::caldav::CalDAV instproc PROPFIND"
    "::caldav::CalDAV instproc PROPPATCH"
    "::caldav::CalDAV instproc REPORT"
    "::caldav::CalDAV instproc generateResponse"

    "::caldav::CalDAV instproc returnXMLelement"
} Thunderbird_subscribe {

    Steps for adding CalDAV account from macOS to "Calendar".

    Open Thunderbird Calendar
    Double click under the "Calendar" pulldown in the left menu
    Create calendar "On the Network",
    Select Format "CalDAV" and
    location e.g. http://localhost:8100/caldav/ does NOT work, but
    location e.g. http://localhost:8100/caldav/calendar works

    Provide a calendar name (e.g. openacs-5-10)

    For debugging you should "calendar.debug.log" and
    "calendar.debug.log.verbose" set to "true" in the config editor
    (Options/Preferences > Advanced > General > Config Editor)

    Tested with
    - Thunderbird/52.6.0 Lightning/5.4.6
    - Thunderbird/67.0 Lightning/6.9

} {
    set info [::caldav::test::basic_setup]
    set user_info [dict get $info user_info]

    try {
        #
        # 1. Query: principal-URL (Depth 0)
        #
        set queryNr 1
	set d [::acs::test::http -prefix "$queryNr: " \
		   -user_info $user_info \
		   -method PROPFIND \
                   -headers {Content-Type text/xml Depth 0} \
                   -body [::caldav::test::propfind_body "<D:resourcetype/><D:owner/><D:current-user-principal/><D:supported-report-set/><C:supported-calendar-component-set/><CS:getctag/>"] \
		   /caldav/]
	aa_equals "Status code valid" [dict get $d status] 207
	set xml [dict get $d body]
	aa_log "Result body:<pre>\n[::aa_test::visualize_control_chars $xml]</pre>"

        ::caldav::test::foreach_response response $xml {
            ::acs::test::xpath::non_empty $response {
                d:href
            }
            ::acs::test::xpath::equals $response {
                d:href                                       /caldav/
                d:propstat/d:prop/d:current-user-principal   /caldav/principal
                d:propstat/d:prop/d:owner                    ""
                d:propstat/d:prop/cs:getctag                 ""
            }
        }
    } on error {errorMsg} {
	aa_true "Error msg: $errorMsg" 0
    } finally {
	#calendar::delete -calendar_id $temp_calendar_id
    }
}


aa_register_case -cats {web} -procs {
    "::caldav::CalDAV instproc PUT"
    "::caldav::CalDAV instproc REPORT"

    "::xo::ical::VEVENT instproc finish"
    "::xo::ical::VCALITEM instproc get"
    "::xo::ical::VCALITEM instproc add_recurrence"
} Thunderbird_add_event {

    Add a new event via Thunderbirld Calendar application, after
    subscribing via caldav.

} {
    set info [::caldav::test::basic_setup]
    set user_info [dict get $info user_info]

    try {
        #
        # We want a valid calendar entry without an entry in cal_uids.
        #
        set uid "bfdf5503-c795-5946-93fc-cb445f189817"

        #
        # Make sure, uid of the item to be inserted newly does not
        # exist.
        #
        set cal_info [::caldav::calendars get_calendar_and_cal_item_from_uid $uid]
        if {[llength $cal_info] > 0} {
            #
            # Someone has already inserted such an item. Remove it!
            #
            lassign [lindex $cal_info 0] calendar_id cal_item_id
            aa_log "deleting cal_item $cal_item_id with uid $uid"
            calendar::item::delete -cal_item_id $cal_item_id
        }

        #
        # PUT REQUEST
        #
        set icalText ""
        append icalText \
            {BEGIN:VCALENDAR} \r\n\
            {PRODID:-//Mozilla.org/NONSGML Mozilla Calendar V1.1//EN} \r\n\
            {VERSION:2.0} \r\n\
            {BEGIN:VTIMEZONE} \r\n\
            {TZID:Europe/Berlin} \r\n\
            {BEGIN:DAYLIGHT} \r\n\
            {TZOFFSETFROM:+0100} \r\n\
            {TZOFFSETTO:+0200} \r\n\
            {TZNAME:CEST} \r\n\
            {DTSTART:19700329T020000} \r\n\
            {RRULE:FREQ=YEARLY;BYDAY=-1SU;BYMONTH=3} \r\n\
            {END:DAYLIGHT} \r\n\
            {BEGIN:STANDARD} \r\n\
            {TZOFFSETFROM:+0200} \r\n\
            {TZOFFSETTO:+0100} \r\n\
            {TZNAME:CET} \r\n\
            {DTSTART:19701025T030000} \r\n\
            {RRULE:FREQ=YEARLY;BYDAY=-1SU;BYMONTH=10} \r\n\
            {END:STANDARD} \r\n\
            {END:VTIMEZONE} \r\n\
            {BEGIN:VEVENT} \r\n\
            {CREATED:20180402T094320Z} \r\n\
            {LAST-MODIFIED:20180402T094426Z} \r\n\
            {DTSTAMP:20180402T094426Z} \r\n\
            {UID:bfdf5503-c795-5946-93fc-cb445f189817} \r\n\
            {SUMMARY:thunderbild event} \r\n\
            {DTSTART;TZID=Europe/Berlin:20180402T150000} \r\n\
            {DTEND;TZID=Europe/Berlin:20180402T160000} \r\n\
            {TRANSP:OPAQUE} \r\n\
            {DESCRIPTION:from 3 to 4} \r\n\
            {END:VEVENT} \r\n\
            {END:VCALENDAR} \r\n\

        # item is from three to four pm
        set created [::caldav::test::ical_extract $icalText CREATED]
        set DTSTART [lindex [::caldav::test::ical_extract $icalText DTSTART] end]
        set DTEND   [lindex [::caldav::test::ical_extract $icalText DTEND]]
        set isummary [::caldav::test::ical_extract $icalText SUMMARY]

        aa_log "created $created DTSTART $DTSTART DTEND $DTEND"

	set d [::acs::test::http \
		   -user_info $user_info \
		   -method PUT \
                   -headers {Content-Type text/calendar} \
                   -body $icalText \
                   /caldav/calendar/$uid.ics]

        aa_equals "Status code valid" [dict get $d status] 201

	set d [::acs::test::http \
		   -user_info $user_info \
		   -method GET \
                   /caldav/calendar/$uid.ics]

        set rIcalText [dict get $d body]
	aa_log "Result body:<pre>\n[::aa_test::visualize_control_chars $rIcalText]</pre>"

        set rsummary     [::caldav::test::ical_extract $rIcalText SUMMARY]
        set rdescription [::caldav::test::ical_extract $rIcalText DESCRIPTION]

        aa_equals "Retrieved Ical valid" [::caldav::test::ical_valid $rIcalText] ""

        set rlocation    [::caldav::test::ical_extract $rIcalText LOCATION]
        set rsummary     [::caldav::test::ical_extract $rIcalText SUMMARY]

        aa_equals "location empty"        $rlocation ""
        aa_true   "last_modified updated" {$isummary eq $rsummary}

        #
	# REPORT request (calendar-multiget with single href, getting etag and calendar-data)
        #
        incr queryNr

	set d [::acs::test::http -prefix "$queryNr: " \
		   -user_info $user_info \
		   -method REPORT \
		   -headers {Content-Type text/xml} \
		   -body {<?xml version="1.0" encoding="UTF-8"?>
                       <C:calendar-multiget xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
                       <D:prop>
                       <D:getetag/>
                       <C:calendar-data/>
                       </D:prop>
                       <D:href>/caldav/calendar/bfdf5503-c795-5946-93fc-cb445f189817.ics</D:href>
                       </C:calendar-multiget>
		   } \
		   /caldav/calendar/]

	aa_equals "Status code valid" [dict get $d status] 207
	set xml [dict get $d body]
        aa_log "Result body:<pre>\n[::aa_test::visualize_control_chars $xml]</pre>"

        ::caldav::test::foreach_response response $xml {
            ::acs::test::xpath::non_empty $response {
                d:href
                d:propstat/d:prop/d:getetag
            }
            set href [::acs::test::xpath::get_text $response d:href]
            aa_true "href for calitem ends with .ics" [string match *ics $href]

            set icalText [::acs::test::xpath::get_text $response d:propstat/d:prop/c:calendar-data]

            aa_true "href for calitem ends with .ics" [string match *ics $href]
            aa_equals "Ical of $href valid" [::caldav::test::ical_valid -require_crlf=0 $icalText] ""
        }
    } on error {errorMsg} {
	aa_true "Error msg: $errorMsg" 0
    } finally {
	#calendar::delete -calendar_id $temp_calendar_id
    }
}



########################################################################
# macOS
########################################################################

aa_register_case -cats {web} -procs {
    "::caldav::CalDAV instproc PROPFIND"
    "::caldav::CalDAV instproc PROPPATCH"
    "::caldav::CalDAV instproc REPORT"
    "::caldav::CalDAV instproc generateResponse"

    "::caldav::CalDAV instproc returnXMLelement"
    "::caldav::CalDAV instproc calcCtag"
    "::caldav::calitem instproc as_ical_calendar"
} macOS_subscribe {

    Steps for adding CalDAV account from macOS to "Calendar".

    Open Apple Calendar
    In the toolbar, click "Calendar", then "Preferences"
    Click the "Accounts" tab
    In the accounts pane on the left, click the + button to add an account
    Select Add CalDAV account...
    Select Advanced
    Enter the following information:

    Server Path: /caldav/

} {

    set info [::caldav::test::basic_setup]
    set user_info [dict get $info user_info]

    try {
        #
        # 1. Query: principal-URL (Depth 0)
        #
        set queryNr 1
	set d [::acs::test::http -prefix "$queryNr: " \
                   -user_info $user_info \
		   -method PROPFIND \
                   -headers {Content-Type text/xml Depth 0} \
                   -body [::caldav::test::propfind_body "<D:principal-URL/>"] \
		   /caldav/]
	aa_equals "Status code valid" [dict get $d status] 207
	set xml [dict get $d body]
	aa_log "Result body:<pre>\n[::aa_test::visualize_control_chars $xml]</pre>"

        ::caldav::test::foreach_response response $xml {
            ::acs::test::xpath::non_empty $response {
                d:href
            }
            ::acs::test::xpath::equals $response {
                d:href                                       /caldav/
                d:propstat/d:prop/d:principal-URL            /caldav/principal
            }
        }

        #
        # 2. Query / multiple attributes (Depth 0)
        #
        incr queryNr
	set d [::acs::test::http -prefix "$queryNr: " \
                   -user_info $user_info \
                   -method PROPFIND \
                   -headers {Content-Type text/xml Depth 0} \
                   -body {<?xml version="1.0" encoding="UTF-8"?>
                       <A:propfind xmlns:A="DAV:">
                       <A:prop>
                       <C:calendar-home-set xmlns:C="urn:ietf:params:xml:ns:caldav"/>
                       <C:calendar-user-address-set xmlns:C="urn:ietf:params:xml:ns:caldav"/>
                       <A:current-user-principal/>
                       <A:displayname/>
                       <E:dropbox-home-URL xmlns:E="http://calendarserver.org/ns/"/>
                       <E:email-address-set xmlns:E="http://calendarserver.org/ns/"/>
                       <E:notification-URL xmlns:E="http://calendarserver.org/ns/"/>
                       <A:principal-collection-set/>
                       <A:principal-URL/>
                       <A:resource-id/>
                       <C:schedule-inbox-URL xmlns:C="urn:ietf:params:xml:ns:caldav"/>
                       <C:schedule-outbox-URL xmlns:C="urn:ietf:params:xml:ns:caldav"/>
                       <A:supported-report-set/>
                       </A:prop>
                       </A:propfind>} \
		   /caldav/]
	aa_equals "Status code valid" [dict get $d status] 207
	set xml [dict get $d body]
        aa_log "Result body:<pre>\n[::aa_test::visualize_control_chars $xml]</pre>"

        ::caldav::test::foreach_response response $xml {
            ::acs::test::xpath::non_empty $response {
                d:href
            }
            ::acs::test::xpath::equals $response {
                d:href                                       /caldav/
                d:propstat/d:prop/c:calendar-home-set        /caldav/calendar
                d:propstat/d:prop/d:current-user-principal   /caldav/principal
                d:propstat/d:prop/d:principal-URL            /caldav/principal
            }
        }
        #
        # OPTIONS request
        # .... omitted here
        #
        # 3. Query on calendar (Depth 1)
        #
        incr queryNr
	set d [::acs::test::http -prefix "$queryNr: " \
                   -user_info $user_info \
                   -method PROPFIND \
                   -headers {Content-Type text/xml Depth 1} \
                   -body {<?xml version="1.0" encoding="UTF-8"?>
                       <A:propfind xmlns:A="DAV:">
                       <A:prop>
                       <A:add-member/>
                       <E:allowed-sharing-modes xmlns:E="http://calendarserver.org/ns/"/>
                       <F:autoprovisioned xmlns:F="http://apple.com/ns/ical/"/>
                       <G:bulk-requests xmlns:G="http://me.com/_namespace/"/>
                       <C:calendar-alarm xmlns:C="urn:ietf:params:xml:ns:caldav"/>
                       <F:calendar-color xmlns:F="http://apple.com/ns/ical/"/>
                       <C:calendar-description xmlns:C="urn:ietf:params:xml:ns:caldav"/>
                       <C:calendar-free-busy-set xmlns:C="urn:ietf:params:xml:ns:caldav"/>
                       <F:calendar-order xmlns:F="http://apple.com/ns/ical/"/>
                       <C:calendar-timezone xmlns:C="urn:ietf:params:xml:ns:caldav"/>
                       <A:current-user-privilege-set/>
                       <C:default-alarm-vevent-date xmlns:C="urn:ietf:params:xml:ns:caldav"/>
                       <C:default-alarm-vevent-datetime xmlns:C="urn:ietf:params:xml:ns:caldav"/>
                       <A:displayname/>
                       <E:getctag xmlns:E="http://calendarserver.org/ns/"/>
                       <E:invite xmlns:E="http://calendarserver.org/ns/"/>
                       <F:language-code xmlns:F="http://apple.com/ns/ical/"/>
                       <F:location-code xmlns:F="http://apple.com/ns/ical/"/>
                       <A:owner/>
                       <E:pre-publish-url xmlns:E="http://calendarserver.org/ns/"/>
                       <E:publish-url xmlns:E="http://calendarserver.org/ns/"/>
                       <E:push-transports xmlns:E="http://calendarserver.org/ns/"/>
                       <E:pushkey xmlns:E="http://calendarserver.org/ns/"/>
                       <A:quota-available-bytes/>
                       <A:quota-used-bytes/>
                       <F:refreshrate xmlns:F="http://apple.com/ns/ical/"/>
                       <A:resource-id/>
                       <A:resourcetype/>
                       <C:schedule-calendar-transp xmlns:C="urn:ietf:params:xml:ns:caldav"/>
                       <C:schedule-default-calendar-URL xmlns:C="urn:ietf:params:xml:ns:caldav"/>
                       <E:source xmlns:E="http://calendarserver.org/ns/"/>
                       <E:subscribed-strip-alarms xmlns:E="http://calendarserver.org/ns/"/>
                       <E:subscribed-strip-attachments xmlns:E="http://calendarserver.org/ns/"/>
                       <E:subscribed-strip-todos xmlns:E="http://calendarserver.org/ns/"/>
                       <C:supported-calendar-component-set xmlns:C="urn:ietf:params:xml:ns:caldav"/>
                       <C:supported-calendar-component-sets xmlns:C="urn:ietf:params:xml:ns:caldav"/>
                       <A:supported-report-set/>
                       <A:sync-token/>
                       </A:prop>
                       </A:propfind>} \
		   /caldav/calendar]
	aa_equals "Status code valid" [dict get $d status] 207
	set xml [dict get $d body]
        aa_log "Result body:<pre>\n[::aa_test::visualize_control_chars $xml]</pre>"

        ::caldav::test::foreach_response response $xml {
            ::acs::test::xpath::non_empty $response {
                d:href
                d:propstat/d:prop/c:calendar-description
                d:propstat/d:prop/d:displayname
                d:propstat/d:prop/cs:getctag
            }
            ::acs::test::xpath::equals $response {
                d:href                                       /caldav/calendar/
                d:propstat/d:prop/ical:calendar-order        1
            }
        }

        #
        # 4. Query PROPPATCH setting default-alarm-vevent-date
        # Note the encoded CRs for XML.
        incr queryNr

        set ical ""
        append ical \
            {BEGIN:VALARM&#13;} \n\
            {X-WR-ALARMUID:3DC5B1FB-C20F-4DD1-AF41-06DF92E4C2A4&#13;} \n\
            {UID:3DC5B1FB-C20F-4DD1-AF41-06DF92E4C2A4&#13;} \n\
            {TRIGGER:-PT15H&#13;} \n\
            {ATTACH;VALUE=URI:Basso&#13;} \n\
            {ACTION:AUDIO&#13;} \n\
            {END:VALARM&#13;} \n
        set d [::caldav::test::proppatch \
                   -prefix "$queryNr: " \
                   -user_info $user_info \
                   /caldav/calendar default-alarm-vevent-date $ical]
	set xml [dict get $d body]
        aa_log "Result body:<pre>\n[::aa_test::visualize_control_chars $xml]</pre>"

        ::caldav::test::foreach_response response $xml {
            ::acs::test::xpath::equals $response {
                d:href                 /caldav/calendar
                d:propstat/d:status    "HTTP/1.1 403 Forbidden"
            }
        }

        #
        # 5. Query PROPPATCH setting default-alarm-vevent-datetime
        # Note the encoded CRs for XML.
        incr queryNr

        set ical ""
        append ical \
            {BEGIN:VALARM&#13;} \n\
            {X-WR-ALARMUID:41C0F75E-720F-427B-8F9F-49EDF69DB760&#13;} \n\
            {UID:41C0F75E-720F-427B-8F9F-49EDF69DB760&#13;} \n\
            {TRIGGER;VALUE=DATE-TIME:19760401T005545Z#13;} \n\
            {ATTACH;VALUE=URI:Basso&#13;} \n\
            {ACTION:NONE&#13;} \n\
            {END:VALARM&#13;} \n

        set d [::caldav::test::proppatch \
                   -user_info $user_info \
                   -prefix "$queryNr: " \
                   /caldav/calendar default-alarm-vevent-datetime $ical]
	set xml [dict get $d body]
        aa_log "Result body:<pre>\n[::aa_test::visualize_control_chars $xml]</pre>"

        ::caldav::test::foreach_response response $xml {
            ::acs::test::xpath::equals $response {
                d:href                 /caldav/calendar
                d:propstat/d:status    "HTTP/1.1 403 Forbidden"
            }
        }

        #
        # 6. Query PROPPATCH setting calendar-timezone
        # Note the encoded CRs for XML.
        incr queryNr

        set ical ""
        append ical \
            {BEGIN:VCALENDAR&#13;} \n\
            {VERSION:2.0&#13;} \n\
            {PRODID:-//Apple Inc.//macOS 10.13.3//EN&#13;} \n\
            {CALSCALE:GREGORIAN&#13;} \n\
            {BEGIN:VTIMEZONE&#13;} \n\
            {TZID:Europe/Vienna&#13;} \n\
            {BEGIN:DAYLIGHT&#13;} \n\
            {TZOFFSETFROM:+0100&#13;} \n\
            {RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU&#13;} \n\
            {DTSTART:19810329T020000&#13;} \n\
            {TZNAME:GMT+2&#13;} \n\
            {TZOFFSETTO:+0200&#13;} \n\
            {END:DAYLIGHT&#13;} \n\
            {BEGIN:STANDARD&#13;} \n\
            {TZOFFSETFROM:+0200&#13;} \n\
            {RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU&#13;} \n\
            {DTSTART:19961027T030000&#13;} \n\
            {TZNAME:GMT+1&#13;} \n\
            {TZOFFSETTO:+0100&#13;} \n\
            {END:STANDARD&#13;} \n\
            {END:VTIMEZONE&#13;} \n\
            {END:VCALENDAR&#13;} \n

        set d [::caldav::test::proppatch \
                   -user_info $user_info \
                   -prefix "$queryNr: " \
                   /caldav/calendar calendar-timezone $ical]
	set xml [dict get $d body]
        aa_log "Result body:<pre>\n[::aa_test::visualize_control_chars $xml]</pre>"

        ::caldav::test::foreach_response response $xml {
            ::acs::test::xpath::equals $response {
                d:href                 /caldav/calendar
                d:propstat/d:status    "HTTP/1.1 403 Forbidden"
            }
        }

        #
        # 7. Query PROPFIND for sync-token or getctag with Depth 0
        #
        incr queryNr

        set XMLquery {<E:getctag xmlns:E="http://calendarserver.org/ns/"/><D:sync-token/>}
	set d [::acs::test::http \
                   -prefix "$queryNr: " \
                   -user_info $user_info \
		   -method PROPFIND \
		   -headers {Content-Type text/xml Depth 0} \
		   -body [::caldav::test::propfind_body $XMLquery] \
		   /caldav/calendar]
	aa_equals "Status code valid" [dict get $d status] 207
        set xml [dict get $d body]
        aa_log "Result body:<pre>\n[::aa_test::visualize_control_chars $xml]</pre>"

        ::caldav::test::foreach_response response $xml {
            ::acs::test::xpath::equals $response {
                d:href                          /caldav/calendar/
                d:propstat/d:prop/d:sync-token  ""
            }
            ::acs::test::xpath::non_empty $response {
                d:propstat/d:prop/cs:getctag
            }
        }

        #
	# 8. Query REPORT for etags and getcontenttype
        # TODO: filter + calendar-query guessed, has to corrected for macOS client
        #
        incr queryNr

	set d [::acs::test::http -prefix "$queryNr: " \
                   -user_info $user_info \
                   -method REPORT \
		   -headers {Content-Type text/xml} \
		   -body {<?xml version="1.0" encoding="UTF-8"?>
                       <B:calendar-query xmlns:B="urn:ietf:params:xml:ns:caldav">
                       <A:prop xmlns:A="DAV:">
                       <A:getetag/>
                       <A:getcontenttype/>
                       </A:prop>
                       <B:filter>
                       <B:comp-filter name="VCALENDAR">
                       <B:comp-filter name="VEVENT">
                       <B:time-range start="20180221T000000Z"/>
                       </B:comp-filter>
                       </B:comp-filter>
                       </B:filter>
                       </B:calendar-query>
		   } \
		   /caldav/calendar/]

	aa_equals "Status code valid" [dict get $d status] 207
	set xml [dict get $d body]
        aa_log "Result body:<pre>\n[::aa_test::visualize_control_chars $xml]</pre>"

        ::caldav::test::foreach_response response $xml {
            ::acs::test::xpath::non_empty $response {
                d:href
                d:propstat/d:prop/d:getetag
                d:propstat/d:prop/d:getcontenttype
            }
            set href [::acs::test::xpath::get_text $response d:href]
            aa_true "href for calitem ends with .ics" [string match *ics $href]
        }

	# 9. Query REPORT for etags and calendar-data
        # TODO: filter + calendar-query guessed, has to corrected for macOS client
        #
        incr queryNr

	set d [::acs::test::http -prefix "$queryNr: " \
                   -user_info $user_info \
		   -method REPORT \
		   -headers {Content-Type text/xml} \
		   -body {<?xml version="1.0" encoding="UTF-8"?>
                       <B:calendar-query xmlns:B="urn:ietf:params:xml:ns:caldav">
                       <A:prop xmlns:A="DAV:">
                       <A:getetag/>
                       <B:calendar-data/>
                       </A:prop>
                       <B:filter>
                       <B:comp-filter name="VCALENDAR">
                       <B:comp-filter name="VEVENT">
                       <B:time-range start="20180221T000000Z"/>
                       </B:comp-filter>
                       </B:comp-filter>
                       </B:filter>
                       </B:calendar-query>
		   } \
		   /caldav/calendar/]

	aa_equals "Status code valid" [dict get $d status] 207
	set xml [dict get $d body]
        aa_log "Result body:<pre>\n[::aa_test::visualize_control_chars $xml]</pre>"

        ::caldav::test::foreach_response response $xml {
            ::acs::test::xpath::non_empty $response {
                d:href
                d:propstat/d:prop/d:getetag
                d:propstat/d:prop/c:calendar-data
            }
            set href [::acs::test::xpath::get_text $response d:href]
            set icalText [::acs::test::xpath::get_text $response d:propstat/d:prop/c:calendar-data]
            #aa_log CHECK=[::aa_test::visualize_control_chars $icalText]

            aa_true "href for calitem ends with .ics" [string match *ics $href]
            aa_equals "Ical of $href valid" [::caldav::test::ical_valid -require_crlf=0 $icalText] ""
        }

        #
        # 10. Query PROPFIND for checksum-versions with Depth 0
        # .... not clear what it can return, all checked clients ignore this
        #
        incr queryNr

        set XMLquery {<E:checksum-versions xmlns:E="http://calendarserver.org/ns/"/>}
	set d [::acs::test::http -prefix "$queryNr: " \
                   -user_info $user_info \
		   -method PROPFIND \
		   -headers {Content-Type text/xml Depth 0} \
		   -body [::caldav::test::propfind_body $XMLquery] \
		   /caldav/calendar]
	aa_equals "Status code valid" [dict get $d status] 207
        set xml [dict get $d body]
        aa_log "Result body:<pre>\n[::aa_test::visualize_control_chars $xml]</pre>"

        #
        # 11. Query PROPFIND for getctag with Depth 0
        #
        incr queryNr

        set XMLquery {<E:getctag xmlns:E="http://calendarserver.org/ns/"/>}
	set d [::acs::test::http -prefix "$queryNr: " \
                   -user_info $user_info \
		   -method PROPFIND \
		   -headers {Content-Type text/xml Depth 0} \
		   -body [::caldav::test::propfind_body $XMLquery] \
		   /caldav/calendar]
	aa_equals "Status code valid" [dict get $d status] 207
        set xml [dict get $d body]
        aa_log "Result body:<pre>\n[::aa_test::visualize_control_chars $xml]</pre>"

        ::caldav::test::foreach_response response $xml {
            ::acs::test::xpath::equals $response {
                d:href                          /caldav/calendar/
            }
            ::acs::test::xpath::non_empty $response {
                d:propstat/d:prop/cs:getctag
            }
        }

        #
        # 12. Query PROPFIND for etag and contenttype Depth 1
        #
        incr queryNr

	set d [::acs::test::http -prefix "$queryNr: " \
		   -user_info $user_info \
		   -method PROPFIND \
		   -headers {Content-Type text/xml Depth 1} \
		   -body [::caldav::test::propfind_body "<D:getcontenttype/><D:getetag/>"] \
		   /caldav/calendar]
	aa_equals "Status code valid" [dict get $d status] 207
        set xml [dict get $d body]
        aa_log "Result body:<pre>\n[::aa_test::visualize_control_chars $xml]</pre>"

        set nrEtags 0
        ::caldav::test::foreach_response response $xml {
            set href [::acs::test::xpath::get_text $response d:href]
            if {[string match *.ics $href]} {
                ::acs::test::xpath::non_empty $response {
                    d:propstat/d:prop/d:getetag
                    d:propstat/d:prop/d:getcontenttype
                }
                incr nrEtags
            }
        }
        aa_true "Got multiple etags: $nrEtags" {$nrEtags >= 3}

    } on error {errorMsg} {
	aa_true "Error msg: $errorMsg" 0
    } finally {
	#calendar::delete -calendar_id $temp_calendar_id
    }
}

aa_register_case -cats {web} -procs {
    "::caldav::CalDAV instproc PUT"
} macOS_add_location {

    Add a location via macOS Calendar application.

    Go to calendar entry in macOS Calendar on a calendar item (without
    a registered UID) and add an Apple location (APPLE-STRUCTURED-LOCATION)

} {
    set info [::caldav::test::basic_setup]
    set user_info [dict get $info user_info]

    try {
        #
        # We want a valid calendar entry without an entry in cal_uids.
        #
        # Get form the user calendar the first (lowest) uid
        #
        set uid [::caldav::test::get_lowest_uid -user_info $user_info]
        aa_log "get_lowest_uid -> '$uid' ($user_info)"

        set d [::acs::test::http \
                   -user_info $user_info \
                   -method GET \
                   /caldav/calendar/$uid.ics]

        set originalIcalText [dict get $d body]
        aa_log "Result body:<pre>\n[::aa_test::visualize_control_chars $originalIcalText]</pre>"
        aa_equals "Original Ical valid" [::caldav::test::ical_valid $originalIcalText] ""

        set olocation      [::caldav::test::ical_extract $originalIcalText LOCATION]
        set olast_modified [::caldav::test::ical_extract $originalIcalText LAST-MODIFIED]
        aa_log "location: $olocation"
        aa_log "last-mod: $olast_modified"
        set icalText ""
        append icalText \
            {BEGIN:VCALENDAR} \r\n\
            {VERSION:2.0} \r\n\
            {PRODID:-//Apple Inc.//macOS 10.13.3//EN} \r\n\
            {CALSCALE:GREGORIAN} \r\n\
            {BEGIN:VEVENT} \r\n\
            {CREATED:20190420T120804Z} \r\n\
            {LAST-MODIFIED:20190420T120804Z} \r\n\
            {DTSTAMP:20190420T120804Z} \r\n\
            {DTSTART:20190420T111933Z} \r\n\
            {DTEND:20190420T121933Z} \r\n\
            "UID:$uid" \r\n\
            {DESCRIPTION:my first private entry} \r\n\
            {SUMMARY:remember!} \r\n\
            {TRANSP:OPAQUE} \r\n\
            {LOCATION:WU Wien\nWelthandelsplatz 1\, 1020 Vienna\, Austria} \r\n\
            {SEQUENCE:0} \r\n\
            {X-APPLE-TRAVEL-ADVISORY-BEHAVIOR:AUTOMATIC} \r\n\
            {X-APPLE-STRUCTURED-LOCATION;VALUE=URI;X-APPLE-MAPKIT-HANDLE=CAES/wEIrk0Q} \r\n\
            { 0rr2qKC0qb5cGhIJJLddQ14bSEARAAAAeLRoMEAihAEKB0F1c3RyaWESAkFUGgZWaWVubmEy} \r\n\
            { BlZpZW5uYToEMTAyMFISV2VsdGhhbmRlbHNwbGF0eiAxWgExYhJXZWx0aGFuZGVsc3BsYXR6} \r\n\
            { IDFyHFdpcnRzY2hhZnRzdW5pdmVyc2l0w6R0IFdpZW6KAQZCZXppcmuKAQxMZW9wb2xkc3Rh} \r\n\
            { ZHQqK1ZpZW5uYSBVbml2ZXJzaXR5IG9mIEVjb25vbWljcyBhbmQgQnVzaW5lc3MyEldlbHRo} \r\n\
            { YW5kZWxzcGxhdHogMTILMTAyMCBWaWVubmEyB0F1c3RyaWE=;X-APPLE-RADIUS=6267.432} \r\n\
            { 12890625;X-TITLE="WU Wien\nWelthandelsplatz 1, 1020 Vienna, Austria":geo} \r\n\
            { :48.213814,16.409004} \r\n\
            {BEGIN:VALARM} \r\n\
            {X-WR-ALARMUID:05AD14A0-51DA-411C-9D8C-57C991801196} \r\n\
            {UID:05AD14A0-51DA-411C-9D8C-57C991801196} \r\n\
            {TRIGGER:-PT15H} \r\n\
            {X-APPLE-DEFAULT-ALARM:TRUE} \r\n\
            {ATTACH;VALUE=URI:Basso} \r\n\
            {ACTION:AUDIO} \r\n\
            {END:VALARM} \r\n\
            {END:VEVENT} \r\n\
            {END:VCALENDAR} \r\n

        set d [::acs::test::http \
                   -user_info $user_info \
                   -method PUT \
                   -headers {Content-Type text/calendar If-Match db70bfb110288c02f6f0a0e3c862ce8e} \
                   -body $icalText \
                   /caldav/calendar/$uid.ics]

        aa_equals "Status code valid" [dict get $d status] 201
        set mlocation      [::caldav::test::ical_extract $icalText LOCATION]
        set mlast_modified [::caldav::test::ical_extract $icalText LAST-MODIFIED]
        set d [::acs::test::http \
                   -user_info $user_info \
                   -method GET \
                   /caldav/calendar/$uid.ics]

        set updatedIcalText [dict get $d body]
        aa_log "Retrieved modified ical text:<pre>\n[::aa_test::visualize_control_chars $updatedIcalText]</pre>"
        aa_equals "updated Ical valid" [::caldav::test::ical_valid $updatedIcalText] ""

        set ulocation      [::caldav::test::ical_extract $updatedIcalText LOCATION]
        set ulast_modified [::caldav::test::ical_extract $updatedIcalText LAST-MODIFIED]

        set alarm_uid      [::caldav::test::ical_extract $updatedIcalText X-WR-ALARMUID]
        set structured_loc [::caldav::test::ical_extract $updatedIcalText X-APPLE-STRUCTURED-LOCATION]

        aa_equals "location preserved"    $mlocation $ulocation
        aa_true   "last_modified updated" {$mlast_modified ne $ulast_modified}
        aa_true   "alarm_uid not empty"   {$alarm_uid ne ""}
        set len   [string length $structured_loc]
        aa_true   "structured_locaction not empty (len $len)" {$len > 10}


    } on error {errorMsg} {
        aa_true "Error msg: $errorMsg" 0
    } finally {
        #calendar::delete -calendar_id $temp_calendar_id
    }
}


aa_register_case -cats {web} -procs {
    "::caldav::CalDAV instproc PUT"

    "::caldav::calitem instproc add_ical_var"
} macOS_add_event {

    Add a new event via macOS Calendar application.

    Go to calendar entry in macOS Calendar and add a new calendar entry.

} {
    set info [::caldav::test::basic_setup]
    set user_info [dict get $info user_info]

    try {
        #
        # We want a valid calendar entry without an entry in cal_uids.
        #
        set uid 8750

        set uid "23009F17-383F-4FBD-92D4-AB0F27CF7326"

        #
        # Make sure, uid of the item to be inserted newly does not
        # exist.
        #
        set cal_info [::caldav::calendars get_calendar_and_cal_item_from_uid $uid]
        if {[llength $cal_info] > 0} {
            #
            # Someone has already inserted such an item. Remove it!
            #
            lassign [lindex $cal_info 0] calendar_id cal_item_id
            aa_log "deleting cal_item $cal_item_id with uid $uid"
            calendar::item::delete -cal_item_id $cal_item_id
        }

        set icalText ""
        append icalText \
            {BEGIN:VCALENDAR} \r\n\
            {VERSION:2.0} \r\n\
            {PRODID:-//Apple Inc.//macOS 10.13.3//EN} \r\n\
            {CALSCALE:GREGORIAN} \r\n\
            {BEGIN:VTIMEZONE} \r\n\
            {TZID:Europe/Vienna} \r\n\
            {BEGIN:DAYLIGHT} \r\n\
            {TZOFFSETFROM:+0100} \r\n\
            {RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU} \r\n\
            {DTSTART:19810329T020000} \r\n\
            {TZNAME:GMT+2} \r\n\
            {TZOFFSETTO:+0200} \r\n\
            {END:DAYLIGHT} \r\n\
            {BEGIN:STANDARD} \r\n\
            {TZOFFSETFROM:+0200} \r\n\
            {RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU} \r\n\
            {DTSTART:19961027T030000} \r\n\
            {TZNAME:GMT+1} \r\n\
            {TZOFFSETTO:+0100} \r\n\
            {END:STANDARD} \r\n\
            {END:VTIMEZONE} \r\n\
            {BEGIN:VEVENT} \r\n\
            {CREATED:20180401T165215Z} \r\n\
            {UID:23009F17-383F-4FBD-92D4-AB0F27CF7326} \r\n\
            {DTEND;TZID=Europe/Vienna:20180402T100000} \r\n\
            {TRANSP:OPAQUE} \r\n\
            {X-APPLE-TRAVEL-ADVISORY-BEHAVIOR:AUTOMATIC} \r\n\
            {SUMMARY:a new event} \r\n\
            {DTSTART;TZID=Europe/Vienna:20180402T090000} \r\n\
            {DTSTAMP:20180401T165246Z} \r\n\
            {SEQUENCE:0} \r\n\
            {END:VEVENT} \r\n\
            {END:VCALENDAR} \r\n\

        set created [::caldav::test::ical_extract $icalText CREATED]
        set DTSTART [lindex [::caldav::test::ical_extract $icalText DTSTART] end]
        set DTEND   [lindex [::caldav::test::ical_extract $icalText DTEND]]

        aa_log "created $created DTSTART $DTSTART DTEND $DTEND"

        #======== <DTSTART;TZID=Europe/Vienna:20180402T090000>
        #set_date_time: set_date_time parses 20180402 090000 0 -> 2018-04-02 09:00

        # ======== <DTEND;TZID=Europe/Vienna:20180402T100000>
        # set_date_time: set_date_time parses 20180402 100000 0 -> 2018-04-02 10:00

        # X-WR-CALNAME:Main Site Calendar for Gustaf Neumann
        # PRODID:-//OpenACS//OpenACS 6.0 MIMEDIR//EN
        # CALSCALE:GREGORIAN
        # VERSION:2.0
        # METHOD:PUBLISH
        # BEGIN:VEVENT
        # CREATED:20180402T081947Z
        # LAST-MODIFIED:20180402T082620Z
        # DTSTAMP:20180402T081947Z
        # DTSTART:20180402T100000Z
        # DTEND:20180402T110000Z
        # UID:15012
        # DESCRIPTION:1h
        # SUMMARY:high noon (created in OpenACS)
        # SEQUENCE:0
        # END:VEVENT
        # END:VCALENDAR

        # BEGIN:VCALENDAR
        # VERSION:2.0
        # PRODID:-//Apple Inc.//macOS 10.13.3//EN
        # CALSCALE:GREGORIAN
        # BEGIN:VTIMEZONE
        # TZID:Europe/Vienna
        # BEGIN:DAYLIGHT
        # TZOFFSETFROM:+0100
        # RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU
        # DTSTART:19810329T020000
        # TZNAME:GMT+2
        # TZOFFSETTO:+0200
        # END:DAYLIGHT
        # BEGIN:STANDARD
        # TZOFFSETFROM:+0200
        # RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU
        # DTSTART:19961027T030000
        # TZNAME:GMT+1
        # TZOFFSETTO:+0100
        # END:STANDARD
        # END:VTIMEZONE
        # BEGIN:VEVENT
        # CREATED:20180402T084642Z
        # UID:6B1BDFCB-A069-4BEB-82EB-C3DF13925772
        # DTEND;TZID=Europe/Vienna:20180402T180000
        # SUMMARY:tea time (from Calendar)
        # DTSTART;TZID=Europe/Vienna:20180402T170000
        # DTSTAMP:20180402T084755Z
        # SEQUENCE:0
        # DESCRIPTION:from Calendar
        # END:VEVENT
        # END:VCALENDAR


	set d [::acs::test::http \
                   -user_info $user_info \
		   -method PUT \
                   -headers {Content-Type text/calendar} \
                   -body $icalText \
                   /caldav/calendar/$uid.ics]

        aa_equals "Status code valid" [dict get $d status] 201
        set isummary [::caldav::test::ical_extract $icalText SUMMARY]

	set d [::acs::test::http \
		   -user_info $user_info \
		   -method GET \
                   /caldav/calendar/$uid.ics]

	set rIcalText [dict get $d body]
	aa_log "Result body:<pre>\n[::aa_test::visualize_control_chars $rIcalText]<pre>"
        aa_equals "Retrieved Ical valid" [::caldav::test::ical_valid $rIcalText] ""

        set rlocation    [::caldav::test::ical_extract $rIcalText LOCATION]
        set rsummary     [::caldav::test::ical_extract $rIcalText SUMMARY]

        aa_equals "location empty"        $rlocation ""
        aa_true   "last_modified updated" {$isummary eq $rsummary}

    } on error {errorMsg} {
	aa_true "Error msg: $errorMsg" 0
    } finally {
	#calendar::delete -calendar_id $temp_calendar_id
    }
}

#
# Local variables:
#    mode: tcl
#    tcl-indent-level: 4
#    indent-tabs-mode: nil
# End:
