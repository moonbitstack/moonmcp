///|
/// Serve newline-delimited JSON-RPC: read a line with `read` until it gives
/// `None`, answer it, and `write` the reply as one line (← the stdio
/// transport, over any pair of streams). A line that is not JSON is answered
/// with a parse error; a blank one is skipped.
///
/// Requests are answered one at a time, in the order they arrive.
pub async fn Server::serve_lines(
  self : Server,
  read : async () -> String?,
  write : async (String) -> Unit,
) -> Unit {
  while read() is Some(line) {
    let line = line.trim(chars=" \t\r\n").to_owned()
    if line.is_empty() {
      continue
    }
    let message = @json.parse(line) catch {
      _ => {
        write(
          refusal(Json::null(), fail(parse_error, "Parse error")).1.stringify(),
        )
        continue
      }
    }
    if self.answer(message) is Some((_, reply)) {
      write(reply.stringify())
    }
  }
}
