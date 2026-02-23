(**************************************************************************)
(*                                                                        *)
(*  Copyright (c) 2025 OCamlPro                                           *)
(*                                                                        *)
(*  All rights reserved.                                                  *)
(*  This file is distributed under the terms of the GNU Affero General    *)
(*  Public License.                                                       *)
(*                                                                        *)
(**************************************************************************)

(** Report generation with GCOV/LCOV *)

open Sc_sys.File.TYPES
open Sc_core.Types
open Sc_project.Types

open Lwt.Infix
open Lwt.Syntax
open Sc_sys.File.Syntax

(* --- *)

module Log = (val (Ez_logs.from_src @@ Logs.Src.create "Sc_postproc.Lcov"))

module Log_lwt_lcov = (val Ez_logs.subproc "lcov")
module Log_lwt_genhtml = (val Ez_logs.subproc "genhtml")
module Log_lwt_llvm_cov = (val Ez_logs.subproc "llvm-cov")
module Log_lwt_llvm_profdata = (val Ez_logs.subproc "llvm-profdata")

type options =
  {
    lcov_enabled: bool;
    outdir: string;
    include_testsuite: bool;
    text_report: string;
    report_in_logs: bool;
    lcov_path: string;
    llvm_cov_path: string;
    llvm_profdata_path: string;
    genhtml_path: string;
  }

let config_section =
  let default =
    {
      lcov_enabled = false;
      outdir = "";
      include_testsuite = false;
      text_report = "";
      report_in_logs = false;
      lcov_path = "lcov";
      llvm_cov_path = "llvm-cov";
      llvm_profdata_path = "llvm-profdata";
      genhtml_path = "genhtml";
    }
  in
  Sc_config.Section.define "lcov" ~default ~entries:Sc_config.Eztoml.[
      bool
        ~key:"enable"
        ~doc:"Enable report generation via lcov (%a by default). NOTE: custom \
              user-provided tests are not taken into account when computing \
              coverage for LCOV"
        ~default:default.lcov_enabled
        ~as_flag:(Positive { keys = `Alt ["enable-lcov-report"; "lcov-report"];
                             doc = `Alt "Enable lcov report" })
        ~runtime:true
        (fun c b -> { c with lcov_enabled = b })
        (fun c -> c.lcov_enabled);
      bool
        ~key:"include-testsuite"
        ~doc:"Include coverage of generated testsuite files in lcov report \
              (default is %a)"
        ~default:default.include_testsuite
        ~runtime:true
        (fun c b -> { c with include_testsuite = b })
        (fun c -> c.include_testsuite);
      string
        ~key:"output-directory"
        ~doc:"Path to a directory where to output the report; if \"\", the \
              report is generated in a directory `lcov/report' that is situated \
              within the project working directory (defaults to %a)"
        ~default:default.outdir
        ~runtime:true
        (fun c s -> { c with outdir = s })
        (fun c -> c.outdir);
      string'
        ~key:"text-report"
        ~doc:"Unless \"\", which is the default, name of a file where to export \
              a textual representation of the coverage report"
        ~default:default.text_report
        ~runtime:true
        (fun c s -> { c with text_report = s })
        (fun c -> c.text_report);
      bool
        ~key:"report-in-logs"
        ~doc:"Include a textual representation of the coverage report in logs
              (default is %a)"
        ~default:default.report_in_logs
        ~runtime:true
        (fun c b -> { c with report_in_logs = b })
        (fun c -> c.report_in_logs);
      string
        ~key:"executable-path"
        ~doc:"Path to the lcov executable (defaults to %a)"
        ~default:default.lcov_path
        ~env:"LCOV"
        ~runtime:true
        (fun c s -> { c with lcov_path = s })
        (fun c -> c.lcov_path);
      string
        ~key:"llvm-cov-path"
        ~doc:"Path to the llvm-cov executable (defaults to %a)"
        ~default:default.llvm_cov_path
        ~env:"LLVM_COV"
        ~runtime:true
        (fun c s -> { c with llvm_cov_path = s })
        (fun c -> c.llvm_cov_path);
      string
        ~key:"llvm-profdata-path"
        ~doc:"Path to the llvm-profdata executable (defaults to %a)"
        ~default:default.llvm_profdata_path
        ~env:"LLVM_PROFDATA"
        ~runtime:true
        (fun c s -> { c with llvm_profdata_path = s })
        (fun c -> c.llvm_profdata_path);
      string
        ~key:"genhtml-path"
        ~doc:"Path to the genhtml executable (defaults to %a)"
        ~default:default.genhtml_path
        ~env:"GENHTML"
        ~runtime:true
        (fun c s -> { c with genhtml_path = s })
        (fun c -> c.genhtml_path);
    ]

type coverage_use_model =
  | Gcov [@warning "-unused-constructor"]
  | LLVM
[@@warning "-unused-constructor"]                          (* for ocaml < 5.1 *)

(* --- *)

let install_resources_in: workspace:_ -> dir Lwt.t =
  Sc_core.Workspace.install_resources_in @@
  Sc_core.Resource.register_crunched "lcov" (module Lcov_res)

let availability_check ~options =
  Lwt_list.for_all_p Sc_sys.Process.exec_status
    Sc_sys.Ezcmd.Std.[
      make options.lcov_path |> key "version" |> to_cmd;
      make options.llvm_cov_path |> key "version" |> to_cmd;
      make options.llvm_profdata_path |> key "help" |> to_cmd;
      make options.genhtml_path |> key "version" |> to_cmd;
    ]

(* --- *)

let gen_coverage_flags = function
  | Gcov -> ["--coverage"]
  | LLVM -> ["-fprofile-instr-generate"; "-fcoverage-mapping"]

let compile_testsuite ~workdir ?(coverage = `Without) ~cppflags testsuite_file =
  let coverage_cflags =
    match coverage with
    | `Without -> []
    | `With model -> gen_coverage_flags model
  in
  let oracle_verdict_assessment_flag =
    "-D" ^ Sc_project.Export.oracle_verdict_assessment_preproc_flag
  in
  Sc_C.Cmd.clang_c testsuite_file
    ~o_dir:workdir
    ~cppflags:(oracle_verdict_assessment_flag :: cppflags)
    ~cflags:("-O0" :: coverage_cflags)

let main_replacement_hack =
  Fmt.str "-Dmain=%s" Sc_project.Preproc.main_replacement_symbol

let compile_codebase_for_coverage ~project ~workdir ~resdir ~model =
  (* TODO: maybe limit process-parallelism here, via Lwt_stream.iter_n and a
     results mailbox. *)
  Lwt_list.map_p begin fun file_c ->
    Sc_C.Cmd.clang_c file_c
      ~o_dir:workdir
      ~cppflags:(main_replacement_hack ::
                 "-I" :: Sc_sys.File.absname resdir ::
                 (Sc_C.Cmd.cppflags_of_header_dirs @@
                  project.config.project_problem.header_dirs))
      ~cflags:("-O0" :: gen_coverage_flags model)
  end project.config.project_problem.input_files

let compile_fixtures ~project ~workdir ~resdir =
  Lwt_list.map_p begin fun file_c ->
    Sc_C.Cmd.clang_c file_c
      ~o_dir:workdir
      ~cppflags:(main_replacement_hack ::
                 "-I" :: Sc_sys.File.absname resdir ::
                 (Sc_C.Cmd.cppflags_of_header_dirs @@
                  project.config.project_problem.header_dirs))
      ~cflags:["-O0"]
  end project.config.project_problem.fixtures_files

let compile_exe ~workdir ~model ~codebase_objects ~external_libs testsuite_o =
  let output_filename f =
    Sc_sys.File.(name @@
                 PRETTY.assume_in ~dir:workdir "%s.exe" @@
                 basename ~chop_extension:true f)
  in
  Sc_C.Cmd.clang_ld testsuite_o ~output_filename
    ~o_files:codebase_objects
    ~ldflags:("-O0" :: gen_coverage_flags model @ external_libs)

let compile_n_exec ~options ~project ~workdir ~resdir ~model testfiles =
  let coverage = if options.include_testsuite then `With model else `Without in
  let* codebase_objects =
    compile_codebase_for_coverage ~project ~workdir ~resdir ~model
  and* fixtures_objects =
    compile_fixtures ~project ~workdir ~resdir
  in
  let executables =
    let cppflags = Sc_project.Export.sufficient_cppflags project in
    Lwt_stream.map_s begin fun c_file ->
      compile_testsuite ~workdir ~coverage ~cppflags c_file >>=
      compile_exe ~workdir ~model
        ~codebase_objects:(codebase_objects @ fixtures_objects)
        ~external_libs:project.config.project_problem.external_libs
    end testfiles
  in
  let* () =
    Lwt_stream.iter_p begin fun exe ->
      Sc_sys.Process.join_lwt @@
      Sc_sys.Process.exec [|Sc_sys.File.absname exe|]
        ~cwd:(Sc_sys.File.absname workdir)
        ~on_success:Lwt.return
        ~on_error:(fun _ -> Lwt.return ())
    end (Lwt_stream.clone executables)
  in
  Lwt_stream.to_list executables

let testfiles = function
  | Combined_testsuite { cov; _ } ->
      Lwt_stream.return cov.file
  | Split_testsuite { cov; _ } ->
      Lwt_stream.of_list cov |>
      Lwt_stream.map (fun (c: individual_test_in_testsuite) -> c.file)

let run_lcov ~options ~workspace ~info_file =
  Sc_sys.Process.join_lwt @@
  Sc_sys.Process.exec
    [|
      options.lcov_path;
      "--capture";
      "--output-file"; Sc_sys.File.name info_file;
      "--directory"; Sc_sys.File.name workspace.workdir;
      "--gcov-tool"; options.llvm_cov_path;
      "--gcov-tool"; "gcov";
    |]
    ~stdout:(`Log Log_lwt_lcov.LWT.debug)
    ~stderr:(`Log Log_lwt_lcov.LWT.debug)
    ~log_command:`On_exit
    ~on_success:Lwt.return

let run_llvm_profdata ~options ~workspace ~profdata_file =
  let* profraw_files =
    Sc_sys.Lwt_file.files_of_dir workspace.workdir |>
    Lwt_stream.filter (fun f -> Sc_sys.File.check_suffix f ".profraw") |>
    Lwt_stream.map Sc_sys.File.absname |>
    Lwt_stream.to_list
  in
  Sc_sys.Process.join_lwt @@
  Sc_sys.Process.exec
    ~stdout:(`Log Log_lwt_llvm_profdata.LWT.debug)
    ~stderr:(`Log Log_lwt_llvm_profdata.LWT.debug)
    ~log_command:`On_exit
    ~on_success:Lwt.return
  @@ Array.of_list @@ [
    options.llvm_profdata_path;
    "merge";
    "--sparse";
    "--output"; Sc_sys.File.name profdata_file;
  ] @ profraw_files

let llvm_cov_cmd ~options ~profdata_file ~execs cmd_n_args =
  Array.of_list @@
  options.llvm_cov_path :: cmd_n_args
  @ [ "--instr-profile";
      Sc_sys.File.name profdata_file;
      Sc_sys.File.name (List.hd execs) ]
  @ List.concat_map (fun e -> ["--object"; Sc_sys.File.name e]) (List.tl execs)

let llvm_show_lcov ~options ~profdata_file ~execs =
  if not options.report_in_logs then Lwt.return () else
    Sc_sys.Process.join_lwt @@
    Sc_sys.Process.exec (llvm_cov_cmd ~options ~profdata_file ~execs
                           ["show"; "--show-branches=percent"])
      ~stdout:(`Log Log_lwt_llvm_cov.LWT.info)
      ~stderr:(`Log Log_lwt_llvm_cov.LWT.debug)
      ~log_command:`On_exit
      ~on_success:Lwt.return

let outfile_descr file =
  Sc_sys.Lwt_file.descriptor file [O_CREAT; O_WRONLY; O_NONBLOCK] 0o644

let llvm_show_text_report ~options ~profdata_file ~execs =
  if options.text_report = "" then Lwt.return () else
    let* text_fd = outfile_descr (Sc_sys.File.assume options.text_report) in
    Sc_sys.Process.join_lwt @@
    Sc_sys.Process.exec (llvm_cov_cmd ~options ~profdata_file ~execs
                           ["show"; "--show-branches=percent"])
      ~stdout:(`FD_move (Lwt_unix.unix_file_descr text_fd))
      ~stderr:`Dev_null
      ~log_command:`On_exit
      ~on_success:Lwt.return

let llvm_export_lcov_info ~options ~profdata_file ~execs ~info_file =
  let* info_fd = outfile_descr info_file in
  Sc_sys.Process.join_lwt @@
  Sc_sys.Process.exec (llvm_cov_cmd ~options ~profdata_file ~execs
                         ["export"; "--format"; "lcov"])
    ~stdout:(`FD_move (Lwt_unix.unix_file_descr info_fd))
    ~stderr:`Dev_null
    ~log_command:`On_exit
    ~on_success:Lwt.return

let run_genhtml ~options ~srcdir:_ ~info_file ~report_dir =
  Sc_sys.Process.join_lwt @@
  Sc_sys.Process.exec
    [|
      options.genhtml_path;
      Sc_sys.File.name info_file;
      "--output-directory"; Sc_sys.File.name report_dir;
      (* "--source-directory"; Sc_sys.File.name srcdir; <- only lcov≥2 *)
      "--branch-coverage";
      (* TODO: depends on version of `genhtml` *)
      (* "--exclude"; "seacoral/annots.h";        (\* FIXME: bit too hardcoded... *\) *)
      (* "--ignore-errors"; "unused"; *)
    |]
    ~stdout:(`Log Log_lwt_genhtml.LWT.debug)
    ~stderr:(`Log Log_lwt_genhtml.LWT.debug)
    ~log_command:`On_exit
    ~on_success:Lwt.return

let exec_testsuite_n_gen_report ~project ~workspace ~options testsuite =
  let* resdir = install_resources_in ~workspace in
  let model = LLVM in
  let report_dir =
    if options.outdir = ""
    then workspace.workdir / "report"
    else Sc_sys.File.assume_dir options.outdir
  in
  let* () =
    Sc_sys.Lwt_file.touch_dir report_dir
  and* execs =
    compile_n_exec ~options ~project ~workdir:workspace.workdir ~resdir ~model
      (testfiles testsuite)
  in
  let info_file = workspace.workdir / "seacoral.info" in
  let* () =
    match model with
    | Gcov ->
        run_lcov ~options ~workspace ~info_file
    | LLVM ->
        let profdata_file = workspace.workdir / "default.profdata" in
        run_llvm_profdata ~options ~workspace ~profdata_file >>= fun () ->
        llvm_show_lcov ~options ~profdata_file
          ~execs >>= fun () ->
        llvm_export_lcov_info ~options ~profdata_file
          ~execs ~info_file >>= fun () ->
        llvm_show_text_report ~options ~profdata_file
          ~execs
  in
  let* () =
    run_genhtml ~options ~info_file ~report_dir
      ~srcdir:project.config.project_srcdir_root
  in
  Lwt.return Sc_sys.File.(existing_dir @@ name report_dir)

let run ~project testsuite : dir option Lwt.t =
  let options =
    Sc_config.Section.get
      ~for_:(`Entrypoint (Sc_project.Manager.entrypoint_name project))
      config_section
  in
  if not options.lcov_enabled then
    Lwt.return_none
  else
    let* ok = availability_check ~options in
    if not ok then
      let* () = Log.LWT.warn "lcov is unavailable" in
      Lwt.return_none
    else
      let* workspace = Sc_core.Workspace.LWT.mksub project.workspace "lcov" in
      exec_testsuite_n_gen_report ~project ~workspace ~options testsuite >>=
      Lwt.return_some
