(**************************************************************************)
(*                                                                        *)
(*  Copyright (c) 2025 OCamlPro                                           *)
(*                                                                        *)
(*  All rights reserved.                                                  *)
(*  This file is distributed under the terms of the GNU Affero General    *)
(*  Public License.                                                       *)
(*                                                                        *)
(**************************************************************************)

(** Post processing of test cases with lreplay *)

open Sc_project.Types

open Lwt.Infix
open Lwt.Syntax

(* --- *)

module Log = (val (Ez_logs.from_src @@ Logs.Src.create "Sc_postproc.Lreplay"))

type options =
  {
    lreplay_enabled: bool;
  }

let config_section =
  let default =
    {
      lreplay_enabled = true;
    }
  in
  Sc_config.Section.define "lreplay" ~default ~entries:Sc_config.Eztoml.[
      bool
        ~key:"enable"
        ~doc:"Enable post-processing with lreplay (defaults to %a)"
        ~default:default.lreplay_enabled
        ~as_flag:(Both { neg_keys = `Alt ["disable-lreplay"; "no-lreplay"];
                         neg_doc = `Alt "Disable post-processing with lreplay";
                         pos_keys = `Alt ["enable-lreplay"; "lreplay"];
                         pos_doc = `Alt "Enable post-processing with lreplay" })
        ~runtime:true
        (fun _ b -> { lreplay_enabled = b })
        (fun c -> c.lreplay_enabled);
    ]

let make_lreplay_module config =
  Sc_project.Manager.make_ltest_module config
    ~workspace:(Sc_core.Workspace.mksub config.project_workspace "lreplay")

let run (p: _ Sc_project.Types.project) testsuite =
  let lreplay_options =
    Sc_config.Section.get
      ~for_:(`Entrypoint (Sc_project.Manager.entrypoint_name p))
      config_section
  in
  if lreplay_options.lreplay_enabled
  then
    let* lrep_installed = Sc_ltest.Lreplay.lreplay_installed () in
    if lrep_installed
    then
      let module Ltest = (val make_lreplay_module p.config) in
      let* () =
        let covdir = match testsuite with
          | Split_testsuite { covdir; _ }
          | Combined_testsuite { covdir; _ } -> covdir
        in
        Ltest.Lreplay.lreplay_current_tests p.label_data.labelized_file
          ~extra_testsuite_headers:(Sc_project.Export.sufficient_generated_headers p)
          ~covdir
      in
      Lwt.return_some =<< Ltest.Label_database.results p.label_data.label_file
    else
      Log.LWT.warn "Lreplay@ is@ enabled,@ but@ not@ installed:@ no@ result@ \
                    will@ be@ reported" >>= fun () ->
      Lwt.return_none
  else
    Lwt.return None
