
export TESTERDIR="/app/tester"
echo "TESTERDIR = $TESTERDIR"
# if we pass '$1' as command line argument to python -m ....
# it will be handled as module to be loaded and issue an error
# so, passing it as environment variable....
export EXE_MODE="$1"

# needed by some test cases like 2D64BA7A8706C023860594E839DBB82E
export GIDDEFAULT=/gid/

# and for any case:
export GIDDEFAULTTCL=$GIDDEFAULT/scripts/

# pipeline.tester defines
#   <basecasesdir>/GID-prebuild/tester_gid</basecasesdir>

win_tester_project="/app/project/kratos x64.tester"
# gid_exe="$BASEDIR/../run_gid_debug.sh"
gid_exe="/gid/gidx"
# extra_flags=-debug

echo "Tester project = $win_tester_project"

if [ ! -d /test-reports ] ; then
    mkdir /test-reports
fi

echo "$gid_exe -tclsh $TESTERDIR/tester.tcl -project $win_tester_project -gui 0 -source $TESTERDIR/xunit_log.tcl -xunit_log /test-reports/logs.xml -verbose 1 -eval 'tester::run_all ; tester::exit_with_error_code'"
$gid_exe -debug -tclsh "$TESTERDIR"/tester.tcl -project "$win_tester_project" -gui 0 -source "$TESTERDIR"/xunit_log.tcl -xunit_log /test-reports/logs.xml -verbose 1 -eval "tester::run_all ; tester::exit_with_error_code"
tester_code=$?
echo "Tester returned error code: $tester_code"
exit $tester_code
