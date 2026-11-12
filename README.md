# kratos-gid-tester

Integration tests for the Kratos Multiphysics problemtype for GiD ([GiDInterface](https://github.com/KratosMultiphysics/GiDInterface)).

Each test case opens GiD in batch mode, loads the `kratos` problemtype, builds one of its examples, meshes it, writes the Kratos input files and, for `*_calculate` cases, runs the simulation. A case passes if the files it produced pass its checks (see `xmls/tester_cases.xml`).

For the structure of the repo and how to add cases, see [AGENTS.md](./AGENTS.md).

## Requirements

- GiD (the same version the problemtype targets; currently 17.1.4d is used locally and `gidhome/docker-unix-developer:17.2.0-IR` in Docker).
- Kratos installed in GiD's python: `<gid>/pip install KratosMultiphysics[all]==10.4.3`.
- The `kratos.gid` folder you want to test available in GiD's `problemtypes` folder (a copy or a link to your GiDInterface checkout).
- Node.js (≥ 18) for the runner.

## Option A: Run locally (Windows)

1. Install the runner dependencies:
   ```
   npm install
   ```
2. Point the runner at your GiD executable:
   ```
   set CURRENT_GID_PATH=E:/GiD/GiD 17.1.4d/gid.exe
   ```
   (or use the *Launch Program* configuration in `.vscode/launch.json`, which already sets it).
3. Check the machine-specific paths, which are currently hard-coded:
   - `scripts/runAllCases.js` (Windows branch): `-tclsh`, `-source` and `-xunit_log` paths.
   - `project/kratos x64.tester/config/preferences.xml`: `basecasesdir`, `exe`, `debug_exe`, `gidini`.
4. Run all cases:
   ```
   npm start
   ```

The runner wipes `project/kratos x64.tester/logfiles/`, runs every case, prints the failing ones and exits with code `1` if any case failed (`0` otherwise). xunit results are written to `output/results.xml`. Models are created in the tester's temporary folder (`tester::get_tmp_folder`), one `<case name>.gid` per case.

### Running a single case

In `scripts/runAllCases.js`, replace the `run_command` with the commented-out form, using the case `id` from `xmls/tester_cases.xml`:

```js
let run_command = 'tester::run {<case id>} 0 ; tester::exit'
```

### Tester window

`scripts/open-window.bat` opens the tester GUI on this project, where you can filter by tag, run individual cases and see their history. Adjust its paths first.

## Option B: Run in Docker (Linux container)

The image installs GiD, Kratos and the **`master` branch of GiDInterface from GitHub** (not your local checkout):

```
docker build -t kratos-tester .
docker run --rm -v ./output:/app/output kratos-tester
```

In Docker, `kratos.gid/exec/pip_gids_python.unix.bat` is replaced by `scripts/dockerlauncher.bat`.

## CI

The GiDInterface workflow `.github/workflows/tester.yml` runs the image `fjgarate/kratos-tester` on a self-hosted runner, on pushes to `master` and on PRs labelled `safe-to-test`. `deploy.bat` builds and pushes that image (and force-pushes a git tag); only run it when releasing a new tester version.
