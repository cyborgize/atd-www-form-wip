(*
  OCaml code generator for the biniou format.
*)


open Printf

open Atd_ast
open Ag_error
open Ag_mapping
open Ag_ob_mapping
open Ag_ob_spe

(*
  OCaml code generator (biniou readers and writers)
*)

let name_of_var s = "_" ^ s


let make_ocaml_biniou_intf ~with_create buf deref defs =
  List.iter (
    fun x ->
      let s = x.def_name in
      if s <> "" && s.[0] <> '_' && x.def_value <> None then (
        let full_name = Ag_ocaml.get_full_type_name x in
        let writer_params =
          String.concat "" (
            List.map
              (fun s ->
                 sprintf "\n  Bi_io.node_tag ->\
                          \n  (Bi_outbuf.t -> '%s -> unit) ->\
                          \n  (Bi_outbuf.t -> '%s -> unit) ->" s s)
              x.def_param
          )
        in
        let reader_params =
          String.concat "" (
            List.map (
              fun s ->
                sprintf
                  "\n  (Bi_io.node_tag -> (Bi_inbuf.t -> '%s)) ->\
                   \n  (Bi_inbuf.t -> '%s) ->" s s
            )
              x.def_param
          )
        in
	bprintf buf "(* Writers for type %s *)\n\n" s;

	bprintf buf "\
val %s_tag : Bi_io.node_tag
  (** Tag used by the writers for type {!%s}.
      Readers may support more than just this tag. *)

"
          s
          s;

	bprintf buf "\
val write_untagged_%s :%s
  Bi_outbuf.t -> %s -> unit
  (** Output an untagged biniou value of type {!%s}. *)

"
          s writer_params
          full_name
          s;

	bprintf buf "\
val write_%s :%s
  Bi_outbuf.t -> %s -> unit
  (** Output a biniou value of type {!%s}. *)

"
          s writer_params
          full_name
          s;

	bprintf buf "\
val string_of_%s :%s
  ?len:int -> %s -> string
  (** Serialize a value of type {!%s} into
      a biniou string. *)

"
          s writer_params
          full_name
          s;

	bprintf buf "(* Readers for type %s *)\n\n" s;

	bprintf buf "\
val get_%s_reader :%s
  Bi_io.node_tag -> (Bi_inbuf.t -> %s)
  (** Return a function that reads an untagged
      biniou value of type {!%s}. *)

"
          s reader_params
          full_name
          s;

	bprintf buf "\
val read_%s :%s
  Bi_inbuf.t -> %s
  (** Input a tagged biniou value of type {!%s}. *)

"
          s reader_params
          full_name
          s;

	bprintf buf "\
val %s_of_string :%s
  ?pos:int -> string -> %s
  (** Deserialize a biniou value of type {!%s}.
      @param pos specifies the position where
                 reading starts. Default: 0. *)

"
          s reader_params
          full_name
          s;

        if with_create then
          let create_record_intf, create_record_impl =
            Ag_ocaml.make_record_creator deref x
          in
          bprintf buf "%s" create_record_intf;
          bprintf buf "\n";
      )
  ) (flatten defs)


let rec get_biniou_tag (x : ob_mapping) =
  match x with
      `Unit (loc, `Unit, `Unit) -> "Bi_io.unit_tag"
    | `Bool (loc, `Bool, `Bool) -> "Bi_io.bool_tag"
    | `Int (loc, `Int o, `Int b) ->
	(match b with
	     `Uvint -> "Bi_io.uvint_tag"
	   | `Svint -> "Bi_io.svint_tag"
	   | `Int8 -> "Bi_io.int8_tag"
	   | `Int16 -> "Bi_io.int16_tag"
	   | `Int32 -> "Bi_io.int32_tag"
	   | `Int64 -> "Bi_io.int64_tag"
	)
    | `Float (loc, `Float, `Float b) ->
        (match b with
            `Float32 -> "Bi_io.float32_tag"
          | `Float64 -> "Bi_io.float64_tag"
        )
    | `String (loc, `String, `String) -> "Bi_io.string_tag"
    | `Sum (loc, a, `Sum x, `Sum) -> "Bi_io.variant_tag"
    | `Record (loc, a, `Record o, `Record) -> "Bi_io.record_tag"
    | `Tuple (loc, a, `Tuple, `Tuple) -> "Bi_io.tuple_tag"
    | `List (loc, x, `List o, `List b) ->
	(match b with
	     `Array -> "Bi_io.array_tag"
	   | `Table -> "Bi_io.table_tag"
	)
    | `Option (loc, x, `Option, `Option)
    | `Nullable (loc, x, `Nullable, `Nullable) -> "Bi_io.num_variant_tag"
    | `Shared (loc, id, x, `Shared _, `Shared) -> "Bi_io.shared_tag"
    | `Wrap (loc, x, `Wrap _, `Wrap) -> get_biniou_tag x

    | `Name (loc, s, args, None, None) -> sprintf "%s_tag" s
    | `External (loc, s, args,
                 `External (types_module, main_module, ext_name),
                 `External) ->
        sprintf "%s.%s_tag" main_module ext_name
    | `Tvar (loc, s) -> sprintf "%s_tag" (name_of_var s)
    | _ -> assert false

let nth name i len =
  let l =
    Array.to_list (Array.init len (fun j -> if i = j then name else "_")) in
  String.concat ", " l


let get_fields deref a =
  List.map (
    fun x ->
      let ocaml_fname, ocaml_default, optional, unwrapped =
	match x.f_arepr, x.f_brepr with
	    `Field o, `Field b ->
	      let ocaml_default =
		match x.f_kind with
		    `With_default ->
		      (match o.Ag_ocaml.ocaml_default with
			   None ->
			     let d =
			       Ag_ocaml.get_implicit_ocaml_default
                                 deref x.f_value in
			     if d = None then
			       error x.f_loc "Missing default field value"
			     else
			       d
			 | Some _ as default -> default
		      )
		  | `Optional -> Some "None"
		  | `Required -> None
	      in
	      let optional =
		match x.f_kind with
		    `Optional | `With_default -> true
		  | `Required -> false
	      in
	      o.Ag_ocaml.ocaml_fname,
	      ocaml_default,
	      optional,
	      b.Ag_biniou.biniou_unwrapped
	  | _ -> assert false
      in
      (x, ocaml_fname, ocaml_default, optional, unwrapped)
  )
    (Array.to_list a)


let unopt = function None -> assert false | Some x -> x

let rec get_writer_name
    ?(paren = false)
    ?name_f
    ~tagged
    (x : ob_mapping) : string =

  let name_f =
    match name_f with
        Some f -> f
      | None ->
          if tagged then
            (fun s -> "write_" ^ s)
          else
            (fun s -> "write_untagged_" ^ s)
  in

  let un = if tagged then "" else "untagged_" in
  match x with
      `Unit (loc, `Unit, `Unit) ->
	sprintf "Bi_io.write_%sunit" un
    | `Bool (loc, `Bool, `Bool) ->
	sprintf "Bi_io.write_%sbool" un
    | `Int (loc, `Int o, `Int b) ->
	(match o, b with
	     `Int, `Uvint -> sprintf "Bi_io.write_%suvint" un
	   | `Int, `Svint -> sprintf "Bi_io.write_%ssvint" un
	   | `Char, `Int8 -> sprintf "Bi_io.write_%schar" un
	   | `Int, `Int8 -> sprintf "Bi_io.write_%sint8" un
	   | `Int, `Int16 -> sprintf "Bi_io.write_%sint16" un
	   | `Int32, `Int32 -> sprintf "Bi_io.write_%sint32" un
	   | `Int64, `Int64 -> sprintf "Bi_io.write_%sint64" un
	   | _ ->
	       error loc "Unsupported combination of OCaml/Biniou int types"
	)

    | `Float (loc, `Float, `Float b) ->
        (match b with
            `Float32 -> sprintf "Bi_io.write_%sfloat32" un
          | `Float64 -> sprintf "Bi_io.write_%sfloat64" un
        )
    | `String (loc, `String, `String) ->
	sprintf "Bi_io.write_%sstring" un

    | `Tvar (loc, s) ->
        sprintf "write_%s%s" un (name_of_var s)

    | `Name (loc, s, args, None, None) ->
        let l = List.map get_writer_names args in
        let s = String.concat " " (name_f s :: l) in
        if paren && l <> [] then "(" ^ s ^ ")"
        else s

    | `External (loc, s, args,
                 `External (types_module, main_module, ext_name),
                 `External) ->
        let f = main_module ^ "." ^ name_f ext_name in
        let l = List.map get_writer_names args in
        let s = String.concat " " (f :: l) in
        if paren && l <> [] then "(" ^ s ^ ")"
        else s

    | _ -> assert false

and get_writer_names x =
  let tag = get_biniou_tag x in
  let write_untagged = get_writer_name ~paren:true ~tagged:false x in
  let write = get_writer_name ~paren:true ~tagged:true x in
  String.concat " " [ tag; write_untagged; write ]


let get_left_writer_name ~tagged name param =
  let args = List.map (fun s -> `Tvar (dummy_loc, s)) param in
  get_writer_name ~tagged
    (`Name (dummy_loc, name, args, None, None))

let get_left_to_string_name name param =
  let name_f s = "string_of_" ^ s in
  let args = List.map (fun s -> `Tvar (dummy_loc, s)) param in
  get_writer_name ~tagged:true ~name_f
    (`Name (dummy_loc, name, args, None, None))

(*
let make_writer_name tagged loc name args =
  let un = if tagged then "" else "untagged_" in
  let f = sprintf "write_%s%s" un name in
  let l =
    List.map (
      function
          `Tvar (loc, s) ->
            let name = name_of_var s in
            (* TODO (incomplete) *)
            [ sprintf "%s_tag" name;
              sprintf "write_%s" name ]
        | _ -> assert false
    ) args
  in
  String.concat " " (f :: List.flatten l)
*)

let rec get_reader_name
    ?(paren = false)
    ?name_f
    ~tagged
    (x : ob_mapping) : string =

  let name_f =
    match name_f with
        Some f -> f
      | None ->
          if tagged then
            (fun s -> "read_" ^ s)
          else
            (fun s -> sprintf "get_%s_reader" s)
  in

  let xreader s =
    if tagged then
      sprintf "Ag_ob_run.read_%s" s
    else
      sprintf "Ag_ob_run.get_%s_reader" s
  in
  match x with
      `Unit (loc, `Unit, `Unit) -> xreader "unit"

    | `Bool (loc, `Bool, `Bool) -> xreader "bool"

    | `Int (loc, `Int o, `Int b) ->
	(match o, b with
	     `Int, `Uvint
	   | `Int, `Svint
	   | `Int, `Int8
	   | `Int, `Int16 -> xreader "int"
	   | `Char, `Int8 -> xreader "char"
	   | `Int32, `Int32 -> xreader "int32"
	   | `Int64, `Int64 -> xreader "int64"
	   | _ ->
	       error loc "Unsupported combination of OCaml/Biniou int types"
	)

    | `Float (loc, `Float, `Float b) ->
        (match b with
            `Float32 -> xreader "float32"
          | `Float64 -> xreader "float64"
        )

    | `String (loc, `String, `String) -> xreader "string"

    | `Tvar (loc, s) ->
        let name = name_of_var s in
        if tagged then
          sprintf "read_%s" name
        else
          sprintf "get_%s_reader" name

    | `Name (loc, s, args, None, None) ->
        let l = List.map get_reader_names args in
        let s = String.concat " " (name_f s :: l) in
        if paren && l <> [] then "(" ^ s ^ ")"
        else s

    | `External (loc, s, args,
                 `External (types_module, main_module, ext_name),
                 `External) ->
        let f = main_module ^ "." ^ name_f ext_name in
        let l = List.map get_reader_names args in
        let s = String.concat " " (f :: l) in
        if paren && l <> [] then "(" ^ s ^ ")"
        else s

    | _ -> assert false

and get_reader_names x =
  let get_reader = get_reader_name ~paren:true ~tagged:false x in
  let reader = get_reader_name ~paren:true ~tagged:true x in
  String.concat " " [ get_reader; reader ]


let get_left_reader_name ~tagged name param =
  let args = List.map (fun s -> `Tvar (dummy_loc, s)) param in
  get_reader_name ~tagged (`Name (dummy_loc, name, args, None, None))

let get_left_of_string_name name param =
  let name_f s = s ^ "_of_string" in
  let args = List.map (fun s -> `Tvar (dummy_loc, s)) param in
  get_reader_name ~name_f ~tagged:true
    (`Name (dummy_loc, name, args, None, None))

(*
let make_reader_name loc name args =
  let f = sprintf "read_%s" name in
  let l =
    List.map (
      function
          `Tvar (loc, s) -> sprintf "read_%s" (name_of_var s)
        | _ -> assert false
    ) args
  in
  String.concat " " (f :: l)
*)



let rec make_writer ~tagged deref (x : ob_mapping) : Ag_indent.t list =
  let un = if tagged then "" else "untagged_" in
  match x with
      `Unit _
    | `Bool _
    | `Int _
    | `Float _
    | `String _
    | `Name _
    | `External _
    | `Tvar _ -> [ `Line (get_writer_name ~tagged x) ]

    | `Sum (loc, a, `Sum x, `Sum) ->
	let tick =
	  match x with
	      `Classic -> ""
	    | `Poly -> "`"
	in
	let match_ =
	  [
            `Line "match x with";
            `Block (
              Array.to_list (
		Array.map
		  (fun x -> `Inline (make_variant_writer deref tick x))
		  a
	      )
	    )
	  ]
	in
	let body =
	  if tagged then
	    `Line "Bi_io.write_tag ob Bi_io.variant_tag;" :: match_
	  else
	    match_
	in
	[
          `Annot ("fun", `Line "fun ob x ->");
          `Block body;
        ]

    | `Record (loc, a, `Record o, `Record) ->
	let body = make_record_writer deref tagged a o in
	[
          `Annot ("fun", `Line "fun ob x ->");
          `Block body;
        ]

    | `Tuple (loc, a, `Tuple, `Tuple) ->
	let main =
	  let len = Array.length a in
	  let a =
	    Array.mapi (
	      fun i x ->
		[
                  `Line "(";
                  `Block [
		    `Line (sprintf "let %s = x in (" (nth "x" i len));
                    `Block (make_writer ~tagged:true deref x.cel_value);
		    `Line ") ob x";
                  ];
		  `Line ");"
		]
	    ) a
	  in
	  [
            `Line (sprintf "Bi_vint.write_uvint ob %i;" len);
	    `Inline (List.flatten (Array.to_list a))
          ]
	in
	let body =
	  if tagged then
	    `Line "Bi_io.write_tag ob Bi_io.tuple_tag;" :: main
	  else
	    main
	in
	[
          `Annot ("fun", `Line "fun ob x ->");
          `Block body;
        ]

    | `List (loc, x, `List o, `List b) ->
	(match o, b with
	     `List, `Array ->
	       let tag = get_biniou_tag x in
	       [
                 `Line (sprintf "Ag_ob_run.write_%slist" un);
                 `Block [
		   `Line tag;
                   `Line "(";
                   `Block (make_writer ~tagged:false deref x);
                   `Line ")";
                 ]
               ]
	   | `Array, `Array ->
	       let tag = get_biniou_tag x in
               [
	         `Line (sprintf "Ag_ob_run.write_%sarray" un);
                 `Block [
		   `Line tag;
                   `Line "(";
                   `Block (make_writer ~tagged deref x);
                   `Line ")";
                 ]
               ]
	   | list_kind, `Table ->
	       let body = make_table_writer deref tagged list_kind x in
	       [
                 `Annot ("fun", `Line "fun ob x ->");
                 `Block body;
               ]
	)

    | `Option (loc, x, `Option, `Option)
    | `Nullable (loc, x, `Nullable, `Nullable) ->
	[
          `Line (sprintf "Ag_ob_run.write_%soption (" un);
	  `Block (make_writer ~tagged:true deref x);
          `Line ")";
        ]

    | `Shared (loc, id, x, `Shared kind, `Shared) ->
        let suffix =
          match kind with
              `Flat -> ""
            | `Ref -> "_ref"
        in
	[
          `Line (sprintf "Ag_ob_run.write_%sshared%s shared%s (" un suffix id);
	  `Block (make_writer ~tagged:true deref x);
          `Line ")";
        ]

    | `Wrap (loc, x, `Wrap o, `Wrap) ->
        let simple_writer = make_writer ~tagged deref x in
        (match o with
            None -> simple_writer
          | Some { Ag_ocaml.ocaml_wrap_t; ocaml_wrap; ocaml_unwrap } ->
              [
                `Line "fun ob x -> (";
                `Block [
                  `Line (sprintf "let x = ( %s ) x in (" ocaml_unwrap);
                  `Block simple_writer;
                  `Line ") ob x)";
                ]
              ]
        )

    | _ -> assert false



and make_variant_writer deref tick x : Ag_indent.t list =
  let o =
    match x.var_arepr, x.var_brepr with
	`Variant o, `Variant -> o
      | _ -> assert false
  in
  let ocaml_cons = o.Ag_ocaml.ocaml_cons in
  match x.var_arg with
      None ->
	let h = Bi_io.string_of_hashtag (Bi_io.hash_name x.var_cons) false in
	[ `Line (sprintf "| %s%s -> Bi_outbuf.add_char4 ob %C %C %C %C"
		   tick ocaml_cons
		   h.[0] h.[1] h.[2] h.[3]) ]
    | Some v ->
	let h = Bi_io.string_of_hashtag (Bi_io.hash_name x.var_cons) true in
	[
          `Line (sprintf "| %s%s x ->" tick ocaml_cons);
          `Block [
	    `Line (sprintf "Bi_outbuf.add_char4 ob %C %C %C %C;"
		     h.[0] h.[1] h.[2] h.[3]);
	    `Line "(";
            `Block (make_writer ~tagged:true deref v);
	    `Line ") ob x"
	  ]
        ]

and make_record_writer deref tagged a record_kind =
  let dot =
    match record_kind with
	`Record -> "."
      | `Object -> "#"
  in
  let fields = get_fields deref a in
  let write_length =
    (* count the number of defined optional fields in order
       to determine the length of the record *)
    let min_len =
      List.fold_left
	(fun n (_, _, _, opt, _) -> if opt then n else n + 1) 0 fields
    in
    let max_len = List.length fields in
    if min_len = max_len then
      [ `Line (sprintf "Bi_vint.write_uvint ob %i;" max_len) ]
    else
      [
        (* Using a ref because many "let len = ... len + 1 in"
           cause ocamlopt to take a very long time to finish *)
	`Line (sprintf "let len = ref %i in" min_len);
	`Inline (
	  List.fold_right (
	    fun (x, ocaml_fname, default, opt, unwrap) l ->
	      if opt then
		let getfield =
		  sprintf "let x_%s = x%s%s in" ocaml_fname dot ocaml_fname in
		let setlen =
		  sprintf "if x_%s != %s then incr len;"
		    ocaml_fname (unopt default)
		in
		`Line getfield :: `Line setlen :: l
	      else l
	  ) fields []
	);
	`Line "Bi_vint.write_uvint ob !len;"
      ]
  in

  let write_fields =
    List.map (
      fun (x, ocaml_fname, ocaml_default, optional, unwrapped) ->
	let f_value =
	  if unwrapped then Ag_ocaml.unwrap_option deref x.f_value
	  else x.f_value
	in
	let write_field_tag =
	  let s = Bi_io.string_of_hashtag (Bi_io.hash_name x.f_name) true in
	  sprintf "Bi_outbuf.add_char4 ob %C %C %C %C;"
	    s.[0] s.[1] s.[2] s.[3]
	in
	let app v =
	  [
	    `Line write_field_tag;
            `Line "(";
	    `Block (make_writer ~tagged:true deref f_value);
	    `Line (sprintf ") ob %s;" v);
	  ]
	in
	let v =
	  if optional then
	    sprintf "x_%s" ocaml_fname
	  else
	    sprintf "x%s%s" dot ocaml_fname
	in
	if unwrapped then
	  [
	    `Line (sprintf "(match %s with None -> () | Some x ->" v);
	    `Block (app "x");
	    `Line ");"
	  ]
	else if optional then
	  [
	    `Line (sprintf "if %s != %s then (" v (unopt ocaml_default));
	    `Block (app v);
	    `Line ");"
	  ]
	else
	  app v
    ) fields
  in

  let main = write_length @ List.flatten write_fields in

  if tagged then
    `Line "Bi_io.write_tag ob Bi_io.record_tag;" :: main
  else
    main



and make_table_writer deref tagged list_kind x =
  let a, record_kind =
    match deref x with
	`Record (_, a, `Record record_kind, `Record) -> a, record_kind
      | _ ->
	  error (loc_of_mapping x) "Not a record type"
  in
  let dot =
    match record_kind with
	`Record -> "."
      | `Object -> "#"
  in
  let let_len =
    match list_kind with
	`List -> `Line "let len = List.length x in"
      | `Array -> `Line "let len = Array.length x in"
  in
  let iter2 =
    match list_kind with
	`List -> "Ag_ob_run.list_iter2"
      | `Array -> "Ag_ob_run.array_iter2"
  in
  let l = Array.to_list a in
  let write_header =
    `Line (sprintf "Bi_vint.write_uvint ob %i;" (Array.length a)) ::
    List.flatten (
      List.map (
	fun x ->
	  [ `Line (sprintf "Bi_io.write_hashtag ob (%i) true;"
		     (Bi_io.hash_name x.f_name));
	    `Line (sprintf "Bi_io.write_tag ob %s;"
		     (get_biniou_tag x.f_value)) ]
      ) l
    )
  in
  let write_record =
    List.flatten (
      List.map (
	fun x ->
	  [ `Line "(";
	    `Block (make_writer ~tagged:false deref x.f_value);
	    `Line ")";
	    `Block [ `Line (sprintf "ob x%s%s;" dot x.f_name) ] ]
      ) l
    )
  in
  let write_items =
    [ `Line (iter2 ^ " (fun ob x ->");
      `Block write_record;
      `Line ") ob x;" ]
  in
  let main =
    [
      let_len;
      `Line "Bi_vint.write_uvint ob len;";
      `Line "if len > 0 then (";
      `Block (write_header @ write_items);
      `Line ");"
    ]
  in
  if tagged then
    `Line "Bi_io.write_tag ob Bi_io.table_tag;" :: main
  else
    main


let study_record deref fields =
  let maybe_constant =
    List.for_all (function (_, _, Some _, _, _) -> true | _ -> false) fields
  in
  let _, init_fields =
    List.fold_right (
      fun (x, name, default, opt, unwrap) (maybe_constant, l) ->
	let maybe_constant, v =
	  match default with
	      None ->
		assert (not opt);
		(*
		  The initial value is a float because the record may be
		  represented as a double_array (unboxed floats).
		  Float values work in all cases.
		*)
		let v = "Obj.magic 0.0" in
		maybe_constant, v
	    | Some s ->
		false, (if maybe_constant then sprintf "(fun x -> x) (%s)" s
			else s)
	in
	(maybe_constant, `Line (sprintf "%s = %s;" name v) :: l)
    ) fields (maybe_constant, [])
  in
  let n, mapping =
    List.fold_left (
      fun (i, acc) (x, name, default, opt, unwrap) ->
	if not opt then
	  (i+1, (Some i :: acc))
	else
	  (i, (None :: acc))
    ) (0, []) fields
  in
  let mapping = Array.of_list (List.rev mapping) in

  let init_val = [ `Line "{"; `Block init_fields; `Line "}" ] in

  let k = n / 31 + (if n mod 31 > 0 then 1 else 0) in
  let init_bits =
    Array.to_list (
      Array.init k (
	fun i -> `Line (sprintf "let bits%i = ref 0 in" i)
      )
    )
  in
  let final_bits = Array.make k 0 in
  for z0 = 0 to List.length fields - 1 do
    match mapping.(z0) with
	None -> ()
      | Some z ->
	  let i = z / 31 in
	  let j = z mod 31 in
	  final_bits.(i) <- final_bits.(i) lor (1 lsl j);
  done;
  let set_bit z0 =
    match mapping.(z0) with
	None -> []
      | Some z ->
	  let i = z / 31 in
	  let j = z mod 31 in
	  [ `Line (sprintf "bits%i := !bits%i lor 0x%x;" i i (1 lsl j)) ]
  in
  let check_bits =
    let bool_expr =
      String.concat " || " (
	Array.to_list (
	  Array.mapi (
	    fun i x -> sprintf "!bits%i <> 0x%x" i x
	  ) final_bits
	)
      )
    in
    let bit_fields =
      let a = Array.init k (fun i -> sprintf "!bits%i" i) in
      sprintf "[| %s |]" (String.concat "; " (Array.to_list a))
    in
    let field_names =
      let l =
	List.fold_right (
	  fun (x, name, default, opt, unwrap) acc ->
	    if not opt then
	      sprintf "%S" x.f_name :: acc
	    else
	      acc
	) fields []
      in
      sprintf "[| %s |]" (String.concat "; " l)
    in
    if k = 0 then []
    else
      [ `Line (sprintf "if %s then Ag_ob_run.missing_fields %s %s;"
		 bool_expr bit_fields field_names) ]
  in
  init_val, init_bits, set_bit, check_bits


let wrap_body ~tagged expected_tag body =
  if tagged then
    [
      `Annot ("fun", `Line "fun ib ->");
      `Block [
	`Line (sprintf "if Bi_io.read_tag ib <> %i then \
                        Ag_ob_run.read_error_at ib;"
		 expected_tag);
	`Inline body;
      ]
    ]
  else
    [
      `Annot ("fun", `Line "fun tag ->");
      `Block [
	`Line (sprintf "if tag <> %i then \
                          Ag_ob_run.read_error () else"
		 expected_tag);
        `Block [
	  `Line "fun ib ->";
          `Block body;
        ]
      ]
    ]

let wrap_bodies ~tagged l =
  if tagged then
    let cases =
      List.map (
	fun (expected_tag, body) ->
	  `Inline [
	    `Line (sprintf "| %i -> " expected_tag);
	    `Block body;
	  ]
      ) l
    in
    [
      `Line "fun ib ->";
      `Block [
	`Line "match Bi_io.read_tag ib with";
	`Block [
	  `Inline cases;
	  `Line "| _ -> Ag_ob_run.read_error_at ib"
	]
      ]
    ]
  else
    let cases =
      List.map (
	fun (expected_tag, body) ->
	  `Inline [
	    `Line (sprintf "| %i -> " expected_tag);
	    `Block [
	      `Line "(fun ib ->";
	      `Block body;
	      `Line ")";
	    ]
	  ]
      ) l
    in
    [
      `Line "function";
      `Block [
	`Inline cases;
	`Line "| _ -> Ag_ob_run.read_error ()"
      ]
    ]


let rec make_reader
    deref ~tagged ?type_annot (x : ob_mapping)
    : Ag_indent.t list =
  match x with
      `Unit _
    | `Bool _
    | `Int _
    | `Float _
    | `String _
    | `Name _
    | `External _
    | `Tvar _ -> [ `Line (get_reader_name ~tagged x) ]

    | `Sum (loc, a, `Sum x, `Sum) ->
	let tick =
	  match x with
	      `Classic -> ""
	    | `Poly -> "`"
	in
	let body =
	  [
	    `Line "Bi_io.read_hashtag ib (fun ib h has_arg ->";
	    `Block [
	      `Line "match h, has_arg with";
              `Block [
		`Inline (
                  Array.to_list (
		    Array.map
		      (fun x ->
                        `Inline (make_variant_reader deref tick ?type_annot x)
                      )
		      a
                  )
		);
                `Line "| _ -> Ag_ob_run.unsupported_variant h has_arg";
              ]
	    ];
	    `Line ")"
	  ]
	in
	wrap_body ~tagged Bi_io.variant_tag body

    | `Record (loc, a, `Record o, `Record) ->
	(match o with
	     `Record -> ()
	   | `Object ->
	       error loc "Sorry, OCaml objects are not supported"
	);
	let body = make_record_reader deref ~tagged ?type_annot a o in
	wrap_body ~tagged Bi_io.record_tag body

    | `Tuple (loc, a, `Tuple, `Tuple) ->
	let body = make_tuple_reader deref ~tagged a in
	wrap_body ~tagged Bi_io.tuple_tag body

    | `List (loc, x, `List o, `List b) ->
	(match o, b with
	     `List, `Array ->
	       let f =
		 if tagged then "Ag_ob_run.read_list"
                 else "Ag_ob_run.get_list_reader"
	       in
	       [
                 `Line (f ^ " (");
                 `Block (make_reader deref ~tagged:false x);
                 `Line ")";
	       ]
	   | `Array, `Array ->
	       let f =
                 if tagged then "Ag_ob_run.read_array"
                 else "Ag_ob_run.get_array_reader"
	       in
	       [
                 `Line (f ^ " (");
                 `Block (make_reader deref ~tagged:false x);
                 `Line ")";
	       ]
	   | list_kind, `Table ->
	       (* Support table format and regular array format *)
	       let body1 = make_table_reader deref loc list_kind x in
	       let body2 =
		 let f =
		   match list_kind with
		       `List -> "Ag_ob_run.read_list_value"
		     | `Array -> "Ag_ob_run.read_array_value"
		 in
		 [
		   `Line (f ^ " (");
		   `Block (make_reader deref ~tagged:false x);
		   `Line ") ib";
		 ]
	       in
	       wrap_bodies ~tagged [ Bi_io.table_tag, body1;
				     Bi_io.array_tag, body2 ]
	)

    | `Option (loc, x, `Option, `Option)
    | `Nullable (loc, x, `Nullable, `Nullable) ->
	let body = [
	  `Line "match Char.code (Bi_inbuf.read_char ib) with";
	  `Block [
	    `Line "| 0 -> None";
	    `Line "| 0x80 ->";
	    `Block [
	      `Line "Some (";
	      `Block [
		`Line "(";
		`Block (make_reader deref ~tagged:true x);
		`Line ")";
		 `Block [ `Line "ib"];
	      ];
	      `Line ")"
	    ];
	    `Line "| _ -> Ag_ob_run.read_error_at ib";
	  ]
	]
	in
	wrap_body ~tagged Bi_io.num_variant_tag body

    | `Shared (loc, id, x, `Shared kind, `Shared) ->
        let body =
          match kind with
              `Flat ->
                (match deref x with
                     `Record (loc, a, `Record o, `Record) ->
                       (match o with
	                    `Record -> ()
	                  | `Object ->
	                      error loc "OCaml objects are not supported"
	               );
	               make_record_reader
                         ~shared_id:id deref ~tagged ?type_annot a o

                   | _ ->
                       error loc "Only record types can use sharing \
                                  (or use <ocaml repr=\"ref\">)"
                )
            | `Ref ->
	        let read_value = make_reader deref ~tagged:true x in
	        [
                  `Line (sprintf "Ag_ob_run.read_shared shared%s (" id);
                  `Block read_value;
                  `Line ") ib";
                ]
        in
        wrap_body ~tagged Bi_io.shared_tag body

    | `Wrap (loc, x, `Wrap o, `Wrap) ->
        let simple_reader = make_reader deref ~tagged x in
        (match o with
            None -> simple_reader
          | Some { Ag_ocaml.ocaml_wrap } ->
              if tagged then
                [
                  `Line "fun ib ->";
                  `Block [
                    `Line (sprintf "( %s ) ((" ocaml_wrap);
                    `Block simple_reader;
                    `Line ") ib)";
                  ]
                ]
              else
                [
                  `Line "fun tag ib ->";
                  `Block [
                    `Line (sprintf "( %s ) ((" ocaml_wrap);
                    `Block simple_reader;
                    `Line ") tag ib)";
                  ]
                ]
        )
    | _ -> assert false


and make_variant_reader deref tick ?(type_annot = "") x : Ag_indent.t list =
  let o =
    match x.var_arepr, x.var_brepr with
	`Variant o, `Variant -> o
      | _ -> assert false
  in
  let ocaml_cons = o.Ag_ocaml.ocaml_cons in
  match x.var_arg with
      None ->
	let h = Bi_io.hash_name x.var_cons in
        let typed_cons = sprintf "(%s%s%s)" tick ocaml_cons type_annot in
	[ `Line (sprintf "| %i, false -> %s" h typed_cons) ]
    | Some v ->
	let h = Bi_io.hash_name x.var_cons in
	[
          `Line (sprintf "| %i, true -> (%s%s (" h tick ocaml_cons);
          `Block [
            `Block [
              `Line "(";
	      `Block (make_reader deref ~tagged:true v);
	      `Line ") ib";
	    ];
            `Line (sprintf ")%s)" type_annot);
	  ];
        ]

and make_record_reader
    ?shared_id deref ~tagged ?(type_annot = "")
    a record_kind =
  let fields = get_fields deref a in
  let init_val, init_bits, set_bit, check_bits = study_record deref fields in

  let build share body =
    [
      `Line (sprintf "let x%s =" type_annot);
      `Block init_val;
      `Line "in";
      `Inline share;
      `Inline init_bits;
      `Line "let len = Bi_vint.read_uvint ib in";
      `Line "for i = 1 to len do";
      `Block body;
      `Line "done;";
      `Inline check_bits;
      `Line "Ag_ob_run.identity x"
    ]
  in

  let loop body =
    match shared_id with
        None -> build [] body
      | Some id ->
          let share = [
            `Line (sprintf "if Bi_io.read_tag ib <> %i then \
                              Ag_ob_run.read_error_at ib;"
		     Bi_io.record_tag);
            `Line (sprintf "Bi_share.Rd.put ib.Bi_inbuf.i_shared \
                              (pos, shared%s) (Obj.repr x);" id);
          ]
          in
          [
            `Line "let pos = ib.Bi_inbuf.i_offs + ib.Bi_inbuf.i_pos in";
            `Line "let offset = Bi_vint.read_uvint ib in";
            `Line "if offset = 0 then";
            `Block (build share body);
            `Line "else";
            `Block [
              `Line (sprintf "Obj.obj (Bi_share.Rd.get ib.Bi_inbuf.i_shared \
                                        (pos - offset, shared%s))" id)
            ]
          ]
  in
  let body =
    let a = Array.of_list fields in
    let cases =
      Array.mapi (
	fun i (x, name, _, opt, unwrapped) ->
	  let f_value =
	    if unwrapped then Ag_ocaml.unwrap_option deref x.f_value
	    else x.f_value
	  in
	  let wrap l =
	    if unwrapped then
	      [
		`Line "Some (";
		`Block l;
		`Line ")"
	      ]
	    else l
	  in
	  let read_value =
	    [
	      `Line "(";
	      `Block (make_reader deref ~tagged:true f_value);
	      `Line ") ib"
	    ]
	  in
	  `Inline [
            `Line (sprintf "| %i ->" (Bi_io.hash_name x.f_name));
            `Block [
	      `Line "let v =";
	      `Block (wrap read_value);
	      `Line "in";
	      `Line (sprintf "Obj.set_field (Obj.repr x) %i (Obj.repr v);" i);
	      `Inline (set_bit i);
	    ];
          ]
      ) a
    in
    [
      `Line "match Bi_io.read_field_hashtag ib with";
      `Block [
        `Inline (Array.to_list cases);
        `Line "| _ -> Bi_io.skip ib";
      ]
    ]
  in

  loop body

and make_tuple_reader deref ~tagged a =
  let cells =
    Array.map (
      fun x ->
	match x.cel_arepr with
	    `Cell f -> x, f.Ag_ocaml.ocaml_default
	  | _ -> assert false
    ) a
  in
  let min_length =
    let n = ref (Array.length cells) in
    (try
       for i = Array.length cells - 1 downto 0 do
	 let x, default = cells.(i) in
	 if default = None then (
	   n := i + 1;
	   raise Exit
	 )
       done
     with Exit -> ());
    !n
  in
  let tup_len = Array.length a in

  let read_cells =
    List.flatten (
      Array.to_list (
	Array.mapi (
	  fun i (x, default) ->
	    let read_value = make_reader deref ~tagged:true x.cel_value in
	    let get_value =
	      if i < min_length then
                [
                  `Line "(";
                  `Block read_value;
                  `Line ") ib";
                ]
	      else
		[
                  `Line (sprintf "if len >= %i then (" (i+1));
                  `Block read_value;
                  `Line ") ib";
                  `Line "else";
		  `Block [
		    `Line
		      (match default with None -> assert false | Some s -> s)
                  ]
                ]
	    in
	    [
              `Line (sprintf "let x%i =" i);
              `Block get_value;
              `Line "in"
            ]
	) cells
      )
    )
  in

  let make_tuple =
    sprintf "(%s)"
      (String.concat ", "
	 (Array.to_list (Array.mapi (fun i _ -> sprintf "x%i" i) a)))
  in
  let req_fields =
    let acc = ref [] in
    for i = Array.length cells - 1 downto 0 do
      let _, default = cells.(i) in
      if default = None then
	acc := string_of_int i :: !acc
    done;
    sprintf "[ %s ]" (String.concat "; " !acc)
  in
  [
    `Line "let len = Bi_vint.read_uvint ib in";
    `Line (sprintf
	     "if len < %i then Ag_ob_run.missing_tuple_fields len %s;"
	     min_length req_fields);
    `Inline read_cells;
    `Line (sprintf "for i = %i to len - 1 do Bi_io.skip ib done;" tup_len);
    `Line make_tuple
  ]


and make_table_reader deref loc list_kind x =
  let empty_list, to_list =
    match list_kind with
	`List -> "[ ]", (fun s -> "Array.to_list " ^ s)
      | `Array -> "[| |]", (fun s -> s)
  in
  let fields =
    match deref x with
	`Record (loc, a, `Record o, `Record) ->
	  (match o with
	       `Record -> ()
	     | `Object ->
		 error loc "Sorry, OCaml objects are not supported"
	  );
	  get_fields deref a
      | _ ->
	  error loc "Not a list or array of records"
  in
  let init_val, init_bits, set_bit, check_bits = study_record deref fields in
  let cases =
    Array.to_list (
      Array.mapi (
	fun i (x, name, default, opt, unwrap) ->
	  `Inline [
	    `Line (sprintf "| %i ->" (Bi_io.hash_name x.f_name));
	    `Block [
	      `Inline (set_bit i);
	      `Line "let read =";
	      `Block [
		`Line "(";
		`Block (make_reader deref ~tagged:false x.f_value);
		`Line ")";
		`Block [ `Line "tag" ]
	      ];
	      `Line "in";
	      `Line "(fun x ib ->";
	      `Block [
		`Line (sprintf
			 "Obj.set_field (Obj.repr x) %i \
                            (Obj.repr (read ib)))" i
		      )
	      ]
	    ]
	  ]
      ) (Array.of_list fields)
    )
  in
  [
    `Line "let row_num = Bi_vint.read_uvint ib in";
     `Line ("if row_num = 0 then " ^ empty_list);
     `Line "else";
     `Block [
       `Line "let col_num = Bi_vint.read_uvint ib in";
       `Inline init_bits;
       `Line "let readers =";
       `Block [
	 `Line "Ag_ob_run.array_init2 col_num ib (";
	 `Block [
	   `Line "fun col ib ->";
	   `Block [
	     `Line "let h = Bi_io.read_field_hashtag ib in";
	     `Line "let tag = Bi_io.read_tag ib in";
	     `Line "match h with";
	     `Block cases;
	     `Block [ `Line "| _ -> (fun x ib -> Bi_io.skip ib)" ]
	   ]
	 ];
	 `Line ")";
       ];
       `Line "in";
       `Inline check_bits;
       `Line "let a = Array.make row_num (Obj.magic 0) in";
       `Line "for row = 0 to row_num - 1 do";
       `Block [
	 `Line "let x =";
	 `Block init_val;
	 `Line "in";
	 `Line "for i = 0 to Array.length readers - 1 do";
	 `Block [ `Line "readers.(i) x ib" ];
	 `Line "done;";
	 `Line "a.(row) <- x";
       ];
       `Line "done;";
       `Line (to_list "a")
     ]
  ]


let rec is_function (l : Ag_indent.t list) =
  match l with
      [] -> false
    | x :: _ ->
        match x with
            `Line _ -> false
          | `Block l -> is_function l
          | `Inline l -> is_function l
          | `Annot ("fun", _) -> true
          | `Annot _ -> false

let make_ocaml_biniou_writer deref is_rec let1 let2 def =
  let x = match def.def_value with None -> assert false | Some x -> x in
  let name = def.def_name in
  let param = def.def_param in
  let tag = get_biniou_tag (deref x) in
  let write_untagged = get_left_writer_name ~tagged:false name param in
  let write = get_left_writer_name ~tagged:true name param in
  let to_string = get_left_to_string_name name param in
  let write_untagged_expr = make_writer deref ~tagged:false x in
  let extra_param, extra_args =
    if is_function write_untagged_expr || not is_rec then "", ""
    else " ob x", " ob x"
  in
  let type_annot =
    match x with
        `Record _ | `Sum (_, _, `Sum `Classic, _) ->
            sprintf " : Bi_outbuf.t -> %s -> unit" name
      | _ -> ""
  in
  [
    `Line (sprintf "%s %s_tag = %s" let1 name tag);
    `Line (sprintf "%s %s%s%s = (" let2 write_untagged extra_param type_annot);
    `Block (List.map Ag_indent.strip write_untagged_expr);
    `Line (sprintf ")%s" extra_args);
    `Line (sprintf "%s %s ob x =" let2 write);
    `Block [
      `Line (sprintf "Bi_io.write_tag ob %s;" tag);
      `Line (sprintf "%s ob x" write_untagged);
    ];
    `Line (sprintf "%s %s ?(len = 1024) x =" let2 to_string);
    `Block [
      `Line "let ob = Bi_outbuf.create len in";
      `Line (sprintf "%s ob x;" write);
      `Line "Bi_outbuf.contents ob"
    ]
  ]

let make_ocaml_biniou_reader deref is_rec let1 let2 def =
  let x = match def.def_value with None -> assert false | Some x -> x in
  let name = def.def_name in
  let param = def.def_param in
  let get_reader = get_left_reader_name ~tagged:false name param in
  let read = get_left_reader_name ~tagged:true name param in
  let of_string = get_left_of_string_name name param in
  let type_annot =
    match x with
        `Record _ | `Sum (_, _, `Sum `Classic, _) -> " : " ^ name
      | _ -> ""
  in
  let get_reader_expr = make_reader deref ~tagged:false ~type_annot x in
  let read_expr = make_reader deref ~tagged:true ~type_annot x in
  let extra_param1, extra_args1 =
    if is_function get_reader_expr || not is_rec then "", ""
    else " tag", " tag"
  in
  let extra_param2, extra_args2 =
    if is_function read_expr || not is_rec then "", ""
    else " ib", " ib"
  in
  [
    `Line (sprintf "%s %s%s = (" let1 get_reader extra_param1);
    `Block (List.map Ag_indent.strip get_reader_expr);
    `Line (sprintf ")%s" extra_args1);
    `Line (sprintf "%s %s%s = (" let2 read extra_param2);
    `Block (List.map Ag_indent.strip read_expr);
    `Line (sprintf ")%s" extra_args2);
    `Line (sprintf "%s %s ?pos s =" let2 of_string);
    `Block [
      `Line (sprintf "%s (Bi_inbuf.from_string ?pos s)" read)
    ]
  ]

let map f = function
    [] -> []
  | x :: l ->
      let y = f true x in
      y :: List.map (f false) l

let get_let ~is_rec ~is_first =
  if is_first then
    if is_rec then "let rec", "and"
    else "let", "let"
  else "and", "and"

module S = Set.Make (String)

let extract_loc_ids_from_expr x acc =
  Atd_ast.fold
    (fun x acc ->
       match x with
           (`Shared (_, _, a)) ->
             let id =
               Atd_annot.get_field (fun s -> Some s) "" ["share"] "id" a in
             if id <> "" then
               S.add id acc
             else
               acc
         | _ -> acc)
    x
    acc

let extract_loc_ids l =
  let set =
    List.fold_left (
      fun acc (`Type (loc, (name, param, a), x)) ->
        extract_loc_ids_from_expr x acc
    ) S.empty l
  in
  S.elements set

let make_shared_id_defs atd_module =
  let buf = Buffer.create 200 in
  let l = extract_loc_ids atd_module in
  List.iter
    (fun id ->
       bprintf buf
         "let shared%s = Bi_share.create_type_id ()\n" id)
    l;
  Buffer.contents buf

let make_ocaml_biniou_impl ~with_create buf deref defs =
  (*bprintf buf "%s\n" (make_shared_id_defs ());*)

  let ll =
    List.map (
      fun (is_rec, l) ->
	let l = List.filter (fun x -> x.def_value <> None) l in
	let writers =
	  map (
	    fun is_first def ->
	      let let1, let2 = get_let ~is_rec ~is_first in
	      make_ocaml_biniou_writer deref is_rec let1 let2 def
	  ) l
	in
	let readers =
	  map (
	    fun is_first def ->
	      let let1, let2 = get_let ~is_rec ~is_first in
	      make_ocaml_biniou_reader deref is_rec let1 let2 def
	  ) l
	in
	List.flatten (writers @ readers)
  ) defs
  in
  Atd_indent.to_buffer buf (List.flatten ll);

  if with_create then
    List.iter (
      fun (is_rec, l) ->
        List.iter (
          fun x ->
            let intf, impl = Ag_ocaml.make_record_creator deref x in
            Buffer.add_string buf impl
        ) l
    ) defs



(*
  Glue
*)

let translate_mapping (l : (bool * Atd_ast.module_body) list) =
  defs_of_atd_modules l

let write_opens buf l =
  List.iter (fun s -> bprintf buf "open %s\n" s) l;
  bprintf buf "\n"

let make_mli
    ~header ~opens ~with_typedefs ~with_create ~with_fundefs
    ocaml_typedefs deref defs =
  let buf = Buffer.create 1000 in
  bprintf buf "%s\n" header;
  write_opens buf opens;
  if with_typedefs then
    bprintf buf "%s\n" ocaml_typedefs;
  if with_typedefs && with_fundefs then
    bprintf buf "\n";
  if with_fundefs then
    make_ocaml_biniou_intf ~with_create buf deref defs;
  Buffer.contents buf

let make_ml
    ~header ~opens ~with_typedefs ~with_create ~with_fundefs
    ocaml_typedefs ocaml_impl_misc deref defs =
  let buf = Buffer.create 1000 in
  bprintf buf "%s\n" header;
  write_opens buf opens;
  if with_typedefs then
    bprintf buf "%s\n" ocaml_typedefs;
  if with_typedefs && with_fundefs then
    bprintf buf "\n";
  if with_fundefs then (
    bprintf buf "%s\n" ocaml_impl_misc;
    make_ocaml_biniou_impl ~with_create buf deref defs
  );
  Buffer.contents buf

let make_ocaml_files
    ~opens
    ~with_typedefs
    ~with_create
    ~with_fundefs
    ~all_rec
    ~pos_fname
    ~pos_lnum
    ~type_aliases
    ~force_defaults
    ~name_overlap
    atd_file out =
  let head, m0 =
    match atd_file with
        Some file ->
          Atd_util.load_file
            ~expand:false ~inherit_fields:true ~inherit_variants:true
            ?pos_fname ?pos_lnum
            file
      | None ->
          Atd_util.read_channel
            ~expand:false ~inherit_fields:true ~inherit_variants:true
            ?pos_fname ?pos_lnum
            stdin
  in
  let m1 =
    if all_rec then
      [ (true, m0) ]
    else
      Atd_util.tsort m0
  in
  let defs1 = translate_mapping m1 in
  if not name_overlap then Ag_ox_emit.check defs1;
  Ag_xb_emit.check defs1;
  let m2 = Atd_util.tsort (Atd_expand.expand_module_body ~keep_poly:true m0) in
  (* m0 = original type definitions
     m1 = original type definitions after dependency analysis
     m2 = monomorphic type definitions after dependency analysis *)
  let ocaml_typedefs =
    Ag_ocaml.ocaml_of_atd ~target:`Biniou ~type_aliases (head, m1) in
  let ocaml_impl_misc = make_shared_id_defs m0 in
  let defs = translate_mapping m2 in
  let header =
    let src =
      match atd_file with
          None -> "stdin"
        | Some path -> sprintf "%S" (Filename.basename path)
    in
    sprintf "(* Auto-generated from %s *)\n" src
  in
  let mli =
    make_mli ~header ~opens ~with_typedefs ~with_create ~with_fundefs
      ocaml_typedefs (Ag_mapping.make_deref defs1) defs1
  in
  let ml =
    make_ml ~header ~opens ~with_typedefs ~with_create ~with_fundefs
      ocaml_typedefs ocaml_impl_misc (Ag_mapping.make_deref defs) defs
  in
  Ag_ox_emit.write_ocaml out mli ml
