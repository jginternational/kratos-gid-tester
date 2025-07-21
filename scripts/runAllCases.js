const abs_path = process.cwd();
const { spawn } = require('child_process');
const path = require('path');
const project_dir = path.join(abs_path, "project", "kratos x64.tester");
const fsExtra = require('fs-extra');
const logdir = path.join(abs_path, "project", "kratos x64.tester", "logfiles");
const casespath = path.join(abs_path, "xmls","tester_cases.xml");

function runAllCases() {

    // Clean previous output
    cleanPreviousLogs()

    // Detectar plataforma y construir parámetros
    let gid_exec, gid_args, working_dir;

    // let run_command = 'tester::run {8B71110A51BC7BD27DE9117E295EDF9C} 0 ; tester::exit'
    let run_command = 'tester::run_all ; tester::exit'

    if (process.platform === 'win32') {
        gid_exec = process.env.CURRENT_GID_PATH;
        working_dir = path.dirname(gid_exec);
        gid_args = [
            '-tclsh', 'E:/PROYECTOS/GiD/gid_project/tester/tester.tcl',
            '-source', 'E:/PROYECTOS/GiD/gid_project/tester/xunit_log.tcl',
            '-xunit_log', 'E:/tmp.xml',
            '-project', project_dir,
            '-gui', '0',
            '-verbose', '1',
            '-eval', run_command
        ];
    } else {
        gid_exec = '/gid/gid';
        working_dir = '/gid';
        gid_args = [
            '-tclsh', '/app/tester/tester.tcl',
            '-source', '/app/tester/xunit_log.tcl',
            '-xunit_log', '/app/output/tamp.xml',
            '-project', project_dir,
            '-gui', '0',
            '-verbose', '1',
            '-eval', run_command
        ];
    }

    console.log(`Running: ${gid_exec} ${gid_args.join(' ')}`);
    console.log(`Working directory: ${working_dir}`);
    process.chdir(working_dir);

    // Ejecutar proceso con salida en tiempo real
    const gidProcess = spawn(gid_exec, gid_args, { stdio: 'inherit' });

    gidProcess.on('close', (code) => {
        console.log(`GID exited with code ${code}`);

        const cases = serializeLogs();
        console.log(cases);

        const has_error = cases.some(c => c.error !== 0);
        process.exit(has_error ? 1 : 0);
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
    
function replace_launch_bat() {
    // RUN rm "/gid/problemtypes/kratos.gid/exec/pip_gids_python.unix.bat"
    // COPY "scripts/dockerlauncher.bat" "/gid/problemtypes/kratos.gid/exec/pip_gids_python.unix.bat"
    const fs = require('fs');
    const sourcePath = path.join(abs_path, "scripts", "dockerlauncher.bat");
    const targetPath = path.join("/gid", "problemtypes", "kratos.gid", "exec", "pip_gids_python.unix.bat");

    // delete the target file if it exists
    if (fs.existsSync(targetPath))
        fs.unlinkSync(targetPath);
    // copy the source file to the target path
    fs.copyFileSync(sourcePath, targetPath);
    console.log(`Replaced ${targetPath} with ${sourcePath}`);
}

// if linux, replace the launch bat file
if (process.platform !== 'win32') {
    replace_launch_bat();
}

runAllCases();
//serializeLogs()