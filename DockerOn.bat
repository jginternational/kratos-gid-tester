docker build -t kratos-tester .
docker run -it --name kratos-tester kratos-tester

@REM /gid/tclsh /app/tester/tester.tcl -project "/app/project/kratos x64.tester" -source /app/tester/xunit_log.tcl -xunit_log /app/tester/tamp.xml  -gui 0 -verbose 1 -eval "tester::run_all; tester::exit"