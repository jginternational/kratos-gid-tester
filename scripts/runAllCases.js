// Runs the GiD tester on this project and writes a readable report.
//
// Environment variables (all optional):
//   CURRENT_GID_PATH  GiD executable (Windows only; Linux uses /gid/gid)
//   CASES             comma-separated case names or ids to run (default: all)
//   TAGS              comma-separated tags; runs cases having any of them
//   MAXPROCESS        number of cases run in parallel (default: project preference)
//   OUTPUT_DIR        where results go (default: <repo>/output)
//
// Outputs in OUTPUT_DIR:
//   results.xml       xunit report from the tester
//   summary.md/.json  one entry per case: status, time, Tcl error, failed checks
//   gid.log           stdout/stderr of the tester process
//   models/<case>/    files produced by each case (big meshes/results skipped)

const fs = require('fs');
const fsExtra = require('fs-extra');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');
const xml2js = require('xml2js');

const repo_dir = path.resolve(__dirname, '..');
const project_dir = path.join(repo_dir, 'project', 'kratos x64.tester');
const log_dir = path.join(project_dir, 'logfiles');
const cases_path = path.join(repo_dir, 'xmls', 'tester_cases.xml');
const output_dir = process.env.OUTPUT_DIR || path.join(repo_dir, 'output');
const is_windows = process.platform === 'win32';

const RESULT_CODES = { '-3': 'pending', '-2': 'running', '-1': 'untested', '0': 'ok', '1': 'fail', '2': 'crash', '3': 'timeout', '4': 'maxmemory', '5': 'userstop', '6': 'random' };
const MAX_COPY_BYTES = 20 * 1024 * 1024;
const SKIP_COPY_EXT = ['.msh', '.bin', '.res', '.lst', '.vtk', '.h5', '.ico', '.ini'];

function loadCases() {
    const xml = fs.readFileSync(cases_path, 'utf-8');
    let cases = [];
    new xml2js.Parser().parseString(xml, (err, result) => {
        if (err) throw new Error(`Error parsing ${cases_path}: ${err}`);
        cases = result.cases.case.map(c => ({
            id: c.$.id,
            name: c.name[0],
            batch: c.batch ? c.batch[0] : '',
            tags: (c.tags ? c.tags[0] : '').split(/\s+/).filter(t => t),
            checks: c.check && c.check[0] ? Object.values(c.check[0]).map(v => v[0]) : [],
        }));
    });
    const without_id = cases.filter(c => !c.id);
    if (without_id.length) {
        throw new Error(`Cases without id in ${cases_path}: ${without_id.map(c => c.name).join(', ')}`);
    }
    return cases;
}

function selectCases(cases) {
    const list = v => (v || '').split(',').map(s => s.trim()).filter(s => s);
    const wanted = list(process.env.CASES);
    const tags = list(process.env.TAGS);
    if (!wanted.length && !tags.length) return null; // run_all

    const selected = cases.filter(c =>
        wanted.includes(c.name) || wanted.includes(c.id) || c.tags.some(t => tags.includes(t)));
    const unknown = wanted.filter(w => !cases.some(c => c.name === w || c.id === w));
    if (unknown.length) throw new Error(`Unknown cases: ${unknown.join(', ')}`);
    if (!selected.length) throw new Error('No case matches CASES/TAGS');
    return selected;
}

function testerCommand(selected) {
    let cmd = '';
    if (process.env.MAXPROCESS) cmd += `tester::set_preference maxprocess ${parseInt(process.env.MAXPROCESS)}; `;
    cmd += selected ? `tester::run {${selected.map(c => c.id).join(' ')}} 0; ` : 'tester::run_all; ';
    return cmd + 'tester::exit';
}

function gidCommand(run_command) {
    const tester_dir = path.join(repo_dir, 'scripts');
    const exe = is_windows ? process.env.CURRENT_GID_PATH : '/gid/gid';
    if (!exe) throw new Error('Set CURRENT_GID_PATH to the GiD executable');
    const args = [
        '-tclsh', path.join(tester_dir, 'tester.tcl'),
        '-source', path.join(tester_dir, 'xunit_log.tcl'),
        '-xunit_log', path.join(output_dir, 'results.xml'),
        '-project', project_dir,
        '-gui', '0',
        '-verbose', '1',
        '-eval', run_command,
    ];
    return { exe, args, cwd: path.dirname(exe) };
}

// Tester log line: "<time> <date> <case_id> <code> {key value ... error {msg}}"
// or "<time> <date> error {case <case_id> <msg>}"
function parseTesterLog() {
    const logfile = path.join(log_dir, 'tester.log');
    if (!fs.existsSync(logfile)) return [];
    const runs = [];
    for (const line of fs.readFileSync(logfile, 'utf-8').split('\n')) {
        const parts = line.split(' ');
        if (parts.length < 4) continue;
        if (parts[2] === 'error') {
            const m = line.match(/error \{case ([0-9A-Fa-f]+) (.*)\}\s*$/);
            if (m) runs.push({ id: m[1], code: null, note: m[2] });
            continue;
        }
        const rest = parts.slice(4).join(' ');
        const err = rest.match(/ error \{(.*)\}\}\s*$/s);
        const time = rest.match(/\btime (\d+)/);
        runs.push({
            id: parts[2],
            code: parts[3],
            time: time ? parseInt(time[1]) : null,
            error: err ? err[1].replace(/\\n/g, '\n') : '',
        });
    }
    return runs;
}

// Failed checks per case from the xunit report
function parseXunitFailures() {
    const file = path.join(output_dir, 'results.xml');
    const failures = {};
    if (!fs.existsSync(file)) return failures;
    const xml = fs.readFileSync(file, 'utf-8');
    for (const m of xml.matchAll(/<testcase([^>]*)>([\s\S]*?)<\/testcase>/g)) {
        const name = (m[1].match(/name="([^"]*)"/) || [])[1];
        const body = m[2];
        if (!name || !/<(failure|error)/.test(body)) continue;
        failures[name] = body.replace(/<!\[CDATA\[|\]\]>/g, '').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
    }
    return failures;
}

function newestTesterTmpFolder(since_ms) {
    const tmp = os.tmpdir();
    const dirs = fs.readdirSync(tmp)
        .filter(d => d.startsWith('_tester-'))
        .map(d => path.join(tmp, d))
        .filter(d => fs.statSync(d).mtimeMs >= since_ms)
        .sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs);
    return dirs.length ? dirs[0] : null;
}

function tail(file, bytes = 3000) {
    if (!fs.existsSync(file)) return null;
    const size = fs.statSync(file).size;
    if (size === 0) return '';
    const fd = fs.openSync(file, 'r');
    const buf = Buffer.alloc(Math.min(bytes, size));
    fs.readSync(fd, buf, 0, buf.length, size - buf.length);
    fs.closeSync(fd);
    return buf.toString('utf-8');
}

function collectModel(tmp_folder, case_name) {
    const model = { files: [], err_tail: null, info_tail: null };
    if (!tmp_folder) return model;
    const src = path.join(tmp_folder, `${case_name}.gid`);
    if (!fs.existsSync(src)) return model;
    const dst = path.join(output_dir, 'models', case_name);
    fsExtra.ensureDirSync(dst);
    for (const f of fs.readdirSync(src)) {
        const p = path.join(src, f);
        const st = fs.statSync(p);
        if (!st.isFile()) continue;
        model.files.push({ name: f, size: st.size });
        const skip = st.size > MAX_COPY_BYTES || SKIP_COPY_EXT.some(e => f.endsWith(e));
        if (!skip) fs.copyFileSync(p, path.join(dst, f));
    }
    model.err_tail = tail(path.join(src, `${case_name}.err`));
    model.info_tail = tail(path.join(src, `${case_name}.info`), 1500);
    return model;
}

function writeReport(cases, selected, t_start, exit_code) {
    const runs = parseTesterLog();
    const failures = parseXunitFailures();
    const tmp_folder = newestTesterTmpFolder(t_start);
    const by_id = Object.fromEntries(cases.map(c => [c.id, c]));
    const ran = selected || cases;

    const results = ran.map(c => {
        const case_runs = runs.filter(r => r.id === c.id);
        const last = [...case_runs].reverse().find(r => r.code !== null);
        const notes = case_runs.filter(r => r.code === null).map(r => r.note);
        const status = last ? (RESULT_CODES[last.code] || `code ${last.code}`) : 'not run';
        return {
            name: c.name, id: c.id, status,
            time: last ? last.time : null,
            tcl_error: last ? last.error : '',
            failed_checks: failures[c.name] || '',
            notes,
            model: collectModel(tmp_folder, c.name),
        };
    });
    // Log entries for ids not in the catalogue (e.g. a case saved with an empty id)
    const unknown = [...new Set(runs.map(r => r.id).filter(id => !by_id[id]))];

    fs.writeFileSync(path.join(output_dir, 'summary.json'), JSON.stringify({ tmp_folder, gid_exit_code: exit_code, unknown_ids: unknown, results }, null, 2));

    const count = s => results.filter(r => r.status === s).length;
    let md = `# Tester summary\n\n${results.length} cases: ${count('ok')} ok, ${results.length - count('ok')} not ok. GiD exit code ${exit_code}.\n\n`;
    md += '| Case | Status | Time (s) |\n|---|---|---|\n';
    for (const r of results) md += `| ${r.name} | ${r.status} | ${r.time ?? ''} |\n`;
    for (const r of results.filter(r => r.status !== 'ok')) {
        md += `\n## ${r.name} — ${r.status}\n\n`;
        if (r.tcl_error) md += `Tcl error:\n\n\`\`\`\n${r.tcl_error}\n\`\`\`\n\n`;
        if (r.failed_checks) md += `Failed checks: \`${r.failed_checks.slice(0, 1500)}\`\n\n`;
        if (r.notes.length) md += `Tester notes: ${r.notes.join('; ')}\n\n`;
        if (r.model.files.length) md += `Files: ${r.model.files.map(f => `${f.name} (${f.size})`).join(', ')}\n\n`;
        else md += 'No model folder was produced.\n\n';
        if (r.model.err_tail) md += `.err (tail):\n\n\`\`\`\n${r.model.err_tail}\n\`\`\`\n\n`;
        if (r.model.info_tail) md += `.info (tail):\n\n\`\`\`\n${r.model.info_tail}\n\`\`\`\n\n`;
    }
    if (unknown.length) md += `\nLog entries for ids not in tester_cases.xml: ${unknown.join(', ')}\n`;
    fs.writeFileSync(path.join(output_dir, 'summary.md'), md);
    return results;
}

function replaceLaunchBat() {
    // In Docker, run Kratos with GiD's python through our own launcher
    const source = path.join(repo_dir, 'scripts', 'dockerlauncher.bat');
    const target = path.join('/gid', 'problemtypes', 'kratos.gid', 'exec', 'pip_gids_python.unix.bat');
    if (!fs.existsSync(path.dirname(target))) return;
    fs.copyFileSync(source, target);
    console.log(`Replaced ${target} with ${source}`);
}

function main() {
    const cases = loadCases();
    const selected = selectCases(cases);
    if (!is_windows) replaceLaunchBat();

    fsExtra.emptyDirSync(log_dir);
    fsExtra.ensureDirSync(output_dir);
    fsExtra.removeSync(path.join(output_dir, 'models'));

    const { exe, args, cwd } = gidCommand(testerCommand(selected));
    console.log(`Running ${selected ? selected.length : 'all'} cases: ${exe} ${args.join(' ')}`);

    const t_start = Date.now() - 1000;
    const gid_log = fs.createWriteStream(path.join(output_dir, 'gid.log'));
    const gid = spawn(exe, args, { cwd, stdio: ['ignore', 'pipe', 'pipe'] });
    for (const stream of [gid.stdout, gid.stderr]) {
        stream.on('data', d => { process.stdout.write(d); gid_log.write(d); });
    }

    gid.on('close', code => {
        gid_log.end();
        const results = writeReport(cases, selected, t_start, code);
        const bad = results.filter(r => r.status !== 'ok');
        console.log(`\n${results.length - bad.length}/${results.length} ok. Report: ${path.join(output_dir, 'summary.md')}`);
        bad.forEach(r => console.log(`  ${r.status.padEnd(9)} ${r.name}${r.tcl_error ? ' (Tcl error)' : ''}`));
        process.exit(bad.length ? 1 : 0);
    });
}

main();
