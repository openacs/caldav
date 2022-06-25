ad_library {
    CalDav implementation for OpenACS
    @author Gustaf Neumann
    @author marmoser@wu.ac.at
    @creation-date Jan, 2017
}

ns_logctl severity Debug(caldav) true
ns_logctl severity Debug(caldav-request) true


# TODOS
# - DELETE, PUT
#
# - move get_sync_calendar to interface-procs
#
# - There is a lot of guess work in cases, when no calendar UID is
#   set (using the activity_id in such cases). Not sure, if it would
#   be better to set UID during exports, such we have always valid
#   UIDs for calendar items.
#
# - etags on modification date are not good enough.
#
# - The implementation depends on NaviServer by using
#   e.g. "ns_cache_eval", "ns:memoize" and "ns_conn
#   partialtimes". with some effort, it would possible to provide an
#   AOLserver version as well.
#

::xo::library require caldav-interface-procs

namespace eval ::caldav {

    ad_proc -private get_sync_calendar {
        -user_id:required
    } {
        
        Get the calendar, to which we want to sync.  This method
        returns the first (and only in usual installations)
        calendar_id if it is found.
        
    } {
        set calendar_id [ns_cache_eval ns:memoize caldav-sync-cal-$user_id \
                             ::xo::dc list get_sync_calendar {
                                 select calendar_id from calendars
                                 where private_p = 't' and owner_id = :user_id
                             }]
        if {[llength $calendar_id] > 1} {
            #
            # In general, there is no rule which states that there is
            # for a user just a single private calendar. However, in
            # typical installations, this is the case for "normal"
            # users. In case there are multiple such calendars, return
            # the first a sync calendar and issue a warning. Probably,
            # such cases should be fixed manually in the database.
            #
            ns_log warning "CalDAV: more than one sync calendar for user $user_id ($calendar_id);" \
                "fall back to first one"
            set calendar_id [lindex $calendar_id 0]
        } elseif {[llength $calendar_id] == 0} {
            #
            # On non-DotLRN installations, the private calendar is
            # created when a user visits the first time the calendar
            # package, and no personal calendar exists. Bail out if
            # no such calendar exists.
            #
            error "can't get sync calendar for user $user_id"
        }
        return $calendar_id
    }

    ad_proc -private get_public_calendars {
    } {
        Get all public calendars, which might return empty.
    } {
        #
        # In case we have a dotlrn installation,
        #
        if {[info commands ::dotlrn_calendar::my_package_key] ne ""} {
            set main_calendar_package_id [parameter::get_from_package_key \
                                              -package_key [dotlrn_calendar::my_package_key] \
                                              -parameter main_calendar_package_id]

            set calendar_ids [ns_cache_eval ns:memoize caldav-cal-public \
                                  ::xo::dc list -prepare integer cal {
                                      select calendar_id from calendars
                                      where package_id = :main_calendar_package_id
                                      and private_p = 'f';
                                  }]
        } else {
            set calendar_ids {}
        }
        return $calendar_ids
    }


    xotcl::Class create CalDAV -superclass ::xo::ProtocolHandler -parameter {
        {url /caldav/}
    }

    CalDAV instproc debug {msg} {
        ns_log Debug(caldav) "[uplevel self proc]: $msg"
    }


    #
    # The two methods "getcontent" and "response" are responsible for
    # consistent logging. "getcontent" should be called on the begin
    # of every HTTP method implementation, "response" should be used
    # for delivering the result.
    #
    
    CalDAV instproc response {code mimetype response} {
        ns_log Debug(caldav-request) "Response ([ns_conn partialtimes]) for ${:method} $code ${:uri}\n$response"
        ns_return $code $mimetype $response
    }
    
    CalDAV instproc getcontent {{headers ""}} {
        lappend headers Content-Type ""  User-Agent ""
        foreach {tag default} $headers {
            lappend reportHeaders [list $tag [ns_set iget [ns_conn headers] $tag $default]]
        }
        set content [ns_getcontent -as_file false -binary false]
        set msg "[ns_conn method] ${:uri} ([join $reportHeaders {, }])"
        if {$content ne ""} {
            append msg ":\n$content"
        }
        ns_log Debug(caldav-request) $msg
        return $content
    }

    CalDAV instproc get_uid_from_href {href} {
        set uid ""
        regexp {/([^/]+)[.]ics$} $href . uid
        return $uid
    }

    
    ###
    ###  HTTP method GET
    ###
    CalDAV ad_instproc GET {} {

        GET calendar content in ical syntax. The method can either
        return an individual calendar item based on a cal_uid or a
        full calendar (may be an aggregated calendar) depending on the
        syntax of the URL.

        - individual cal_items (must end with .ics)
        
        /caldav/calendar/12872/12907.ics
        
        -  complete calendar
        
        /caldav/calendar
        /caldav/calendar?calendar_ids=12872
        /caldav/calendar/12872

        where the "12872" is a calendar_id and "12907"
        is the UID of a calendar item.
        
    } {
        # the following getcontent call is just for consistent logging
        :getcontent
        #
        #
        set tail [lindex ${:urlv} end]
        set mimetype "text/calendar"
        set code 404
        set resp ""
        :debug ":urlv [list ${:urlv}]"

        if {[file extension $tail] eq ".ics"} {
            #
            # Retrieve a single item identified by an UID
            #
            set uid [:get_uid_from_href ${:uri}]
            :debug "return single calendar item for uid $uid"

            # 
            # We need the calendar_ids for consistent naming of
            # calendars (aggregated, etc.).... 
            #
            if {[string is integer -strict [lindex ${:urlv} end-1]]} {
                set calendar_ids [lindex ${:urlv} end-1]
            } else {
                set calendar_ids ""
            }
            :calendar_ids $calendar_ids

            #
            # GN TODO: running two queries is not optimal but having
            # these separate eases type mismatch.
            #
            #    cal_uids(cal_uid, on_which_activity references acs_activities(activity_id), ical_vars)
            #    cal_items(cal_item_id references acs_events(event_id), on_which_calendar, ...)
            #    acs_events(event_id, ..., activity_id references acs_activities(activity_id), ...)
            #
            set cal_items [::xo::dc list_of_lists -prepare varchar get_calitem {
                select e.event_id as cal_item_id, u.ical_vars, a.creation_date, a.last_modified
                from   cal_uids u, acs_events e, acs_objects a
                where  u.cal_uid = :uid
                and    e.activity_id = u.on_which_activity
                and    a.object_id = e.event_id
                limit 1
            }]
            :debug "cal_items 1 (join on <$uid>): <$cal_items>"
            if {[llength $cal_items] == 0 && [string is integer -strict $uid]} {
                set cal_items [::xo::dc list_of_lists -prepare integer get_calitem {
                    select e.event_id as cal_item_id, '' as ical_vars, a.creation_date, a.last_modified
                    from   acs_events e, acs_objects a
                    where  e.activity_id = :uid
                    and    a.object_id = e.event_id
                    limit 1
                }]
            }
            
            #:debug "cal_items 2: <$cal_items>"
            if {[llength $cal_items] == 1} {
                lassign [lindex $cal_items 0] cal_item_id ical_vars creation_date last_modified
                calendar::item::get -cal_item_id $cal_item_id -array c
                :debug "calendar::item::get -cal_item_id $cal_item_id->\n[array get c]"
                set vevent [calitem new  \
                                -uid $uid \
                                -creation_date $creation_date \
                                -last_modified $last_modified \
                                -dtstart $c(start_date_ansi) \
                                -is_day_item [dt_no_time_p -start_time $c(start_date_ansi) -end_time $c(end_date_ansi)] \
                                -formatted_recurrences [calendars format_recurrence -recurrence_id $c(recurrence_id)] \
                                -dtend $c(end_date_ansi) \
                                -ical_vars $ical_vars \
                                -location $c(location) \
                                -summary $c(name) \
                                -description $c(description)]
                array unset c
                append resp [$vevent as_ical_calendar -calendar_name [:calendarName]]
                $vevent destroy
                
                # GN TODO: do we need always the database to get an etag ?
                ns_set put [ns_conn outputheaders] ETag [subst {"[:getETagByUID $uid]"}]
                set code 200
            } else {
                #
                # Nothing found or a weird result (multiple items). If
                # nothing is found, we have the error status code from
                # above. On too many results, raise an exception.
                #
                if {[llength $cal_items] > 1} {
                    error "cal_item query based on cal_uid $uid lead to multiple results [llength $cal_items]"
                }
            }
        } else {
            #
            # Retrieve a calendar.
            #
            # This query is run currently without a time constraints.
            #
            # GN TODO: not sure, returning always the full calendar is
            # a good idea, my personal calendar has more than 10 years
            # of data ... but maybe this is not often executed.
            #
            # The query parameter "calendar_ids" is used e.g. for
            # regression testing.
            #
            # GN TODO: 
            #
            if {[llength ${:urlv}] > 1} {
                set calendar_ids [lindex ${:urlv} 1]
            } else {
                set calendar_ids [ns_queryget calendar_ids ""]
            }
            :calendar_ids $calendar_ids
            
            if {$calendar_ids ne ""} {
                #
                # For specified calendars, return the calendar name of
                # the first calendar_id
                #
                set calendar_query "-calendar_ids $calendar_ids"
            } else {
                set calendar_query ""
            }
            set resp [calendars header -calendar_name [:calendarName]]
            foreach item [calendars get_calitems -user_id ${:user_id} {*}$calendar_query] {
                append resp [$item as_ical_event]
            }
            append resp [calendars footer]
            set code 200
        }
        :response $code $mimetype $resp

    }

    CalDAV instproc request_error {msg} {
        ad_log warning "CalDAV: $msg"
        :response 500 text/plain ""
    }

    ###
    # PROPFIND Method
    ###
    CalDAV ad_instproc PROPFIND {} {

        read and answer PROPFIND requests
        RFC 2518, section 8.1
        https://tools.ietf.org/html/rfc4918#page-35

    } {

        #https://github.com/seiyanuta/busybook/blob/master/Documentation/caldav-request-examples.md
        # Do a PROPFIND on the url the user supplied, requesting {DAV:}current-user-principal.
        # Using this url, you do a PROPFIND to find out more information about the user.
        # Here, you should typically request for the calendar-home-set property in the caldav namespace.
        # Then, using the calendar-home-set, do a PROPFIND (depth: 1) to find the calendars.


        # A client MUST submit a Depth header with a value of "0", "1",
        # or "infinity" with a PROPFIND request.  Servers MUST support
        # "0" and "1" depth requests on WebDAV-compliant resources and
        # SHOULD support "infinity" requests.  Servers SHOULD treat a
        # request without a Depth header as if a "Depth: infinity"
        # header was included.
        # 
        
        set depth [ns_set iget [ns_conn headers] Depth "infinity"]
        #ns_log notice "caldav: depth = $depth"

        set content [:getcontent {Depth "infinity"}]
        set doc [:parseRequest $content]
        ns_log notice "after parseRequest <$content>"
        if {$doc eq ""} {
            return [:request_error "could not parse request. Probably invalid XML"]
        }

        set root [$doc documentElement]
        #
        # Element name of root node must be "propfind"
        #
        if {[$root localName] ne "propfind"} {
            $doc delete
            return [:request_error "invalid request, no <propfind> element"]
        }

        set prop [$root firstChild]
        #
        # child of root must be prop or allprop
        #
        set elementName [$prop localName]
        if {$elementName ni {prop allprop}} {
            $doc delete
            return [:request_error "invalid request, no <prop> or <allprop> element, but '$elementName' provided"]
        }

        #
        # Special case allprop: return all properties
        #
        if {$elementName eq "allprop"} {
            dom parse {
                <A:prop xmlns:A="DAV:">
                <A:getcontenttype/>
                <A:getetag/>
                <A:sync-token/>
                <A:supported-report-set/>
                <c:getctag xmlns:c="http://calendarserver.org/ns/"/>
                <A:resourcetype/>
                <B:supported-calendar-component-set xmlns:B="urn:ietf:params:xml:ns:caldav"/>
                <B:calendar-home-set xmlns:B="urn:ietf:params:xml:ns:caldav"/>
                <A:displayname/>
                <A:current-user-principal/>
                </A:prop>
            } propTree
            set prop [$propTree firstChild]
        }

        set response ""

        # The incoming request URI should fall into the following categories
        #
        # - TOPLEVEL:      /caldav
        # - PRINCIPAL:     /caldav/principal
        # - FULL CALENDAR: /caldav/calendar
        #
        
        # GN TODO: remove the following test when we are sure it is ok.
        #ns_log notice "PROPFIND <${:uri}>, tail <[file tail ${:uri}]> urlv: <${:urlv}>"
        if {[file tail ${:uri}] ne [lindex ${:urlv} end]} {
            ns_log notice "========================== <[file tail ${:uri}]> ne <[lindex ${:urlv} end]>"
            error
        }

        switch [lindex ${:urlv} end] {
            "" {
                ns_log notice "=== CalDAV /caldav/ depth $depth"
                append response [:generateResponse -queryType top -user_id ${:user_id} $prop]
                if {$depth ne "0"} {
                    #
                    # Not sure, what should be sent in such cases. we
                    # could send "principal" or "calendar" replies.

                    ns_log notice "CalDAV /caldav/ query <${:uri}> with depth $depth"
                    #append response [:generateResponse -queryType principal $prop]
                }
            }
            "principal" {
                # A principal is a network resource that represents a distinct human or
                # computational actor that initiates access to network resources.
                # https://tools.ietf.org/html/rfc3744
                append response [:generateResponse -queryType principal $prop]
                #
                # here we ignore depth for the time being
                #
            }
            "calendar" {
                # TODO: we assume, we are working on the aggregated calendar
                :calendar_ids ""

                #set calendar_id [::caldav::get_sync_calendar -user_id ${:user_id}]
                #append response [:generateResponse -queryType calendar -calendar_id $calendar_id $prop]
                append response [:generateResponse -queryType calendar -calendar_id "" $prop]
                #ns_log notice "=== CALENDAR depth $depth FIND getetag=[$prop selectNodes -namespaces {d DAV:} //d:getetag] PROP [$prop asXML] "
                
                if {$depth ne "0"} {
                    #
                    # Search in depth 1 to deeper. Since all our
                    # calendar data is at depth 1, there is no need to
                    # differentiate.
                    #
                    # GN TODO: In general, PROPFIND on calendars is
                    # needed also without etags, not sure, where the
                    # restriction concerning "etag"comes from.
                    #
                    if {[$prop selectNodes -namespaces {d DAV:} //d:getetag] ne ""} {
                        #
                        # Query attributes containing also etags for
                        # this users' resources
                        #
                        foreach item [calendars get_calitems -user_id ${:user_id}] {
                            append response [:generateResponse -queryType resource -cal_item $item $prop]
                        }
                    } else {
                        ns_log notice "CalDAV: ===== calendar query on components with depth $depth on [$prop asXML]"
                    }
                }
            }
            default {
                $doc delete
                return [:request_error "invalid uri '${:uri}'"]
            }
        }
        # create response
        append resp \
            {<?xml version="1.0" encoding="utf-8" ?>} \n\
            {<d:multistatus } \
            {xmlns:d="DAV:" } \
            {xmlns:cs="http://calendarserver.org/ns/" } \
            {xmlns:c="urn:ietf:params:xml:ns:caldav" } \
            {xmlns:ical="http://apple.com/ns/ical/">} \
            $response \
            </d:multistatus>

        :response 207 text/xml $resp
        $doc delete
    }

    CalDAV instproc calendar_ids {value} {
        #
        # When calendar_ids is "", we work on on aggregated
        # (dotlrn-style calendar), when nonempty (single or multiple
        # calendars) we work on concrete calendars
        #
        set :calendar_ids $value
    }
    
    CalDAV instproc calendarName {} {
        :debug "calendarName has :calendar_ids <${:calendar_ids}>"
        if {${:calendar_ids} eq ""} {
            set calendar_name [:aggregatedCalendarName]
        } else {
            calendar::get -calendar_id [lindex ${:calendar_ids} 0] -array calinfo
            #:debug "calinfo of [lindex ${:calendar_ids} 0]: [array get calinfo]"
            set calendar_name $calinfo(calendar_name)
        }
        return $calendar_name
    }
    
    CalDAV instproc aggregatedCalendarName {} {
        set d [site_node::get_from_object_id -object_id [ad_conn subsite_id]]
        set instance_name [lang::util::localize [dict get $d instance_name]]
        set user_name [::xo::get_user_name ${:user_id}]
        return [_ caldav.aggregated_calendar_name \
                    [list instance_name $instance_name user_name $user_name]]
    }

    #################################################################################
    # FINDPROP property handlers
    #################################################################################
    CalDAV instproc unknown args {
        ns_log notice "CalDAV ${:method} unknown <$args>"
        return ""
    }

    #
    # Properties from xmlns "DAV:"
    #
    CalDAV instproc property=d-current-user-principal {res node} {
        #
        # Indicates a URL for the currently authenticated user's
        # principal resource on the server.
        #
        return <d:href>${:url}principal</d:href>
    }

    CalDAV instproc property=d-current-user-privilege-set {res node} {
        return {
            <d:privilege><d:all /></d:privilege>
            <d:privilege><d:read /></d:privilege>
            <d:privilege><d:write /></d:privilege>
            <d:privilege><d:write-properties /></d:privilege>
            <d:privilege><d:write-content /></d:privilege>
        }
    }

    CalDAV instproc property=d-displayname {res node} {
        #
        # The displayname property should be defined on all DAV
        # compliant resources. If present, it provides a name for the
        # resource that is suitable for presentation to a user.
        #
        # https://tools.ietf.org/html/rfc2518#section-13.2
        #
        switch ${:queryType} {
            "calendar"  { return [ns_quotehtml [:aggregatedCalendarName]] }
            "resource"  { return [ns_quotehtml [$res cget -summary]] }
            "principal" { return [ns_quotehtml [::xo::get_user_name ${:user_id}]]}
        }
        return ""
    }

    CalDAV instproc property=d-getcontenttype {res node} {
        #
        # Contains the Content-Type header returned by a GET without
        # accept headers.
        #
        return "text/calendar; charset=utf-8"
    }

    CalDAV instproc property=d-getetag {res node} {
        # An etag is the entity-id of the resource
        if {${:queryType} eq "resource"} {
            # cal_items have already etags precalculated
            return [$res cget -etag]
        }
        # Other resource types (calendars, principal, user) do not have etags
        return ""
    }

    CalDAV instproc property=d-owner {res node} {
        # This  property identifies a particular principal as being the "owner"
        # of the resource.
        #return "<d:href>${:url}</d:href>"
        return ""
    }

    CalDAV instproc property=d-principal-address {res node} {
        return <d:href>${:url}principal</d:href>
    }
    CalDAV instproc property=d-principal-collection-set {res node} {
        return [subst {<d:href>${:url}principal</d:href>}]
    }
    CalDAV instproc property=d-principal-URL {res node} {
        #
        # A principal may have many URLs, but there must be one
        # "principal URL" that clients can use to uniquely identify a
        # principal.  This protected property contains the URL that
        # MUST be used to identify this principal in an ACL request.
        #
        return <d:href>${:url}principal</d:href>
    }


    CalDAV instproc property=d-supported-report-set {res node} {
        return {
            <d:supported-report><d:report><c:calendar-multiget/></d:report></d:supported-report>
            <d:supported-report><d:report><c:calendar-query/></d:report></d:supported-report>
        }
    }

    CalDAV instproc property=d-sync-token {res node} {
        # set result [:calcSyncToken ${:user_id}]
        return ""
    }

    CalDAV instproc property=d-resourcetype {res node} {
        # Specifies the nature of the resource.
        # todo:resourcetype for single item
        switch ${:queryType} {
            "resource" {
                # single items do not have a resourcetype
                return ""
            }
            "calendar" {
                return <d:collection/><c:calendar/>
            }
            "principal" -
            "default" {
                return <d:collection/>
            }
        }
    }

    #
    # Properties from xmlns "http://calendarserver.org/ns/"
    #
    CalDAV instproc property=cs-getctag {res node} {
        # Specifies a "synchronization" token used to indicate when
        # the contents of a calendar or scheduling Inbox or Outbox
        # collection have changed.
        if {${:queryType} eq "calendar"} {
            return [:calcCtag ${:user_id}]
        } else {
            return ""
        }
    }

    #
    # Properties from xmlns "urn:ietf:params:xml:ns:caldav"
    # https://tools.ietf.org/html/rfc4791
    #

    CalDAV instproc property=c-calendar-data {res node} {
        #
        # RFC 4791: Given that XML parsers normalize the two character
        # sequence CRLF (US-ASCII decimal 13 and US-ASCII decimal 10)
        # to a single LF character (US-ASCII decimal 10), the CR
        # character (US-ASCII decimal 13) MAY be omitted in calendar
        # object resources specified in the CALDAV:calendar-data XML
        # element.  Therefore, we do not have to do special encoding
        # on the CR.
        #
        # https://tools.ietf.org/html/rfc4791#page-79
        #
        # That being said, the content lines of iCalendar objects specified in
        # the request body of a PUT or in the response body of a GET will still
        # be required to be delimited by a CRLF sequence (US-ASCII decimal 13,
        # followed by US-ASCII decimal 10).
        #
        # https://www.ietf.org/mail-archive/web/caldav/current/msg00551.html
        
        if {${:queryType} eq "resource"} {
            return [ns_quotehtml [$res as_ical_calendar]]
        } else {
            ns_log warning "CalDav can't return c-calendar-data for ${:queryType}"
        }
    }
    
    CalDAV instproc property=c-calendar-home-set {res node} {
        return <d:href>${:url}calendar</d:href>
    }
    CalDAV instproc property=c-supported-calendar-component-set {res node} {
        #
        # Specifies the calendar component types (e.g., VEVENT,VTODO,
        # VJOURNAL etc.)  that calendar object resources can contain
        # in the calendar collection.  c:comp name="VTODO" />
        #
        return "<c:comp name='VEVENT'/>"
    }

    CalDAV instproc property=c-calendar-description {res node} {
        return [ns_quotehtml [:aggregatedCalendarName]]
    }

    CalDAV instproc property=c-calendar-user-address-set {res node} {
        #
        # Identify the calendar addresses of the associated principal resource.
        # return <d:href>${:url}</d:href>
        return ""
    }

    CalDAV instproc property=c-calendar-timezone {res node} {
        #return [calendars timezone]
        return ""
    }


    #
    # Properties from xmlns "http://apple.com/ns/ical/"
    #
    CalDAV instproc property=ical-calendar-color {res node} {
        if {${:queryType} eq "calendar"} {
            # GN TODO:do not hard-code colors
            return "#2C5885"
        }
        return ""
    }
    CalDAV instproc property=ical-calendar-order {res node} {
        return 1
    }


    CalDAV ad_instproc returnXMLelement {resource node} {
        Return a pair of values indicating success and the value to
        be returned. While the property=* methods above return just
        values, this method wraps it into XML elements for returning
        it.
    } {
        #
        #
        set property [$node localName]
        set ns       [$node name]
        :debug "<$property> <$ns> resource $resource queryType <${:queryType}>"

        if {[info exists :xmlns($ns)]} {
            set outputNs [set :xmlns($ns)]
            set methodName property=$outputNs-$property
            #:debug "call method $methodName"
            try {
                set value [:$methodName $resource $node]
                :debug "<$property> <$ns> resource $resource queryType <${:queryType}> -> '$value'"
            } on error {errorMsg} {
                ns_log warning "CalDAV returnXMLelement: call method $methodName raised exception: $errorMsg"
                set value ""
            }
            if {$value eq ""} {
                set result [list 1 <${outputNs}:$property/>]
                #:debug "${:method} query $methodName returns empty (probably not found)"
            } else {
                set result [list 0 <${outputNs}:$property>$value</${outputNs}:$property>]
            }
        } else {
            ns_log warning "CalDAV: client requested a element with unknown namespace $ns known ([array names :xmlns])"
            set result [list 1 [subst {<[$node nodeName] xmlns:[$node prefix]="[$node namespaceURI]"/>}]]
        }
        return $result
    }

    CalDAV ad_instproc generateResponse {
        -queryType:required
        -user_id
        -calendar_id
        -cal_item
        node
    } {
        
        Return a &lt;response&gt; ... &lt;/response&gt; entry for the
        URL specified in the ${:url} and for the query attributes
        specified in the tdom node. The attributes user_id,
        calendar_id, or cal_item have to be set according to the
        queryType.

        @param queryType is an abstraction of the query url and
        can be "calendar", "resource", "top", or "principal"
        
    } {
        # @prop: requested properties as tdom nodes
        # generate xml for this resource
        
        #ns_log notice "generateResponse $queryType"
        set :queryType $queryType
        switch $queryType {
            "resource" {
                set href "${:url}calendar/[ns_urlencode [$cal_item cget -uid]].ics"
                set resource $cal_item
            }
            "calendar" {
                set href "${:url}calendar/"
                set resource $calendar_id
            }
            "top" {
                set href ${:url}
                set resource $user_id
            }
            "principal" {
                set href "${:url}principal"
                set resource "none"
            }
            "default" {
                error "invalid input"
            }
        }
        ns_log notice "generateResponse href=$href, resource=$resource child nodes [llength [$node childNodes]]"
        set not_found_props ""
        set found_props ""
        foreach childNode [$node childNodes] {
            lassign [:returnXMLelement $resource $childNode] returncode val
            if {$returncode} {
                append not_found_props $val \n
            } else {
                append found_props $val \n
            }
        }
        :debug "found_props $found_props, not_found_props $not_found_props"
        append result \
            <d:response> \n \
            <d:href>$href</d:href> \n
        
        if {$found_props ne ""} {
            #
            # return 200 for properties that were found
            #
            append result \
                <d:propstat> \n \
                <d:prop>$found_props</d:prop> \n \
                "<d:status>HTTP/1.1 200 OK</d:status>" \n \
                </d:propstat>
        }

        if {$not_found_props ne ""} {
            #
            # return 404 for properties that were not found
            #
            append result \n\
                <d:propstat> \n\
                <d:prop>$not_found_props</d:prop> \n\
                "<d:status>HTTP/1.1 404 Not Found</d:status>" \n\
                </d:propstat>
        }
        append result \n </d:response>
        return $result
    }

    ###
    ### HTTP method PROPPATCH
    ###
    CalDAV instproc PROPPATCH {} {
        
        set content [:getcontent]
        set doc [:parseRequest $content]
        
        # TODO: we assume, we are working on the aggregated calendar
        :calendar_ids ""

        if {$doc eq ""} {
            return [:request_error "request document invalid:\n$content"]
        }
        set reply ""
        set innerresponse ""
        
        set root [$doc documentElement]
        set props [$root selectNodes -namespaces ${:namespaces} /d:propertyupdate/d:set/d:prop]
        if {[llength $props] == 0} {
            ns_log Warning "PROPPATCH: invalid request: no property /d:propertyupdate/d:set/d:prop in\n$content"
            set statusCode 400
        } else {
            #
            # Return a multistatus with all properties forbidden.
            #
            foreach n [$props childNodes] {
                append innerresponse [subst {<d:propstat>
                    <d:prop><Z:[$n localName] xmlns:Z="[$n name]"/></d:prop>
                    <d:status>HTTP/1.1 403 Forbidden</d:status>
                    </d:propstat>}]
            }
            set resp [subst {<?xml version="1.0" encoding="utf-8" ?>
                <d:multistatus xmlns:d="DAV:">
                <d:response>
                <d:href>[string trimright [ns_conn url] "/"]</d:href>
                $innerresponse
                </d:response>
                </d:multistatus>}]
            set statusCode 207
        }
        :response $statusCode text/xml $resp
        $doc delete
    }

    ###
    ### REPORT
    ###
    CalDAV ad_instproc REPORT {} {

        CalDAV REPORT Method, see RFC 3253, section 3.6
        
    } {

        set content [:getcontent]
        set doc [:parseRequest $content]
        
        if {$doc eq ""} {
            return [:request_error "empty reports are not allowed"]
        }

        #
        # Currently, three reports are supported
        #
        # - calendar-multiget
        # - calendar-query
        # - sync-collection
        #
        $doc documentElement root
        set responses_xml ""

        # TODO: we assume, we are working on the aggregated calendar
        :calendar_ids ""

        if {[$root selectNodes -namespaces {c urn:ietf:params:xml:ns:caldav} "//c:calendar-multiget"] ne ""} {
            set ics_set [:calendar-multiget [$root firstChild]]
            
        } elseif {[$root selectNodes -namespaces {c urn:ietf:params:xml:ns:caldav} "//c:calendar-query"] ne ""} {
            set ics_set [:calendar-query $root]
            
        } elseif {[$root selectNodes -namespaces {d DAV:} "//d:sync-collection"] ne ""} {
            set ics_set [:sync-collection $root responses_xml]

        } else {
            #unknown type requested, aborting
            $doc delete
            return [:request_error "request type unknown [$root localName]"]
        }

        set props [$root selectNodes -namespaces {d DAV:} "d:prop"]
        foreach ics $ics_set {
            append responses_xml [:generateResponse -queryType resource -cal_item $ics $props]
        }

        append xml \
            {<?xml version="1.0" encoding="utf-8"?>} \n\
            {<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:cs="http://calendarserver.org/ns">} \n\
            $responses_xml \n\
            </d:multistatus>

        :response 207 text/xml $xml
        $doc delete
    }

    
    
    CalDAV ad_instproc calendar-multiget {prop} {
        
        calendar-multiget REPORT is used to retrieve specific calendar
        object resources from within a collection, if the Request- URI
        is a collection, or to retrieve a specific calendar object
        resource, if the Request-URI is a calendar object
        resource. This report is similar to the CALDAV:calendar-query
        REPORT (see Section 7.8), except that it takes a list of
        DAV:href elements, instead of a CALDAV:filter element, to
        determine which calendar object resources to return.
        
        https://icalendar.org/CalDAV-Access-RFC-4791/7-9-caldav-calendar-multiget-report.html
    } {
        #ns_log notice "==== calendar-multiget {$prop}"
        set cal_uids {}
        set act_ids {}

        foreach node [$prop selectNodes -namespaces {d DAV:} //d:href/text()] {
            set href [$node asText]
            set id [:get_uid_from_href $href]
            if {$id eq ""} {
                ns_log notice "CalDAV calendar-multiget: ignore href '$href'"
                continue
            }
            if {[string is integer -strict $id]
                && [::xo::dc get_value -prepare integer is_activity_id {
                    select 1 from acs_activities where activity_id = :id
                } 0] != 0
            } {
                lappend act_ids $id
            } else {
                lappend cal_uids [ns_urldecode $id]
            }
        }
        
        #
        # GN TODO: it is probably better to use a UNION instead of the
        # construct of "coalesce()" and "OR" below. We need to
        # test/benchmark with a full database with real-world data for
        # this.
        #
        set uid_clauses {}
        if {[llength $cal_uids] > 0} {
            lappend uid_clauses "u.cal_uid in ([ns_dbquotelist $cal_uids])"
        }
        if {[llength $act_ids] > 0} {
            lappend uid_clauses "e.activity_id in ([ns_dbquotelist $act_ids])"
        }
        ns_log notice uid_clauses=$uid_clauses
        
        set recurrences {}
        set ics_set {}

        #
        # TODO: why not [calendar get_calitems] ?
        #
        
        foreach row [::xo::dc list_of_lists get_calitems [subst {
            select
            md5(last_modified::text) as etag,
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
            acs_objects ao,
            acs_events e
            left outer join cal_uids u on u.on_which_activity = e.activity_id,
            acs_activities a,
            timespans s,
            time_intervals t,
            cal_items c
            where e.event_id = ao.object_id
            and a.activity_id = e.activity_id
            and c.cal_item_id = e.event_id
            and e.timespan_id = s.timespan_id
            and s.interval_id = t.interval_id
            and ( [join $uid_clauses " or "])
            order by start_date asc
        }]] {
            lassign $row etag cal_uid ical_vars calendar_id item_type \
                start_date end_date name description \
                cal_item_id recurrence_id creation_date last_modified
            
            if {$recurrence_id ne "" && $recurrence_id in $recurrences} {
                continue
            }
            # set item [::caldav::calitem new  \
                #               -id $cal_item_id \
                #               -uid $cal_uid \
                #               -ical_vars $ical_vars \
                #               -etag $etag \
                #               -calendar $calendar_id \
                #               -creation_date $creation_date \
                #               -last_modified $last_modified \
                #               -dtstart $start_date \
                #               -is_day_item [dt_no_time_p -start_time $start_date -end_time $end_date] \
                #               -formatted_recurrences [calendars format_recurrence -recurrence_id $recurrence_id] \
                #               -dtend $end_date \
                #               -summary $name \
                #               -description $description \
                #               -item_type $item_type]
            set item [::caldav::calitem new  \
                          -uid $cal_uid \
                          -ical_vars $ical_vars \
                          -etag $etag \
                          -creation_date $creation_date \
                          -last_modified $last_modified \
                          -dtstart $start_date \
                          -is_day_item [dt_no_time_p -start_time $start_date -end_time $end_date] \
                          -formatted_recurrences [calendars format_recurrence -recurrence_id $recurrence_id] \
                          -dtend $end_date \
                          -summary $name \
                          -description $description \
                         ]
            $item destroy_on_cleanup
            lappend ics_set $item
            lappend recurrences $recurrence_id
        }
        return $ics_set
    }

    CalDAV ad_instproc calendar-query {root} {
        Client wants the complete calendar
        Open: restrict to types
    } {
        set start ""
        set end ""
        #
        # determine filters
        #
        set time_range [$root selectNodes -namespaces {c urn:ietf:params:xml:ns:caldav} "//c:time-range"]
        #ns_log notice "time-range : $time_range"
        
        if {$time_range ne ""} {
            if {[$time_range hasAttribute start]} {
                set start [$time_range getAttribute start]
                set start [::xo::ical clock_to_oacstime [::xo::ical utc_to_clock $start]]
            }
            if {[$time_range hasAttribute end]} {
                set end [$time_range getAttribute end]
                set end [::xo::ical clock_to_oacstime [::xo::ical utc_to_clock $end]]
            }
        }
        ns_log notice "calendar-query: start time $start end time $end"
        
        #
        # components
        #
        set time_range [$root selectNodes -namespaces {c urn:ietf:params:xml:ns:caldav} "//c:comp-filter"]
        set fetch_vtodos 0
        set fetch_vevents 0
        foreach x $time_range {
            if {[$x getAttribute name] eq "VEVENT"} {set fetch_vevents 1}
            if {[$x getAttribute name] eq "VTODO"} {set fetch_vtodos 1}
        }
        set ics_set ""
        if {$fetch_vevents} {
            set ics_set [calendars get_calitems -user_id ${:user_id} -start_date $start -end_date $end]
        }
        return $ics_set
    }

    CalDAV ad_instproc sync-collection {root extraXMLvar} {
        sync
    } {
        upvar $extraXMLvar extraXML
        
        set props [$root selectNodes -namespaces {d DAV:} "//d:prop"]
        #set sync_level_node [$root selectNodes -namespaces {d DAV:} "//d:sync-level"]
        set sync_token_node [$root selectNodes -namespaces {d DAV:} "//d:sync-token"]
        if {$sync_token_node ne ""} {
            set sync_token [$sync_token_node text]
        } else {
            set sync_token ""
        }
        :debug "received sync-token <$sync_token>"

        #
        # Calculate a new sync token and return this as extraXML
        #
        set new_sync_token [:calcSyncToken ${:user_id}]
        set extraXML <d:sync-token>$new_sync_token</d:sync-token>
        
        if {$sync_token eq ""} {
            #
            # return all cal_items
            #
            set ics_set [calendars get_calitems -user_id ${:user_id}]
            
        } elseif {$sync_token ne $new_sync_token} {
            #
            # return cal_items since last sync_token
            #
            set ics_set [calendars get_calitems \
                             -user_id ${:user_id} \
                             -start_date [ns_fmttime $sync_token "%Y-%m-%d 00:00"] \
                             -end_date [ns_fmttime $new_sync_token "%Y-%m-%d 00:00"]]
        } else {
            #
            # return cal_items since the day of the sync_token
            #
            set ics_set [calendars get_calitems \
                             -user_id ${:user_id} \
                             -start_date [ns_fmttime $sync_token "%Y-%m-%d 00:00"]]
        }
        return $ics_set
    }

    ###
    ###  HTTP method OPTIONS
    ###
    CalDAV instproc OPTIONS {} {
        # A minimal definition for OPTIONS. Extend if necessary.
        set content [:getcontent]
        ns_set put [ns_conn outputheaders] DAV "1,2,access-control,calendar-access"
        ns_set put [ns_conn outputheaders] Allow "OPTIONS,GET,DELETE,PROPFIND,PUT,REPORT"
        ns_set put [ns_conn outputheaders] Cache-Control "no-cache"
        # return the response
        :response 200 "text/plain" {}
    }

    
    CalDAV ad_instproc calcCtag {user_id} {

        Generate a ctag (collection entity tag). The calendar ctag is
        like a resource etag; it changes when anything in the (joint)
        calendar has changed.

        This implementation returns a md5 value from the sum of the
        cal_item_ids, which changes when an item is deleted or a new
        community is joined, and the latest modification date of the
        cal_item_ids.

    } {
        lappend clauses \
            {*}[calendars communityCalendarClause $user_id] \
            {*}[calendars alwaysQueriedClause $user_id]
        #ns_log notice "calendar_clause [join $clauses { union }]"
        return [::xo::dc get_value lastmod [subst {
            select md5(sum(cal_item_id)::text || max(last_modified)::text)
            from   cal_items ci
            join   acs_objects ao on (ao.object_id = ci.cal_item_id)
            where  ci.on_which_calendar in
            ([join $clauses " union "])
        }]]
    }


    CalDAV instproc calcSyncToken {user_id} {
        # sync-token is the last modified value for the calendar items
        # needs to be in a format that can be converted back to the original value
        lappend clauses \
            {*}[calendars communityCalendarClause $user_id] \
            {*}[calendars alwaysQueriedClause $user_id]

        return [::xo::dc get_value lastmod [subst {
            select date_part('epoch', max(last_modified))::numeric::integer from cal_items ci
            join acs_objects ao on (ao.object_id = ci.cal_item_id) where ci.on_which_calendar in
            ([join $clauses " union "])
        }]]
    }

    CalDAV instproc parseRequest {content} {
        try {
            #dom setResultEncoding utf-8
            set document [dom parse $content]
        } on error {errorMsg} {
            ns_log error "CalDAV: parsing of request lead to error: $errorMsg!\n$content"
            throw {DOM PARSE {dom parse triggered exception}} $errorMsg
        }
        return $document
    }

    ###
    ###  HTTP method DELETE
    ###

    CalDAV instproc DELETE {} {
        set content [:getcontent {If-Match ""}]
        set url [ns_conn url]
        set user_id ${:user_id}
        # GN TODO: use ${:uri}, use in code ${:user_id}
        ns_log notice "DELETE TODO <${:uri}> vs. <$url>"

        set uid [:get_uid_from_href $url]
        set headers [ns_conn headers]
        #read if-match header which denotes the etag
        set if_match [ns_set get $headers If-Match]
        set calendar_id [::xo::dc get_value private_cal "
    select calendar_id from calendars where private_p = 't' and owner_id = :user_id limit 1" 0]

        :log "UID: $uid, calendar_id: $calendar_id: if_match $if_match"

        set item_exists [calendars get_cal_item_from_uid -calendar_ids $calendar_id $uid]
        ns_log notice "item_exists $item_exists"
        if {[llength $item_exists] > 0} {
            #todo: verify if deletion has finished
            foreach cal_item $item_exists {
                catch {::calendar::item::delete -cal_item_id $cal_item} err
                ns_log notice "calendar item delete: cal_item: $cal_item - err: $err"
            }
            set code 204
            set mimetype "text/plain"
            set response ""
        } else {
            set response [subst {
                <?xml version="1.0" encoding="utf-8" ?>
                <d:multistatus xmlns:d="DAV:">
                <d:response>
                <d:href>$url</d:href>
                <d:status>HTTP/1.1 404 Not Found</d:status>
                </d:response>
                </d:multistatus>}]
            set code 207
            set mimetype "text/xml"
        }
        :response $code $mimetype $response
    }

    ###
    ###  HTTP method PUT
    ###

    CalDAV ad_instproc PUT {} {

        UPDATE (SAVE?) a single calendar item denoted by a uid of a
        calendar item.
        
    } {
        set content [:getcontent {If-Match ""}]
        set ifmatch [ns_set iget [ns_conn headers] If-Match "*"]

        #
        # The request URI has to end with UID.ics, but we get the
        # actual UID from the ical UID field of the parsed content.
        #
        if {![string match *.ics ${:uri}]} {
            return [:request_error "Trying to PUT on a calendar that does not end with *.ics: ${:uri}"]
        }
        
        try {
            set sync_calendar_id [::caldav::get_sync_calendar -user_id ${:user_id}]
        } on error {errorMsg} {
            return [:request_error "no private calendar found for ${:user_id}"]
        }

        set items [calendars parse $content]
        :debug "caldav parser returned items <$items>"

        foreach item $items {
            set uid [$item cget -uid]
            :debug [$item serialize]

            if {$ifmatch eq "*"} {
                #
                # Create new entry
                #
                :debug "add a new entry"
                set calendar_id $sync_calendar_id
                #
                # We should probably check, whether we can really
                # write on the calendar in the general case, but here,
                # we know, the sync calendar is always writable for the
                # current user.
                #
                # - GN TODO: not sure, when mutating the UID is necessary, and 
                #   whether adding a suffix with the user_id is the best solution.
                #   So we deactivate this code for now....
                #
                if {0} {
                    set user_id ${:user_id}
                    if {[::xo::dc get_value -prepare varchar,integer uid_exists {
                        select 1 from cal_uids u
                        join acs_objects o on (o.object_id = u.on_which_activity)
                        where cal_uid = :uid
                        and o.creation_user != :user_id
                    } 0]} {
                        ad_log warning "uid already exists for another user, suffixing ${uid}-${:user_id}"
                        $item set uid "${uid}-${:user_id}"
                    }
                }
            } else {
                #
                # Update an existing entry
                #
                :debug "update existing entry..."

                lappend clauses \
                    {*}[calendars communityCalendarClause ${:user_id}] \
                    {*}[calendars alwaysQueriedClause ${:user_id}]

                set all_calendar_ids [::xo::dc list read_only_cals [subst {
                    select calendar_id from ([join $clauses " union "]) as cals
                }]]

                set cal_infos [calendars get_calendar_and_cal_item_from_uid -calendar_ids $all_calendar_ids $uid]
                :debug "cal_infos for calendar_ids $all_calendar_ids uid $uid -> <$cal_infos>"

                if {$cal_infos ne ""} {
                    set cal_info [lindex $cal_infos 0]
                    lassign $cal_info calendar_id cal_item_id

                    :debug "write check needed? [expr {$calendar_id ne $sync_calendar_id}]"
                    
                    if {$calendar_id != $sync_calendar_id} {
                        set can_write_p [permission::permission_p -object_id $cal_item_id -privilege write]
                        :debug "write check: $can_write_p (calendar_id $calendar_id, sync_calendar_id $sync_calendar_id)"

                        if {!$can_write_p} {
                            ns_log warning "CalDAV: user tried to perform a PUT on a read only item item: $cal_item_id user ${:user_id}"
                            if {[string match "*CalDavSynchronizer*" ${:user_agent}]} {
                                #
                                # Outlook sychronizer will continue
                                # hammering if 403 is returned,
                                # therefore try a different status
                                # code.
                                #
                                # GN TODO: please check, what happens
                                # with status code 412 on Outlook,
                                # since 202 probably silently swallows
                                # the update, which never happens.
                                #
                                :debug "CalDav: outlook client encountered"
                                set statusCode 202
                            } else {
                                set statusCode 412
                            }
                            return [:response $statusCode text/plain {}]
                        }
                    }
                }
            }
            #
            # save the item
            #
            :debug "updating item [$item cget -uid] in calendar $sync_calendar_id"
            :item_update -calendar_id $sync_calendar_id -item $item
            
            #ns_log notice "CalDAV PUT: [$item serialize]"
            ns_set put [ns_conn outputheaders] ETag [subst {"[:getETagByUID [$item cget -uid]]"}]
            $item destroy
            :response 201 text/plain {}
            return
        }
        # TODO what happens here
    }

    CalDAV instproc item_update {
        {-calendar_id:integer}
        {-item:object}
    } {
        #
        # This method inserts or updates a caldav calendar
        # item. If there is already a cal_item for this uid, we
        # perform an update on the original calendar. If it does
        # not exists, we perform an insert in the specified
        # calendar (calendar_id).
        #
        # The caller is responsible to acertain that the calendar
        # is writable.
        #
        # @param calendar_id place where new calendar items are added to

        set summary [$item get summary]
        if {$summary eq ""} {
            :log "CalDAV: summary is empty, skip this item"
            return
        }
        set uid [$item cget -uid]

        # TODO: is the following comment useful?
        #
        # We need to check if the item exists in one of the other
        # calendars of the user.  If an item with this uid already
        # exists, return an error

        set cal_item_id [lindex [::caldav::calendars get_cal_item_from_uid -calendar_ids $calendar_id $uid] 0]

        set dtend   [$item get dtend]
        set dtstart [$item get dtstart]
        #
        # TODO: as_ical_event checks as well for is_day_item
        #
        if { [clock scan $dtend] - [clock scan $dtstart] == 86400
             && [clock format [clock scan $dtstart] -format %H%M] eq "0000"
             && [clock format [clock scan $dtend]   -format %H%M] eq "0000"
         } {
            #ns_log notice "this is an all day event! ${:dtstart} ${:dtend}"
            #we set end to start as this is the way openacs calendar marks all day events
            set :dtend $dtstart
            $item is_day_item set true
        }
        set description [$item get description]
        set location    [$item get location]
        set ical_vars   [$item get ical_vars]

        if {$cal_item_id eq ""} {
            #
            # Create a new item
            #
            :debug "create a new item"
            set cal_item_id [calendar::item::new \
                                 -start_date ${dtstart} \
                                 -end_date ${dtend} \
                                 -name ${summary} \
                                 -description $description \
                                 -calendar_id $calendar_id \
                                 -location $location \
                                 -cal_uid $uid \
                                 -ical_vars $ical_vars]
            
            $item add_recurrence -cal_item_id $cal_item_id
            
        } else {
            #
            # Update an existing item
            #
            :debug "update/edit cal_item_id $cal_item_id uid <$uid> ical_vars $ical_vars"
            
            calendar::item::edit \
                -cal_item_id $cal_item_id \
                -start_date ${dtstart} \
                -end_date ${dtend} \
                -name ${summary} \
                -description ${description} \
                -location ${location} \
                -calendar_id $calendar_id \
                -edit_all_p 1 \
                -ical_vars ${ical_vars} \
                -cal_uid ${uid}

            set recurrence_id [::xo::dc get_value -prepare integer get_recurrence {
                select recurrence_id from acs_events where event_id = :cal_item_id
            }]
            
            $item edit_recurrence \
                -cal_item_id $cal_item_id \
                -recurrence_id $recurrence_id
        }
    }


    #CalDAV instproc handle_request {} {
    #    set ms [clock milliseconds]
    #    next
    #    if {[parameter::get_global_value -package_key caldav -parameter "debugmode"] > 0} {
    #        ns_log notice "CalDav ${:method} request took [expr {[clock milliseconds] - $ms}]ms"
    #    }
    #}

    CalDAV instproc getETagByUID {uid} {
        #note: last_modified is updated for the acs_event/cal_item object_id, not the acs_activity
        #when has this collection item been modified the last time?
        # TODO: do we need "max()"? 2 times
        set c_uid [::xo::dc get_value -prepare varchar select_last_modified_uid {
            select max(md5(last_modified::text))
            from cal_uids c, acs_objects ao, acs_events e
            where c.on_which_activity = e.activity_id
            and e.event_id = ao.object_id
            and cal_uid = :uid
        }]
        # fallback for events without an uid
        if {$c_uid eq "" && [string is integer -strict $uid]} {
            set c_uid [::xo::dc get_value -prepare integer select_last_modified_uid {
                select max(md5(last_modified::text))
                from  acs_objects ao, acs_events e
                where e.event_id = ao.object_id
                and e.activity_id = :uid
            }]
        }
        return $c_uid
    }
}

namespace eval ::caldav {
    CalDAV create ::caldav::dav

    ::caldav::dav eval {
        array set :xmlns {
            "DAV:"                          d
            "http://calendarserver.org/ns/" cs
            "urn:ietf:params:xml:ns:caldav" c
            "http://apple.com/ns/ical/"     ical
        }
        set :namespaces {}
        foreach {ns prefix} [array get :xmlns] {
            lappend :namespaces $prefix $ns
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
