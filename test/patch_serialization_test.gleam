import gleam/dict
import gleam/json
import gleeunit/should
import squirtle

pub fn patch_to_json_value_add_test() {
  let patch = squirtle.Add(path: "/name", value: squirtle.String("John"))
  let result = squirtle.patch_to_json_value(patch)

  result
  |> should.equal(
    squirtle.Object(
      dict.from_list([
        #("op", squirtle.String("add")),
        #("path", squirtle.String("/name")),
        #("value", squirtle.String("John")),
      ]),
    ),
  )
}

pub fn patch_to_json_value_remove_test() {
  let patch = squirtle.Remove(path: "/age")
  let result = squirtle.patch_to_json_value(patch)

  result
  |> should.equal(
    squirtle.Object(
      dict.from_list([
        #("op", squirtle.String("remove")),
        #("path", squirtle.String("/age")),
      ]),
    ),
  )
}

pub fn patch_to_json_value_replace_test() {
  let patch = squirtle.Replace(path: "/email", value: squirtle.String("new@example.com"))
  let result = squirtle.patch_to_json_value(patch)

  result
  |> should.equal(
    squirtle.Object(
      dict.from_list([
        #("op", squirtle.String("replace")),
        #("path", squirtle.String("/email")),
        #("value", squirtle.String("new@example.com")),
      ]),
    ),
  )
}

pub fn patch_to_json_value_copy_test() {
  let patch = squirtle.Copy(from: "/name", path: "/nickname")
  let result = squirtle.patch_to_json_value(patch)

  result
  |> should.equal(
    squirtle.Object(
      dict.from_list([
        #("op", squirtle.String("copy")),
        #("from", squirtle.String("/name")),
        #("path", squirtle.String("/nickname")),
      ]),
    ),
  )
}

pub fn patch_to_json_value_move_test() {
  let patch = squirtle.Move(from: "/old_name", path: "/new_name")
  let result = squirtle.patch_to_json_value(patch)

  result
  |> should.equal(
    squirtle.Object(
      dict.from_list([
        #("op", squirtle.String("move")),
        #("from", squirtle.String("/old_name")),
        #("path", squirtle.String("/new_name")),
      ]),
    ),
  )
}

pub fn patch_to_json_value_test_test() {
  let patch = squirtle.Test(path: "/status", value: squirtle.String("active"))
  let result = squirtle.patch_to_json_value(patch)

  result
  |> should.equal(
    squirtle.Object(
      dict.from_list([
        #("op", squirtle.String("test")),
        #("path", squirtle.String("/status")),
        #("value", squirtle.String("active")),
      ]),
    ),
  )
}

pub fn patch_to_string_test() {
  let patch = squirtle.Add(path: "/name", value: squirtle.String("John"))
  let result = squirtle.patch_to_string(patch)

  // Parse it back to verify it's valid JSON
  let assert Ok(parsed) = json.parse(result, squirtle.json_value_decoder())

  parsed
  |> should.equal(
    squirtle.Object(
      dict.from_list([
        #("op", squirtle.String("add")),
        #("path", squirtle.String("/name")),
        #("value", squirtle.String("John")),
      ]),
    ),
  )
}

pub fn round_trip_test() {
  // Create a patch, convert to string, parse back, and apply
  let patch = squirtle.Replace(path: "/name", value: squirtle.String("Jane"))
  let patch_string = squirtle.patch_to_string(patch)

  // Parse the patch back from string
  let assert Ok(parsed_patch) =
    json.parse(patch_string, squirtle.patch_decoder())

  // Verify the parsed patch is the same
  parsed_patch |> should.equal(patch)

  // Apply it to a document
  let doc =
    squirtle.Object(
      dict.from_list([#("name", squirtle.String("John"))]),
    )

  let assert Ok(result) = squirtle.patch(doc, [parsed_patch])

  result
  |> should.equal(
    squirtle.Object(
      dict.from_list([#("name", squirtle.String("Jane"))]),
    ),
  )
}
