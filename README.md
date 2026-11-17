# kratos-gid-tester

Integration tests for the Kratos Multiphysics problemtype for GiD ([GiDInterface](https://github.com/KratosMultiphysics/GiDInterface)).

Each test case opens GiD in batch mode, loads the `kratos` problemtype, builds one of its examples, meshes it, writes the Kratos input files and, for `*_calculate` cases, runs the simulation. A case passes if the files it produced pass its checks (see `xmls/tester_cases.xml`).

For the structure of the repo and how to add cases, see [AGENTS.md](./AGENTS.md).

## Requirements

- GiD (the same version the problemtype targets; currently 17.1.4d is used locally and `gidhome/docker-unix-developer:17.2.0-IR` in Docker).
- Kratos installed in GiD's python: `<gid>/pip install KratosMultiphysics[all]==10.4.3`.
- The `kratos.gid` folder you want to test available in GiD's `problemtypes` folder (a copy or a link to your GiDInterface checkout).
- Node.js (≥ 18) for the runner.
- If you run a newer tester from GiD's sources (`gid_project/tester/tester.tcl`, v1.9+), it needs the `gid_math_utils` package, which released GiD versions (≤ 18.0) do not ship. Copy `gid_project/scripts/gid_math_utils` into `<gid>/scripts/`. The vendored `scripts/tester.tcl` (v1.8) does not need it.

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
3. Check the machine-specific paths in `project/kratos x64.tester/config/preferences.xml`: `basecasesdir`, `exe` (the GiD that runs each case), `debug_exe`, `gidini`.
4. Run all cases:
   ```
   npm start
   ```

The runner wipes `project/kratos x64.tester/logfiles/`, runs the cases, prints the failing ones and exits with code `1` if any case failed (`0` otherwise). See [Output](#output). The `CASES`, `TAGS` and `MAXPROCESS` variables described in Option B also work locally, e.g. `set CASES=fluid_2d_cylinderinflow_write`.

### Tester window

`scripts/open-window.bat` opens the tester GUI on this project, where you can filter by tag, run individual cases and see their history. Adjust its paths first.

## Option B: Run in Docker (recommended, same environment as CI)

The image contains GiD 17.2.0-IR (Linux), Kratos in GiD's python and, by default, the `master` branch of GiDInterface. Mount your own checkout to test it instead:

```
docker build -t kratos-tester .
docker run --rm -v <GiDInterface>/kratos.gid:/src/kratos.gid:ro -v <abs path>/output:/app/output kratos-tester
```

Environment variables (`-e NAME=value`):

| Variable | Meaning |
|---|---|
| `CASES` | Comma-separated case names or ids to run (default: all). |
| `TAGS` | Comma-separated tags; runs the cases that have any of them (e.g. `DEM,Fluid`). |
| `MAXPROCESS` | Cases run in parallel (default 4 from `preferences_docker.xml`). Use `1` for a stable baseline: the `_calculate` batches kill Kratos after 10 s, so under load they can fail without a real error. |

Example, two cases one at a time:

```
docker run --rm -v E:/src/GiDInterface/kratos.gid:/src/kratos.gid:ro -v E:/src/KratosTester/output:/app/output -e CASES=dem_2d_circledrop_write,fsi_2d_mok_calculate -e MAXPROCESS=1 kratos-tester
```

The mounted folder is copied inside the container, so the tester never writes into your checkout. `kratos.gid/exec/pip_gids_python.unix.bat` is replaced by `scripts/dockerlauncher.bat` in that copy.

Results differ between GiD versions and platforms (e.g. meshes are not identical between GiD 17.1.4d on Windows and 17.2.0-IR on Linux), so a case can pass in Docker and fail locally. CI uses Docker.

## Output

Both options write to `output/` (or `OUTPUT_DIR`):

- `summary.md` / `summary.json` — status and time per case; for each failing case, the Tcl error reported by the tester, the failed checks, the list of files produced and the tail of its `.err` and `.info`.
- `results.xml` — xunit report.
- `gid.log` — output of the tester process.
- `models/<case>/` — files produced by each case (meshes, results and files over 20 MB are skipped).

## CI

The GiDInterface workflow `.github/workflows/tester.yml` runs the image `fjgarate/kratos-tester` on a self-hosted runner, on pushes to `master` and on PRs labelled `safe-to-test`. `deploy.bat` builds and pushes that image (and force-pushes a git tag); only run it when releasing a new tester version.
