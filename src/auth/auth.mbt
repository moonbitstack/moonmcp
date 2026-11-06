// The bearer token an HTTP transport checks before it serves anything.
//
// A token arrives as `Authorization: Bearer …`; what it says is only worth
// reading once its signature has been checked, which is the order here: the
// token is verified first, and only a token that verified is asked who the
// caller is.

///|
/// The caller a token vouched for: its `sub`, and every claim as it arrived.
///
/// A claim is whatever the issuer put there — a scope list, a tenant, a role.
/// Nothing here interprets them; a handler reads what it needs.
#derive(Debug, Eq)
pub(all) struct Principal {
  subject : String?
  claims : Map[String, Json]
}

///|
pub extend Principal with Debug::{to_repr}

///|
pub extend Principal with Eq::{not_equal, equal}

///|
/// Whether the token grants `scope`, read from the `scope` claim (space
/// separated) or `scp` (a list), which are the two spellings in use.
pub fn Principal::has_scope(self : Principal, scope : String) -> Bool {
  let from_words = match self.claims.get("scope") {
    Some(String(scopes)) => scopes.split(" ").contains(scope)
    _ => false
  }
  if from_words {
    return true
  }
  match self.claims.get("scp") {
    Some(Array(scopes)) =>
      scopes.any(entry => entry is String(text) && text == scope)
    _ => false
  }
}

///|
/// How a transport checks a bearer token (← the authorization section of the
/// protocol): a request without one is answered `401` with a
/// `WWW-Authenticate` challenge, and one whose token does not verify is
/// answered the same way with `invalid_token`.
///
/// Two ways to build one: `Bearer::hmac` for a token signed with a shared
/// secret, which is what a test and a single-tenant deployment use, and
/// `Bearer::own` for anything else — an RSA or ECDSA key, a JSON Web Key Set
/// fetched from the issuer, an opaque token looked up in a table. `own` takes
/// the whole decision, so this library never has an opinion about how a token
/// is judged, only about what happens when it is not.
pub struct Bearer {
  priv check : (String) -> Result[Principal, String]
}

///|
/// Check tokens with `check`, which returns the caller or the reason the token
/// is refused. The reason travels to the client in `error_description`, so it
/// should say what is wrong without saying anything a stranger could use.
pub fn Bearer::own(check~ : (String) -> Result[Principal, String]) -> Bearer {
  { check, }
}

///|
/// Check tokens signed with `secret` by a shared key: `alg` is the algorithm
/// the verifier uses, and a token that names another one is refused rather
/// than trusted.
///
/// `issuer` and `audience` are checked when given, so a token minted for
/// another service does not open this one. `clock` is the instant in seconds
/// since the epoch that expiry is measured against, which a test fixes and a
/// deployment leaves alone.
pub fn Bearer::hmac(
  secret~ : String,
  alg~ : @jwt.Alg = HS256,
  issuer? : String,
  audience~ : Array[String] = [],
  leeway? : Int64,
  clock~ : () -> Int64 = fn() { wall_clock() },
) -> Bearer {
  let key = @jwt.mac(fn() {
    @hmac.Hmac::new(@utf8.encode(secret)[:], fn() { @sha2.Hasher::new() })
  })
  Bearer::own(check=fn(token) {
    let claims = @jwt.verify(
      token,
      alg,
      key,
      now=@jwt.At(clock()),
      issuer?,
      audience~,
      leeway?,
    ) catch {
      e => return Err(refusal_text(e))
    }
    let subject = match claims.get("sub") {
      Some(String(subject)) => Some(subject)
      _ => None
    }
    Ok({ subject, claims, })
  })
}

///|
/// Check the `Authorization` header of a request. `Err` carries the reason the
/// token is refused, phrased for the client.
pub fn Bearer::check(
  self : Bearer,
  authorization : String,
) -> Result[Principal, String] {
  let scheme = match authorization.find(" ") {
    Some(at) => authorization.exact_view(end=at).to_owned()
    None => return Err("the Authorization header carries no token")
  }
  if !scheme.equal_ignore_ascii_case("bearer") {
    return Err("the Authorization header is not a bearer token")
  }
  let token = authorization
    .exact_view(start=scheme.length() + 1)
    .to_owned()
    .trim(chars=" ")
    .to_owned()
  if token.is_empty() {
    return Err("the Authorization header carries no token")
  }
  (self.check)(token)
}

///|
/// Why a token did not verify, in words a client may read: the constructor
/// says what went wrong, and nothing else of the token appears.
fn refusal_text(e : @jwt.Refused) -> String {
  match e {
    Signature => "the token's signature does not verify"
    Expired(_) => "the token has expired"
    TooEarly(_) => "the token is not valid yet"
    Algorithm(want~, got~) =>
      "the token is signed with \{got}, this server expects \{want}"
    Issuer(want~, got~) =>
      "the token is issued by \{got}, this server expects \{want}"
    Audience(_) => "the token is not for this audience"
    Subject(want~, got~) =>
      "the token is for \{got}, this server expects \{want}"
    IssuedAt(_) => "the token was issued in the future"
    Type(want~, got~) =>
      "the token is of type \{got}, this server expects \{want}"
    Missing(claim~) => "the token has no \{claim} claim"
    _ => "the token is malformed"
  }
}

///|
/// Seconds since the epoch. The runtime's clock counts milliseconds, which is
/// also what `exp`, `iat` and `nbf` are measured in once they are seconds.
fn wall_clock() -> Int64 {
  @async.now() / 1_000L
}
