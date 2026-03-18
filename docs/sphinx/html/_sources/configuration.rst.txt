.. _configuration:

Seacoral's configuration
========================

Configuration file
------------------

SeaCoral can be configured differently via a `toml` file with the option `-C`.

Options can be `project-defining` or `runtime`, depending on how they influence
the analysis. If a `project-defining` option is changed between two analyses,
a new separate project will be created and the old results will not be used.
If a `runtime` option is changed beween two analyses, it will re-use the
previous project.

Note that you can generate a new configuration file with `$ seacoral init`.
It will create a `seacoral.toml` that you can use to start the analysis.

.. The following documentation can be generated with "$ seacoral gen-rst-doc".

Logs configuration options [logs]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- `console-level` [runtime knob]: Console log level: use 0 for no message, 1 for application-level messages
  only, 2 to include error messages, 3 to include warnings as well, 4 for more
  information, and 5 or any other value for full debug messages (default: 3).
  
 
Run configuration options [run]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- `workdir` [runtime knob]: Directory where the working files are stored (defaults to "_sc").
  
- `display-outcomes` [runtime knob]: When set to "yes", displays for each test which labels it covers ("yes" by
  default).
  
- `max-validation-concurrency` [runtime knob]: Maximum number of concurrent validations (defaults to 16). A null value
  enables unlimitted parallelism.
  
- `verbose-validation` [runtime knob]: When set, show labels reached during test validation in logs (false by
  default).
  
- `force-preprocess` [runtime knob]: Force preprocessing, even if it has already been performed.
  
- `enable-syntax-check` [runtime knob]: Whether to check for syntax errors in input files prior to labeling and test
  generation (true by default).
  
- `strategy` [runtime knob]: Employ the given orchestration strategy: 's' stands for sequential, 'p' for
  parallel, and 'o' for optimized.  The default is "p".
  
- `test-timeout` [runtime knob]: Time (in seconds) after which a test execution is considered to fail (1.000
  by default).
  
- `tools` [runtime knob]: Tools to use. Defaults to []. Use ["*"] to select every known tool.
  
 
Project configuration options [project]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- `ignored-globals` [project-defining knob]: Global variables that should be ignored.
  
- `external-libs` [runtime knob]: External libraries required to compile the project, like "m" for the math
  library, for instance. Defaults to [].
  
- `name` [project-defining knob]: Name for the project: this is used in logs and to name the working directory.
  
- `files` [project-defining knob]: C files to consider.
  
- `criterion` [project-defining knob]: Coverage criterion (case-insensitive). Launch `frama-c -lannot-list` for a list of available criteria (default: "CC"). If you used custom labels, you can use the "Custom" or "Empty" criterion.
  
- `entrypoint` [project-defining knob]: Entrypoint for the project.

- `functions-to-cover` [project-defining knob]: Comma-separated list of functions to cover. Use an empty string to automatically cover the entrypoint and any function it may call (this is the default); note this is achieved using an analysis of the syntactic callgraph, so function pointers are ignored. Use '*' to select every function defined in the project.
  
- `include-dirs` [project-defining knob]: Directories where header files are searched for (default: []).
  
 
Pointer-handling configuration options [pointer-handling]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- `max-ptr-array-length` [project-defining knob]: Maximal size of C arrays that are induced by naked pointers. Default is 1.
  
- `max-cstring-length` [project-defining knob]: Maximal size of C strings, excluding any additional terminating '\000'.
  Default is 20.
  
- `max-non-nil-ptr-depth` [project-defining knob]: Maximal depth at which pointers may be non-NULL, measured in number of
  pointer dereferences from function arguments. Default is 3.
  
- `treat-pointer-as-string` [project-defining knob]: Formal arguments or global variables that are declared as naked pointers to
  characters (`char *p`), but need to be treated as '\000'-terminated C-strings
  (default: []).
  
- `array-size-mapping` [project-defining knob]: Pairs of variables of the form `"p:n"`, where `p` is a pointer (formal
  argument to the entrypoint, or global variable), and `n` is a variable of
  integral type that represents the length of the array pointed to by `p` (in
  number of elements of type `t`, if `p` is of type `t*`).
  
- `treat-pointer-as-array` [project-defining knob]: Formal arguments or global variables that are declared as naked pointers
  (like `int *p` or `struct t * x`), but need to be treated as arrays (default:
  []).
  
 
Build-tools configuration options [build-tools]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- `clangxx-path` [runtime knob]: Path to the clang++ executable (defaults to "clang++")
  
- `c-pre-processor-flags` [project-defining knob]: Default pre-processor flags
  
- `clang-path` [runtime knob]: Path to the clang executable (defaults to "clang")
  
- `objcopy-path` [runtime knob]: Path to the objcopy executable (defaults to "objcopy")
  
- `c-linker-flags` [project-defining knob]: Default linker flags
  
- `ld-path` [runtime knob]: Path to the ld executable (defaults to "ld")
  
 
Cbmc configuration options [cbmc]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- `timeout` [runtime knob]: Sets the timeout of the tool (default: 0.000). If set to 0, no timeout is
  imposed on the CBMC process.
  
- `mode` [runtime knob]: Sets CBMC's mode. It can either be "cover" (standard coverage analysis),
  "assert" (uncoverability detection with assertions) or "clabel"
  (uncoverability detection with C labels). (default: "cover").
  
- `unwind` [runtime knob]: Sets the loop unwinding (default: 10). If set to 0, there will not be
  unwinding.
  
 
Eacsl configuration options [eacsl]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- `path` [runtime knob]: Path to the e-acsl-gcc.sh executable
  
- `enable` [project-defining knob]: Enables post-processing with E-ACSL (default: false)
  
- `mode` [project-defining knob]: E-ACSL post-processing mode. Available modes are: parallel (activated with
  "p"), and sequential (activated with "s"). The parallel mode will switch to
  sequential if it fails too many times.  Defaults to "sequential".
  
 
Export configuration options [export]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- `malloc-heapside-memory` [runtime knob]: Use `malloc` to allocate heap-side memory in generated C code. When false,
  heap-side memory is allocated statically. Defaults to true. Forced to true in
  combined testsuites
  
- `split-suite` [project-defining knob]: Whether to put individual tests in separate C files, or to combine them.
  Defaults to false
  
 
Fixtures configuration options [fixtures]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- `seek-oracle-failures` [project-defining knob]: Whether to instruct analysis tools to aim at generating tests that violate
  the oracle, in addition to a testsuite that targets coverage.
  
- `init` [project-defining knob]: Initialization function for the entrypoint.  If given, this setting must be
  the name of a function defined in either the project codebase or within a
  file listed in `files`.  This function must not accept any argument.
  
- `oracle` [project-defining knob]: Oracle function for the entrypoint.  Constraints of `init` also apply, with
  the requirements that the given function: (i) must accept an additional last
  argument that is given the entrypoint's return value (if non-void); and (ii)
  return a zero value of an integral type (like `int`) if and only if the
  oracle fails.
  
- `files` [project-defining knob]: C files where to find additional test fixtures like initialization and oracle
  functions.
  
 
Klee configuration options [klee]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- `only-new-tests` [runtime knob]: Activate option '--only-output-states-covering-new' (default: true)
  
- `timeout` [runtime knob]: Sets the timeout of the tool, in seconds; 0 means no timeout (default:
  30.000)
  
- `libc` [runtime knob]: Choose libc version (default: "none")
  
- `search` [runtime knob]: Specify klee search strategy (see `klee --help` for details, use an empty
  listfor klee defaults --- default: [])
  
- `replay-max-concurrency` [runtime knob]: Maximum number of replayers running concurrently. A null value enables full
  parallelism (this is the default), and a negative value disables on-the-fly
  replay of test cases
  
- `replay` [runtime knob]: On-the-fly replay of generated test cases (default: "yes"; possible values:
  {inhibit, yes, delayed, force})
  
- `label-handling` [project-defining knob]: Label handling mode (default: "optimize"; possible values: {ignore, naive,
  optimize, optimize+avoid, optimize+keepall})
  
- `keep-error-cases` [runtime knob]: Keep tests that are generated because they raise errors (default: true)
  
 
Lcov configuration options [lcov]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- `output-directory` [runtime knob]: Path to a directory where to output the report; if "", the report is generated in a directory 'lcov/report' that is situated within the project working directory (defaults to "")
  
- `report-in-logs` [runtime knob]: Include a textual representation of the coverage report in logs
                (default is false)
  
- `include-testsuite` [runtime knob]: Include coverage of generated testsuite files in lcov report (default is
  false)
  
- `llvm-cov-path` [runtime knob]: Path to the llvm-cov executable (defaults to "llvm-cov")
  
- `enable` [runtime knob]: Enable report generation via lcov (false by default). NOTE: custom
  user-provided tests are not taken into account when computing coverage for
  LCOV
  
- `executable-path` [runtime knob]: Path to the lcov executable (defaults to "lcov")
  
- `genhtml-path` [runtime knob]: Path to the genhtml executable (defaults to "genhtml")
  
- `llvm-profdata-path` [runtime knob]: Path to the llvm-profdata executable (defaults to "llvm-profdata")
  
- `text-report` [runtime knob]: Unless "", which is the default, name of a file where to export a textual
  representation of the coverage report
  
 
Libfuzzer configuration options [libfuzzer]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- `max-starvation-time` [runtime knob]: Maximum number of seconds to wait for valid inputs from the corpus in case no
  randomly generated seed is valid (in seconds, default: 60)
  
- `init-corpus-size` [runtime knob]: Size of the initial input corpus (default: 10; must be strictly positive)
  
- `use-cmp` [runtime knob]: Whether tracing of comparison instructions may be used to guide mutations
  (default: true; using this feature may increase the amount of generated test
  cases)
  
- `timeout` [runtime knob]: Total time to spend while fuzzing (in seconds, default: 30.000; 0 means run
  indefinitely)
  
- `labels-only` [project-defining knob]: Whether to restrict libfuzzers' sensitivity to labels instead of to its own
  counters (default: false; `use-counters` and `use-cmp` have no effect when
  used in combination with this option)
  
- `runs` [runtime knob]: Number of individual test runs (default: -1; a strictly negative value
  indicates an infinite number of runs)
  
- `init-corpus-with-uniform-bytes` [runtime knob]: Whether to include inputs that only consist of bytes of the given values into
  the initial corpus (default: ["\u0000", "\u0001"])
  
- `use-counters` [runtime knob]: Whether libfuzzer's coverage counters may be used as features (default:
  false; using counters may increase the amount of generated test cases)
  
- `init-corpus-with-nulls` [runtime knob]: Whether to include an input that only consists of null bytes into the initial
  corpus (default: true); equivalent to specifying '\000' in
  `init-corpus-with-uniform-bytes`
  
- `triage-timeout` [runtime knob]: Total time to spend while in each triage phase (in seconds, default: 0.000; 0
  means run indefinitely)
  
- `seed` [runtime knob]: Seed to pass to libfuzzer.  Default is 0, which instructs libfuzzer to
  generate a seed internally.
  
- `micro-timeout` [runtime knob]: Single-test timeout (in seconds, default: 1.000)
  
 
Lreplay configuration options [lreplay]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- `enable` [runtime knob]: Enable post-processing with lreplay (defaults to true)
  
 
Luncov configuration options [luncov]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- `extra-args` [runtime knob]: Adds extra arguments to frama-c as pair of "cmd_key:cmd_value" separated by a
  comma (default: [])
  
- `plugins` [runtime knob]: Sets the plugins tools used by luncov. Default is ["wp"]. "eva" (or "value")
  is also possible, but not recommended as it may report coverable labels
  uncoverable.
  
 
Report configuration options [report]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- `output-dir` [runtime knob]: Output directory (default: "report")
  
- `enable` [runtime knob]: Generates an HTML report (default: false)
  
- `format` [runtime knob]: Selects whether the report must be in a single page ("onepage") or with tabs
  ("pretty") (default: "pretty")
  
 
Test-runner configuration options [test-runner]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- `max-concurrency` [runtime knob]: Maximum number of replayers running concurrently (default: 1; 1 or less
  disables parallelism)
  
- `custom-tests` [runtime knob]: Custom tests to be added to the testsuite; they are played before any
  analysis or tests generation is started (default: [])

About pointer specification
...........................

The core configuration options `treat_pointer_as_array/cstring` require a list of pointers.
It is possible to directly specify inputs or fields of a given structure.
Examples

- `treat-pointer-as-array = ["foo"]`: input `foo` is not only a pointer, but an array with
  several elements whose size is bounded by `max-ptr-array-length`.
- `treat-pointer-as-cstring = [{struct t}.p]`: all values of type `struct t` in the input
  has a field `p` that must be a a `char*` and is a string. 

A similar syntax is used for `array-size-mapping`: this list is a list of pairs of
named locations separated by ':'.

- `array-size-mapping=[arr:N]`: the input `arr` is an array that must have size `N`.
- `array-size-mapping=[{struct s}:a:N]`: all values of type `struct s` in the input
  has a field `a` that is an array of `N`.

..
  The core configuration options `treat_pointer_as_array/cstring` require a list
  of "named locations". Named locations represent a position in the memory layout
  of the test input.
  It is possible to directly write variables (for example, `foo` in
  `treat_pointer_as_array` will specify the pointer `foo` must be treated as a reference to
  an array).

  It is also possible to specify indirect pointers. For example, for an input 
  `char **foo`, you may add `foo[_]` in `treat_pointer_as_cstring`
  to specify that pointers accessed via `*foo` or `foo[i]`, for some `i`, 
  point to C character strings.
  You may also specify a path in a structure (`foo.bar.tri...`), or even every
  structure of a given type (`{struct:t}.foo.bar.tri...`).
  Use of the `->` operator is also permitted to represent the access of a pointer
  field (`x->y` is equivalent to `x[_].y`).

  A similar syntax is used for `array_size_mapping`: this list is a list of pairs of
  named locations separated by ':'.
  For example, the string `x.y:N` states that the field `y` of `x` is an array that
  must have size `N`, where `x` and `N` either are globals or formals of the
  tested function.
  It also is possible for a structure to reference itself:
  `{struct:t}.y:.N` states that for any structure `s` of type `t` in the input,
  `s.y` is an array whose size must be equal to `s.N`.

Command line
------------

Previous options can be accessed via the command line interface with their key
(for example, `$ seacoral --force-preprocess`). Both the configuration file and
CLI arguments can be used; CLI arguments will override keys set up in the
configuration file.



Environment variables
---------------------

======================== ================================================== ==============
Variable                 Documentation                                      Default value
======================== ================================================== ==============
CLANG                    Executable name of `clang`                         `clang`
CLANGXX                  Executable name of `clang++`                       `clang++`
CPPFLAGS                 Flags to use with `cpp`                            
EACSL_GCC                Executable name of `e-acsl-gcc`                    `e-acsl-gcc.sh`
LD                       Path to the ld executable                          `ld`
LDFLAGS                  Flags to use with `clang`                          
OBJCOPY                  Path to the objcopy executable                     `objcopy`
OPAM_SWITCH_PREFIX       The prefix of your opam switch
SC_ENABLE_CONSOLE_TIMING Defines the precision of the logged times          `true`
SC_ENABLE_DETAILED_STATS Displays the results of lreplay and eacsl          `true`
SC_TIDY_COMMANDS         Prints processes logs better                       `false`
======================== ================================================== ==============
