(*
  Translation from ATD types into OCaml types and pretty-printing.

  This is derived from the ATD pretty-printer (atd_print.ml).
*)

open Printf

open Easy_format
open Atd_ast
open Ag_mapping


(* Type mapping from ATD to OCaml *)

type atd_ocaml_sum = [ `Classic | `Poly ]
type atd_ocaml_record = [ `Record | `Object ]

type atd_ocaml_int = [ `Int | `Char | `Int32 | `Int64 | `Float ]
type atd_ocaml_list = [ `List | `Array ]

type atd_ocaml_shared = [ `Flat | `Ref ]

type atd_ocaml_wrap = {
  ocaml_wrap_t : string;
  ocaml_wrap : string;
  ocaml_unwrap : string;
}

type atd_ocaml_field = {
  ocaml_default : string option;
  ocaml_fname : string;
  ocaml_mutable : bool;
  ocaml_fdoc : Ag_doc.doc option;
}

type atd_ocaml_variant = {
  ocaml_cons : string;
  ocaml_vdoc : Ag_doc.doc option;
}

type atd_ocaml_def = {
  ocaml_predef : bool;
  ocaml_ddoc : Ag_doc.doc option;
}

type atd_ocaml_repr =
    [
    | `Unit
    | `Bool
    | `Int of atd_ocaml_int
    | `Float
    | `String
    | `Sum of atd_ocaml_sum
    | `Record of atd_ocaml_record
    | `Tuple
    | `List of atd_ocaml_list
    | `Option
    | `Nullable
    | `Shared of atd_ocaml_shared
    | `Wrap of atd_ocaml_wrap option
    | `Name of string
    | `External of (string * string * string)
        (*
          (module providing the type,
           module providing everything else,
           type name)
        *)

    | `Cell of atd_ocaml_field
    | `Field of atd_ocaml_field
    | `Variant of atd_ocaml_variant
    | `Def of atd_ocaml_def
    ]

type target = [ `Default | `Biniou | `Json | `Validate ]


let ocaml_int_of_string s : atd_ocaml_int option =
  match s with
      "int" -> Some `Int
    | "char" -> Some `Char
    | "int32" -> Some `Int32
    | "int64" -> Some `Int64
    | "float" -> Some `Float
    | _ -> None

let string_of_ocaml_int (x : atd_ocaml_int) =
  match x with
      `Int -> "int"
    | `Char -> "Char.t"
    | `Int32 -> "Int32.t"
    | `Int64 -> "Int64.t"
    | `Float -> "float"

let ocaml_sum_of_string s : atd_ocaml_sum option =
  match s with
      "classic" -> Some `Classic
    | "poly" -> Some `Poly
    | s -> None

let ocaml_record_of_string s : atd_ocaml_record option =
  match s with
      "record" -> Some `Record
    | "object" -> Some `Object
    | s -> None

let ocaml_list_of_string s : atd_ocaml_list option =
  match s with
      "list" -> Some `List
    | "array" -> Some `Array
    | s -> None

let string_of_ocaml_list (x : atd_ocaml_list) =
  match x with
      `List -> "list"
    | `Array -> "Ag_util.ocaml_array"

let ocaml_shared_of_string s : atd_ocaml_shared option =
  match s with
      "flat" -> Some `Flat
    | "ref" -> Some `Ref
    | s -> None

let get_ocaml_int an =
  Atd_annot.get_field ocaml_int_of_string `Int ["ocaml"] "repr" an

let get_ocaml_type_path atd_name an =
  let x =
    match atd_name with
	"unit" -> `Unit
      | "bool" -> `Bool
      | "int" -> `Int (get_ocaml_int an)
      | "float" -> `Float
      | "string" -> `String
      | s -> `Name s
  in
  match x with
      `Unit -> "unit"
    | `Bool -> "bool"
    | `Int x -> string_of_ocaml_int x
    | `Float -> "float"
    | `String -> "string"
    | `Name s -> s

let path_of_target (target : target) =
  match target with
      `Default -> [ "ocaml" ]
    | `Biniou -> [ "ocaml_biniou"; "ocaml" ]
    | `Json -> [ "ocaml_json"; "ocaml" ]
    | `Validate -> [ "ocaml_validate"; "ocaml" ]

let get_ocaml_sum an =
  Atd_annot.get_field ocaml_sum_of_string `Poly ["ocaml"] "repr" an

let get_ocaml_field_prefix an =
  Atd_annot.get_field (fun s -> Some s) "" ["ocaml"] "field_prefix" an

let get_ocaml_record an =
  Atd_annot.get_field ocaml_record_of_string `Record ["ocaml"] "repr" an

let get_ocaml_list an =
  Atd_annot.get_field ocaml_list_of_string `List ["ocaml"] "repr" an

let get_ocaml_shared an =
  Atd_annot.get_field ocaml_shared_of_string `Flat ["ocaml"] "repr" an

let get_ocaml_wrap loc an =
  let module_ =
    Atd_annot.get_field (fun s -> Some (Some s)) None ["ocaml"] "module" an in
  let default field =
    match module_ with
        None -> None
      | Some s -> Some (sprintf "%s.%s" s field)
  in
  let t =
    Atd_annot.get_field (fun s -> Some (Some s))
      (default "t") ["ocaml"] "t" an
  in
  let wrap =
    Atd_annot.get_field (fun s -> Some (Some s))
      (default "wrap") ["ocaml"] "wrap" an
  in
  let unwrap =
    Atd_annot.get_field (fun s -> Some (Some s))
      (default "unwrap") ["ocaml"] "unwrap" an
  in
  match t, wrap, unwrap with
      None, None, None -> None
    | Some t, Some wrap, Some unwrap ->
        Some { ocaml_wrap_t = t; ocaml_wrap = wrap; ocaml_unwrap = unwrap }
    | _ ->
        Ag_error.error loc "Incomplete annotation. Missing t, wrap or unwrap"

let get_ocaml_cons default an =
  Atd_annot.get_field (fun s -> Some s) default ["ocaml"] "name" an

let get_ocaml_fname default an =
  Atd_annot.get_field (fun s -> Some s) default ["ocaml"] "name" an

let get_ocaml_default an =
  Atd_annot.get_field (fun s -> Some (Some s)) None ["ocaml"] "default" an

let get_ocaml_mutable an =
  Atd_annot.get_flag ["ocaml"] "mutable" an

let get_ocaml_predef target an =
  let path = path_of_target target in
  Atd_annot.get_flag path "predef" an

let get_ocaml_module target an =
  let path = path_of_target target in
  let o = Atd_annot.get_field (fun s -> Some (Some s)) None path "module" an in
  match o with
      Some s -> Some (s, s)
    | None ->
        let o =
          Atd_annot.get_field (fun s -> Some (Some s)) None path "from" an
        in
        match o with
            None -> None
          | Some s ->
              let type_module = s ^ "_t" in
              let main_module =
                match target with
                    `Default -> type_module
                  | `Biniou -> s ^ "_b"
                  | `Json -> s ^ "_j"
                  | `Validate -> s ^ "_v"
              in
              Some (type_module, main_module)

let get_ocaml_t target default an =
  let path = path_of_target target in
  Atd_annot.get_field (fun s -> Some s) default path "t" an

let get_ocaml_module_and_t target default_name an =
  match get_ocaml_module target an with
      None -> None
    | Some (type_module, main_module) ->
        Some (type_module, main_module, get_ocaml_t target default_name an)


(*
  OCaml syntax tree
*)
type ocaml_type_param = string list

type ocaml_expr =
    [ `Sum of (atd_ocaml_sum * ocaml_variant list)
    | `Record of (atd_ocaml_record * ocaml_field list)
    | `Tuple of ocaml_expr list
    | `Name of (string * ocaml_expr list)
    | `Tvar of string
    ]

and ocaml_variant =
    string * ocaml_expr option * Ag_doc.doc option

and ocaml_field =
    (string * bool (* is mutable? *)) * ocaml_expr * Ag_doc.doc option

type ocaml_def = {
  o_def_name : (string * ocaml_type_param);
  o_def_alias : (string * ocaml_type_param) option;
  o_def_expr : ocaml_expr option;
  o_def_doc : Ag_doc.doc option
}

type ocaml_module_item =
    [ `Type of ocaml_def ]

type ocaml_module_body = ocaml_module_item list



(*
  Mapping from ATD to OCaml
*)

let omap f = function None -> None | Some x -> Some (f x)

let rec map_expr (x : type_expr) : ocaml_expr =
  match x with
      `Sum (loc, l, an) ->
	let kind = get_ocaml_sum an in
	`Sum (kind, List.map map_variant l)
    | `Record (loc, l, an) ->
	let kind = get_ocaml_record an in
	let field_prefix = get_ocaml_field_prefix an in
        if l = [] then
          Ag_error.error loc "Empty record (not valid in OCaml)"
        else
	  `Record (kind, List.map (map_field field_prefix) l)
    | `Tuple (loc, l, an) ->
	`Tuple (List.map (fun (_, x, _) -> map_expr x) l)
    | `List (loc, x, an) ->
	let s = string_of_ocaml_list (get_ocaml_list an) in
	`Name (s, [map_expr x])
    | `Option (loc, x, an) ->
	`Name ("option", [map_expr x])
    | `Nullable (loc, x, an) ->
	`Name ("option", [map_expr x])
    | `Shared (loc, x, a) ->
        (match get_ocaml_shared a with
             `Flat -> map_expr x
           | `Ref -> `Name ("Pervasives.ref", [map_expr x])
        )
    | `Wrap (loc, x, a) ->
        (match get_ocaml_wrap loc a with
            None -> map_expr x
          | Some { ocaml_wrap_t } -> `Name (ocaml_wrap_t, [])
        )
    | `Name (loc, (loc2, s, l), an) ->
	let s = get_ocaml_type_path s an in
	`Name (s, List.map map_expr l)
    | `Tvar (loc, s) ->
	`Tvar s

and map_variant (x : variant) : ocaml_variant =
  match x with
      `Inherit _ -> assert false
    | `Variant (loc, (s, an), o) ->
	let s = get_ocaml_cons s an in
	(s, omap map_expr o, Ag_doc.get_doc loc an)

and map_field ocaml_field_prefix (x : field) : ocaml_field =
  match x with
      `Inherit _ -> assert false
    | `Field (loc, (atd_fname, fkind, an), x) ->
	let ocaml_fname =
	  get_ocaml_fname (ocaml_field_prefix ^ atd_fname) an in
	let fname =
	  if ocaml_fname = atd_fname then ocaml_fname
	  else sprintf "%s (*atd %s *)" ocaml_fname atd_fname
	in
	let is_mutable = get_ocaml_mutable an in
	((fname, is_mutable), map_expr x, Ag_doc.get_doc loc an)

let map_def
    ~(target : target)
    ~(type_aliases : string option)
    ((loc, (s, param, an1), x) : type_def) : ocaml_def option =
  let is_predef = get_ocaml_predef target an1 in
  let is_abstract = Ag_mapping.is_abstract x in
  let define_alias =
    if is_predef || is_abstract || type_aliases <> None then
      match get_ocaml_module_and_t target s an1, type_aliases with
          Some (types_module, main_module, s), _ -> Some (types_module, s)
        | None, Some types_module -> Some (types_module, s)

        | None, None -> None
    else
      None
  in
  if is_predef && define_alias = None then
    None
  else
    let an2 = Atd_ast.annot_of_type_expr x in
    let an = an1 @ an2 in
    let doc = Ag_doc.get_doc loc an in
    let alias, x =
      match define_alias with
          None ->
            if is_abstract then (None, None)
            else (None, Some (map_expr x))
        | Some (module_path, ext_name) ->
            let alias = Some (module_path ^ "." ^ ext_name, param) in
            let x =
              match map_expr x with
                  `Sum (`Classic, _)
                | `Record (`Record, _) as x -> Some x
                | _ -> None
            in
            (alias, x)
    in
    if x = None && alias = None then
      None
    else
      Some {
        o_def_name = (s, param);
        o_def_alias = alias;
        o_def_expr = x;
        o_def_doc = doc
      }

let rec select f = function
    [] -> []
  | x :: l ->
      match f x with
	  None -> select f l
	| Some y -> y :: select f l

let map_module ~target ~type_aliases (l : module_body) : ocaml_module_body =
  select (
    fun (`Type td) ->
      match map_def ~target ~type_aliases td with
	  None -> None
	| Some x -> Some (`Type x)
  ) l


(*
  Mapping from Ag_mapping to OCaml
*)


let rec ocaml_of_expr_mapping (x : (atd_ocaml_repr, _) mapping) : ocaml_expr =
  match x with
      `Unit (loc, `Unit, _) -> `Name ("unit", [])
    | `Bool (loc, `Bool, _) -> `Name ("bool", [])
    | `Int (loc, `Int x, _) -> `Name (string_of_ocaml_int x, [])
    | `Float (loc, `Float, _) -> `Name ("float", [])
    | `String (loc, `String, _) -> `Name ("string", [])
    | `Sum (loc, a, `Sum kind, _) ->
        let l = Array.to_list a in
        `Sum (kind, List.map ocaml_of_variant_mapping l)
    | `Record (loc, a, `Record o, _) ->
        let l = Array.to_list a in
        `Record (`Record, List.map ocaml_of_field_mapping l)
    | `Tuple (loc, a, o, _) ->
        let l = Array.to_list a in
        `Tuple (List.map (fun x -> ocaml_of_expr_mapping x.cel_value) l)
    | `List (loc, x, `List kind, _) ->
        `Name (string_of_ocaml_list kind, [ocaml_of_expr_mapping x])
    | `Option (loc, x, `Option, _) ->
        `Name ("option", [ocaml_of_expr_mapping x])
    | `Nullable (loc, x, `Nullable, _) ->
        `Name ("option", [ocaml_of_expr_mapping x])
    | `Name (loc, s, l, _, _) ->
        `Name (s, List.map ocaml_of_expr_mapping l)
    | `Tvar (loc, s) ->
        `Tvar s
    | _ -> assert false

and ocaml_of_variant_mapping x =
  let o =
    match x.var_arepr with
        `Variant o -> o
      | _ -> assert false
  in
  (o.ocaml_cons, omap ocaml_of_expr_mapping x.var_arg, o.ocaml_vdoc)

and ocaml_of_field_mapping x =
  let o =
    match x.f_arepr with
        `Field o -> o
      | _ -> assert false
  in
  let v = ocaml_of_expr_mapping x.f_value in
  ((o.ocaml_fname, o.ocaml_mutable), v, o.ocaml_fdoc)


(*
  Pretty-printing
*)



let rlist = { list with
		wrap_body = `Force_breaks;
		indent_body = 0;
		align_closing = false;
		space_after_opening = false;
		space_before_closing = false
	    }

let plist = { list with
		align_closing = false;
		space_after_opening = false;
		space_before_closing = false }

let hlist = { list with wrap_body = `No_breaks }
let shlist = { hlist with
		 stick_to_label = false;
		 space_after_opening = false;
		 space_before_closing = false }
let shlist0 = { shlist with space_after_separator = false }

let llist = {
  list with
    separators_stick_left = false;
    space_before_separator = true;
    space_after_separator = true
}

let lplist = {
  llist with
    space_after_opening = false;
    space_before_closing = false
}

let vseq = {
  list with
    indent_body = 0;
    wrap_body = `Force_breaks;
}


let vlist1 = { list with stick_to_label = false }

let vlist = {
  vlist1 with
    wrap_body = `Force_breaks;
}


let label0 = { label with space_after_label = false }

let make_atom s = Atom (s, atom)

let horizontal_sequence l = List (("", "", "", shlist), l)
let horizontal_sequence0 l = List (("", "", "", shlist0), l)

let rec insert sep = function
    [] | [_] as l -> l
  | x :: l -> x :: sep @ insert sep l

let rec insert2 f = function
    [] | [_] as l -> l
  | x :: (y :: _ as l) -> x :: f x y @ insert2 f l


let vertical_sequence ?(skip_lines = 0) l =
  let l =
    if skip_lines = 0 then l
    else
      let sep =
        Array.to_list (Array.init skip_lines (fun _ -> (Atom ("", atom))))
      in
      insert sep l
  in
  List (("", "", "", rlist), l)

let escape f s =
  let buf = Buffer.create (2 * String.length s) in
  for i = 0 to String.length s - 1 do
    let c = s.[i] in
    match f c with
        None -> Buffer.add_char buf c
      | Some s -> Buffer.add_string buf s
  done;
  Buffer.contents buf

let ocamldoc_escape s =
  let esc = function
      '{' | '}' | '[' | ']' | '@' | '\\' as c -> Some (sprintf "\\%c" c)
    | _ -> None
  in
  escape esc s

let ocamldoc_verbatim_escape s =
  let esc = function
      '{' | '}' | '\\' as c -> Some (sprintf "\\%c" c)
    | _ -> None
  in
  escape esc s

let split = Str.split (Str.regexp " ")


let make_ocamldoc_block = function
    `Pre s -> Atom ("\n{v\n" ^ ocamldoc_verbatim_escape s ^ "\nv}", atom)
  | `Before_paragraph -> Atom ("", atom)
  | `Paragraph l ->
      let l = List.map (
        function
            `Text s -> ocamldoc_escape s
          | `Code s -> "[" ^ ocamldoc_escape s ^ "]"
      ) l
      in
      let words = split (String.concat "" l) in
      let atoms = List.map (fun s -> Atom (s, atom)) words in
      List (("", "", "", plist), atoms)

let make_ocamldoc_blocks (l : Ag_doc.block list) =
  let l =
    insert2 (
      fun x y ->
        match y with
            `Paragraph _ -> [`Before_paragraph]
          | `Pre _ -> []
          | _ -> assert false
    ) (l :> [ Ag_doc.block | `Before_paragraph ] list)
  in
  List.map make_ocamldoc_block l


let make_ocamldoc_comment (`Text l) =
  let blocks = make_ocamldoc_blocks l in
  let xlist =
    match l with
        [] | [_] -> vlist1
      | _ -> vlist
  in
  List (("(**", "", "*)", xlist), blocks)

let prepend_ocamldoc_comment doc x =
  match doc with
      None -> x
    | Some y ->
        let comment = make_ocamldoc_comment y in
        List (("", "", "", rlist), [comment;x])

let append_ocamldoc_comment x doc =
  match doc with
      None -> x
    | Some y ->
        let comment = make_ocamldoc_comment y in
        Label ((x, label), comment)

let rec format_module_item
    is_first (`Type def : ocaml_module_item) =
  let type_ = if is_first then "type" else "and" in
  let s, param = def.o_def_name in
  let alias = def.o_def_alias in
  let expr = def.o_def_expr in
  let doc = def.o_def_doc in
  let append_if b s1 s2 =
    if b then s1 ^ s2
    else s1
  in
  let part1 =
    horizontal_sequence (
      make_atom type_ ::
        prepend_type_param param
        [ make_atom (append_if (alias <> None || expr <> None) s " =") ]
    )
  in
  let part12 =
    match alias with
        None -> part1
      | Some (name, param) ->
          let right =
            horizontal_sequence (
              prepend_type_param param
                [ make_atom (append_if (expr <> None) name " =") ]
            )
          in
          Label (
            (part1, label),
            right
          )
  in
  let part123 =
    match expr with
        None -> part12

      | Some t ->
	  Label (
	    (part12, label),
	    format_type_expr t
	  )
  in
  prepend_ocamldoc_comment doc part123

	
and prepend_type_param l tl =
  match l with
      [] -> tl
    | _ ->
	let make_var s = make_atom ("'" ^ s) in
	let x =
	  match l with
	      [s] -> make_var s
	    | l -> List (("(", ",", ")", plist), List.map make_var l)
	in
	x :: tl

and prepend_type_args l tl =
  match l with
      [] -> tl
    | _ ->
	let x =
	  match l with
	      [t] -> format_type_expr t
	    | l -> List (("(", ",", ")", plist), List.map format_type_expr l)
	in
	x :: tl

and format_type_expr x =
  match x with
      `Sum (kind, l) ->
	let op, cl =
	  match kind with
	      `Classic -> "", ""
	    | `Poly -> "[", "]"
	in
	List (
	    (op, "|", cl, llist),
	    List.map (format_variant kind) l
	  )
    | `Record (kind, l) ->
	let op, cl =
	  match kind with
	      `Record -> "{", "}"
	    | `Object -> "<", ">"
	in
	List (
	  (op, ";", cl, list),
	  List.map format_field l
	)
    | `Tuple l ->
	List (
	  ("(", "*", ")", lplist),
	  List.map format_type_expr l
	)
    | `Name (name, args) ->
	format_type_name name args

    | `Tvar name ->
	make_atom ("'" ^ name)

and format_type_name name args =
  horizontal_sequence (prepend_type_args args [ make_atom name ])
	
and format_field ((s, is_mutable), t, doc) =
  let l =
    let l = [make_atom (s ^ ":")] in
    if is_mutable then
      make_atom "mutable" :: l
    else l
  in
  let field =
    Label (
      (horizontal_sequence l, label),
      format_type_expr t
    )
  in
  append_ocamldoc_comment field doc

and format_variant kind (s, o, doc) =
  let s =
    match kind with
	`Classic -> s
      | `Poly -> "`" ^ s
  in
  let cons = make_atom s in
  let variant =
    match o with
        None -> cons
      | Some t ->
	  Label (
	    (cons, label),
	    Label (
	      (make_atom "of", label),
	      format_type_expr t
	    )
	  )
  in
  append_ocamldoc_comment variant doc

let format_module_items is_rec (l : ocaml_module_body) =
  match l with
      x :: l ->
	format_module_item true x ::
	  List.map (fun x -> format_module_item false x) l
    | [] -> []

let format_module_body is_rec (l : ocaml_module_body) =
  List (
    ("", "", "", rlist),
    format_module_items is_rec l
  )

let format_module_bodies (l : (bool * ocaml_module_body) list) =
  List.flatten (List.map (fun (is_rec, x) -> format_module_items is_rec x) l)

let format_head (loc, an) =
  match Ag_doc.get_doc loc an with
      None -> []
    | Some doc -> [make_ocamldoc_comment doc]

let format_all l =
  vertical_sequence ~skip_lines:1 l


let ocaml_of_expr x : string =
  Easy_format.Pretty.to_string (format_type_expr x)

let ocaml_of_atd ~target ~type_aliases
    (head, (l : (bool * module_body) list)) : string =
  let head = format_head head in
  let bodies =
    List.map (fun (is_rec, m) ->
                (is_rec, map_module ~target ~type_aliases m)) l
  in
  let body = format_module_bodies bodies in
  let x = format_all (head @ body) in
  Easy_format.Pretty.to_string x


let get_full_type_name x =
  let s = x.def_name in
  match x.def_param with
      [] -> s
    | [x] -> sprintf "'%s %s" x s
    | l ->
        let l = List.map (fun s -> "'" ^ s) l in
        sprintf "(%s) %s" (String.concat ", " l) s


let unwrap_option deref x =
  match deref x with
      `Option (_, x, _, _)
    | `Nullable (_, x, _, _) -> x
    | `Name (loc, s, _, _, _) ->
	Ag_error.error loc ("Not an option type: " ^ s)
    | x ->
        Ag_error.error (loc_of_mapping x) "Not an option type"



let get_implicit_ocaml_default deref x =
  match deref x with
      `Unit (loc, `Unit, _) -> Some "()"
    | `Bool (loc, `Bool, _) -> Some "false"
    | `Int (loc, `Int o, _) ->
	Some (match o with
		  `Int -> "0"
		| `Char -> "'\000'"
		| `Int32 -> "0l"
		| `Int64 -> "0L"
                | `Float -> "0.")
    | `Float (loc, `Float, _) -> Some "0.0"
    | `String (loc, `String, _) -> Some "\"\""
    | `List (loc, x, `List `List, _) -> Some "[]"
    | `List (loc, x, `List `Array, _) -> Some "[||]"
    | `Option (loc, x, `Option, _) -> Some "None"
    | `Nullable (loc, x, `Nullable, _) -> Some "None"
    | _ -> None


let map_record_creator_field deref x =
  let o =
    match x.f_arepr with
        `Field o -> o
      | _ -> assert false
  in
  let fname = o.ocaml_fname in
  let impl2 = sprintf "\n    %s = %s;" fname fname in
  match x.f_kind with
      `Required ->
        let t = ocaml_of_expr (ocaml_of_expr_mapping x.f_value) in
        let intf = sprintf "\n  %s: %s ->" fname t in
        let impl1 = sprintf "\n  ~%s" fname in
        intf, impl1, impl2

    | `Optional ->
        let x = unwrap_option deref x.f_value in
        let t = ocaml_of_expr (ocaml_of_expr_mapping x) in
        let intf = sprintf "\n  ?%s: %s ->" fname t in
        let impl1 = sprintf "\n  ?%s" fname in
        intf, impl1, impl2

    | `With_default ->
        let t = ocaml_of_expr (ocaml_of_expr_mapping x.f_value) in
        let intf = sprintf "\n  ?%s: %s ->" fname t in
        let impl1 =
          let default =
            match o.ocaml_default with
                None ->
                  (match get_implicit_ocaml_default deref x.f_value with
                       None ->
                         Ag_error.error x.f_loc "Missing default field value"
                     | Some s -> s
                  )
              | Some s -> s
          in
          sprintf "\n  ?(%s = %s)" fname default
        in
        intf, impl1, impl2


let make_record_creator deref x =
  match x.def_value with
      Some (`Record (loc, a, `Record `Record, _)) ->
        let s = x.def_name in
        let full_name = get_full_type_name x in
        let l = Array.to_list (Array.map (map_record_creator_field deref) a) in
        let intf_params = List.map (fun (x, _, _) -> x) l in
        let intf =
          sprintf "\
val create_%s :%s
  unit -> %s
  (** Create a record of type {!%s}. *)

"
            s (String.concat "" intf_params)
            full_name
            s
        in
        let impl_params = List.map (fun (_, x, _) -> x) l in
        let impl_fields = List.map (fun (_, _, x) -> x) l in
        let impl =
          sprintf "\
let create_%s %s
  () =
  {%s
  }
"
            s (String.concat "" impl_params)
            (String.concat "" impl_fields)
        in
        intf, impl

    | _ -> "", ""
