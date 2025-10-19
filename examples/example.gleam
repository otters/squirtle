import gleam/io
import squirtle

pub fn main() {
  io.println("")

  // Example 1: Simple string-based API
  io.println("1. Simple string-based API:")
  let doc1 = "{\"name\": \"John\", \"age\": 30}"
  let patches1 =
    "[
    {\"op\": \"replace\", \"path\": \"/name\", \"value\": \"Jane\"},
    {\"op\": \"add\", \"path\": \"/email\", \"value\": \"jane@example.com\"},
    {\"op\": \"remove\", \"path\": \"/age\"}
  ]"

  case squirtle.patch_string(doc1, patches1) {
    Ok(result) -> {
      io.println("  Input:  " <> doc1)
      io.println("  Output: " <> result)
    }
    Error(reason) -> io.println("  Error: " <> reason)
  }

  io.println("")

  // Example 2: Working with arrays
  io.println("2. Array operations:")
  let doc2 = "{\"users\": [\"Alice\", \"Bob\"]}"
  let patches2 =
    "[
    {\"op\": \"add\", \"path\": \"/users/-\", \"value\": \"Charlie\"},
    {\"op\": \"add\", \"path\": \"/users/1\", \"value\": \"Dave\"}
  ]"

  case squirtle.patch_string(doc2, patches2) {
    Ok(result) -> {
      io.println("  Input:  " <> doc2)
      io.println("  Output: " <> result)
    }
    Error(reason) -> io.println("  Error: " <> reason)
  }

  io.println("")

  // Example 3: Copy and move operations
  io.println("3. Copy and move:")
  let doc3 = "{\"name\": \"John\", \"address\": {\"city\": \"NYC\"}}"
  let patches3 =
    "[
    {\"op\": \"copy\", \"from\": \"/name\", \"path\": \"/username\"},
    {\"op\": \"move\", \"from\": \"/address/city\", \"path\": \"/city\"}
  ]"

  case squirtle.patch_string(doc3, patches3) {
    Ok(result) -> {
      io.println("  Input:  " <> doc3)
      io.println("  Output: " <> result)
    }
    Error(reason) -> io.println("  Error: " <> reason)
  }

  io.println("")

  // Example 4: Test operation
  io.println("4. Test operation (success):")
  let doc4 = "{\"name\": \"John\"}"
  let patches4 =
    "[
    {\"op\": \"test\", \"path\": \"/name\", \"value\": \"John\"},
    {\"op\": \"replace\", \"path\": \"/name\", \"value\": \"Jane\"}
  ]"

  case squirtle.patch_string(doc4, patches4) {
    Ok(result) -> {
      io.println("  Input:  " <> doc4)
      io.println("  Output: " <> result)
    }
    Error(reason) -> io.println("  Error: " <> reason)
  }

  io.println("")

  // Example 5: Test operation failure
  io.println("5. Test operation (failure):")
  let doc5 = "{\"name\": \"John\"}"
  let patches5 =
    "[
    {\"op\": \"test\", \"path\": \"/name\", \"value\": \"Jane\"},
    {\"op\": \"replace\", \"path\": \"/name\", \"value\": \"Bob\"}
  ]"

  case squirtle.patch_string(doc5, patches5) {
    Ok(result) -> {
      io.println("  Input:  " <> doc5)
      io.println("  Output: " <> result)
    }
    Error(reason) -> io.println("  Error: " <> reason)
  }

  io.println("")

  // Example 6: Programmatic API
  io.println("6. Programmatic API:")
  let assert Ok(doc6) = squirtle.json_value_parse("{\"count\": 0}")

  let patches6 = [
    squirtle.Replace(path: "/count", value: squirtle.Int(42)),
    squirtle.Add(path: "/active", value: squirtle.Bool(True)),
  ]

  case squirtle.patch(doc6, patches6) {
    Ok(result) -> {
      io.println("  Input:  {\"count\": 0}")
      io.println("  Output: " <> squirtle.json_value_to_string(result))
    }
    Error(reason) -> io.println("  Error: " <> reason)
  }

  io.println("")

  // Example 7: Nested objects
  io.println("7. Nested object manipulation:")
  let doc7 = "{\"user\": {\"profile\": {\"name\": \"John\", \"age\": 30}}}"
  let patches7 =
    "[
    {\"op\": \"replace\", \"path\": \"/user/profile/name\", \"value\": \"Jane\"},
    {\"op\": \"add\", \"path\": \"/user/profile/email\", \"value\": \"jane@example.com\"},
    {\"op\": \"remove\", \"path\": \"/user/profile/age\"}
  ]"

  case squirtle.patch_string(doc7, patches7) {
    Ok(result) -> {
      io.println("  Input:  " <> doc7)
      io.println("  Output: " <> result)
    }
    Error(reason) -> io.println("  Error: " <> reason)
  }

  io.println("")
}
