Tools
=====

We describe here the different tools used by SeaCoral, and how it intergates them as
part of its generation process.  When a tool operates on the inputs that have
been prepared by SeaCoral, it uses external files that can be found in `sc_drivers`
at the root of the project.

SeaCoral works in three successive phases: preprocessing, test generation, and post
processing.

Preprocessing
-------------

LAnnotate
~~~~~~~~~

SeaCoral involves a tool for preprocessing files: `frama-c-lannotate`.  This is a
`frama-c <https://frama-c.com/>`_ plug-in that belongs to the `LTest
<https://git.frama-c.com/pub/ltest>`_ suite.

Its purpose is to add `labels` to the analyzed functions (check :ref:`the
Usage section<Usage>` for an example).  Several annotation modes are available;
use `frama-c -lannot-list` to list them.

Test runner
~~~~~~~~~~~

You can give SeaCoral your own set of tests with the test runner extension,
configurable with the `[test_runner] custom_tests = [file1.c,...]` in the toml
:ref:`configuration<Configuration>` table. If custom tests are provided, the
test runner will compile the project (annotated by lannotate), execute each
input and check which labels are covered.


Generating tests
----------------

There are four main tools for generating test cases or proving
unreachability of `pclabels`: `klee`, `libfuzzer`, `cbmc` and
`luncov`.

Klee
~~~~

`Klee <https://klee.github.io/>`_ is a dynamic symbolic execution engine built
on top of the LLVM compiler infrastructure.

Two external files are associated with `klee`: `klee.h` and `klee_driver.h`.

.. We should remove this file from the project and add the proper include
   directory.

- `klee.h` gathers the definitions of `klee` primitives used by the project.
  It comes from the main `klee` repository.

- `klee_driver.h` gathers the definitions for `pc_label` as well as memory
  initialization macros.

Klee operates on a harness that SeaCoral generates based on the input source code.
The purpose of the harness is to properly initialize each function arguments and
uninitialized global using `klee_make_symbolic` (with proper treatment of
pointers), and then call the studied function (aka. "entrypoint").  The
reachability of a `pclabel` at location :math:`l` and with condition expression
:math:`e` is encoded as follows: if :math:`l` is reached and :math:`e` holds,
then `klee_assert(0)` is called.  This forces klee to raise an error stating
that the assertion has been violated, and to return the test corresponding to
the failed assertion.  SeaCoral retreives the test that covers the `pclabel`, and
registers it as a new test; at the same time, SeaCoral also replays the test using a
process that does not fail when the assertion is reached: this allows SeaCoral to
check whether further labels are covered by the newly registered test.

NB: `klee` only generates new tests: it cannot prove the unreachability of
a `pclabel`.

Libfuzzer
~~~~~~~~~

`libfuzzer <https://www.llvm.org/docs/LibFuzzer.html>`_ is a fuzzing utility
that ships with any recent version of `clang <https://clang.llvm.org/>`_.  A
fuzzer searches the space of all test inputs for "interesting" items.  In
general, the search is performed via selection, random mutations, and crossovers
of given or generated inputs.  An input :math:`x` is deemed "interesting", and
thus kept and more susceptible to be selected for mutations, when the execution
of the tested function on :math:`x` increases a specific coverage criterion.
The latter is typically measured by means of an instrumentation of the tested
code, and does not directly correspond the kind of criteria considered in SeaCoral.

NB: `libfuzzer` only generates new tests: it cannot prove the unreachability of
a `pclabel`.

Test Harness & Structured Data
..............................

In SeaCoral, `libfuzzer` operates by linking an automatically generated test harness
with an instrumented version of the tested code.  Each input given and generated
by the fuzzer solely consists of an array of bytes, that must then be fed to a
deterministic decoder to produce the structured data that the tested function
expects for each one of its arguments (and global variables).  The decoding
algorithm employed allows SeaCoral to interpret generated tests and reuse them as
seeds for any other tool that may be able to exploit them, such as `klee`.

Note that, whereas every possible input data-structure (currently subject to the
assumption that there is no sharing of pointers, i.e. there can be no aliasing
between pointer arguments, and they may only point to tree-like data-structures)
can be encoded into an array of bytes, some byte vectors may lead to
inconsistent data-structures and thus need to be filtered out.  SeaCoral's use of
`libfuzzer` integrates dedicated filtering phases for this purpose.

Corpus Initialization
.....................

Fuzzers require an initial corpus of *test inputs* to operate properly.  In SeaCoral,
these first inputs can either be randomly generated, or come from tests already
generated in the project.  The size of this initial input corpus is determined
by the `libfuzzer.init_corpus_size` configuration entry, and defaults to 1.
When an insufficient amount of existing tests exists when libfuzzer starts, this
corpus is completed by using a vector of null bytes (if the configuration entry
`libfuzzer.init_corpus_with_nulls` holds), and then a set of vectors of bytes
chosen uniformly at random.

Fuzzing Process
...............

The initial corpus is first filtered to deal with sets of inputs that induce
similar coverage, and eliminate inputs that correspond to inconsistent
data-structures or do not satisfy pre-conditions.
Then the search for new inputs happens via the fuzzing loop, for some given
total time (`libfuzzer.timeout`) and/or number of iterations (`libfuzzer.runs`).

Focus on Labels
...............

Eventually, a second filtering phase is used to filter out uneeded inputs.  At
this stage, an optional tweak is available, that forces `libfuzzer` to only
consider the coverage of `pclabels` when deciding whether to keep an input in
the corpus.  Indeed, as mentioned above, coverage criteria that are directly
measured by fuzzers do not directly corresond to coverage of `pclabels`.  One
consequence of this mismatch is that `libfuzzer` may generate more test inputs
than necessary to satisfy SeaCoral's `pclabel`-based coverage criterion.  To counter
this effect, SeaCoral offers the Boolean option `labels_only`, that makes this last
filtering phase keep only those inputs that cover at least one `pclabels` that
is not already covered by another known or generated input.

CBMC
~~~~

`CBMC <http://cprover.diffblue.com/>`_ stands for "C Bounded Model Checking".
This is a static analysis tool for analyzing C programs.

There are three different execution modes for `cbmc`. They all generate similar
harnesses for initializing variables through the
`goto-cc <http://cprover.diffblue.com/group__goto-cc.html>`_ and
`goto-harness <http://cprover.diffblue.com/md__home_travis_build_diffblue_cbmc_doc_architectural_goto-harness.html>`_ tools.
The three modes only differ in how the `pclabel` s are defined and how `cbmc` is
called.

- CBMC cover (cbmc)

  This options works with the `cover` mode of `cbmc`.
  It uses the external file `cbmc_cover_driver.h`.
  Each `pc_label` is defined as `__CPROVER_cover(expr)` and `CBMC` called with the `--cover` option.
  `cbmc` then attempts to cover as many `pclabel` s as possible and returns a list of test cases.

  NB: this mode only generates new tests: it cannot prove the unreachability of
  a `pclabel`.

- CBMC with assertions (cbmc-assert)

  This options works with the classic execution mode of `cbmc`.
  It uses the external file `cbmc_assert_driver.h`.
  Each `pc_label(p)` is defined as an assertion of the negation of `p` (`__CPROVER_assert (!p)`).

  - If there exist a counter example to this assertion, it means that `p` is reachable.
  - If the assertion `!p` is proven by `cbmc`, then `p` never is true: the `pclabel` is unreachable.

- CBMC with C labels (cbmc-clabel)

  This has the same behaviour than `cbmc-assert` except it replaces `assertions` by
  conditions leading to C labels; `cbmc` is then called to check if the C labels are
  reachable or not.

LUncov
~~~~~~

Preamble: the current version of the LUncov plug-in does not allow it to handle
tasks involving complex pointer manipulation.

Part of the `LTest <https://git.frama-c.com/pub/ltest>`_ suite, `luncov` is a `frama-c` plug-in
that perform static analyzes on a project and try to deduce uncoverability of `pclabel` s.
The analyzes are done by `EVA`, an abstract intepreter, and `WP`, a weakest precondition
calculator.
SeaCoral does not perform preprocessing for `luncov`, as `lannot` already prepares the project
for it to work as is.

NB: `luncov` does not generate new tests: it can only prove the unreachability of
`pclabel` s.

Postprocessing
--------------

Once tests are generated, SeaCoral provides two coverage report utilities: `lreplay` and
`e-acsl`.

LReplay
~~~~~~~

Part of the `LTest <https://git.frama-c.com/pub/ltest>`_ suite, `lreplay` is a
standalone executable that will compile and execute a set of tests, and register
which labels are reached in practice.

E-ACSL
~~~~~~

`E-ACSL <https://frama-c.com/fc-plugins/e-acsl.html>`_ is a `frama-c` plug-in
that translates an annotated C program into another program that detects the
violated annotations at runtime. The annotations language used by `e-acsl` is
`ACSL <https://frama-c.com/html/acsl.html>`_.

SeaCoral can use `e-acsl` to verify that `ACSL` annotations associated to a function
are satisfied by the testcases generated during the previous phase.
