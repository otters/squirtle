import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/function
import gleam/int
import gleam/json
import gleam/list
import gleam/pair
import gleam/result
import gleam/string

pub type JsonDict =
  dict.Dict(String, JsonValue)

pub type JsonArray =
  List(JsonValue)

pub type JsonValue {
  Null
  String(String)
  Int(Int)
  Bool(Bool)
  Float(Float)
  Array(JsonArray)
  Object(JsonDict)
}

pub fn json_value_decoder() -> decode.Decoder(JsonValue) {
  use <- decode.recursive
  decode.one_of(decode.string |> decode.map(String), [
    json_int(),
    json_bool(),
    json_float(),
    json_array(),
    json_object(),
    decode.success(Null),
  ])
}

fn json_bool() {
  decode.bool |> decode.map(Bool)
}

fn json_float() {
  decode.float |> decode.map(Float)
}

fn json_int() {
  decode.int |> decode.map(Int)
}

fn json_array() {
  decode.list(json_value_decoder()) |> decode.map(Array)
}

fn json_object() {
  decode.dict(decode.string, json_value_decoder())
  |> decode.map(Object)
}

pub fn parse(raw: String) -> Result(JsonValue, json.DecodeError) {
  json.parse(raw, json_value_decoder())
}

fn do_to_dynamic(value) {
  case value {
    String(s) -> dynamic.string(s)
    Int(i) -> dynamic.int(i)
    Bool(b) -> dynamic.bool(b)
    Float(f) -> dynamic.float(f)
    Array(arr) -> dynamic.list(arr |> list.map(do_to_dynamic))
    Null -> dynamic.nil()
    Object(obj) -> {
      let d =
        obj
        |> dict.to_list
        |> list.map(fn(p) {
          p
          |> pair.map_first(dynamic.string)
          |> pair.map_second(do_to_dynamic)
        })

      dynamic.properties(d)
    }
  }
}

pub fn to_dynamic(value: JsonValue) {
  do_to_dynamic(value)
}

pub fn decode_value(value: JsonValue, decoder: decode.Decoder(a)) {
  to_dynamic(value) |> decode.run(decoder)
}

pub fn to_json(value: JsonValue) -> json.Json {
  case value {
    String(s) -> json.string(s)
    Int(i) -> json.int(i)
    Bool(b) -> json.bool(b)
    Float(f) -> json.float(f)
    Array(arr) -> json.array(arr, to_json)
    Object(obj) -> json.dict(obj, function.identity, to_json)
    Null -> json.null()
  }
}

pub fn to_string(value: JsonValue) -> String {
  value |> to_json |> json.to_string
}

pub type Patch {
  Add(path: String, value: JsonValue)
  Remove(path: String)
  Replace(path: String, value: JsonValue)
  Copy(from: String, path: String)
  Move(from: String, path: String)
  Test(path: String, value: JsonValue)
}

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
          case dict.get(dict, token) {
            Ok(value) -> navigate_get(value, rest)
            Error(_) -> Error("path /" <> token <> " does not exist")
          }
        }
        Array(elements) -> {
          case has_leading_zero(token) {
            True -> Error("invalid array index: " <> token)
            False -> {
              case int.parse(token) {
                Ok(index) -> {
                  case get_at_index(elements, index) {
                    Ok(value) -> navigate_get(value, rest)
                    Error(_) -> Error("array index out of bounds: " <> token)
                  }
                }
                Error(_) -> Error("invalid array index: " <> token)
              }
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
    [token] -> {
      case data {
        Object(d) -> {
          let new_dict = dict.insert(d, token, value)
          Ok(Object(new_dict))
        }
        Array(elements) -> {
          case token {
            "-" -> {
              let new_array = list.append(elements, [value])
              Ok(Array(new_array))
            }
            _ -> {
              case has_leading_zero(token) {
                True -> Error("invalid array index: " <> token)
                False -> {
                  case int.parse(token) {
                    Ok(index) -> {
                      case insert_at_index(elements, index, value, mode) {
                        Ok(new_array) -> Ok(Array(new_array))
                        Error(e) -> Error(e)
                      }
                    }
                    Error(_) -> Error("invalid array index: " <> token)
                  }
                }
              }
            }
          }
        }
        _ -> Error("cannot add to non-object/non-array")
      }
    }
    [token, ..rest] -> {
      case data {
        Object(d) -> {
          case dict.get(d, token) {
            Ok(nested) -> {
              use new_nested <- result.try(navigate_set(
                nested,
                rest,
                value,
                mode,
                is_add,
              ))
              let new_dict = dict.insert(d, token, new_nested)
              Ok(Object(new_dict))
            }
            Error(_) ->
              case is_add {
                True -> Error("add to a non-existent target")
                False -> Error("path does not exist")
              }
          }
        }
        Array(elements) -> {
          case has_leading_zero(token) {
            True -> Error("invalid array index: " <> token)
            False -> {
              case int.parse(token) {
                Ok(index) -> {
                  case get_at_index(elements, index) {
                    Ok(nested) -> {
                      use new_nested <- result.try(navigate_set(
                        nested,
                        rest,
                        value,
                        mode,
                        is_add,
                      ))
                      case replace_at_index(elements, index, new_nested) {
                        Ok(new_array) -> Ok(Array(new_array))
                        Error(e) -> Error(e)
                      }
                    }
                    Error(_) -> Error("array index out of bounds: " <> token)
                  }
                }
                Error(_) -> Error("invalid array index: " <> token)
              }
            }
          }
        }
        _ -> Error("cannot navigate into non-object/non-array")
      }
    }
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
    [token] -> {
      case data {
        Object(d) -> {
          case dict.has_key(d, token) {
            True -> {
              let new_dict = dict.delete(d, token)
              Ok(Object(new_dict))
            }
            False -> Error("path does not exist")
          }
        }
        Array(elements) -> {
          case has_leading_zero(token) {
            True -> Error("invalid array index: " <> token)
            False -> {
              case int.parse(token) {
                Ok(index) -> {
                  case remove_at_index(elements, index) {
                    Ok(new_array) -> Ok(Array(new_array))
                    Error(e) -> Error(e)
                  }
                }
                Error(_) -> Error("invalid array index: " <> token)
              }
            }
          }
        }
        _ -> Error("cannot remove from non-object/non-array")
      }
    }
    [token, ..rest] -> {
      case data {
        Object(d) -> {
          case dict.get(d, token) {
            Ok(nested) -> {
              use new_nested <- result.try(navigate_remove(nested, rest))
              let new_dict = dict.insert(d, token, new_nested)
              Ok(Object(new_dict))
            }
            Error(_) -> Error("path does not exist")
          }
        }
        Array(elements) -> {
          case int.parse(token) {
            Ok(index) -> {
              case get_at_index(elements, index) {
                Ok(nested) -> {
                  use new_nested <- result.try(navigate_remove(nested, rest))
                  case replace_at_index(elements, index, new_nested) {
                    Ok(new_array) -> Ok(Array(new_array))
                    Error(e) -> Error(e)
                  }
                }
                Error(_) -> Error("array index out of bounds: " <> token)
              }
            }
            Error(_) -> Error("invalid array index: " <> token)
          }
        }
        _ -> Error("cannot navigate into non-object/non-array")
      }
    }
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

pub fn patch_string(data: String, patches: String) -> Result(String, String) {
  use doc <- result.try(
    parse(data)
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
  Ok(to_string(patched))
}

pub fn parse_patches(patches: String) -> Result(List(Patch), json.DecodeError) {
  json.parse(patches, decode.list(patch_decoder()))
}
