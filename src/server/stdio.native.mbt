///|
/// Serve over the process's standard input and output (← FastMCP's
/// `run(transport="stdio")`): one message per line each way, until standard
/// input closes. Anything else the program prints belongs on standard error,
/// since standard output carries nothing but messages.
pub async fn Server::run_stdio(self : Server) -> Unit {
  self.serve_lines(() => @stdio.stdin.read_until("\n"), line => {
    @stdio.stdout.write(line + "\n")
  })
}
