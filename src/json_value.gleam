import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/function
import gleam/json
import gleam/list
import gleam/pair

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

pub fn decoder() -> decode.Decoder(JsonValue) {
  use <- decode.recursive
  decode.one_of(decode.string |> decode.map(String), [
    int(),
    bool(),
    float(),
    array(),
    object(),
    decode.success(Null),
  ])
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

pub fn decode(value: JsonValue, decoder: decode.Decoder(a)) {
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

pub fn bool() {
  decode.bool |> decode.map(Bool)
}

pub fn float() {
  decode.float |> decode.map(Float)
}

pub fn int() {
  decode.int |> decode.map(Int)
}

pub fn array() {
  decode.list(decoder()) |> decode.map(Array)
}

pub fn object() {
  decode.dict(decode.string, decoder())
  |> decode.map(Object)
}

pub fn parse(raw: String) -> Result(JsonValue, json.DecodeError) {
  json.parse(raw, decoder())
}

pub fn to_string(value: JsonValue) -> String {
  value |> to_json |> json.to_string
}
