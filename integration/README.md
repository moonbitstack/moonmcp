# moonmcp-ecosystem

The parts of moonmcp that need a program around them: a server for the
documentation page to sit beside, the server the official conformance suite
drives, and the test that reaches a server over a socket. They are a module of
their own so that a program using the library does not download an HTTP server
for the sake of an example.

```bash
cd integration && moon run src/02-http --target native
cd integration && moon run src/07-conformance --target native
cd integration && moon test src/http --target native
```
