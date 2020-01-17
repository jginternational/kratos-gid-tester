lappend auto_path /gid/gid-x64/scripts

package provide app-tester 1.5

package require msgcat

if { [info procs ::_] == ""  && [info commands ::_] == "" } {
    interp alias {} _ {} ::msgcat::mc
}


proc ::bgerror { errstring } {
    tester::message $::errorInfo
}

proc ::W { text } {
    tester::message $text
}

proc ::WV { varname_list { msg ""} } {
    set text [ list]
    foreach varname $varname_list {
        upvar $varname contents
        set err [ catch {
            set len [ llength $contents]
            if { $len == 1} {
                set text_var "$varname = $contents"
            } else {
                set text_var "$varname ( [ llength $contents]) = $contents"
            }
            if { "$contents" == ""} {
                set text_var "$varname is empty"
            }
        } err_txt]
        if { $err} {
            set text_var "can't read \"$varname\": no such variable"
        }
        lappend text $text_var
    }
    if { "$msg" == ""} {
        ::W [ join $text \n]
    } else {
        ::W "$msg [ join $text \n]"
    }
}

proc ::DefineMouseButtons { } {
    if { $::tcl_platform(os) == "Darwin" } {
        # http://wiki.tcl.tk/12987 FAQ 7.7:
        # For historical reasons, MacMice buttons 2 and 3 refer to the right and middle buttons
        # respectively, which is indeed the opposite way round from Windows and *nix systems.
        set ::tester_central_button 3
        set ::tester_middle_button 3
        set ::tester_right_button 2
    } else {
        # use both aliases for middle mouse button
        set ::tester_central_button 2
        set ::tester_middle_button 2
        set ::tester_right_button 3
    }
}

::DefineMouseButtons

########################################################################
################################## tester ##############################
########################################################################

namespace eval tester {
    variable private_options ;#array to store some inner program variables
    array set private_options {
        program_name "Tester"
        program_version "1.5"
        program_web "www.cimne.com"
        gui 0
        program_path ""
        project_path ""
        menu_recent_projects ""
        log ""
        xml_document ""       
        must_save_document 0 
        must_save_digest_results 0
    }            
    variable ini ;#array to be saved in .ini of the user
    array set ini {
        recent_projects ""
        reloadlastproject 1
    }
    variable preferences ;#array to store the public_options showed in the window, and saved to config/preferences.xml (really must be saved in a user place)!!
    variable preferences_defaults ;#internal default values of preferences
    array set preferences_defaults {
        analize_cause_fail 0
        basecasesdir ""
        branch_provide ""
        email_on_fail 0
        enable_filters 1
        exe ""
        filter_date 0
        filter_time 0
        filter_time_value 2
        filter_memory 0
        filter_memory_value 200
        filter_tags 0
        filter_tags_value ""
        filter_fail 0
        filter_fail_value fail
        filter_fail_accepted 1
        filter_fail_accepted_value 1
        filter_fail_random 0
        filter_fail_random_value 1
        filter_branch_provide 1
        filter_platform_provide 1
        gidini ""
        gidshowtclerror 1
        graphs_date_min 0
        graphs_date_min_value ""
        graphs_date_max 0
        graphs_date_max_value ""
        htmlimagesbyrow 3
        initialdir ""
        mailsend_password ""        
        mailsend_port 465    
        mailsend_server smtp.gmail.com
        mailsend_username ""
        maxmemory 0
        maxprocess 8
        offscreen_exe ""
        opposite_filters 0
        owner ""
        owners ""
        path ""
        platform_provide ""
        run_at 0
        run_at_value 00:15
        show_current_case 0
        show_as_tree 0
        test_gid 1
        timeout 3600
    }   
    
    variable data ;#array to store cases data, I want to replace this variable by a TDOM document read/saved form/to a xml file...
    variable digest_results ;#array to store digest of history of results, and last tested result 
    #for each case_id a list of 7 items: fail time memory date min_time min_memory ok_date    
    
    variable tested_cases ;#array with three items: ok, fail, untested, to count and linked to show labels
    array set tested_cases { 
        ok 0 
        fail 0 
        untested 0 
    }
    
    variable array_result_code
    array set array_result_code { 
        "running" -2
        "untested" -1
        "ok" 0
        "fail" 1
        "crash" 2
        "timeout" 3
        "maxmemory" 4
        "userstop" 5       
    }
    
    variable array_result_string
    array set array_result_string { 
        -2 "running"
        -1 "untested"
        0 "ok"
        1 "fail"
        2 "crash"
        3 "timeout"
        4 "maxmemory"
        5 "userstop"
    }
    
    variable nprocess 0 ;#integer
    variable case_ids_running {}
    variable cancel_process 0 ;#boolean    
    variable pause_process 0 ;#boolean
    variable progress 0 ;#advance bar variable
    variable maxprogress 0 ;#advance bar variable
    
    variable case_allowed_keys ;#sorted list of allowed xml case keys
    set case_allowed_keys [lsort -dictionary [list args batch check codetosource exe filetosource gidini \
                help jira_id maxmemory maxprocess name offscreen_exe outfile outputfiles owner platform_require readingproc tags timeout]]
    #maxprocess: don't add it to case_allowed_keys because it is difficult to control not to run more processes that a limit while running this    
    variable case_allowed_attributes ;#sorted list of allowed xml case attributes
    variable case_default_attributes ;#               default values
    set case_allowed_attributes { branch_require fail_accepted fail_random id } 
    set case_default_attributes { "" 0 0 "" }
    variable batch_allowed_attributes ;#sorted list of allowed xml batch attributes
    variable batch_default_attributes ;#               default values
    set batch_allowed_attributes { offscreen with_graphics with_window }
    set batch_default_attributes { 0 0 0 }
    #id=$md5 (assigned automatically)
    #branch_require=developer|official (default={}) to allow filter the case
    #fail_accepted=1 (default=0) to allow filter the case
    #fail_random=1 (default=0) to know that has this behavior
    variable allowed_plaforms
    set allowed_plaforms [list {Windows 32} {Windows 64} {Linux 32} {Linux 64} {MacOSX 32} {MacOSX 64}]
    variable allowed_branchs
    set allowed_branchs [list developer official]
    
    variable _images ;#array to store images
    
    #GUI only variables?
    variable mainwindow ;#widget
    variable button ;#widget
    variable tree ;#widget
    variable tree_item_case ;#array to get the tree item related to a case_id
    variable tree_sorted_by_column 0
    variable tree_sorted_direction -increasing
    variable message ;#message to be shown in the command line
    variable up_arrow 0
}

proc tester::get_default_attribute_value { attribute } {
    variable case_allowed_attributes
    variable case_default_attributes
    set index [lsearch -dictionary -exact -sorted $case_allowed_attributes $attribute]
    if { $index != -1 } {
        set value [lindex $case_default_attributes $index]
    } else {
        variable batch_allowed_attributes
        variable batch_default_attributes
        set index [lsearch -dictionary -exact -sorted $batch_allowed_attributes $attribute]
        if { $index != -1 } {
            set value [lindex $batch_default_attributes $index]
        } else {
            tester::message "tester::get_default_attribute_value, unexpected attribute $attribute"
            set value ""
        }
    }
    return $value
}

proc tester::set_preference { key value } {
    variable preferences
    set preferences($key) $value
}


proc tester::get_preferences_key_value { key } {
    variable preferences
    if { $key == "maxmemory" || $key == "maxprocess" || $key == "exe" || $key == "offscreen_exe"  || $key == "owner" || $key == "timeout" } {
        set value $preferences($key)
    } elseif { $key == "gidini" } {
        set value [tester::get_full_gidini_filename $preferences(exe) $preferences(gidini)]                
    } else {
        set value ""
    }    
    return $value   
}

#for future multilingual application
proc tester::get_current_language { } {
    return en
}

#counter tested cases
#set num_untested -1 to recalculate it with the amount of enabled cases
proc tester::reset_counter_tested_cases { num_untested  } {
    variable tested_cases ;#array with three items: ok, fail, untested, to count and linked to show labels
    set tested_cases(ok) 0 
    set tested_cases(fail) 0 
    if { $num_untested == -1 } {
        set num_untested [llength [tester::filter_case_ids [tester::case_ids]]]   
        set tested_cases(untested) $num_untested
    }
}

proc tester::get_current_formatted_date { } {
    return [tester::format_date [clock seconds]]
}


#log files
proc tester::open_log { } {
    variable private_options   
    tester::close_log
    set dir [file join $private_options(project_path) logfiles]
    if { ![file exists $dir] || ![file isdirectory $dir] } {
        file mkdir $dir
    }    
    set private_options(log) [open [file join $dir tester.log]  a]
}

proc tester::check_log_size { } {
    variable private_options
    #check every midnight the size 
    set maxsize 1048576 ;#1MB
    set filename [file join $private_options(project_path) logfiles tester.log]
    if { [file exists $filename] && [file size $filename] > $maxsize } {
        tester::close_log
        set new_name [file join $private_options(project_path) logfiles tester_[clock format [clock seconds] -format {%H%M%S%m%d%Y}].log]
        catch {file rename -force $filename $new_name}
        tester::open_log
    }
    # set after event to check every midnight 
    set now [clock seconds]
    set next [expr {([clock scan 23:59:59 -base $now]-$now+1000)*1000}]
    after cancel tester::check_log_size
    after $next tester::check_log_size
}

proc tester::close_log { } {
    variable private_options
    if { $private_options(log) != "" } {
        close $private_options(log)   
    }
    set private_options(log) ""
}

proc tester::puts_log { message } {
    variable private_options    
    puts $private_options(log) "[tester::get_current_formatted_date] $message"
    flush $private_options(log)
}

proc tester::puts_log_error { message } {
    tester::puts_log [list error $message]
}

proc tester::puts_log_case { case_id } {
    set result [tester::evaluate_checks $case_id]
    set result_code [tester::get_result_code $result]
    puts [list $case_id $result_code [tester::get_variable $case_id results]]
    tester::puts_log [list $case_id $result_code [tester::get_variable $case_id results]]
}

proc tester::get_result_code { result } {
    variable array_result_code
    return $array_result_code($result)
}

proc tester::get_result_string { result_code } {
    variable array_result_string
    return $array_result_string($result_code)
}

#list of owners of the cases (e.g. to send e-mail to its responsible)
proc tester::owners_append_unique { owner } {
    variable preferences
    if { $owner != "" && [lsearch -sorted -dictionary $preferences(owners) $owner] == -1 } {
        lappend preferences(owners) $owner
        set preferences(owners) [lsort -dictionary $preferences(owners)]
    }
}

proc tester::get_owners { } {
    variable preferences
    return $preferences(owners)
}

#list of tags to filter cases to be shown and run
proc tester::set_filter_tag { tag value } {
    variable preferences
    set pos [lsearch -sorted -index 0 -dictionary $preferences(filter_tags_value) $tag]
    if { $pos == -1 } {
        lappend preferences(filter_tags_value) [list $tag $value]
        set preferences(filter_tags_value) [lsort -index 0 -dictionary $preferences(filter_tags_value)]
    } else {
        lset preferences(filter_tags_value) $pos 1 $value        
    }    
}

proc tester::exists_filter_tag { tag } {
    variable preferences
    set pos [lsearch -sorted -index 0 -dictionary $preferences(filter_tags_value) $tag]
    if { $pos == -1 } {
        set exists 0
    } else {
        set exists 1
    }
    return $exists
}

proc tester::get_filter_tag { tag } {
    variable preferences
    set pos [lsearch -sorted -index 0 -dictionary $preferences(filter_tags_value) $tag]
    if { $pos != -1 } {
        set value [lindex [lindex $preferences(filter_tags_value) $pos] 1]
    } else {
        set value 0
    }
    return $value
}

proc tester::get_filter_tags { } {
    variable preferences
    set tags [list ]
    foreach item $preferences(filter_tags_value) {
        lappend tags [lindex $item 0]
    }
    #set tags [lsort -dictionary $tags] ;#preferences(filter_tags_value) is already sorted by its index 0
    return $tags
}


proc tester::delete_declared_outputfiles { case_id } {
    set key outputfiles
    if { [tester::exists_variable $case_id $key] } {
        foreach filename [tester::get_variable $case_id $key] {
            set filename [subst -nobackslashes -novariables $filename] ;#to allow replacing [] procedures 
            if { [file exists $filename] } {
                file delete -force $filename
                if { [file exists $filename] } {
                    tester::message "tester::delete_declared_outputfiles. Cannot delet outputfile '$filename'"
                }
            }
        }
    }
    return 0
}

#some events raised to do some tasks when something happen

proc tester::private_event_before_run_case { case_id } {
    variable tree
    variable tree_item_case
    variable preferences
    
    #tester::digest_results_set_last_test_values $case_id untested "" "" ""
    #tester::array_unset $case_id results
    #tester::remove_results_from_tree $case_id
    tester::delete_declared_outputfiles $case_id 
    if { $preferences(show_current_case) && [info exists tree] && [winfo exists $tree] } {
        set item $tree_item_case($case_id)
        set items_to_open [$tree item id "$item ancestors state !open"]
        foreach item_to_open $items_to_open {
            $tree item expand $item_to_open
        }
        $tree see $item -center y
        $tree activate $item 
    }
    if { [info procs ::tester::event_before_run_case] != "" } {
        tester::event_before_run_case $case_id
    }
}

proc tester::private_event_after_run_case { case_id } {    
    if { [info procs ::tester::event_after_run_case] != "" } {
        tester::event_after_run_case $case_id
    }
}

proc tester::private_event_before_run_cases { case_ids } {
    variable _fail_before_run_cases
    array unset _fail_before_run_cases
    foreach case_id $case_ids {
        set _fail_before_run_cases($case_id) [tester::digest_results_get_fail $case_id]
        tester::digest_results_set_last_test_values $case_id "running" "" "" ""
        tester::array_unset $case_id results
        tester::remove_results_from_tree $case_id
    }
    foreach case_id $case_ids {
        tester::update_case_and_parents_tree_state $case_id "running"
    }        
    tester::set_message [_ "Running %s cases" [llength $case_ids]]
    tester::gui_enable_pause
    if { [info procs ::tester::event_before_run_cases] != "" } {
        tester::event_before_run_cases $case_ids
    }
}

proc tester::private_event_after_run_cases { case_ids } {
    variable preferences
    variable private_options
    variable _fail_before_run_cases
    variable _body_text_last_email ;#no not re-send again and again the same message (e.g. running daily with the same fail)
    tester::gui_disable_play
    #to send e-mail error messages only running all, not manually running a selection
    set run_all_cases [expr [llength $case_ids]==[llength [tester::filter_case_ids [tester::case_ids]]]]
    if { $preferences(email_on_fail) && $run_all_cases } {
        set case_ids_to_notify [list]

        foreach case_id $case_ids {
            set fail_before_evaluate_checks $_fail_before_run_cases($case_id)
            if { $fail_before_evaluate_checks == 0} {
                #only notify if case does not fail before
                continue
            }            
            if { [tester::exists_variable $case_id fail_random] && [tester::get_variable $case_id fail_random]} {
                #and also ignore random cases
                continue
            } 
            set fail_after_evaluate_checks [tester::digest_results_get_fail $case_id]
            if { ($fail_after_evaluate_checks == 1 || $fail_after_evaluate_checks == "crash" || $fail_after_evaluate_checks == "timeout" \
                || $fail_after_evaluate_checks == "maxmemory" || $fail_after_evaluate_checks == "userstop" ) } {
                lappend case_ids_to_notify $case_id
            }
        }
        set num_cases_to_notify [llength $case_ids_to_notify] 
        if { $num_cases_to_notify } {
            #send only a message by resposible user
            foreach case_id $case_ids_to_notify {
                set owner [tester::get_variable $case_id owner]
                if { $owner != "" } {
                    lappend case_ids_to_notify_by_owner($owner) $case_id
                } else {
                    
                }
            }

            set max_cases_to_analize 5
            set i_cases_to_analize 0
            set num_cases_tested [llength $case_ids]
            foreach owner [lsort -dictionary [array names case_ids_to_notify_by_owner]] {
                set num_cases_of_owner [llength $case_ids_to_notify_by_owner($owner)]
                set body($owner) [_ "failed %s cases assigned to your owner of %d tested" $num_cases_of_owner $num_cases_tested]\n
                foreach case_id $case_ids_to_notify_by_owner($owner) {
                    if { $preferences(analize_cause_fail) } {
                        if { $i_cases_to_analize < $max_cases_to_analize } {
                            #very expensive and must not run in parallel (the source code is unique and will change during the analysis)
                            set txt "case $case_id [tester::analize_cause_fail $case_id]"
                            incr i_cases_to_analize
                        } else {
                            set txt "case $case_id fail (only try to analize max=$max_cases_to_analize cases)"
                        }
                    } else {
                        set txt "case $case_id fail"
                    }
                    append body($owner) $txt\n
                }
                if { 0 } {
                    #by now do not send to other GiD developers until the application is finished
                    set subject [_ "failed %s cases assigned to your owner of %d tested at %s" $num_cases_of_owner $num_cases_tested [info hostname]]
                    tester::mail_send $owner $subject $body($owner)
                }                
            }
            
            if { 1 } {
                #harcoded by now to not send to other GiD developers until the application is finished                
                set owner "escolano@cimne.upc.edu"
                set subject [_ "failed %s cases of %d tested at %s" $num_cases_to_notify $num_cases_tested [info hostname]]
                set body_text ""
                foreach item [array names body] {
                    append body_text "$item : $body($item)\n"
                }
                if { ![info exists _body_text_last_email] || $body_text != $_body_text_last_email } {
                    tester::mail_send $owner $subject $body_text
                    set _body_text_last_email $body_text
                }
            }                       
        }
    }
    
    tester::gui_enable_play
    #tester::save_report_html {time workingsetpeak check} tester_report.html 0    
    tester::set_message [_ "Run %s cases finished" [llength $case_ids]]
    
    if { [info procs ::tester::event_after_run_cases] != "" } {
        tester::event_after_run_cases $case_ids
    }
}


#variables (key - value) of each case, to represent it and its results

proc tester::get_variable { case_id key } {
    variable data
    return $data($case_id,$key)
}

proc tester::set_variable { case_id key value } {
    variable data    
    return [set data($case_id,$key) $value]
}

proc tester::lappend_variable { case_id key args } {
    variable data    
    return [lappend data($case_id,$key) {*}$args]
}

proc tester::exists_variable { case_id key } {
    variable data
    return [info exists data($case_id,$key)]
}

proc tester::array_names { case_id key } {
    variable data
    return [array names data $case_id,$key]
}

proc tester::array_unset { case_id key } {
    variable data
    return [array unset data $case_id,$key]
}

proc tester::array_reset {  } {
    variable data
    return [array unset data]
}

#get the list of keys of a case, without include checks
proc tester::get_keys { case_id } { 
    variable case_allowed_keys
    variable case_allowed_attributes
    variable batch_allowed_attributes 
    set pos [string length $case_id,]
    set keys ""
    foreach item [lsort -dictionary [tester::array_names $case_id *]] {
        set key [string range $item $pos end]
        if { [lsearch -dictionary -exact -sorted $case_allowed_keys $key] != -1 } {
            lappend keys $key
        } elseif { [lsearch -dictionary -exact -sorted $case_allowed_attributes $key] != -1 } {
            lappend keys $key
        } elseif { [lsearch -dictionary -exact -sorted $batch_allowed_attributes $key] != -1 } {
            lappend keys $key
        } elseif { [string range $key 0 5] == "check," } {
            #don't want to consider checks as key
        } elseif { [string range $key 0 11] == "checkresult," } {
            #don't want to consider checkresult as key
        } elseif { $key == "maxprocess" } {
            #maxprocess: don't add it to case_allowed_keys because it is difficult to control not to run more processes that a limit while running this
            lappend keys $key
        } else {
            incr unexpected_key
        }
    }
    return $keys
}

#get the list of check keys of a case
proc tester::get_checks { case_id } {    
    set pos [string length $case_id,check,]
    set checks ""
    foreach item [tester::array_names $case_id check,*] {
        set check [string range $item $pos end]
        lappend checks $check
    }
    return $checks
}


#procedures to centralize acess to some files

proc tester::get_relative_path { base_dir filename } {
    set bparts [file split [file normalize $base_dir]]
    set tparts [file split [file normalize $filename]]
    
    if {[lindex $bparts 0] eq [lindex $tparts 0]} {
        # If the first part doesn't match - there is no good relative path
        set blen [llength $bparts]
        set tlen [llength $tparts]
        for {set i 1} {$i < $blen && $i < $tlen} {incr i} {
            if {[lindex $bparts $i] ne [lindex $tparts $i]} { break }
        }
        set path [lrange $tparts $i end]
        for {} {$i < $blen} {incr i} {
            set path [linsert $path 0 ..]
        }
        set filename [join $path [file separator]]
    }
    #file join to change \ by / also for windows
    return [file join $filename]
}

proc tester::get_full_path { base_dir filename } {
    if { [file pathtype $filename] == "relative" } {
        set filename [file join $base_dir $filename]
    }
    return $filename
}

#get the gid.ini file to run gid with this ini configuration
proc tester::get_full_gidini_filename { exefile filename } {
    return [tester::get_full_path [file dirname $exefile] $filename]
}

#inner mean that in tclkit wrapping find inside the exe, else find outside
proc tester::get_full_application_path_inner { filename } {
    variable private_options
    return [tester::get_full_path $private_options(program_path_inner) $filename]
}

proc tester::get_full_case_path { filename } {
    variable preferences
    return [tester::get_full_path $preferences(basecasesdir) $filename]
}

#create the folder if it doesn't exists
proc tester::get_preferences_filename { } {
    variable private_options      
    set dir [file join $private_options(project_path) config]
    if { ![file exists $dir] || ![file isdirectory $dir] } {
        file mkdir $dir
    }
    set filename [file join $dir preferences.xml]
}

proc tester::get_document_filename { } {
    set filename [tester::get_full_case_path [file join xmls tester_cases.xml]]
}

#create the folder if it doesn't exists
proc tester::get_digest_results_filename { } {
    variable private_options      
    set dir [file join $private_options(project_path) config]
    if { ![file exists $dir] || ![file isdirectory $dir] } {
        file mkdir $dir
    }
    set filename [file join $dir digest_results.txt]
}

proc tester::get_tree_open_filename { } {
    variable private_options      
    set dir [file join $private_options(project_path) config]
    if { ![file exists $dir] || ![file isdirectory $dir] } {
        file mkdir $dir
    }
    set filename [file join $dir tree_open.txt]
}

proc tester::get_tmp_folder { } {
    global tcl_platform env
    set tmpdir ""
    if { $tcl_platform(platform) == "unix" } {
        set tmpdir /tmp
    } else {
        if { [info exists ::env(TMP)] } {
            set tmpdir [file join $::env(TMP)] ;#use file join to have always / as separator, also on Windows
        } elseif { [info exists ::env(TEMP)] } {
            set tmpdir [file join $::env(TEMP)] ;#use file join to have always / as separator, also on Windows
        } else {
            set tmpdir [file join $::env(windir) Temp]
        } 
    }
    return $tmpdir
}

proc tester::get_ini_filename { } {
    variable private_options
    if { $::tcl_platform(platform) == "windows" } {
        set ini_filename [file join $::env(APPDATA) $private_options(program_name) $private_options(program_version) $private_options(program_name).ini]
    } else {
        set ini_filename [file join $::env(HOME) .$private_options(program_name) $private_options(program_version) $private_options(program_name).ini]        
    }
    return $ini_filename
}

proc tester::get_ini_filename_other_version { } {
    variable private_options
    set ini_filename_other_version ""     
    set common_folder [file dirname [file dirname [tester::get_ini_filename]]]
    foreach folder [lsort -real -decreasing [glob -nocomplain -type d -directory $common_folder -tails *]] {
        set ini_filename [file join $common_folder $folder $private_options(program_name).ini]
        if { [file exists $ini_filename] } {
            set ini_filename_other_version $ini_filename
            break
        }
    }
    return $ini_filename_other_version
}

proc tester::read_ini { } {
    variable ini
    set ini_filename [tester::get_ini_filename]
    if { ![file exists  $ini_filename] } {
        set ini_filename_other_version [tester::get_ini_filename_other_version]
        if { $ini_filename_other_version != "" } {
            set ini_filename $ini_filename_other_version
        }
    }
    if { [file exists $ini_filename] } {
        set fp [open $ini_filename r]
        set all [read $fp]
        foreach line [split $all \n] {
            lassign $line key value
            if { $key != "" } {
                set ini($key) $value
            }
        }
        close $fp
    }
}

proc tester::save_ini { } {
    variable ini
    set ini_filename [tester::get_ini_filename]
    set dir [file dirname $ini_filename]
    if { ![file exists $dir] || ![file isdirectory $dir] } {
        file mkdir $dir
    }
    set fp [open $ini_filename w]
    foreach key [lsort -dictionary [array names ini]] {
        if { $key != "" } {
            puts $fp "$key [list $ini($key)]"
        }
    }
    close $fp
}

#returns a non existent filename inside the temporal directory
proc tester::get_tmp_filename { {extension .tmp} {suffix "0"} } {  
    set tmpdir [tester::get_tmp_folder]
    #open and close the file to be used to create it and reserve for the process 
    #(else can repeat the name for other process)
    set tmpname [file join $tmpdir gid$suffix]$extension
    set fp [open $tmpname "w"]
    set i 1
    while { $fp == "" } {
        set tmpname [file join $tmpdir gid$suffix-$i]$extension
        set fp [open $tmpname "w"]
        incr i
    }
    if { $fp != "" } {
        close $fp
    }
    return $tmpname
}

#return something like Windows
proc tester::get_platform_provide_os { } {
    variable preferences
    return [lindex $preferences(platform_provide) 2]
}

#return 32 or 64
proc tester::get_platform_provide_bits { } {
    variable preferences
    return [lindex $preferences(platform_provide) 1]
}

proc tester::read_gid_monitoring_info { filename } {
    set all ""
    if { [file exists $filename] } {
        set all [tester::read_file $filename]
    } else {
        tester::puts_log_error "file '$filename' doesn't exists"
    }
    return $all
}

#common procedure to read the whole content
proc tester::read_file { filename {encoding ""} } {
    set content ""
    if { [file exists $filename] } {
        set fp [open $filename r]
        if { $fp != "" } {
            if { $encoding != "" } {
                fconfigure $fp -encoding $encoding
            }
            set content [read -nonewline $fp]
            close $fp
        }
    }
    return $content
}

#procedure to be used to get some part of a file in test cases
#e.g.
#<outfile>models/example_other/example_other.post.res</outfile>
#<readingproc>::tester::get_line_file 10 2</readingproc>
#filename extra argument is automatically appended with the value of outfile
#<check>
#   <check-1>$my_value>5.69 &amp;&amp; $file_item&lt;5.70</check-1>
# </check>

proc tester::get_line_file { row column filename args } {
    set res [list my_value -1]
    if { [file exists $filename] } {
        set fp [open $filename r]
        set i_line 0
        while { ![eof $fp] } {
            gets $fp line
            incr i_line
            if { $i_line == $row } {
                set res [list file_item [lindex $line $column-1]]
            }
        } 
        close $fp
    }
    return $res
}

#use a md5 digest to assign a unique id to each case

#assign/recover id, read, save digest vs id
proc tester::get_md5_xml_node_case { xml_node_case } {
    set md5_token [md5::MD5Init]
    foreach xml_child_node [$xml_node_case childNodes] {
        set node_type [$xml_child_node nodeType]
        if { $node_type == "ELEMENT_NODE" } {
            set node_name [$xml_child_node nodeName] 
            if { $node_name == "batch" || $node_name == "exe" || $node_name == "args" } {
                #ignore the rest of tags to avoid case_id change when modifying auxiliary things
                md5::MD5Update $md5_token [$xml_child_node text]
            }        
        }
    }
    return [md5::Hex [md5::MD5Final $md5_token]]    
}

#generic procedures are not used to avoid changing digest
proc tester::get_md5_xml_generic { xml_node_case } {
    set md5_token [md5::MD5Init]
    tester::get_md5_recursive_xml_node $xml_node_case $md5_token    
    return [md5::Hex [md5::MD5Final $md5_token]]    
}

#auxiliary recursive procedure to calculate digest 
proc tester::get_md5_recursive_xml_node { xml_node md5_token } {
    set node_type [$xml_node nodeType]
    if { $node_type == "ELEMENT_NODE" } {
        set node_name [$xml_node nodeName] 
        md5::MD5Update $md5_token $node_name
        md5::MD5Update $md5_token [$xml_node text]
        md5::MD5Update $md5_token [$xml_node attributes] 
        foreach xml_child_node [$xml_node childNodes] {
            tester::get_md5_recursive_xml_node $xml_child_node $md5_token
        }
    }
    return 0 
}

proc tester::unset_digest_results { } {
    variable digest_results
    variable private_options
    array unset digest_results
    set private_options(must_save_digest_results) 0
}

#store some averaged digest of the historic results
proc tester::read_digest_results { } {
    variable digest_results ;#array to store digest of history of results, and last tested result
    variable private_options
    set filename [tester::get_digest_results_filename]
    set txt [::tester::read_file $filename]
    if { $txt != "" } {
        foreach line [split $txt \n] {
            set case_id [lindex $line 0]
            set digest_results($case_id) [lrange $line 1 7] ;#fail time memory date min_time min_memory ok_date
        }
    }
    set private_options(must_save_digest_results) 0
}

proc tester::save_digest_results { } {
    variable digest_results ;#array to store digest of history of results, and last tested result
    variable private_options
    if { $private_options(must_save_digest_results) } {
        set filename [tester::get_digest_results_filename]
        set fp [open $filename w]
        foreach case_id [lsort -dictionary [array names digest_results]] {
            puts $fp [list $case_id {*}[tester::digest_results_get_values $case_id]]
        }
        close $fp
        set private_options(must_save_digest_results) 0
    }
}

# xml document tools
proc tester::save_xml_file { doc filename } { 
    set fail 0
    set fout [open $filename w]
    if { $fout != "" } {
        fconfigure $fout -encoding utf-8
        puts $fout {<?xml version="1.0" encoding="utf-8"?>}
        puts $fout [$doc asXML -indent 2]
        close $fout
    } else {
        set fail 1
    }
    return $fail
}

proc tester::xml_create_text_node { xml_parent txt } {
    set newNode [[$xml_parent ownerDocument] createTextNode $txt]
    $xml_parent appendChild $newNode
    return $newNode
}

proc tester::xml_create_element { xml_parent name {attributes ""} } {
    set newNode [[$xml_parent ownerDocument] createElement $name]
    if { $attributes != "" } {
        $newNode setAttribute {*}$attributes
    }
    $xml_parent appendChild $newNode
    return $newNode
}

#getElementById seem that already doesn't work in tdom 0.8.3, or only works for -html parsed documents!!
proc tester::xml_get_element_by_id { xml_document case_id } {
    #return [$xml_document getElementById $case_id]
    set xml_node [$xml_document selectNodes "//*\[@id='$case_id'\]"]
    if { [llength $xml_node] > 1 } {
        tester::message "tester::xml_get_element_by_id. case_id '$case_id' repeated [llength $xml_node], copies deleted"
        foreach xml_child [lrange $xml_node 0 end-1] {
            [$xml_child parentNode] removeChild $xml_child
            $xml_child delete
        }
        set xml_node [lindex $xml_node end]
    }
    return $xml_node
}

proc tester::xml_get_text_node_by_field { xml_parent field } {
    set xml_text_node ""
    set xml_node [$xml_parent selectNodes "./$field"]
    if { [llength $xml_node] > 1 } {
        tester::message "tester::xml_get_text_node_by_field. Field '$field' repeated [llength $xml_node], copies deleted"
        foreach xml_child [lrange $xml_node 0 end-1] {
            $xml_parent removeChild $xml_child 
            $xml_child delete
        }
        set xml_node [lindex $xml_node end]
    }
    if { [llength $xml_node] == 1 } {
        lappend xml_text_node [$xml_node childNodes] ;#expected only a text child node
    }
    return $xml_text_node
}

proc tester::xml_clone_node_case { xml_node_case } {    
    #return [$xml_node_case cloneNode -deep]    
    
    #instead of clone it fill the new node with the accepted keys and ordered
    variable case_allowed_keys
    variable case_allowed_attributes
    
    set new_xml_node_case [tester::xml_create_element $xml_node_case case ""]    
    foreach key $case_allowed_keys {
        if { $key == "check" } {
            continue 
        }
        set xml_node [$xml_node_case selectNodes ./$key]
        if { [llength $xml_node] == 1 } {
            set value [string trim [$xml_node text]]
            if { $value != "" && $value != [tester::get_preferences_key_value $key] } {
                set key_xml_node [tester::xml_create_element $new_xml_node_case $key ""]
                tester::xml_create_text_node $key_xml_node $value
            }
        } elseif { [llength $xml_node] > 1 } {
            tester::message "tester::xml_clone_node_case. unexpected [llength $xml_node] $key nodes"
            foreach xml_repeated_node $xml_node {
                tester::message [$xml_repeated_node text]
            }
        }
    }    
    foreach attribute $case_allowed_attributes {
        if { $attribute == "id" } {
            #this attribute is set automatically
            continue
        }        
        if { [$xml_node_case hasAttribute $attribute] } {
            set value [$xml_node_case getAttribute $attribute]
            if { $value != "" && $value != [tester::get_default_attribute_value $attribute]} {         
                $new_xml_node_case setAttribute $attribute $value
            }
        }
    }
    set xml_node [$xml_node_case selectNodes ./check]
    if { [llength $xml_node] == 1 } {
        set check_xml_node [tester::xml_create_element $new_xml_node_case check ""]
        set i 1
        foreach xml_child_node [$xml_node childNodes] {
            set key check-$i
            set value [string trim [$xml_child_node text]]
            if { $value != "" } {
                set key_xml_node [tester::xml_create_element $check_xml_node $key ""]
                tester::xml_create_text_node $key_xml_node $value        
                incr i
            }
        }    
    } elseif { [llength $xml_node] > 1 } {
        tester::message "tester::xml_clone_node_case. unexpected [llength $xml_node] check nodes"
    }
    return $new_xml_node_case
}

proc tester::merge_xml_files { filestoread xml_document_to_add } {  
    if { $xml_document_to_add == "" } {        
        set doc_total [dom parse "<cases version='1.0'/>"]
    } else {
        set doc_total $xml_document_to_add
    }
    set root_total [$doc_total documentElement]
    foreach filename $filestoread {
        set xml [tester::read_file $filename utf-8]        
        if { $xml != "" } {            
            #tricks to import old information encoded in filenames
            if { [string match {*only developer*} $filename] } {
                set branch_require developer
            } else {
                set branch_require ""
            }
            if { [string match {*cases_failing*} $filename] } {
                set fail_accepted 1
            } else {
                set fail_accepted 0
            }
            set fail_random 0
            set file_tags [split [string tolower [file rootname [file tail $filename]]] _]
            set doc_to_merge [dom parse $xml]
            set root_to_merge [$doc_to_merge documentElement]
            #file could have a 'owner' node as common value for its cases (and the case could also overwrite this common value)
            set owner ""
            set xml_owner_node [$root_to_merge selectNodes /cases/owner]
            if { $xml_owner_node != "" } {
                set owner [string trim [$xml_owner_node text]]
            }                
            foreach xml_node_case [$root_to_merge selectNodes case] {
                #if there is general owner and case doesn't has a particular owner set it as the general one
                if { $owner != "" } {
                    set xml_owner_node [$xml_node_case selectNodes ./owner]
                    if { $xml_owner_node == "" } {
                        set new_xml_node [tester::xml_create_element $xml_node_case owner ""]
                        set new_xml_text_node [tester::xml_create_text_node $new_xml_node $owner]
                    }
                }
                #if case doesn't has a tags node then add it based on the filename file_tags
                set xml_child [$xml_node_case selectNodes ./tags]
                if { $xml_child == "" } {
                    set new_xml_node [tester::xml_create_element $xml_node_case tags ""]
                    set new_xml_text_node [tester::xml_create_text_node $new_xml_node $file_tags]
                }                
                #if case doesn't has name set it from batch if any
                set xml_node_name [$xml_node_case selectNodes ./name]
                if { $xml_node_name == "" } {
                    set xml_node_batch [$xml_node_case selectNodes ./batch]
                    if { $xml_node_batch != "" } {
                        set value [file rootname [file tail [$xml_node_batch text]]]
                        set xml_node_name [tester::xml_create_element $xml_node_case name ""]
                        tester::xml_create_text_node $xml_node_name $value
                    }
                }
                #convert old classification "only developer" as branch_require=developer attribute
                if { $branch_require != "" } {
                    $xml_node_case setAttribute branch_require $branch_require                    
                }
                #convert old classification "cases_failing" as fail_accepted=1 attribute
                if { $fail_accepted } {
                    $xml_node_case setAttribute fail_accepted 1
                }
                if { $fail_random } {
                    $xml_node_case setAttribute fail_random 1
                }
            }                  
            #add only case nodes to the total file: instead of
            #  $root_to_merge childNodes
            #  $root_to_merge selectNodes case
            foreach xml_node_case [$root_to_merge selectNodes case] {
                set case_id [tester::get_md5_xml_node_case $xml_node_case]
                $xml_node_case setAttribute id $case_id
                set xml_node_cases_old [tester::xml_get_element_by_id $doc_total $case_id]
                if { [llength $xml_node_cases_old] > 1 } {
                    tester::message "unexpected [llength $xml_node_cases_old] cases with id $case_id"
                }
                foreach xml_node_case_old $xml_node_cases_old {
                    #case already exists, delete it to be redefined
                    [$xml_node_case_old parentNode] removeChild $xml_node_case_old 
                    $xml_node_case_old delete
                }
                $root_total appendChild [tester::xml_clone_node_case $xml_node_case]
            }
            $doc_to_merge delete
        }
    }        
    return $doc_total
}

proc tester::set_case_id_variables_from_xml_node_case { xml_node_case case_id } {
    variable case_allowed_keys
    variable case_allowed_attributes
    variable private_options
    variable batch_allowed_attributes
    tester::array_unset $case_id *
    foreach child [$xml_node_case childNodes] {
        if { [lsearch -dictionary -exact -sorted -dictionary $case_allowed_keys [$child nodeName]] != -1 } {
            if { [$child nodeName] == "check" } {
                set i 1
                foreach check [$child childNodes] {
                    set key check-$i
                    tester::set_variable $case_id check,$key [$check text]
                    incr i
                }
            } else {
                tester::set_variable $case_id [$child nodeName] [$child text]
                if { [$child nodeName] == "batch" } {
                    foreach attribute $batch_allowed_attributes {                          
                        if { [$child hasAttribute $attribute] } {
                            set value [$child getAttribute $attribute]
                            if { $value != "" } {         
                                tester::set_variable $case_id $attribute $value
                            }
                        }
                    }
                    
                }
            }
        } else {
            #help or bad key
            if { [$child nodeName] != "#comment" } {
                tester::message "Unknown key [$child nodeName]"
            }
        }                         
    }
    
    if { ![tester::exists_variable $case_id exe] } {
        #force set exe variable because is used by tester::case_ids to enumerate them
        tester::set_variable $case_id exe [tester::get_preferences_key_value exe]
    }
    
    if { ![tester::exists_variable $case_id offscreen_exe] } {
        #force set exe variable because is used by tester::case_ids to enumerate them
        tester::set_variable $case_id offscreen_exe [tester::get_preferences_key_value offscreen_exe]
    }
    
    foreach attribute $case_allowed_attributes {
        if { $attribute == "id" } {
            #this attribute is set automatically
            continue
        }
        set value [$xml_node_case getAttribute $attribute ""]
        if { $value != "" } {
            tester::set_variable $case_id $attribute $value
        }
    }
    foreach tag [tester::get_variable $case_id tags] {                            
        if { ![tester::exists_filter_tag $tag] } {
            tester::set_filter_tag $tag 0
        }                            
    }       
    set private_options(must_save_document) 1
    return 0
}
#read tester cases from xml file
proc tester::read_cases_xml_file { filename } {    
    set xml [tester::read_file $filename utf-8]
    if { $xml == "" } return     
    set document [dom parse $xml]
    return [tester::read_cases_xml_document $document]
}

#assumed all cases stored in a single document file 
#(but can unload cases from several selected files that are merged before in a single document)
proc tester::read_cases_xml_document { document } {        
    variable preferences
    variable private_options      
    
    foreach key {maxmemory maxprocess exe offscreen_exe timeout gidini owner} {
        set general($key) [tester::get_preferences_key_value $key]
    }
    
    set num_cases 0
    set root [$document documentElement]
    if { [$root nodeName] == "cases"} {
        foreach xml_child_node [$root childNodes] {
            set node_type [$xml_child_node nodeType]
            if { $node_type == "COMMENT_NODE"} {
                continue
            } elseif { $node_type == "ELEMENT_NODE" } {
                #process it
            } else {
                set wrong_file 1
            }
            
            switch [$xml_child_node nodeName] {
                "maxmemory" {
                    set general(maxmemory) [$xml_child_node text]
                    if { $general(maxmemory) < 0 } {
                        set general(maxmemory) $preferences(maxmemory)
                    }
                }
                "maxprocess" {
                    set general(maxprocess) [$xml_child_node text]
                    if { $general(maxprocess) < 1 } {
                        set general(maxprocess) $preferences(maxprocess)
                    }
                }
                "exe" {                 
                    set general(exe) [$xml_child_node text]                               
                }
                "offscreen_exe" {                 
                    set general(offscreen_exe) [$xml_child_node text]                               
                }  
                "timeout" {
                    set general(timeout) [$xml_child_node text]
                    if { $general(timeout) < 0 } {
                        set general(timeout) $preferences(timeout)
                    }
                } 
                "owner" {
                    set general(owner) [$xml_child_node text]
                    tester::owners_append_unique $general(owner)
                }
                "gidini" {
                    set general(gidini) [$xml_child_node text]
                }                
                "case" {
                    set xml_node_case $xml_child_node
                    set case_id [tester::get_md5_xml_node_case $xml_node_case]
                    $xml_node_case setAttribute id $case_id
                    tester::set_case_id_variables_from_xml_node_case $xml_node_case $case_id
                    if { ![tester::exists_variable $case_id exe] } { 
                        tester::set_variable $case_id exe $general(exe)                            
                    }
                    if { ![tester::exists_variable $case_id offscreen_exe] } { 
                        tester::set_variable $case_id offscreen_exe $general(offscreen_exe)
                    }
                    if { ![tester::exists_variable $case_id timeout] } { 
                        tester::set_variable $case_id timeout $general(timeout)
                    }                    
                    if { ![tester::exists_variable $case_id owner] } { 
                        tester::set_variable $case_id owner $general(owner)
                    } else {
                        tester::owners_append_unique [tester::get_variable $case_id owner]
                    }
                    if { ![tester::exists_variable $case_id gidini] } { 
                        tester::set_variable $case_id gidini [get_full_gidini_filename [tester::get_variable $case_id exe] $general(gidini)]
                    }
                    incr num_cases                    
                }
                default {
                }
            }
        }
    }
    
    set private_options(xml_document) $document
    return $num_cases
}

#
proc tester::delete_case { case_id } {    
    variable tested_cases
    variable private_options
    
    tester::remove_case_from_tree $case_id
    
    set result [tester::evaluate_checks $case_id]    
    if { $result == "untested" || $result == "running" || $result == -1 } {
        incr tested_cases(untested) -1
    } elseif { $result == "ok" || $result == 0 } {
        incr tested_cases(ok) -1
    } elseif { $result == "fail" || $result == "crash" || $result == "timeout" || $result == "maxmemory" } {
        incr tested_cases(fail) -1
    } elseif { $result == "userstop" } {
        #do nothing
    } else {
        incr tested_cases(fail) -1
    }
    
    tester::array_unset $case_id *    
    
    set document $private_options(xml_document)
    set xml_node_case [tester::xml_get_element_by_id $document $case_id]
    if { $xml_node_case == "" } {
        tester::message [_ "The case %s doesn't exists" $case_id]
    } else {        
        [$xml_node_case parentNode] removeChild $xml_node_case 
        $xml_node_case delete
    }
    set private_options(must_save_digest_results) 1
    set private_options(must_save_document) 1
}

#list of all cases integer ids
proc tester::case_ids { } {    
    set case_ids ""
    foreach item [tester::array_names * exe] {
        lappend case_ids [string range $item 0 end-4]
    }
    set case_ids [lsort -dictionary $case_ids]
    return $case_ids
}

proc tester::ignore_case_id { case_id } {
    variable preferences
    
    if { $preferences(filter_platform_provide) } {  
        if { [tester::exists_variable $case_id platform_require] } {
            set value_required [list]
            foreach require [tester::get_variable $case_id platform_require] provide $preferences(platform_provide) {
                if { $require == "*" } {
                    lappend value_required $provide
                } else {
                    lappend value_required $require
                }
            }
        } else {
            set value_required $preferences(platform_provide)
        }
        if { $value_required != $preferences(platform_provide) } {
            return 1
        }            
    }
    
    if { $preferences(filter_branch_provide) } {  
        if { [tester::exists_variable $case_id branch_require] } {
            set value_required [tester::get_variable $case_id branch_require]                
        } else {               
            set value_required $preferences(branch_provide)
        }
        if { $value_required != $preferences(branch_provide) } {
            return 1
        }            
    }             
    
    if { $preferences(filter_fail_accepted) } {                                        
        if { [tester::exists_variable $case_id fail_accepted] } {
            set value [tester::get_variable $case_id fail_accepted]
        } else {
            set value 0
        }                
        if { $value == $preferences(filter_fail_accepted_value) } {                
            return 1
        }
    }                    
    
    if { $preferences(filter_fail_random) } {                                        
        if { [tester::exists_variable $case_id fail_random] } {
            set value [tester::get_variable $case_id fail_random]
        } else {
            set value 0
        }                
        if { $value == $preferences(filter_fail_random_value) } {                
            return 1
        }
    }          
    
    if { $preferences(filter_tags) } {
        #hide cases that match some of the current active tags
        set ignore_case 0
        set case_tags [tester::get_variable $case_id tags]
        foreach case_tag $case_tags {
            set tag_active [tester::get_filter_tag $case_tag]
            if { $tag_active } {
                set ignore_case 1
                break
            }
        }
        if { $ignore_case } {
            return 1
        }
    }
    if { $preferences(filter_date) } {
        set case_test_ok_date [tester::digest_results_get_ok_date $case_id] ;#last test date
        if { $case_test_ok_date != "" } {
            set exe [tester::get_variable $case_id exe]
            if { ![info exists exe_mtime($exe)] } {
                #cache it to find it once in this loop
                if { [file exists $exe] } {
                    set exe_mtime($exe) [file mtime $exe]
                } else {
                    set exe_mtime($exe) ""
                }
            }
            set exe_date $exe_mtime($exe)
            if { $exe_date != "" && $case_test_ok_date > $exe_date } {
                #to not repeat the same test with the same exe
                return 1
            }
        }            
    }
    if { $preferences(filter_time) } {
        set time_max_limit [expr {$preferences(filter_time_value)*60}]
        set case_test_min_time [tester::digest_results_get_min_time $case_id] ;#last test date
        if { $case_test_min_time != "" && $case_test_min_time > $time_max_limit } {
            #to test only fast cases
            return 1
        }
    }
    if { $preferences(filter_memory) } {
        set memory_max_limit [expr {$preferences(filter_memory_value)*1024*1024}]
        set case_test_min_memory [tester::digest_results_get_min_memory $case_id] ;#last test date
        if { $case_test_min_memory != ""  && $case_test_min_memory > $memory_max_limit } {
            #to test only fast cases
            return 1            
        }
    }
    if { $preferences(filter_fail) } {
        set result [tester::digest_results_get_fail $case_id] ;#last test result
        if { $result != "" && $result == $preferences(filter_fail_value) } {
            #to hide previously fail or ok cases
            return 1
        }
    }
    return 0
}

#apply selection filters to a list of cases
proc tester::filter_case_ids { case_ids } {        
    variable preferences
    set num_filtered 0
    set filtered_case_ids [list]
    foreach case_id $case_ids {
        if { $preferences(enable_filters) } {
            set ignore_case [tester::ignore_case_id $case_id]
            if { $preferences(opposite_filters) } {
                set ignore_case [expr !$ignore_case]
            }
        } else {
            set ignore_case 0
        }
        if { $ignore_case } {
            incr num_filtered        
        } else {
            lappend filtered_case_ids $case_id
        }
    }
    if { $num_filtered } {
        tester::set_message [_ "Filtered %s cases" $num_filtered]
    }
    return $filtered_case_ids
}

# start/end the program
proc tester::start { } {    
    variable private_options      
    variable ini  
    
    #set dir [file dirname [info script]]
    #if { $dir == "" } {
        #        set dir [file dirname [info nameofexecutable]]
        #}
    #set dir [file normalize $dir]
    
    if { [info exists starkit::topdir] } {
        #if it's packed as starkit, must go up a directory, argv0 point to passerver-conf.exe\main.tcl
        set ::argv0 [file dirname $::argv0]
        set private_options(program_path_inner) $starkit::topdir        
    }
    
    set dir [file dirname $::argv0]
    if { [file pathtype $dir] == "relative" } {
        set dir [file join [pwd] $dir]
    }    
    set dir [file normalize $dir]
    set private_options(program_path) $dir
    
    if { ![info exists starkit::topdir] } {
        #if is not a starkit then inner doen't has sense, use outer
        set private_options(program_path_inner) $private_options(program_path)
    }
    
    package require msgcat   
    package require tdom
    package require gid_cross_platform
    package require md5
    
    #if { $::tcl_platform(platform) == "windows" } {       
    #    package require registry        
    #} 
    
    #check command line arguments
    foreach {flag variable_name} {-project project_path -eval eval_code -source tcl_filename -gui gui} {
        if { [set ipos [lsearch $::argv $flag]] != -1 } {
            set $variable_name [lindex $::argv $ipos+1]
        } else {
            set $variable_name ""
        }   
    }
    
    if { $gui != "" } {
        set private_options(gui) $gui
    }   
    if { $private_options(gui) } {
        package require img::png
    }
    
    tester::set_default_preferences   
    tester::trace_add_variable_preferences 
    tester::read_ini    
    tester::create_win        
    if { $project_path == "" && $ini(reloadlastproject) } {        
        set project_path [lindex [tester::get_recent_projects] 0]
    }
    if { $project_path != ""} {    
        tester::read_project $project_path
    }
    
    if { $tcl_filename != "" } {
        tester::source $tcl_filename
    }
    if { $eval_code != "" } {
        uplevel #0 eval $eval_code
    }
    
    tester::start_track_schedule_run_at ; #to allow automatically run all cases daily and analize fails
        
    if { !$private_options(gui) } {
        vwait forever
    }
    return 0
}

proc tester::source { batch_file } { 
    if { ![file exists $batch_file] } {
        tester::message_box [_ "Batch file '%s' doesn't exists" $batch_file] error
        return 1
    }
    source $batch_file
    return 0
}

proc tester::clear_project { } {    
    tester::clear_process
    tester::array_reset
    tester::unset_digest_results
    tester::new_document    
    tester::clear_tree
}

proc tester::clear_process { } {
    variable progress
    variable maxprogress
    tester::kill_all_process
    tester::reset_counter_tested_cases -1
    tester::gui_enable_play
    set progress 0
    set maxprogress 0    
}

proc tester::clear_tree { } {
    variable private_options
    if { $private_options(gui) } {
        variable tree
        variable tree_item_case
        $tree item delete all
        array unset tree_item_case
    }
}

proc tester::new_project { project_path } {
    variable private_options
    variable preferences
    if { $project_path == "" } {
        return 1
    }
    if { [file extension $project_path] != ".tester" } {
        tester::message_box [_ "The project folder must have '.tester' extension"] error
        return 1
    }
    if { [file exists $project_path] } {
        if { ![file isdirectory $project_path] } {
            ester::message_box [_ "The project must be a folder"] error
            return 1
        }
    } else {
        file mkdir $project_path
    }
    set private_options(project_path) $project_path        
    tester::open_log
    tester::clear_project
    tester::set_default_preferences   
    tester::update_title
    tester::fill_tree
    tester::add_recent_projects $project_path
    tester::fill_menu_recent_projects     
    tester::ask_missing_preferences    
    tester::check_log_size ;#to check every midnigth the log size
}

proc tester::wait_state { } {
    variable private_options
    if { $private_options(gui) } {
        variable mainwindow
        $mainwindow configure -cursor watch 
        update
    }
}

proc tester::end_wait_state { } {
    variable private_options
    if { $private_options(gui) } {
        variable mainwindow
        $mainwindow configure -cursor "" 
        update
    }
}

proc tester::read_project { project_path } { 
    variable private_options
    variable preferences
    variable ini
    
    
    #     if { $project_path == "" } {
        #         set project_path [tk_chooseDirectory -title "Choose project folder"]
        #     }
    if { $project_path == ""} {     
        return 1
    }
    if { [file extension $project_path] != ".tester" } {
        tester::message_box [_ "The project folder must have '.tester' extension"] error
        return 1
    }
    if { [file exists $project_path] } {
        if { ![file isdirectory $project_path] } {
            tester::message_box [_ "The project must be a folder"] error
            return 1
        }
    } else {        
        tester::message_box [_ "Folder '%s' doesn't exists" $project_path] error
        return 1
    }
    
    tester::wait_state
    
    set private_options(project_path) $project_path
    tester::open_log
    tester::clear_project
    tester::read_preferences
    tester::ask_missing_preferences        
    tester::update_title
    tester::read_digest_results   
    tester::read_document
    tester::read_tree_status_filename
    tester::fill_tree
    tester::add_recent_projects $project_path
    tester::fill_menu_recent_projects 
    tester::check_log_size ;#to check every midnigth the log size
    cd $preferences(basecasesdir)   
    
    tester::end_wait_state
    return 0
}

proc tester::add_recent_projects { project_path } {
    variable ini
    set project_path [file join $project_path] ;#to change \ by /
    if { [lsearch -exact $ini(recent_projects) $project_path] == -1 } {
        set ini(recent_projects) [list $project_path {*}$ini(recent_projects)]
        if { [llength $ini(recent_projects)] > 5 } {
            set ini(recent_projects) [lrange $ini(recent_projects) 0 4]
        }
    }
}

proc tester::get_recent_projects { } {
    variable ini
    return $ini(recent_projects)
}

proc tester::exit { } {
    tester::kill_all_process
    tester::save_preferences    
    tester::save_tree_status_filename
    tester::close_log
    tester::save_ini
    ::exit 0
}

#automatic check, if outputfiles are declared impliclty check that files exists
proc tester::file_exists_declared_outputfiles { case_id } {
    set exists 1
    set key outputfiles
    if { [tester::exists_variable $case_id $key] } {                
        foreach filename [tester::get_variable $case_id $key] {
            set filename [subst -nobackslashes -novariables $filename] ;#to allow replacing [] procedures 
            if { ![file exists $filename] } {
                set exists 0
                break
            }
        }
    }
    return $exists
}

#get the case result based on checks done. returns: untested running ok fail crash timeout maxmemory userstop
# untested                            not tried to run
# runnnig                             already running
# ok                                  run and pass all tests
# fail                                run and some test not passed
# crash timeout maxmemory userstop   had problems to run
proc tester::evaluate_checks { case_id } {
    set result "ok"
    set checks [tester::get_checks $case_id]
    if { [tester::exists_variable $case_id outputfiles] } {
        set checks [list outputfiles {*}$checks]
    }
    foreach check $checks {
        if { [tester::exists_variable $case_id checkresult,$check] } {
            set ok_check [tester::get_variable $case_id checkresult,$check]
        } else {
            set result "untested"
            break
        }
        if { $ok_check == 0 } {
            set result "fail"
        } elseif { $ok_check == 1 } {
            #set result "ok"            
            #commented to not overwrite possible fail value of other checks            
            #globally is ok only if all are ok
        } elseif { $ok_check == 5 } {            
            set result "userstop"
        } else {
            set result "crash"
            #overwrite global ok with some local fail crash timeout maxmemory userstop           
        }
    }    
    return $result
}

proc tester::update_counters_ok_fail_untested_new_run_cases { case_ids_to_run } {
    variable tested_cases
    variable digest_results
    #tester::reset_counter_tested_cases [llength $case_ids_to_run]
    foreach case_id $case_ids_to_run {
        #set result [tester::evaluate_checks $case_id]
        if { [info exists digest_results($case_id)] } {
            lassign $digest_results($case_id) result time memory date min_time min_memory ok_date
            if { $result == "" } {
                set result "untested"
            }
        } else {
            set result "untested" 
        }
        if { $result == "ok" || $result == 0 } {
            incr tested_cases(ok) -1
            incr tested_cases(untested)
        } elseif { $result == "untested" || $result == "running" || $result == -1 } {
            #untested
        } elseif { $result == "fail" || $result == 1 || $result == "crash" || $result == "timeout" || $result == "maxmemory" } {
            incr tested_cases(fail) -1
            incr tested_cases(untested)
        } elseif { $result == "userstop" } {
            #do nothing
        } else {
            incr tested_cases(fail) -1
            incr tested_cases(untested)
        }                                
    }
    return 0
}

proc tester::run_case_userstop { case_id } {
    #variable tested_cases
    set result "userstop"
    #incr tested_cases(untested) -1
    tester::digest_results_set_last_test_values $case_id $result "" "" ""
    #tester::update_case_and_parents_tree_state $case_id $result
}

#run a selection of cases
proc tester::run { case_ids force_with_window { run_option ""}} {    
    variable nprocess
    variable case_ids_running
    variable preferences    
    variable cancel_process
    variable pause_process
    variable progress
    variable maxprogress
    
    
    set case_ids_to_run $case_ids
    tester::update_counters_ok_fail_untested_new_run_cases $case_ids_to_run    
    tester::private_event_before_run_cases $case_ids_to_run
    
    set progress 0
    if { $force_with_window } {
        set maxprogress 0
    } else {
        set maxprogress [llength $case_ids_to_run]
    }
        
    while { [llength $case_ids_to_run] >0 } {
        if { $pause_process } {
            vwait ::tester::pause_process
        }
        set case_id [lindex $case_ids_to_run 0]        
        if { $case_id == "" } {
            #unexpected
        } else {
            if { [tester::exists_variable $case_id maxprocess] } {
                set maxprocess [tester::get_variable $case_id maxprocess]
            } else {
                set maxprocess $preferences(maxprocess)
            }
            #if some process already running has maxprocess more restrictive use it
            foreach case_id_running $case_ids_running {
                if { [tester::exists_variable $case_id_running maxprocess] } {
                    set v [tester::get_variable $case_id_running maxprocess]
                    if { $v < $maxprocess } {
                        set maxprocess $v
                    }
                }                
            }
            while { $nprocess >= $maxprocess && !$cancel_process } {
                vwait ::tester::nprocess
            }
            if { $cancel_process } {
                tester::run_case_userstop $case_id
            } else {
                tester::execute_test $case_id $force_with_window $run_option
            }
        }
        set case_ids_to_run [lrange $case_ids_to_run 1 end]
    }
    
    #all process are started, but wait until they finish before raise private_event_after_run_cases
    while { $nprocess } {
        vwait ::tester::nprocess
    }
    if { $cancel_process } {
        tester::set_message [_ "User stopped"]
    }
    tester::private_event_after_run_cases $case_ids
}

#get the list of variables involved in the checks to be required to GiD (trough the bath) 
proc tester::get_check_variables { case_id } {
    set variables ""
    foreach check [tester::get_checks $case_id] {
        set test [tester::get_variable $case_id check,$check]
        foreach item [regexp -all -inline {\${[a-zA-Z0-9_:]+(?:\([^\)]*\))?}|\$[a-zA-Z0-9_:]+(?:\([^\)]*\))?} $test] {
            lappend variables [string range $item 1 end]
        }        
    }
    return $variables
}

#get the list of Tcl expressiong involved in the checks to be required to GiD (trough the bath)
proc tester::get_expr_procedures { case_id } {
    set expr_procedures [list]
    foreach check [tester::get_checks $case_id] {
        set test [tester::get_variable $case_id check,$check]
        if { [regexp {GiD_expr (.*)} $test dummy procedure] } {
            lappend expr_procedures $procedure
        }
    }
    return $expr_procedures
}

#auxliary
proc tester::is_gid_exe { exefile } {
    if { [string first "gid" [string tolower [file tail $exefile]]] != -1 } {
        return 1
    } else {
        return 0        
    }    
}

proc tester::valgrind_get_output_filename { case_id extension} {
    set dir [ file join [ pwd] output]
    file mkdir $dir
    return [ file join $dir valgrind_gid${case_id}.${extension}]
}

proc tester::valgrind_open_output { case_id editor extension} {
    if { "$editor" == "code"} {
        set val_file [ tester::valgrind_get_output_filename $case_id $extension]
        if { ![ file exists $val_file]} {
            tester::message [_ "Valgrind $extension file does not exist for case $case_id"]
            return
        }
        if { [ catch { exec code $val_file &} error]} {
            return -code error "couldn't execute 'code': $error"
        }
    } elseif { "$editor" == "valkyrie"} {
        set val_file [ tester::valgrind_get_output_filename $case_id xml]
        if { ![ file exists $val_file]} {
            tester::message [_ "Valgrind xml file does not exist for case $case_id"]
            return
        }
        if { [ catch { exec valkyrie -l $val_file &} error]} {
            return -code error "couldn't execute 'valkyrie': $error"
        }
    } else {
        set val_file [ tester::valgrind_get_output_filename $case_id $extension]
        if { ![ file exists $val_file]} {
            tester::message [_ "Valgrind $extension file does not exist for case $case_id"]
            return
        }
        gid_cross_platform::open_by_extension $val_file
    }
}

proc tester::sanitize_get_output_filename { case_id} {
    set dir [ file join [ pwd] output]
    file mkdir $dir
    return [ file join $dir sanitize_gid${case_id}.txt]
}

proc tester::sanitize_open_output { case_id editor} {
    if { "$editor" == "code"} {
        set val_file [ tester::sanitize_get_output_filename $case_id]
        if { ![ file exists $val_file]} {
            tester::message [_ "Sanitize txt file does not exist for case $case_id"]
            return
        }
        if { [ catch { exec code $val_file &} error]} {
            return -code error "couldn't execute 'code': $error"
        }
    } else {
        set val_file [ tester::sanitize_get_output_filename $case_id]
        if { ![ file exists $val_file]} {
            tester::message [_ "Sanitize txt file does not exist for case $case_id"]
            return
        }
        gid_cross_platform::open_by_extension $val_file
    }
}

#exec a test
proc tester::execute_test { case_id force_with_window { run_option ""}} {
    variable nprocess
    variable case_ids_running
    variable preferences    
    tester::private_event_before_run_case $case_id
    
    set my_exe [tester::get_variable $case_id exe]
    if { $my_exe != "" && ![file exists $my_exe] && [file pathtype $my_exe] == "relative" } {
        set my_exe_full [file join [file dirname $preferences(exe)] $my_exe]
        if { [file exists $my_exe_full] } {
            set my_exe $my_exe_full 
        }
    }
    
    if { [tester::exists_variable $case_id offscreen] && [tester::get_variable $case_id offscreen]} {
        set offscreen 1
    } else {
        set offscreen 0
    }
    if { $offscreen } {
        set my_offscreen_exe [tester::get_variable $case_id offscreen_exe]
        if { $my_offscreen_exe != "" } {
            if { [file pathtype $my_offscreen_exe] == "relative" } {
                set my_exe_full [file join [file dirname $preferences(exe)] $my_offscreen_exe]
                if { [file exists $my_exe_full] } {
                    set my_offscreen_exe $my_exe_full
                    set my_exe $my_offscreen_exe
                }
            } else {
                set my_exe $my_offscreen_exe
            }
        }        
    }
    if { $my_exe == "" || ![file exists $my_exe] } {
        if { $my_exe == "" } {
            tester::puts_log_error "case $case_id without exe"
        } else {
            tester::puts_log_error "case $case_id exe '$my_exe' doesn't exist"
        }
        tester::set_variable $case_id results [list tini [clock seconds]]
        tester::after_execute_test "" ok $case_id
        tester::message "case $case_id exe '$my_exe' doesn't exist"
        return 1
    }
    
    if { [tester::exists_variable $case_id filetosource] } {
        if { [catch { source [get_full_case_path [tester::get_variable $case_id filetosource]] } err] } {
            tester::set_variable $case_id err $err
        }
    }
    if { [tester::exists_variable $case_id codetosource] } {
        if { [catch {eval [tester::get_variable $case_id codetosource]} err] } {
            tester::set_variable $case_id err $err
        }
    }    
    
    set exe [file join $my_exe]
    if { [string first { } $exe] != -1 } {
        set exe "\"$exe\""
    }
    
    if { $force_with_window } {
        set with_window $force_with_window
    } else {
        if { [tester::exists_variable $case_id with_window] } {
            set with_window [tester::get_variable $case_id with_window]
        } else {
            set with_window 0
        }
    }
    
    if { [tester::exists_variable $case_id with_graphics] } {
        set with_graphics [tester::get_variable $case_id with_graphics]
    } else {
        set with_graphics 0
    }    
    
    #automatically add or remove gid flags
    if { [tester::exists_variable $case_id args] } {
        set args [tester::get_variable $case_id args]
        if { [tester::is_gid_exe $my_exe] } {
            if { $with_window } {
                #try to remove flags " -n" or " -n2" if exists
                foreach flag {-n -n2} {
                    set pos [lsearch $args $flag]
                    if { $pos != -1 } {
                        set args [lreplace $args $pos $pos]
                    }
                }
            }            
            if { [string first " -c " $args] == -1 && [string first " -c2 " $args] == -1 } {
                #if not exists flag -c or -c2 try to set the tester default gidini
                if { [tester::exists_variable $case_id gidini] } {
                    set gidini [get_full_gidini_filename $my_exe [tester::get_variable $case_id gidini]]
                } else {
                    set gidini [get_full_gidini_filename $my_exe [file join scripts gidDefaults]]
                }        
                if { [string first { } $gidini] != -1 } {
                    set gidini "\"$gidini\""
                }                
                append args " -c $gidini"
            }
        }
    } else {
        if { [tester::exists_variable $case_id batch] } {
            set batch [tester::get_variable $case_id batch]
            if { [string first { } $batch] != -1 } {
                set batch "\"$batch\""
            }
            if { $offscreen } {
                # -offscreen flag added at the end ...
                # set args " -offscreen -b"
                set args " -b+g"                
            } else {
                set args " -b"
            }
            if { $with_window || $force_with_window } {
                append args +w
            }
            if { $with_graphics } {
                if { !$offscreen } {
                    #with offscreen already was added +g, avoid repeat it
                    append args +g
                }
            }
            append args " $batch"
            if { $with_window } {
                if { $force_with_window } {
                    #not try minimized
                } else {
                    if { !$with_graphics } {
                        #try to run with windows but minimized                    
                        append args " -n2"
                    }
                }
            } else {
                if { !$with_graphics } {
                    if { !$offscreen } {
                        #with offscreen really it is alternative to -n, must not be used together
                        append args " -n"
                    }
                }
            }
            # Add the -offscreen flag at the end for the correct handling of the batch file arguments in the rest of the tester program
            if { $offscreen  && !$force_with_window} {
                append args " -offscreen"
            }
            if { [tester::exists_variable $case_id gidini] } {
                set gidini [get_full_gidini_filename $my_exe [tester::get_variable $case_id gidini]]
            } else {
                set gidini [tester::get_preferences_key_value gidini]
            }        
            if { [string first { } $gidini] != -1 } {
                set gidini "\"$gidini\""
            }                
            append args " -c $gidini"
        } else {
            set args ""
        }
    }

    if { [llength $args] > 1 && [regexp -nocase {:?^-b([+-]?[giw]?){0,3}$} [lindex $args 0]] && [tester::is_gid_exe $my_exe]} {
        set full_path_batch [get_full_case_path [lindex $args 1]]
        if { ![file exists $full_path_batch] } {
            tester::puts_log_error "batch file '[lindex $args 1]' doesn't exists"            
            tester::array_unset $case_id outfile
            set outfile  ""
            tester::message [_ "Batch file '%s' doesn't exists" [lindex $args 1]]  
        } else {
            #assumed that it's a GiD batch file
            #create a temporary batchfile, adding a monitoring line, and ending with a quit line if necessary
            if { ![tester::exists_variable $case_id readingproc] } {
                tester::set_variable $case_id readingproc read_gid_monitoring_info
            }
            tester::set_variable $case_id filestodelete ""        
            set all [tester::read_file [get_full_case_path [lindex $args 1]]]   
            set all [subst -novariables $all]  ;#to allow replacing [] procedures 
            if { ![tester::exists_variable $case_id outfile] } {
                set outfile [tester::get_tmp_filename .out $case_id] 
                tester::set_variable $case_id outfile $outfile
            } else {
                set outfile [get_full_case_path [tester::get_variable $case_id outfile]]
            }
            tester::lappend_variable $case_id filestodelete $outfile
            set monitoring "*****tcl package require gid_monitoring\n"
            set check_variables [tester::get_check_variables $case_id]
            append monitoring "*****tcl gid_monitoring::set_request [list $check_variables]\n"
            set expr_procedures [tester::get_expr_procedures $case_id]
            if { [llength $expr_procedures] } {
                append monitoring "*****tcl gid_monitoring::set_expr_procedures [list $expr_procedures]\n"
            }
            append monitoring "*****tcl gid_monitoring::saveinfo [list $outfile]\n"            
            set all [split [string trim $all] \n]
            if { [lsearch [string tolower [lindex $all end]] quit] != -1 } {
                set all [linsert $all end-1 $monitoring]
                if { $force_with_window == 1 } {
                    set all [lrange $all 0 end-1]
                }
            } else {
                if { $force_with_window == 1 } {
                    lappend all $monitoring
                } else {
                    lappend all $monitoring {Mescape Quit No}
                }
            }
            set all [join $all \n]
            set tmpbatchfile [tester::get_tmp_filename .bch $case_id]
            set fp [open $tmpbatchfile w]
            puts $fp $all
            close $fp
            tester::lappend_variable $case_id filestodelete $tmpbatchfile
            if { [string first { } $tmpbatchfile] != -1 } {
                set tmpbatchfile "\"$tmpbatchfile\""
            }
            lset args 1 $tmpbatchfile
        }        
    } else {
        # outfile needs to be defined !!!
    }
    
    if { [lsearch $args {$outfile}] != -1 } {
        if { [tester::exists_variable $case_id outfile] } {
            if { [tester::get_variable $case_id outfile] != "stdout" } {
                set outfile [get_full_case_path [tester::get_variable $case_id outfile]]
            } else {
                set outfile [tester::get_variable $case_id outfile]
            }
        } else {
            set outfile [tester::get_tmp_filename .out $case_id]
        }
        if { $outfile != "stdout" && $outfile != "" } {
            tester::lappend_variable $case_id filestodelete $outfile
        }
        if { [string first { } $outfile] != 1 } {
            set outfile "\"$outfile\""
        }
        regsub -all -- {\$outfile} $args $outfile args
    }           
    
    if { [file exists $outfile] && $outfile != "stdout" } {
        #delete old output if any before recalculate
        if { [catch {file delete $outfile} err] } {
            tester::puts_log_error "case $case_id process id=$case_id couldn't delete old file=$outfile, err=$err"
        }
    }
    
    set cmd "$exe $args"
    if { $run_option != ""} {
        switch $run_option {
            "valgrind debug (xml)" {
                # add an output file to store the output
                set output_valgrind_filename [ tester::valgrind_get_output_filename $case_id xml]
                set cmd "$exe -valgrind -xml $output_valgrind_filename $args"
            }
            "valgrind debug (txt)" {
                # add an output file to store the output
                set output_valgrind_filename [ tester::valgrind_get_output_filename $case_id txt]
                set cmd "$exe -valgrind -txt $output_valgrind_filename $args"
            }
            "valgrind release (xml)" {
                # add an output file to store the output
                set output_valgrind_filename [ tester::valgrind_get_output_filename $case_id xml]
                set cmd "$exe -valgrind_release -xml $output_valgrind_filename $args"
            }
            "valgrind release (txt)" {
                # add an output file to store the output
                set output_valgrind_filename [ tester::valgrind_get_output_filename $case_id txt]
                set cmd "$exe -valgrind_release -txt $output_valgrind_filename $args"
            }
            "sanitize (txt)" {
                # add an output file to store the output
                set output_sanitize_filename [ tester::sanitize_get_output_filename $case_id]
                set cmd "$exe -sanitize $output_sanitize_filename $args"
            }
            default {
                set cmd "$exe -$run_option $args"
            }
        }
    }
    if { $force_with_window == 1 } {
        set timeout 0
        set maxmemory 0
    } else {   
        if { [tester::exists_variable $case_id timeout] } {
            set timeout [tester::get_variable $case_id timeout]
        } else {
            set timeout 0         
        }
        if { [tester::exists_variable $case_id maxmemory] } {
            set maxmemory_mb [tester::get_variable $case_id maxmemory]
        } else {
            set maxmemory_mb $preferences(maxmemory)
        }
        set maxmemory [expr $maxmemory_mb*1024*1024];#Bytes            
    }    
        
    if { [tester::exists_variable $case_id outfile] && [tester::get_variable $case_id outfile] == "stdout" } {
        #with stdout redirect console output to a file
        set stdout_filename [tester::get_tmp_filename .stdout $case_id] 
        if { [file exists $stdout_filename] } {
            #delete old output if any before recalculate
            if { [catch {file delete$stdout_filename} err] } {
                tester::puts_log_error "case $case_id process id=$case_id couldn't delete old file=$stdout_filename, err=$err"
            }
        }
        tester::lappend_variable $case_id filestodelete $stdout_filename
        variable stdoutput_$case_id ;#store auxiliary name to redirect stdout
        set stdoutput_$case_id $stdout_filename
        if { [string first { } $stdout_filename] != 1 } {
            set stdout_filename "\"$stdout_filename\""
        }
        set cmd "$cmd > $stdout_filename"
    }
    puts "cmd -> $cmd"

    #tester::trace_preferences_path ;#to force to set env(PATH)
    set t0 [clock seconds]
    set pid [exec {*}$cmd &]
    incr nprocess
    lappend case_ids_running $case_id
    #in case of a bat pid->cmd.exe and has two child processes: conhost.exe and gid*.exe    
    tester::set_variable $case_id pid $pid
    tester::set_variable $case_id results [list tini $t0]
    gid_cross_platform::track_process $pid 500 $t0 $timeout $maxmemory [list tester::after_execute_test $case_id] ""
    return 0
}

proc tester::after_execute_test { pid status case_id } {
    variable nprocess
    variable case_ids_running
    variable progress
    variable maxprogress       
    set tend [clock seconds]

    tester::array_unset $case_id pid
    set tini [lindex [tester::get_variable $case_id results] 1]
    tester::lappend_variable $case_id results time [expr $tend-$tini]   
    set crashed_or_killed ""
    if { $status == "timeout" } {
        set crashed_or_killed "timeout"
    } elseif { $status == "maxmemory" } {
        set crashed_or_killed "maxmemory"
    } elseif { $status == "userstop" } {
        set crashed_or_killed "userstop"
    } elseif { $status == "crash" } {
        set crashed_or_killed "crash"
    } else {
        if { [tester::exists_variable $case_id readingproc] && [info procs [lindex [tester::get_variable $case_id readingproc] 0]] != "" } {
            if {[tester::exists_variable $case_id outfile]} {
                set outfile [tester::get_variable $case_id outfile]
            } else {
                set outfile ""
            }
            if { $outfile == "stdout" } {
                variable stdoutput_$case_id
                set outfile [set stdoutput_$case_id]
            }
            if {![info exists ::wait_time]} {set ::wait_time 1000}
            after $::wait_time
            puts "$::wait_time $outfile [file exists $outfile]"
            if { [file exists $outfile] } {
                tester::set_variable $case_id results [concat [tester::get_variable $case_id results] [{*}[tester::get_variable $case_id readingproc] $outfile]]                 
            } else {
                #case crashed or killed
                if { $status == "timeout" } {
                    set crashed_or_killed "timeout"
                } elseif { $status == "maxmemory" } {
                    set crashed_or_killed "maxmemory"
                } elseif { $status == "userstop" } {
                    set crashed_or_killed "userstop"
                } else {
                    set crashed_or_killed "crash"
                }
            }
        }
    }
    tester::do_checks $case_id $crashed_or_killed
    tester::puts_log_case $case_id
    tester::set_digest_results $case_id
    tester::fill_results_to_tree $case_id
    tester::fill_checks_to_tree $case_id
    
    if { [tester::exists_variable $case_id filestodelete] } {
        #tester::message "files to delete = [tester::get_variable $case_id filestodelete]"
        foreach filename [tester::get_variable $case_id filestodelete] {
            continue
            if { [catch {file delete $filename} err] } {
                tester::puts_log_error "case $case_id process id=$case_id couldn't delete file=$filename, err=$err"
                #         # try to kill processes that lock this file
                #         foreach case_id [gid_cross_platform::get_process_ids_from_name dwwin.exe] {
                #             set parent [gid_cross_platform::get_process_parent $case_id]
                #             if { ![gid_cross_platform::process_exists $parent] } {
                #                 catch {gid_cross_platform::end_process $case_id} err
                #             } elseif { [gid_cross_platform::get_process_name $parent] == "gid.exe" } {
                #                 catch {gid_cross_platform::end_process $case_id} err
                #             }
                #         }
                #         if { [catch {file delete $filename} err] } {
                #             tester::puts_log_error "case $case_id process id=$case_id couldn't delete file=$filename, err=$err"
                #         }
            }
        }
        tester::set_variable $case_id filestodelete ""
    }
    incr progress            

    set idx [lsearch $case_ids_running $case_id]
    set case_ids_running [lreplace $case_ids_running $idx $idx] 
    incr nprocess -1
    
    update
       
    tester::private_event_after_run_case $case_id
}


####################################################
##################### GUI ##########################
####################################################


#common dialogs

#icon:  error, info, question or warning
proc tester::message_box { text {icon warning} {parent .} } {
    variable private_options
    if { !$private_options(gui) } {
        return
    }
    if { $parent != "" && [winfo exists $parent] } {
        tk_messageBox -message $text -parent $parent -title Warning -icon $icon -type ok
    } else {
        tk_messageBox -message $text -title Warning -icon $icon -type ok
    }
}

proc tester::message { text  } {
    variable private_options
    if { !$private_options(gui) } {
        return
    }
    set w .warning
    
    if { ![winfo exists $w] } {        
        toplevel $w
        wm transient $w [winfo toplevel [winfo parent $w]]
        if { $::tcl_platform(platform) == "windows" } {
            wm attributes $w -toolwindow 1
        }
        wm title $w [_ "Warning"]
        
        #text with scrolls only if required
        ttk::frame $w.fr
        ttk::scrollbar $w.fr.scrolly -command [list $w.fr.t yview] -orient vertical
        ttk::scrollbar $w.fr.scrollx -command [list $w.fr.t xview] -orient horizontal
        text $w.fr.t -yscrollcommand [list $w.fr.scrolly set] \
            -xscrollcommand [list $w.fr.scrollx set] -wrap none
        if { [lsearch [font names] SmallFont] != -1} {
            $w.fr.t configure -font SmallFont 
        }
        
        grid $w.fr.t -row 1 -column 1 -sticky nsew
        grid $w.fr.scrolly -row 1 -column 2 -sticky ns
        grid $w.fr.scrollx -row 2 -column 1 -sticky ew
        grid rowconfigure $w.fr 1 -weight 1
        grid columnconfigure $w.fr 1 -weight 1
        grid $w.fr -sticky nsew -padx 5 -pady 5
        
        grid remove $w.fr.scrolly
        grid remove $w.fr.scrollx
        bind $w.fr.t <Configure> [list tester::configure_scrollbars $w.fr.t $w.fr.scrollx $w.fr.scrolly]
        
        #lower buttons
        ttk::frame $w.frmButtons -style BottomFrame.TFrame
        ttk::button $w.frmButtons.btnclose -text [_ "Close"] -command [list destroy $w] -underline 0
        
        grid $w.frmButtons -sticky ews -columnspan 7
        grid anchor $w.frmButtons center
        grid $w.frmButtons.btnclose -padx 5 -pady 6
        grid columnconfigure $w 0 -weight 1
        grid rowconfigure $w 0 -weight 1
        
        focus $w.frmButtons.btnclose
        bind $w <Alt-c> [list $w.frmButtons.btnclose invoke]
        bind $w <Escape> [list $w.frmButtons.btnclose invoke]
    }
    
    $w.fr.t insert end $text\n
    $w.fr.t see end
    tester::configure_scrollbars $w.fr.t $w.fr.scrollx $w.fr.scrolly
    update
}

#auxiliary common procedure, used to automatically add/remove scrollbars when needed
#widget must be a list, treectrl, text or cavas widget with xview/yview command and sx,sy scrollbar widgets
proc tester::configure_scrollbars { widget sx sy } {
    foreach i "x y" {
        if { ![info exists s${i}] || ![winfo exists [set s${i}]] } { continue }
        foreach "${i}1 ${i}2" [$widget ${i}view] break
        if { [set ${i}1] == 0 && [set ${i}2] == 1 } {
            after idle grid remove [set s${i}]
        } else {
            after idle grid [set s${i}]
        }
    }
}



#show help manuals in lognoter format
proc tester::open_lognoter_external { dbfile } {
    variable private_options   
    set exe [file join $private_options(program_path) Lognoter Lognoter.exe]
    set lan [tester::get_current_language]
    exec $exe -readprefs 0 -readonly 1 -language $lan -manageicontray 0 -title [_ "Help viewer"] -saveprefs 0 -notebookname $dbfile   
}

proc tester::open_lognoter { dbfile {open_page ""} {select_in_tree ""} {key ""}} {       
    set execute_commands ""
    if { $open_page ne "" } {
        append execute_commands ";[list showpage $open_page]"
    }
    if { $select_in_tree ne "" } {
        append execute_commands ";[list toctree_process expand_page $select_in_tree]"
        append execute_commands ";[list toctree_process select_in_tree [list $select_in_tree]]"
    }   
    
    set lan [tester::get_current_language]
    
    set argv [list -readprefs 0 -readonly 1 -language $lan \
            -manageicontray 0 -prefs_data \
            [list view_languages_toolbar 0 add_more_pages_to_tree 0 \
                view_main_menu 0 geometry_default {{} 940x700 {tree 200}}] \
            -hide_on_exit 0 -execute_commands $execute_commands \
            -title [_ "Help viewer"] -saveprefs 0 \
            -dbtype sqlite -notebookname $dbfile -key $key]
    
    if { ![interp exists lognoter_intp] } {
        interp create lognoter_intp
        lognoter_intp eval lappend auto_path $::auto_path
        #lognoter_intp eval [list set auto_path $::auto_path]
        lognoter_intp eval [list set argv [list -language $lan]]
        #lognoter_intp eval [list set ::GIDDEFAULT $::GIDDEFAULT]
    }        
    
    package require Lognoter
    
    #interp alias lognoter_intp exit "" return
    #lappend argv -external_master_callback eval_master
    
    # necessary to avoid loading different versions in main interp and slave interp
    #lognoter_intp eval [list package require -exact treectrl [package require treectrl]]
    
    set r [lognoter_intp eval lognoter .%AUTO% $argv]    
    #interp alias lognoter_intp eval_master "" gid_groups_conds::_report_data_from_lognoter_cmd
    if { 0 } {
        #not exit if opened from tester
        interp alias lognoter_intp exit {} exit ;#else not exit or exit raise an error when closing lognoter       
    } else {
        if { $::tcl_platform(os) == "Darwin"} {
            # if tester exists, if lognoter exists, do not exit from tester
            proc ::DoNothing  {} {}
            interp alias lognoter_intp exit {} ::DoNothing
        }
    }
}

proc tester::help { } {
    variable private_options
    set language [tester::get_current_language]
    set full_filename [file join $private_options(program_path) doc $language tester.wnl]   
    set w .
    tester::wait_state
    #tester::open_lognoter $full_filename
    tester::open_lognoter_external $full_filename
    tester::end_wait_state
}

#show the 'short helps' of selected cases
proc tester::help_selection { } {
    set text ""
    set case_ids [tester::tree_get_selection_case_ids]
    foreach case_id $case_ids {
        if { [tester::exists_variable $case_id help] } {
            if { [tester::exists_variable $case_id name] } {
                append text "[tester::get_variable $case_id name] [tester::get_variable $case_id help]\n"
            } else {
                append text "$case_id [tester::get_variable $case_id help]\n"
            }
        }
    }
    if { $text != "" } {
        tester::message $text
    }
}

#notepad-like edit tool of ASCII files
#facilitate the edition of the batch of selected cases
proc tester::edit_batchfile_selection { } {   
    set case_ids [tester::tree_get_selection_case_ids]    
    tester::edit_files $case_ids batch
}

#facilitate the edition of the xml (where was defined) of selected cases
proc tester::edit_xmlfile_selection { } {
    set case_ids [tester::tree_get_selection_case_ids]   
    tester::edit_files $case_ids xml
}

#to edit a selection of batch or xml of multiple selected cases
#type: batch xml
proc tester::edit_files { case_ids type } {
    if { $type != "batch" && $type != "xml" } {
        tester::message_box [_ "bad type %s, must be batch or xml" $type] error
    }
    set filenames [list]
    foreach case_id $case_ids {
        if { [tester::exists_variable $case_id $type] } {
            set filename [tester::get_variable $case_id $type]
            set full_filename [tester::get_full_case_path $filename]
            if { [lsearch -exact $filenames $full_filename] == -1 } {
                lappend filenames $full_filename
            }
        }        
    }
    foreach filename $filenames {
        tester::edit_file $filename
    }
}

#to edit a selection of filenames
proc tester::edit_file { filename } {
    if { ![info exists filename] } {
        tester::message_box [_ "file %s does not exist" $filename] error
    } else {        
        package require texteditor
        set hidenewandopen 1            
        set search_line 0
        set search_text ""
        if { 0 } {
            #get an unused window name
            set base_name .texteditor
            for {set count 1} {$count < 1000} {incr count} {
                set w $base_name-$count
                if { ![winfo exists $w] } {
                    break
                }            
            }
        } else {
            #use a single name, because texteditor 1.0 is not implemented for multiple instances!!
            set w .texteditor
        }
        TextEditor::Create $filename $search_line $search_text $hidenewandopen $w
    }
}


#show in tabs the graphs analizing the tests of a selected case along the time, reading the logs


proc tester::close_tab { nb tab_id } {
    #event generate $nb <<NotebookTabClosed>>
    set tab_index [$nb index $tab_id]
    if { $tab_index == 0 } {
        tester::message_box [_ "The first tab with the table must not be deleted"] warning
    } else {
        $nb forget $tab_index
        destroy $tab_id
    }
}

#trick to show a X button to close a tab
proc tester::on_button_press_1_notebook { nb x y } {
    set tab_index [$nb identify tab $x $y]
    if { $tab_index != "" && $tab_index > 0 } {
        #don't delete the first tab with the cases
        set element_id [$nb identify $x $y ] 
        if { $element_id == "image" } {
            set tab_id [lindex [$nb tabs] $tab_index]
            tester::close_tab $nb $tab_id
        }
    }
}

proc tester::show_graphs_analisis_selection { } {
    set case_ids [tester::tree_get_selection_case_ids]   
    tester::analize_log $case_ids
    foreach case_id $case_ids {
        tester::show_graph_analysis $case_id
    }
}

proc tester::analize_log { case_ids_original } {    
    variable private_options   
    variable graph
    variable cancel_process
    variable pause_process
    variable progress
    variable maxprogress
    variable last_analysis ;#cache    
    
    set dir [file join $private_options(project_path) logfiles]
    set file_and_time [list]
    foreach filename [glob -nocomplain -dir $dir *.log] {
        lappend file_and_time [list $filename [file mtime $filename]]
    }
    set file_and_time_sorted [lsort -integer -index 1 $file_and_time]
    
    if { [info exists last_analysis(file_and_time_sorted)] && $last_analysis(file_and_time_sorted)==$file_and_time_sorted } {        
        set case_ids [list]
        foreach case_id $case_ids_original {
            if { ![info exists graph($case_id,xs)] } {
                lappend case_ids $case_id
            }
        }        
    } else {
        set case_ids $case_ids_original
    }
    if { ![llength $case_ids] } {
        #unneded, already done   
        return 0
    }
    set case_ids [lsort $case_ids]
        
    set filenames [list]
    foreach item $file_and_time_sorted {
        lappend filenames [lindex $item 0]
    }
    
    foreach case_id $case_ids {
        array unset graph $case_id,*
    }
    
    tester::gui_enable_pause
    set maxprogress [llength $filenames]
    set update_each 10
    set progress 0
    foreach filename $filenames {
        if { $::tester::pause_process } {
            vwait ::tester::pause_process
        }
        if { $cancel_process } {
            tester::set_message [_ "User stopped analizing logs in file %s." $filename]
            break
        }
        set data [tester::read_file $filename]
        foreach line [split $data \n] {
            set line_case_id [lindex $line 2]
            if { [lsearch -sorted $case_ids $line_case_id] != -1 } {
                lassign $line log_time log_date case_id result_code results                
                set test_date [tester::unformat_date "$log_time $log_date"]
                lappend graph($case_id,xs) $test_date
                lappend graph($case_id,ys_fail) $result_code ;#graph with number, not string
                if { $result_code == 0 } { 
                    #ok result_code
                    array set case_results $results
                    #lappend graph($case_id,xs) $case_results(tini)
                    lappend graph($case_id,ys_time) $case_results(time)
                    if { [info exists case_results(workingset)] } {
                        lappend graph($case_id,ys_memory) [tester::format_memory $case_results(workingset)]
                        lappend graph($case_id,ys_memory_peak) [tester::format_memory $case_results(workingsetpeak)]
                    } else {
                        #memory used by test not available
                    }
                } else {
                    #untested fail crash timeout maxmemory userstop
                    lappend graph($case_id,ys_time) 0
                    lappend graph($case_id,ys_memory) 0
                    lappend graph($case_id,ys_memory_peak) 0
                }
            }            
        }
        incr progress
        if { ![expr {$progress%$update_each}] } {
            update
        }
    }    
    set last_analysis(file_and_time_sorted) $file_and_time_sorted
    tester::gui_enable_play
    return 0
}

proc tester::all_graph_values_are_ok { ys } {
    set all_ok 1
    foreach y $ys {
        if { $y } {
            set all_ok 0
            break
        }
    }
    return $all_ok
}

proc tester::show_graph_analysis { case_id } {    
    variable graph    
    if { ![info exists graph($case_id,xs)]} {
        tester::message [_ "Case %s. History logs not found" $case_id]
    } else {
        if { [llength $graph($case_id,xs)] < 2 } {
            tester::set_message [_ "Not enough history logs to show a graph for the case %s." $case_id]
        } else {       
            set results_to_plot {time memory fail}
            foreach result $results_to_plot {
                if { $result == "fail" && [tester::all_graph_values_are_ok $graph($case_id,ys_fail)] } {
                    #if all are ok along the history does not show this graph
                    continue
                }
                set nb .fcenter.nb
                set f $nb.graph_${case_id}_${result}
                if { [winfo exists $f] } {
                    destroy $f
                }
                ttk::frame $f
                $nb add $f -text [_ "Case %s" $case_id] -image [tester::get_image close.png] -compound right        
                tester::create_graph $f $case_id $result
                set tab_id [lindex [$nb tabs] end]
                $nb select $tab_id
            }
        }
    }
}

#use only the last 25 tests (if it was random in the past doesn't matter to be considered as random now)
proc tester::num_changes { serie } {
    set num_changes 0
    set item_previous [lindex $serie 0]
    foreach item [lrange $serie 1 end] {
        if { $item != $item_previous } {
            incr num_changes
            set item_previous $item 
        }
    }
    return $num_changes
}

#check number of changes of latest 25 (or less) values
#if latest 10 items are constant doesn't consider it as now random
proc tester::clasify_now_random { case_id serie } {
    set is_random 0
    set serie_latests [lrange $serie end-24 end]
    set num_latests [llength $serie_latests]
    if { $num_latests >= 10 } {
        set num_changes [tester::num_changes $serie_latests]
        set factor_changes [expr double($num_changes)/$num_latests]
        if { $factor_changes >= 0.25 } {
            if { [tester::num_changes [lrange $serie_latests end-9 end]] > 1 } {
                set is_random 1
            }
        }
    }  
    #if { $is_random } {  
    #    tester::message "factor_changes=$factor_changes ($num_changes/$num_latests) case_id=$case_id"
    #}
    return $is_random
}

proc tester::classify_random_log_selection { } {    
    set case_ids [tester::tree_get_selection_case_ids]   
    tester::analize_log $case_ids
    set num_random 0
    foreach case_id $case_ids {
        incr num_random [tester::classify_random_log $case_id]
    }
    tester::set_message [_ "Classified as random %s of %s cases" $num_random [llength $case_ids]]
}

#consider random if last 25 tests has standard deviation > 0.5 and last 10 cases are not constant
proc tester::classify_random_log { case_id } {
    variable graph
    set num_random 0
    set num_tests 0
    if { [info exists graph($case_id,ys_fail)] } {
        set num_tests [llength $graph($case_id,ys_fail)]
    }            
    if { $num_tests >= 10 } {
        set is_random [tester::clasify_now_random $case_id $graph($case_id,ys_fail)]
        tester::set_case_definition_field $case_id fail_random $is_random
        if { $is_random } {
            incr num_random
        }
    } else {
        #tester::message "tester::classify_random. Doesn't exists enougth test done ($num_tests) to classify case $case_id as random"
    }
    return $num_random
}

proc tester::clipboard_copy_graph { case_id result } {
    set data_list [list "case $case_id"]
    lappend data_list [join [list date $result] \t]    
    lassign [tester::get_graph_data_range $case_id $result] xs ys x_scale y_scale
    foreach x $xs y $ys {
        set line_list [list $x $y]
        lappend data_list [join $line_list \t]
    }    
    clipboard clear
    clipboard append [join $data_list \n]   
}

proc tester::get_min_max { ys } {
    set y_min [lindex $ys 0]
    set y_max $y_min
    foreach y $ys {
        if { $y_min > $y } {
            set y_min $y
        }
        if { $y_max < $y } {
            set y_max $y
        }
    }
    return [list $y_min $y_max]
}

#xs ordered increasing list. return the index of range between x_min and x_max
proc tester::get_range_pos { xs x_min x_max } {
    set pos_ini 0
    set pos_end [expr [llength $xs]-1]
    if { $x_min != "" } {
        while { [lindex $xs $pos_ini]<$x_min && $pos_ini<$pos_end } {
            incr pos_ini
        }
    }
    if { $x_max != "" } {
        while { [lindex $xs $pos_end]>$x_max && $pos_end>$pos_ini } {
            incr pos_end -1
        }
    }
    return [list $pos_ini $pos_end]
}

proc tester::get_graph_data_range { case_id result } { 
    variable preferences
    variable graph
        
    set xs $graph($case_id,xs)
    set ys $graph($case_id,ys_$result)    
    
    set timeformat {%d-%m-%Y}
    set graph_range 0
    set date_min ""
    if { $preferences(graphs_date_min) } {
        #set date_min [tester::unformat_date $preferences(graphs_date_min_value)]
        set date_min [clock scan $preferences(graphs_date_min_value) -format $timeformat]
        set graph_range 1
    }
    set date_max ""
    if { $preferences(graphs_date_max) } {
        #set date_max [tester::unformat_date $preferences(graphs_date_max_value)]
        set date_max [clock scan $preferences(graphs_date_max_value) -format $timeformat]
        set graph_range 1
    }
    if { $graph_range } {
        lassign [tester::get_range_pos $xs $date_min $date_max] pos_ini pos_end
        set xs [lrange $xs $pos_ini $pos_end]
        set ys [lrange $ys $pos_ini $pos_end]
    }
    
    # calculate also scales
    if { $date_min!= "" } {
        set x_min $date_min
    } else {
        set x_min [lindex $xs 0]
    }
    if { $date_max!= "" } {
        set x_max $date_max
    } else {
        set x_max [lindex $xs end]
    }
    set x_increment [expr {int(($x_max-$x_min)/10.0)}]
    
    lassign [tester::get_min_max $ys] y_min y_max
    if { $y_min>0 } {
        #to start y from 0 in our graphs
        set y_min 0
    }
    set y_increment [expr {($y_max-$y_min)/10.0}]
    if { $y_increment <1e-10 } {
        set y_increment 1.0
    }
    set y_max [expr $y_max+$y_increment] 
    set x_scale [list $x_min $x_max $x_increment]
    set y_scale [list $y_min $y_max $y_increment]
    
    return [list $xs $ys $x_scale $y_scale]
}

proc tester::create_graph { w case_id result } { 
    variable preferences
    variable graph

    if { ![info exists graph($case_id,xs)] } {
        return 1
    }   
    lassign [tester::get_graph_data_range $case_id $result] xs ys x_scale y_scale
    
    if { [llength $xs] < 2 } {
        return 1
    }   
    
    package require Plotchart
    
    #Plotchart::plotstyle load default
    foreach margin {top bottom left right} size { 50 50 100 50 } {
        ::Plotchart::plotconfig xyplot margin $margin $size
    } 
    
    canvas $w.c
    $w.c configure -background [Plotchart::plotconfig xyplot background innercolor]
    set text_colour black    
           
    set graph($case_id,$result,plot) [Plotchart::createXYPlot $w.c $x_scale $y_scale -timeformat {%d-%m-%Y}]
    tester::configure_graph $graph($case_id,$result,plot) $w.c $case_id $result
    grid $w.c -sticky nsew
    grid rowconfigure $w 0 -weight 1
    grid columnconfigure $w 0 -weight 1    
    set serie time
    #$graph($case_id,$result,plot) plotlist $serie $xs $ys 1
    foreach x $xs y $ys {
        $graph($case_id,$result,plot) plot $serie $x $y
        $graph($case_id,$result,plot) bindlast $serie <Enter> [list tester::graph_show_annotation $graph($case_id,$result,plot) %W]
    }
    
    bind $w.c <Configure> [list +tester::on_resize_graph $w.c $case_id $result]        
    bind $w.c <ButtonPress-$::tester_right_button> [list +tester::show_menu_graph %W %x %y $case_id $result]
    return 0
}

proc tester::show_menu_graph { w x y case_id result } {
    set m .menu_contextual    
    if { [winfo exists $m] } {
        destroy $m
    }
    menu $m -tearoff no
    $m add command -label [_ "Copy"] -command [list tester::clipboard_copy_graph $case_id $result]
    set xx [expr [winfo rootx $w]+$x+50]
    set yy [expr [winfo rooty $w]+$y]    
    tk_popup $m $xx $yy 0
}

proc tester::show_menu_tab { nb x y } {
    set tab_id [$nb identify tab $x $y]
    if { $tab_id == "" } {
        return
    }    
    set tab_index [$nb index $tab_id]    
    if { $tab_index == 0 } {
        #The first tab with the table must not be deleted, dont show any menu only with this unwanted option
    } else {
        set m .menu_contextual    
        if { [winfo exists $m] } {
            destroy $m
        }
        menu $m -tearoff no    
        
        $m add command -label [_ "Close tab"] -command [list tester::close_tab $nb $tab_id]
        set xx [expr [winfo rootx $nb]+$x+50]
        set yy [expr [winfo rooty $nb]+$y]    
        tk_popup $m $xx $yy 0
    }
}

proc tester::graph_show_annotation { xcoord ycoord plot w } {
    tester::graph_remove_annotation $w
    set date [clock format [expr int($xcoord)] -format {%d-%m-%Y}]
    set value [format "%.2f" $ycoord]
    $plot balloon $xcoord $ycoord "$date $value" north
    after 2000 [list tester::graph_remove_annotation $w]
}

proc tester::graph_remove_annotation {w} {
    # Use the tags to remove all annotations
    if { [winfo exists $w] } {
        $w delete BalloonText
        $w delete BalloonFrame
    }
}

proc tester::configure_graph { g c case_id result } {     
    if { ![ winfo exists $c]} {
        return
    }
    set serie time
    set text_colour black
    set mem_colour #007f7f
    set legend_bg [$c cget -background]    
    $g xtext [_ "Date"]   
    $g dataconfig $serie -color red -type both -symbol dot
    #-symbol cross
    $g dataconfig memory -color $mem_colour
    $g xticklines
    $g yticklines
    $g background plot gray95
    #$g legendconfig -position bottom-right
    #$g legendconfig -background $legend_bg
    #$g legendconfig -border $text_colour
    #$g legend $seri [concat [_ "Time"] " " [_ "seconds"]
    #$g legend memory [concat [_ "Memory"] " "  MB]
    
    # a little bit nasty to access internal variables of Plotchart config,
    # but there is no other way until we get Plotchart 2.2.0 where we can do something like this:
    # Plotchart::plotconfig xyplot textcolor $text_colour
    # Plotchart adds a prefix in its objects withthe type of graph, underscore, a number and the canvas name
    # following the ::Plotchart::GetCanvas which does
    # regsub {^[^_]+_%} $cmd "" w
    # return $w ( w = canvas name)
    
    #set w_plotchart --
    #if { [ regexp {^[^_]+_(\d+.*)$} $g dum w_plotchart] == 1} {
    #    set ::Plotchart::config($w_plotchart,title,textcolor) $text_colour
    #}
    $g title [concat [_ "Test evolution"] $case_id $result] center
    # configure color of text and add vertical axis info:
    if { $result == "time" } {
        $c create text 100 10 -text [concat [_ "Time"] " " [_ "seconds"]] -anchor e -justify right -fill $mem_colour
    } elseif { $result == "memory" } {
        $c create text 100 24 -text [ concat [_ "Memory"] " " MB] -anchor e -justify right -fill $mem_colour
    } elseif { $result == "memory_peak" } {
        $c create text 100 24 -text [ concat [_ "Memory peak"] " " MB] -anchor e -justify right -fill $mem_colour
    } elseif { $result == "fail" } {
        $c create text 100 24 -text [ concat [_ "Fail"] " " ""] -anchor e -justify right -fill $mem_colour
    } else {
        $c create text 100 10 -text [concat [_ $result] " " ""] -anchor e -justify right -fill red
    }
    $c itemconfigure legend_$result -fill $text_colour
}

proc tester::on_resize_graph { c case_id result } { 
    # To avoid redrawing the plot many times during resizing,
    # cancel the callback, until the last one is left.    
    variable graph
    if { [info exists graph($case_id,$result,resizing)] } {
        after cancel $graph($case_id,$result,resizing)
    }
    set graph($case_id,$result,resizing) [after 50 [list tester::resize_graph $c $case_id $result]]
}

proc tester::resize_graph { c case_id result } {             
    variable graph    
    if { [catch { lassign [tester::get_graph_data_range $case_id $result] xs ys x_scale y_scale } msg] } {
        #e.g. wrong date  min or max format
        return 1
    }
    
    #deletedata also does a $graph($case_id,$result,plot) delete data
    if { [catch { $graph($case_id,$result,plot) deletedata } err] } {
        # WarnWinText "ProgressInMeshing::DoResize $err"
    }
    if { [winfo exists $c] } {           
        $c delete all        
        set graph($case_id,$result,plot) [Plotchart::createXYPlot $c $x_scale $y_scale -timeformat {%d-%m-%Y}]
        tester::configure_graph $graph($case_id,$result,plot) $c $case_id $result            
        if { [llength $xs] >= 2 } {
            set serie time
            #$graph($case_id,$result,plot) plotlist $serie $xs $ys 1
            foreach x $xs y $ys {
                $graph($case_id,$result,plot) plot $serie $x $y
                $graph($case_id,$result,plot) bindlast $serie <Enter> [list tester::graph_show_annotation $graph($case_id,$result,plot) %W]
            }
        }
        #if { [catch { set graph($case_id,$result,plot) [Plotchart::createXYPlot $c $x_scale $y_scale -timeformat {%d-%m-%Y}] } err] } {
            #catch because Plotchat package 2.0.1 can raise error if canvas is deleted while evaluating Plotchart::createXYPlot                
        #} else {
            
        #}
    }         
    unset -nocomplain graph($case_id,$result,resizing)
    return 0
}

proc tester::update_range_graphs { } {
    variable graph
    foreach item [array names graph *,plot] {
        lassign [split $item ,] case_id result
        #set c [$graph($item) canvas]
        set c .fcenter.nb.graph_${case_id}_${result}.c
        if { [winfo exists $c] } {            
            tester::resize_graph $c $case_id $result
        }        
    }
    
}

proc tester::analize_cause_fail_selection { } {
    set case_ids [tester::tree_get_selection_case_ids] 
    foreach case_id $case_ids {
        set msg [tester::analize_cause_fail $case_id]
        if { $msg != "" } {
            tester::message $msg
        }
    }
}

proc tester::analize_cause_fail { case_id } {
    set is_random 0
    if { [tester::exists_variable $case_id fail_random] } {
        set is_random [tester::get_variable $case_id fail_random]
    }     
    if { $is_random } {
        set msg [_ "Case %s is classified as random, doesn't has sense to find the cause of the fail in the code history." $case_id]
    } else {
        #set msg [tester::analize_cause_fail_cvs $case_id]
        set msg [tester::analize_cause_fail_git $case_id]
    }
    return $msg
}

proc tester::analize_cause_fail_cvs { case_id } {
    variable preferences    
    set msg ""
    set last_fail [tester::digest_results_get_fail $case_id]   
    if { $last_fail == "" } {
        set msg [_ "Case %s not run." $case_id]    
    } elseif { $last_fail == 0 } {     
        set msg [_ "Case %s is ok." $case_id]    
    } elseif { $last_fail == 1 || $last_fail == "timeout" || $last_fail == "maxmemory" || $last_fail == "userstop" || $last_fail == "crash" } {     
        #set fail_date [tester::digest_results_get_date $case_id]
        set fail_date [clock seconds] ;#now
        set ok_date [tester::digest_results_get_ok_date $case_id]
        if { $ok_date == "" } {
            set msg [_ "Not found any test passed for the case %s." $case_id]
        } else {
            set msg [_ "Case %s failed between %s and %s." $case_id [tester::format_date $ok_date] [tester::format_date $fail_date]]
            append msg "\n[join [concat [tester::get_variable $case_id tags] [tester::get_variable $case_id name]] /]"
            if { $preferences(analize_cause_fail) } {                
                #find source files that changed after the ok_date
                set filenames_changed [list]
                set source_folders {{C:/gid project/gid} {C:/gid project/gid/Post} {C:/gid project/scripts}}
                set source_extensions {{.cc .h} {.cc .h} {.tcl}}
                foreach source_folder $source_folders extensions $source_extensions {
                    foreach extension $extensions {
                        foreach filename [glob -nocomplain -directory $source_folder -types f *$extension] {
                            set file_mtime [file mtime $filename]
                            if { $file_mtime > $ok_date } {
                                lappend filenames_changed $filename
                            }
                        }
                    }
                }           
                #append msg "\n[llength $filenames_changed] files changed:\n"
                #foreach filename $filenames_changed {
                    #    append msg [file tail $filename]\n
                    #}
                
                #use cvs to filter files that changed in CVS in these dates
                set filenames_changed_cvs [list]
                foreach filename $filenames_changed {
                    set filename_tail [file tail $filename]
                    set filename_dir [file dirname $filename]                    
                    set d0 [clock format $ok_date -format {%Y-%m-%d %H:%M:%S}]
                    set d1 [clock format $fail_date -format {%Y-%m-%d %H:%M:%S}]
                    set prev_dir [pwd]
                    cd $filename_dir
                    if { [catch { exec cvs log -N "-d$d0<$d1" "$filename_tail" } result] } {
                        set kk 1
                    } else {
                        if { ![regexp {selected revisions: ([0-9]+)\n} $result dummy num_selected] } {
                            set kk 0
                        } else {
                            if { $num_selected } {                                    
                                set revisions [list]
                                foreach {dummy revision} [regexp -all -inline {revision ([0-9]+.[0-9]+)} $result] {
                                    lappend revisions $revision
                                }
                                set revisions [lsort -real $revisions]
                                set r0 [lindex $revisions 0]
                                set r1 [lindex $revisions end]
                                if { $r0 == $r1 } {
                                    set revisions $r0
                                } else {
                                    set revisions [list $r0 $r1]
                                }
                                set authors [list]
                                foreach {dummy author} [regexp -all -inline {author: ([^;]+);} $result] {
                                    lappend authors $author
                                }
                                set authors [lsort -dictionary -unique $authors]
                                lappend filenames_changed_cvs [list $filename $revisions $authors]
                            }
                        }
                    }
                    cd $prev_dir
                }
                append msg "\n[llength $filenames_changed_cvs] CVS files changed:\n"
                foreach item $filenames_changed_cvs {
                    set filename_tail [file tail $filename]
                    set filename_dir [file dirname $filename]                   
                    lassign $item filename revisions authors
                    append msg "$filename_tail $revisions $authors\n"                
                    if { 0 && [lsearch -exact $authors abel] != -1 } {
                        lassign $revisions r0 r1
                        set prev_dir [pwd]
                        cd $filename_dir
                        #catch { exec cvs diff -r $r0 -r $r1 "$filename_tail" } result
                        exec {C:\Program Files (x86)\TkCvs 8.2.3-source\bin\tkdiff.exe} -r $r0 -r $r1 "$filename_tail" &
                        cd $prev_dir
                    }
                }
            }            
        }   
    } else {
        error "tester::analize_cause_fail_cvs. unexpected last_fail=$last_fail"     
    }
    return $msg
}

proc tester::analize_cause_fail_git { case_id } {
    variable preferences    
    variable cancel_process
    variable pause_process
    variable progress
    variable maxprogress
    
    set msg ""
    set last_fail [tester::digest_results_get_fail $case_id]   
    if { $last_fail == "" } {
        set msg [_ "Case %s not run." $case_id]    
    } elseif { $last_fail == 0 } {     
        set msg [_ "Case %s is ok." $case_id]
    } elseif { $last_fail == 1 || $last_fail == "timeout" || $last_fail == "maxmemory" || $last_fail == "userstop" || $last_fail == "crash" } {
        #set ok_date [tester::digest_results_get_ok_date $case_id]
        #I am not confident on ok_date, maybe is better find for example from a week ago
        set now [clock seconds]
        set a_week_ago [expr {$now-604800}]
        set since [clock format $a_week_ago -format {%Y %m %d %H %M %S}]
        set commits [git::list_commits $since 100]
        set num_commits [llength $commits]
        if { $num_commits } {
            set prev_current_commit [git::get_current_commit]
            set bits 64
            visual_studio::set_environment_variables $bits
            tester::message  [_ "Find in %s last git commits the one broking case %s" $num_commits $case_id]

            tester::gui_enable_pause
            set maxprogress $num_commits
            set progress 0
            set i_commit 0
            foreach commit $commits {
                if { $::tester::pause_process } {
                    vwait ::tester::pause_process
                }
                if { $cancel_process } {
                    set msg [_ "User stopped find of fail cause of case %s." $case_id]               
                    break
                }
                tester::message  [_ "Checkout commit %s" $commit] 
                set fail_checkout [git::checkout $commit 1]
                if { $fail_checkout } {
                    set msg [_ "Fail checkout case %s." $case_id]
                    break
                } else {
                    #try to delete gid_${bits}.exe to be sure that is rebuild ?
                    tester::message  [_ "Building (%s bits)" $bits] 
                    set fail_build [visual_studio::build_gid $bits]
                    if { $fail_build } {
                        set msg [_ "Fail visual studio build case %s." $case_id]
                        break
                    } else {                    
                        tester::message  [_ "Running case %s" $case_id] 
                        tester::execute_test $case_id 0
                        #to wait until the process finish
                        while { [tester::exists_variable $case_id pid] } {
                            after 100
                            update
                        }
                        set fail_run [tester::digest_results_get_fail $case_id]
                        tester::message  [_ "Result %s" $fail_run]
                        if { $fail_run == 0 } {
                            set commit_broken [lindex $commits [expr $i_commit-1]] ;#the previous one
                            set msg [_ "Case %s broken in commit %s" $case_id $commit_broken]
                            append msg "\n [git::show_commit $commit_broken]"
                            break
                        }                    
                    }                    
                }
                incr i_commit
                incr progress
            }                               
            #restore gid initial commit
            tester::message  [_ "Restore initial commit %s" $prev_current_commit] 
            if { $prev_current_commit == [git::get_master_commit] } {
                git::checkout master 0
            } else {
                git::checkout $prev_current_commit 1
            }
            set maxprogress 0
            tester::gui_enable_play
        }  else {
            set msg [_ "Any commit broken the case %s." $case_id]
        }        
    } else {
        error "tester::analize_cause_fail_git. unexpected last_fail=$last_fail"
    }
    return $msg    
}


#tester::mail_send_smtp is not working, use mailsend.exe!!
proc tester::mail_send_smtp {recipients subject body} {
    variable preferences
    set fail 0
    package require smtp
    package require mime
    package require tls
    package require SASL
    package require SASL::NTLM
    set server $preferences(mailsend_server)
    set port $preferences(mailsend_port)
    set username $preferences(mailsend_username)
    set password $preferences(mailsend_password)
    set token [mime::initialize -canonical text/plain -param {charset "utf-8"} -encoding quoted-printable -string [encoding convertto utf-8 $body]]
    mime::setheader $token Subject [mime::word_encode "utf-8" quoted-printable [encoding convertto utf-8 $subject]]
    mime::setheader $token To $recipients
    smtp::sendmessage $token -ports $port -originator $username -recipients $recipients -servers $server -username $username -password $password -usetls 1
    mime::finalize $token
    return $fail
}

proc tester::mail_send_mailsend_exe {recipients subject body} {
    variable private_options
    variable preferences
    set fail 0
    if { $::tcl_platform(platform) == "windows" } {
        set mailsend_exe [file join $private_options(program_path) bin mailsend.exe]
    } else {
        set mailsend_exe [file join $private_options(program_path) bin mailsend]
    }
    set server $preferences(mailsend_server)
    set port $preferences(mailsend_port) 
    set username $preferences(mailsend_username)
    set password $preferences(mailsend_password)
    if { [catch { exec $mailsend_exe -t $recipients -f $username -ssl -port $port -auth -smtp $server -sub $subject -M $body -user $username -pass $password & } msg] } {
        set fail 1
    }
    return $fail
}

proc tester::mail_send { recipients subject body } {
    #tester::mail_send_smtp $recipients $subject $body ;#is not working!!
    tester::mail_send_mailsend_exe $recipients $subject $body
}

proc tester::run_all { } {
    set force_with_window 0
    set filtered_cases [tester::filter_case_ids [tester::case_ids]]
    tester::set_message [_ "start automatic run of %s cases at %s" [llength $filtered_cases] [tester::get_current_formatted_date]]
    tester::run $filtered_cases $force_with_window
    tester::set_message [_ "end automatic run at %s" [tester::get_current_formatted_date]]
    return 0
}

# start an after event to check every midnight
proc tester::start_track_schedule_run_at { } {
    variable preferences    
    set now [clock seconds]
    set dt [expr {([clock scan $preferences(run_at_value)]-$now)*1000}]
    if { $dt<0 } {
        #cannot go back in the time, it is an hour of the next day, 89928000=24 hours in milliseconds
        incr dt 89928000
    }    
    after $dt tester::track_schedule_run_at
}

# event raised every midnight
proc tester::track_schedule_run_at { } {
    variable preferences
    after cancel tester::track_schedule_run_at
    if { $preferences(run_at) } {
        tester::run_all
    }        
    tester::start_track_schedule_run_at
}

#tree GUI utilities

#auxiliary recursive procedure to get case ids of a tree item
proc tester::tree_get_child_cases { tree item } {
    set case_ids [list]
    if { [$tree item tag expr $item case] } {
        lappend case_ids [tester::tree_get_item_case_id $tree $item]
    } elseif { [$tree item tag expr $item container] } {
        foreach item_child [$tree item children $item] {
            lappend case_ids {*}[tester::tree_get_child_cases $tree $item_child]
        }
    }
    return $case_ids
}

#auxiliary procedure to get case ids of the current tree selection
proc tester::tree_get_selection_case_ids { } {
    variable tree    
    set case_ids [list]    
    foreach item [$tree selection get] {
        lappend case_ids {*}[tester::tree_get_child_cases $tree $item]        
    }
    set case_ids [lsort -dictionary -unique $case_ids]
    return $case_ids
}

#to run the current tree selected items
proc tester::run_selection { force_with_window { run_option ""}} {    
    set case_ids [tester::tree_get_selection_case_ids]
    tester::run $case_ids $force_with_window $run_option
}

proc tester::edit_selected_case { } {
    if { [llength [tester::tree_get_selection_case_ids]] == 1 } {
        set case_id [lindex [tester::tree_get_selection_case_ids] 0]
        tester::edit_case $case_id
    }
}

proc tester::set_case_definition_field_selected_cases { field value } {
    set case_ids [tester::tree_get_selection_case_ids]
    foreach case_id $case_ids {
        tester::set_case_definition_field $case_id $field $value
    }    
    tester::set_message [_ "Set field %s=%s to %s cases" $field $value [llength $case_ids]]
}

proc tester::set_case_definition_field { case_id field value } {
    variable private_options
    variable case_allowed_keys
    variable case_allowed_attributes
    
    tester::set_case_definition_field_from_tree $case_id $field $value      
    tester::set_variable $case_id $field $value    
    set document $private_options(xml_document)
    set xml_node_case [tester::xml_get_element_by_id $document $case_id]
    if { $xml_node_case == "" } {
        tester::message [_ "The case %s doesn't exists" $case_id]
    } else {
        if { [lsearch -dictionary -exact -sorted $case_allowed_attributes $field] != -1 } {
            if { $value == [tester::get_default_attribute_value $field] } {
                if { [$xml_node_case hasAttribute $field] } {
                    $xml_node_case removeAttribute $field
                }
            } else {
                $xml_node_case setAttribute $field $value
            }
        } elseif { [lsearch -dictionary -exact -sorted $case_allowed_keys $field] != -1 } {
            set xml_text_node [tester::xml_get_text_node_by_field $xml_node_case $field]
            if { $xml_text_node != "" } {
                $xml_text_node nodeValue $value
            } else {
                #create the xml node
                set key_xml_node [tester::xml_create_element $xml_node_case $field ""]
                tester::xml_create_text_node $key_xml_node $value                
            }
        } else {
            tester::message [_ "case %s definition field unexpected" $case_id $field]
        }
    }
    set private_options(must_save_document) 1        
}

#to delete frm the tree selected items
proc tester::delete_selected_cases { } {    
    set case_ids [tester::tree_get_selection_case_ids]
    set num_cases [llength $case_ids]
    if { !$num_cases } {
        tester::message [_ "The cases to be deleted must selected before"]
    } else {
        set txt [_ "Selected %s cases to be deleted. Delete them?\n(batch file and models won't be deleted)" $num_cases]
        set reply [tk_messageBox -message $txt -icon question -default no -type yesno]
        if { $reply == "no"  } {
            return 1
        }         
        foreach case_id $case_ids {
            tester::delete_case $case_id
        }
        tester::set_message [_ "Deleted %s cases" $num_cases]
    }
}

proc tester::tree_select_next_case_starting_by_letter { char } {
    variable tree
    set searchstring $char
    set id_start [$tree index "active below"]
    set id $id_start
    set reached_end 0
    set id_found ""
    while { $id != "" } {
        set txt [$tree item text $id 0]
        if { [string match -nocase $searchstring* $txt] } {
            set id_found $id
            break
        }
        set id [$tree index "$id below"]
        if { $id == "" && !$reached_end } {           
            set id [$tree index "first visible"]
            set reached_end 1
        } elseif { $reached_end && [$tree item compare $id >= $id_start] } {
            break
        }
    }
    if { $id_found != "" } {
        $tree activate $id_found
        $tree see $id_found
        $tree selection clear all
        $tree selection add active
        $tree selection anchor active
    }
}

proc tester::tree_keypress { key char } {
    if { [string is print -strict $char] } { 
        tester::tree_select_next_case_starting_by_letter $char    
    }
}

proc tester::clipboard_copy_tree { } {
    variable tree
    set columns [$tree column list -visible]
    set data_list [list]
    set item [$tree index "first visible"]
    while { $item != "" } {
        if { [$tree selection includes $item] } {
            set line_list [list]
            foreach column $columns {
                if { $column == 4 || $column == 7 } {
                    set date_unformatted [$tree item element cget $item $column e_text_date -data]
                    lappend line_list [tester::format_date $date_unformatted]           
                } else {
                    lappend line_list [$tree item text $item $column]
                }
            }
            lappend data_list [join $line_list \t]
        }
        set item [$tree index "$item below"]
    }
    clipboard clear
    clipboard append [join $data_list \n]
}

proc tester::tree_collapse_all { } {
    variable tree
    $tree item collapse root -recurse
}

proc tester::tree_expand_all { } {
    variable tree
    #expand only containers, to see cases (not its childs)
    set items_to_expand [$tree item id "all tag container state !open"]
    foreach item_to_expand $items_to_expand {
        $tree item expand $item_to_expand
    }
}


proc tester::tree_sort_recursive { tree parent column direction mode } {
    #do not sort items of a case, in particular must not reorder the checks
    if { ![$tree item tag expr $parent case] } {        
        $tree item sort $parent -column $column $direction $mode
        foreach child_item [$tree item children $parent] {
            tester::tree_sort_recursive $tree $child_item $column $direction $mode
        }
    }
}

proc tester::tree_sort { tree header column } {
    variable private_options
    variable preferences
    variable tree_sorted_by_column
    variable tree_sorted_direction
    set direction -increasing
    set arrow [$tree header cget $header $column -arrow]
    if { $arrow == "up" } {        
        $tree header configure $header $column -arrow down
        set direction -increasing
    } elseif { $arrow == "down" } {        
        $tree header configure $header $column -arrow up
        set direction -decreasing
    } elseif { $arrow == "none" } {
        set nj [$tree column count]
        for {set j 0} {$j<$nj } {incr j} {
            if { [$tree header cget $header $column -arrow] != "none" } {
                $tree header configure $header $column -arrow none
            }
        }
        $tree header configure $header $column -arrow up
        set direction -decreasing
    } else {
        return
    }    
    set tree_sorted_by_column $column
    set tree_sorted_direction $direction
    #do not use -integer in any column because some could be ""
    tester::tree_sort_recursive $tree root $column $direction -dictionary
}


#add a row to the tree
proc tester::tree_insert { tree img_ok_fail img_category txt parent } {
    set item [$tree item create -button auto -parent $parent -open 0]
    $tree item style set $item 0 style_image_text 1 style_test_fail 2 style_test_time 3 style_test_memory \
        4 style_date 5 style_normal 6 style_normal 7 style_date 8 style_normal
    $tree item element configure $item \
        0 e_image -image $img_ok_fail + e_image_category -image $img_category + e_text_sel -text $txt -justify left , \
        1 e_text_test_fail -text "" , \
        2 e_text_test_time -text "" , \
        3 e_text_test_memory -text "" , \
        4 e_text_date -data "" , \
        5 e_text_normal -text "" , \
        6 e_text_normal -text "" , \
        7 e_text_date -data "" , \
        8 e_text_normal -text ""
    return $item
}

#set/get some case definition field to/from a tree item
proc tester::tree_set_item_definition_field { tree item value } {
    $tree item element configure $item 0 e_text_sel -text $value
}

proc tester::tree_get_item_definition_field  { tree item } {
    return [$tree item element cget $item 0 e_text_sel -text]
}

#store last test values: fail time memory date (and compare with min_time, min_memory to raise warnings)
proc tester::tree_set_item_case_last_test_values { tree item result time memory date } {
    $tree item element configure $item 1 e_text_test_fail -text $result , 2 e_text_test_time -text $time , \
        3 e_text_test_memory -text $memory , 4 e_text_date -data $date  
}

#states is a list, each state x could be: test_done test_fail test_crash test_run test_warning_time test_warning_memory
#or its negations (!x) or swaps  (~x)
proc tester::set_digest_results_test_states { case_id states } {
    variable tree
    if { [info exists tree] && [winfo exists $tree] } {
        variable tree_item_case ;#to store the tree item of a case id
        set item $tree_item_case($case_id)        
        $tree item state set $item $states
    }
}

#minimum time spent by some ok case
proc tester::tree_set_item_case_min_time { tree item min_time } {
    $tree item element configure $item 5 e_text_normal -text $min_time
}

#minimum RAM used by some ok case
proc tester::tree_set_item_case_min_memory { tree item min_memory } {
    $tree item element configure $item 6 e_text_normal -text $min_memory
}

#date of last test that was ok
proc tester::tree_set_item_case_ok_date { tree item ok_date } {
    $tree item element configure $item 7 e_text_date -data $ok_date
}

#set/get the case id to/from a tree item
proc tester::tree_set_item_case_id { tree item case_id } {
    $tree item element configure $item 8 e_text_normal -text $case_id
}

proc tester::tree_get_item_case_id { tree item } {
    return [$tree item element cget $item 8 e_text_normal -text]
}

#format to MB
proc tester::format_memory { memory } {
    if { $memory != "" } {
        set memory_mb [format "%.1f" [expr double($memory)/(1024*1024)]]
    } else {
        set memory_mb ""
    }
    return $memory_mb
}

#format the integer date to a human representation
proc tester::format_date { date } {
    if { $date != "" } {
        set date_formatted [clock format $date -format {%H:%M:%S %m/%d/%Y}]
    } else {
        set date_formatted ""
    }
    return $date_formatted
}

proc tester::unformat_date { date_formatted } {
    return [clock scan $date_formatted -format {%H:%M:%S %m/%d/%Y}]
}

proc tester::digest_results_set_result_state { case_id result } {
    if { $result == "untested"  || $result == -1 || $result == "" } {
        tester::set_digest_results_test_states $case_id {!test_done}
    } elseif { $result == "running"  } {
        tester::set_digest_results_test_states $case_id {!test_done test_run}
    } elseif { $result == "ok" || $result == 0 } {
        tester::set_digest_results_test_states $case_id {test_done !test_fail !test_run}
    } elseif { $result == "fail" || $result == 1 } {
        tester::set_digest_results_test_states $case_id {test_done test_fail !test_run}
    } elseif { $result == "crash" || $result == 2} { 
        #2 by back compatibility
        tester::set_digest_results_test_states $case_id {test_done test_fail test_crash !test_run}
    } elseif { $result == "timeout" } {
        tester::set_digest_results_test_states $case_id {test_done test_fail test_crash !test_run}
    } elseif { $result == "maxmemory" } {
        tester::set_digest_results_test_states $case_id {test_done test_fail test_crash !test_run}
    } elseif { $result == "userstop" } {
        tester::set_digest_results_test_states $case_id {!test_done !test_run}
    } else {
        tester::message "tester::digest_results_set_result_state. unexepected result=$result"
        tester::set_digest_results_test_states $case_id {!test_done}
    }
}

### test values: fail time memory date (and compare with min_time, min_memory to raise warnings)
proc tester::digest_results_set_last_test_values { case_id result time memory date } {
    variable digest_results ;#array to store digest of history of results, and last tested result    
    variable private_options
    variable tree
    if { ![info exists digest_results($case_id)] } {
        set digest_results($case_id) [lrepeat 7 {}]
    }
    lset digest_results($case_id) 0 $result
    lset digest_results($case_id) 1 $time
    lset digest_results($case_id) 2 $memory
    lset digest_results($case_id) 3 $date  
    set private_options(must_save_digest_results) 1  
    if { [info exists tree] && [winfo exists $tree] } {
        variable tree_item_case ;#to store the tree item of a case id
        set item $tree_item_case($case_id)
        set memory_kb [tester::format_memory $memory]
        #set date_formatted [tester::format_date $date]
        tester::tree_set_item_case_last_test_values $tree $item $result $time $memory_kb $date
    }
    tester::digest_results_set_result_state $case_id $result
}

proc tester::digest_results_set_values { case_id result time memory date min_time min_memory ok_date } {
    variable digest_results
    variable private_options
    variable tree
    set digest_results($case_id) [list $case_id $result $time $memory $date $min_time $min_memory $ok_date]
    set private_options(must_save_digest_results) 1
    if { [info exists tree] && [winfo exists $tree] } {
        variable tree_item_case ;#to store the tree item of a case id
        set item $tree_item_case($case_id)     
        set memory_kb [tester::format_memory $memory]
        #set date_formatted [tester::format_date $date]
        set min_memory_kb [tester::format_memory $min_memory]           
        #set ok_date_formatted [tester::format_date $ok_date]
        tester::tree_set_item_case_last_test_values $tree $item $result $time $memory_kb $date
        tester::tree_set_item_case_min_time $tree $item $min_time        
        tester::tree_set_item_case_min_memory $tree $item $min_memory_kb
        tester::tree_set_item_case_ok_date $tree $item $ok_date
    }
    tester::digest_results_set_result_state $case_id $result
}

#return the list of all values in this order: fail time memory date min_time min_memory ok_date
proc tester::digest_results_get_values { case_id } {
    variable digest_results
    return $digest_results($case_id)
}

proc tester::digest_results_get_fail { case_id } {
    variable digest_results
    if { ![info exists digest_results($case_id)] } {
        return ""
    }
    return [lindex $digest_results($case_id) 0]
}

proc tester::digest_results_get_date { case_id } {
    variable digest_results
    if { ![info exists digest_results($case_id)] } {
        return ""
    }
    return [lindex $digest_results($case_id) 3]
}

#minimum time spent by some ok case
proc tester::digest_results_set_min_time { case_id min_time } {
    variable digest_results
    variable private_options
    variable tree
    if { ![info exists digest_results($case_id)] } {
        set digest_results($case_id) [lrepeat {}  7]
    }
    lset digest_results($case_id) 4 $min_time
    set private_options(must_save_digest_results) 1
    if { [info exists tree] && [winfo exists $tree] } {
        variable tree_item_case ;#to store the tree item of a case id
        set item $tree_item_case($case_id)
        tester::tree_set_item_case_min_time $tree $item $min_time
    }    
}

proc tester::digest_results_get_min_time { case_id } {
    variable digest_results
    if { ![info exists digest_results($case_id)] } {
        return ""
    }
    return [lindex $digest_results($case_id) 4]
}

#minimum RAM used by some ok case
proc tester::digest_results_set_min_memory { case_id min_memory } {
    variable digest_results
    variable private_options
    variable tree
    if { ![info exists digest_results($case_id)] } {
        set digest_results($case_id) [lrepeat {}  7]
    }
    lset digest_results($case_id) 5 $min_memory
    set private_options(must_save_digest_results) 1
    if { [info exists tree] && [winfo exists $tree] } {
        variable tree_item_case ;#to store the tree item of a case id
        set item $tree_item_case($case_id)     
        set min_memory_kb [tester::format_memory $min_memory]
        tester::tree_set_item_case_min_memory $tree $item $min_memory_kb
    }    
}

proc tester::digest_results_get_min_memory { case_id } {
    variable digest_results
    if { ![info exists digest_results($case_id)] } {
        return ""
    }
    return [lindex $digest_results($case_id) 5]
}

#date of last test that was ok
proc tester::digest_results_set_ok_date { case_id ok_date } {
    variable digest_results
    variable private_options
    variable tree
    if { ![info exists digest_results($case_id)] } {
        set digest_results($case_id) [lrepeat {}  7]
    }
    lset digest_results($case_id) 6 $ok_date
    set private_options(must_save_digest_results) 1
    if { [info exists tree] && [winfo exists $tree] } {
        variable tree_item_case ;#to store the tree item of a case id
        set item $tree_item_case($case_id)       
        #set ok_date_formatted [tester::format_date $ok_date]
        tester::tree_set_item_case_ok_date $tree $item $ok_date
    }    
}

proc tester::digest_results_get_ok_date { case_id } {
    variable digest_results
    if { ![info exists digest_results($case_id)] } {
        return ""
    }
    return [lindex $digest_results($case_id) 6]
}

#old_case_id "" except editing a case changing batch that modify its id
proc tester::tree_update_case { case_id old_case_id } {
    variable tree
    variable tree_item_case
    if { ![info exists tree] || ![winfo exists $tree] } {
        return 1
    }    
    if { $old_case_id != "" && [info exists tree_item_case($old_case_id)] } {
        set item $tree_item_case($old_case_id)
        unset tree_item_case($old_case_id)
        set tree_item_case($case_id) $item
        tester::tree_set_item_case_id $tree $item $case_id
    } else {
        set item $tree_item_case($case_id)    
    }
    set label [string trim [tester::get_variable $case_id name]]
    if { [tester::tree_get_item_definition_field $tree $item] != $label } {
        tester::tree_set_item_definition_field $tree $item $label
    }
    foreach item_child [$tree item children $item] {
        $tree item delete $item_child
    }
    tester::tree_create_childs $item
    tester::fill_digest_results_to_tree $case_id
    return 0
}

proc tester::tree_create_childs { item } {
    variable tree
    if { [$tree item tag expr $item case] } {
        if { [$tree item numchildren $item] } {
            return
        }
        #not create items until the user expand it
        variable preferences
        set case_id [tester::tree_get_item_case_id $tree $item]
        set img [tester::get_image blue-r.png]
        set item_definition [tester::tree_insert $tree $img "" [_ "definition"] $item]
        $tree item tag add $item_definition definition       
        foreach key [tester::get_keys $case_id] {
            set value [tester::get_variable $case_id $key]
            if { $value == "" } {
                continue
            }
            if { $key == "name" } {
                continue
            } elseif { $key == "outfile" } {
                #not show the temporary output filename
                continue
            } elseif { $key == "gidini" } {
                if { $value == [tester::get_preferences_key_value gidini]} {
                    continue
                }
            } elseif { $key == "readingproc" } {
                if { $value == "read_gid_monitoring_info" } {
                    continue
                }
            } elseif { $key == "fail_accepted" } {
                if { $value == "0" } {
                    continue
                }
            } elseif { $key == "fail_random" } {
                if { $value == "0" } {                    
                    continue
                }
            }
            if { [info exists preferences($key)] && $value == $preferences($key) } {
                #only show fields without default value
                continue
            }            
            
            set id_key [tester::tree_insert $tree $img "" "$key: $value" $item_definition]
        }
        set checks [tester::get_checks $case_id]
        set implicit_check_outputfiles [tester::exists_variable $case_id outputfiles]
        if { $checks != "" || $implicit_check_outputfiles } {
            set item_checks [tester::tree_insert $tree $img "" [_ "checks"] $item]
            $tree item tag add $item_checks checks
            if { $implicit_check_outputfiles } {
                #set content "\[tester::check_files_exists [tester::get_variable $case_id outputfiles]\]"
                set item_check [tester::tree_insert $tree $img "" outputfiles $item_checks]
            }
            foreach check $checks {
                set item_check [tester::tree_insert $tree $img "" [tester::get_variable $case_id check,$check] $item_checks]               
            }
        }        
    }
}

proc tester::tree_expand_after { tree item } {    
    variable tree_isopen
    set case_id [tester::tree_get_item_case_id $tree $item]
    if { $case_id != "" } {
        set tree_isopen($case_id) 1
    } elseif { [$tree item tag expr $item container] } {
        set tag [tester::tree_get_item_definition_field $tree $item]
        set tree_isopen($tag) 1
    }
}

proc tester::tree_collapse_after { tree item } {
    variable tree_isopen
    set case_id [tester::tree_get_item_case_id $tree $item]
    if { $case_id != "" } {
        unset -nocomplain tree_isopen($case_id)
    } elseif { [$tree item tag expr $item container] } {
        set tag [tester::tree_get_item_definition_field $tree $item]
        unset -nocomplain tree_isopen($tag)
    }
}

proc tester::save_tree_status_filename { } {
    variable tree_isopen
    set filename [tester::get_tree_open_filename]
    set fp [open $filename w]
    foreach case_id [lsort -dictionary [array names tree_isopen]] {
        puts $fp $case_id
    }
    close $fp
}

proc tester::read_tree_status_filename { } {
    variable tree_isopen
    array unset tree_isopen
    set filename [tester::get_tree_open_filename]
    if { [file exists $filename] } {
        set fp [open $filename r]
        set all [read $fp]
        close $fp
        foreach case_id [split $all \n] {
            if { $case_id != "" } {
                set tree_isopen($case_id) 1
            }
        }
    }    
}

#populate the tree with the data of current filtered cases
proc tester::fill_tree {  } {    
    variable tree    
    variable tree_item_case ;#to store the tree item of a case id
    variable tree_isopen
    variable tree_sorted_by_column
    variable tree_sorted_direction
    variable private_options
    variable preferences
    
    if { ![info exists tree] || ![winfo exists $tree] } {
        return 1
    }    
    
    tester::reset_counter_tested_cases -1    
    tester::clear_tree    
    set case_ids [tester::case_ids]    
    set case_ids [tester::filter_case_ids $case_ids]
    
    foreach case_id $case_ids {
        tester::add_case_to_tree $case_id         
        tester::fill_digest_results_to_tree $case_id
        #tester::fill_checks_to_tree $case_id
        #tester::fill_results_to_tree $case_id
        if { [info exists tree_isopen($case_id)] } {
            set item $tree_item_case($case_id)
            $tree item expand $item
        }
    }
    tester::fill_containers_state
        
    tester::tree_sort_recursive $tree root $tree_sorted_by_column $tree_sorted_direction -dictionary
    return 0
} 

#esto aun no esta bien!!!!
proc tester::fill_containers_state { } {
    variable tree
    #order them decreasing to set up first child folders and later parent folders
    set items_container [lsort -integer -decreasing [$tree item id "all tag container"]]    
    foreach item $items_container {        
        set result [tester::get_result_from_tree_childs $tree $item]
        tester::set_item_test_state $tree $item $result
    }
}

proc tester::add_case_to_tree { case_id } {
    variable tree
    variable tree_item_case ;#to store the tree item of a case id
    variable tree_isopen
    variable preferences
    if { ![info exists tree] || ![winfo exists $tree] } {
        return 1
    }
    
    set parent 0        
    set img_untested [tester::get_image untested.png]
    if { $preferences(show_as_tree) } {
        set img_case_folder [tester::get_image case_folder.png]
        set items [tester::get_variable $case_id tags]
        foreach item $items {
            set text $item
            set current [tester::tree_get_first_children_tag_text $tree $parent container $text]            
            if { ![llength $current] } {
                set current [tester::tree_insert $tree $img_untested $img_case_folder $text $parent]
                $tree item tag add $current container
                if { [info exists tree_isopen($text)] } {
                    $tree item expand $current
                }
                
            }
            set parent $current
        }        
    }
    if { [tester::exists_variable $case_id name] } {
        set label [string trim [tester::get_variable $case_id name]]
    } else {
        set label ""
    }      
    set img_case [tester::get_image case.png]
    set item [tester::tree_insert $tree $img_untested $img_case $label $parent]
    tester::tree_set_item_case_id $tree $item $case_id
    $tree item tag add $item case
    set tree_item_case($case_id) $item       
    $tree item configure $item -button yes ;#force create the button to be filled later on demand
}

proc tester::remove_case_from_tree { case_id } {
    variable tree
    variable tree_item_case ;#to store the tree item of a case id
    if { ![info exists tree] || ![winfo exists $tree] } {
        return 1
    }    
    if { [info exists tree_item_case($case_id)] } {
        set item $tree_item_case($case_id)
        if { [$tree item id $item] != "" } {
            $tree item delete $item
        }    
        unset tree_item_case($case_id)
    }
    return 0
}

proc tester::set_case_definition_field_from_tree { case_id field value } {
    variable tree   
    variable tree_item_case ;#to store the tree item of a case id
    if { ![info exists tree] || ![winfo exists $tree] } {
        return 1
    }  
    set item $tree_item_case($case_id)
    set item_definition [tester::tree_get_first_children_tag $tree $item definition]
    if { [llength $item_definition] == 1 } {        
        set item_definition_field [tester::tree_get_first_children_field $tree $item_definition $field]
        if { [llength $item_definition_field] == 1 } {
            tester::tree_set_item_definition_field $tree $item_definition_field $value
        } else {
            #create the field if already was not created
            set img [tester::get_image blue-r.png]
            set item_definition_field [tester::tree_insert $tree $img "" "$field: $value" $item_definition]
        }
    }
    return 0
}

proc tester::remove_results_from_tree { case_id } {    
    variable tree   
    variable tree_item_case ;#to store the tree item of a case id
    if { ![info exists tree] || ![winfo exists $tree] } {
        return 1
    }  
    set item $tree_item_case($case_id)
    set item_results [tester::tree_get_first_children_tag $tree $item results]
    if { [llength $item_results] == 1 } {
        $tree item delete $item_results
    }
    return 0
}

proc tester::fill_results_to_tree { case_id } {    
    variable tree
    variable tree_item_case ;#to store the tree item of a case id
    if { ![tester::exists_variable $case_id results] } {
        return
    }            
    if { [info exists tree] && [winfo exists $tree] } {
        set img [tester::get_image blue-r.png]
        set item $tree_item_case($case_id)        
        tester::tree_create_childs $item        
        set item_results [tester::tree_get_first_children_tag $tree $item results]
        if { ![llength $item_results] } {
            set item_results [tester::tree_insert $tree $img "" [_ "results"] $item]
            $tree item tag add $item_results results
        }
        foreach {key value} [tester::get_variable $case_id results] {
            set item_results_item [tester::tree_insert $tree $img "" "$key: $value" $item_results]
        }    
    }       
    return 0
}

proc tester::fill_digest_results_to_tree { case_id } {
    variable digest_results
    variable tree    
    variable tested_cases
    if { [info exists digest_results($case_id)] } {
        lassign $digest_results($case_id) result time memory date min_time min_memory ok_date
        if { [info exists tree] && [winfo exists $tree] } {
            variable tree_item_case ;#to store the tree item of a case id
            set item $tree_item_case($case_id)         
            set memory_kb [tester::format_memory $memory]
            #set date_formatted [tester::format_date $date]
            set min_memory_kb [tester::format_memory $min_memory]
            #set ok_date_formatted [tester::format_date $ok_date]
            tester::tree_set_item_case_last_test_values $tree $item $result $time $memory_kb $date
            tester::tree_set_item_case_min_time $tree $item $min_time
            tester::tree_set_item_case_min_memory $tree $item $min_memory_kb
            tester::tree_set_item_case_ok_date $tree $item $ok_date
        }
        tester::digest_results_set_result_state $case_id $result
        if { $result == "untested" || $result == "running" || $result == -1 || $result == "" } {
            # do nothing
        } elseif { $result == "ok" || $result == 0 } {
            incr tested_cases(ok)
            incr tested_cases(untested) -1
        } elseif { $result == "fail" || $result == 1 } {
            incr tested_cases(fail) 
            incr tested_cases(untested) -1
        } elseif { $result == "crash" || $result == 2 } {
            #2 by back compatibility
            incr tested_cases(fail) 
            incr tested_cases(untested) -1
        } elseif { $result == "timeout" } {
            incr tested_cases(fail) 
            incr tested_cases(untested) -1
        } elseif { $result == "maxmemory" } {
            incr tested_cases(fail) 
            incr tested_cases(untested) -1
        } elseif { $result == "userstop" } {
            #do nothing
        } else {
            tester::message "tester::fill_digest_results_to_tree. unexpeced result=$result"
        }
    }
}

#fill other columns of the case
proc tester::set_digest_results { case_id } {       
    array set case_results [tester::get_variable $case_id results]
    set result [tester::evaluate_checks $case_id]
    if { $result == "ok" || $result == 0 } {
        array set case_results [tester::get_variable $case_id results]        
        set time $case_results(time)
        if { [info exists case_results(workingset)] } {
            set memory $case_results(workingset)
        } else {
            set memory ""
        }
        set date $case_results(tini)
        tester::digest_results_set_last_test_values $case_id $result $time $memory $date
        set min_time [tester::digest_results_get_min_time $case_id]
        set warning_time 0
        if { $min_time == "" || $min_time > $time } {
            tester::digest_results_set_min_time $case_id $time
        } else {
            if { $time > [expr {$min_time*1.2}] } {
                #warning, current case spend too much time, set to orange!!
                set warning_time 1
            }
        }    
        if { $warning_time } {
            tester::set_digest_results_test_states $case_id test_warning_time
        } else {
            tester::set_digest_results_test_states $case_id !test_warning_time
        }
        set warning_memory 0
        if { $memory != "" } {
            set min_memory [tester::digest_results_get_min_memory $case_id]
            if { $min_memory == "" || $min_memory > $memory } {
                tester::digest_results_set_min_memory $case_id $memory            
            } else {
                if { $memory > [expr {$min_memory*1.2}] } {
                    #warning, current case spend too much memory, set to orange!!  
                    set warning_memory 1                
                }
            }        
        }
        if { $warning_memory } {
            tester::set_digest_results_test_states $case_id test_warning_memory
        } else {
            tester::set_digest_results_test_states $case_id !test_warning_memory
        }
        tester::digest_results_set_ok_date $case_id $date
    } else {
        #fail or user stop or crash
        tester::digest_results_set_last_test_values $case_id $result "" "" ""
    }
}

proc tester::do_checks { case_id crashed_or_killed } {       
    variable tested_cases
    set fail 0
    
    set ns results$case_id
    if { [namespace exists $ns] } {
        namespace delete $ns
    }
    foreach {item value} [tester::get_variable $case_id results] {
        set err ""
        if { [catch {namespace eval $ns [list set $item $value]} err] } {
            #e.g. some variable not exists
            namespace eval $ns [list set $item ""]
            tester::puts_log_error "case $case_id tester::do_checks. '$err'"
        }
    }
    set implicit_check_outputfiles [tester::exists_variable $case_id outputfiles]
    if { $implicit_check_outputfiles } {
        set check outputfiles
        if { $crashed_or_killed != "" } {
            set x [tester::get_result_code $crashed_or_killed]
        } else {
            set x [tester::file_exists_declared_outputfiles $case_id]            
        }
        tester::set_variable $case_id checkresult,$check $x
        if { $x == 0 } {
            incr fail
        }
    }
    
    set cont 0
    foreach check [tester::get_checks $case_id] {        
        if { $crashed_or_killed != "" } {
            set x [tester::get_result_code $crashed_or_killed]
        } else {
            set x 0
            set test [tester::get_variable $case_id check,$check]
            set err ""
            if { [regexp {GiD_expr (.*)} $test dummy procedure] } {
                incr cont
                if { [catch { set x [namespace eval $ns [list set expression-$cont]] } err] } {
                    #some error
                    set x 0
                }
            } else {           
                if { [catch { set x [namespace eval $ns [list expr $test]] } err] } {
                    #e.g. some variable not exists
                    set x 0
                }
            }
            if { ![string is boolean $x]} {
                tester::message "tester::do_checks. case id $case_id check result is not boolean (x=$x)"
                set x 0 ;#check not passed
            }
        }
        tester::set_variable $case_id checkresult,$check $x
        if { $x == 0 } {
            incr fail          
        }
    }
    namespace delete $ns
    
    if { $crashed_or_killed != "" || $fail > 0 } {
        if { $crashed_or_killed == "userstop" } {
            #do nothing
        } else {
            incr tested_cases(fail)
        }
    } else {
        incr tested_cases(ok)
    }   
    incr tested_cases(untested) -1
    
    return $fail
}


proc tester::set_item_test_state { tree item result } {
    if { $result == "untested" || $result == -1 } {     
        $tree item state set $item {!test_done}
    } elseif { $result == "running" } {
        $tree item state set $item {!test_done test_run}
    } elseif { $result == "ok" || $result == 0 } {
        $tree item state set $item {test_done !test_fail}
    } elseif { $result == "fail" || $result == 1 } {        
        $tree item state set $item {test_done test_fail}        
    } elseif { $result == "crash" || $result == 2 } {        
        #2 by back compatibility
        $tree item state set $item {test_done test_fail test_crash}        
    } elseif { $result == "timeout" } {        
        $tree item state set $item {test_done test_fail test_crash}
    } elseif { $result == "maxmemory" } {        
        $tree item state set $item {test_done test_fail test_crash}
    } elseif { $result == "userstop" } {        
        $tree item state set $item {!test_done !test_run}
    } else {
        $tree item state set $item {!test_done}       
        tester::message "tester::set_item_test_state. unexpected result=$result"
    } 
}

proc tester::get_result_from_tree_childs { tree item } {    
    set result "ok"
    foreach child_item [$tree item children $item] {
        set is_test_done [$tree item state get $child_item test_done]
        if { $is_test_done } {
            set is_test_fail [$tree item state get $child_item test_fail]
            if { $is_test_fail } {
                set is_test_crash [$tree item state get $child_item test_crash]
                if { $is_test_crash } {
                    set result "crash"
                } else {
                    set result "fail"
                }
                break           
            }
        } else {
            if { [$tree item tag expr $child_item container] } {
                set result [tester::get_result_from_tree_childs $tree $child_item]
                if { $result == 1 || $result == "fail" || $result == "crash" || $result == "timeout" || $result == "maxmemory" || $result == "userstop" } {
                    break
                }
            } else {
                #untested      
                set is_test_running [$tree item state get $child_item test_run]
                if { $is_test_running } {
                    set result "running"
                } else {
                    set result "untested"
                }
            }
        }        
    }    
    return $result
}

proc tester::tree_get_first_children_tag { tree item_parent tag } {
    foreach item [$tree item children $item_parent] {
        if { [$tree item tag expr $item $tag] } {
            return $item
        }
    }
    return ""
}

proc tester::tree_get_first_children_tag_text { tree item_parent tag text } {
    foreach item [$tree item children $item_parent] {
        if { [$tree item tag expr $item $tag] && [$tree item text $item 0] == $text } {
            return $item            
        }        
    }
    return ""
}

proc tester::tree_get_first_children_field { tree item_definition field } {
    foreach item_definition_field [$tree item children $item_definition] {
        set text [tester::tree_get_item_definition_field $tree $item_definition_field]
        if { [string compare -length [string length ${field}:] $text ${field}:] == 0 } {
            return $item_definition_field
        }
    }
    return ""
}

proc tester::fill_checks_to_tree { case_id } {
    variable tree    
    variable tree_item_case ;#to store the tree item of a case id    
    if { ![info exists tree] || ![winfo exists $tree] } {
        return 1
    }
    set ns results$case_id
    if { [namespace exists $ns] } {
        namespace delete $ns
    }
    foreach {item value} [tester::get_variable $case_id results] {
        set err ""
        if { [catch {namespace eval $ns [list set $item $value]} err] } {
            #e.g. some variable not exists
            namespace eval $ns [list set $item ""]            
        }
    }
    set some_check 0
    set checks [tester::get_checks $case_id]
    set implicit_check_outputfiles [tester::exists_variable $case_id outputfiles]   
    if { $implicit_check_outputfiles || [llength $checks] } {
        set some_check 1        
        set item $tree_item_case($case_id)
        tester::tree_create_childs $item        
        set item_checks [tester::tree_get_first_children_tag $tree $item checks]
    }       
    if { $implicit_check_outputfiles } {   
        set checks [list outputfiles {*}$checks]
    }
    set item_check ""        
    foreach check $checks {
        if { $check == "outputfiles" } {
            set test outputfiles
        } else {
            set test [tester::get_variable $case_id check,$check]
        }
        if { [tester::exists_variable $case_id checkresult,$check] } {
            if { $item_check == "" } {                               
                set item_check [$tree item firstchild $item_checks]
            } else {
                set item_check [$tree item nextsibling $item_check] 
            }
            set ok_check [tester::get_variable $case_id checkresult,$check]            
            if { $ok_check == 0 } {
                set result_string "fail"
            } elseif { $ok_check == 1 } {
                set result_string "ok"
            } elseif { $ok_check == 5 } {      
                set result_string "userstop"
            } else {
                set result_string "crash"
            }
            if { ![catch { set kk [namespace eval $ns [list subst $test]] } err] } {
                $tree item text $item_check 0 "$test ($kk)"                
            }
            tester::set_item_test_state $tree $item_check $result_string        
        }    
    }        
    if { $some_check } {
        set result [tester::evaluate_checks $case_id]
        tester::update_case_and_parents_tree_state $case_id $result
    }
    namespace delete $ns    
    return 0
}

#update in cascade parents state
proc tester::update_case_and_parents_tree_state { case_id result } {
    variable private_options
    if { !$private_options(gui) } {
        return
    }
    variable tree
    variable tree_item_case        
    set item $tree_item_case($case_id)
    set item_parent $item
    while { $item_parent != 0 } {     
        #if result == "fail" "crash" "timeout" "maxmemory" "userstop" don't need to check all its childs, parent also fail        
        if { $result == "untested" || $result == "running" || $result == "ok" } {
            if { [$tree item tag expr $item_parent container] } {
                set result [tester::get_result_from_tree_childs $tree $item_parent]
            }
        }
        tester::set_item_test_state $tree $item_parent $result           
        set item_parent [$tree item parent $item_parent]
    }    
}

proc tester::is_valid_file { filename } {
    set file_ok 0
    if { [file exists $filename]} {
        file stat $filename file_info
        if { $file_info(size) > 0} {
            set file_ok 1
        }
    }
    return $file_ok
}

proc tester::is_image_file { filename } {
    set ext [file extension $filename]
    set lst_img [list .gif .png .jpg .jpeg .tif .tiff]
    set ret 0
    if { [lsearch $lst_img $ext] != -1 } {
        set ret 1
    }
    return $ret
}

proc tester::is_animation_file { filename } {
    set ext [file extension $filename]
    set lst_vid [list .avi .flv .mpg .mpeg]
    set ret 0
    if { [lsearch $lst_vid $ext] != -1 } {
        set ret 1
    }
    return $ret
}

proc tester::is_text_file { filename } {
    set ext [file extension $filename]
    set lst_txt [list .txt .text .tim]
    set ret 0
    if { [lsearch $lst_txt $ext] != -1 } {
        set ret 1
    }
    return $ret
}

proc tester::is_html_file { filename } {
    set ext [file extension $filename]
    set lst_txt [list .html .htm]
    set ret 0
    if { [lsearch $lst_txt $ext] != -1 } {
        set ret 1
    }
    return $ret
}

proc tester::launch_editor { filename} {
    foreach editor [list code gedit kwrite kate xedit emacs vi] {
        set err [catch {exec $editor $filename &}]
        if { $err == 0} {
            break
        }
    }
}


#to cache images
proc tester::get_image { name } {
    variable _images
    if { ![info exists _images($name)] } {
        set full_filename [tester::get_full_application_path_inner images/$name]
        if { ![file exists $full_filename] } {
            #set full_filename [tester::get_full_application_path_inner images/16x16/$name]
            set full_filename [tester::get_full_application_path_inner images/24x24/$name]
        }
        set _images($name) [image create photo -file $full_filename]
    } 
    return $_images($name)
}

#application window

proc tester::update_title { } {        
    variable private_options
    variable preferences
    if { !$private_options(gui) } {
        return 1
    }
    wm title . "$private_options(program_name) $private_options(program_version) $preferences(branch_provide) $preferences(platform_provide)"
}

proc tester::command_on_return { e } {
    variable up_arrow
    set text [$e get]
    $e delete 0 end
    set list .fcommands.fm.messages
    tester::set_message ->$text
    set up_arrow [$list size]
    #eval $text
    uplevel #0 $text
}

proc tester::command_on_up { e } {
    variable up_arrow
    $e delete 0 end
    set list .fcommands.fm.messages
    while 1 {
        incr up_arrow -1
        if { $up_arrow < 0 } {
            set up_arrow -1
            break
        } elseif { [regexp {^->.*[^ ]+.*$} [$list get $up_arrow]] } {
            $e insert 0 [string range [$list get $up_arrow] 2 end]
            break
        }
    }
}

proc tester::command_on_down { e } {
    variable up_arrow
    $e delete 0 end
    set list .fcommands.fm.messages
    while 1 {
        incr up_arrow 1
        if { $up_arrow >= [$list size]  } {
            set up_arrow [$list size]
            break
        } elseif { [regexp {^->.*[^ ]+.*$} [$list get $up_arrow]] } {
            $e insert 0 [string range [$list get $up_arrow] 2 end]
            break
        }
    }
}

proc tester::clone_menu_bindings_to_window { parent_menu w Mp M } {
    foreach menu [winfo children $parent_menu] {
        for {set index [$menu index 0]} {$index <=[$menu index end]} {incr index} {
            if { [$menu type $index] != "separator" } {            
                set accelerator [$menu entrycget $index -accelerator]
                set command [$menu entrycget $index -command]
                if {$accelerator != "" && $command != "" } {
                    set items [split $accelerator -]
                    if { [llength $items] == 1 } {
                        if { $items == "F1" } {
                            bind $w <$items> $command
                        } elseif { $items == "Delete" } {
                            #not to do it, else deleting the text find will try to delete cases                            
                        } else {
                            #unexpected, must decide if do it or not
                        }
                    } elseif { [llength $items] == 2 } {
                        lassign [split $accelerator -] key letter
                        if { $key == $Mp } {         
                            bind $w <$M-[string tolower $letter]> $command
                            bind $w <$M-[string toupper $letter]> $command
                        } else {
                            error "tester::clone_menu_bindings_to_window, unexpected accelerator=$accelerator"
                        }
                    } else {
                        error "tester::clone_menu_bindings_to_window, unexpected accelerator=$accelerator"
                    }
                }                
            }
        }
    }
    
}

proc tester::create_win { } {
    variable private_options
    variable preferences
    variable button    
    variable maxprogress
    variable tree
    variable mainwindow
    variable tested_cases
    variable message
    
    if { !$private_options(gui) } {
        return 1
    }
    
    package require Tk
    package require treectrl
    package require tooltip
    if { $::tcl_platform(platform) == "windows" } {
        #ttk::style theme use winnative
        #ttk::style theme use vista
        #$tree theme setwindowtheme Explorer        
    }      
    
    set w .
    
    set mainwindow $w
    
    tester::update_title
    if { $::tcl_platform(platform) == "windows" } {
        wm iconbitmap $w [tester::get_full_application_path_inner images/tester.ico]
    }
    wm protocol $w WM_DELETE_WINDOW [list tester::destroy_win $w]
    
    #create menu
    if { [tk windowingsystem] eq "aqua"} {
        set Mp Command
        set M Command
    } else {
        set Mp Ctrl
        set M Control
    }
    set menu [menu $w.menu]
    $w configure -menu $menu
    $menu add cascade -label [_ "File"] -menu $menu.file
    $menu add cascade -label [_ "Edit"] -menu $menu.edit
    $menu add cascade -label [_ "Case"] -menu $menu.case
    $menu add cascade -label [_ "Help"] -menu $menu.help
    
    menu $menu.file -tearoff 0
    menu $menu.edit -tearoff 0
    menu $menu.case -tearoff 0
    menu $menu.help -tearoff 0
    $menu.file add command -label [_ "New"]... -command [list tester::press_new_project] -image [tester::get_image 16x16/project-new.png] -compound left -accelerator $Mp-n
    $menu.file add command -label [_ "Open"]... -command [list tester::press_read_project] -image [tester::get_image 16x16/project-open.png] -compound left -accelerator $Mp-o
    set private_options(menu_recent_projects) $menu.file.recent_projects
    menu $private_options(menu_recent_projects) -tearoff 0
    $menu.file add cascade -label [_ "Recent projects"] -menu $private_options(menu_recent_projects)
    $menu.file add command -label [_ "Save"]... -command [list tester::save] -image [tester::get_image 16x16/document-save.png] -compound left -accelerator $Mp-s
    #$menu.file add command -label [_ "Save as"]... -command [list tester::press_save_file] -image [tester::get_image 16x16/document-save-as.png] -compound left -accelerator $Mp-v
    $menu.file add separator
    $menu.file add command -label [_ "Preferences"]... -command [list tester::preferences_win] -image [tester::get_image 16x16/preferences.png] \
        -compound left -accelerator $Mp-p
    $menu.file add separator
    $menu.file add command -label [_ "Exit"]... -command [list tester::destroy_win $w] -image [tester::get_image 16x16/application-exit.png] \
        -compound left -accelerator $Mp-q
    
    $menu.edit add command -label [_ "Find"]... -command [list tester::find_win] -image [tester::get_image 16x16/find.png] \
        -compound left -accelerator $Mp-f
    
    $menu.case add command -label [_ "Define case"]... -command [list tester::define_case_win ""] -image [tester::get_image 16x16/case-new.png] \
        -compound left -accelerator $Mp-d    
    $menu.case add command -label [_ "Upload cases"]... -command [list tester::upload_cases] -image [tester::get_image 16x16/stock_insert-file.png] \
        -compound left -accelerator $Mp-a
    $menu.case add command -label [_ "Delete cases"]... -command [list tester::delete_selected_cases] -image [tester::get_image 16x16/stock_delete.png] \
        -compound left -accelerator Delete
    $menu.case add command -label [_ "View html"]... -command [list tester::save_report_html {time workingsetpeak check outputfiles} tester_report.html 1] \
        -image [tester::get_image 16x16/gnome-mime-text-html.png] -compound left -accelerator $Mp-h
    
    $menu.help add command -label [_ "Tester help"]... -command [list tester::help] -image [tester::get_image 16x16/help.png] \
        -compound left -accelerator F1
    $menu.help add command -label [_ "About"]... -command [list tester::about] -compound left -accelerator ""
    #
    
       
    bind $w <F3> [list tester::find] ;#find next
    bind $w <FocusIn> [list tester::check_if_must_reload]
    tester::clone_menu_bindings_to_window $menu $w $Mp $M
    
    
    set ftop [ttk::frame .ftop]
    set fcommands [ttk::frame .fcommands -relief sunken -borderwidth 2]
    set fcenter [ttk::frame .fcenter]
    set fbottom [ttk::frame .fbottom]
    
    #toolbar    
    set b_new_project [ttk::button $ftop.b_new_project -image [tester::get_image project-new.png] -command [list tester::press_new_project]]
    tooltip::tooltip $b_new_project [_ "Create a new project (a .tester folder with options to run cases, collection of cases, and its logs)"]
    set b_read_project [ttk::button $ftop.b_read_project -image [tester::get_image project-open.png] -command [list tester::press_read_project]]
    tooltip::tooltip $b_read_project [_ "Select the .tester folder that define a project (options to run cases, collection of cases, and its logs)"]    
    set b_case_new [ttk::button $ftop.b_case_new -image [tester::get_image case-new.png] -command [list tester::define_case_win ""]]
    tooltip::tooltip $b_case_new [_ "Open a window to define a new tester case"]
    set b_save [ttk::button $ftop.b_save -image [tester::get_image document-save.png] -command [list tester::save]]
    tooltip::tooltip $b_save [_ "Save the document (definition of cases and test results)"]    
    set b_separator_0 [ttk::separator $ftop.separator_0 -orient vertical]
    
    set b_upload_cases [ttk::button $ftop.b_upload_cases -image [tester::get_image stock_insert-file.png] -command [list tester::upload_cases]]    
    tooltip::tooltip $b_upload_cases [_ "Upload tester cases defined in xml files"]
    set b_delete_cases [ttk::button $ftop.b_delete_cases -image [tester::get_image stock_delete.png] -command [list tester::delete_selected_cases]]    
    tooltip::tooltip $b_delete_cases [_ "Delete the selected tester cases"]
    set b_preferences [ttk::button $ftop.b_preferences -image [tester::get_image preferences.png] -command [list tester::preferences_win]]    
    tooltip::tooltip $b_preferences [_ "Open the preferences window"]
    set b_separator_1 [ttk::separator $ftop.separator_1 -orient vertical]
    set b_play [ttk::button $ftop.b_play]
    tooltip::tooltip $b_play [_ "Run all tester cases (avoiding filtered)"]
    set b_stop [ttk::button $ftop.b_stop -image [tester::get_image media-stop.png] -command [list tester::press_stop]]    
    tooltip::tooltip $b_stop [_ "Stop running cases"]    
    set b_separator_2 [ttk::separator $ftop.separator_2 -orient vertical]
    if { $preferences(test_gid) } {
        set b_edit_batchfile [ttk::button $ftop.b_edit_batchfile -image [tester::get_image gnome-mime-text.png] -command [list tester::edit_batchfile_selection]]
        tooltip::tooltip $b_edit_batchfile [_ "Edit the batch file of the selected cases"]
    }
    set b_chart [ttk::button $ftop.b_chart -image [tester::get_image chart.png] -command [list tester::show_graphs_analisis_selection]]
    tooltip::tooltip $b_chart [_ "Create graphs of the results of the test along the time for the selected cases"]
    set b_cause_fail [ttk::button $ftop.b_cause_fail -image [tester::get_image logviewer.png] -command [list tester::analize_cause_fail_selection]]
    tooltip::tooltip $b_cause_fail [_ "Try to find the cause of the fail for the selected cases"]
        
    set b_help [ttk::button $ftop.b_help -image [tester::get_image help.png] -command [list tester::help]]
    tooltip::tooltip $b_help [_ "Open the documentation"]
    
    set f_find [ttk::frame $ftop.f_find]
    tester::find_win
    if { $preferences(test_gid) } {
        grid $b_new_project $b_read_project $b_save $b_separator_0 $b_case_new $b_upload_cases $b_delete_cases $b_preferences $b_separator_1 $b_play $b_stop $b_separator_2 $b_edit_batchfile $b_chart $b_cause_fail $b_help $f_find -sticky nsw -padx 0
        set column_find 16
    } else {
        grid $b_new_project $b_read_project $b_save $b_separator_0 $b_case_new $b_upload_cases $b_delete_cases $b_preferences $b_separator_1 $b_play $b_stop $b_separator_2 $b_chart $b_cause_fail $b_help $f_find -sticky nsw -padx 0
        set column_find 15
    }
    grid configure $f_find -sticky nse
    grid columnconfigure $f_find 0 -weight 1
    grid rowconfigure $f_find 0 -weight 1
    
    grid configure $b_separator_0 $b_separator_1 $b_separator_2 -padx 2
    set button(play) $b_play
    set button(stop) $b_stop
    
    tester::gui_enable_play
    
    #commands toolbar
    set fm [ttk::frame $fcommands.fm]
    ttk::scrollbar $fm.yscroll -takefocus 0 -command [list $fm.messages yview] -orient vertical
    listbox $fm.messages -takefocus 0 -yscroll [list $fm.yscroll set] -selectmode single -height 2
    grid $fm.messages $fm.yscroll -sticky ew
    grid configure $fm.yscroll -sticky ns
    set fc [ttk::frame $fcommands.fc]
    label $fc.lcommand -text [_ "Command"]:
    entry $fc.command
    grid $fc.lcommand $fc.command -sticky ew    
    grid configure $fc.lcommand -sticky w
    grid $fm -sticky ew
    set show_command 1
    if { $show_command } {
        grid $fc -sticky ew
    }
    grid columnconfigure $fm 0 -weight 1
    grid columnconfigure $fc 1 -weight 1
    grid columnconfigure $fcommands 0 -weight 1
    bind $fc.command <Return> [list tester::command_on_return %W]
    bind $fc.command <Up> [list tester::command_on_up %W]
    bind $fc.command <Down> [list tester::command_on_down %W]
    focus $fc.command     

    # trick to be able to add to a tab a close button, and identify that the element of the style is the image
    ttk::style layout TNotebook.Tab {
        Notebook.tab -children {
            Notebook.padding -side top -children {
                Notebook.focus -side top -children {
                    Notebook.text -side left
                    Notebook.image -side right -sticky nse
                }
            }
        }
    }
    
    set nb [ttk::notebook .fcenter.nb]
    set test [ttk::frame $nb.test]
    $nb add $test -text [_ "Test cases"] -sticky nsew
    bind $nb <ButtonPress-1> [list +tester::on_button_press_1_notebook %W %x %y]
    bind $nb <ButtonPress-$::tester_right_button> [list +tester::show_menu_tab %W %x %y]
    
    set w_aux [listbox .listbox]    
    set selectforeground [$w_aux cget -selectforeground]  
    set selectbackground [$w_aux cget -selectbackground] 
    set font [$w_aux cget -font]
    destroy $w_aux
    
    set fr1 [ttk::frame $test.fr1]
    set vsb $fr1.vsb1
    set hsb $fr1.hsb1    
    set tree [treectrl $fr1.tree \
            -selectmode extended -showheader 1 \
            -showroot 0 -showbutton 1 -showrootbutton 0 \
            -width 1400 -height 700 -borderwidth 0 \
            -showlines 1 -indent 25 -itemheight 15 -font $font \
            -xscrollcommand [list $hsb set] -yscrollcommand [list $vsb set] \
            -xscrollincrement 20 -yscrollincrement 20] 
    ttk::scrollbar $vsb -orient vertical -command [list $tree yview]
    ttk::scrollbar $hsb -orient horizontal -command [list $tree xview]
    
    $tree column create -width 400 -text [_ "Cases"] -justify left
    $tree column create -width 40 -text [_ "Result"] -justify right
    $tree column create -width 120 -text [_ "Time (seconds)"] -justify right
    $tree column create -width 120 -text [_ "Memory (MB)"] -justify right
    $tree column create -width 120 -text [_ "Test date"] -justify right
    $tree column create -width 120 -text [_ "Min. time (seconds)"] -justify right
    $tree column create -width 120 -text [_ "Min. memory (MB)"] -justify right
    $tree column create -width 120 -text [_ "Ok date"] -justify right
    $tree column create -width 220 -text [_ "Case ID"] -justify right
    $tree configure -treecolumn 0
    
    $tree header configure 0 1 -arrow up    
    
    #this state could be used to automatically show the appropiated image ok or warning
    $tree item state define test_done
    $tree item state define test_fail
    $tree item state define test_crash
    $tree item state define test_run
    $tree item state define test_warning_time
    $tree item state define test_warning_memory
    $tree item state define test_case
    $tree item state define test_folder
    
    #to create child nodes on demand, only when user open them
    $tree notify bind $tree <Expand-before> {tester::tree_create_childs %I}
    $tree notify bind $tree <Expand-after> {tester::tree_expand_after %T %I}
    $tree notify bind $tree <Collapse-after> {tester::tree_collapse_after %T %I}
    
    $tree notify install <Header-invoke>
    $tree notify bind $tree <Header-invoke> {tester::tree_sort %T %H %C}
    
    # fbottom
    #set label_message [ttk::label $fbottom.label_message -text "" -textvariable ::tester::message -width 100]        
    set progress_bar [ttk::progressbar $fbottom.progress_bar -variable ::tester::progress -mode determinate]   
    set f_checkbox [ttk::frame $fbottom.f_checkbox -relief sunken -borderwidth 2]    
    set cb_show_as_tree [ttk::checkbutton $f_checkbox.cb_show_as_tree -text [_ "Show as tree"] -variable tester::preferences(show_as_tree) -command tester::fill_tree]
    tooltip::tooltip $cb_show_as_tree [_ "To show tests cases as tree or as table"]    
    set cb_see_running_case [ttk::checkbutton $f_checkbox.cb_see_running_case -text [_ "see running case"] -variable ::tester::preferences(show_current_case)]
    tooltip::tooltip $cb_see_running_case [_ "To set visible in the tree the case currently running"]   
    set f_ok [ttk::frame $fbottom.f_ok -relief sunken -borderwidth 2]
    set label_ok [ttk::label $f_ok.label_ok -text [_ "Ok"]:]
    set label_count_ok [ttk::label $f_ok.label_count_ok -textvariable ::tester::tested_cases(ok) -foreground green]
    set f_fail [ttk::frame $fbottom.f_fail -relief sunken -borderwidth 2]
    set label_fail [ttk::label $f_fail.label_fail -text [_ "Fail"]:]
    set label_count_fail [ttk::label $f_fail.label_count_fail -textvariable ::tester::tested_cases(fail) -foreground red]
    set f_untested [ttk::frame $fbottom.f_untested -relief sunken -borderwidth 2]
    set label_untested [ttk::label $f_untested.label_untested -text [_ "Untested"]:]
    set label_count_untested [ttk::label $f_untested.label_count_untested -textvariable ::tester::tested_cases(untested) -foreground gray]
        
    grid $tree $vsb -sticky nsew
    grid configure $vsb -sticky ns
    grid $hsb -sticky ew
    grid remove $vsb $hsb
    bind $tree <Configure> [list tester::configure_scrollbars $tree $hsb $vsb]
    
    grid columnconfigure $test 0 -weight 1
    grid rowconfigure $test 0 -weight 1
    grid $fr1 -sticky nsew
    grid columnconfigure $fr1 0 -weight 1
    grid rowconfigure $fr1 0 -weight 1
    grid $cb_show_as_tree $cb_see_running_case -sticky e
    grid $label_ok $label_count_ok -sticky e
    grid $label_fail $label_count_fail -sticky e
    grid $label_untested $label_count_untested -sticky e
    grid $progress_bar $f_checkbox $f_ok $f_fail $f_untested -sticky ew -padx 2
    grid columnconfigure $fbottom 0 -weight 1    
    
    grid $nb -sticky nsew
    
    grid $ftop -sticky new
    grid $fcenter -sticky nsew
    grid $fcommands -sticky new
    grid $fbottom -sticky sew
    grid columnconfigure $ftop $column_find -weight 1
    grid columnconfigure $fcenter 0 -weight 1
    grid rowconfigure $fcenter 0 -weight 1
    #grid columnconfigure $fbottom 0 -weight 1
    grid columnconfigure $w 0 -weight 1
    grid rowconfigure $w 1 -weight 1
        
    set cmd "$progress_bar configure -maximum \$tester::maxprogress"
    trace add variable tester::maxprogress write "$cmd ;#"
    bind $progress_bar <Destroy> [list trace remove variable tester::maxprogress write "$cmd ;#"]
    
    ######################################################### START menu contextual
    
    bind $tree <ButtonPress-$::tester_right_button> [list tester::show_menu_tree_and_select_click %W 0 %x %y]
    bind $tree <Double-1> [list tester::edit_selected_case]
    #bind $tree <F2> [list tester::edit_selected_case]
    bind $tree <Delete> [list tester::delete_selected_cases]
    bind $tree <KeyPress> [list tester::tree_keypress %K %A]
    bind $tree <$M-c> [list tester::clipboard_copy_tree]
        
    ######################################################## END menu contextual
    $tree state define emphasis     
    $tree element create e_image image -image [list [tester::get_image clock.png] {!test_done test_run} \
                                                   [tester::get_image crash.png] {test_done test_fail test_crash} \
                                                   [tester::get_image fail.png] {test_done test_fail} \
                                                   [tester::get_image ok.png] {test_done}]    
    $tree element create e_image_category image -image [list [tester::get_image case.png] {test_case} [tester::get_image case_folder.png] {test_folder}]    
    set bfont [concat [font actual [$tree cget -font]] [list -weight bold]]
    
    
    $tree element create e_text_sel text -lines 1 \
        -fill [list grey !enabled $selectforeground {selected focus}] -font [list $bfont emphasis]
    $tree element create e_rect rect -fill \
        [list $selectbackground {selected focus} gray90 {selected !focus}] \
        -showfocus yes -open we
    $tree element create e_text_normal text -lines 1 -datatype string
    $tree element create e_text_date text -lines 1 -datatype time -format {%H:%M:%S %m/%d/%Y}
    $tree element create e_text_test_fail text -lines 1 -datatype string \
        -fill {blue {test_run} \
                   pink {test_done test_fail test_crash} \
                   red {test_done test_fail} \
                   green {test_done}}
    $tree element create e_text_test_time text -lines 1 -datatype string \
        -fill {blue {test_run} \
                   pink {test_done test_fail test_crash} \
                   red {test_done test_fail} \
                   orange {test_done test_warning_time} \
                   green {test_done}}
    $tree element create e_text_test_memory text -lines 1 -datatype string \
        -fill {blue {test_run} \
                   pink {test_done test_fail test_crash} \
                   red {test_done test_fail} \
                   orange {test_done test_warning_memory} \
                   green {test_done}}
    
    set S [$tree style create style_image_text -orient horizontal]
    $tree style elements $S [list e_rect e_image e_image_category e_text_sel]
    $tree style layout $S e_image -expand ns
    $tree style layout $S e_image_category -expand ns    
    $tree style layout $S e_text_sel -padx {4 0} -squeeze x -expand ns -iexpand nsx -sticky w
    $tree style layout $S e_rect -union [list e_text_sel] -iexpand nswe -ipadx 2  
    
    foreach category {normal date test_fail test_time test_memory} {
        set S [$tree style create style_$category -orient horizontal]
        $tree style elements $S [list e_rect e_text_$category]
        $tree style layout $S e_text_$category -sticky e
        $tree style layout $S e_rect -union [list e_text_$category] -iexpand nswe -ipadx 2
    }  
    
    #tester::fill_tree
    tester::fill_menu_recent_projects
    return 0
}

proc tester::fill_menu_recent_projects { } {
    variable private_options
    variable ini
    if { !$private_options(gui) } {
        return
    }
    if { ![info exists private_options(menu_recent_projects)] || ![winfo exists $private_options(menu_recent_projects)] } {
        return 1
    }
    $private_options(menu_recent_projects) delete 0 end
    foreach project_path [tester::get_recent_projects] {
        set label $project_path
        if { [string length $label] > 80 } {
            set label ...[string range $label end-77 end]
        }
        $private_options(menu_recent_projects) add command -label $label -command [list tester::read_project $project_path]
    }
}

proc tester::destroy_win { w } {    
    if { [tester::must_save] } {
        set answer [tk_messageBox -icon question -type yesnocancel -message [_ "Save changes before exit?"] -title [_ "Exit tester"]...]
        if { $answer == "yes" } {
            tester::save           
        } elseif { $answer == "cancel" } { 
            return 1
        }
    }
    tester::exit    
    return 0
}

proc tester::set_message { txt {self_clear 1} } {
    variable private_options
    if { !$private_options(gui) } {
        return 1
    }
    #variable message
    #after cancel set tester::message ""
    #set message $txt
    #if { $self_clear } {
    #    after 10000 [list set tester::message ""]
    #}
    set w .fcommands.fm.messages
    $w insert end $txt
    $w yview [expr [$w size]-2]
    return 0
}

#trick to click-right button and select the new item or maintain prev selection and show contextual menu
proc tester::show_menu_tree_and_select_click { tree item x y } {
  if { ![$tree selection includes "nearest $x $y"] } {
    TreeCtrl::ButtonPress1 $tree $x $y
  }
  tester::show_menu_tree $tree $item $x $y
}

#contextual application menu
proc tester::show_menu_tree { tree item x y } {
    variable preferences
    variable allowed_plaforms
    set m .menu_contextual
    
    if { [winfo exists $m] } {
        destroy $m
    }
    menu $m -tearoff no
    $m add command -label [_ "Run selection"] -command [list tester::run_selection 0]
    if { $preferences(test_gid) } {
        $m add command -label [_ "Run selection with window"] -command [list tester::run_selection 1]
    }
    
    if { $::tcl_platform(platform) != "windows" } {
        menu $m.m_run_with -tearoff 0
        foreach opt [ list debug release "valgrind debug (xml)" "valgrind debug (txt)" "valgrind release (xml)" "valgrind release (txt)" "sanitize (txt)"] {
            $m.m_run_with add command -label [ string totitle $opt] -command [ list tester::run_selection 0 $opt]
        }
        $m add cascade -label [_ "Run diagnostics with"] -menu $m.m_run_with
    }
    
    $m add command -label [_ "Edit case"] -command [list tester::edit_selected_case]
    $m add command -label [_ "Delete selection"] -command [list tester::delete_selected_cases]    
    $m add cascade -label [_ "Set field selection"] -menu $m.set_case    
    menu $m.set_case -tearoff no
    $m.set_case add cascade -label [_ "Fail accepted"] -menu $m.set_case.fail_accepted
    menu $m.set_case.fail_accepted -tearoff no
    $m.set_case.fail_accepted add command -label [_ "Yes"] -command [list tester::set_case_definition_field_selected_cases fail_accepted 1]    
    $m.set_case.fail_accepted add command -label [_ "No"] -command [list tester::set_case_definition_field_selected_cases fail_accepted 0]    
    
    $m.set_case add cascade -label [_ "Fail random"] -menu $m.set_case.fail_random
    menu $m.set_case.fail_random -tearoff no
    $m.set_case.fail_random add command -label [_ "Yes"] -command [list tester::set_case_definition_field_selected_cases fail_random 1]    
    $m.set_case.fail_random add command -label [_ "No"] -command [list tester::set_case_definition_field_selected_cases fail_random 0]    
    
    $m.set_case add cascade -label [_ "Platform require"] -menu $m.set_case.platform_require
    menu $m.set_case.platform_require -tearoff no
    foreach platform [concat $allowed_plaforms {{* 64} {Windows *} {Linux *}}] {
        $m.set_case.platform_require add command -label $platform -command [list tester::set_case_definition_field_selected_cases platform_require $platform]
    }
    $m.set_case.platform_require add command -label Any -command [list tester::set_case_definition_field_selected_cases platform_require ""]
    $m.set_case add cascade -label [_ "Branch require"] -menu $m.set_case.branch_require
    menu $m.set_case.branch_require -tearoff no
    $m.set_case.branch_require add command -label [_ "Developer"] -command [list tester::set_case_definition_field_selected_cases branch_require developer]    
    $m.set_case.branch_require add command -label [_ "Official"] -command [list tester::set_case_definition_field_selected_cases branch_require official]   
    $m.set_case.branch_require add command -label [_ "Any"] -command [list tester::set_case_definition_field_selected_cases branch_require ""]   
    
    $m add command -label [_ "Select all"] -command [list tester::modifyselection all]
    $m add command -label [_ "Invert Selection"] -command [list tester::modifyselection invert] 
    if { $preferences(test_gid) } {
        $m add command -label [_ "Run selection with window"] -command [list tester::run_selection 1]
        $m add command -label [_ "Edit batch file selection"] -command [list tester::edit_batchfile_selection] 
    }
    #$m add command -label [_ "Edit xmlfile selection"] -command [list tester::edit_xmlfile_selection] 
    $m add command -label [_ "Open Outputfiles"] -command [list tester::open_output_files_selection]
    if { $::tcl_platform(platform) != "windows" } {
        menu $m.m_valgrind_open -tearoff 0
        $m.m_valgrind_open add command -label "valgrind txt" -command [ list tester::open_valgrind_output_selection by_extension txt]
        $m.m_valgrind_open add command -label "valgrind in VS Code (txt)" -command [ list tester::open_valgrind_output_selection code txt]
        $m.m_valgrind_open add command -label "valgrind in VS Code (xml)" -command [ list tester::open_valgrind_output_selection code xml]
        $m.m_valgrind_open add command -label "valgrind in Valkyrie" -command [ list tester::open_valgrind_output_selection valkyrie xml]
        $m.m_valgrind_open add command -label "sanitize txt output" -command [ list tester::open_sanitize_output_selection by_extension]
        $m.m_valgrind_open add command -label "sanitize in VS Code (txt)" -command [ list tester::open_sanitize_output_selection code]
        $m add cascade -label [_ "Open diagnostics"] -menu $m.m_valgrind_open
        $m add command -label [_ "Clear diagnostics files"] -command [ list tester::clear_diagnostics_files]
    }

    $m add command -label [_ "Graphs along the time"] -command [list tester::show_graphs_analisis_selection]
    $m add command -label [_ "Analize fail cause"] -command [list tester::analize_cause_fail_selection]
    $m add command -label [_ "Analize if random"] -command [list tester::classify_random_log_selection]
    if { $preferences(show_as_tree) } {
        $m add command -label [_ "Collapse all cases"] -command [list tester::tree_collapse_all]
        $m add command -label [_ "Expand all cases"] -command [list tester::tree_expand_all]
    }
    $m add command -label [_ "Help"] -command [list tester::help_selection]
    
    ## set xx [expr [winfo rootx $tree]+$x+50]
    ## set yy [expr [winfo rooty $tree]+$y]
    
    # add some offset like other contextual menus, like VScode and firefox
    set xx [expr [winfo rootx $tree]+$x+100]
    set yy [expr [winfo rooty $tree]+$y+20]
    
    tk_popup $m $xx $yy 0
    # do no select the first entry by default, to avoid mistakes
    $m activate none
}

proc tester::open_output_files_selection { } {    
    set case_ids [tester::tree_get_selection_case_ids]   
    foreach case_id $case_ids {
        set key outputfiles
        if { [tester::exists_variable $case_id $key] } {
            foreach filename [tester::get_variable $case_id $key] {
                if { [tester::is_valid_file $filename]} {
                    gid_cross_platform::open_by_extension $filename
                } else {
                    tester::message [_ "Filename '%s' not found or is not a valid file" [file join [pwd] $filename]]
                }
            }
        } else {
            tester::message [_ "outputfiles field in test description not defined"]
        }
    }
}
proc tester::open_valgrind_output_selection { editor extension } {    
    set case_ids [tester::tree_get_selection_case_ids]   
    foreach case_id $case_ids {
        tester::valgrind_open_output $case_id $editor $extension
    }
}
proc tester::open_sanitize_output_selection { editor } {    
    set case_ids [tester::tree_get_selection_case_ids]   
    foreach case_id $case_ids {
        tester::sanitize_open_output $case_id $editor
    }
}

proc tester::clear_diagnostics_files { } {
    set case_ids [tester::tree_get_selection_case_ids]   
    foreach case_id $case_ids {
        set lst_files [ list \
                            [ tester::sanitize_get_output_filename $case_id] \
                            [ tester::valgrind_get_output_filename $case_id txt] \
                            [ tester::valgrind_get_output_filename $case_id xml] \
                            ]
        file delete -force {*}$lst_files
    }                            
}

proc tester::upload_cases { } {
    set new_case 0
    set num_cases [tester::press_open_file $new_case]
    tester::set_message [_ "Uploaded %s cases" $num_cases]
}

proc tester::press_read_project { } {
    set initialdir [file dirname [lindex [tester::get_recent_projects] 0]]
    set project [tk_chooseDirectory  -parent . -title [_ "Read project (.tester folder)"] -initialdir $initialdir]
    if { $project != "" } {       
        return [tester::read_project $project]
    }
    return 0
}

proc tester::press_new_project { } {
    set initialdir [file dirname [lindex [tester::get_recent_projects] 0]]
    set project_path [tk_chooseDirectory  -parent . -title [_ "New project (.tester folder)"] -initialdir $initialdir]              
    return [tester::new_project $project_path]
}

proc tester::press_open_file { new_case } {
    variable preferences
    set filestoread [tk_getOpenFile -filetypes {{{Tester xml Files} {.xml}} {{All types} {.*}}} \
            -initialdir $preferences(initialdir) -parent . -title "browser" -multiple 1]
    if { $filestoread != "" } {
        set preferences(initialdir) [file dirname [lindex $filestoread 0]]
        return [tester::open_files $filestoread $new_case]
    }
    return 0
}

proc tester::press_save_file { } {
    variable private_options
    variable preferences
    set filename [tk_getSaveFile -filetypes {{{Tester xml Files} {.xml}} {{All types} {.*}}} \
            -initialdir $preferences(initialdir) -parent . -title "browser" -defaultextension .xml]
    if { $filename != "" } {
        if { [file exists $filename] } {
            set txt [_ "File '%s' exists. Overwrite?" $filename]
            set reply [tk_messageBox -message $txt -icon question -default no -type yesno]
            if { $reply == "no"  } {
                return 1
            }
        }
    }
    if { $filename != "" } {        
        set preferences(initialdir) [file dirname $filename]
        tester::save_xml_file $private_options(xml_document) $filename
    }
    return 0
}

proc tester::new_document { } {
    variable private_options
    if { $private_options(xml_document) != "" } {
        $private_options(xml_document) delete     
    }
    set private_options(xml_document) [dom parse "<cases version='1.0'/>"]
    set private_options(must_save_document) 1
}

proc tester::read_document { } {
    variable private_options
    set err [ catch {
            tester::read_cases_xml_file [tester::get_document_filename]
        } err_txt]
    if { $err} {
        tester::message_box "Error parsing XML file: $err_txt" error
    }
    set private_options(must_save_document) 0
    set private_options(mtime_read_document) [clock seconds]
}

proc tester::must_save { } {
    variable private_options    
    set changes 0
    if { $private_options(must_save_document) || $private_options(must_save_digest_results)} {
        set changes 1
    }
    return $changes
}

proc tester::save { } {
    variable private_options
    if { $private_options(must_save_document) } {
        tester::save_document
    }
    if { $private_options(must_save_digest_results) } {
        tester::save_digest_results
    }    
    tester::set_message [_ "Document saved in folder '%s'" [file dirname [tester::get_document_filename]]]
    return 0
}

proc tester::save_document { } {
    variable private_options
    set dir [tester::get_full_case_path xmls]
    if { ![file exists $dir] } {
        file mkdir $dir
    }            
    tester::save_xml_file $private_options(xml_document) [tester::get_document_filename]    
    set private_options(must_save_document) 0
    set private_options(mtime_read_document) [clock seconds] ;#update this time to avoid offer to be reloaded
}

proc tester::save_document_as { filename } {
    variable private_options
    tester::save_xml_file $private_options(xml_document) $filename
    return 0
}

proc tester::check_if_must_reload { } {
    variable private_options
    if { [info exists private_options(avoid_reenter)] && $private_options(avoid_reenter) } {
        return 1
    }
    set private_options(avoid_reenter) 1    
    set filename [tester::get_document_filename]
    if { [file exists $filename] } {
        set file_mtime [file mtime $filename]
        if { [info exists private_options(mtime_read_document)] } {
            if { $file_mtime > $private_options(mtime_read_document) } {
                if { $private_options(must_save_document) } {
                    set text [_ "Project has unsaved changes and has been changed externally. Do you want to reload it and lose the changes?"]
                } else {
                    set text [_ "Project has been changed externally. Do you want to reload it?"]
                }
                set answer [tk_messageBox -icon question -type yesno -message $text -title [_ "Project changed"]...]
                if { $answer == "yes" } {
                    after idle [list tester::read_project $private_options(project_path)]
                } else {
                    set private_options(mtime_read_document) $file_mtime
                }
            }
        }
    }
    set private_options(avoid_reenter) 0
    return 0
}

proc tester::open_files { filestoread new_case } {
    variable private_options
    if { $new_case } {
        tester::kill_all_process
        #tester::gui_enable_play
        tester::array_reset
    } 
    #parse all files and store all in doc, adding also 'tags' node to the cases based on filename
    if { $new_case } {
        if { $private_options(xml_document) != "" } {
            $private_options(xml_document) delete            
        }
        set xml_document_to_add ""
    } else {
        set xml_document_to_add $private_options(xml_document)
    }
    set private_options(xml_document) [tester::merge_xml_files $filestoread $xml_document_to_add]
    
    set num_cases [tester::read_cases_xml_document $private_options(xml_document)]
    tester::fill_tree
    return $num_cases
}

proc tester::gui_disable_play { } {
    variable private_options
    variable button
    variable cancel_process
    variable pause_process
    if { $private_options(gui) } {
        $button(play) configure -state disabled
        $button(stop) configure -state disabled
        update
    }
    set cancel_process 1
    set pause_process 1
}

proc tester::gui_enable_pause { } {
    variable private_options
    variable button
    variable cancel_process
    variable pause_process
    if { $private_options(gui) } {
        $button(play) configure -state normal -image [tester::get_image media-pause.png] -command [list tester::press_pause]
        tooltip::tooltip $button(play) [_ "Pause run tester cases"]
        $button(stop) configure -state normal
        update
    }
    set cancel_process 0
    set pause_process 0
}

proc tester::gui_enable_resume { } {
    variable private_options
    variable button  
    variable cancel_process
    variable pause_process
    if { $private_options(gui) } {
        $button(play) configure -state normal -image [tester::get_image media-play.png] -command [list tester::press_resume]
        tooltip::tooltip $button(play) [_ "Resume run tester cases"]
        $button(stop) configure -state normal
        update
    }
    set cancel_process 0
    set pause_process 1
}

proc tester::gui_enable_play { } {
    variable private_options
    variable button
    variable cancel_process
    variable pause_process
    if { $private_options(gui) } {
        $button(play) configure -state normal -image [tester::get_image media-play.png] -command [list tester::press_run 0]
        tooltip::tooltip $button(play) [_ "Run all tester cases (avoiding filtered)"]
        $button(stop) configure -state disabled
        update
    }
    set cancel_process 0
    set pause_process 0
}

proc tester::press_run { force_with_window } {
    tester::gui_enable_pause
    set filtered_cases [tester::filter_case_ids [tester::case_ids]]
    tester::run $filtered_cases $force_with_window
}

proc tester::press_stop { } {
    #tester::gui_disable_play
    tester::kill_all_process
    #tester::gui_enable_play
}

proc tester::press_pause { } {  
    variable pause_process
    tester::gui_enable_resume
    
}

proc tester::press_resume { } {
    tester::gui_enable_pause
}

proc tester::kill_all_process { } {       
    variable nprocess
    variable pause_process
    variable cancel_process
    set prev_pause_process $pause_process
    set pause_process 1 ;#to avoid start new processes
    set cancel_process 1 ;#to avoid start new processes
    set errors ""
    foreach case_id [tester::case_ids] {
        if { [tester::exists_variable $case_id pid] } {            
            set pid [tester::get_variable $case_id pid]
            if { [gid_cross_platform::process_exists $pid] } {
                gid_cross_platform::cancel_track_process $pid
                if { $::tcl_platform(platform) == "windows" } {
                    #kill also its recursive child process
                    set child_pids [gid_cross_platform::get_process_childs $pid 0]
                    foreach child_pid $child_pids {
                        if { [gid_cross_platform::process_exists $child_pid] } {
                            if { [catch {gid_cross_platform::end_process $child_pid} err] } {
                                if { [gid_cross_platform::process_exists $child_pid] } {
                                    tester::puts_log_error "case $case_id can't end child process=$child_pid, err=$err"                        
                                    lappend errors "case $case_id can't end child process=$child_pid"
                                }
                            }
                        }
                    }
                }
                set process_killed 0
                if { [catch {set process_killed [gid_cross_platform::end_process $pid]} err] } {
                    if { [gid_cross_platform::process_exists $pid] } {
                        set process_killed 0
                        tester::puts_log_error "case $case_id can't end process=$pid, err=$err"                        
                        lappend errors "case $case_id can't end process=$pid"                        
                    }
                }                
                tester::after_execute_test $pid "userstop" $case_id                                
            }
            #tester::array_unset $case_id pid            
        }
    } 
    set pause_process $prev_pause_process
    #set nprocess 0
    if { $errors != "" } {
        tester::message_box $errors error
    } 
}

proc tester::modifyselection { type } {
    variable tree
    variable tree_item_case ;#to store the tree item of a case id
    if { $type == "all" } {
        $tree selection clear
        $tree selection add "tag case"
    } elseif { $type == "invert" } {
        set current_selection [$tree selection get]
        $tree selection clear
        $tree selection add "tag case"
        $tree selection modify "" $current_selection 
    }
}

proc tester::get_report_html { {items -ALL-} } {    
    variable preferences
    
    set keysfixed {exe args}
    set keysresult ""
    set key_outputfiles 0
    set key_valgrindfiles 0
    set key_sanitizefiles 0
    foreach case_id [tester::case_ids] {
        if { ![tester::exists_variable $case_id results] } {        
            continue
        }
        foreach {item value} [tester::get_variable $case_id results] {
            if { [lsearch $keysresult $item] == -1 } {
                lappend keysresult $item
            }
        }
        set lst_out {}
        if { [tester::exists_variable $case_id outputfiles] } {
            set lst_out [tester::get_variable $case_id outputfiles]
        }
        if { [llength $lst_out] != 0} {
            set key_outputfiles 1
        }
        
        if { $::tcl_platform(platform) != "windows" } {
            set val_file_xml [ tester::valgrind_get_output_filename $case_id xml]
            set val_file_txt [ tester::valgrind_get_output_filename $case_id txt]
            if { [ file exists $val_file_xml] || [ file exists $val_file_txt]} {
                set key_valgrindfiles 1
            }
            set san_file_txt [ tester::sanitize_get_output_filename $case_id txt]
            if { [ file exists $san_file_txt]} {
                set key_sanitizefiles 1
            }
        }
    }
    set keysresult [lsort -dictionary $keysresult]
    if { $items == "-ALL-" } {
        set selectedkeys $keysresult
    } else {
        set selectedkeys ""
        foreach item $items {
            if { [lsearch -sorted $keysresult $item] != -1 } {
                lappend selectedkeys $item
            }
        }
        if { $key_outputfiles } {
            if { [lsearch $items outputfiles] == -1} {
                set key_outputfiles 0
            }
        }
    }
    
    set color "blue"
    
    set text "<table border=\"1\" align=\"center\" cellpadding=4>\n"
    append text "<tr bgcolor=\"#bbbbbb\">"
    foreach key [concat {id exe args} $selectedkeys] {
        append text "<td><b>$key</b></td>"        
    }
    if { $key_outputfiles} {
        append text "<td><b>outputfiles</b></td>"
    }
    if { $key_valgrindfiles} {
        append text "<td><b>valgrind info</b></td>"
    }
    if { $key_sanitizefiles} {
        append text "<td><b>sanitize info</b></td>"
    }
    append text "</tr>\n"
    
    #array warn #warnings by owner    
    set last_tags ""
    foreach case_id [tester::case_ids] {
        if { ![tester::exists_variable $case_id results] } {
            continue
        }
        set my_exe [tester::get_variable $case_id exe]
        if { $my_exe == ""} {
            continue
        }        
        if { $last_tags != [tester::get_variable $case_id tags]} {
            set num_columns [expr [llength $selectedkeys]+4]
            set text_tags [join [tester::get_variable $case_id tags] /]
            append text "<tr><td bgcolor=\"eeeeee\" colspan=$num_columns align=center>$text_tags</td></tr>"
            set last_tags [tester::get_variable $case_id tags]
        }
        
        array unset r
        array set r [tester::get_variable $case_id results]
        set result [tester::evaluate_checks $case_id]
        if { $result == "untested" || $result == "running" || $result == "ok" } {
            append text {<tr>}
        } elseif { $result == "fail" || $result == "crash" || $result == "timeout" || $result == "maxmemory" || $result == "userstop" } {
            append text {<tr bgcolor="#ff0000">}            
            lappend warn([tester::get_variable $case_id owner]) $case_id            
        } else {
            append text {<tr>}
        }
        append text "<td>$case_id</td>"
        append text "<td>$my_exe</td>"
        if { [tester::exists_variable $case_id args] } {
            append text "<td>[tester::get_variable $case_id args]</td>"
        }
        if { [tester::exists_variable $case_id batch] } {
            append text "<td>[tester::get_variable $case_id batch]</td>"
        }
        foreach key $selectedkeys {
            if { [info exists r($key)] } {
                append text "<td>$r($key)</td>"
            } else {
                append text "<td>-</td>"
            }           
        }
        if { $key_outputfiles} {            
            set lst_out [tester::get_variable $case_id outputfiles]
            set num_outs [llength $lst_out]
            if { $num_outs != 0} {
                append text "<td>"
                set max_horizontal_images $preferences(htmlimagesbyrow)
                # first all images
                append text "<table border=\"0\" align=\"center\"><tr>"
                set num_img 0
                set pos [string length $case_id,]
                foreach of $lst_out {
                    set key [string range $of $pos end]
                    set filename [tester::get_variable $case_id $key]                    
                    if { [tester::is_image_file $filename] } {
                        if { $num_img && [expr $num_img % $max_horizontal_images] == 0 } {
                            append text "</tr><tr>"
                        }
                        incr num_img
                        # tell also the name of the file
                        append text "<td>"
                        append text "<table border=\"0\" align=\"center\"><tr>"
                        append text "<tr><td>"
                        append text "<a href=\"$filename\"><img src=\"$filename\" alt=\"$filename\" border=0 height=192></a>"
                        append text "</td></tr>"
                        append text "<tr><td align=\"center\">$filename</td>"
                        append text "</tr></table>"
                        append text "</td>"
                    }
                }
                if { $num_img} {
                    append text "</tr><tr>"
                }
                # all other                
                foreach of $lst_out {
                    set key [string range $of $pos end]
                    set filename [tester::get_variable $case_id $key]                    
                    if { ![tester::is_image_file $filename] } {
                        append text "<td><a href=\"$filename\">$filename</a></td>"
                    }
                }
                append text "</tr></table>"
                append text "</td>"
            } else {
                append text "<td align=center>N/A</td>"
            }
        }
        if { $key_valgrindfiles} {
            set val_file_xml [ tester::valgrind_get_output_filename $case_id xml]
            set val_file_txt [ tester::valgrind_get_output_filename $case_id txt]
            set ff 0
            append text "<td align=center>"
            if { [ file exists $val_file_xml]} {
                regsub [ pwd]/ $val_file_xml {} val_file_xml
                append text "<a href=\"$val_file_xml\">xml</a>"
                incr ff
            }
            append text "&nbsp;&nbsp;&nbsp;"
            if { [ file exists $val_file_txt]} {
                regsub [ pwd]/ $val_file_txt {} val_file_txt
                append text "<a href=\"$val_file_txt\">txt</a>"
                incr ff
            }
            if { !$ff} {
                append text "N/A"
            }
            append text "</td>"
        }
        if { $key_sanitizefiles} {
            set san_file_txt [ tester::sanitize_get_output_filename $case_id txt]
            if { [ file exists $san_file_txt]} {
                regsub [ pwd]/ $san_file_txt {} san_file_txt
                append text "<a href=\"$san_file_txt\">txt</a>"
            } else {
            append text "<td>N/A</td>"
            }
        }
        append text "</tr>\n"
    }
    append text "</table>\n"
    
    set top "<html><body bgcolor=#ffffff>\n"
    if { [llength [array names warn]]  > 0 } {
        append top {<center>}
        foreach owner [array names warn] {
            append top {<A HREF="mailto:}
            append top $owner
            append top {?subject=Errores%20tester&body=}
            set count 0
            foreach case_id $warn($owner) {
                incr count
                append top {exe:%20}
                append top [regsub -all {\"} $my_exe {%22}]
                if { [tester::exists_variable $case_id args] } {
                    append top {%0D%0Aargs:%20}
                    append top [regsub -all {\"} [tester::get_variable $case_id args] {%22}]
                }
                if { [tester::exists_variable $case_id batch] } {
                    append top {%0D%0Abatch:%20}
                    append top [regsub -all {\"} [tester::get_variable $case_id batch] {%22}]
                }                
                append top {%0D%0A%0D%0A}
            }
            append top {">Send (}
            append top $count
            append top {) errors to }
            append top $owner
            append top {</A><br><br>}
        }
        append top {</center>}
    }
    
    set tail {</body></html>}
    append top $text
    append top $tail
    return $top
}

proc tester::get_platform_information {} {
    set text "<h3>Platform information</h3>\n"
    append text "<table border=\"1\" align=\"center\" cellpadding=4>\n"
    append text "<tr bgcolor=\"#cccccc\">"
    foreach idx [list machine platform os osVersion pointerSize wordSize] {
        append text "<td align=center><b>$idx</b></td>"
    }
    append text "</tr>\n"
    append text "<tr>"
    foreach idx [list machine platform os osVersion pointerSize wordSize] {
        append text "<td align=center>$::tcl_platform($idx)</td>"
    }
    append text "</tr>\n"
    append text "</table>\n"
    return $text
}

proc tester::get_preferences {} {
    variable preferences
    set text "<h3>Preferences</h3>\n"
    append text "<table border=\"1\" align=\"center\" cellpadding=4>\n"
    foreach item [lsort -dictionary [array names preferences]] {
        append text "<tr><td bgcolor=\"#cccccc\" align=right><b>$item</b></td>"
        append text "<td align=center>$preferences($item)</td></tr>\n"
    }
    append text "</table>\n"
    return $text
}

proc tester::save_report_html { {items -ALL-} {filename ""} { view 1} } {    
    if { $filename == "" } {
        set filename [tester::get_tmp_filename .html]
    }
    set fp [open $filename w] 
    if { $fp != "" } {
        
        puts $fp "<h2>Tests run on [clock format [clock seconds]]</h2>"
        puts $fp [tester::get_platform_information]
        puts $fp "<br>"
        puts $fp [tester::get_preferences]
        puts $fp "<br>"
        puts $fp [tester::get_report_html $items]
        close $fp
        if { $view } {
            gid_cross_platform::open_by_extension $filename
        }
    }
}



#preferences window

proc tester::read_preferences {} {
    variable private_options
    variable preferences      
    
    set filename [tester::get_preferences_filename]
    if { [file exists $filename]} {
        set xml [tester::read_file $filename utf-8]        
        if { $xml   != "" } {            
            if { [catch { set document [dom parse $xml] } err] } {
                tester::message_box [_ "Error reading preferences file '%s': %s" $filename $err] error
                return 1
            }
            set root [$document documentElement]    
            set root_nodename [$root nodeName]
            if { $root_nodename == "variables" } { 
                #old initial format
                foreach test [$root childNodes] {
                    set name [$test nodeName]
                    #store also if unknown, to save again 
                    #(for future new names unknow in current version)                    
                    if { $name == "mailsend_username"  || $name == "mailsend_password" } {
                        set preferences($name) [tester::decode [$test text]]
                    } else {
                        set preferences($name) [$test text]   
                    }
                }
            } elseif { $root_nodename == "tester_configuration" } { 
                #store also if unknown, to save again (for future new names unknow in current version)                           
                foreach child_node [$root childNodes] {
                    set child_node_nodename [$child_node nodeName]
                    if { $child_node_nodename == "variables_tester" } { 
                        foreach test [$child_node childNodes] {
                            set name [$test nodeName]
                            set value [$test text]
                            if { $name == "mailsend_username"  || $name == "mailsend_password" } {
                                set value [tester::decode $value]
                            }
                            tester::set_preference $name $value
                        }
                    } elseif { $child_node_nodename == "variables_visual_studio" } { 
                        foreach test [$child_node childNodes] {
                            set name [$test nodeName]
                            set value [$test text]
                            visual_studio::set_preference $name $value
                        }                        
                    } elseif { $child_node_nodename == "variables_git" } { 
                        foreach test [$child_node childNodes] {
                            set name [$test nodeName]
                            set value [$test text]
                            git::set_preference $name $value
                        }                        
                    }
                }
                
            }
            $document delete                                
        }
    }    
    return 0
}

proc tester::trace_preferences_gidshowtclerror { args } {
    variable preferences
    if { $preferences(gidshowtclerror) == 1 } {
        set ::env(GID_SHOW_TCL_ERROR) 1
    } else {
        unset -nocomplain ::env(GID_SHOW_TCL_ERROR)
    }
}

proc tester::set_default_preferences { } {
    variable preferences
    variable preferences_defaults
    array set preferences [array get preferences_defaults]
    visual_studio::set_default_preferences
    git::set_default_preferences
}

proc tester::ask_missing_preferences { } {
    variable private_options
    variable preferences
    variable preferences_defaults
    
    if { $preferences_defaults(platform_provide) == "" } {
        set preferences_defaults(platform_provide) [gid_cross_platform::get_current_platform]
    }
    
    foreach key [array names preferences_defaults] {
        if { ![info exists preferences($key)] } {
            set preferences($key) $preferences_defaults($key)
        }        
    }
    
    if { $preferences(basecasesdir) == "" } {
        set preferences(basecasesdir) [tk_chooseDirectory -title "Choose base folder of cases"]
    }
    if { $preferences(exe) == "" } {
        set types [list {{Executable} {.exe *.bat}} {{All files} *}]
        set preferences(exe) [tk_getOpenFile -filetypes $types -title "Choose default exe or bat to run"]
    }
    if { $preferences(offscreen_exe) == "" } {
        set types [list {{Executable} {.exe *.bat}} {{All files} *}]
        set preferences(offscreen_exe) [tk_getOpenFile -filetypes $types -title "Choose default offscreen exe or bat to run"]
    }                  
    visual_studio::ask_missing_preferences
    git::ask_missing_preferences
}

proc tester::ask_missing_preferences_mailsend { } {
    variable preferences
    package require getstring
    if { $preferences(mailsend_username) == "" } {
        ::getstring::tk_getString .gs preferences(mailsend_username) "mailsend: enter gmail username"
        set preferences(mailsend_username) [string trim $preferences(mailsend_username)]
    }
    if { $preferences(mailsend_password) == "" } {        
        ::getstring::tk_getString .gs preferences(mailsend_password) "mailsend: enter gmail password"
        set preferences(mailsend_password) [string trim $preferences(mailsend_password)]  
    }
}

proc tester::save_preferences_variables { fp } {
    variable preferences
    puts $fp "<variables_tester>"
    foreach name [lsort -dictionary [array names preferences]] {
        if { $name == "mailsend_username"  || $name == "mailsend_password" } {
            puts $fp "  <$name>[tester::encode $preferences($name)]</$name>"    
        } else {
            puts $fp "  <$name>$preferences($name)</$name>"    
        }
    }
    puts $fp "</variables_tester>"
}

proc tester::save_preferences { } {
    variable preferences
    set filename [tester::get_preferences_filename]
    set fp [open $filename w]
    if { $fp != "" } {
        fconfigure $fp -encoding utf-8
        puts $fp {<?xml version="1.0" encoding="utf-8"?>}
        puts $fp "<tester_configuration version='1.0'>"        
        tester::save_preferences_variables $fp    
        visual_studio::save_preferences_variables $fp    
        git::save_preferences_variables $fp    
        puts $fp "</tester_configuration>"
        close $fp
    }
}

proc tester::encode { text } {
    package require blowfish
    package require base64
    return [base64::encode [blowfish::blowfish -mode ecb -dir encrypt -key 673g6sh6gedy4 $text]]
}

proc tester::decode { text } {
    package require blowfish
    package require base64
    #trimrigth to avoid extra spaces provided by the cypher that uses packs of 64 bits
    return [string trimright [blowfish::blowfish -mode ecb -dir decrypt -key 673g6sh6gedy4 [base64::decode $text]]]
}

proc tester::set_filters_state { } {
    variable preferences
    set f .preferences.frm.run.filters
    if { $preferences(enable_filters) } {
        set state normal
    } else {
        set state disabled        
    }
    $f.f.e_opposite_filters configure -state $state
    foreach w [winfo children $f] {
        catch { $w configure -state $state }
    }
    if { $state == "normal" } {
        #avoid set as normal the widged of value of disabled concepts
        foreach item {filter_time filter_memory filter_tags filter_fail filter_fail_accepted filter_fail_random } {
            if { $tester::preferences($item) } {
                $f.e_${item}_value configure -state normal
            } else {
                $f.e_${item}_value configure -state disabled
            }
        }       
    }
}

proc tester::on_change_enable_filters { } {
    tester::set_filters_state
    tester::fill_tree
}

proc tester::on_change_opposite_filters { } {    
    tester::fill_tree
}

proc tester::on_change_filter_date { } {
    tester::fill_tree
}

proc tester::on_change_filter_time { w } {
    variable preferences
    if { $tester::preferences(filter_time) } {
        $w configure -state normal
    } else {
        $w configure -state disabled
    }
    tester::fill_tree
}

proc tester::on_change_filter_memory { w } {
    variable preferences
    if { $tester::preferences(filter_memory) } {
        $w configure -state normal
    } else {
        $w configure -state disabled
    }
    tester::fill_tree
}

proc tester::on_change_filter_tags { w } {
    variable preferences
    if { $tester::preferences(filter_tags) } {
        $w configure -state normal
    } else {
        $w configure -state disabled
    }    
    tester::fill_tree
}

proc tester::on_change_filter_fail { w } {
    variable preferences
    if { $tester::preferences(filter_fail) } {
        $w configure -state normal
    } else {
        $w configure -state disabled
    }
    tester::fill_tree
}

proc tester::on_change_filter_fail_accepted { w } {
    variable preferences
    if { $tester::preferences(filter_fail_accepted) } {
        $w configure -state normal
    } else {
        $w configure -state disabled
    }
    tester::fill_tree
}

proc tester::on_change_filter_fail_random { w } {
    variable preferences
    if { $tester::preferences(filter_fail_random) } {
        $w configure -state normal
    } else {
        $w configure -state disabled
    }
    tester::fill_tree
}

proc tester::on_change_filter_branch_provide { } {        
    tester::update_title
    tester::fill_tree
}

proc tester::on_change_filter_platform_provide { } {    
    tester::update_title
    tester::fill_tree
}

proc tester::create_treectrol { fr1 } {
    set w_aux [listbox .listbox]    
    set selectforeground [$w_aux cget -selectforeground]  
    set selectbackground [$w_aux cget -selectbackground] 
    set font [$w_aux cget -font]
    destroy $w_aux
    
    set vsb $fr1.vsb1
    set hsb $fr1.hsb1    
    set tree [treectrl $fr1.tree \
            -selectmode extended -showheader 1 \
            -showroot 0 -showbutton 1 -showrootbutton 0 \
            -width 240 -height 240 -borderwidth 0 \
            -showlines 1 -indent 25 -itemheight 15 -font $font \
            -xscrollcommand [list $hsb set] -yscrollcommand [list $vsb set] \
            -xscrollincrement 20 -yscrollincrement 20] 
    ttk::scrollbar $vsb -orient vertical -command [list $tree yview]
    ttk::scrollbar $hsb -orient horizontal -command [list $tree xview]
    
    $tree column create -width 50 -text "" -justify right
    $tree column create -width 120 -text [_ "Tag"] -justify right
    
    $tree header configure 0 1 -arrow up
    
    #this state could be used to automatically show the appropiated image ok or warning
    $tree item state define tag_true
    
    $tree notify install <Header-invoke>
    $tree notify bind $tree <Header-invoke> {tester::tree_sort %T %H %C}
    
    grid $tree $vsb -sticky nsew
    grid configure $vsb -sticky ns
    grid $hsb -sticky ew
    grid remove $vsb $hsb
    bind $tree <Configure> [list tester::configure_scrollbars $tree $hsb $vsb]                                      
    
    $tree state define emphasis
    $tree element create e_image image -image [list [tester::get_image ok.png] tag_true]    
    set bfont [concat [font actual [$tree cget -font]] [list -weight bold]]
    
    $tree element create e_text_sel text -lines 1 \
        -fill [list grey !enabled $selectforeground {selected focus}] -font [list $bfont emphasis]
    $tree element create e_rect rect -fill \
        [list $selectbackground {selected focus} gray90 {selected !focus}] \
        -showfocus yes -open we
    
    set S [$tree style create style_image -orient horizontal]
    $tree style elements $S [list e_rect e_image]
    $tree style layout $S e_image -expand ns
    $tree style layout $S e_rect -union [list e_image] -iexpand nswe -ipadx 2
    
    set S [$tree style create style_text -orient horizontal]
    $tree style elements $S [list e_rect e_text_sel]
    $tree style layout $S e_text_sel -padx {4 0} -squeeze x -expand ns -iexpand nsx -sticky w
    $tree style layout $S e_rect -union [list e_text_sel] -iexpand nswe -ipadx 2
    return $tree    
}

proc tester::on_button_1_tree_tags { x y tree } {
    set info [$tree identify $x $y]
    if { [lindex $info 0] == "item" && [llength $info] >= 4 } {
        set item [lindex $info 1]
        set column [lindex $info 3]    
        set tag [$tree item text $item 1]
        if { $column == 0 && $tag != "" } {
            #get the value as the opposite of the selected item
            set value [tester::get_filter_tag $tag]
            if { [tester::get_filter_tag $tag] } {
                set swap_value 0
                set states !tag_true
            } else {
                set swap_value 1
                set states tag_true
            }
            set current_selection [$tree selection get]
            if { ![$tree selection includes $item] } {               
                #if clicked item is not in the selection, select only this item
                $tree selection clear
                $tree selection add $item
                $tree activate $item
            }
            foreach item_selected [$tree selection get] {
                set tag [$tree item text $item_selected 1]
                tester::set_filter_tag $tag $swap_value
                $tree item state set $item_selected $states
            }            
            tester::fill_tree
            return -code break
        }
    }    
}

proc tester::fiter_tags_on_off_selection { tree value } {
    if { $value } {
        set states tag_true
    } else {
        set states !tag_true
    }
    foreach item_selected [$tree selection get] {
        set tag [$tree item text $item_selected 1]
        tester::set_filter_tag $tag $value
        $tree item state set $item_selected $states
    }
    tester::fill_tree
}

proc tester::trace_preferences_filter_time_value { args } {
    variable preferences
    if { [string is double -strict $preferences(filter_time_value)] && $preferences(filter_time_value) > 0 } {
        tester::fill_tree
    }
}

proc tester::trace_preferences_filter_memory_value { args } {
    variable preferences
    if { [string is double -strict $preferences(filter_memory_value)] && $preferences(filter_memory_value) > 0 } {
        tester::fill_tree
    }
}

proc tester::trace_preferences_filter_fail_value { args } {
    variable preferences
    if { $preferences(filter_fail_value) != "" } {
        tester::fill_tree
    }
}

proc tester::trace_preferences_filter_fail_accepted_value { args } {
    variable preferences
    if { $preferences(filter_fail_accepted_value) != "" } {
        tester::fill_tree
    }
}

proc tester::trace_preferences_filter_fail_random_value { args } {
    variable preferences
    if { $preferences(filter_fail_random_value) != "" } {
        tester::fill_tree
    }
}

proc tester::trace_preferences_branch_provide { args } {
    variable preferences
    if { $preferences(branch_provide) != "" } {
        tester::fill_tree
    }
}

proc tester::trace_preferences_platform_provide { args } {
    variable preferences
    if { $preferences(platform_provide) != "" } {
        tester::fill_tree
    }
}

proc tester::show_menu_filter_tags { tree item x y } {
    variable preferences
    set m .menu_contextual_filter_tags 
    
    if { [winfo exists $m] } {
        destroy $m
    }
    menu $m -tearoff no
    $m add command -label [_ "On selection"] -command [list tester::fiter_tags_on_off_selection $tree 1]
    $m add command -label [_ "Off selection"] -command [list tester::fiter_tags_on_off_selection $tree 0]
    
    set xx [expr [winfo rootx $tree]+$x+50]
    set yy [expr [winfo rooty $tree]+$y]    
    tk_popup $m $xx $yy 0
}


proc tester::on_click_filter_tags { } {
    set w .preferences.tags
    if { [winfo exists $w] } {
        destroy $w
    }
    toplevel $w
    wm transient $w [winfo toplevel [winfo parent $w]]
    if { $::tcl_platform(platform) == "windows" } {
        wm attributes $w -toolwindow 1
    }
    wm title $w [_ "Hide tags"]
    set f [ttk::frame $w.frm]
    set tree_tags [tester::create_treectrol $f]    
    $tree_tags configure -width 640 -height 480 -wrap window
    bind $tree_tags <ButtonPress-$::tester_right_button> [list tester::show_menu_filter_tags %W 0 %x %y] 
    foreach tag [tester::get_filter_tags] {
        set item [$tree_tags item create -button auto -parent 0 -open 0]
        $tree_tags item style set $item 0 style_image 1 style_text
        $tree_tags item element configure $item 0 e_image -image "" , 1 e_text_sel -text $tag -justify left
        if { [tester::get_filter_tag $tag] } {
            set states tag_true
        } else {
            set states !tag_true
        }
        $tree_tags item state set $item $states
    }
    bind $tree_tags <Button-1> [list tester::on_button_1_tree_tags %x %y $tree_tags]
    
    grid $f -sticky nsew
    grid rowconfigure $f 0 -weight 1
    grid columnconfigure $f 0 -weight 1        
    
    #lower buttons    
    ttk::frame $w.frmButtons -style BottomFrame.TFrame
    ttk::button $w.frmButtons.btnclose -text [_ "Close"] -command [list destroy $w] -underline 0
    
    grid $w.frmButtons -sticky ews -columnspan 7
    grid anchor $w.frmButtons center
    grid $w.frmButtons.btnclose -padx 5 -pady 6
    grid columnconfigure $w 0 -weight 1
    grid rowconfigure $w 0 -weight 1
    
    focus $w.frmButtons.btnclose
    bind $w <Alt-c> [list $w.frmButtons.btnclose invoke]
    bind $w <Escape> [list $w.frmButtons.btnclose invoke]    
}

proc tester::on_change_test_gid { w } {
    variable preferences
    set tester_project_frm $w.frm.localization.project
    if { $preferences(test_gid) } {
        foreach item {offscreen_exe gidini} {        
            grid $tester_project_frm.l_$item $tester_project_frm.e_$item            
        }
        grid $w.frm.run.e_gidshowtclerror
    } else {
        foreach item {offscreen_exe gidini} {        
            grid remove $tester_project_frm.l_$item $tester_project_frm.e_$item
        }
        grid remove $w.frm.run.e_gidshowtclerror 
    }
}

proc tester::preferences_win { } {    
    variable preferences
    variable ini
    variable allowed_plaforms
    set w .preferences
    if { [winfo exists $w] } {
        destroy $w
    }   
    toplevel $w      
    wm transient $w [winfo toplevel [winfo parent $w]]
    if { $::tcl_platform(platform) == "windows" } {
        wm attributes $w -toolwindow 1
    }   
    wm title $w [_ "Preferences"]
    ttk::frame $w.frm
    
    ttk::labelframe $w.frm.localization -text [_ "Localization"]
    
    
    set item test_gid
    ttk::checkbutton $w.frm.localization.e_$item -text [_ "test GiD"] -variable tester::preferences($item) -command [list tester::on_change_test_gid $w]
    grid $w.frm.localization.e_$item -sticky w -columnspan 2
    tooltip::tooltip $w.frm.localization.e_$item [_ "To do special features if the exe program to be tested is %s" GiD]
    
    set item platform_provide
    ttk::label $w.frm.localization.l_$item -text [_ "platform provide"]
    ttk::combobox $w.frm.localization.e_$item -textvariable tester::preferences($item) -values $allowed_plaforms
    grid $w.frm.localization.l_$item $w.frm.localization.e_$item -sticky w
    grid configure $w.frm.localization.e_$item -sticky ew
    tooltip::tooltip $w.frm.localization.e_$item [_ "Declares our platform. Cases whit platform_require different to this value could be filtered"]       
    set item branch_provide
    ttk::label $w.frm.localization.l_$item -text [_ "branch provide"]
    ttk::combobox $w.frm.localization.e_$item -textvariable tester::preferences($item) -values {developer official}
    grid $w.frm.localization.l_$item $w.frm.localization.e_$item -sticky w
    grid configure $w.frm.localization.e_$item -sticky ew
    tooltip::tooltip $w.frm.localization.e_$item [_ "Declares our branch. Cases whit branch_require different to this value could be filtered"]
    
    set tester_project_frm [ttk::labelframe $w.frm.localization.project -text [_ "Tester project"]]
    foreach item {basecasesdir exe offscreen_exe path gidini} {
        ttk::label $tester_project_frm.l_$item -text $item
        ttk::entry $tester_project_frm.e_$item -textvariable tester::preferences($item)
        grid $tester_project_frm.l_$item $tester_project_frm.e_$item -sticky w
        grid configure $tester_project_frm.e_$item -sticky ew
    }     
    if { !$preferences(test_gid) } {
        grid remove $tester_project_frm.l_gidini $tester_project_frm.e_gidini
    }
    tooltip::tooltip $tester_project_frm.e_basecasesdir [_ "Path to add to relative rutes of cases"]
    tooltip::tooltip $tester_project_frm.e_exe [_ "Full path to gid.exe to be run"]
    tooltip::tooltip $tester_project_frm.e_offscreen_exe [_ "Full path to gid_offscreen.exe to be run"]
    tooltip::tooltip $tester_project_frm.e_path [_ "Environment variable PATH to be set (e.g. to allow the calculation program find its libraries)"]
    tooltip::tooltip $tester_project_frm.e_gidini [_ "Path to GiD .ini to be used to do always the same (relative to gid.exe or absolute)"]        
    grid columnconfigure $tester_project_frm 1 -weight 1
    grid $tester_project_frm -stick ew -columnspan 2
    
    set vs_frm [ttk::labelframe $w.frm.localization.vs -text [_ "Visual studio"]]
    foreach item {vs_path vs_solution} {
        ttk::label $vs_frm.l_$item -text $item
        ttk::entry $vs_frm.e_$item -textvariable visual_studio::preferences($item)
        grid $vs_frm.l_$item $vs_frm.e_$item -sticky w
        grid configure $vs_frm.e_$item -sticky ew
    }    
    grid columnconfigure $vs_frm 1 -weight 1
    grid $vs_frm -stick ew -columnspan 2
    
    set git_frm [ttk::labelframe $w.frm.localization.git -text [_ "git (version control system)"]]
    foreach item {project_dir} {
        ttk::label $git_frm.l_$item -text $item
        ttk::entry $git_frm.e_$item -textvariable git::preferences($item)
        grid $git_frm.l_$item $git_frm.e_$item -sticky w
        grid configure $git_frm.e_$item -sticky ew
    }    
    grid columnconfigure $git_frm 1 -weight 1
    grid $git_frm -stick ew -columnspan 2
    

    set item reloadlastproject
    ttk::checkbutton $w.frm.localization.e_$item -text [_ "reload last project"] -variable tester::ini($item)    
    tooltip::tooltip $w.frm.localization.e_$item [_ "to automatically load last project when starting"]
    grid $w.frm.localization.e_$item -sticky w -columnspan 2
    
    set item run_at
    ttk::checkbutton $w.frm.localization.e_$item -text [_ "run at"] -variable tester::preferences($item) -command [list tester::on_change_$item $w.frm.localization.e_${item}_value]
    tooltip::tooltip $w.frm.localization.e_$item [_ "To automatically run cases at an hour and optionally analize fails and send e-mails"]        
    
    #ttk::spinbox $w.frm.localization.e_${item}_value -textvariable tester::preferences(${item}_value) -from 0 -to 23 -justify left
    package require timebox
    ttk::timebox $w.frm.localization.e_${item}_value tester::preferences(${item}_value) Hm
    tooltip::tooltip $w.frm.localization.e_${item}_value [_ "The hour to automatically run cases at"]
    if { !$tester::preferences($item) } {
        $w.frm.localization.e_${item}_value configure -state disabled
    }
    grid $w.frm.localization.e_$item $w.frm.localization.e_${item}_value -sticky w
    #grid configure $w.frm.localization.e_${item}_value -sticky ew
    
    set item email_on_fail
    ttk::checkbutton $w.frm.localization.e_$item -text [_ "email on fail"] -variable tester::preferences($item) -command [list tester::on_change_email_on_fail]
    #grid $w.frm.localization.e_$item -sticky w -columnspan 2
    tooltip::tooltip $w.frm.localization.e_$item [_ "To automatically send an e-mail after run cases that now fail"]        
    
    set item analize_cause_fail
    ttk::checkbutton $w.frm.localization.e_$item -text [_ "analize cause fail"] -variable tester::preferences($item)
    tooltip::tooltip $w.frm.localization.e_$item [_ "To automatically find the git commit that caused the fail"]
    grid $w.frm.localization.e_email_on_fail $w.frm.localization.e_$item -sticky w
    
    ttk::labelframe $w.frm.run -text [_ "Run"]
    set item timeout 
    ttk::label $w.frm.run.l_$item -text [_ "timeout"]
    ttk::entry $w.frm.run.e_$item -textvariable tester::preferences($item)
    ttk::label $w.frm.run.l2_$item -text [_ "seconds"]
    grid $w.frm.run.l_$item $w.frm.run.e_$item $w.frm.run.l2_$item -sticky w
    grid configure $w.frm.run.e_$item -sticky ew
    tooltip::tooltip $w.frm.run.e_$item [_ "To kill a process that exceed this time (seconds), set 0 to no limit"]
    set item maxmemory
    ttk::label $w.frm.run.l_$item -text [_ "max memory"]
    ttk::entry $w.frm.run.e_$item -textvariable tester::preferences($item)
    ttk::label $w.frm.run.l2_$item -text "MB"
    grid $w.frm.run.l_$item $w.frm.run.e_$item $w.frm.run.l2_$item -sticky w
    grid configure $w.frm.run.e_$item -sticky ew
    tooltip::tooltip $w.frm.run.e_$item [_ "To kill a process that exceed this memory use (MB), set 0 to no limit"]
    set item maxprocess
    ttk::label $w.frm.run.l_$item -text [_ "max process"]
    ttk::spinbox $w.frm.run.e_$item -textvariable tester::preferences($item) -from 1 -to 64 -justify left
    grid $w.frm.run.l_$item $w.frm.run.e_$item -sticky w
    grid configure $w.frm.run.e_$item -sticky ew
    tooltip::tooltip $w.frm.run.e_$item [_ "Number of cases to be run simultaneously"]
    set item gidshowtclerror
    ttk::checkbutton $w.frm.run.e_$item -text [_ "show GiD Tcl error"] -variable tester::preferences($item)
    grid $w.frm.run.e_$item -sticky w -columnspan 2
    tooltip::tooltip $w.frm.run.e_$item [_ "To show or hide tcl errors raised by GiD, specially running with -n (some problemtypes are not prepared to work without Tk)"]    
    set item show_current_case
    ttk::checkbutton $w.frm.run.e_$item -text [_ "show current case"] -variable tester::preferences($item)
    grid $w.frm.run.e_$item -sticky w -columnspan 2    
    tooltip::tooltip $w.frm.run.e_$item [_ "To set visible in the tree the case currently running"]
    
    
    if { !$preferences(test_gid) } {
        grid remove $w.frm.run.e_gidshowtclerror 
    }
    ttk::labelframe $w.frm.run.filters
    #ttk::label $w.frm.run.filters.filters -image [tester::get_image 16x16/stock_filter-data-by-criteria.png] -text [_ "Run filters"] -compound left
    #$w.frm.run.filters configure -labelwidget $w.frm.run.filters.filters
    ttk::frame $w.frm.run.filters.f
    ttk::label $w.frm.run.filters.f.lbl -image [tester::get_image 16x16/stock_filter-data-by-criteria.png] -text [_ "Run filters"] -compound left
    set item enable_filters
    ttk::checkbutton $w.frm.run.filters.f.e_$item -text [_ "enable"] -variable tester::preferences($item) \
        -command [list tester::on_change_$item]
    tooltip::tooltip $w.frm.run.filters.f.e_$item [_ "Enable of disable all filters"]    
    set item opposite_filters
    ttk::checkbutton $w.frm.run.filters.f.e_$item -text [_ "opposite"] -variable tester::preferences($item) \
        -command [list tester::on_change_$item]
    tooltip::tooltip $w.frm.run.filters.f.e_$item [_ "Apply all opposite filters"]    
    grid $w.frm.run.filters.f.lbl $w.frm.run.filters.f.e_enable_filters $w.frm.run.filters.f.e_opposite_filters
    $w.frm.run.filters configure -labelwidget $w.frm.run.filters.f
    
    set item filter_date
    ttk::checkbutton $w.frm.run.filters.e_$item -text [_ "hide date"] -variable tester::preferences($item) \
        -command [list tester::on_change_$item]
    grid $w.frm.run.filters.e_$item -sticky w
    tooltip::tooltip $w.frm.run.filters.e_$item [_ "Enable filter by date to show only cases untested or tested but before the current exe date"]
    
    set item filter_time
    ttk::checkbutton $w.frm.run.filters.e_$item -text [concat [_ "hide time"] " >"] -variable tester::preferences($item) \
        -command [list tester::on_change_$item $w.frm.run.filters.e_${item}_value]
    ttk::entry $w.frm.run.filters.e_${item}_value -textvariable tester::preferences(${item}_value)
    ttk::label $w.frm.run.filters.l_${item}_value -text [_ "minutes"]
    if { !$tester::preferences($item) } {
        $w.frm.run.filters.e_${item}_value configure -state disabled
    }
    grid $w.frm.run.filters.e_${item} $w.frm.run.filters.e_${item}_value $w.frm.run.filters.l_${item}_value -sticky w
    grid configure $w.frm.run.filters.e_${item}_value -sticky ew    
    tooltip::tooltip $w.frm.run.filters.e_${item} [_ "Enable filter of tested cases depending on its minimum running time (untested cases are not filtered)"]
    tooltip::tooltip $w.frm.run.filters.e_${item}_value [_ "Set min time filter to show only smalls cases, that spend less running time than the limit"]
    
    set item filter_memory
    ttk::checkbutton $w.frm.run.filters.e_$item -text [concat [_ "hide memory"] " >"] -variable tester::preferences($item) \
        -command [list tester::on_change_$item $w.frm.run.filters.e_${item}_value]
    ttk::entry $w.frm.run.filters.e_${item}_value -textvariable tester::preferences(${item}_value)
    ttk::label $w.frm.run.filters.l_${item}_value -text [_ "MB"]    
    if { !$tester::preferences($item) } {
        $w.frm.run.filters.e_${item}_value configure -state disabled
    }    
    grid $w.frm.run.filters.e_${item} $w.frm.run.filters.e_${item}_value $w.frm.run.filters.l_${item}_value -sticky w
    tooltip::tooltip $w.frm.run.filters.e_${item} [_ "Enable filter of tested cases depending on its minimum used memory (untested cases are not filtered)"]
    tooltip::tooltip $w.frm.run.filters.e_${item}_value [_ "Set min time filter to show only smalls cases, that spend less memory than the limit"]
    grid configure $w.frm.run.filters.e_${item}_value -sticky ew
    
    set item filter_tags  
    ttk::checkbutton $w.frm.run.filters.e_$item -text [_ "hide tags"] -variable tester::preferences($item) \
        -command [list tester::on_change_${item} $w.frm.run.filters.e_${item}_value]
    ttk::button $w.frm.run.filters.e_${item}_value -image [tester::get_image 16x16/stock_bookmark.png] -text [_ "tags"]... -compound left \
        -command [list tester::on_click_${item}]
    if { !$tester::preferences(${item}) } {
        $w.frm.run.filters.e_${item}_value configure -state disabled
    } 
    grid $w.frm.run.filters.e_${item} $w.frm.run.filters.e_${item}_value -sticky w  
    grid configure $w.frm.run.filters.e_${item}_value -sticky ew
    tooltip::tooltip $w.frm.run.filters.e_${item} [_ "Enable filter of cases depending on its tags"]
    tooltip::tooltip $w.frm.run.filters.e_${item}_value [_ "Select tags to show only cases including them"]
    
    set item filter_fail
    ttk::checkbutton $w.frm.run.filters.e_${item} -text [_ "hide result"] -variable tester::preferences(${item}) \
        -command [list tester::on_change_${item} $w.frm.run.filters.e_${item}_value]
    ttk::combobox $w.frm.run.filters.e_${item}_value -textvariable tester::preferences(${item}_value) \
        -values {"fail" "ok" "untested" "running" "crash" "timeout" "maxmemory" "userstop"}
    if { !$tester::preferences(${item}) } {
        $w.frm.run.filters.e_${item}_value configure -state disabled
    }    
    grid $w.frm.run.filters.e_${item} $w.frm.run.filters.e_${item}_value -sticky w
    grid configure $w.frm.run.filters.e_${item}_value -sticky ew    
    tooltip::tooltip $w.frm.run.filters.e_${item} [_ "Enable filter of tested cases depending on its result (untested cases are not filtered)"]
    tooltip::tooltip $w.frm.run.filters.e_${item}_value [_ "Set value to show only tested cases whit fail value 1 or 0 (untested cases are not filtered)"]
    
    set item filter_fail_accepted
    ttk::checkbutton $w.frm.run.filters.e_${item} -text [_ "hide fail accepted"] -variable tester::preferences(${item}) \
        -command [list tester::on_change_${item} $w.frm.run.filters.e_${item}_value]
    ttk::combobox $w.frm.run.filters.e_${item}_value -textvariable tester::preferences(${item}_value) -values {1 0}
    if { !$tester::preferences(${item}) } {
        $w.frm.run.filters.e_${item}_value configure -state disabled
    }    
    grid $w.frm.run.filters.e_${item} $w.frm.run.filters.e_${item}_value -sticky w
    grid configure $w.frm.run.filters.e_${item}_value -sticky ew    
    tooltip::tooltip $w.frm.run.filters.e_${item} [_ "Enable filter of cases depending on its fail_accepted field value (e.g. cases that fail and won't be fixed)"]
    tooltip::tooltip $w.frm.run.filters.e_${item}_value [_ "Set value to show only cases whit fail_accepted value 1 or 0"]
    
    set item filter_fail_random
    ttk::checkbutton $w.frm.run.filters.e_${item} -text [_ "hide fail random"] -variable tester::preferences(${item}) \
        -command [list tester::on_change_${item} $w.frm.run.filters.e_${item}_value]
    ttk::combobox $w.frm.run.filters.e_${item}_value -textvariable tester::preferences(${item}_value) -values {1 0}
    if { !$tester::preferences(${item}) } {
        $w.frm.run.filters.e_${item}_value configure -state disabled
    }    
    grid $w.frm.run.filters.e_${item} $w.frm.run.filters.e_${item}_value -sticky w
    grid configure $w.frm.run.filters.e_${item}_value -sticky ew    
    tooltip::tooltip $w.frm.run.filters.e_${item} [_ "Enable filter of cases depending on its fail_random field value (e.g. cases that fail doesn't mean that something has been broken)"]
    tooltip::tooltip $w.frm.run.filters.e_${item}_value [_ "Set value to show only cases whit fail_random value 1 or 0"]

    set item filter_platform_provide
    ttk::checkbutton $w.frm.run.filters.e_${item} -text [_ "hide platform provide"] -variable tester::preferences(${item}) \
        -command [list tester::on_change_${item}]
    grid $w.frm.run.filters.e_${item} -sticky w 
    tooltip::tooltip $w.frm.run.filters.e_${item} [_ "Enable filter of cases depending on its platform_require field value (e.g. cases with a problemtype compiled only for some platform)"]        
    
    set item filter_branch_provide
    ttk::checkbutton $w.frm.run.filters.e_filter_branch_provide -text [_ "hide branch provide"] -variable tester::preferences(${item}) \
        -command [list tester::on_change_${item}]
    grid $w.frm.run.filters.e_${item} -sticky w
    tooltip::tooltip $w.frm.run.filters.e_${item} [_ "Enable filter of cases depending on its branch_require field value (e.g. cases with new features available only in developer versions)"]
    
    grid $w.frm.run.filters -sticky nsew -columnspan 3
    grid columnconfigure $w.frm.run.filters 1 -weight 1    
    
    
    ttk::labelframe $w.frm.view -text [_ "View"]
    set item show_as_tree
    ttk::checkbutton $w.frm.view.e_$item -text [_ "show as tree"] -variable tester::preferences($item) -command tester::fill_tree
    grid $w.frm.view.e_$item -sticky w -columnspan 2
    tooltip::tooltip $w.frm.view.e_$item [_ "To show tests cases as tree or as table"]
    
    ttk::labelframe $w.frm.graphs -text [_ "Graphs"]
    set item graphs_date_min
    ttk::checkbutton $w.frm.graphs.e_$item -text [_ "Date min"] -variable tester::preferences($item) -command tester::update_range_graphs
    tooltip::tooltip $w.frm.graphs.e_$item [_ "To show only a range of graphs values between two dates (format dd-mm-yyyy)"]
    ttk::entry $w.frm.graphs.e_${item}_value -textvariable tester::preferences(${item}_value)
    grid $w.frm.graphs.e_$item $w.frm.graphs.e_${item}_value -sticky w
    grid configure $w.frm.graphs.e_${item}_value -sticky ew
    bind $w.frm.graphs.e_${item}_value <Return> [list tester::update_range_graphs]
    set item graphs_date_max
    ttk::checkbutton $w.frm.graphs.e_$item -text [_ "Date max"] -variable tester::preferences($item) -command tester::update_range_graphs
    tooltip::tooltip $w.frm.graphs.e_$item [_ "To show only a range of graphs values between two dates (format dd-mm-yyyy)"]
    ttk::entry $w.frm.graphs.e_${item}_value -textvariable tester::preferences(${item}_value)
    grid $w.frm.graphs.e_$item $w.frm.graphs.e_${item}_value -sticky w
    grid configure $w.frm.graphs.e_${item}_value -sticky ew 
    bind $w.frm.graphs.e_${item}_value <Return> [list tester::update_range_graphs]
    
    ttk::labelframe $w.frm.report -text [_ "Report"]
    set item htmlimagesbyrow
    ttk::label $w.frm.report.l_$item -text [_ "html images by row"]
    ttk::spinbox $w.frm.report.e_$item -textvariable tester::preferences($item) -from 1 -to 4 -justify left
    grid $w.frm.report.l_$item $w.frm.report.e_$item -sticky w 
    grid configure $w.frm.report.e_$item -sticky ew
    tooltip::tooltip $w.frm.report.e_htmlimagesbyrow [_ "layout of the html report"]            
    
    foreach frame {localization run view graphs report} {
        grid $w.frm.$frame -sticky nsew -padx 2 -pady 2
        grid columnconfigure $w.frm.$frame 1 -weight 1
    }
    
    grid columnconfigure $w.frm 0 -weight 1
    grid $w.frm -sticky nsew -padx 2 -pady 2
    ttk::frame $w.frmclose
    ttk::button $w.frmclose.b_close -text [_ "Close"] -command [list destroy $w] -underline 0
    grid $w.frmclose.b_close -padx 2 -pady 2
    grid $w.frmclose -sticky sew
    grid anchor $w.frmclose center
    grid columnconfigure $w 0 -weight 1
    grid rowconfigure $w 0 -weight 1
    bind $w <Escape> [list $w.frmclose.b_close invoke]
    if { !$preferences(enable_filters) } {
        tester::set_filters_state
    }
}

proc tester::trace_add_variable_preferences { } {
    variable preferences
    foreach item { basecasesdir path platform_provide branch_provide gidshowtclerror filter_time_value filter_memory_value \
        filter_fail_value filter_fail_accepted_value filter_fail_random_value } {
        trace add variable tester::preferences($item) write tester::trace_preferences_$item
    }
}

proc tester::trace_remove_variable_preferences { } {
    variable preferences
    foreach item { basecasesdir path platform_provide branch_provide gidshowtclerror filter_time_value filter_memory_value \
        filter_fail_value filter_fail_accepted_value filter_fail_random_value } {
        trace remove variable tester::preferences($item) write tester::trace_preferences_$item
    }
}


proc tester::trace_preferences_basecasesdir { args } {
    variable preferences
    if { [file exists $preferences(basecasesdir)] && [file isdirectory $preferences(basecasesdir)] } {
        cd $preferences(basecasesdir)
    }
}

proc tester::trace_preferences_path { args } {
    variable preferences    
    if { $preferences(path) != "" } {
        #set ::env(PATH) $preferences(path)
        if { [file pathtype $preferences(path)] == "relative" } {
            #consider relative to the path of the exe            
            set full_path [file join [file dirname $preferences(exe)] $preferences(path)]
        } else {
            set full_path $preferences(path)
        }
        #set ::env(PATH) $full_path
        set len_path [string length $full_path]        
        if { [string range $::env(PATH) end-[expr $len_path-1] end] != $full_path } {
            set ::env(PATH) "$::env(PATH);$full_path"
        }
    }
}

proc tester::on_change_run_at { w } {
    variable preferences
    if { $tester::preferences(run_at) } {
        $w configure -state normal
    } else {
        $w configure -state disabled
    }
}

proc tester::on_change_email_on_fail { } {
    variable preferences
    if { $preferences(email_on_fail) } {
        tester::ask_missing_preferences_mailsend
    }
}

#define new case window

proc tester::get_relative_batch_filename  { variable_name } {
    variable preferences
    set filename [set ::$variable_name]
    set full_filename [tester::get_full_case_path $filename]
    set types [list [list [_ "GiD bach file"] ".bch"] [list [_ "All files"] ".*"]]
    set title [_ "Select file"]
    set current_value [tk_getOpenFile -filetypes $types -initialdir $full_filename -parent . -title $title -multiple 0]    
    set current_value [tester::get_relative_path $preferences(basecasesdir) $current_value]
    set ::$variable_name $current_value
    return $current_value
}

proc tester::on_change_execution_type_gid_batch { f_gidbatch f_generic } {
    variable current_case_definition
    if { [winfo exists $f_gidbatch] } {
        if { $current_case_definition(execution_type_gid_batch) } {
            grid $f_gidbatch
            grid remove $f_generic
        } else {
            grid remove $f_gidbatch
            grid $f_generic
        }
    }
}

proc tester::add_test_entry { f_checks } {
    variable current_case_definition
    set i 1
    while { 1 } {
        set item check-$i
        if { ![winfo exists $f_checks.l_$item] } {
            break
        }
        incr i
    }
    set item check-$i
    if { ![info exists tester::current_case_definition($item)] } {
        set tester::current_case_definition($item) ""
    }
    ttk::label $f_checks.l_$item -text $item
    ttk::entry $f_checks.e_$item -textvariable tester::current_case_definition($item)
    grid $f_checks.l_$item $f_checks.e_$item -sticky w
    grid configure $f_checks.e_$item -sticky ew
}

proc tester::remove_test_entry { f_checks } {
    variable current_case_definition
    set i 1
    while { 1 } {
        set item check-$i
        if { ![winfo exists $f_checks.l_$item] } {
            break
        }
        incr i
    }
    incr i -1
    if { $i > 0 } {
        set item check-$i
        destroy $f_checks.l_$item
        destroy $f_checks.e_$item
        unset tester::current_case_definition($item)   
    }
}

proc tester::edit_case { case_id } {
    variable current_case_definition ;#current case definition values    
    array unset current_case_definition        
    foreach key [tester::get_keys $case_id] {
        set current_case_definition($key) [tester::get_variable $case_id $key]
    }
    if { ![info exists current_case_definition(fail_accepted)] } {
        set current_case_definition(fail_accepted) 0
    }
    if { ![info exists current_case_definition(fail_random)] } {
        set current_case_definition(fail_random) 0
    }
    if { ![info exists current_case_definition(branch_require)] } {
        set current_case_definition(branch_require) ""
    }    
    
    if { [info exists current_case_definition(batch)] } {
        set current_case_definition(execution_type_gid_batch) 1     
    } else {
        set current_case_definition(execution_type_gid_batch) 0
    }    
    
    set i 1
    foreach check [tester::get_checks $case_id] {
        set key check,$check
        set item check-$i
        if { [tester::exists_variable $case_id $key] } {            
            set current_case_definition($item) [tester::get_variable $case_id $key]
        } else {
            unset -nocomplain current_case_definition($item)            
        }  
        incr i 
    }        
    
    tester::define_case_win $case_id
}

proc tester::set_xml_node_case_from_current_case_definition { xml_node_case } {
    variable current_case_definition ;#current case definition values
    variable case_allowed_attributes
    variable case_allowed_keys    
    foreach xml_child_node [$xml_node_case childNodes] {
        $xml_node_case removeChild $xml_child_node
        $xml_child_node delete
    }
    foreach key $case_allowed_keys {
        if { $key == "check" } {
            continue 
        }
        if { [info exists current_case_definition($key)] } {
            set value $current_case_definition($key)            
            if { $value != "" && $value != [tester::get_preferences_key_value $key] } {
                if { $key == "outfile" } {
                    set tmpdir [tester::get_tmp_folder]
                    if { [file dirname $value] == $tmpdir  } {
                        continue ;#ignore it if is inside the temporary foldes (default automatic name), to not save explicitly after in the doc -> xml file
                    }            
                } elseif { $key == "readingproc" } {
                    if { $value == "read_gid_monitoring_info" } {
                        continue ;#ignore it if is the default value, to not save explicitly after in the doc -> xml file
                    }
                }
                set key_xml_node [tester::xml_create_element $xml_node_case $key ""]
                tester::xml_create_text_node $key_xml_node $value
                if { $key == "batch" } {
                    variable batch_allowed_attributes
                    foreach attribute $batch_allowed_attributes {                        
                        if { [info exists current_case_definition($attribute)] } {
                            set value $current_case_definition($attribute)
                            if { $value == "" || $value == [tester::get_default_attribute_value $attribute]} {
                                if { [$key_xml_node hasAttribute $attribute] } {
                                    $key_xml_node removeAttribute $attribute
                                }
                            } else {
                                $key_xml_node setAttribute $attribute $value
                            }
                        } else {
                            if { [$key_xml_node hasAttribute $attribute] } {
                                $key_xml_node removeAttribute $attribute
                            }
                        }
                    }
                    
                }
            }
        }
    }    
    foreach attribute $case_allowed_attributes {
        if { $attribute == "id" } {
            #this attribute is set automatically
            continue
        }
        if { [info exists current_case_definition($attribute)] } {
            set value $current_case_definition($attribute)
            if { $value == "" || $value == [tester::get_default_attribute_value $attribute]} {
                if { [$xml_node_case hasAttribute $attribute] } {
                    $xml_node_case removeAttribute $attribute
                }
            } else {
                $xml_node_case setAttribute $attribute $value
            }
        } else {
            if { [$xml_node_case hasAttribute $attribute] } {
                $xml_node_case removeAttribute $attribute
            }
        }
    }
    set check_xml_node [tester::xml_create_element $xml_node_case check ""]
    set i 1
    while { 1 } {
        set key check-$i
        if { [info exists current_case_definition($key)] } {
            set value $current_case_definition($key)
            set key_xml_node [tester::xml_create_element $check_xml_node $key ""]
            tester::xml_create_text_node $key_xml_node $value        
        } else {
            break
        }
        incr i
    }    
}

proc tester::on_ok_define_case { case_id w } {
    variable private_options    
    set document $private_options(xml_document)
    if { $case_id == "" } {
        set mode new
    } else {
        set mode edit
    }
    
    set text $w.frm.f_definition.f_basic_and_execution.f_execution.f_generic.e_codetosource    
    if { [winfo exists $text] } {
        set tester::current_case_definition(codetosource) [$text get 1.0 end-1c]
    }
    set old_case_id "" ;#used if edit and the case change its id (changing batch)
    if { $mode == "new" } {
        #new case
        #create a xml node to check its digest id
        set xml_node_case [$document createElement case]
        tester::set_xml_node_case_from_current_case_definition $xml_node_case
        set case_id [tester::get_md5_xml_node_case $xml_node_case]        
        set xml_node_case_old [tester::xml_get_element_by_id $document $case_id]
        if { $xml_node_case_old != "" } {
            #case already exists, delete the newly created node
            $xml_node_case delete
            tester::set_message [_ "The case %s already exists" $case_id]
            return 1
        } else {
            $xml_node_case setAttribute id $case_id
            set root_xml [$document documentElement]
            $root_xml appendChild $xml_node_case
        }
        tester::set_message [_ "Defined new case %s" $case_id]
    } elseif { $mode == "edit" } {
        #edit case
        set xml_node_case [tester::xml_get_element_by_id $document $case_id]
        if { $xml_node_case == "" } {
            tester::message [_ "The case %s doesn't exists" $case_id]
            return 1
        } else {            
            tester::set_xml_node_case_from_current_case_definition $xml_node_case
            #modifying the case definition could force change its digest id
            set case_id_new [tester::get_md5_xml_node_case $xml_node_case]
            if { $case_id_new != $case_id } {
                tester::array_unset $case_id *
                $xml_node_case setAttribute id $case_id_new
                set old_case_id $case_id
                set case_id $case_id_new
            }
        }
        tester::set_message [_ "Modified case %s" $case_id]
    } else {
        #re-fill the tree to update the information    
        tester::fill_tree
        error "unexpected mode=$mode"
    }
    #add also to the tcl variables    
    tester::set_case_id_variables_from_xml_node_case $xml_node_case $case_id
    
    destroy $w
    if { $mode == "new" } {
        tester::add_case_to_tree $case_id
        tester::tree_update_case $case_id ""
    } elseif { $mode == "edit" } {
        #avoid rebuild the full tree, only rebuild this item                
        tester::tree_update_case $case_id $old_case_id
    } else {
        #re-fill the tree to update the information    
        tester::fill_tree
        error "unexpected mode=$mode"
    }
}

proc tester::get_tree_case_ids_current_sort { } {
    variable tree
    set tree_case_ids [list]
    foreach tree_item [$tree item range 0 end] {
        if { [$tree item tag expr $tree_item case] } {
            lappend tree_case_ids [tester::tree_get_item_case_id $tree $tree_item]
        }        
    }
    return $tree_case_ids
}

proc tester::find { } {
    variable find_values    
    variable tree_item_case
    set case_id_found ""
    if { $tester::find_values(find) == "" } {
        return 0
    }
    
    set pattern *$tester::find_values(find)*
    set where $tester::find_values(where) ; #case_id case_name
    set case_sensitive $tester::find_values(case_sensitive)
    #set tree_case_ids [array names tree_item_case]
    set tree_case_ids [tester::get_tree_case_ids_current_sort]
    set start $tester::find_values(start) ;#to find next...
    if { $where == "case_id" } {
        set data_where_search $tree_case_ids           
    } elseif { $where == "case_name" } {
        set data_where_search [list]
        foreach case_id $tree_case_ids {
            lappend data_where_search [tester::get_variable $case_id name]
        }
    } else {
        error "tester::find. Unexpected where=$where"
    }
    set flags [list -glob]
    if { !$case_sensitive } {
        lappend flags -nocase
    }
    set match [lsearch -all {*}$flags $data_where_search $pattern]
    set num_match [llength $match]
    if { $num_match } {
        if { $start >= $num_match } {
            set start 0
            set tester::find_values(start) 0
        }
        set pos [lindex $match $start]
    } else {
        set pos -1
    }
    if { $pos != -1 } {
        set case_id_found [lindex $tree_case_ids $pos]
        incr tester::find_values(start)
        if { $tester::find_values(start) >= $num_match } {
            set tester::find_values(start) 0
        }
    } else {
        set case_id_found ""
        set tester::find_values(start) 0
    }
    tester::highlight_found $case_id_found
    if { $case_id_found == "" } {
        #not found
        set tester::find_values(message) [_ "No results"]
    } else {
        set tester::find_values(message) [_ "%s of %s" [expr $start+1] $num_match]
    }
    tester::find_add_to_history $tester::find_values(find)
    return 0
}

proc tester::find_add_to_history { text } {
    variable find_values
    if { $text != "" && [lsearch -exact $tester::find_values(find_history) $text] == -1 } {
        set tester::find_values(find_history) [linsert $tester::find_values(find_history) 0 $text]
        set num_max 20
        if { [llength $tester::find_values(find_history)] > $num_max } {
            set tester::find_values(find_history) [lrange $tester::find_values(find_history) 0 $num_max-1]
        }
        set w .ftop.f_find
        $w.f.frm_find.e_find configure -values $tester::find_values(find_history)
    }
}

proc tester::highlight_found { case_id } {
    variable tree
    variable tree_item_case
    if { [info exists tree] && [winfo exists $tree] } {
        $tree selection clear
        if { [info exists tree_item_case($case_id)] } {
            set item $tree_item_case($case_id)
            set items_to_open [$tree item id "$item ancestors state !open"]
            foreach item_to_open $items_to_open {
                $tree item expand $item_to_open
            }
            $tree see $item -center y
            $tree activate $item 
            $tree selection add $item        
        }
    }
}

proc tester::find_win { } {
    variable find_values
    
    set w .ftop.f_find
    if { [winfo exists $w.f] } {
        destroy $w.f        
    }
    
    set f [ttk::frame $w.f]
    set frm [ttk::labelframe $f.frm_find -text [_ "Find"]]
    ttk::combobox $frm.e_where -textvariable tester::find_values(where) -values {case_id case_name} -state readonly -width 10
    if { ![info exists tester::find_values(find_history)] } {
        set tester::find_values(find_history) ""
    }
    ttk::combobox $frm.e_find -textvariable tester::find_values(find) -values $tester::find_values(find_history) -width 20
    if { ![info exists tester::find_values(case_sensitive)] } {
        set tester::find_values(case_sensitive) 0
    }
    ttk::checkbutton $frm.cb_case_sensitive -text "Aa" -variable tester::find_values(case_sensitive) -style Toolbutton
    if { ![info exists tester::find_values(where)] } {
        set tester::find_values(where) case_id
    }    
    if { ![info exists tester::find_values(message)] } {
        set tester::find_values(message) ""
    }
    ttk::label $frm.l_find_result -textvariable tester::find_values(message) -width 10
    ttk::button $frm.b_find_close -command [list destroy $w.f] -image [tester::get_image "close.png"]
    grid $frm.e_where $frm.e_find $frm.cb_case_sensitive $frm.l_find_result $frm.b_find_close -sticky w
    grid configure $frm.e_find -sticky ew
    grid columnconfigure $frm 1 -weight 1        
    
    grid $frm -sticky nsew -padx 2 -pady 2

    set tester::find_values(start) 0    
    bind $frm.e_find <Return> [list tester::find]        
    
    grid $f -sticky nsew
    grid columnconfigure $f 0 -weight 1
    grid rowconfigure $f 0 -weight 1
    
    focus $frm.e_find    
    if { [trace info variable tester::find_values(find)] == "" } {
        #check to avoid repeat traces
        trace add variable tester::find_values(find) write tester::on_change_find
        trace add variable tester::find_values(where) write tester::on_change_find
    }
}

proc tester::on_change_find { args } {
    variable find_values
    
    set tester::find_values(start) 0
    set tester::find_values(message) ""
}
    
proc tester::define_case_win { {case_id ""} } {
    variable current_case_definition ;#current case definition values
    variable preferences
    variable allowed_plaforms
    variable allowed_branchs
    
    set w .definecase
    if { [winfo exists $w] } {
        destroy $w
    }
    if { $case_id == "" } {
        set title [_ "Define case"]
    } else {
        set title [_ "Edit case %s" $case_id]
    }
    toplevel $w
    wm transient $w [winfo toplevel [winfo parent $w]]
    if { $::tcl_platform(platform) == "windows" } {
        wm attributes $w -toolwindow 1
    }
    wm title $w $title
    ttk::frame $w.frm     
    
    set nb_definition [ttk::notebook $w.frm.f_definition]
    set f_basic_and_execution [ttk::frame $nb_definition.f_basic_and_execution]
    $nb_definition add $f_basic_and_execution -text [_ "Basic"] -sticky nsew
    set f_particular_and_advanced [ttk::frame $nb_definition.f_particular_and_advanced]
    $nb_definition add $f_particular_and_advanced -text [_ "Advanced"] -sticky nsew
    
    set f_basic [ttk::frame $f_basic_and_execution.f_basic]
    foreach item { name tags help owner jira_id } text [list [_ "name"] [_ "tags"] [_ "help"] [_ "owner"] [_ "Jira id"]] {
        ttk::label $f_basic.l_$item -text $text
        if { $item == "owner" } {
            ttk::combobox $f_basic.e_$item -textvariable tester::current_case_definition($item) -values [tester::get_owners]
        } else {
            ttk::entry $f_basic.e_$item -textvariable tester::current_case_definition($item)
        }
        grid $f_basic.l_$item $f_basic.e_$item -sticky w
        grid configure $f_basic.e_$item -sticky ew
    }
    tooltip::tooltip $f_basic.e_name [_ "Case name"]
    tooltip::tooltip $f_basic.e_tags [_ "list of tags to filter cases and show as tree by categories"]
    tooltip::tooltip $f_basic.e_help [_ "Small help to explain something about the case"]
    tooltip::tooltip $f_basic.e_owner [_ "e-mail of the responsible of the case"]    
    tooltip::tooltip $f_basic.e_jira_id [_ "id of Jira issue related to the case"]
    
    $f_basic.e_name configure -width 80 ;#to force a window width
    
    set f_execution [ttk::labelframe $f_basic_and_execution.f_execution -text [_ "Execution"]]
    if { ![info exists current_case_definition(execution_type_gid_batch)] } {
        set current_case_definition(execution_type_gid_batch) 1
    }
    if { $preferences(test_gid) } {
        ttk::checkbutton $f_execution.cb_gidbatch -text [_ "GiD batch"] \
            -variable tester::current_case_definition(execution_type_gid_batch) \
            -command [list tester::on_change_execution_type_gid_batch $f_execution.f_gidbatch $f_execution.f_generic]
        grid $f_execution.cb_gidbatch -sticky w        
    } else {
        set tester::current_case_definition(execution_type_gid_batch) 0
    }
    
    set f_gidbatch [ttk::frame $f_execution.f_gidbatch]
    set item batch
    ttk::label $f_gidbatch.l_$item -text [_ "batch"]
    ttk::entry $f_gidbatch.e_$item -textvariable tester::current_case_definition($item)
    if { ![info exists current_case_definition(batch)] } {
        set current_case_definition(batch) ""
    }
    ttk::button $f_gidbatch.b_$item -image [tester::get_image "folder.png"] \
        -command [list tester::get_relative_batch_filename tester::current_case_definition($item)]    
    grid $f_gidbatch.l_$item $f_gidbatch.e_$item $f_gidbatch.b_$item -sticky w
    grid configure $f_gidbatch.e_$item -sticky ew
    tooltip::tooltip $f_gidbatch.e_$item [_ "GiD batch filename to be used as input"]
    
    set f_batchoptions [ttk::frame $f_gidbatch.f_batchoptions]
    foreach item {with_window offscreen with_graphics} {
        if { ![info exists current_case_definition($item)] } {
            set current_case_definition($item) 0
        }
        ttk::checkbutton $f_batchoptions.cb_$item -text [_ $item] -variable tester::current_case_definition($item)
    }
    grid $f_batchoptions.cb_with_window $f_batchoptions.cb_offscreen $f_batchoptions.cb_with_graphics -sticky w
    grid $f_batchoptions -sticky ew -columnspan 3
    grid $f_gidbatch -sticky nsew
    grid columnconfigure $f_gidbatch 1 -weight 1
    
    set f_generic [ttk::frame $f_execution.f_generic]    
    foreach item { exe args outfile readingproc filetosource codetosource } {
        ttk::label $f_generic.l_$item -text $item
        if { $item == "codetosource" } {
            text $f_generic.e_$item -height 6
            if { [info exists tester::current_case_definition($item)] } {
                $f_generic.e_$item insert 1.0 $tester::current_case_definition($item)
            }
        } else {
            ttk::entry $f_generic.e_$item -textvariable tester::current_case_definition($item)
        }
        grid $f_generic.l_$item $f_generic.e_$item -sticky w
        grid configure $f_generic.e_$item -sticky ew
    }
    tooltip::tooltip $f_generic.e_exe [_ "executable. Left empty to inherit the general preference"]
    tooltip::tooltip $f_generic.e_args [_ "Command line arguments for the exe"]
    tooltip::tooltip $f_generic.e_outfile [_ "output filename where readingproc will expects to read information. Can use 'stdout' to send standard output to readingproc instead '\$outfile'"]
    tooltip::tooltip $f_generic.e_readingproc [_ "Callback Tcl procedure to invoke after run. Left empty to use the default 'read_gid_monitoring_info {outfile}' procedure"]
    tooltip::tooltip $f_generic.e_filetosource [_ "Tcl filename to be sourced (e.g: to define other reading procedures)"]
    tooltip::tooltip $f_generic.e_codetosource [_ "Tcl code to be sourced (e.g: to define other reading procedures)"]    
    grid $f_generic -sticky nsew
    grid columnconfigure $f_generic 1 -weight 1    
    
    if { $current_case_definition(execution_type_gid_batch) } {
        grid remove $f_generic
    } else {
        grid remove $f_gidbatch
    }
    
    set f_checks [ttk::labelframe $f_basic_and_execution.f_checks -text [_ "Checks"]]
    set f_addremove [ttk::frame $f_checks.f_addremove]
    ttk::button $f_addremove.b_add -image [tester::get_image 16x16/add.png] -command [list tester::add_test_entry $f_checks]   
    ttk::button $f_addremove.b_remove -image [tester::get_image 16x16/remove.png] -command [list tester::remove_test_entry $f_checks]   
    grid $f_addremove.b_add $f_addremove.b_remove -sticky w
    grid $f_addremove -sticky w
    
    set i 1
    while { 1 } {
        set item check-$i
        if { [info exists current_case_definition($item)] } {
            ttk::label $f_checks.l_$item -text $item
            ttk::entry $f_checks.e_$item -textvariable tester::current_case_definition($item)
            grid $f_checks.l_$item $f_checks.e_$item -sticky w
            grid configure $f_checks.e_$item -sticky ew
        } else {
            break
        }
        incr i
    }
    tooltip::tooltip $f_checks [_ "Tcl expression, based on some variables of the test, that must be true to pass the test"]
    
    set f_particular [ttk::labelframe $f_particular_and_advanced.f_particular -text [_ "Particular settings"]]
    ttk::label $f_particular.l_timeout -text [_ "timeout"]
    ttk::entry $f_particular.e_timeout -textvariable tester::current_case_definition(timeout)
    ttk::label $f_particular.l2_timeout -text [_ "seconds"]
    grid $f_particular.l_timeout $f_particular.e_timeout $f_particular.l2_timeout -sticky w
    grid configure $f_particular.e_timeout -sticky ew
    tooltip::tooltip $f_particular.e_timeout [_ "To kill a process that exceed this time (seconds). Left empty to inherit the general preference"]
    if { 1 } {
        #don't do it because it is difficult to control not to run more processes that a limit while running this
        ttk::label $f_particular.l_maxprocess -text [_ "max process"]
        ttk::spinbox $f_particular.e_maxprocess -textvariable tester::current_case_definition(maxprocess) -from 1 -to 64 -justify left
        grid $f_particular.l_maxprocess $f_particular.e_maxprocess -sticky w
        grid configure $f_particular.e_maxprocess -sticky ew
        tooltip::tooltip $f_particular.e_maxprocess [_ "Number of cases to be run simultaneously. Left empty to inherit the general preference"]       
    }
    if { $preferences(test_gid) } {
        ttk::label $f_particular.l_gidini -text [_ "GiD ini"]
        ttk::entry $f_particular.e_gidini -textvariable tester::current_case_definition(gidini)
        grid $f_particular.l_gidini $f_particular.e_gidini -sticky w
        grid configure $f_particular.e_gidini -sticky ew
    }
    
    set f_advanced [ttk::labelframe $f_particular_and_advanced.f_advanced -text [_ "Advanced"]]
    ttk::label $f_advanced.l_platform_require -text [_ "platform require"]
    ttk::combobox $f_advanced.e_platform_require -textvariable tester::current_case_definition(platform_require) -values [list {} {*}$allowed_plaforms]
    grid $f_advanced.l_platform_require $f_advanced.e_platform_require -sticky w
    grid configure $f_advanced.e_platform_require -sticky ew    
    tooltip::tooltip $f_advanced.e_platform_require [_ "A plaform (Windows Linux MacOSX) and bits (32 64) that is compulsory to run this case. e.g. to run a case calculating with a problemtype only compiled for Windows x64 must specify: Windows 64"]
    
    ttk::label $f_advanced.l_outputfiles -text [_ "outputfiles"]
    ttk::entry $f_advanced.e_outputfiles -textvariable tester::current_case_definition(outputfiles)
    grid $f_advanced.l_outputfiles $f_advanced.e_outputfiles -sticky w
    grid configure $f_advanced.e_outputfiles -sticky ew    
    tooltip::tooltip $f_advanced.e_outputfiles [_ "Declares an output file created by the test, like an image, movie,text, html. Tester displays if the image or video was created and when clicking on them will display them. When creating the HTML output, the link to the image or video is included"]
    
    ttk::label $f_advanced.l_branch_require -text [_ "branch_require"]
    ttk::combobox $f_advanced.e_branch_require -textvariable tester::current_case_definition(branch_require) -values [list {} {*}$allowed_branchs]
    grid $f_advanced.l_branch_require $f_advanced.e_branch_require -sticky w
    grid configure $f_advanced.e_branch_require -sticky ew
    tooltip::tooltip $f_advanced.e_branch_require [_ "Declares that the case could be run only if match the current branch (declared in preferences)"]    
    set item fail_accepted
    ttk::checkbutton $f_advanced.e_${item} -text [_ "fail accepted"] -variable tester::current_case_definition(${item})
    grid configure $f_advanced.e_${item} -sticky w -columnspan 2
    tooltip::tooltip $f_advanced.e_${item} [_ "Declares that the case is known to fail, then it will be hidden"]
    set item fail_random
    ttk::checkbutton $f_advanced.e_${item} -text [_ "fail random"] -variable tester::current_case_definition(${item})
    grid configure $f_advanced.e_${item} -sticky w -columnspan 2
    tooltip::tooltip $f_advanced.e_${item} [_ "Declares that the case is known to fail random"]
    
    grid $f_basic -sticky nsew -padx 2
    grid $f_execution -sticky nsew -padx 2
    grid $f_checks -sticky nsew  -padx 2
    grid $f_particular -sticky nsew -padx 2
    grid $f_advanced -sticky nsew -padx 2
    grid columnconfigure $f_basic 1 -weight 1
    grid columnconfigure $f_execution 0 -weight 1
    grid columnconfigure $f_checks 1 -weight 1
    grid columnconfigure $f_particular 1 -weight 1    
    grid columnconfigure $f_advanced 1 -weight 1    
    
    grid columnconfigure $f_basic_and_execution 0 -weight 1
    grid columnconfigure $f_particular_and_advanced 0 -weight 1            
    
    grid $nb_definition -sticky nsew
    grid columnconfigure $nb_definition 0 -weight 1    
    
    grid columnconfigure $w.frm 0 -weight 1
    grid $w.frm -sticky nsew -padx 2 -pady 2
    
    ttk::frame $w.frmclose
    ttk::button $w.frmclose.b_apply -text [_ "Ok"] -command [list tester::on_ok_define_case $case_id $w] -underline 0
    ttk::button $w.frmclose.b_close -text [_ "Cancel"] -command [list destroy $w] -underline 0
    grid $w.frmclose.b_apply $w.frmclose.b_close -padx 2 -pady 2
    grid $w.frmclose -sticky sew
    grid anchor $w.frmclose center
    grid columnconfigure $w 0 -weight 1
    grid rowconfigure $w 0 -weight 1
    bind $w <Escape> [list $w.frmclose.b_close invoke]
    bind $w <Return> [list $w.frmclose.b_apply invoke]
}


#about window
proc tester::about { } {
    variable private_options
    set text "$private_options(program_name) $private_options(program_version)\n"
    append text "$private_options(program_web)"
    tester::message_box $text info
}


########################################################################
################################# VS ###################################
########################################################################

namespace eval visual_studio {
    variable preferences ;#array to store the public_options showed in the window, and saved to config/preferences.xml (really must be saved in a user place)!!
    variable preferences_defaults ;#internal default values of preferences
    
    set vs_path "C:/Program Files (x86)/Microsoft Visual Studio/2017/Enterprise"
    #set vs_devenv_path [file join $vs_path Common7 IDE]
    #set vs_bat_path [file join $vs_path VC Auxiliary Build]
    array set preferences_defaults {
        vs_path "C:/Program Files (x86)/Microsoft Visual Studio/2017/Enterprise"
        vs_solution "C:/gid project/gidvs/gid.sln"
    }
    variable _current_environment_variables ""
}

proc visual_studio::set_default_preferences { } {
    variable preferences
    variable preferences_defaults
    array set preferences [array get preferences_defaults]
}

proc visual_studio::ask_missing_preferences { } {
    variable private_options
    variable preferences
    variable preferences_defaults    
    foreach key [array names preferences_defaults] {
        if { ![info exists preferences($key)] } {
            set preferences($key) $preferences_defaults($key)
        }        
    }    
    if { $preferences(vs_solution) == "" } {
        set types [list {{Visual studio solution} {.sln}} {{All files} *}]
        set preferences(vs_solution) [tk_getOpenFile -filetypes $types -title "Choose Visual Studio solution to build"]
    }
}

proc visual_studio::save_preferences_variables { fp } {
    variable preferences
    puts $fp "<variables_visual_studio>"
    foreach name [lsort -dictionary [array names preferences]] {
        puts $fp "  <$name>$preferences($name)</$name>"            
    }
    puts $fp "</variables_visual_studio>"
}

proc visual_studio::set_preference { key value } {
    variable preferences
    set preferences($key) $value
}

proc visual_studio::build_solution { solution configuration {project_and_configuration ""} } {
    variable preferences
    set fail 0
    set vs_devenv_path [file join $preferences(vs_path) Common7 IDE]
    set out ""
    if { [llength $project_and_configuration] == 2 } {
        lassign $project_and_configuration project_name project_configuration
        if { [catch { exec [file join $vs_devenv_path devenv] $solution /build $configuration /project $project_name /projectconfig $project_configuration } out] } {
            set fail 1
            error "visual_studio::build_solution. $out"
        }
    } else {        
        if { [catch { exec [file join $vs_devenv_path devenv] $solution /build $configuration } out] } {
            set fail 1
            error "visual_studio::build_solution. $out"
        }
    }
    set last_line [lindex [split $out \n] end]
    regexp {([0-9]+) succeeded, ([0-9]+) failed, ([0-9]+) up-to-date, ([0-9]+) skipped} $last_line dummy succeeded failed up_to_date skipped
    if { ![info exists failed] || $failed } {
        set fail 1
    } else {
        set fail 0
    }
    return $fail
}

proc visual_studio::set_environment_variables { bits } {
    variable preferences
    variable _current_environment_variables
    if { $_current_environment_variables != $bits } {        
        set vs_bat_path [file join $preferences(vs_path) VC Auxiliary Build]
        if { $bits == "64" } {
            set vcvars_bat [file join $vs_bat_path vcvars64.bat]
        } elseif { $bits == "32" } {
            set vcvars_bat [file join $vs_bat_path vcvarsamd64_x86.bat]        
        } else {
            error "unexected bits=$bits"
        }
        exec cmd /C $vcvars_bat
        set _current_environment_variables $bits ;#to avoid repeat
    }
}

proc visual_studio::build_gid { bits } {
    variable preferences
    if { $bits == "64" } {
        set configuration Release|x64
    } elseif { $bits == "32" } {
        set configuration Release|Win32
    } else {
        error "unexected bits=$bits"
    }    
    #set project_and_configuration {gid Release|x64}
    set project_and_configuration ""
    return [visual_studio::build_solution $preferences(vs_solution) $configuration $project_and_configuration]
}

proc visual_studio::build_gid_do { bits } {
    visual_studio::set_environment_variables $bits
    visual_studio::build_gid $bits
}

########################################################################
#################################### GIT ###############################
########################################################################

namespace eval git {
    variable preferences ;#array to store the public_options showed in the window, and saved to config/preferences.xml (really must be saved in a user place)!!
    variable preferences_defaults ;#internal default values of preferences
    array set preferences_defaults {
        project_dir "C:/gid project"
    }
    #project_dir "C:/gid project"
}

proc git::set_default_preferences { } {
    variable preferences
    variable preferences_defaults
    array set preferences [array get preferences_defaults]
}

proc git::ask_missing_preferences { } {
    variable private_options
    variable preferences
    variable preferences_defaults    
    foreach key [array names preferences_defaults] {
        if { ![info exists preferences($key)] } {
            set preferences($key) $preferences_defaults($key)
        }        
    }
    if { $preferences(project_dir) == "" } {
        set preferences(project_dir) [tk_chooseDirectory -title "Choose git project folder (folder that contain .git subfolder)"]
    }
}

proc git::save_preferences_variables { fp } {
    variable preferences
    puts $fp "<variables_git>"
    foreach name [lsort -dictionary [array names preferences]] {
        puts $fp "  <$name>$preferences($name)</$name>"            
    }
    puts $fp "</variables_git>"
}

proc git::set_preference { key value } {
    variable preferences
    set preferences($key) $value
}

proc git::set_project_dir { dir } {
    git::set_preference project_dir $dir
}

proc git::clone { dst_folder } {
    variable preferences
    set fail 0
    set git_dir [file join $preferences(project_dir) .git]
    set out ""
    if { [catch {exec git "--git-dir=$git_dir" "--work-tree=$preferences(project_dir)" clone --single-branch --quiet $preferences(project_dir) $dst_folder} out] } {
        set fail 1
        error "git::clone. $out"
    } else {
    }
    return $fail
}

proc git::checkout { commit detach } {
    variable preferences    
    set fail 0
    set git_dir [file join $preferences(project_dir) .git]
    set out ""
    if { $detach } {
        set ret [catch {exec git "--git-dir=$git_dir" "--work-tree=$preferences(project_dir)" checkout --detach $commit} out]
    } else {
        set ret [catch {exec git "--git-dir=$git_dir" "--work-tree=$preferences(project_dir)" checkout $commit} out]
    }
    if { $ret } {
        #git is returning 1 (fail in theory), but really is ok       
        #set fail 1
        #error "git::checkout. $out"
        if { [string range $out 0 5] == "error:" } {
            set fail 1
            error "git::checkout. $out"
        }        
    } else {
        
    }
    return $fail
}

#since: YYYY MM DD hh mm ss
proc git::list_commits { since max_count } {
    variable preferences
    set git_dir [file join $preferences(project_dir) .git]
    set commits [list]
    lassign $since YYYY MM DD hh mm ss
    set out ""
    if { [catch {exec git "--git-dir=$git_dir" log --format=%H --max-count=$max_count "--since=$YYYY-$MM-$DD $hh:$mm:$ss"} out] } {
        error "git::list_commits. $out"
    } else {
        set commits [split $out \n]
    }
    return $commits
}

proc git::get_current_commit { } {
    variable preferences
    set git_dir [file join $preferences(project_dir) .git]
    set commit ""
    set out ""
    if { [catch {exec git "--git-dir=$git_dir" rev-parse HEAD} out] } {
        error "git::list_commits. $out"
    } else {
        set commit $out
    }
    return $commit
}

proc git::get_master_commit { } {
    variable preferences
    set git_dir [file join $preferences(project_dir) .git]
    set commit ""
    set out ""
    if { [catch {exec git "--git-dir=$git_dir" rev-parse master} out] } {
        error "git::list_commits. $out"
    } else {
        set commit $out
    }
    return $commit
}

proc git::show_commit { commit } {
    variable preferences
    set git_dir [file join $preferences(project_dir) .git]
    set out ""
    if { [catch {exec git "--git-dir=$git_dir" show --no-patch $commit} out] } {
        error "git::show_commit. $out"
    } else {
    }
    return $out
}


########################################################################
########################################################################
########################################################################

tester::start
