# AGENTS.md

Guidance for AI coding agents (and humans) working on **kratos-gid-tester**, the integration test suite of the Kratos ↔ GiD problemtype ([GiDInterface](https://github.com/KratosMultiphysics/GiDInterface), `kratos.gid/`).
For how to run it, see [README.md](./README.md).

## What this repo is

A project for the GiD **tester** (`scripts/tester.tcl`, a Tcl app run by GiD with `-tclsh`). Each test case runs a GiD batch file (`.bch`) that loads the `kratos` problemtype, builds one of its examples, meshes it, writes the Kratos input files and, for `*_calculate` cases, runs Kratos. The case then passes or fails according to Tcl checks on the files produced.

There are no unit tests: everything runs inside GiD.

## Layout

| Path | Purpose |
|---|---|
| `xmls/tester_cases.xml` | Case catalogue: one `<case>` per test (id, batch, name, tags, checks). |
| `batchs/<App>/*.bch` | GiD batch files, one per case. |
| `scripts/runAllCases.js` | Entry point (`npm start`): launches GiD + tester, parses `tester.log`, exit code 1 if any case failed. |
| `scripts/tester.tcl`, `scripts/xunit_log.tcl` | GiD tester and its xunit reporter. Third-party (GiD team) — do not modify. |
| `scripts/run_tests.sh` | Alternative Linux runner (writes `/test-reports/logs.xml`). |
| `scripts/dockerlauncher.bat` | Replaces `kratos.gid/exec/pip_gids_python.unix.bat` inside Docker. |
| `scripts/install-kratos.sh` | Docker: clones GiDInterface `master` into `/gid/problemtypes/kratos.gid`. |
| `project/kratos x64.tester/config/` | Tester preferences: `preferences.xml` (local, Windows paths), `preferences_docker.xml` (copied over it in Docker). |
| `project/kratos x64.tester/logfiles/` | Runtime logs (`tester.log`), wiped on every run. |
| `output/` | xunit results (ignored). |
| `Dockerfile`, `deploy.bat` | Image `fjgarate/kratos-tester` used by the GiDInterface CI. |

## Anatomy of a case

A batch file (`batchs/Fluid/fluid_2d_cylinderinflow_calculate.bch`):

```
*****tcl file delete -force "[tester::get_tmp_folder]/<name>.gid"
MEscape Data Defaults ProblemType kratos escape
*****tcl Kratos::Quicktest <App> <2D|3D> ::<App>::examples::<Example>::Init
*****tcl MeshGenerationOKDo DefaultSize
MEscape Files SaveAs "[tester::get_tmp_folder]/<name>" escape
MEscape Utilities Calculate escape escape escape      ;# only *_calculate
Mescape Files Save
*****tcl after 10000 {PWKillProc current yes}         ;# only *_calculate
*****tcl WaitUntilAllProcessTerminate                 ;# only *_calculate
```

Its entry in `xmls/tester_cases.xml`:

```xml
<case id="<32 hex chars, unique>" branch_require="developer">
  <batch>batchs/<App>/<name>.bch</batch>
  <help>...</help>
  <name><name></name>
  <owner>...</owner>
  <tags><App> <2D|3D> Production</tags>
  <check>
    <check-1>[file size "[tester::get_tmp_folder]/<name>.gid/<name>.mdpa"]&gt;N</check-1>
    <!-- *_calculate also: .err size < 1 and .post.lst size > 0 -->
  </check>
</case>
```

Conventions:
- Case name = batch file name = model name: `<app>_<2d|3d>_<example>_<write|calculate>`.
- `*_write` only writes the input files; `*_calculate` also runs Kratos.
- `Kratos::Quicktest` (defined in GiDInterface `kratos.gid`) is the bridge into the problemtype: it activates the app and dimension and calls the example's `Init`. Renaming an example proc in GiDInterface breaks its case here.
- The `id` must be a unique, non-empty 32-character hex string. `runAllCases.js` looks cases up by id and crashes if one is missing.
- Escape `<`/`>` in checks as `&lt;`/`&gt;`.
- Checks are only file-size thresholds today. Prefer adding a check on content (e.g. a `grep` of the `.mdpa` or `ProjectParameters.json`) when a fix needs to be pinned down.

### Adding a case
1. Copy a `.bch` of the same kind (`_write` or `_calculate`) and adapt app, dimension, example proc and names.
2. Add the `<case>` to `xmls/tester_cases.xml` with a new unique id and the app tag.
3. If it introduces a new app tag, add it to `filter_tags_value` in both `project/kratos x64.tester/config/preferences*.xml`.
4. Run it locally (see README) before committing.

## Coverage (as of 2026-11)

Covered apps: Fluid, EmbeddedFluid, FSI, ConvectionDiffusion, Buoyancy, ConjugateHeatTransfer, Structural, Dam, MPM, PotentialFluid, DEM, CDEM, SwimmingDEM/FluidDEM, PfemFluid.

Not covered: GeoMechanics, DEMPFEM, PfemThermic, PfemMelting, FreeSurface, CompressibleFluid, ShallowWater, StenosisWizard, Stent, MdpaGenerator.

Only the default launch mode (GiD's own python) is exercised. In Docker, `pip_gids_python.unix.bat` is replaced by `scripts/dockerlauncher.bat`, so the problemtype's own Linux launch scripts are never run.

Batch files present but not registered in `tester_cases.xml`: `FSI/fsi_3d_mok_{write,calculate}.bch`, `PfemFluid/pfemfluid_2d_{dambreakfsi,waterdambreak}_write.bch`.

## Versioning

The Kratos version must match the one in GiDInterface (`kratos.gid/kratos.xml`). Here it appears in:
- `Dockerfile` — `pip install KratosMultiphysics[all]==<version>`
- `deploy.bat` — `set version=` (image and git tag)

## Rules

- Do not edit `scripts/tester.tcl` or `scripts/xunit_log.tcl` (vendored from GiD).
- Do not commit machine-specific changes to `project/kratos x64.tester/config/preferences.xml`, `last_results.txt`, `digest_results.txt`, `tree_open.txt` or `logfiles/`.
- `*.sh` and `scripts/dockerlauncher.bat` run in Linux and must keep **LF** line endings.
- `deploy.bat` force-pushes tags and pushes Docker images: do not run it unless asked.
- Without GiD you can only review batch/XML syntax. Say so when reporting instead of claiming a case passes.
