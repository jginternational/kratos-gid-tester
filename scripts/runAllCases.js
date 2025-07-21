const abs_path = process.cwd();
const path = require('path');
const project_dir = path.join(abs_path, "project", "kratos x64.tester");
const fsExtra = require('fs-extra');
const { exit } = require('process');
const logdir = path.join(abs_path, "project", "kratos x64.tester", "logfiles");
const casespath = path.join(abs_path, "xmls","tester_cases.xml");

function runAllCases() {

    // Clean previous output
    cleanPreviousLogs()

    //var exepath = path.join(abs_path, "scripts", "tester-windows-64.exe");
    // var exe_name  = process.platform === "win32" ? "tester-windows-64.exe" : "tester-linux-64";
    // var exepath = path.join(abs_path, "scripts", exe_name);
    // var command = exepath + ' -project \"' + project_dir + '\"';
    // command += ' -gui 0 -eval "tester::run_all; tester::exit"';
        //var exepath = path.join(abs_path, "scripts", "tester-windows-64.exe");
    if (process.platform === "win32") {
        // gid path from environment variable
        var gid_path = process.env.CURRENT_GID_PATH;
        var gid_folder = path.dirname(gid_path);
        var command = '"' + gid_path + '" -tclsh E:/PROYECTOS/GiD/gid_project/tester/tester.tcl  -source E:/PROYECTOS/GiD/gid_project/tester/xunit_log.tcl -xunit_log E:/tmp.xml -project \"' + project_dir + '\"';
        var extra_flags = '';
        process.chdir(gid_folder);
    } else {
        var exepath = path.join(abs_path, "tester", "tester");
        var command = '/gid/gid -tclsh /app/tester/tester.tcl -project \"' + project_dir + '\"';
        var extra_flags = ' -source /app/tester/xunit_log.tcl -xunit_log /app/tester/tamp.xml ';
        process.chdir('/gid');
    }
    command += extra_flags + ' -gui 0 -verbose 1 -eval "tester::run_all ; tester::exit"';

    // redirect output to standard output
    command += ' > ' + path.join("/tester.log") + ' 2>&1';

// /gid/tclsh /app/tester/tester.tcl - project /app/project/kratos x64.tester -source /app/tester/xunit_log.tcl -xunit_log /app/tester/tamp.xml -gui 0 -verbose 1 -eval "tester::run; tester::exit"
// &"E:/GiD/GiD 17.1.4d/gid.exe" -tclsh "E:/PROYECTOS/GiD/gid_project/tester/tester.tcl" -project "E:/PROYECTOS/KRATOS/KratosTester/project/kratos x64.tester" -gui 0 -verbose 1 -eval "tester::run; tester::exit"
    console.log(command);
    // print current working directory
    console.log(`Current working directory: ${abs_path}`);
    const { exec } = require('child_process');
    exec(command, (err, stdout, stderr) => {
        if (err) {
            // node couldn't execute the command
            console.log(`ERROR executing tests`);
            console.log(stderr);
            return;
        }

        // the *entire* stdout and stderr (buffered)
        console.log(`FINISH TESTS`);
        var cases = serializeLogs();
        console.log(cases);
        
        // if any case has an error, exit with error code
        var has_error = cases.some(case_item => case_item.error !== 0);
        if (has_error) {
            console.log(`Some cases failed, exiting with error code`);
            exit(1);
        } else {
            console.log(`All cases passed, exiting with success code`);
            exit(0);
        }
    });
};

function cleanPreviousLogs() {
    console.log(`Clear logs at ` + logdir);
    fsExtra.emptyDirSync(logdir);
}

function serializeLogs() {
    var logfile = path.join(logdir, "tester.log");
    console.log(`Reading log file: ${logfile}`);

    var lines = require('fs').readFileSync(logfile, 'utf-8').split('\n');

    // load cases xml file
    var casesxml = require('fs').readFileSync(casespath, 'utf-8');
    // parse xml to json
    var xml2js = require('xml2js');
    var parser = new xml2js.Parser();
    var defined_cases = [];
    parser.parseString(casesxml, function (err, result) {
        if (err) {
            console.error(`Error parsing cases XML: ${err}`);
            return;
        }
        //console.log(result);
        //console.log(JSON.stringify(result, null, 2));
        //console.log(result.tester_cases.case);
        var cases_json = result.cases.case;
        cases_json.forEach(case_item => {
            var id = case_item.$.id;
            var name = case_item.name[0];
            var run_case = { id: id, name: name };
            defined_cases.push(run_case);
        });
    });


    var runned_cases = [];
    lines.forEach(line => {
        console.log(line);
        var res = line.split(" ");
        var error;
        var error_msg = "";
        if (res.length > 4) {
            var caseid = res[2];
            if (caseid === "error") {
                caseid = res[4];
                error = 1;
                error_msg = res.slice(5).join(" ");
                res[5] = res.slice(5).join(" ");
            } else {
                error = res[3];
            }
            var datetime = new Date(res[1] + " " + res[0]);
            //console.log(datetime.toDateString() + " " + caseid + " " + error);
            // find case in defined_cases
            var case_name = defined_cases.find(c => c.id === caseid).name;
            var run_case = { caseid: caseid, name: case_name, datetime: datetime, error: error, error_code: getResultDescription(error), error_msg: error_msg };
            console.log(run_case);
            runned_cases.push(run_case);
        }
    });
    return runned_cases;
}

// gets the description of the error code
// input 0 -> return "ok"
function getResultDescription(error) {
    var array_result_code = {
        "pending": -3,
        "running": -2,
        "untested": -1,
        "ok": 0,
        "fail": 1,
        "crash": 2,
        "timeout": 3,
        "maxmemory": 4,
        "userstop": 5,
        "random": 6
    };
    for (var key in array_result_code) {
        if (array_result_code[key] == error) {
            return key;
        }
    }
    return "unknown";
}
    
runAllCases();
//serializeLogs()