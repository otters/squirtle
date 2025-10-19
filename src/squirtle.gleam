import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/function
import gleam/int
import gleam/json
import gleam/list
import gleam/pair
import gleam/result
import gleam/set
import gleam/string

/// A JSON object represented as a dictionary mapping strings to JsonValues
pub type JsonDict =
  dict.Dict(String, JsonValue)

/// A JSON array represented as a list of JsonValues
pub type JsonArray =
  List(JsonValue)

/// Represents any JSON value
///
/// This type can represent all valid JSON values including objects, arrays,
/// strings, numbers, booleans, and null.
pub type JsonValue {
  Null
  String(String)
  Int(Int)
  Bool(Bool)
  Float(Float)
  Array(JsonArray)
  Object(JsonDict)
}

/// Returns a decoder for parsing JSON into a JsonValue
///
/// This decoder can parse any valid JSON value.
///
/// ## Example
///
/// ```gleam
/// import gleam/json
/// import squirtle
///
/// json.parse("{\"name\": \"John\"}", squirtle.json_value_decoder())
/// // => Ok(Object(...))
/// ```
pub fn json_value_decoder() -> decode.Decoder(JsonValue) {
  use <- decode.recursive
  decode.one_of(decode.string |> decode.map(String), [
    decode.int |> decode.map(Int),
    decode.bool |> decode.map(Bool),
    decode.float |> decode.map(Float),
    decode.list(json_value_decoder()) |> decode.map(Array),
    decode.dict(decode.string, json_value_decoder())
      |> decode.map(Object),
    decode.success(Null),
  ])
}

/// Parse a JSON string into a JsonValue
///
/// ## Example
///
/// ```gleam
/// import squirtle
///
/// squirtle.parse("{\"name\": \"John\", \"age\": 30}")
/// // => Ok(Object(...))
/// ```
pub fn json_value_parse(raw: String) -> Result(JsonValue, json.DecodeError) {
  json.parse(raw, json_value_decoder())
}

/// Convert a JsonValue to a Dynamic value
///
/// This is useful when you need to use the value with Gleam's dynamic decoding functions.
///
/// ## Example
///
/// ```gleam
/// import squirtle
///
/// let value = squirtle.String("hello")
/// squirtle.json_value_to_dynamic(value)
/// ```
pub fn json_value_to_dynamic(value: JsonValue) {
  case value {
    String(s) -> dynamic.string(s)
    Int(i) -> dynamic.int(i)
    Bool(b) -> dynamic.bool(b)
    Float(f) -> dynamic.float(f)
    Array(arr) -> dynamic.list(arr |> list.map(json_value_to_dynamic))
    Null -> dynamic.nil()
    Object(obj) -> {
      let d =
        obj
        |> dict.to_list
        |> list.map(fn(p) {
          p
          |> pair.map_first(dynamic.string)
          |> pair.map_second(json_value_to_dynamic)
        })

      dynamic.properties(d)
    }
  }
}

/// Decode a JsonValue using a custom decoder
///
/// This allows you to decode a JsonValue into a specific Gleam type.
///
/// ## Example
///
/// ```gleam
/// import gleam/dynamic/decode
/// import squirtle
///
/// let value = squirtle.Object(...)
/// squirtle.json_value_decode(value, decode.field("name", decode.string))
/// // => Ok("John")
/// ```
pub fn json_value_decode(value: JsonValue, decoder: decode.Decoder(a)) {
  json_value_to_dynamic(value) |> decode.run(decoder)
}

/// Convert a JsonValue to gleam/json's Json type
///
/// This is useful when you need to work with the standard library's JSON functions.
///
/// ## Example
///
/// ```gleam
/// import squirtle
///
/// let value = squirtle.String("hello")
/// squirtle.json_value_to_json(value)
/// ```
pub fn json_value_to_json(value: JsonValue) -> json.Json {
  case value {
    String(s) -> json.string(s)
    Int(i) -> json.int(i)
    Bool(b) -> json.bool(b)
    Float(f) -> json.float(f)
    Array(arr) -> json.array(arr, json_value_to_json)
    Object(obj) -> json.dict(obj, function.identity, json_value_to_json)
    Null -> json.null()
  }
}

/// Convert a JsonValue to a JSON string
///
/// ## Example
///
/// ```gleam
/// import squirtle
///
/// let value = squirtle.Object(...)
/// squirtle.json_value_to_string(value)
/// // => "{\"name\":\"John\"}"
/// ```
pub fn json_value_to_string(value: JsonValue) -> String {
  value |> json_value_to_json |> json.to_string
}

/// A JSON Patch operation
/// Represents one of the six operations defined in RFC 6902:
pub type Patch {
  /// Add a value at a path
  Add(path: String, value: JsonValue)
  /// Remove a value at a path
  Remove(path: String)
  /// Replace a value at a path
  Replace(path: String, value: JsonValue)
  /// Copy a value from one path to another
  Copy(from: String, path: String)
  /// Move a value from one path to another
  Move(from: String, path: String)
  /// Test that a value at a path equals an expected value
  Test(path: String, value: JsonValue)
}

/// Returns a decoder for parsing JSON into a Patch operation
///
/// This decoder parses a single patch operation from JSON according to RFC 6902.
///
/// ## Example
///
/// ```gleam
/// import gleam/json
/// import squirtle
///
/// json.parse("{\"op\": \"add\", \"path\": \"/name\", \"value\": \"John\"}",
///            squirtle.patch_decoder())
/// // => Ok(Add("/name", String("John")))
/// ```
pub fn patch_decoder() -> decode.Decoder(Patch) {
  use op <- decode.field("op", decode.string)

  case op {
    "add" -> {
      use path <- decode.field("path", decode.string)
      use value <- decode.field("value", json_value_decoder())
      decode.success(Add(path:, value:))
    }

    "remove" -> {
      use path <- decode.field("path", decode.string)
      decode.success(Remove(path:))
    }

    "replace" -> {
      use path <- decode.field("path", decode.string)
      use value <- decode.field("value", json_value_decoder())
      decode.success(Replace(path:, value:))
    }

    "copy" -> {
      use from <- decode.field("from", decode.string)
      use path <- decode.field("path", decode.string)
      decode.success(Copy(from:, path:))
    }

    "move" -> {
      use from <- decode.field("from", decode.string)
      use path <- decode.field("path", decode.string)
      decode.success(Move(from:, path:))
    }

    "test" -> {
      use path <- decode.field("path", decode.string)
      use value <- decode.field("value", json_value_decoder())
      decode.success(Test(path:, value:))
    }

    _ -> decode.failure(Copy("", ""), "Unknown op: '" <> op <> "'")
  }
}

/// Apply a list of patch operations to a JSON document
///
/// Applies all patches in order, returning the modified document or an error if any patch fails.
/// All patches must succeed for the operation to succeed.
///
/// ## Example
///
/// ```gleam
/// import squirtle
///
/// let assert Ok(doc) = squirtle.parse("{\"name\": \"John\"}")
/// let patches = [
///   squirtle.Replace(path: "/name", value: squirtle.String("Jane")),
///   squirtle.Add(path: "/age", value: squirtle.Int(30)),
/// ]
///
/// squirtle.patch(doc, patches)
/// // => Ok(Object(...))
/// ```
pub fn patch(data: JsonValue, patches: List(Patch)) {
  do_patch_iter(data, patches)
}

fn parse_path(path: String) -> Result(List(String), String) {
  case path {
    "" -> Ok([])
    "/" <> rest -> {
      string.split(rest, "/")
      |> list.map(decode_pointer_token)
      |> Ok
    }
    _ -> Error("Invalid JSON Pointer: must start with /")
  }
}

fn decode_pointer_token(token: String) -> String {
  token
  |> string.replace("~1", "/")
  |> string.replace("~0", "~")
}

fn encode_pointer_token(token: String) -> String {
  token
  |> string.replace("~", "~0")
  |> string.replace("/", "~1")
}

fn has_leading_zero(s: String) -> Bool {
  case s {
    "0" <> rest -> string.length(rest) > 0
    _ -> False
  }
}

fn get_at_index(lst: List(a), index: Int) -> Result(a, Nil) {
  case index, lst {
    _, [] -> Error(Nil)
    0, [first, ..] -> Ok(first)
    n, [_, ..rest] if n > 0 -> get_at_index(rest, n - 1)
    _, _ -> Error(Nil)
  }
}

fn get_value(data: JsonValue, path: String) -> Result(JsonValue, String) {
  use tokens <- result.try(parse_path(path))
  navigate_get(data, tokens)
}

fn navigate_get(
  data: JsonValue,
  tokens: List(String),
) -> Result(JsonValue, String) {
  case tokens {
    [] -> Ok(data)
    [token, ..rest] -> {
      case data {
        Object(dict) -> {
          use value <- result.try(
            dict.get(dict, token)
            |> result.replace_error("path /" <> token <> " does not exist"),
          )
          navigate_get(value, rest)
        }
        Array(elements) -> {
          case has_leading_zero(token) {
            True -> Error("invalid array index: " <> token)
            False -> {
              use index <- result.try(
                int.parse(token)
                |> result.replace_error("invalid array index: " <> token),
              )
              use value <- result.try(
                get_at_index(elements, index)
                |> result.replace_error("array index out of bounds: " <> token),
              )
              navigate_get(value, rest)
            }
          }
        }
        _ -> Error("cannot navigate into non-object/non-array")
      }
    }
  }
}

fn add(data: JsonValue, path: String, value: JsonValue) {
  use tokens <- result.try(parse_path(path))
  navigate_set(data, tokens, value, AddMode, True)
}

type SetMode {
  AddMode
  ReplaceMode
}

fn navigate_set(
  data: JsonValue,
  tokens: List(String),
  value: JsonValue,
  mode: SetMode,
  is_add: Bool,
) -> Result(JsonValue, String) {
  case tokens {
    [] -> Ok(value)
    [token] -> navigate_set_final(data, token, value, mode)
    [token, ..rest] ->
      navigate_set_recursive(data, token, rest, value, mode, is_add)
  }
}

fn navigate_set_final(
  data: JsonValue,
  token: String,
  value: JsonValue,
  mode: SetMode,
) -> Result(JsonValue, String) {
  case data {
    Object(d) -> Ok(Object(dict.insert(d, token, value)))
    Array(elements) if token == "-" -> Ok(Array(list.append(elements, [value])))
    Array(elements) -> {
      case has_leading_zero(token) {
        True -> Error("invalid array index: " <> token)
        False -> {
          use index <- result.try(
            int.parse(token)
            |> result.replace_error("invalid array index: " <> token),
          )
          use new_array <- result.try(insert_at_index(
            elements,
            index,
            value,
            mode,
          ))
          Ok(Array(new_array))
        }
      }
    }
    _ -> Error("cannot add to non-object/non-array")
  }
}

fn navigate_set_recursive(
  data: JsonValue,
  token: String,
  rest: List(String),
  value: JsonValue,
  mode: SetMode,
  is_add: Bool,
) -> Result(JsonValue, String) {
  case data {
    Object(d) -> {
      use nested <- result.try(
        dict.get(d, token)
        |> result.replace_error(case is_add {
          True -> "add to a non-existent target"
          False -> "path does not exist"
        }),
      )
      use new_nested <- result.try(navigate_set(
        nested,
        rest,
        value,
        mode,
        is_add,
      ))
      Ok(Object(dict.insert(d, token, new_nested)))
    }
    Array(elements) -> {
      case has_leading_zero(token) {
        True -> Error("invalid array index: " <> token)
        False -> {
          use index <- result.try(
            int.parse(token)
            |> result.replace_error("invalid array index: " <> token),
          )
          use nested <- result.try(
            get_at_index(elements, index)
            |> result.replace_error("array index out of bounds: " <> token),
          )
          use new_nested <- result.try(navigate_set(
            nested,
            rest,
            value,
            mode,
            is_add,
          ))
          use new_array <- result.try(replace_at_index(
            elements,
            index,
            new_nested,
          ))
          Ok(Array(new_array))
        }
      }
    }
    _ -> Error("cannot navigate into non-object/non-array")
  }
}

fn insert_at_index(
  lst: List(a),
  index: Int,
  value: a,
  mode: SetMode,
) -> Result(List(a), String) {
  case mode {
    AddMode -> do_insert_at_index(lst, index, value, 0)
    ReplaceMode -> replace_at_index(lst, index, value)
  }
}

fn do_insert_at_index(
  lst: List(a),
  index: Int,
  value: a,
  current: Int,
) -> Result(List(a), String) {
  case index == current, lst {
    True, rest -> Ok([value, ..rest])
    False, [first, ..rest] ->
      case do_insert_at_index(rest, index, value, current + 1) {
        Ok(new_rest) -> Ok([first, ..new_rest])
        Error(e) -> Error(e)
      }
    False, [] -> Error("array index out of bounds")
  }
}

fn replace_at_index(
  lst: List(a),
  index: Int,
  value: a,
) -> Result(List(a), String) {
  do_replace_at_index(lst, index, value, 0)
}

fn do_replace_at_index(
  lst: List(a),
  index: Int,
  value: a,
  current: Int,
) -> Result(List(a), String) {
  case index == current, lst {
    True, [_, ..rest] -> Ok([value, ..rest])
    False, [first, ..rest] ->
      case do_replace_at_index(rest, index, value, current + 1) {
        Ok(new_rest) -> Ok([first, ..new_rest])
        Error(e) -> Error(e)
      }
    _, [] -> Error("array index out of bounds")
  }
}

fn remove(data: JsonValue, path: String) {
  use tokens <- result.try(parse_path(path))
  navigate_remove(data, tokens)
}

fn navigate_remove(
  data: JsonValue,
  tokens: List(String),
) -> Result(JsonValue, String) {
  case tokens {
    [] -> Error("cannot remove root")
    [token] -> navigate_remove_final(data, token)
    [token, ..rest] -> navigate_remove_recursive(data, token, rest)
  }
}

fn navigate_remove_final(
  data: JsonValue,
  token: String,
) -> Result(JsonValue, String) {
  case data {
    Object(d) -> {
      case dict.has_key(d, token) {
        True -> Ok(Object(dict.delete(d, token)))
        False -> Error("path does not exist")
      }
    }
    Array(elements) -> {
      case has_leading_zero(token) {
        True -> Error("invalid array index: " <> token)
        False -> {
          use index <- result.try(
            int.parse(token)
            |> result.replace_error("invalid array index: " <> token),
          )
          use new_array <- result.try(remove_at_index(elements, index))
          Ok(Array(new_array))
        }
      }
    }
    _ -> Error("cannot remove from non-object/non-array")
  }
}

fn navigate_remove_recursive(
  data: JsonValue,
  token: String,
  rest: List(String),
) -> Result(JsonValue, String) {
  case data {
    Object(d) -> {
      use nested <- result.try(
        dict.get(d, token)
        |> result.replace_error("path does not exist"),
      )
      use new_nested <- result.try(navigate_remove(nested, rest))
      Ok(Object(dict.insert(d, token, new_nested)))
    }
    Array(elements) -> {
      use index <- result.try(
        int.parse(token)
        |> result.replace_error("invalid array index: " <> token),
      )
      use nested <- result.try(
        get_at_index(elements, index)
        |> result.replace_error("array index out of bounds: " <> token),
      )
      use new_nested <- result.try(navigate_remove(nested, rest))
      use new_array <- result.try(replace_at_index(elements, index, new_nested))
      Ok(Array(new_array))
    }
    _ -> Error("cannot navigate into non-object/non-array")
  }
}

fn remove_at_index(lst: List(a), index: Int) -> Result(List(a), String) {
  do_remove_at_index(lst, index, 0)
}

fn do_remove_at_index(
  lst: List(a),
  index: Int,
  current: Int,
) -> Result(List(a), String) {
  case index == current, lst {
    True, [_, ..rest] -> Ok(rest)
    False, [first, ..rest] ->
      case do_remove_at_index(rest, index, current + 1) {
        Ok(new_rest) -> Ok([first, ..new_rest])
        Error(e) -> Error(e)
      }
    _, [] -> Error("array index out of bounds")
  }
}

fn replace(data: JsonValue, path: String, value: JsonValue) {
  use tokens <- result.try(parse_path(path))
  navigate_set(data, tokens, value, ReplaceMode, False)
}

fn copy(data: JsonValue, from: String, path: String) {
  use from_value <- result.try(get_value(data, from))
  add(data, path, from_value)
}

fn move(data: JsonValue, from: String, path: String) {
  use from_value <- result.try(get_value(data, from))
  use after_remove <- result.try(remove(data, from))
  add(after_remove, path, from_value)
}

fn test_(data: JsonValue, path: String, value: JsonValue) {
  use found_value <- result.try(get_value(data, path))
  case found_value == value {
    True -> Ok(data)
    False -> Error("values not equivalent")
  }
}

fn do_patch_iter(acc: JsonValue, patches: List(Patch)) {
  case patches {
    [] -> Ok(acc)
    [patch, ..rest] -> {
      use next <- result.try(case patch {
        Add(path, value) -> add(acc, path, value)
        Remove(path) -> remove(acc, path)
        Replace(path, value) -> replace(acc, path, value)
        Copy(from, path) -> copy(acc, from, path)
        Move(from, path) -> move(acc, from, path)
        Test(path, value) -> test_(acc, path, value)
      })

      do_patch_iter(next, rest)
    }
  }
}

/// Parse and apply JSON patches to a JSON document, both provided as strings
///
/// This is a convenience function that combines parsing, patching, and stringifying.
/// Returns the patched document as a JSON string.
///
/// ## Example
///
/// ```gleam
/// import squirtle
///
/// let doc = "{\"name\":\"John\",\"age\":30}"
/// let patches = "[{\"op\":\"replace\",\"path\":\"/name\",\"value\":\"Jane\"}]"
///
/// squirtle.patch_string(doc, patches)
/// // => Ok("{\"name\":\"Jane\",\"age\":30}")
/// ```
pub fn patch_string(data: String, patches: String) -> Result(String, String) {
  use doc <- result.try(
    json_value_parse(data)
    |> result.map_error(fn(e) {
      "Failed to parse document: " <> string.inspect(e)
    }),
  )
  use patch_list <- result.try(
    json.parse(patches, decode.list(patch_decoder()))
    |> result.map_error(fn(e) {
      "Failed to parse patches: " <> string.inspect(e)
    }),
  )
  use patched <- result.try(patch(doc, patch_list))
  Ok(json_value_to_string(patched))
}

/// Parse a JSON array of patch operations from a string
///
/// ## Example
///
/// ```gleam
/// import squirtle
///
/// let patches_json = "[
///   {\"op\": \"add\", \"path\": \"/name\", \"value\": \"John\"},
///   {\"op\": \"remove\", \"path\": \"/age\"}
/// ]"
///
/// squirtle.parse_patches(patches_json)
/// // => Ok([Add("/name", String("John")), Remove("/age")])
/// ```
pub fn parse_patches(patches: String) -> Result(List(Patch), json.DecodeError) {
  json.parse(patches, decode.list(patch_decoder()))
}

fn diff_arrays(from: JsonArray, to: JsonArray, path: String) -> List(Patch) {
  let from_len = list.length(from)
  let to_len = list.length(to)
  let min_len = case from_len < to_len {
    True -> from_len
    False -> to_len
  }

  let change_patches = case min_len > 0 {
    True ->
      list.range(0, min_len - 1)
      |> list.flat_map(fn(idx) {
        let assert Ok(from_val) = get_at_index(from, idx)
        let assert Ok(to_val) = get_at_index(to, idx)
        do_diff(from_val, to_val, path <> "/" <> int.to_string(idx))
      })
    False -> []
  }

  let add_patches = case to_len > from_len {
    True -> {
      list.range(from_len, to_len - 1)
      |> list.map(fn(idx) {
        let assert Ok(val) = get_at_index(to, idx)
        Add(path: path <> "/-", value: val)
      })
    }
    False -> []
  }

  let remove_patches = case from_len > to_len {
    True -> {
      list.range(to_len, from_len - 1)
      |> list.reverse
      |> list.map(fn(idx) { Remove(path: path <> "/" <> int.to_string(idx)) })
    }
    False -> []
  }

  list.flatten([change_patches, add_patches, remove_patches])
}

fn diff_objects(from: JsonDict, to: JsonDict, path: String) -> List(Patch) {
  let from_keys = dict.keys(from) |> set.from_list
  let to_keys = dict.keys(to) |> set.from_list

  let removed = set.difference(from_keys, to_keys)
  let remove_patches =
    set.to_list(removed)
    |> list.map(fn(key) {
      Remove(path: path <> "/" <> encode_pointer_token(key))
    })

  let added = set.difference(to_keys, from_keys)
  let add_patches =
    set.to_list(added)
    |> list.map(fn(key) {
      let assert Ok(value) = dict.get(to, key)
      Add(path: path <> "/" <> encode_pointer_token(key), value: value)
    })

  let common = set.intersection(from_keys, to_keys)
  let change_patches =
    set.to_list(common)
    |> list.flat_map(fn(key) {
      let assert Ok(from_value) = dict.get(from, key)
      let assert Ok(to_value) = dict.get(to, key)
      do_diff(from_value, to_value, path <> "/" <> encode_pointer_token(key))
    })

  list.flatten([remove_patches, add_patches, change_patches])
}

fn do_diff(from: JsonValue, to: JsonValue, path: String) -> List(Patch) {
  case from == to {
    True -> []
    False ->
      case from, to {
        Object(from_obj), Object(to_obj) -> diff_objects(from_obj, to_obj, path)
        Array(from_arr), Array(to_arr) -> diff_arrays(from_arr, to_arr, path)
        _, _ -> [Replace(path: path, value: to)]
      }
  }
}

/// Generate a list of patch operations that transform one JSON value into another
///
/// This function compares two JsonValues and produces the minimal set of patches
/// that, when applied to the first value, will produce the second value.
///
/// ## Example
///
/// ```gleam
/// import gleam/dict
/// import squirtle
///
/// let doc1 = squirtle.Object(dict.from_list([
///   #("name", squirtle.String("John")),
///   #("age", squirtle.Int(30))
/// ]))
///
/// let doc2 = squirtle.Object(dict.from_list([
///   #("name", squirtle.String("Jane")),
///   #("age", squirtle.Int(30)),
///   #("email", squirtle.String("jane@example.com"))
/// ]))
///
/// let patches = squirtle.diff(doc1, doc2)
/// // => [
/// //   Replace(path: "/name", value: String("Jane")),
/// //   Add(path: "/email", value: String("jane@example.com"))
/// // ]
///
/// squirtle.patch(doc1, patches)
/// // => Ok(doc2)
/// ```
pub fn diff(from: JsonValue, to: JsonValue) -> List(Patch) {
  do_diff(from, to, "")
}
