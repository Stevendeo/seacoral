(**************************************************************************)
(*                                                                        *)
(*  Copyright (c) 2025 OCamlPro                                           *)
(*                                                                        *)
(*  All rights reserved.                                                  *)
(*  This file is distributed under the terms of the GNU Affero General    *)
(*  Public License.                                                       *)
(*                                                                        *)
(**************************************************************************)

module Log =
  (val (Ez_logs.from_src @@
        Logs.Src.create "Sc_config.Section"
          ~doc:"Logs of configuration sections manager"))

type 'a section =
  {
    section_name: string;
    section_schema: 'a Eztoml.schema;
    section_default: 'a;
    mutable section_status: 'a section_status;
  }
and 'a section_status =
  | Registered
  | Configured of { values: 'a entrypoint_status_map }
and any_section =
  | Any: _ section -> any_section
and 'a entrypoint_status_map = {
    global: 'a;
    specialized: (string, 'a) Hashtbl.t
  }

let sections: (string, any_section) Hashtbl.t =
  Hashtbl.create 1

let define (type o) name ~entries ~default : o section =
  if Hashtbl.mem sections name
  then raise @@ Errors.Duplicate_section_names name
  else
    let section =
      {
        section_name = name;
        section_schema = Eztoml.build entries;
        section_default = default;
        section_status = Registered;
      }
    in
    Hashtbl.add sections name (Any section);
    section

let subtable key table =
  let open Toml.Types in
  let key = Table.Key.of_string key in
  match Table.find key table with
  | TTable t ->
      t
  | value ->
      raise @@ Errors.Bad_value_type_in_toml_table (key, value, "table")
  | exception Not_found ->
      Table.empty

let section_subtable section table =
  subtable (section.section_name) table

(* Takes two tables and merges them. In case of conflict, takes
   the [spec]'s element. *)
let merge_global_and_specialized_tables glob spec =
  Toml.Types.Table.merge
    (fun _ v1 v2 ->
      match v1, v2 with
      | None, None -> None (* Dead code *)
      | Some v, None | None, Some v -> Some v (* No ambiguity *)
      | Some _, Some v -> Some v (* Ambiguous: take specialized *)
    ) glob spec

(* Assumes the toml file has sections prefixed with entrypoints.
   Returns the list of entrypoints associated to the configurations linked
   to their section table. *)
let specialized_tables_of_section section table :
      (string * Toml.Types.table) list =
  let open Toml.Types in
  Table.fold
    (fun ep v acc ->
      let ep = Table.Key.to_string ep in
      match v with
      | TTable t -> begin
         match Table.find (Table.Key.of_string section.section_name) t with
         | TTable t -> (ep, t) :: acc
         | _ ->
            Log.warn "Unexpected value for key %s.%s in configuration. \
                      Ignoring it.\
                      " ep section.section_name;
            acc
         | exception Not_found -> acc
        end
      | _ -> acc)
    table
    []

let update_section
      (section : 'a section)
      (from : 'a entrypoint_status_map)
      (table: Toml.Types.table) :
      ('a entrypoint_status_map, string) result =
  let error_header ppf =
    Fmt.pf ppf "Error@ in@ section@ [%s]:" section.section_name
  in
  try
    let global_subtable = section_subtable section table
    and specialized_tables = specialized_tables_of_section section table in
    let global = Eztoml.parse from.global global_subtable section.section_schema
    and specialized = from.specialized in
    let res = {global; specialized} in
    let () =
      List.iter
        (fun (entrypoint, spec_table) ->
          let ep_config_table =
            merge_global_and_specialized_tables global_subtable spec_table
          in
          let from =
            match Hashtbl.find from.specialized entrypoint with
            | v -> v
            | exception Not_found -> from.global
          in
          let config =
            Eztoml.parse from ep_config_table section.section_schema
          in
          Hashtbl.add specialized entrypoint config)
        specialized_tables
    in
    Ok res
  with
  | Errors.Bad_value_type_in_toml_table  _
  | Errors.Bad_value_in_toml_table _ as e ->
      Basics.PPrt.string_to (fun s -> Error s) "@[<2>%t@;%a@]"
        error_header Fmt.exn e
  | Errors.Unknown_toml_key _ as e ->
      Basics.PPrt.string_to (fun s -> Error s)
        "@[<2>%t@;%a@;(accepted@ entries@ are:@;@[%a@])@]"
        error_header Fmt.exn e
        Fmt.(list ~sep:comma string) (Eztoml.keys section.section_schema)

let load_section section (table: Toml.Types.table) : (unit, string) result =
  let from =
    match section.section_status with
    | Configured { values } -> values
    | Registered -> {
        global = section.section_default
      ; specialized = Hashtbl.create 0}
  in
  match update_section section from table with
  | Ok values ->
      section.section_status <- Configured { values };
      Ok ()
  | Error e ->
      Error e

let load (table: Toml.Types.table) : (unit, string) result =
  (* A local exception to stop the iteration. The string is the Error
     message to return. *)
  (* TODO: symbolic errors *)
  let exception Err of string in
  try
    Hashtbl.iter begin fun _name (Any section) ->
      match load_section section table with
      | Ok () -> ()
      | Error e -> raise (Err e)
    end sections;
    Ok ()
  with Err e ->
    Error e

let get (type o) ?(check_loaded = true) ~for_ (section: o section) : o =
  match section.section_status with
  | Registered when check_loaded ->
      raise @@ Errors.Unconfigured_section section.section_name
  | Registered ->
      Log.warn "Configuration section %S has not been loaded (yet?); returning \
                default options." section.section_name;
      section.section_default
  | Configured { values } -> begin
      match for_ with
      | `Global -> values.global
      | `Entrypoint ep ->
          try Hashtbl.find values.specialized ep with
          | Not_found -> values.global
    end

let digest_config buff section c =
  Buffer.add_string buff @@
  Digest.to_hex @@
  Eztoml.core_digest section.section_schema c
  

let core_digest () : Digest.t =
  let buff = Buffer.create 42 in
  Hashtbl.iter begin fun _name (Any section) : unit ->
    match section.section_status with
    | Registered -> digest_config buff section section.section_default
    | Configured { values } ->
       digest_config buff section values.global;
       Hashtbl.iter
         (fun _ -> digest_config buff section)
         values.specialized
    end sections;
  Digest.bytes (Buffer.to_bytes buff)

let print_toml_spec ppf (Any section) : unit =
  Eztoml.print_as_toml_file ppf (section.section_name, section.section_schema)

let section_name (Any s) =
  s.section_name

let section_compare s1 s2 =
  String.compare (section_name s1) (section_name s2)

let iter_sections ~head f =
  (* Small hack to visit important modules first. *)
  let in_head s = List.exists (fun s' -> section_compare s s' = 0) head in
  List.iter f head;
  (* Sort remaining sections lexicographically. *)
  List.iter f begin
    List.sort section_compare @@ List.of_seq @@
    Seq.filter (fun s -> not (in_head s)) @@
    Hashtbl.to_seq_values sections
  end

let print_default_config_file ~head ppf =
  iter_sections ~head (print_toml_spec ppf)

let print_current_config_file ppf =
  iter_sections ~head:[] begin fun (Any section) ->
    match section.section_status with
    | Registered -> 
       Eztoml.print_as_toml_file ~with_doc:false ppf
         (section.section_name, section.section_schema)
    | Configured {values} ->
       Eztoml.print_as_toml_file ~with_doc:false ~value:values.global ppf
         (section.section_name, section.section_schema);
       Hashtbl.iter
         (fun entrypoint value ->
           let key = Fmt.str "%s.%s" entrypoint section.section_name in
           Eztoml.print_as_toml_file ~with_doc:false ~value:value ppf
             (key, section.section_schema))
         values.specialized
  end

let print_doc ~head ppf =
  iter_sections ~head begin fun (Any section) ->
    let section_name = Fmt.(styled (`Fg (`Hi `Magenta)) string) in
    let section_header ppf section =
      Fmt.pf ppf "@[<h>Configuration@ section@ [%a]:@]"
        section_name section.section_name
    in
    Fmt.pf ppf "@[<v>%a@;%a@]@."
      Fmt.(styled `Bold section_header) section
      Eztoml.print_doc section.section_schema
  end

let key_prefix ?(with_section_name_prefix = true) section =
  if with_section_name_prefix
  then Some section.section_name
  else None

let manpage_section_name (Any section) =
  Eztoml.manpage_section_name section.section_name

let as_section_update_cmdliner_term ?with_section_name_prefix section =
  Eztoml.as_section_update_cmdliner_term section.section_schema
    ~section_name:section.section_name
    ?prefix:(key_prefix ?with_section_name_prefix section)

let as_toml_table_cmdliner_term sections =
  List.fold_left begin fun table (Any s, prefix_flag) ->
    let with_section_name_prefix = prefix_flag = `with_section_name_prefix in
    Eztoml.acc_toml_table_for_cmdliner s.section_schema table
      ~section_name:s.section_name
      ?prefix:(key_prefix ~with_section_name_prefix s)
  end (Cmdliner.Term.const Toml.Types.Table.empty) sections
