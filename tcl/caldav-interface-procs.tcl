ad_library {
    CalDav implementation for OpenACS. Abstraction between calendars
    and items Parsing, formatting, retrieving calendar items.

    @author Gustaf Neumann
    @author marmoser@wu.ac.at
    @creation-date Jan, 2017
}

::xo::library require caldav-item-procs

namespace eval ::caldav {}

nx::Object create ::caldav::calendars {
    #
    #  The class "calendars" implements the interface to the database
    #  structures.
    #

    :object method debug {msg} {
        ns_log Debug(caldav) "[uplevel current proc]: $msg"
    }

    # TODO move get_sync_calendar here
    #
    :public object method format_recurrence {
        {-recurrence_id:integer,0..1}
    } {
        # Return the recurrence specification in form of a formatted
        # ical RRULE.  @param recurrence_id is the unique id of the
        # recurrence item.

        if {$recurrence_id eq ""} {
            return ""
        }
        #ns_log notice "recurrence_id $recurrence_id"
        set recur_rule "RRULE:FREQ="

        ::xo::dc 1row -prepare integer select_recurrence {
            select
                recurrence_id,
                recurrences.interval_type,
                interval_name,
                every_nth_interval,
                days_of_week,
                recur_until
            from
                recurrences,
                recurrence_interval_types
            where recurrence_id= :recurrence_id
            and   recurrences.interval_type = recurrence_interval_types.interval_type
        }

        switch -glob $interval_name {
            day      { append recur_rule "DAILY" }
            week     { append recur_rule "WEEKLY" }
            *month*  { append recur_rule "MONTHLY"}
            year     { append recur_rule "YEARLY"}
        }

        if { $interval_name eq "week"
             && $days_of_week ne ""
         } {
            #DRB: Standard indicates ordinal week days are OK, but Outlook
            #only takes two-letter abbreviation form.

            set week_list [list "SU" "MO" "TU" "WE" "TH" "FR" "SA" "SU"]
            set rec_list [list]
            foreach day [split $days_of_week " "] {
                lappend rec_list [lindex $week_list $day]
            }
            append recur_rule ";BYDAY=" [join $rec_list ,]
        }

        if {$every_nth_interval ne ""} {
            append recur_rule ";INTERVAL=$every_nth_interval"
        }

        if {$recur_until ne ""} {
            set stamp [string range $recur_until 0 18]
            append recur_rule ";UNTIL=" [xo::ical tcl_time_to_utc $stamp]
        }

        #ns_log notice "recur_rule $recur_rule"
        return [::xo::ical reflow_content_line $recur_rule]\r\n
    }


    :public object method get_cal_item_from_uid {
        {-calendar_ids:integer,0..n}
        uid
    } {
        # @return for a uid the cal_item_id(s?)
        # @param uid unique id of an calendar item

        #
        # GN TODO:
        #
        # - document, why and how the or test "e.activity_id = :uid" is
        #   needed this looks like a hack, since the UID can be modified
        #   by a calendar client, we can't assume that this is the same
        #   as some OpenACS id.
        #
        # - when the uid refers to a recurrence item, multiple
        #   cal_item_ids are returned. (a) is this needed (maybe limit
        #   1 is sufficient)? (b) is this handled everywhere
        #   correctly? (c) if needed, name should be change to
        #   get_cal_items_from_uid
        #
        # - HOW ABOUT using activity_id instead of the cal_item_id... such as get_activity_from_uid
        #
        # - probably base on get_calendar_and_cal_item_from_uid
        #
        #
        if {[llength $calendar_ids] > 1} {
            set calclause "in ( [template::util::tcl_to_sql_list $calendar_ids] )"
        } elseif {[llength $calendar_ids] eq 0} {
            return 0
        } else {
            set calclause "= :calendar_ids"
        }
        set e_clause [expr {[string is integer $uid] ? " or e.activity_id = :uid" : ""}]

        return [::xo::dc list get_cal_item_from_uid [subst {
            select cal_item_id
            from cal_items c, acs_events e
            left outer join cal_uids u on u.on_which_activity = e.activity_id
            where c.cal_item_id = e.event_id
            and ( u.cal_uid = :uid
                  $e_clause
                  )
            and  c.on_which_calendar $calclause
            order by 1 desc
        }]]
    }

    :public object method get_calendar_and_cal_item_from_uid {
        {-calendar_ids:integer,0..n}
        uid
    } {
        # @return for a uid the cal_item_id(s?)
        # @param uid unique id of an calendar item

        #
        # GN TODO:
        #
        # - see above... get_cal_item_from_uid
        #
        # The following query is tricky, since it avoids
        # an error "invalid input syntax for integer" on uids like
        #
        #     23009F17-383F-4FBD-92D4-AB0F27CF7326
        #
        # needs probably work for Oracle.
        #
        return [::xo::dc list_of_lists query_calendar_and_cal_item {
            select c.on_which_calendar, c.cal_item_id
            from acs_events e, cal_items c
            where e.activity_id in
            (
             select CASE WHEN :uid !~ '^[0-9]+$' THEN NULL ELSE :uid ::text::integer END
             union (select on_which_activity from cal_uids where cal_uid = :uid)
            )
            and c.cal_item_id = e.event_id
            order by 2 desc
            limit 1
        }]

        # set e_clause [expr {[string is integer $uid] ? " or e.activity_id = :uid" : ""}]
        #
        # - we could pass-in a calendar-clause, would save a query in
        #   the PUT case
        #if {[llength $calendar_ids] > 1} {
        #    set calclause "in ( [template::util::tcl_to_sql_list $calendar_ids] )"
        #} elseif {[llength $calendar_ids] eq 0} {
        #    return 0
        #} else {
        #    set calclause "= :calendar_ids"
        #}

        # return [::xo::dc list query_calendar_and_cal_item [subst {
        #     select c.on_which_calendar, cal_item_id
        #     from cal_items c, acs_events e
        #     left outer join cal_uids u on u.on_which_activity = e.activity_id
        #     where c.cal_item_id = e.event_id
        #     and ( u.cal_uid = :uid $e_clause )
        #     and  c.on_which_calendar $calclause
        #     order by 2 desc}]]

    }


    :public object method alwaysQueriedCalendars {
        {-with_sync_calendar:boolean true}
        user_id:integer
    } {
        lappend calendar_ids {*}[::caldav::get_public_calendars]
        if {$with_sync_calendar} {
            lappend calendar_ids [::caldav::get_sync_calendar -user_id $user_id]
        }
        return $calendar_ids
    }

    :public object method alwaysQueriedClause {
        user_id:integer
    } {
        set calendar_ids [:alwaysQueriedCalendars $user_id]
        if {[llength $calendar_ids] > 0} {
            set values [::xo::db::list_to_values $calendar_ids integer]
            set result [list "select calendar_id from $values as values(calendar_id)"]
        } else {
            set result {}
        }
        return $result
    }

    :public object method communityCalendarClause {
        user_id:integer
    } {
        #
        # Get calendars from communities, when DotLRN is active.
        #
        if {[info commands ::dotlrn_calendar::my_package_key] ne ""} {
            set result [list "
                WITH communities AS (
                                     select distinct dcc.community_id
                                     from dotlrn_communities_core dcc
                                     inner join dotlrn_member_rels_approved dma
                                     on dcc.community_id = dma.community_id
                                     and dma.user_id = $user_id
                                     and dcc.archived_p = 'f'
                                     )
                select calendar_id
                from communities m, calendars c
                join dotlrn_community_applets a on (a.package_id = c.package_id)
                join dotlrn_applets ap on (ap.applet_id = a.applet_id) where
                ap.package_key = 'dotlrn-calendar' and
                a.community_id = m.community_id
            "]
        } else {
            set result {}
        }
        return $result
    }

    :public object method calendar_clause {
        {-calendar_ids:integer,0..n ""}
        {-user_id:integer}
        {-attr c.on_which_calendar}
    } {
        #
        # When calendar_ids are empty, user_id has to be specified
        #

        if {$calendar_ids eq ""} {
            lappend clauses \
                {*}[:communityCalendarClause $user_id] \
                {*}[:alwaysQueriedClause $user_id]
            set clause [subst { and $attr in ([join $clauses " union "]) }]
        } elseif {[llength $calendar_ids] == 1} {
            set clause [subst {and $attr = :calendar_ids}]
        } else {
            set clause [subst {and $attr in ( [template::util::tcl_to_sql_list $calendar_ids] )}]
        }
        :debug calendar_clause=$clause-calendar_ids=$calendar_ids
        return $clause
    }


    #
    # API for selecting calendar items
    #
    :public object method get_calitems {
        {-user_id:integer ""}
        {-start_date ""}
        {-end_date ""}
        {-calendar_ids:integer,0..n ""}
    } {
        #
        # Get feed of calendar items for a given user.
        #
        # @return list set of calendar item objects

        :debug "get_calitems [current args]"

        if {$start_date ne "" && $end_date ne ""} {
            set time_limitation_clause [subst { and start_date between
                to_timestamp('$start_date','YYYY-MM-DD HH24:MI:SS')
                and to_timestamp('$end_date', 'YYYY-MM-DD HH24:MI:SS')
            }]
        } else {
            set time_limitation_clause ""
        }

        set eventlist {}
        set recurrences {}

        #
        # Note that we can have items without a entry in cal_uids for
        # these we will use the activity_id as uid calendars of
        # communities, personal calendars, and public calendars in the
        # same package as the personal calendar-
        #
        foreach item [::xo::dc list_of_lists cal_items [subst {
            select md5(last_modified::text) as etag,
            coalesce(cal_uid, e.activity_id::varchar),
            ical_vars,
            on_which_calendar,
            c.item_type_id,
            to_char(start_date, 'YYYY-MM-DD HH24:MI:SS'),
            to_char(end_date, 'YYYY-MM-DD HH24:MI:SS'),
            coalesce(e.name, a.name),
            coalesce(e.description, a.description),
            c.cal_item_id,
            recurrence_id,
            creation_date,
            last_modified
            from
            acs_objects ao, acs_events e
            left outer join cal_uids u on u.on_which_activity = e.activity_id,
            acs_activities a, timespans s,
            time_intervals t, cal_items c
            where e.event_id = ao.object_id
            and a.activity_id = e.activity_id
            and c.cal_item_id = e.event_id
            and e.timespan_id = s.timespan_id
            and s.interval_id = t.interval_id
            $time_limitation_clause
            [:calendar_clause -calendar_ids $calendar_ids -user_id $user_id]
            order by start_date asc
        }]] {

            lassign $item \
                etag cal_uid ical_vars calendar_id item_type \
                start_date end_date name description \
                cal_item_id recurrence_id creation_date last_modified

            #ns_log notice "get_calitems: item $cal_item_id calendar $calendar_id" \
                "we got an recurrence <$recurrence_id>"

            if {$recurrence_id ne "" && $recurrence_id in $recurrences} {
                #
                # Don't report calendar items with recurrence multiple
                # times.
                #
                continue
            }
            set caldavItem [::caldav::calitem new \
                                -uid $cal_uid \
                                -ical_vars $ical_vars \
                                -etag $etag \
                                -creation_date $creation_date \
                                -last_modified $last_modified \
                                -dtstart $start_date \
                                -is_day_item [dt_no_time_p -start_time $start_date -end_time $end_date] \
                                -formatted_recurrences [:format_recurrence -recurrence_id $recurrence_id] \
                                -dtend $end_date \
                                -summary $name \
                                -description $description \
                               ]

            $caldavItem destroy_on_cleanup
            lappend eventlist $caldavItem
            lappend recurrences $recurrence_id
        }
        return $eventlist
    }
}


caldav::calendars eval {
    # TODO: should be probably moved to the ical procs.

    set :opaque_tags {CATEGORIES CLASS COMMENT GEO
        PERCENT-COMPLETE PRIORITY RESOURCES STATUS SEQUENCE URL
        X-APPLE-STRUCTURED-LOCATION
    }

    :object method set_date_time {date time utc:boolean tz} {
        #
        # Format a date-time value based on the provided date and time
        # components, optionally in utc. This function is just used be
        # the ical parser.
        #
        # GN TODO: TZ is currently ignored, we assume, if not UTC, then
        # use localtime of the host.
        #
        set clock [::xo::ical date_time_to_clock $date $time $utc]
        #:debug "set_date_time parses $date $time $utc ($tz)-> [::xo::ical clock_to_oacstime $clock]"
        return [::xo::ical clock_to_oacstime $clock]
    }

    :public object method parse {
        text
    } {
        #
        # Parse the ical file passed in as string and output a list of
        # CalItem objects. The attributes specified in opaque_tags are
        # passed as opaque values. Opaque attributes are not shown in
        # OpenACS, but output when the calendar item is requested in
        # ical format.
        #
        # @param text the text do be parsed
        #
        # TODO: this should go into ical-procs..... but first check dependencies
        # - $item add_ical_var ....
        # - ::caldav::calitem new

        set parse_error 0
        set in_valarm 0
        set in_vevent 0
        set item_list {}
        #opaque_tags are the tags that will be persisted in ical_vars
        set opaque_re ^([join ${:opaque_tags} |]):(.*)$
        :debug opaque_re=$opaque_re
        set prefix ""
        regsub -all "\n " $text "" text
        regsub -all "\r" $text "" text
        foreach line [split $text \n] {
            ns_log notice "======== <$line>"
            if {$in_valarm} {
                #
                # treat everything in an VALARM as opaque for the time being
                #
                append :OPAQUE-VALARM $line\r\n
                if { $line eq "END:VALARM"} {
                    # end of valarm section
                    set in_valarm 0
                    $item add_ical_var OPAQUE-VALARM "" [set :OPAQUE-VALARM]
                }
            } elseif { $in_vevent && [regexp $opaque_re $line _ tag value] } {
                $item add_ical_var $tag "" [::xo::ical ical_to_text $value]
            } elseif { $line eq "BEGIN:VEVENT" } {
                # reset values
                set in_valarm 0
                set in_vevent 1
                set r_error 0
                #
                #setting a creation date is only needed for debugging
                #
                # GN TODO: DO NOT HARDCODE calitem HERE!
                #
                set item [::caldav::calitem new \
                              -description "" \
                              -creation_date [xo::ical clock_to_utc [clock seconds]]]
                $item destroy_on_cleanup
                #$item set description ""
                #$item set creation_date  [xo::ical clock_to_utc [clock seconds]]
                lappend item_list $item
            } elseif { $line eq {BEGIN:VALARM} } {
                # begin of VALARM section
                set in_valarm 1
                set :OPAQUE-VALARM $line\r\n
            } elseif { $in_vevent && [regexp {^LOCATION[^:]*:(.*)$} $line _ location] } {
                $item location set [::xo::ical ical_to_text $location]
            } elseif { $in_vevent && [regexp {^SUMMARY[^:]*:(.*)$} $line _ title] } {
                $item summary set [::xo::ical ical_to_text $title]
            } elseif { $in_vevent && [regexp {^(DTSTAMP|UID|LAST-MODIFIED)[^:]*:(.*)$} $line _ field entry] } {
                $item [string tolower $field] set $entry
            } elseif { $in_vevent && [regexp {^DTSTART(\;TZID.*)?:([0-9]+)T+([0-9]+)(Z?).*$} $line _ tz date time utc] } {
                if {[string length $date] != 8 || [string length $time] != 6} {
                    set parse_error 1
                } else {
                    $item dtstart set [:set_date_time $date $time [expr {$utc ne ""}] $tz]
                }
            } elseif { $in_vevent && [regexp {^DTSTART.+DATE[^:]*:([0-9]+).*$} $line _ date] } {
                if {[string length $date] != 8} {
                    set parse_error 1
                } else {
                    $item dtstart set [:set_date_time $date "0000" 0 ""]
                }
            } elseif { $in_vevent && [regexp {^DTEND(\;TZID.*)?[^:]*:([0-9]+)T+([0-9]+)(Z?).*$} $line _ tz date time utc] } {
                if {[string length $date] != 8 || [string length $time] != 6} {
                    set parse_error 1
                } else {
                    $item dtend set [:set_date_time $date $time [expr {$utc ne ""}] $tz]
                }
            } elseif { $in_vevent && [regexp {^DTEND.+?DATE[^:]*:([0-9]+).*$} $line _ date ] } {
                if {[string length $date] != 8} {
                    set parse_error 1
                } else {
                    $item dtend set [:set_date_time $date "0000" 0 ""]
                }
            } elseif {$in_vevent && [regexp {^DURATION[^:]*:P(.*)$} $line _ duration] } {
                $item duration set 0
                if {[regexp {^([0-9]+)W(.*)$} $duration _ units duration]} {
                    $item incr duration [expr {[util::trim_leading_zeros $units]*24*3600*7}]
                }
                if {[regexp {([0-9]+)D(.*)$} $duration _ units duration]} {
                    $item incr duration [expr {[util::trim_leading_zeros $units]*24*3600}]
                }
                if {[regexp {([0-9]+)H(.*)$} $duration _ units duration]} {
                    $item incr duration [expr {[util::trim_leading_zeros $units]*3600}]
                }
                if {[regexp {([0-9]+)M(.*)$} $duration _ units duration]} {
                    $item incr duration [expr {[util::trim_leading_zeros $units]*60}]
                }
                if {[regexp {([0-9]+)S(.*)$} $duration _ units duration]} {
                    $item incr duration [util::trim_leading_zeros $units]
                }
            } elseif {$in_vevent && [regexp {^DESCRIPTION[^:]*:(.*)$} $line _ desc] } {
                $item description set [::xo::ical ical_to_text $desc]
            }  elseif {$in_vevent && [regexp {^URL[^:]*:(.*)$} $line _ desc] } {
                $item add_ical_var URL "" [::xo::ical ical_to_text $desc]
            } elseif { $in_vevent && [regexp {^RRULE[^:]*:(.*)$} $line _ recurrule] } {
                $item parse RRULE $recurrule
            } elseif { $in_vevent && $line eq "END:VEVENT" } {
                set in_vevent 0
                $item finish $parse_error
            } elseif {$in_vevent && [regexp {^X-APPLE-STRUCTURED-LOCATION(\;[^:]+|):(.*)$} $line . params value]} {
                #
                # Special handling for Apple ical implementations
                #
                $item add_ical_var X-APPLE-STRUCTURED-LOCATION $params $value
            } else {
                # Ignore unused ical lines
                :debug "ical parse ignores <$line>"
            }
        }
        return $item_list
    }

    :public object method header {
        {-calendar_name ""}
    } {
        #
        # Return the header of the ical file.
        #
        # GN TODO: don't hardcode TIMEZONE
        # "X-WR-TIMEZONE:Europe/Vienna"
        #
        if {$calendar_name eq ""} {
            set $calendar_name "Calendar from [ad_system_name]"
        }

        append lines \
            "BEGIN:VCALENDAR" \r\n \
            "X-WR-CALNAME:$calendar_name" \r\n \
            "PRODID:-//OpenACS//OpenACS 6.0 MIMEDIR//EN" \r\n \
            "CALSCALE:GREGORIAN" \r\n \
            "VERSION:2.0" \r\n \
            "METHOD:PUBLISH" \r\n
    }

    :public object method footer {} {
        #
        # Return the footer of the ical file.
        #

        return "END:VCALENDAR\r\n"
    }

    :public object method timezone {} {
        #
        # Return the timezone
        #

        # GN TODO: don't hardcode timezone

        set timezone [lang::system::timezone]
        set date_info [exec date "+%Z %z"]
        set TZNAME [linex $date_info 0]
        set default_offset [linex $date_info 1]

        # TZOFFSETFROM: local time offset from GMT when daylight saving time is in operation,
        # TZOFFSETTO is the local time offset from GMT when standard time is in operation.
        # set TZOFFSETFROM "+0100"
        # set TZOFFSETTO "+0200"

        set TZOFFSETFROM $default_offset
        set TZOFFSETTO $default_offset

        #
        # Compute offsets. It is not so easy to come up with a variant
        # that works under linux and macOS, since the results of zdump
        # is different (no gmtoff= under macOS) and date has well
        # different arguments.
        #
        try {
            set year [clock format [clock seconds] -format %Y ]
            set lines [exec zdump -v [lang::system::timezone] | fgrep $year]
            foreach l [split $lines \n] {
                #
                # Compute date difference in seconds
                #
                set diff [expr {([clock scan [lindex $l 11]]-[clock scan [lindex $l 4]]) / 60}]
                #
                # Format diff in seconds in a form like "+0200"
                #
                set sign [expr {$diff>0 ? "+" : "-"}]
                set H [format %02d [expr {$diff/60}]]
                set M [format %02d [expr {$diff%60}]]
                dict set time [lindex $l 14] $sign$H$M
            }

            if {[dict exists $time isdst=1]} {
                set TZOFFSETFROM [dict get $time isdst=1]
            }
            if {[dict exists $time isdst=0]} {
                set TZOFFSETTO [dict get $time isdst=0]
            }
        }

        return "BEGIN:VTIMEZONE
TZID:$timezone
TZURL:http://tzurl.org/zoneinfo-outlook/timezone
X-LIC-LOCATION:[lang::system::timezone]
BEGIN:DAYLIGHT
TZOFFSETFROM:$TZOFFSETFROM
TZOFFSETTO:$TZOFFSETTO
TZNAME:$TZNAME
DTSTART:19700329T020000
RRULE:FREQ=YEARLY;BYDAY=-1SU;BYMONTH=3
END:DAYLIGHT
BEGIN:STANDARD
TZOFFSETFROM:+0200
TZOFFSETTO:+0100
TZNAME:CET
DTSTART:19701025T030000
RRULE:FREQ=YEARLY;BYDAY=-1SU;BYMONTH=10
END:STANDARD
END:VTIMEZONE"
    }
}

::xo::library source_dependent
#
# Local variables:
#    mode: tcl
#    tcl-indent-level: 4
#    indent-tabs-mode: nil
#    eval: (setq tcl-type-alist (remove* "method" tcl-type-alist :test 'equal :key 'car))
# End:
