# Changelog

This file documents all notable changes to the GCHP wrapper repository starting in version 14.0.0. See also CHANGELOG files for individual submodules, such as:
- `src/GCHP_GridComp/GEOSChem_GridComp/geos-chem/CHANGELOG.md`
- `src/GCHP_GridComp/GEOSChem_GridComp/HEMCO/CHANGELOG.md`
- `src/GCHP_GridComp/GEOSChem_GridComp/Cloud-J/CHANGELOG.md`
- `src/GCHP_GridComp/GEOSChem_GridComp/HETP/CHANGELOG.md`
- `src/MAPL/CHANGELOG.md`

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased] - TBD
### Added

### Fixed
- Check if mass flux is top-down and flip accordingly

### Changed

### Removed

## [14.5.0] - 2024-11-08
### Added
- Added documentation about GEOS convection change affecting meteorology starting June 1, 2020

### Changed
- Updated GEOS-Chem to 14.5.0
- Updated HEMCO to 3.10.0
- Updated Cloud-J to 8.0.1

### Fixed
- Fixed formatting error in `.github/workflows/stale.yml` that caused the Mark Stale Issues action not to run
- Updated compiler requirements to specify max GNU version is 12
- Updated documentation for version 14.5.0
- Updated `docs/requirements.txt` to use `jinja2==3.1.4` (fixes a security issue)

## [14.4.3] - 2024-08-13
### Changed
- Updated GEOS-Chem (science codebase) to 14.4.3
- Updated HEMCO to 3.9.3
- Updated Cloud-J to 7.7.3

### Fixed
- Added brackets around `exempt-issue-labels` list in `.github/workflows/stale.yml`

## [14.4.2] - 2024-07-24
### Changed
- Updated Cloud-J submodule to 7.7.2
- Disable support for FAST-JX for all simulations except Hg

## [14.4.1] - 2024-06-28
### Fixed
- Fixed formatting error in `.github/workflows/stale.yml` that caused the Mark Stale Issues action not to run

## [14.4.0] - 2024-05-30
### Added
- RTD docs now includes Supplemental Guide "Archiving Output with the History diagnostics"
- GitHub Action config file `.github/workflows/stale.yml`, which replaces StaleBot
- Added git submodule HETP for aerosol thermodynamics in GEOS-Chem

### Changed
- Updated Python package versions for ReadTheDocs in `docs/requirements.txt`
- Now request Python 3.12 for ReadTheDocs builds in `.readthedocs.yaml`
- Updated GEOS-Chem submodule to 14.4.0
- Updated HEMCO submodule to 3.9.0
- Changed subdirectory name HEMCO_GridComp to HEMCO since not its own gridded component
- Moved HEMCO and Cloud-J submodules from GCHP_GridComp to GCHP_GridComp/GEOSChem_GridComp where they are used
- Converted Github issue templates to issue forms using YAML definition files

### Removed
- GitHub config files `.github/stale.yml` and `.github/no-response.yml`

## [14.3.1] - 2024-04-02
### Added
- Now print container name being read by ExtData when `CAP.EXTDATA` is set to `DEBUG` in `logging.yml`
- Added new pre-processer setting GCHP_WRAPPER for use in submodules
- Added PLEadv export to FV3 submodule for inclusion in GCHP HISTORY.rc files
- Added git submodule for HETP aerosol thermodynamics

### Changed
- Updated GEOS-Chem submodule to 14.3.1
- Updated HEMCO submodule to 3.8.1
- Now use short names for submodules (i.e. without the path) in `.gitmodules`

### Fixed
- Fixed bug where SPHU used to construct PLE for advection was vertically inverted if using raw GMAO meteorology files
- Fixed bug in UpwardsMassFlux diagnostic that was causing all values to be zero

## [14.3.0] - 2024-02-07
### Added
- Added capability for TOMAS simulations in GCHP
- Added Cloud-J as submodule within GCHP_GridComp directory
- Added compile option FASTJX to use legacy Fast-JX to compute J-values in GEOS-Chem instead of Cloud-J (required for mercury simulation)

### Changed
- Updated GEOS-Chem submodule to 14.3.0
- Updated HEMCO submodule to 3.8.0

### Fixed
- Avoid semicolon in `CMAKE_ Fortran_FLAGS` variable when additional flags are passed to `cmake`
- Updated debugging guide with clearer examples

## [14.2.3] - 2023-12-01
### Added
- Script `.release/changeVersionNumbers.sh` to change version numbers before a new GCHP release

## [14.2.2] - 2023-10-23
### Changed
- Updated GEOS-Chem submodule to 14.2.2

## [14.2.1] - 2023-10-10
### Changed
- `test` now points to `src/GCHP_GridComp/GEOSChem_GridComp/geos-chem/test`
- Hard-coded ESMF logging option removed from GCHPctm.F90
- Updated version numbers and documentation

## [14.2.0] - 2023-10-05
### Added
- Added run-time option to use dry air pressure in advection
- Added run-time option to correct mass flux for humidity
- Added `.readthedocs.yaml` to configure ReadTheDocs builds

### Changed
- Updated GEOS-Chem submodule to 14.2.0
- Updated HEMCO submodule to 3.7.0
- Updated version numbers in `CMakeLists.txt` and `docs/source/conf.py` to 14.2.0
- Changed default air pressure in advection from total to dry
- Updated `AUTHORS.txt` for GCHP 14.2.0
- Updated `README.md` so that links point to http://geos-chem.org
- Updated logo & badge links in `README.md`
- Updated version number to 14.2.0

### Fixed
- Fixed post-advection pressure edges (PLE1) passed to advection to be derived from the correct surface pressure
- Fixed typo in `docs/source/conf.py`, "_static" should be "_static/"

## [14.1.1] - 2023-03-03
### Added
- Added `EXE_FILE_NAME` and `INSTALLCOPY` to src/CMakeLists.txt (facilitates integration testing)

### Changed
- Changed "carboncycle" to "carbon" in `src/GCHP_GridComp/GEOSChem_GridComp/CMakeLists.txt`
- Simplified Github issue and pull request templates
- Updated ReadTheDocs to specify 8.1 is minimum version of ESMF
- Updated version numbers in `CMakeLists.txt` and `docs/source/conf.py` to 14.1.1

### Fixed
- Fixed global attributes written to stretched grid checkpoint files to enable restart
- Fixed day-of-week scale factor handling in MAPL ExtData
- Fixed stretched grid checkpoint file issue in MAPL that prevented restarting stretched grid simulations

## [14.1.0] - 2023-02-01
### Changed
- Updated GEOS-Chem submodule to 14.1.0
- Updated HEMCO submodule to 3.6.0
- Updated MAPL submodule from v2.18.3 -> v2.26.0
- Updated gFTL-shared submodule from v1.4.1 -> v1.5.0
- Updated yaFyaml submodule from v1.0-beta.4 -> v1.0.4
- Updated pFlogger submodule from v1.6.1 -> v1.9.1
- Updated ReadTheDocs documentation for 14.1.0

### Fixed
- Fixed logic in .github/workflows/findRefKey.sh for determining previous commit

## [14.0.2] - 2022-11-29
### Changed
- Updated GEOS-Chem submodule to 14.0.2
- Updated HEMCO submodule to 3.5.2
- Updated the documentation for clarity

### Fixed
- Removed memory leaks in GEOS-Chem and HEMCO submodule code
- Units for State_Diag%RxnRate diagnostic are now `molec cm-3 s-1` instead of `s-1`

## [14.0.1] - 2022-10-31
### Changed
- Updated GEOS-Chem submodule to 14.0.1

## [14.0.0] - 2022-10-25
### Added
- Created CHANGELOG.md

### Changed
- Changed GEOS-Chem submodule to 14.0.0 release
- Changed HEMCO submodule version: 3.4.0 -> 3.5.0
- Changed GEOS-ESM submodule versions:
  * MAPL: v2.6.3 -> v2.18.3
  * FVdycoreCubed_GridComp: v1.2.12 -> v1.8.0
  * fvdycore: geos/v1.1.6 -> geos/v1.4.0
  * GMAO_Shared: v1.3.8 -> v1.5.3
  * FMS: geos/2019.01.02+noaff.6 -> geos/2019.01.02+noaff.8
  * ESMA_cmake: v3.0.6 -> v3.8.0
- Changed Goddard-Fortran-Ecosystem submodule versions:
  * gFTL-shared: v1.2.0 -> v1.4.1
  * gFTL: v1.3.1 -> v1.6.0
  * pFlogger: v1.5.0 -> v1.6.1
  * yaFyaml: v0.5.0 -> v1.0-beta.4
- Updated build files for compatibility with new submodule versions
- Updated CONTRIBUTING.md and SUPPORT.md to retire guidelines on GEOS-Chem wiki
- Updated GCHP ReadTheDocs documentation
- Updated spack deployment action to use new installation procedure
- Update AWS benchmarking github actions to act on all dev* branches

### Removed
- Removed Azure continuous integration test pipeline
- Removed pFUnit submodule since not used

### Fixed
- Fixed broken CMAKE_BUILD_TYPE options for intel and gfortran compilers
