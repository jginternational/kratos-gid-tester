const abs_path = process.cwd();
const path = require('path');
const project_dir = path.join(abs_path, "project", "kratos x64.tester");
const fsExtra = require('fs-extra');
const logdir = path.join(abs_path, "project", "kratos x64.tester", "logfiles");

function runAllCases() {

    // Clean previous output
    cleanPreviousLogs()

    //var exepath = path.join(abs_path, "scripts", "tester-windows-64.exe");
    var exe_name  = process.platform === "win32" ? "tester-windows-64.exe" : "tester-linux-64";
    var exepath = path.join(abs_path, "scripts", exe_name);
    var command = exepath + ' -project \"' + project_dir + '\"';
    command += ' -gui 0 -eval "tester::run_all; tester::exit"';

    console.log(command);
    const { exec } = require('child_process');
    exec(command, (err, stdout, stderr) => {
        if (err) {
            // node couldn't execute the command
            console.log(`ERROR`);
            console.log(stderr);
            return;
        }

        // the *entire* stdout and stderr (buffered)
        console.log(`FINISH TESTS`);
        var cases = serializeLogs();
        console.log(cases);
    });
};

function cleanPreviousLogs() {
    console.log(`Clear logs at ` + logdir);
    fsExtra.emptyDirSync(logdir);
}

function serializeLogs() {
    var logfile = path.join(logdir, "tester.log");

    var cases = [];
    var lines = require('fs').readFileSync(logfile, 'utf-8').split('\n');
    lines.forEach(line => {
        //console.log(line);
        var res = line.split(" ");
        if (res.length > 4) {
            var caseid = res[2];
            var error = res[3];
            var datetime = new Date(res[1] + " " + res[0]);
            //console.log(datetime.toDateString() + " " + caseid + " " + error);
            var run_case = { caseid: caseid, datetime: datetime, error: error };
            //console.log(run_case);
            cases.push(run_case);
        }
    });
    return cases;
}

//console.log(serializeLogs());
runAllCases();