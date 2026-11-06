// A verifier drawn from the system's entropy. Only a backend that has one can
// do this, so the test lives where the source does.

///|
test "a fresh pair is a verifier of the allowed length and its own digest" {
  let pkce = @auth.Pkce::new() catch {
    @auth.Refused(message~) => fail(message)
  }
  assert_eq(pkce.verifier.length(), 43)
  assert_eq(@auth.Pkce::of(pkce.verifier).challenge, pkce.challenge)
}

///|
test "two verifiers in a row are not the same" {
  let first = @auth.Pkce::new() catch {
    @auth.Refused(message~) => fail(message)
  }
  let second = @auth.Pkce::new() catch {
    @auth.Refused(message~) => fail(message)
  }
  assert_eq(first.verifier == second.verifier, false)
}
