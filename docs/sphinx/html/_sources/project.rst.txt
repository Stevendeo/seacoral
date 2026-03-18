.. _project:

Project management
==================

The set of analyzed files is called in Seacoral a **project**. Each time you
invoke seacoral with a given configuration, it will either create a new project
or use an existing one, and start a new **run**.

More prcisely, the configuration options either are *project-wide* or *runtime*.
Running seacoral on configuration that only differ in their *runtime* options
will not create a new project: it will re-use the previously generated results
for the new run. If only one project-wide option is changed, then seacoral will
create another project and restart from scratch.

Your projects
-------------

Each invocation of seacoral will generate several directories in the output
path (by default, the directory is `_sc` and it is created where you launch
seacoral). Let's take the following commands as an example:

  .. code-block::

    $ seacoral
        --config test/cram/heavy/common-files/get_sign/seacoral.toml
	--tools cbmc
    ...
    $ ls _sc/
    7888bd774fd614036e1314ed8ef490b8  get_sign.c-CC-TIMESTAMP            last
    get_sign.c-CC-@1                  get_sign.c-CC-last                 shared
    

These directories

1. `7888bd774fd614036e1314ed8ef490b8/`
   
   This directory name corresponds to the project hash, i.e. the hash of the
   project-wide configuration options used (including the C source code of the project).

2. `get_sign.c-CC-@1`
   
   The directory of the first invocation of seacoral on a set of files and a
   criterion. If you restart seacoral with the same file and coverage
   criterion, it will generate a `get_sign.c-CC-@2` directory.

3. `get_sign.c-CC-TIMESTAMP`
   
   An alias of the previous directory, but with a timestamp.

4. `get_sign.c-CC-last`
   
   A alias of the first directory, corresponds to the latest run of seacoral
   on a given project.

5. `last`
   
   An alias to the latest seacoral run.

6. `shared/`
   
   A special directory containing the stubs and drivers required for every project.


Project layout
--------------

Let's now see what is generated for a given project:

  .. code-block::

    $ ls _sc/last
    cbmc    corpus       decoder  labeling  lreplay  store  validator
    config  covinfo.csv  headers  logs      stats    tests


1. `cbmc/`

   The working directory of the CBMC tool. If we had called another tool, it
   would have created a dedicated 

2. `config/`

   For each run, this directory will contain three different files:
   * `'n'-given.toml`: the toml given for the `n` th run;
   * `'n'-cmdline.txt`: the command line of the `n` th run;
   * `'n'-actual.toml`: the configuration of the `n` th run, merging the given
   configuration file and the command line (note: the command line arguments
   override the configuration file options).

2. `corpus/`
   
   The directory where the seacoral internal representation of the generated
   tests are stored.

3. `covinfo.csv`

   A csv with information about each run (run id, time,
   covered/uncoverable/unknown labels, num of tests generated)

4. `decoder/`

   This directory contains the C file (and the associated `.so`) that decodes
   the internal representation of tests from `corpus/` into actual inputs of the
   tested function.

5. `headers/`

   Internal C files required for proper compilation of several modules of
   seacoral (lreplay & validator). 

6. `labeling/`
   
   The input files are labelized by `frama-c-lannotate` tool before being sent
   to the orchestrated tools. This directory contains the labelized file as
   well as several internal files used by the `ltest` tools.

7. `logs/`
   
   The directory in which the whole log of seacoral is stored.

8. `lreplay/`

   The working directory of the lreplay tool.

9. `stats/`

   For each run, a `'n'.json` file in generated with several statistics (tools,
   execution time, number of generated tests, ...)

10. `store/`
   
   Contains the project runtime store and stubs that allows dynamic tools to share
   their results efficiently. This is only used by seacoral internally.

11. `tests/`

    The C files of the generated tests are stored in this directory. They are
    separated into two categories: tests that do not raise an RTE (saved in
    `tests/cov/`), tests raising RTEs (saved in `tests/rte/`) and tests which make
    the oracle fail (saved in `tests/oracle/`).

12. `validator/`

    Contains the project validator stubs and shared objects. This is only used
    by seacoral internally. 
