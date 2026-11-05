// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "a loopback listener answers to loopback names only" {
  let bound = Some(("127.0.0.1", Some(12000)))
  assert_true(host_allowed(Some("127.0.0.1:12000"), None, bound))
  assert_true(host_allowed(Some("localhost:12000"), None, bound))
  assert_true(host_allowed(Some("localhost"), None, bound))
  assert_true(host_allowed(Some("[::1]:12000"), None, bound))
  assert_false(host_allowed(Some("evil.example"), None, bound))
  assert_false(host_allowed(Some("evil.example:12000"), None, bound))
  // A name that merely starts like a loopback one.
  assert_false(host_allowed(Some("localhost.evil.example"), None, bound))
  assert_true(host_allowed(Some("[::1]"), None, Some(("::1", None))))
  assert_false(host_allowed(Some("evil.example"), None, Some(("::1", None))))
}

///|
test "a listener anywhere else takes any host, since it cannot know its names" {
  let bound = Some(("0.0.0.0", Some(12000)))
  assert_true(host_allowed(Some("evil.example"), None, bound))
  assert_true(host_allowed(Some("evil.example"), None, None))
}

///|
test "hosts, once named, are all there is, wherever the server listens" {
  let hosts = Some(["api.example"])
  let loopback = Some(("127.0.0.1", Some(12000)))
  assert_true(host_allowed(Some("api.example"), hosts, loopback))
  assert_true(host_allowed(Some("api.example:443"), hosts, loopback))
  assert_false(host_allowed(Some("localhost"), hosts, loopback))
  assert_false(
    host_allowed(Some("evil.example"), hosts, Some(("0.0.0.0", None))),
  )
  // Naming one with its port asks for that port.
  let exact = Some(["api.example:8443"])
  assert_true(host_allowed(Some("api.example:8443"), exact, None))
  assert_false(host_allowed(Some("api.example:443"), exact, None))
}

///|
test "a request with no Host has nothing to check" {
  assert_true(host_allowed(None, None, Some(("127.0.0.1", None))))
  assert_true(host_allowed(None, Some(["a"]), None))
}
