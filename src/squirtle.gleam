import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import json_value

pub type Patch {
  Add(path: String, value: json_value.JsonValue)
  Remove(path: String)
  Replace(path: String, value: json_value.JsonValue)
  Copy(from: String, path: String)
  Move(from: String, path: String)
  Test(path: String, value: json_value.JsonValue)
}

pub fn patch_decoder() -> decode.Decoder(Patch) {
  use op <- decode.field("op", decode.string)

  case op {
    "add" -> {
      use path <- decode.field("path", decode.string)
      use value <- decode.field("value", json_value.decoder())
      decode.success(Add(path:, value:))
    }

    "remove" -> {
      use path <- decode.field("path", decode.string)
      decode.success(Remove(path:))
    }

    "replace" -> {
      use path <- decode.field("path", decode.string)
      use value <- decode.field("value", json_value.decoder())
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
      use value <- decode.field("value", json_value.decoder())
      decode.success(Test(path:, value:))
    }

    _ -> decode.failure(Copy("", ""), "Unknown op: '" <> op <> "'")
  }
}

pub fn patch(data: json_value.JsonValue, patches: List(Patch)) {
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

fn get_value(
  data: json_value.JsonValue,
  path: String,
) -> Result(json_value.JsonValue, String) {
  use tokens <- result.try(parse_path(path))
  navigate_get(data, tokens)
}

fn navigate_get(
  data: json_value.JsonValue,
  tokens: List(String),
) -> Result(json_value.JsonValue, String) {
  case tokens {
    [] -> Ok(data)
    [token, ..rest] -> {
      case data {
        json_value.Object(dict) -> {
          case dict.get(dict, token) {
            Ok(value) -> navigate_get(value, rest)
            Error(_) -> Error("path /" <> token <> " does not exist")
          }
        }
        json_value.Array(elements) -> {
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

fn add(data: json_value.JsonValue, path: String, value: json_value.JsonValue) {
  use tokens <- result.try(parse_path(path))
  navigate_set(data, tokens, value, AddMode, True)
}

type SetMode {
  AddMode
  ReplaceMode
}

fn navigate_set(
  data: json_value.JsonValue,
  tokens: List(String),
  value: json_value.JsonValue,
  mode: SetMode,
  is_add: Bool,
) -> Result(json_value.JsonValue, String) {
  case tokens {
    [] -> Ok(value)
    [token] -> {
      case data {
        json_value.Object(d) -> {
          let new_dict = dict.insert(d, token, value)
          Ok(json_value.Object(new_dict))
        }
        json_value.Array(elements) -> {
          case token {
            "-" -> {
              let new_array = list.append(elements, [value])
              Ok(json_value.Array(new_array))
            }
            _ -> {
              case has_leading_zero(token) {
                True -> Error("invalid array index: " <> token)
                False -> {
                  case int.parse(token) {
                    Ok(index) -> {
                      case insert_at_index(elements, index, value, mode) {
                        Ok(new_array) -> Ok(json_value.Array(new_array))
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
        json_value.Object(d) -> {
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
              Ok(json_value.Object(new_dict))
            }
            Error(_) ->
              case is_add {
                True -> Error("add to a non-existent target")
                False -> Error("path does not exist")
              }
          }
        }
        json_value.Array(elements) -> {
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
                        Ok(new_array) -> Ok(json_value.Array(new_array))
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

fn remove(data: json_value.JsonValue, path: String) {
  use tokens <- result.try(parse_path(path))
  navigate_remove(data, tokens)
}

fn navigate_remove(
  data: json_value.JsonValue,
  tokens: List(String),
) -> Result(json_value.JsonValue, String) {
  case tokens {
    [] -> Error("cannot remove root")
    [token] -> {
      case data {
        json_value.Object(d) -> {
          case dict.has_key(d, token) {
            True -> {
              let new_dict = dict.delete(d, token)
              Ok(json_value.Object(new_dict))
            }
            False -> Error("path does not exist")
          }
        }
        json_value.Array(elements) -> {
          case has_leading_zero(token) {
            True -> Error("invalid array index: " <> token)
            False -> {
              case int.parse(token) {
                Ok(index) -> {
                  case remove_at_index(elements, index) {
                    Ok(new_array) -> Ok(json_value.Array(new_array))
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
        json_value.Object(d) -> {
          case dict.get(d, token) {
            Ok(nested) -> {
              use new_nested <- result.try(navigate_remove(nested, rest))
              let new_dict = dict.insert(d, token, new_nested)
              Ok(json_value.Object(new_dict))
            }
            Error(_) -> Error("path does not exist")
          }
        }
        json_value.Array(elements) -> {
          case int.parse(token) {
            Ok(index) -> {
              case get_at_index(elements, index) {
                Ok(nested) -> {
                  use new_nested <- result.try(navigate_remove(nested, rest))
                  case replace_at_index(elements, index, new_nested) {
                    Ok(new_array) -> Ok(json_value.Array(new_array))
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

fn replace(
  data: json_value.JsonValue,
  path: String,
  value: json_value.JsonValue,
) {
  use tokens <- result.try(parse_path(path))
  navigate_set(data, tokens, value, ReplaceMode, False)
}

fn copy(data: json_value.JsonValue, from: String, path: String) {
  use from_value <- result.try(get_value(data, from))
  add(data, path, from_value)
}

fn move(data: json_value.JsonValue, from: String, path: String) {
  use from_value <- result.try(get_value(data, from))
  use after_remove <- result.try(remove(data, from))
  add(after_remove, path, from_value)
}

fn test_(data: json_value.JsonValue, path: String, value: json_value.JsonValue) {
  use found_value <- result.try(get_value(data, path))
  case found_value == value {
    True -> Ok(data)
    False -> Error("values not equivalent")
  }
}

fn do_patch_iter(acc: json_value.JsonValue, patches: List(Patch)) {
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
