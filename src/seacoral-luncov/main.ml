(**************************************************************************)
(*                                                                        *)
(*  Copyright (c) 2025 OCamlPro                                           *)
(*                                                                        *)
(*  All rights reserved.                                                  *)
(*  This file is distributed under the terms of the GNU Affero General    *)
(*  Public License.                                                       *)
(*                                                                        *)
(**************************************************************************)

open Basics

open Sc_core.Types
open Sc_project.Types

open Lwt.Syntax
open Sc_sys.Lwt_file.Syntax

let toolname = "luncov"

module Log =
  (val (Ez_logs.from_src @@
        Logs.Src.create ~doc:"Logs of LUncov tool" "Sc_ltest.Luncov"))

type opt = {
  frama_c_tools : string list;
  architecture: Sc_ltest.Framac.Arch.t;
  frama_c_extra_args: string list; (* ["key:val"; ...] *)
}

type 'raw_test working_data = {
  project: 'raw_test Sc_project.Types.project;
  label_file: [`labeldb] Sc_sys.File.t [@warning "-unused-field"];
  main_file: [`C] Sc_sys.File.t;
  opt: opt;
} [@@warning "-unused-field"]                              (* for ocaml < 5.1 *)

let config_section =
  let default =
    {
      frama_c_tools = ["wp"];
      architecture = X86_64;
      frama_c_extra_args = []
    }
  in
  Sc_config.Section.define toolname ~default ~entries: Sc_config.Eztoml.[
      string_list
        ~key:"plugins"
        ~doc:"Sets the plugins tools used by luncov. Default is %a. \"eva\" \
              (or \"value\") is also possible, but not recommended as it may \
              report coverable labels uncoverable."
        ~default:default.frama_c_tools
        ~runtime:true
        (fun c frama_c_tools -> {c with frama_c_tools})
        (fun c -> c.frama_c_tools)
      ;
      string_list
        ~key:"extra-args"
        ~doc:"Adds extra arguments to frama-c as pair of \"cmd_key:cmd_value\" \
              separated by a comma (default: %a)"
        ~default:default.frama_c_extra_args
        ~runtime:true
        (fun c frama_c_extra_args -> {c with frama_c_extra_args})
        (fun c -> c.frama_c_extra_args)
      ;
    ]

(* --- *)

let emit_initcall project ppf =
  Option.iter begin fun (init: Sc_C.Types.func_repr) ->
    Fmt.pf ppf "(void) %s ();@," init.func_name
  end project.params.init_func

let args project (fname : string) =
  Sc_C.Defs.fun_args fname project.params.cil

let emit_main_file opt project ppf =
  let func_name = project.params.func_repr.func_name in
  let args = args project func_name in
  Lwt_fmt.fprintf ppf {|
/* #define %s // Architecture */
#include <__fc_builtin.h>
#include <__fc_machdep.h>
#include <limits.h>
#include <float.h>
#include %S

int main (%a) {
  /* Function call */
  %t(void) %s (%a);
}@.
|}
    (Sc_ltest.Framac.Arch.to_fc_string opt.architecture)
    (Sc_sys.File.absname project.label_data.labelized_file)
    Sc_C.Printer.pp_formal_decls args
    (emit_initcall project)
    func_name Sc_C.Printer.pp_vars args

(* luncov will work on a link of the label file. *)
let link_file { workdir = dir; _ } ?(no_preprocess=false)
    (orig_file : [> `labeldb] Sc_sys.File.t)
  : [> `labeldb] Sc_sys.File.t =
  if no_preprocess
  then Sc_sys.File.existing_in ~dir (Sc_sys.File.basename orig_file)
  else Sc_sys.File.link_in_dir ~dir orig_file


let create_main_file ~opt ~no_preprocess { workdir; _ } project
  : [`C] Sc_sys.File.t Lwt.t =
  let new_file =
    Sc_sys.File.assume_in ~dir:workdir @@
    Sc_sys.File.basename project.label_data.labelized_file
  in
  let* () =
    if no_preprocess
    then Lwt.return ()
    else let>*% ppf = new_file in emit_main_file opt project ppf
  in
  Lwt.return new_file

let setup workspace ~optional:no_preprocess project : _ Lwt.t =
  let opt =
    Sc_config.Section.get
      ~for_:(`Entrypoint (Sc_project.Manager.entrypoint_name project))
      config_section
  in
  let label_data = project.label_data in
  let label_file = link_file ~no_preprocess workspace label_data.label_file in
  let* main_file = create_main_file ~opt ~no_preprocess workspace project in
  Lwt.return { project; label_file; main_file; opt }

let synchronize_store ~tic project =
  let time = Unix.gettimeofday () -. tic in
  let* uncoverables =
    let lbls =
      Sc_ltest.Label_database.get_lbls ~filter:Sc_C.Cov_label.is_uncoverable
        project.label_data.label_file
    in
    lbls.any
    |> List.rev_map Sc_C.Cov_label.id
    |> Ints.of_list
    |> Lwt.return
  in
  Lwt.catch begin fun () ->
    Lwt.join [
      Sc_project.Manager.report_tool_status project (Ok ())
        ~toolname ~elapsed_time:time ~tests_generated:0;
      Sc_store.share_status project.store
        ~toolname `Uncov uncoverables;
    ]
  end begin function
    | Sc_store.Types.Proof_inconsistency pi ->
        Log.LWT.err "@[<v>@[Unable@ to@ update@ the@ store@ due@ to@ proof@ \
                     inconsistencies:@]@;%a@]\
                    " Sc_store.Printer.pp_proof_inconsistency pi
    | e ->
        Lwt.reraise e
  end

(* Log module for reporting luncov sub-process outputs *)
module Log_luncov = (val Ez_logs.subproc "luncov")

(* Calls luncov *)
let run wd =
  let tic = Unix.gettimeofday () in
  let* cmd =
    let config = wd.project.config in
    let module Conf = struct
      let workspace = wd.project.workspace  (* TODO: mksub workspace "luncov" *)
      let config = config.project_problem
    end in
    (* XXX: what is this Conf actually for? *)
    Sc_ltest.Framac.luncov_cmd (module Conf)
      ~main_name:"main"
      ~framac_tools:wd.opt.frama_c_tools
      ~extra_args:wd.opt.frama_c_extra_args
      [wd.main_file]
  in
  (* We wait for the process to end *)
  Sc_sys.Process.join_lwt @@
  Sc_sys.Process.exec cmd
    ~stdout:(`Log Log_luncov.LWT.debug)
    ~stderr:(`Log Log_luncov.LWT.debug)
    ~on_success:(fun () -> synchronize_store ~tic wd.project)
    ~on_error:(fun _ -> Lwt.return ())

let availability_check () : bool Lwt.t =
  Sc_ltest.Framac.luncov_installed ()

let load () =
  Sc_lib.Tool.register_function For_any_label ~name:toolname
    ~config_section:(Some config_section)
    ~availability_check ~kind:`Static
    ~setup:begin fun ws ~optional (P p) ->
      let* wd = setup ws ~optional p in
      Lwt.return (fun () -> run wd)
    end
