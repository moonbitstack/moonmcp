test "image helper derives mime types" {
  let image = @utilities.Image::new(data=b"pngdata", format="jpg")
  assert_eq(image.mime_type, "image/jpeg")
  let both_missing : Result[@utilities.Image, @exceptions.FastMCPError] = try {
    Ok(@utilities.Image::new())
  } catch {
    e => Err(e)
  }
  assert_true(both_missing is Err(_))
}

test "image converts to image content block" {
  let ann : @types.Annotations = { audience: None, priority: None }
  let image = @utilities.Image::new(
    data=b"rawbytes",
    annotations=ann,
  )
  assert_eq(image.mime_type, "image/png")
  let block = image.to_image_content()
  assert_eq(block, @types.Image(
    data="cmF3Ynl0ZXM=",
    mime_type="image/png",
    annotations=Some(ann),
    meta=None,
  ))
  let data_uri = image.to_data_uri()
  assert_eq(data_uri, "data:image/png;base64,cmF3Ynl0ZXM=")
}

test "audio helper derives mime types" {
  let audio = @utilities.Audio::new(data=b"...", format="mp3")
  assert_eq(audio.mime_type, "audio/mpeg")
  let block = audio.to_audio_content(mime_type="audio/wav")
  guard block is @types.Audio(data~, mime_type~) else {
    fail("expected audio block")
  }
  assert_eq(data, "Li4u")
  assert_eq(mime_type, "audio/wav")
}

test "file helper builds embedded resources" {
  let file = @utilities.File::new(
    data=b"plain text",
    format="txt",
    name="readme",
  )
  assert_eq(file.mime_type, "text/plain")
  let block = file.to_resource_content()
  guard block is @types.EmbeddedResource(resource~, ..) else {
    fail("expected embedded resource")
  }
  guard resource is @types.Text(text~, uri~, mime_type~) else {
    fail("expected text resource contents")
  }
  assert_eq(text, "plain text")
  assert_eq(uri, "file:///readme.txt")
  assert_eq(mime_type, Some("text/plain"))
}

test "file helper emits blob content for non-text mime types" {
  let file = @utilities.File::new(data=b"\x00\x01", format="bin")
  let block = file.to_resource_content()
  guard block is @types.EmbeddedResource(resource~, ..) else {
    fail("expected embedded resource")
  }
  guard resource is @types.Blob(blob~, ..) else {
    fail("expected blob contents")
  }
  assert_eq(blob, "AAE=")
}

test "path-only helpers reject on data access" {
  let image = @utilities.Image::new(path="/tmp/img.png")
  let failed : Result[@types.ContentBlock, @exceptions.FastMCPError] = try {
    Ok(image.to_image_content())
  } catch {
    e => Err(e)
  }
  assert_true(failed is Err(_))
}
