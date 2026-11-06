// Proof Key for Code Exchange (RFC 7636). The client keeps a verifier and sends
// only its SHA-256 digest with the authorization request, so a code stolen from
// the browser's address bar cannot be exchanged on its own.

///|
/// A PKCE pair: `verifier` goes in the token request, `challenge` in the
/// authorization request. Only S256 is used — the plain method protects
/// nothing, and the protocol requires S256 of every client that can do it.
#derive(Debug, Eq)
pub(all) struct Pkce {
  verifier : String
  challenge : String
}

///|
/// A fresh pair, from 32 bytes of entropy: 43 characters, which is the shortest
/// length RFC 7636 allows and enough to be unguessable.
pub fn Pkce::new() -> Pkce raise Refused {
  let bytes = FixedArray::make(32, b'\x00')
  let rng = @auto.rng() catch {
    _ => raise Refused(message="no entropy to draw a PKCE verifier from")
  }
  rng.fill(bytes)
  Pkce::of(@base64.encode(Bytes::from_array(bytes)[:], kind=Url, padding=false))
}

///|
/// The pair for a verifier already chosen: the challenge is its SHA-256 digest
/// in base64url, without padding.
pub fn Pkce::of(verifier : String) -> Pkce {
  let digest = @sha2.hash(@utf8.encode(verifier)[:])
  { verifier, challenge: @base64.encode(digest[:], kind=Url, padding=false), }
}

///|
pub extend Pkce with Debug::{to_repr}

///|
pub extend Pkce with Eq::{not_equal, equal}
