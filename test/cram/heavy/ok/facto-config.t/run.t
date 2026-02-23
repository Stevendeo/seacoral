  $ seacoral --entrypoint sum --tools klee
  [A]{Sc} Getting main configuration
  [A]{Sc} Starting to log into `_sc/test.c-WM-@1/logs/1.log'
  [A]{Sc} Initializing working environment...
  [A]{Sc} Doing the hard work...
  [A]{Sc} Launching klee on `sum'
  [A]{Sc} Extracting new testcases from corpus...
  [A]{Sc} Hard work done
  [A]{Sc} Coverage statistics for `sum':
          cov: 11 (73.3%) uncov: 0 (0.0%) unkwn: 4 (26.7%) with 3 tests
  [A]{Sc} Covered labels: {1, 2, 3, 5, 6, 7, 10, 11, 12, 13, 15}
  [A]{Sc} Uncoverable labels: {}
  [A]{Sc} Crash statistics: rte: none
  [A]{Sc}        1: Covered
                 2: Covered
                 3: Covered
                 4: Unknown
                 5: Covered
                 6: Covered
                 7: Covered
                 8: Unknown
                 9: Unknown
                10: Covered
                11: Covered
                12: Covered
                13: Covered
                14: Unknown
                15: Covered
          Coverage: (11/15) 73.3%

  $ seacoral --entrypoint mult --tools klee
  [A]{Sc} Getting main configuration
  [A]{Sc} Starting to log into `_sc/test.c-WM-@2/logs/1.log'
  [A]{Sc} Initializing working environment...
  [A]{Sc} Doing the hard work...
  [A]{Sc} Launching klee on `mult'
  [A]{Sc} Extracting new testcases from corpus...
  [A]{Sc} Hard work done
  [A]{Sc} Coverage statistics for `mult':
          cov: 11 (73.3%) uncov: 0 (0.0%) unkwn: 4 (26.7%) with 3 tests
  [A]{Sc} Covered labels: {1, 2, 3, 6, 7, 8, 10, 11, 12, 13, 15}
  [A]{Sc} Uncoverable labels: {}
  [A]{Sc} Crash statistics: rte: none
  [A]{Sc}        1: Covered
                 2: Covered
                 3: Covered
                 4: Unknown
                 5: Unknown
                 6: Covered
                 7: Covered
                 8: Covered
                 9: Unknown
                10: Covered
                11: Covered
                12: Covered
                13: Covered
                14: Unknown
                15: Covered
          Coverage: (11/15) 73.3%
