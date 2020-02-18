module type PIC32CONFIG = sig
  val mmcu : string
  val baud : int
  val clock : int
  val folder : string
  val pins_module : string
  val linker_scripts : string list
end

module FubarinoMiniConfig : PIC32CONFIG = struct
  let mmcu = "32MX250F128D"
  let baud = 115_200
  let clock = 48_000_000
  let folder = "fubarino_mini"
  let pins_module = "FubarinoMiniPins"
  let linker_scripts = []
end

module LchipConfig : PIC32CONFIG = struct
  let mmcu = "32MX795F512L"
  let baud = 115_200
  let clock = 48_000_000
  let folder = "lchip"
  let pins_module = "LchipPins"
  let linker_scripts = ["32MX795F512L-lchip.ld"]
end

let default_xc32_cxx_options = [ "-Wl,--defsym=_min_heap_size=1024" ]

module Pic32Config(P : PIC32CONFIG) : DEVICECONFIG = struct
  let compile_ml_to_byte ~ppx_options ~mlopts ~cxxopts ~trace ~verbose
      inputs output =
    let vars = [ ("CAMLLIB", libdir) ] in
    let cmd = [ ocamlc ] @ default_ocamlc_options @ ppx_options @ [ "-custom" ] @ mlopts in
    let cmd = if trace > 0 then cmd @ [ "-ccopt"; "-DDEBUG=" ^ string_of_int trace ] else cmd in
    let cmd = cmd @ List.flatten (List.map (fun cxxopt -> [ "-ccopt"; cxxopt ]) cxxopts) in
    let cmd = cmd @
              [ "-I"; Filename.concat libdir "targets/pic32" ;
                Filename.concat libdir "targets/pic32/pic32.cma";
                "-I"; Filename.concat libdir
                  (Filename.concat "targets/pic32" P.folder);
                Filename.concat libdir
                  (Filename.concat "targets/pic32"
                     (Filename.concat P.folder
                        ((String.uncapitalize_ascii P.pins_module)^".cmo")));
                "-open"; Printf.sprintf "Pic32";
                "-open"; Printf.sprintf "%s" P.pins_module ] in
    let cmd = cmd @ inputs @ [ "-o"; output ] in
    run ~vars ~verbose cmd

  let compile_c_to_hex ~trace:_ ~verbose input output =
    let pic32elf_file = (Filename.remove_extension output)^".pic32_elf" in
    (* Compile a .c into a .pic32_elf *)
    let append_linker_script (ls) = [ "-T"; Filename.concat includedir (Filename.concat "pic32/ld" ls) ] in
    let rec collect_linker_scripts script_list = 
      match script_list with
      | [] -> []
      | head::body -> append_linker_script (head) @ collect_linker_scripts body in
    let cmd = [ xc32_cxx ] @ default_xc32_cxx_options in
    let cmd = cmd @ [ "-mprocessor=" ^ P.mmcu ] in
    let cmd = cmd @ [ "-I"; Filename.concat includedir "pic32" ] in
    let cmd = cmd @ [ "-I"; Filename.concat includedir (Filename.concat "pic32" P.folder) ] in
    let cmd = cmd @ collect_linker_scripts P.linker_scripts in 
    let cmd = cmd @ [ input ; "-o"; pic32elf_file ] in
    run ~verbose cmd;
    (* Compile a .pic32_elf into a .hex *)
    let cmd = [ xc32_bin2hex ] in
    let cmd = cmd @ [ "-a"; pic32elf_file ] in
    run ~verbose cmd

  let flash ~sudo ~verbose path =
    let cmd = if sudo then [ "sudo" ] else [] in
    let cmd = cmd @ [ pic32prog ] in
    let cmd = cmd @ [ "-d"; tty (); "-b"; (string_of_int P.baud); path] in
    run ~verbose cmd
end

let get_config name = match name with
  | "fubarino-mini" -> (module Pic32Config(FubarinoMiniConfig) : DEVICECONFIG)
  | "lchip" -> (module Pic32Config(LchipConfig) : DEVICECONFIG)
  | _ -> get_config name

let all_config_names () = [
  "fubarino-mini";
  "lchip"
]@(all_config_names ())
