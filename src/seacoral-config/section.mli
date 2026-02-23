(**************************************************************************)
(*                                                                        *)
(*  Copyright (c) 2025 OCamlPro                                           *)
(*                                                                        *)
(*  All rights reserved.                                                  *)
(*  This file is distributed under the terms of the GNU Affero General    *)
(*  Public License.                                                       *)
(*                                                                        *)
(**************************************************************************)

(** The type of sections that induce configuration values of type ['a] *)
type _ section

type any_section = Any: _ section -> any_section

(** [define section_name ~entries ~default] defines a new configuration section
    with name [section_name], and TOML entires defined by [entires].  The
    default settings are given by [default]. *)
val define: string -> entries: 'a Eztoml.row list -> default: 'a -> 'a section

(** [load_section section table] updates the internal options for the given
    configuration section using [table]. *)
val load_section:
  'a section -> Toml.Types.table -> (unit, string) result

(** [load table] updates the internal options for registered configuration
    sections using [table]. *)
val load: Toml.Types.table -> (unit, string) result

(** [get ~check_loaded ~entrypoint section] retrieves the settings of the given
    section for a given entrypoint.

    Note: unless [check_loaded] is explicitly set to [false], {!load} must have
    been called before.  Otherwise, {!Errors.Unconfigured_section} is raised. *)
val get:
  ?check_loaded:bool
  -> for_:[`Global | `Entrypoint of string]
  -> 'a section
  -> 'a

(** [core_digest ()] computes a digest of the non-runtime part of the currently
    loaded configuration. *)
val core_digest: unit -> Digest.t

(** Prints a TOML file that corresponds to the default options for all the
    registered sections.

    Sections in [head] are printed first in the same order as in [head]; other
    sections are printed in lexicographic order. *)
val print_default_config_file: head:any_section list -> Format.formatter -> unit

(** Prints a TOML file that corresponds to the current set of options for all
    of the registered and configured sections. *)
val print_current_config_file: Format.formatter -> unit

(** Prints the full documentation of the registered configuration sections.

    See {!print_default_config_file} for the purposes of [head]. *)
val print_doc: head:any_section list -> Format.formatter -> unit

(** [as_section_update_cmdliner_term ~with_section_name_prefix section
    section_term] converts a configuration section into a {!Cmdliner} term for
    parsing command-line arguments.  If [with_section_name_prefix] holds, each
    long-option key for the section is prefixed with the section name and a `-`.

    Note: an evaluation of the resulting term performs a {e functional update}
    of a given record for a configuration section, but does {e not} correspond
    to a call to {!load}.  In particular, the changes have no effect on the
    configuration section that {!load} implicitly acts upon. *)
val as_section_update_cmdliner_term
  : ?with_section_name_prefix:bool
  -> 'a section
  -> 'a Cmdliner.Term.t
  -> 'a Cmdliner.Term.t

(** [as_toml_table_cmdliner_term ~with_section_name_prefix sections] is a
    {!Cmdliner} term that converts command-line arguments into a corresponding
    TOML table for the given list of sections.  If [with_section_name_prefix]
    holds, each long-option key for the section is prefixed with the section
    name and a `-`. *)
val as_toml_table_cmdliner_term
  : (any_section * [ `with_section_name_prefix |
                     `without_section_name_prefix]) list
  -> Toml.Types.table Cmdliner.Term.t

val manpage_section_name: any_section -> string
