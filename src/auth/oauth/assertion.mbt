// A client's own assertion at the token endpoint (RFC 7523): instead of a
// shared secret it signs a short-lived JWT with a private key it holds, and the
// authorization server checks it against the public half.

///|
/// The signing key a client authenticates with. Only ES256 is offered — the
/// curve every authorization server that speaks JWT client authentication
/// supports.
pub struct Assertion {
  client_id : String
  key : @ecdsa.PrivateKey
}

///|
/// The assertion for `client_id`, signed with the PKCS#8 PEM in
/// `private_key`: the form `openssl genpkey -algorithm EC` writes.
pub fn Assertion::es256(
  client_id~ : String,
  private_key~ : String,
) -> Assertion raise @auth.Refused {
  let key = @ecdsa.PrivateKey::new(scalar_of(private_key), curve=@curve.P256) catch {
    e => raise @auth.Refused(message="the private key does not read: \{e}")
  }
  { client_id, key, }
}

///|
/// The token request's fields: the assertion type, and the assertion itself,
/// minted for `audience` at `now` and good for five minutes — the lifetime RFC
/// 7523 §3 suggests.
pub fn Assertion::form(
  self : Assertion,
  audience~ : String,
  now~ : Int64,
) -> Array[(String, String)] {
  let header : Map[String, Json] = {
    "alg": Json::string("ES256"),
    "typ": Json::string("JWT"),
  }
  let claims : Map[String, Json] = {
    "iss": Json::string(self.client_id),
    "sub": Json::string(self.client_id),
    "aud": Json::string(audience),
    "iat": Json::number(now.to_double()),
    "exp": Json::number((now + 300L).to_double()),
    "jti": Json::string(@auth.new_state() catch { _ => "0" }),
  }
  let signing_input = "\{segment(Json(header))}.\{segment(Json(claims))}"
  let signature = self.key.sign(@utf8.encode(signing_input)[:])
  [
    (
      "client_assertion_type", "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
    ),
    (
      "client_assertion",
      "\{signing_input}.\{@base64.encode(signature[:], kind=Url, padding=false)}",
    ),
  ]
}

///|
/// One JWT segment: the JSON in base64url without padding.
fn segment(json : Json) -> String {
  @base64.encode(@utf8.encode(json.stringify())[:], kind=Url, padding=false)
}

///|
/// The private scalar of a PKCS#8 EC key:
/// `PrivateKeyInfo ::= SEQUENCE { version, algorithm, privateKey OCTET STRING }`,
/// whose payload is `ECPrivateKey ::= SEQUENCE { version, privateKey OCTET STRING, … }`.
fn scalar_of(pem : String) -> Bytes raise @auth.Refused {
  let body = StringBuilder::StringBuilder()
  for line in pem.split("\n") {
    let line = line.trim(chars=" \r\n").to_owned()
    if line.is_empty() || line.has_prefix("-----") {
      continue
    }
    body.write_string(line)
  }
  let der = @base64.decode(body.to_string(), kind=Std, padding=false) catch {
    _ => raise @auth.Refused(message="the private key is not base64")
  }
  let outer = @asn1.read(der[:]) catch {
    _ => raise @auth.Refused(message="the private key is not a PKCS#8 document")
  }
  let items = outer.items() catch {
    _ => raise @auth.Refused(message="the private key is not a PKCS#8 document")
  }
  guard items.length() >= 3 else {
    raise @auth.Refused(message="the private key is not a PKCS#8 document")
  }
  let inner = @asn1.read(items[2].octets()) catch {
    _ => raise @auth.Refused(message="the private key carries no EC key")
  }
  let parts = inner.items() catch {
    _ => raise @auth.Refused(message="the private key carries no EC key")
  }
  guard parts.length() >= 2 else {
    raise @auth.Refused(message="the private key carries no EC key")
  }
  let scalar = parts[1].octets() catch {
    _ => raise @auth.Refused(message="the private key carries no scalar")
  }
  scalar.to_owned()
}
