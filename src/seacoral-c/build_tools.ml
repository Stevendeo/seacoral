(**************************************************************************)
(*                                                                        *)
(*  Copyright (c) 2025 OCamlPro                                           *)
(*                                                                        *)
(*  All rights reserved.                                                  *)
(*  This file is distributed under the terms of the GNU Affero General    *)
(*  Public License.                                                       *)
(*                                                                        *)
(**************************************************************************)

type config =
  {
    clang_path: string;
    clangxx_path: string;
    ld_path: string;
    objcopy_path: string;
    cppflags: string;
    ldflags: string;
  }

let config_section =
  let default =
    {
      clang_path = "clang";
      clangxx_path = "clang++";
      ld_path = "ld";
      objcopy_path = "objcopy";
      cppflags = "";
      ldflags = "";
    }
  in
  Sc_config.Section.define "build-tools" ~default ~entries:Sc_config.Eztoml.[
      string
        ~key:"clang-path"
        ~doc:"Path to the clang executable (defaults to %a)"
        ~env:"CLANG"
        ~runtime:true             (* <- TODO: worth thinking about that maybe *)
        ~default:default.clang_path
        (fun c s -> { c with clang_path = s })
        (fun c -> c.clang_path);
      string
        ~key:"clangxx-path"
        ~doc:"Path to the clang++ executable (defaults to %a)"
        ~env:"CLANGXX"
        ~runtime:true             (* <- TODO: worth thinking about that maybe *)
        ~default:default.clangxx_path
        (fun c s -> { c with clangxx_path = s })
        (fun c -> c.clangxx_path);
      string
        ~key:"ld-path"
        ~doc:"Path to the ld executable (defaults to %a)"
        ~env:"LD"
        ~runtime:true
        ~default:default.ld_path
        (fun c s -> { c with ld_path = s })
        (fun c -> c.ld_path);
      string
        ~key:"objcopy-path"
        ~doc:"Path to the objcopy executable (defaults to %a)"
        ~env:"OBJCOPY"
        ~runtime:true
        ~default:default.objcopy_path
        (fun c s -> { c with objcopy_path = s })
        (fun c -> c.objcopy_path);
      string'
        ~key:"c-pre-processor-flags"
        ~doc:"Default pre-processor flags"
        ~env:"CPPFLAGS"
        ~runtime:false            (* <- TODO: worth thinking about that maybe *)
        (fun c s -> { c with cppflags = s })
        (fun c -> c.cppflags);
      string'
        ~key:"c-linker-flags"
        ~doc:"Default linker flags"
        ~env:"LDFLAGS"
        ~runtime:false            (* <- TODO: worth thinking about that maybe *)
        (fun c s -> { c with ldflags = s })
        (fun c -> c.ldflags);
    ]

let config =
  (* Ignoring entrypoint specific configuration for build_tools for now. *)
  lazy (Sc_config.Section.get ~for_:`Global config_section)
