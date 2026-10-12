defmodule MultipartValidationTest do
  use ExUnit.Case, async: true

  alias Multipart.Part

  @boundary "==testboundary=="

  test "explicit filenames are escaped in both file constructors" do
    filename = "report\"\r\nX-Review-Marker: present\\"
    path = Path.join(__DIR__, "files/test.txt")

    parts = [
      Part.file_field(path, :document, [], filename: filename, content_type: false),
      Part.file_content_field(path, "body", :document, [],
        filename: filename,
        content_type: false
      )
    ]

    for part <- parts do
      multipart = Multipart.new(@boundary) |> Multipart.add_part(part)
      output = Multipart.body_binary(multipart)

      assert output =~ "filename=\"report%22%0D%0AX-Review-Marker: present%5C\""
      refute output =~ "\r\nX-Review-Marker: present"
      assert Enum.join(Multipart.body_stream(multipart)) == output
      assert Multipart.content_length(multipart) == byte_size(output)
    end
  end

  test "CR and LF are rejected separately in raw header names and values" do
    for line_break <- ["\r", "\n"],
        headers <- [
          [{"x-custom#{line_break}x-extra", "value"}],
          [{"x-custom", "value#{line_break}x-extra: value"}]
        ] do
      multipart =
        Multipart.new(@boundary)
        |> Multipart.add_part(Part.binary_body("body", headers))

      assert_raise ArgumentError, fn -> Multipart.body_binary(multipart) end
      assert_raise ArgumentError, fn -> Enum.to_list(Multipart.body_stream(multipart)) end
      assert_raise ArgumentError, fn -> Multipart.content_length(multipart) end
    end
  end

  test "an explicit content type cannot add a part header" do
    multipart =
      Multipart.new(@boundary)
      |> Multipart.add_part(
        Part.file_content_field("report.txt", "body", "document", [],
          content_type: "text/plain\r\nX-Review-Marker: present"
        )
      )

    assert_raise ArgumentError, fn -> Multipart.body_binary(multipart) end
    assert_raise ArgumentError, fn -> Multipart.content_length(multipart) end
  end

  test "boundary length limits match the upstream validator" do
    for length <- [1, 70] do
      boundary = String.duplicate("a", length)
      assert %Multipart{boundary: ^boundary} = Multipart.new(boundary)
    end

    for boundary <- ["", String.duplicate("a", 71), "a\r", "a\n", "a b", "a "] do
      assert_raise ArgumentError, fn -> Multipart.new(boundary) end
    end
  end

  test "ordinary Unicode values and percent signs are preserved" do
    multipart =
      Multipart.new(@boundary)
      |> Multipart.add_part(
        Part.file_content_field("report.txt", "body\r\n", "dati-à", [],
          filename: "caffè-100%.txt",
          content_type: "text/plain"
        )
      )

    output = Multipart.body_binary(multipart)
    assert output =~ "name=\"dati-à\"; filename=\"caffè-100%.txt\""
    assert output =~ "content-type: text/plain\r\n"
    assert output =~ "\r\n\r\nbody\r\n"
    assert Multipart.content_length(multipart) == byte_size(output)
  end
end
