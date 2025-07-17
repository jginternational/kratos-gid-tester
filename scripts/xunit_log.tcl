proc ::tester::xunit_get_timestamp { } {
    return [ clock format [ clock seconds] -format {%Y-%m-%d %H:%M:%S}]
}

# xunit_filename
proc ::tester::xunit_xml_open { } {
    variable private_options
    variable preferences

    if { ![ info exists private_options(xunit_filename)]} {
        return
    }
    set project_title \
        "[ file tail $private_options(project_path)] ( $preferences(branch_provide) $preferences(platform_provide) )"
    set time_stamp [ tester::xunit_get_timestamp]
    set private_options(xunit_doc_tini) [ clock seconds]
    set private_options(xunit_doc) [ dom parse "<testsuite name=\"$project_title\" file=\"$private_options(project_path)\" timestamp=\"$time_stamp\"/>"]
}

proc ::tester::xunit_xml_add_case_result { state } {
    variable private_options
    
    # puts "xunit_xml_add_case_result $state"
    if { ![ info exists private_options(xunit_doc)]} {
        # try to create document if asked:
        tester::xunit_xml_open
        # if not created then it was not asked...
        if { ![ info exists private_options(xunit_doc)]} {
            return
        }
    }

    # puts "getting tdom values"
    # get tdom values
    set docElement [ $private_options(xunit_doc) documentElement]
    set testsuiteElement [ $docElement selectNodes /testsuite]
    # failure = test was executed but failed
    # error = test caused an error during execution
    foreach attr [ list tests failures errors skipped] {
        set num($attr) 0
        if { [ $testsuiteElement hasAttribute $attr]} {
            set num($attr) [ $testsuiteElement getAttribute $attr]
            # $testsuiteElement removeAttribute $attr
        }
    }

    # update values
    incr num(tests)
    if { $state == "fail"} {
        incr num(failures)
        # xml_create_text_node <failure type="...." message="...."> <![CDATA[ ... ]]></failure>
    } elseif { $state == "ok"} {
    } else {
        # crash, timeout, etc...
        incr num(errors)
        # xml_create_text_node <error type="...." message="...."> <![CDATA[ ... ]]></failure>
    }

    # save them in tdom
    # if you change private_options(xunit_$attr) please review tester::exit_with_error_code
    foreach attr [ list tests failures errors skipped] {
        $testsuiteElement setAttribute $attr $num($attr)
        set private_options(xunit_$attr) $num($attr)
    }
}

proc ::tester::xunit_xml_write { } {
    variable private_options

    # puts "tester::xunit_xml_write"
    if { ![ info exists private_options(xunit_filename)]} {
        return
    }
    if { ![ info exists private_options(xunit_doc)]} {
        return
    }

    # add time attribute
    if { [ info exists private_options(xunit_doc_tini)]} {
        set docElement [ $private_options(xunit_doc) documentElement]
        set testsuiteElement [ $docElement selectNodes /testsuite]
        $testsuiteElement setAttribute time [ expr [ clock seconds] - $private_options(xunit_doc_tini)]
    }

    tester::save_xml_file $private_options(xunit_doc) $private_options(xunit_filename)
    tester::set_message "$private_options(xunit_filename) saved."
    set txt ""
    foreach attr [ list tests failures errors skipped] {
        append txt "$attr = $private_options(xunit_$attr)   "
    }
    tester::set_message $txt
}

proc ::tester::xunit_get_checks_and_results { case_id which} {
    # which can be fail, ok, all, or ... (error)
    set checks [tester::get_checks $case_id]
    set implicit_check_outputfiles [tester::exists_variable $case_id outputfiles]
    if { $implicit_check_outputfiles } {
        set checks [list outputfiles {*}$checks]
    }

    set lst_checks_ok {}
    set lst_checks_fail {}
    set lst_checks_error {}

    # get results of checks:    
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

    foreach check $checks {
        if { $check == "outputfiles" } {
            set test outputfiles
        } else {
            set test [tester::get_variable $case_id check,$check]
        }
        if { [tester::exists_variable $case_id checkresult,$check] } {
            set ok_check [tester::get_variable $case_id checkresult,$check]            
            if { $ok_check == 0 } {
                set result_string "fail"
            } elseif { $ok_check == 1 } {
                set result_string "ok"
            } elseif { $ok_check == 2 } {
                set result_string "crash"
            } elseif { $ok_check == 3 } {
                set result_string "timeout"
            } elseif { $ok_check == 4 } {
                set result_string "maxmemory"
            } elseif { $ok_check == 5 } {
                set result_string "userstop"
            } elseif { $ok_check == 6 } {
                set result_string "random"
            } else {
                set result_string "crash"
            }
            set check_and_result $test
            # get result of check
            if { ![catch { set kk [namespace eval $ns [list subst $test]] } err] } {
                set check_and_result "$test ( $kk )"
            }
            if { $result_string == "ok"} {
                lappend lst_checks_ok $check_and_result
            } elseif { $result_string == "fail"} {
                lappend lst_checks_fail $check_and_result
            } else {
                lappend lst_checks_error $check_and_result
            }
        }    
    }
    if { $which == "all"} {
        return [ concat $lst_checks_ok $lst_checks_fail $lst_checks_error]
    } elseif { $which == "ok"} {
        return $lst_checks_ok
    } elseif { $which == "fail"} {
        return $lst_checks_fail
    } else {
        return $lst_checks_error
    }
}

proc ::tester::xunit_xml_add_case_info { case_id} {
    variable private_options

    # puts "tester::xunit_xml_add_case_info"

    set docElement [ $private_options(xunit_doc) documentElement]
    # set testsuiteElement [ $docElement selectNodes /testsuite]

    # create element <testcase classname="test2.TestSequenceFunctions" name="test_skipped" time="0.000" timestamp="2020-08-10T20:06:50" file="test2.py" line="11">

    array set case_results [tester::get_variable $case_id results]
    set testcase_attrs [ list name [ tester::get_variable $case_id name] \
                             classname $case_id \
                             timestamp [ tester::xunit_get_timestamp]]
    if { [ info exists case_results(elapsedtime)]} {
        lappend testcase_attrs time
        lappend testcase_attrs $case_results(elapsedtime)
    }

    set testcaseElement [ tester::xml_create_element $docElement testcase $testcase_attrs]

    # calculate execution time
    # $testcaseElement setAttribute time [expr ...]
    set result [tester::evaluate_checks $case_id]
    # set result_code [tester::get_result_code $result]

    # puts "state $case_id = $result"

    # result shows the type of error: crash, timeout, maxmemory, userstop, random, ...
    if { $result == "fail"} {
        # xml_create_text_node <failure type="...." message="...."> <![CDATA[ ... ]]></failure>
        
        set failureElement  [ tester::xml_create_element $testcaseElement failure \
                                  [ list type "checkFailed" message "one of the checks failed"]]
        set failure_txt ""
        foreach check [ tester::xunit_get_checks_and_results $case_id "fail"] {
            append failure_txt $check\n
        }
        tester::xml_create_CDATA_section $failureElement $failure_txt
    } elseif { $result == "ok"} {
    } else {
        # crash, timeout, etc...
        # incr num(errors)
        # xml_create_text_node <error type="...." message="...."> <![CDATA[ ... ]]></failure>
        set error_txt "$result error executing test"
        if { $result == "timeout"} {
            set error_txt "run time limit of [ tester::get_variable $case_id timeout] s. exceded."
        } elseif { $result == "maxmemory"} {
            set maxmemory [ tester::get_maxmemory $case_id]
            set error_txt "memory limit of $maxmemory bytes exceded."
        }
        set errorElement  [ tester::xml_create_element $testcaseElement error \
                                [ list type "$result" message $error_txt]]
        append error_txt "\n"
        foreach check [ tester::xunit_get_checks_and_results $case_id "error"] {
            append error_txt $check\n
        }
        tester::xml_create_CDATA_section $errorElement $error_txt
    }

    set txt "# Results:\n"
    foreach { k v} [tester::get_variable $case_id results] {
        append txt "$k $v\n"
    }

    # puts checks nicely
    append txt "# Checks:\n"
    foreach check [ tester::xunit_get_checks_and_results $case_id "all"] {
        append txt $check\n
    }        

    set systemOutput  [ tester::xml_create_element $testcaseElement system-output ]
    tester::xml_create_CDATA_section $systemOutput $txt
    set txt ""
    set systemError  [ tester::xml_create_element $testcaseElement system-error ]
    tester::xml_create_CDATA_section $systemError $txt
    return
                                    
    # <system-out><![CDATA[]]></system-out>
    # <system-err><![CDATA[]]></system-err>
    # </testcase>
    $docElement appendChild $testcaseElement
    # puts "created $testcaseElement with name [ tester::get_variable $case_id name]"
}

# end xunit_filename

proc ::tester::event_before_run_cases { lst_cases_ids} {
    # puts "before_run_cases = [ llength $lst_cases_ids] cases to run"
    variable private_options
    set private_options(total_num_cases_to_run) [ llength $lst_cases_ids]
    tester::xunit_xml_open    
}

proc ::tester::event_after_run_case { case_id} {
    variable private_options
    set result [tester::evaluate_checks $case_id]
    set result_code [tester::get_result_code $result]
    # tester::puts_log [list $case_id $result_code [tester::get_variable $case_id results]]
    if { [ info exists private_options(total_num_cases_to_run)] || \
             [ info exists private_options(xunit_tests)]} {
        set case_idx 1
        if { [ info exists private_options(xunit_tests)]} {
            set case_idx [ expr $private_options(xunit_tests) + 1]
        }
        set txt "case $case_idx"
        if { [ info exists private_options(total_num_cases_to_run)]} {
            append txt " of $private_options(total_num_cases_to_run)"
        }
        tester::set_message "${txt}: $case_id $result_code $result"
    } else {
        tester::set_message "$case_id $result_code $result"
    }
    if { $result_code >= 0} {
        # skip "running" -2 or "untested" -1 cases
        set err [ catch {
            tester::xunit_xml_add_case_result $result
        } err_txt]
        if { $err} {
            puts "Error : $err_txt"
        }
        set err [ catch {
            tester::xunit_xml_add_case_info $case_id
        } err_txt]
        if { $err} {
            puts "Error : $err_txt"
        }
    }
}

proc ::tester::event_after_run_cases { case_ids} {
    tester::xunit_xml_write
}

# use command line argument: -xunit_log xunit_filename
# because because read_project does a chdir
# proc ::tester::xunit_start { xunit_filename} {
#     variable private_options
#     if { $xunit_filename != ""} {
#         set private_options(xunit_filename) [ file normalize $xunit_filename]
#     }
# }
