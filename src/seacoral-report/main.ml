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
open Sc_sys.File.Syntax

open Lwt.Syntax

module Log = (val (Ez_logs.from_src @@
                   Logs.Src.create ~doc:"Logs of main module" "Sc"))

type 'raw_test db_data = {
  label_data: Sc_ltest.Types.label_data [@warning "-unused-field"];
  lbls: Sc_C.Cov_label.simple list;
  project: 'raw_test Sc_project.Types.project;
  covinfo: Sc_store.Types.covinfo;
  corpus_info: Sc_corpus.Types.info;
  testsuite: Sc_project.Types.testsuite;
} [@@warning "-unused-field"]                              (* for ocaml < 5.1 *)

let r_title ~entrypoint =
  Format.asprintf "Coverage report for function %s" entrypoint

(** Helpers to build the Overview page. *)
module Overview = struct
  (* The tool table in argument has the following format:
     [tool1]
     tool1-key = value
     tool2-key = value

     [tool2]
     ...
  *)
  let table_to_tool_list (table : Toml.Types.table) : (string * (string * string) list) list =
    Toml.Types.Table.fold
      (fun toolname tool_config acc ->
         (Toml.Types.Table.Key.to_string toolname,
          match tool_config with
          | Toml.Types.TTable tool_config ->
              Toml.Types.Table.fold
                (fun key v acc ->
                   let key = Toml.Types.Table.Key.to_string key in
                   let str_v =
                     match v with
                     | Toml.Types.TBool b -> string_of_bool b
                     | TInt i -> string_of_int i
                     | TFloat f -> string_of_float f
                     | TString s -> s
                     | _ -> "--unsupported--"
                   in
                   (key, str_v) :: acc)
                tool_config
                []
          | _ -> []
         ) :: acc
      )
      table
      []

  (** Builds the configuration table as an accordion list. *)
  let config_table_to_accordion run_id table =
    Report_builder.make_accordion_list
      ~name:(Format.sprintf "run-%i-accordion" run_id)
      (table_to_tool_list table)

  (** Builds the details of Run [run_id] from the configuration table
      [table]. *)
  let run_details_from_toml_table run_id table =
    let name = Format.sprintf "Run %i" run_id in
    name,
    Report_builder.{
      run_time = 0.0; (* TODO: change run time *)
      run_config = config_table_to_accordion run_id table;
      extra_run_html = ""
    }

  (** Builds an overview value. *)
  let make db_data =
    let num_covered
      = Basics.Ints.cardinal db_data.covinfo.covered_ids in
    let num_uncoverable
      = Basics.Ints.cardinal db_data.covinfo.uncoverable_ids in
    let* config_tables =
      Lwt_stream.to_list @@
      Sc_project.Run.successive_configs @@
      Sc_project.Manager.run_info db_data.project
    in
    let succ_num_runs, rev_runs =
      List.fold_left
        (fun (cpt, acc) t ->
           (cpt + 1),
           (run_details_from_toml_table cpt t :: acc))
        (1, [])
        config_tables
    in
    Lwt.return @@
    Report_builder.{
      num_tests_gen = db_data.corpus_info.num_tests_gen;
      num_tests_imported = db_data.corpus_info.num_tests_imported;
      num_labels = db_data.covinfo.num_ids;
      num_covered; num_uncoverable;
      num_runs = succ_num_runs - 1;
      runs = Report_builder.make_tab_list ~name:"runs" (List.rev rev_runs)
    }
end

module Tests = struct
  let make { project; testsuite; _ } =
    let open Report_builder in
    (* let* files = test_files_list db_data in *)
    match testsuite with
    | Split_testsuite { cov = inputs; _ } ->
        let* rev_tests =
          Lwt_stream.fold begin fun ({ file; metadata }:
                                       individual_test_in_testsuite) acc ->
            let run_ref_time =
              Sc_project.Run.ref_time_of ~run_num:metadata.crearun
                project.config.project_run
            in
            try
              (Format.sprintf "Test %i" metadata.serialnum,
               { tool_name = metadata.toolname;
                 tool_time = metadata.creatime -. run_ref_time;
                 test_file = file }) :: acc
            with Sc_sys.File.MISSING _ -> acc
          end (Lwt_stream.of_list inputs) []
        in
        Lwt.return @@
        Split (make_tab_list ~name:"tests" (List.rev rev_tests))
    | Combined_testsuite { cov; rte; fail; _ } ->
        let first_tabs =
          [ "Coverage tests", { file = cov.file };
            "RTE-triggering tests", { file = rte.file } ]
        and fail_tab =
          match fail with
          | None ->
              []
          | Some fail ->
              [ "Oracle failing tests", { file = fail.file } ]
        in
        Lwt.return @@
        Combined (make_tab_list ~name:"tests" (first_tabs @ fail_tab))
end

module Labels = struct
  let report_label db_data (lbl: Sc_C.Cov_label.simple) =
    let lbl_id = Sc_C.Cov_label.id lbl in
    Format.sprintf "Label %i" lbl_id,
    Report_builder.{
      static_db_data = lbl;
      runtime_db_data =
        if Basics.Ints.mem lbl_id db_data.covinfo.covered_ids
        then `Cov
        else if Basics.Ints.mem lbl_id db_data.covinfo.uncoverable_ids
        then `Uncov
        else `Unk
    }

  let make db_data =
    let l = List.map (report_label db_data) db_data.lbls in
    Report_builder.make_tab_list ~name:"label" l
end

(** Creates a report from the static database. *)
let fetch_report_from_db db_data : Report_builder.Report.t Lwt.t =
  let* r_overview = Overview.make db_data in
  let* r_tests = Tests.make db_data in
  let r_labels = Labels.make db_data in
  let entrypoint = Sc_project.Manager.entrypoint_name db_data.project in
  Lwt.return Report_builder.{
      r_title = r_title ~entrypoint;
      r_tabs = Report_builder.make_tab_list ~name:"main_tabs"
          [
            "Overview", Overview r_overview;
            "Tests", Tests r_tests;
            "Labels", Labels r_labels
          ]
    }

(** Writes the report (a string) in the report file. *)
let write_report_in ~dir str =
  let name = dir / "report.html" in
  let> chan = name in
  output_string chan str;
  name

(** Prepares the report directory with the style files. *)
let prepare_dir_in ~(t : Types.config) ~workspace =
  (* Write-only files & dirs. *)
  let report_dir = Sc_sys.File.mkdir_in ~dir:workspace.workdir t.output_dir in
  let style_dir = Sc_sys.File.mkdir_in ~dir:report_dir "css" in
  (* Copying style files *)
  begin
    let css_file = Config.css_file t in
    let> chan = style_dir / "style.css" in
    output_string chan css_file
  end;
  report_dir

(** From a static database, writes the HTML report of the analysis. *)
let generate_report project testsuite =
  let t =
    Sc_config.Section.get
      ~for_:(`Entrypoint (Sc_project.Manager.entrypoint_name project))
      Config.section
  in
  if not t.enable then begin
    Log.debug "Not generating report, as requested.";
    Lwt.return_none
  end else begin
    Log.info "Report generation...";
    let report_dir = prepare_dir_in ~t ~workspace:project.workspace in
    let corpus_info = Sc_corpus.info project.corpus in
    let* covinfo = Sc_store.covinfo project.store in
    let db_data = {
      label_data = project.label_data;
      lbls = project.labels.simpl;
      project;
      covinfo;
      corpus_info;
      testsuite;
    } in
    let* report = fetch_report_from_db db_data in
    let report_html = Report_builder.Report.to_html report in
    Lwt.return_some @@ write_report_in ~dir:report_dir report_html
  end
