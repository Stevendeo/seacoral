(**************************************************************************)
(*                                                                        *)
(*  Copyright (c) 2025 OCamlPro                                           *)
(*                                                                        *)
(*  All rights reserved.                                                  *)
(*  This file is distributed under the terms of the GNU Affero General    *)
(*  Public License.                                                       *)
(*                                                                        *)
(**************************************************************************)

(* If you delete or rename this file, you should add
   'src/sc_main/main.ml' to the 'skip' field in "drom.toml" *)

open Sc_core.Types
open Sc_project.Types

open Lwt.Syntax
open Sc_sys.File.Syntax

module Log = Sc_lib.Main_log

(* ---- *)

(* NB: force module loading until we implement proper dynlink of plugins: *)
let load_plugins () =
  Sc_klee.Main.load ();
  Sc_fuzz.Libfuzzer.load ();
  Sc_cbmc.Main.load ();
  Sc_replayer.Main.load ();
  Sc_luncov.Main.load ()

(* TODO: make the same with all the modules expanding the exception printer *)
let init_printers () =
  Sc_config.Printer.init ()

let () =
  load_plugins ();
  init_printers ()

(* --- *)

let colored_logfiles =
  match Sc_sys.Env.get ~default:"no" "SC_ENABLE_COLORED_LOGFILES" with
  | "yes" | "1" -> true
  | _ -> false                       (* disabled for other values; TODO: warn? *)

(* --- *)

(** Used to exit "gracefully" with a given code from {!with_lwt} below. *)
exception EXIT of Cmdliner.Cmd.Exit.code

(** [with_lwt f] executes [f] while catching every raised exception.  Returns
    {!Cmdliner.Cmd.Exit.ok} in case of success, or some error code otherwise. *)
(* Note: this assumes there's no logging in place.  Logging exceptions needs to
   be done within [f]. *)
let with_lwt f =
  Lwt_main.run @@ Lwt.catch begin fun () ->
    let* () = f () in
    Lwt.return Cmdliner.Cmd.Exit.ok
  end begin function
    | EXIT e ->
        Lwt.return e
    | Sc_sys.File.(INVALID_FILENAME _ | MISSING _ |
                   UNEXPECTED _ | UNIX_ERROR _) as e ->
        Fmt.epr "%a@." Fmt.exn e;
        Lwt.return Cmdliner.Cmd.Exit.cli_error
    | e ->
        Fmt.epr "%a@." Fmt.exn_backtrace (e, Printexc.get_raw_backtrace ());
        Lwt.return Cmdliner.Cmd.Exit.internal_error
  end

(* --- *)

(** Setup the reporters and returns a function to update the console level *)
let setup_reporters ~enable_console_timing =
  let time_precision = if enable_console_timing then 2 else 0 in
  Ez_logs.init_stdout_reporter ~time_precision ();
  Logs.set_level (Some Debug);
  (fun i -> Ez_logs.stdout_level_ref := i)

(** Configuration sections to be put first in listings *)
let first_config_sections =
  Sc_config.Section.[
    Any Options.logs_section;
    Any Sc_lib.Config.run_section;
    Any Sc_lib.Config.project_section;
    Any Sc_lib.Config.pointer_handling_section;
  ]

let show_toml_documentation () =
  Sc_config.Section.print_doc Fmt.stdout ~head:first_config_sections;
  Fmt.pr "%!";
  Cmdliner.Cmd.Exit.ok

let init_config_file () =                           (* TODO: `init_args` type *)
  try
    let file = Sc_sys.File.create_empty "seacoral.toml" in
    let () =
      let> chan = file in
      Sc_config.Section.print_default_config_file
        (Format.formatter_of_out_channel chan) ~head:first_config_sections
    in
    Fmt.pr "@[<hov>Default@ configuration@ saved@ in@ %a@]@.\
           " Sc_sys.File.print file;
    Cmdliner.Cmd.Exit.ok
  with Sc_sys.File.UNEXPECTED { file } ->
    Fmt.epr "@[<hov>File@ %a@ exists:@ not@ overriding@]@.\
            " Sc_sys.File.print file;
    Cmdliner.Cmd.Exit.cli_error

(** Start log reporting; returns a function to close any underlying log file. *)
let with_logging ?(enable_logfile = true) ~project_config f =
  if not enable_logfile then
    f ()
  else begin
    let workdir = project_config.project_workspace.workdir in
    let log_file =
      Sc_sys.File.(PRETTY.assume_in ~dir:(mkdir_in ~dir:workdir "logs"))
        "%u.log" project_config.project_run.run_num
    in
    let style_renderer = if colored_logfiles then `Ansi_tty else `None in
    let close_log =
      Ez_logs.persist_in ~oc:(Sc_sys.File.open_append log_file)
        ~time_precision:4 ~style_renderer (Logs.reporter ())
        ~right_margin:(Format.get_margin ())     (* for now: margin of stdout *)
    in
    Log.debug "Previous runs: %u" (pred project_config.project_run.run_num);
    Log.app "Starting to log into `%a'" Sc_sys.File.print log_file;
    Lwt.finalize f begin fun () ->
      close_log ();
      Lwt.return ()
    end
  end

let log_config_info (config: Sc_lib.Types.config) =
  match config.run.config_input with
  | Some { file; _ } ->
      Log.info "Configuration@ loaded@ from `%a'" Sc_sys.File.print file
  | None ->
      ()

let lookup_config_file (_args: Types.options) : [`toml] Sc_sys.File.file option =
  Log.debug "Looking@ up@ configuration@ file...";
  try
    Sc_sys.File.(find_until_root_from ~dir:(assume_dir @@ Sys.getcwd ()))
      ~f:begin fun dir ->
        let file = dir / "seacoral.toml" in
        if Sc_sys.File.exists file then Some file else raise Not_found
      end
  with Not_found ->
    None

let read_config (args: Types.options) =
  match
    match args.config_file with
    | Some f -> Some f
    | None -> lookup_config_file args
  with
  | None ->
      Toml.Types.Table.empty, None
  | Some file ->
      Log.debug "Loading@ configuration@ from `%a'" Sc_sys.File.print file;
      let toml_file = Sc_config.Eztoml.read_file file in
      match Sc_config.Eztoml.load_file toml_file with
      | Ok toml_table ->
          toml_table, Some toml_file
      | Error toml_error ->
          Fmt.epr "%a" Sc_config.Printer.pp_toml_error toml_error;
          raise @@ EXIT Cmdliner.Cmd.Exit.cli_error

let amend_config (args: Types.options) =
  match Sc_config.Section.load args.amending_table with
  | Error msg ->
      Fmt.epr "@[<v>\
               @[Error@ while@ handling@ configuration@ values@ from@ \
               command-line@ arguments:@]@;\
               @[%a@]\
               @]@." Fmt.text msg;
      raise @@ EXIT Cmdliner.Cmd.Exit.internal_error
  | Ok () ->
      ()

let load_config ?(enable_console_timing = true) args =
  let config_table, config_input = read_config args in
  match Sc_config.Section.load config_table with
  | Error msg ->
      Fmt.epr "@[<hov>%a@]@." Fmt.text msg;
      raise @@ EXIT Cmdliner.Cmd.Exit.cli_error
  | Ok () ->
      amend_config args;
      let module Section = Sc_config.Section in
      let for_ =
        (* Only used to get the entrypoint. *)
        let global_project =
          Section.get ~for_:`Global Sc_lib.Config.project_section
        in
        `Entrypoint global_project.entrypoint
      in
      let logs_config = Section.get ~for_ Options.logs_section in
      setup_reporters ~enable_console_timing logs_config.log_level;
      Log.app "Getting main configuration";
      let project = Section.get ~for_ Sc_lib.Config.project_section in
      let run = Section.get ~for_ Sc_lib.Config.run_section
      and fixtures = Section.get ~for_ Sc_lib.Config.fixtures_section
      and pointer_handling =
        Section.get ~for_ Sc_lib.Config.pointer_handling_section
      and run_salt = Section.core_digest () in
      Log.debug "Salt: %s" (Digest.to_hex run_salt);
      Sc_lib.Types.{ run = { run with config_input };
                     project; fixtures; pointer_handling },
      run_salt

let config_step f =
  Lwt.catch f begin function
    | Sc_lib.Types.CONFIG_ERROR e ->
        Fmt.epr "@[<hov>Error@ in@ project@ configuration:@;%a@]@."
          Sc_lib.Printer.pp_config_error e;
        raise @@ EXIT Cmdliner.Cmd.Exit.cli_error
    | e ->
        Lwt.reraise e
  end

let make_strategy (config : Sc_lib.Types.config) =
    Sc_lib.Strategy.make config.run.tools config.run.strategy

let run
    ?enable_logfile ?(enable_detailed_stats = true)
    ?enable_console_timing ~mode (args: Types.options) () =
  (* TODO: add an option `--debug-init` to enable logging during the preliminary
     loading phase. *)
  let config, salt = load_config ?enable_console_timing args in
  let* project_config =
    config_step begin fun () ->
      Sc_lib.Setup.project config ~clean_start:args.clean_start ~salt
    end
  and* encoding_params =
    config_step begin fun () ->
      Sc_lib.Setup.test_encoding_params config
    end
  and* mode =
    match mode with
    | `Replay | `Config_check as mode ->
        Lwt.return mode
    | `Generate ->
        config_step begin fun () ->
          Lwt.return @@ `Generate (make_strategy config)
        end
  in
  with_logging ?enable_logfile ~project_config begin fun () ->
    log_config_info config;
    Lwt.catch begin fun () ->
      match mode with
      | `Config_check ->
          Lwt.return ()
      | `Generate strategy ->
          Sc_lib.Main.generate ~project_config ~encoding_params
            { run = config.run;
              enable_detailed_stats;
              strategy;
              print_statistics = args.print_statistics }              (* temp *)
      | `Replay ->
          Sc_lib.Main.replay ~project_config ~encoding_params
            { replay_config = config.run }
    end begin function
      | Sc_lib.Types.GENERATION_ERROR e ->
          Log.err "%a" Sc_lib.Printer.pp_generation_error e;
          raise @@ EXIT Cmdliner.Cmd.Exit.cli_error
      | Sc_sys.File.(INVALID_FILENAME _ | MISSING _ |     (* log while we can *)
                     UNEXPECTED _ | UNIX_ERROR _) as e ->
          Log.err "%a" Fmt.lines (Printexc.to_string e);
          raise @@ EXIT Cmdliner.Cmd.Exit.cli_error
      | Sc_lib.Types.REPLAY_ERROR _ ->
          .
      | e ->
          Lwt.reraise e
    end
  end

;;
if (Unix.time () |> Unix.gmtime).Unix.tm_year > 126
then failwith "Too old for this; please ask seacoral@ocaml.pro for help."
;;

let config_sections_that_show_up_as_arguments =
  let plugin_sections = Sc_lib.Tool.known_config_sections () in
  Sc_config.Section.[
    Any Options.logs_section, `without_section_name_prefix;
    Any Sc_lib.Config.run_section, `without_section_name_prefix;
    Any Sc_lib.Config.project_section, `without_section_name_prefix;
    Any Sc_lib.Config.pointer_handling_section, `without_section_name_prefix;
    Any Sc_lib.Config.fixtures_section, `with_section_name_prefix;
    Any Sc_project.Export.config_section, `with_section_name_prefix;
    Any Sc_postproc.Lreplay.config_section, `with_section_name_prefix;
    Any Sc_postproc.Eacsl.config_section, `with_section_name_prefix;
    Any Sc_report.Config.section, `with_section_name_prefix;
    Any Sc_postproc.Lcov.config_section, `with_section_name_prefix;
    Any Sc_C.Build_tools.config_section, `without_section_name_prefix;
  ] @ List.map (fun s -> s, `with_section_name_prefix) plugin_sections

let gen_man =
  let sections_in_manpage =
    List.map
      (fun (s, _) -> `S (Sc_config.Section.manpage_section_name s))
      config_sections_that_show_up_as_arguments
  in
  [
    `P "See $(b,EXAMPLES) below for usage examples.";
    `S Cmdliner.Manpage.s_common_options;
  ] @ sections_in_manpage @ [
    `S Cmdliner.Manpage.s_examples;
    `P "To generate tests, start by initializing a test generation project with:";
    `Pre "$(mname) $(b,config init)";
    `P "This will create a file $(i,seacoral.toml) with default configuration \
        values in the current directory.";
    `P "Then, you may run the following command to generate tests for an \
        entrypoint function $(i,entry_function), targetting coverage criterion \
        $(i,DC) (decision coverage), and using some tools currently available:";
    `Pre "$(mname) $(b,generate --sources source1.c,source2.c \\\\)"; `Noblank;
    `Pre "                  $(b,--entrypoint entry_function   \\\\)"; `Noblank;
    `Pre "                  $(b,--criterion DC                \\\\)"; `Noblank;
    `Pre "                  $(b,--tools klee,libfuzzer,cbmc)";
    `P "To avoid using additional command-line arguments as above, you may also \
        edit $(i,seacoral.toml) with the appropriate values:";
    `Pre "  [project]"; `Noblank;
    `Pre "  files      = [\"source1.c\", \"source2.c\"]"; `Noblank;
    `Pre "  entrypoint = \"entry_function\""; `Noblank;
    `Pre "  criterion  = \"DC\""; `Noblank;
    `Pre "  [run]"; `Noblank;
    `Pre "  tools      = [\"klee\", \"libfuzzer\", \"cbmc\"]";
    `P "and then run:";
    `Pre "$(mname) $(b,generate)";
    `P "In both cases, $(mname) will perform its test generation job withinh a \
        working directory (named $(i,_sc) by default).  After that, you may find \
        tests generated for coverage within $(i,_sc/last/tests/cov), and \
        possibly tests that trigger runtime errors or undefined behaviors in \
        $(i,_sc/last/tests/rte).";
    `S Cmdliner.Manpage.s_exit_status;
    `S Cmdliner.Manpage.s_bugs;
    `P "Please email bug reports to <seacoral@ocaml.pro>."
  ]

let load_args ?argv () =
  let open Cmdliner.Cmd in
  let gen_term = Options.term ~config_sections_that_show_up_as_arguments in
  let generate = Cmdliner.Term.map (fun options -> `Generate options) gen_term
  and check = Cmdliner.Term.map (fun options -> `Check options) gen_term
  and replay = Cmdliner.Term.map (fun options -> `Replay options) gen_term in
  eval_value ~catch:false ?argv @@
  group ~default:generate
    (info "seacoral" ~version:Version.version ~doc:"Tests for your project!"
       ~man:(`S Cmdliner.Manpage.s_commands :: gen_man)) @@
  [
    v (info "generate" ~man:gen_man ~doc:"Generate tests (default action)")
      generate;
    group (info "config" ~doc:"Managing configurations") @@
    [
      v (info "initialize" ~doc:"Dump a configuration file with default options")
        (Cmdliner.Term.const `Config_init);
      v (info "doc" ~doc:"Show documentation for the contents of the \
                          configuration file")
        (Cmdliner.Term.const `Config_show_toml);
    ];
    v (info "initialize"                       (* alias for config initialize *)
         ~doc:"Dump a configuration file with default options (alias for \
               $(b,config initialize) sub-command)")
      (Cmdliner.Term.const `Config_init);
    v (info "check" ~man:gen_man
         ~doc:"Check configuration and perform initial project initialization")
      check;
    v (info "replay" ~man:gen_man
         ~doc:"Replay the current test suite without starting any test \
               generation tool.")
      replay;
  ]

let main ?enable_console_timing ?enable_detailed_stats ?enable_logfile ?argv () =

  Basics.PPrt.init_formatters ();

  match load_args ?argv () with
  | Ok `Ok `Config_show_toml ->
      show_toml_documentation ()
  | Ok `Ok `Config_init ->
      init_config_file ()
  | Ok `Ok `Generate args ->
      with_lwt (run ?enable_logfile ?enable_detailed_stats
                  ?enable_console_timing ~mode:`Generate args)
  | Ok `Ok `Check args ->
      with_lwt (run ?enable_logfile ?enable_detailed_stats
                  ?enable_console_timing ~mode:`Config_check args)
  | Ok `Ok `Replay args ->
      with_lwt (run ?enable_logfile ?enable_detailed_stats
                  ?enable_console_timing ~mode:`Replay args)
  | Ok `Version
  | Ok `Help ->
      Cmdliner.Cmd.Exit.ok
  | Error _e ->
      Cmdliner.Cmd.Exit.cli_error
