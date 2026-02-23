(**************************************************************************)
(*                                                                        *)
(*  Copyright (c) 2025 OCamlPro                                           *)
(*                                                                        *)
(*  All rights reserved.                                                  *)
(*  This file is distributed under the terms of the GNU Affero General    *)
(*  Public License.                                                       *)
(*                                                                        *)
(**************************************************************************)

open Sc_core.Types
open Sc_project.Types

open Lwt.Syntax
open Sc_sys.File.Syntax

module Log =
  (val (Ez_logs.from_src @@
        Logs.Src.create ~doc:"Logs of tests replayer" "Sc_replayer"))

type opt =
  {
    custom_tests: string list;
    max_concurrency: int;
  }

let toolname = "test-runner"

let config_section =
  let default =
    {
      custom_tests = [];
      max_concurrency = 1;
    }
  in
  Sc_config.Section.define toolname ~default ~entries:Sc_config.Eztoml.[
      string_list
        ~key:"custom-tests"
        ~doc:"Custom tests to be added to the testsuite; they are played before \
              any analysis or tests generation is started (default: %a)"
        ~default:[]
        ~runtime:true
        (fun c sl -> { c with custom_tests = sl })
        (fun c -> c.custom_tests);
      int
        ~key:"max-concurrency"
        ~doc:"Maximum number of replayers running concurrently (default: %a; 1 \
              or less disables parallelism)"
        ~default:default.max_concurrency
        ~runtime:true
        (fun c i -> { c with max_concurrency = i })
        (fun c -> c.max_concurrency);
    ]


let resource_installer =
  Sc_core.Resource.register_crunched "tester" (module Resources)

(* --- *)

type 'raw_test working_data =
  {
    project: 'raw_test project;
    new_tests: [`C] Sc_sys.File.t list [@warning "-unused-field"];
    replayer_main_o: [`O] Sc_sys.File.t;
    workspace: Sc_core.Types.workspace;
    resdir: Sc_sys.File.dir;
    opt: opt;
  } [@@warning "-unused-field"]                            (* for ocaml < 5.1 *)

(* The tests listed in the configuration file can be relative to the configuration
   file; this function folds on the correct files.
   TODO: adapt the TomlSpec to take paths into account. *)
let map_on_option_testfiles project custom_tests
    (f: [> `C] Sc_sys.File.t -> [> `C] Sc_sys.File.t) =
  let handle_file file =
    try
      Some (f file)
    with Sc_sys.File.MISSING { file } ->
      Log.err "Ignoring missing file: %a" Sc_sys.File.print file;
      None
  in
  let srcdir = project.config.project_srcdir_root in
  List.filter_map begin fun filename ->
    Log.debug "Considering@ `%s'" filename;
    handle_file @@
    if Filename.is_relative filename
    then Sc_sys.File.existing_in ~dir:srcdir filename
    else Sc_sys.File.existing filename
  end custom_tests

let imported_tests_dir workspace =
  Sc_sys.File.mkdir_in ~dir:workspace.workdir "imported-tests"

(** Lists the digest files already imported into the replayer directory. *)
let existing_files_digests workspace =
  Lwt.catch begin fun () ->
    let files = Sc_sys.Lwt_file.files_of_dir @@ imported_tests_dir workspace in
    Lwt_stream.fold
      (fun file acc -> Sc_sys.File.digest file :: acc)
      files
      []
  end begin function
    | Unix.Unix_error (Unix.ENOENT, _, _) -> (* Dir does not exist *) Lwt.return []
    | e -> Lwt.reraise e
  end

(** Compares the digests of the files in the test dir with the one in argument. *)
let test_already_registered dirs (original_test_file : [> `C] Sc_sys.File.t) =
  let* l = existing_files_digests dirs in
  let current_digest = Sc_sys.File.digest original_test_file in
  Lwt.return @@
  List.exists (String.equal current_digest) l

(** Adds to a test file the replayer header driver, initializing pc_label macros. *)
let write_test_with_extra_header wd
    ~(dir:Sc_sys.File.dir)
    ~(labelized_file : [> `labelized] Sc_sys.File.t)
    (testfile : [> `C] Sc_sys.File.t) =
  Log.debug "Writing new test case %s" (Sc_sys.File.name testfile);
  let file = dir / Sc_sys.File.basename testfile in
  let () =
    let> out_chan = file in
    let< in_chan = testfile in
    Format.ksprintf (output_string out_chan)
      "#include \"%s/replayer_driver.c\"\n\
       #include %S\n\n"
      (Sc_sys.File.absname wd.resdir)
      (Sc_sys.File.absname labelized_file);
    try
      while true do
        let l = input_line in_chan in
        output_string out_chan (l ^"\n")
      done
    with End_of_file -> ()
  in
  file

let intermediate_main =
  Sc_project.Preproc.main_replacement_symbol

(* For each custom test, SC will create a separate working directory. *)

type testcase_workspace = {
  dir: Sc_sys.File.dir;         (* The directory of the test case *)
  testcase: [`C] Sc_sys.File.t; (* The modified version of the testcase in dir *)
}

(** Creates a testcase workspace. *)
let init_workspace_for_testcase wd ~labelized_file (testcase: [`C] Sc_sys.File.t) =
  let dir =
    Sc_sys.File.PRETTY.mkdir_in ~dir:wd.workspace.workdir "%s-dir"
      (Filename.chop_extension @@ Sc_sys.File.basename testcase)
  in
  Lwt.return {
    dir;
    testcase = write_test_with_extra_header wd ~dir ~labelized_file testcase;
  }

(** Builds an executable program corresponding to the given custom test, and
    executes it.  Updates the shared status store unless an RTE occurs before
    the program terminates. *)
let play ~wd { dir = _; testcase } =
  (* Note: for now we keep the object and exec files. May be worth adding
     options/env-vars to tune this behavior. *)
  let store = wd.project.store in
  let* { libs; env; _ } = Sc_store.for_compiled_subprocess store in
  (* Compiling testcase without linking *)
  let* ofile =
    Sc_C.Cmd.clang_c testcase
      ~cppflags:(Sc_C.Cmd.cppflags_of_header_dirs @@
                 wd.project.config.project_problem.header_dirs)
  in
  (* Changing main name *)
  let* () = Sc_C.Cmd.redefine_sym ~old:"main" ~new_:intermediate_main ofile in
  (* Compiling executable with the redefined main function *)
  (* let* replayer_main_o = Lazy.force replayer_main_o in *)
  let* executable =
    Sc_C.Cmd.clang_ld ofile ~ldflags:libs ~o_files:[wd.replayer_main_o]
  in
  (* Executing file *)
  Sc_sys.Process.join_lwt @@
  Sc_sys.Process.exec [|Sc_sys.File.name executable|]
    ~env
    ~on_success:(fun () -> (* Covered something *) Lwt.return true)
    ~on_error:begin function
      | Unix.WEXITED 1 ->
          (* Non-0 error code: nothing new covered *)
          Lwt.return false
      | _ ->
          Log.err "Replay of test %a failed" Sc_sys.File.print testcase;
          Lwt.return false
    end

(** Writes a custom test in the main tests directory *)
(* TODO: this should just be handed over to the corpus, not written directly
   into the testsuite (as its representation may vary or depend on options and
   choices from another core/project module) *)
let copy_test_in_testcase_dir ~covdir
    ~(labelized_file : [`C | `labelized] Sc_sys.File.t) test =
  let* () = Sc_sys.Lwt_file.touch_dir covdir in
  (* TODO: lwt-ize these I/Os *)
  let< old = test in
  let> new_ = covdir / Sc_sys.File.basename test in
  Format.ksprintf (output_string new_)
    "@\n#ifdef LREPLAY\
     @\n# include %S\
     @\n# include <lreplay_driver_impl.c>\
     @\n#endif\
     @\n\
    " (Sc_sys.File.absname labelized_file);
  try
    while true do
      output_string new_ (input_line old);
      output_char new_ '\n'
    done;
    Lwt.return ()
  with End_of_file ->
    Lwt.return ()

(** Copies tests given by the user into the working directory. *)
let setup workspace ~optional:_ project =
  (* TODO: use test_already_registered to check which tests already have been
     registered. *)
  ignore test_already_registered;
  let opt =
    Sc_config.Section.get
      ~for_:(`Entrypoint (Sc_project.Manager.entrypoint_name project))
      config_section
  in
  let* resdir =
    Sc_core.Workspace.install_resources_in ~workspace resource_installer
  in
  let new_tests =
    map_on_option_testfiles project opt.custom_tests @@
    Sc_sys.File.copy_in ~dir:(imported_tests_dir workspace)
  in
  (* TODO: crunch it *)
  let* replayer_main_o =
    Sc_C.Cmd.clang_c @@
    Sc_sys.File.copy_in ~dir:workspace.workdir (resdir / "replayer_main.c")
  in
  Lwt.return { project; new_tests; replayer_main_o; workspace; resdir; opt }

let run ({ project; workspace; opt; _ } as wd) =
  let Sc_ltest.Types.{ labelized_file; _ } = project.label_data in
  let covdir = project.covdir in
  let files = Sc_sys.Lwt_file.files_of_dir (imported_tests_dir workspace) in
  let* no_files_to_test = Lwt_stream.is_empty files in
  if no_files_to_test then
      Log.LWT.warn
        "Test@ runner@ has@ no@ file@ to@ run.@ Did@ you@ forget@ to@ import@ \
         test@ files@ (using@ the@ %S@ configuration@ section)?" toolname
  else
    let max_concurrency = max 1 opt.max_concurrency in
    Lwt_stream.iter_n ~max_concurrency begin fun file ->
      let* init_test = init_workspace_for_testcase wd ~labelized_file file in
      let* has_covered_something = play ~wd init_test in
      if has_covered_something
      then Lwt.join [ copy_test_in_testcase_dir ~covdir ~labelized_file file;
                      Sc_corpus.register_one_bypassed_test wd.project.corpus ]
      else Lwt.return ()
    end files

(* No dependency for the replayer. *)
let availability_check () =
  Lwt.return true

let load () =
  Sc_lib.Tool.register_function For_simple_labels ~name:toolname
    ~config_section:(Some config_section)
    ~availability_check ~kind:`Preprocess
    ~setup:begin fun ws ~optional (P p) ->
      let* wd = setup ws ~optional p in
      Lwt.return (fun () -> run wd)
    end
