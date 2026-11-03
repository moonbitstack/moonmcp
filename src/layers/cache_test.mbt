///|
fn counting_call(name : String, arguments : Map[String, Json]) -> @layers.Call {
  @layers.Call::new(
    operation=@layers.CallTool,
    name~,
    arguments~,
    context=@context.Context::quiet(),
  )
}

///|
/// A server that records every call that reached it and answers with the name.
#warnings("-unused_async")
async fn count_them(
  reached : Array[String],
  call : @layers.Call,
) -> Json raise @exceptions.FastMCPError {
  reached.push(call.name)
  if call.name == "boom" {
    raise @exceptions.Tool("the call the test server refuses")
  }
  Json::string(call.name)
}

///|
async test "a repeated call is answered from the cache" {
  let cache = @layers.Caching::new()
  let reached : Array[String] = []
  let layers = [cache.layer()]
  let call = counting_call("add", { "a": 1 })
  for _ in 0..<3 {
    let answer = @layers.chain(layers, call, async fn(
      call,
    ) -> Json raise @exceptions.FastMCPError {
      count_them(reached, call)
    })
    assert_eq(answer.stringify(), "\"add\"")
  }
  assert_eq(reached.length(), 1)
  assert_eq(cache.hits(), 2)
  assert_eq(cache.misses(), 1)
}

///|
async test "arguments in another order hit the same stored answer" {
  let cache = @layers.Caching::new()
  let reached : Array[String] = []
  let layers = [cache.layer()]
  let cases : Array[Map[String, Json]] = [
    { "a": 1, "b": 2 },
    { "b": 2, "a": 1 },
  ]
  for arguments in cases {
    ignore(
      @layers.chain(layers, counting_call("add", arguments), async fn(
        call,
      ) -> Json raise @exceptions.FastMCPError {
        count_them(reached, call)
      }),
    )
  }
  assert_eq(reached.length(), 1)
  assert_eq(cache.hits(), 1)
}

///|
async test "different arguments are different answers" {
  let cache = @layers.Caching::new()
  let reached : Array[String] = []
  let layers = [cache.layer()]
  let cases : Array[Map[String, Json]] = [{ "a": 1 }, { "a": 2 }]
  for arguments in cases {
    ignore(
      @layers.chain(layers, counting_call("add", arguments), async fn(
        call,
      ) -> Json raise @exceptions.FastMCPError {
        count_them(reached, call)
      }),
    )
  }
  assert_eq(reached.length(), 2)
  assert_eq(cache.misses(), 2)
}

///|
/// An answer a failing tool gives, or an ask for client input: the cache must
/// keep neither.
#warnings("-unused_async")
async fn awkward(kind : Int32) -> Json raise @exceptions.FastMCPError {
  let no_content : Array[Json] = []
  if kind < 0 {
    raise @exceptions.Tool("a negative kind")
  }
  if kind == 0 {
    { "content": Json(no_content), "isError": Json::boolean(true) }
  } else {
    { "content": Json(no_content), "requestState": Json::string("leg-1") }
  }
}

///|
async test "an error result is not stored" {
  let cache = @layers.Caching::new()
  let mut reached = 0
  let layers = [cache.layer()]
  for _ in 0..<2 {
    let answer = @layers.chain(layers, counting_call("add", Map([])), async fn(
      _call,
    ) -> Json raise @exceptions.FastMCPError {
      reached = reached + 1
      awkward(0)
    })
    assert_eq(answer.stringify(), "{\"content\":[],\"isError\":true}")
  }
  assert_eq(reached, 2)
  assert_eq(cache.size(), 0)
}

///|
async test "an ask for client input is not stored" {
  let cache = @layers.Caching::new()
  let mut reached = 0
  let layers = [cache.layer()]
  for _ in 0..<2 {
    ignore(
      @layers.chain(layers, counting_call("ask", Map([])), async fn(
        _call,
      ) -> Json raise @exceptions.FastMCPError {
        reached = reached + 1
        awkward(1)
      }),
    )
  }
  assert_eq(reached, 2)
  assert_eq(cache.size(), 0)
}

///|
async test "an answer stops being good when its time is up" {
  let cache = @layers.Caching::new(ttl_ms=0)
  let reached : Array[String] = []
  let layers = [cache.layer()]
  for _ in 0..<2 {
    ignore(
      @layers.chain(layers, counting_call("add", Map([])), async fn(
        call,
      ) -> Json raise @exceptions.FastMCPError {
        count_them(reached, call)
      }),
    )
  }
  assert_eq(reached.length(), 2)
  assert_eq(cache.hits(), 0)
}

///|
async test "the oldest answer goes when the cache is full" {
  let cache = @layers.Caching::new(capacity=1)
  let reached : Array[String] = []
  let layers = [cache.layer()]
  for name in ["add", "add", "sum", "add"] {
    ignore(
      @layers.chain(layers, counting_call(name, Map([])), async fn(
        call,
      ) -> Json raise @exceptions.FastMCPError {
        count_them(reached, call)
      }),
    )
  }
  assert_eq(reached.join(","), "add,sum,add")
  assert_eq(cache.size(), 1)
}

///|
async test "one caller's answer is not another's unless the cache is shared" {
  let private_cache = @layers.Caching::new()
  let shared_cache = @layers.Caching::new(shared=true)
  let reached : Array[String] = []
  for cache in [private_cache, shared_cache] {
    for subject in ["alice", "bob"] {
      let context = @context.Context::new(facts=@context.Facts::new(subject~))
      let call = @layers.Call::new(
        operation=@layers.CallTool,
        name="add",
        arguments=Map([]),
        context~,
      )
      ignore(
        @layers.chain([cache.layer()], call, async fn(
          call,
        ) -> Json raise @exceptions.FastMCPError {
          count_them(reached, call)
        }),
      )
    }
  }
  // Two callers, two caches: the private one asked twice, the shared one once.
  assert_eq(reached.length(), 3)
  assert_eq(private_cache.hits(), 0)
  assert_eq(shared_cache.hits(), 1)
}

///|
async test "a listing is cached too, and a listing call is not" {
  let cache = @layers.Caching::new()
  let reached : Array[String] = []
  let layers = [cache.layer()]
  let listing = @layers.Call::new(
    operation=@layers.ListTools,
    name="",
    context=@context.Context::quiet(),
  )
  for _ in 0..<2 {
    ignore(
      @layers.chain(layers, listing, async fn(
        call,
      ) -> Json raise @exceptions.FastMCPError {
        count_them(reached, call)
      }),
    )
  }
  assert_eq(reached.length(), 1)
}

///|
async test "the cache takes only the operations it was given" {
  let cache = @layers.Caching::new(operations=[@layers.ListTools])
  let reached : Array[String] = []
  let layers = [cache.layer()]
  for _ in 0..<2 {
    ignore(
      @layers.chain(layers, counting_call("add", Map([])), async fn(
        call,
      ) -> Json raise @exceptions.FastMCPError {
        count_them(reached, call)
      }),
    )
  }
  assert_eq(reached.length(), 2)
  assert_eq(cache.misses(), 0)
}
