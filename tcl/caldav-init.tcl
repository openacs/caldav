ad_library {
    CalDav implementation for OpenACS - Init
    
    @author Gustaf Neumann
    @creation-date May, 2019    
}

#
# You might consider turning on logging by activating it in xotcl-core,
# "ProtocolHandler instproc log"
#
ns_log notice "=============================== ::caldav::dav register"
::caldav::dav register
ns_log notice "=============================== ::caldav::dav register DONE"


#
# Local variables:
#    mode: tcl
#    tcl-indent-level: 4
#    indent-tabs-mode: nil
# End:

