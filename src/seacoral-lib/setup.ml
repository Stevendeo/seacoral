(**************************************************************************)
(*                                                                        *)
(*  Copyright (c) 2025 OCamlPro                                           *)
(*                                                                        *)
(*  All rights reserved.                                                  *)
(*  This file is distributed under the terms of the GNU Affero General    *)
(*  Public License.                                                       *)
(*                                                                        *)
(**************************************************************************)

(** Validation of user-given configuration, and project initialization. *)

(** The code in this module translates user-given configurations into the
    structures that are appropriate for the project manager, and initializes the
    main working directory along the way. *)

open Types
open Sc_sys.File.TYPES

open Lwt.Infix
open Lwt.Syntax
open Sc_sys.File.Syntax

module Log = (val (Ez_logs.from_src @@ Logs.Src.create "Sc_lib.Setup"))

(* --- *)

let project_hash ~salt ~files _config =
  (* TODO: include relevant environment variables *)
  Digest.to_hex @@ Digest.string @@ String.concat "" [
    Sc_sys.File.hash_files files;
    salt;
  ]

let tagged_workdir ?(clean_start = false) root_workdir (hash: string) : dir Lwt.t =
  (* TODO: use a lock file in output_path to avoid some (quite unlikely) race
     conditions? *)
  let actual_folder = root_workdir / hash in
  let* () =
    if clean_start && Sc_sys.File.exists actual_folder
    then begin
      let new_dir =
        Sc_sys.File.rename_away
          ~old_file:actual_folder
          ~new_basename:(".archived-" ^ Sc_sys.File.basename actual_folder)
      in
      (* Redirect all symlinks that point to actual_folder *)
      Sc_sys.Lwt_file.redirect_symlinks_of
        ~dir:root_workdir
        ~src:(Sc_sys.File.basename actual_folder)
        ~dst:new_dir
    end else Lwt.return ()
  in
  let* () = Sc_sys.Lwt_file.touch_dir actual_folder in
  Lwt.return actual_folder

let create_pretty_dirs ~project_name ~criterion workdir : dir Lwt.t =
  let dirname = Sc_sys.File.basename workdir in
  let parent = Sc_sys.File.dir workdir in
  let parent_name = Sc_sys.File.name parent in
  (* Creating the directories aliases *)
  let readable_link =
    String.escaped @@
    Fmt.str "%s/%s-%s" parent_name project_name criterion
  in
  let timed_link_base =
    Fmt.str "%s-%a" readable_link
      Basics.PPrt.pp_time Unix.(localtime @@ gettimeofday ())
  in
  let* timed_link =                                (* readable link with time *)
    (* Here, multiple attempts and the suffix (`+i`) are used to deal with calls
       that happen within a short time period, like during automated tests,
       since the timing scheme is not precise enough.  Such a prefix should not
       appear during normal operations though. *)
    Sc_sys.Lwt_file.newsymlink ~to_dir:true ~src:dirname
      ~dstformat:(function
          | 1 -> timed_link_base
          | i -> Fmt.str "%s+%u" timed_link_base i)
  in
  let* short_link =                          (* readable link with nb of runs *)
    Sc_sys.Lwt_file.newsymlink ~to_dir:true ~src:(Filename.basename timed_link)
      ~dstformat:(Fmt.str "%s-@%u" readable_link)
  in
  let* () =                                      (* readable link to last run *)
    Sc_sys.Lwt_file.resymlink ~to_dir:true ~src:(Filename.basename short_link)
      ~dst:(Fmt.str "%s-last" readable_link)
  in
  let* () =                                 (* add one generic `last` symlink *)
    Sc_sys.Lwt_file.resymlink ~to_dir:true ~src:(Filename.basename short_link)
      ~dst:(String.escaped @@ Sc_sys.File.name (parent / "last"))
  in
  Lwt.return @@ Sc_sys.File.assume_dir short_link

(** Relocates user-given inputs {i w.r.t} the configuration file, if any.
    Filters out non-existing input files.

    May raise {!Sc_sys.File.MISSING} in case the tool is launched from a
    directory that does not exist (note this is very-very unlikely). *)
let locate_files (config: config) =
  let root = match config.run.config_input with
    | None -> Sc_sys.File.assume "."       (* Dependent of Sys.getcwd. *)
    | Some i -> Sc_sys.File.parent i.file  (* Dependent of configuration file. *)
  in
  Sc_sys.File.fail_on_missing_dir root;
  let locate kind files =
    List.filter_map begin fun filename ->
      if not (Filename.is_relative filename)
      then Some (Sc_sys.File.existing filename)
      else begin
        try
          Some (Sc_sys.File.existing_in ~dir:root filename)
        with Sc_sys.File.MISSING { file } ->
          (* Note: we may end up with an empty list here. *)
          Main_log.err "Ignoring@ missing@ %s@ file@ %a\
                       " kind Sc_sys.File.print file;
          None
      end
    end files
  in
  let input_files = locate "input" config.project.input_files in
  let fixtures_files = locate "fixtures" config.fixtures.files in
  let header_dirs = List.map (fun d -> root / d) config.project.header_dirs in
  root, input_files, header_dirs, fixtures_files

(** Configuration validation and project initialization function *)
let project ?clean_start ~salt (config: config) =

  let srcdir_root, input_files, header_dirs, fixtures_files
    = locate_files config
  in

  if input_files = []
  then raise @@ CONFIG_ERROR Missing_input_file;

  if config.project.entrypoint = ""
  then raise @@ CONFIG_ERROR Missing_entrypoint;

  Strategy.check_tools_spec config.run.tools;

  let resroot = Sc_sys.File.assume config.run.workdir / "shared" in

  (* let plate = Sc_config.Section.get
        ~for_:(`Entrypoint (Sc_project.Manager.entrypoint_name project))
        Plate_config.section
      in *)

  let* workdir =
    let project_hash =
      project_hash ~salt ~files:(input_files @ fixtures_files) config
    in
    let project_name =
      match config.project.name, input_files, config.project.entrypoint with
      | n, _, _ when n <> "" -> n
      | _, [f], _ -> Sc_sys.File.basename f
      | _, _, entrypoint -> entrypoint
    in
    let root_workdir = Sc_sys.File.mkdir config.run.workdir in
    Sc_sys.Lwt_file.with_lock_in root_workdir ReadWrite begin fun () ->
      tagged_workdir ?clean_start root_workdir project_hash >>=
      create_pretty_dirs ~project_name ~criterion:config.project.cover_criterion
    end
  in

  let* run_data =
    Sc_project.Run.new_in ~workdir ~loaded_config_file:config.run.config_input
  in

  Lwt.return @@
  Sc_project.Types.{
    project_workspace =
      {
        workdir;
        resroot = Sc_core.Resource.root resroot;
      };
    project_run = run_data;
    project_problem =
      {
        input_files = input_files;
        entrypoint = config.project.entrypoint;
        criterion = config.project.cover_criterion;
        header_dirs;
        external_libs = config.project.external_libs;
        annotated_functions = config.project.functions_to_cover;
        ignored_globals = Basics.Strings.of_list config.project.ignored_globals;
        fixtures_files;
        initialization_function = config.fixtures.init;
        oracle_function = config.fixtures.oracle;
        seek_oracle_failures = config.fixtures.seek_oracle_failures;
      };
    project_check_syntax = config.run.enable_syntax_check;
    project_test_timeout = config.run.test_timeout;
    project_max_validation_concurrency = config.run.max_validation_concurrency;
    project_verbose_validation = config.run.verbose_validation;
    project_inhibit_store_autostop = false;
    project_pointer_handling =
      {
        treat_pointer_as_array =
          List.map Sc_C.Named_loc.of_string
            config.pointer_handling.treat_pointer_as_array;
        treat_pointer_as_cstring =
          List.map Sc_C.Named_loc.of_string
            config.pointer_handling.treat_pointer_as_cstring;
        array_size_mapping =
          List.map Sc_C.Named_loc.assoc_of_string
            config.pointer_handling.array_size_mapping;
      };
    project_srcdir_root = srcdir_root;
  }


let test_encoding_params (config: config) =
  Lwt.return @@
  Sc_values.{
    max_ptr_array_length = config.pointer_handling.max_ptr_array_length;
    max_non_nil_ptr_depth = config.pointer_handling.max_non_nil_ptr_depth;
    max_cstring_length = config.pointer_handling.max_cstring_length;
  }
