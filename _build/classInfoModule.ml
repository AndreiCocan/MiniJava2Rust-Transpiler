module SM = StringMap
open MJ
open Print


(*__________________________________________________________________________________________*)
(*ClassInfo interface and implementation*)

module type ClassInfoInterface = sig
  type t

  (** [create name c defs] creates a [ClassInfoType.t] from the [name] of a class,
    the class [c] and all class definitions [defs]. *)
  val create : string -> MJ.java_class -> (identifier * java_class) list -> t

  (** [class_name class_info] returns the name of the class of this [class_info]. *)
  val class_name : t -> string

  (** [is_attribute m v class_info] checks if the variable [v] in the context of
      method [m] is an attribute of the [class_info] or not (if not it is a parameter or a local variable). *)
  val is_attribute : string -> string -> t -> bool

  (** [class_of m v class_info] returns the class name of variable [v] in the context of the
     method [m] in [class_info]. If [v] is of primitive type, the function returns the empty string. *)
  val class_of : string -> string -> t -> string

  (** [method_class_origin m class_info] returns the name of the class, in the class hierarchy for
      this [class_info], where the method [m] is last defined. *)
  val method_class_origin : string -> t -> string

  (** [attribute_class_origin a class_info] returns the name of the class, in the class hierarchy for this [class_info],
      where the attribute [a] is last defined. *)
  val attribute_class_origin : string -> t -> string

  (** [vtable_index m class_info] returns the index of the method [m] in the virtual table for this [class_info]. *)
  val vtable_index : string -> t -> int

  (** [return_type m class_info] gets the return type of the method [m] for this [class_info]. *)
  val return_type : string -> t -> MJ.java_type

  (** [get_methods class_info] returns all the method names of the [class_info] in a list.
      A method name is prefixed by the class where the method is last defined. The list is
      sorted by increasing method's vtable indices. *)
  val get_methods : t -> string list

  (** [get_attributes class_info] returns a list of all the attribute names of the [class_info] associated with their types.
      An attribute name is prefixed by the class where it is defined.
      The order in this list is such that the attributes for a parent class are put before the attributes of a child class.*)
  val get_attributes : t -> (string * MJ.java_type) list
end

module ClassInfo : ClassInfoType = struct
  (*The first element of the tuple is the class origin of the attribute,
  the second element is the type of the attribute.*)
  type attribute_info = (string * MJ.java_type) list SM.t

  (*The first element of the tuple is the class origin of the method,
  the second element is the [MJ.java_method] type for the method. *)
  type method_info = (string * MJ.java_method) SM.t

  type t = {
    class_name : string;
    attribute_info : attribute_info;
    method_info : method_info
  }
(*----------------------------------------------------------------------------------------------------------------*)
(*Utility functions for create method*)

  (*Function to fold a function on all the hierachy starting by the class [parent] all the way to the 
    top of the hierarchy*)
    (*
  let rec fold_class_hierarchy (f : string -> MJ.java_class -> 'a -> 'a) 
  (defs : (MJ.identifier * MJ.java_class) list) (parent : string option) (acc : 'a) : 'a =
    match parent with
    | None -> acc
    | Some name ->  try
                      let c = List.assoc name defs 
                      in
                      f name c (fold_class_hierarchy f defs c.extends acc)
                    with Not_found -> acc

  let set_attribute_index class_name java_class acc index reorderfun =
    let res =
      List.fold_left (
        fun acc (attribute_name, t) -> SM.update attribute_name (reorderfun class_name !index t) acc 
        ) acc (StringMap.to_association_list java_class.attributes)
    in
    index := !index + 1 ;
    res

  *)

  (** If a parent class and a child class have the same attribute name, the attribute
  of the child class is before the attribute of the parent class in the list. *)
  (*
  let reorder_attribute class_name index java_type = function
  | None -> Some [class_name, index, java_type]
  | Some list -> Some ((class_name, index, java_type) :: list)*)
(*
  let set_method_index class_name java_class acc=
    let n = ref (SM.cardinal acc) 
    in
    List.fold_left (
      fun acc (method_name, m) -> if SM.mem method_name acc 
                                  then let _, index, _ = SM.find method_name acc 
                                       in
                                       SM.add method_name (class_name, index, m) acc
                                  else begin 
                                        let index = !n in
                                        incr n;
                                        SM.add method_name (class_name, index, m) acc
                                       end
    )
    *)
(*----------------------------------------------------------------------------------------------------------------*)

  let create class_name c defs =
    let attribute_info =
      (** The [index] is used to sort the attributes in the V structure. The attributes of a child
            must come after the attributes of the parent. *)
      let index = ref 0 
      in
      fold_class_hierarchy set_attribute_index defs (Some class_name) SM.empty
    in
    let method_info =
      fold_class_hierarchy set_method_index defs (Some class_name) SM.empty
    in
    { 
      class_name = class_name;
      attribute_info = attribute_info;
      method_info = method_info 
    }

  let class_name class_info = class_info.class_name

  (** [find_variable_type m v class_info] gets the type of a variable [v] (formal parameter or local variable)
      for the method [m] in [class_info]. If the variable doesn't exist, raises [Not_found]. *)
  let find_variable_type m v class_info =
    let _, _, metho = SM.find m class_info.method_info in
    match List.assoc_opt v metho.formals with
    | Some t -> t
    | None -> List.assoc v metho.locals

  let is_attribute m v class_info =
    try
      find_variable_type m v class_info
      |> ignore;
      false
    with Not_found -> true

  let class_of m v class_info =
    if is_attribute m v class_info then
      let _, _, t =
        SM.find v class_info.attribute_info
        |> List.hd
      in
      match t with
      | Typ t -> t
      | _ -> ""
    else
      match find_variable_type m v class_info with
      | Typ t -> t
      | _ -> ""

  let method_class_origin m class_info =
    let orig, _, _ = SM.find m class_info.method_info in
    orig

  let attribute_class_origin v class_info =
    let orig, _, _ = SM.find v class_info.attribute_info |> List.hd in
    orig

  let vtable_index m class_info =
    let _, index, _ = SM.find m class_info.method_info in
    index

  let return_type m class_info =
    let _, _, metho = SM.find m class_info.method_info in
    metho.result

  let get_methods class_info =
    SM.fold
      (fun method_name (orig, index, _) acc ->
        (index, orig ^ "_" ^ method_name) :: acc
      )
      class_info.method_info
      []
    |> List.sort compare
    |> List.map snd

  let get_attributes class_info =
    SM.fold
      (fun attribute_name l acc ->
        List.fold_right
          (fun (orig, index, t) acc ->
            (index, attribute_name, orig, t) :: acc)
          l
          acc
      )
      class_info.attribute_info
      []
    |> List.sort compare
    |> List.map (fun (_, attribute_name, orig, t) -> (orig ^ "_" ^ attribute_name, t))
end


(*__________________________________________________________________________________________*)
(*Utility functions for the translation*)


(* A hash table from the name of a class to a [class_info]. *)
let class_infos = Hashtbl.create 57

(* Fills the [class_infos] hash table using the classes defined in [program]. *)
let init_class_infos (prog : MJ.program) : unit =
  let main =
    {
      extends = None;
      attributes = StringMap.of_association_list [];
      methods = StringMap.of_association_list []
    }
  in
  ClassInfo.create prog.name main prog.defs |> Hashtbl.add class_infos prog.name;
  List.iter
    (
      fun (class_name, clas) ->
      ClassInfo.create class_name clas p.defs
      |> Hashtbl.add class_infos class_name
    ) prog.defs

(* Returns the [class_info] associated with class name [c]. *)
let get_class_info (class_name : string) : ClassInfo.t =
  Hashtbl.find class_infos class_name

(*Gets the class name of the the type of expression [e] in the context
  of method [m] in [class_info]. If no class type is associated with expression [e], [get_class]
  returns the empty string. *)
let rec get_class_expr (method_name : string) (class_info : ClassInfo.t) (e : MJ.expression) : string =
match e with
| EGetVar x -> ClassInfo.class_of method_name x class_info
| EMethodCall (obj, met, _) ->
                          begin
                            let java_type =
                              get_class_expr method_name class_info o
                              |> get_class_info
                              |> ClassInfo.return_type met
                            in
                            match java_type with
                            | Typ t -> t
                            | _ -> ""
                          end
| EThis -> ClassInfo.class_name class_info
| EObjectAlloc id -> id
| _ -> ""

