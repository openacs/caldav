::xo::library doc {
    CalDav implementation for OpenACS
    Object type for calendar items
    @author marmoser@wu.ac.at
    @creation-date Jan, 2017
}

::xo::library require -package xotcl-core ical-procs

namespace eval ::caldav {
    
    nx::Class create calitem -superclass ::xo::ical::VEVENT {
        #
        # "calitem" is a specialization of a ::xoical::VEVENTV
        # providinig extra functionality.
        #
        # GN TODO: check, what else of this could go into VEVENT.
        #
    
        #:property calendar
        #:property id
        #:property last-modified
        #:property {item_type ""}
        :property {ical_vars ""}
        
        #
        # The following properties are just for the interaction for
        # the XML queries based on [get_calitems]
        #
        :property etag

        :method debug {msg} {
            ns_log Debug(caldav) "[uplevel current proc]: $msg"
        }

        :public method add_ical_var {tag param value} {
            #
            # add tag/param/value to the property ical_vars which are
            # variables treated separately.
            #
            lappend :ical_vars $tag $param $value
        }
   
        :public method as_ical_event {} {
            #
            # Output a ::caldav::calitem into ical VEVENT notation.
            # It differs from standard as_ical in the following aspects:
            #
            # - it hard-codes the item_type to VEVENT
            #
            # - it handles the VALARM block handed in via ical_vars
            #   TODO: probably not the best way.
            #
            # - it imports the attributes of the ical_vars into
            #   instance attributes. TODO: this is dangerous
            #
            # - it flags entries as all day events

            set extra_block ""
            foreach {tag param value} ${:ical_vars} {
                #:debug "attribute $tag value <$value>"
                
                if {$tag eq "OPAQUE-VALARM"} {
                    #
                    # This is a full block, already correctly encoded
                    # 
                    append extra_block $value
                    
                } else {
                    #
                    # standard case
                    #
                    append extra_block \
                        [:tag -tag $tag -param $param -value $value ""]
                }
            }

            #
            # Check for all day events (start time and end time are
            # equal) and convert them
            #
            if {${:dtstart} eq ${:dtend}
                && [clock format [clock scan ${:dtstart}] -format %H%M] eq "0000"
            } {
                set :is_day_item true
                :debug "this is an all day event ${:dtstart}"
            } else {
                :debug "no day event ${:dtstart} ${:dtend} SCAN [clock format [clock scan ${:dtstart}] -format %H%M]"
            }
            return "BEGIN:VEVENT\r\n[:ical_body]${extra_block}END:VEVENT\r\n"
        }

        :public method as_ical_calendar {
            {-calendar_name ""}
        } {
            #
            # Output a ::caldav::calitem in the form of a full calendar.
            #
            # For now, without timezone
            # [::caldav::calendars timezone]

            #
            # TODO: why is not "header" and "footer" a method like
            # as_ical_event but from :caldav::calendars?
            #
            append result \
                [::caldav::calendars header -calendar_name $calendar_name] \
                [:as_ical_event] \
                [::caldav::calendars footer]
            return $result
        }
    }
}

::xo::library source_dependent

#
# Local variables:
#    mode: tcl
#    tcl-indent-level: 4
#    indent-tabs-mode: nil
# End:
