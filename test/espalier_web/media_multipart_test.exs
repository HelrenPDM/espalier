defmodule EspalierWeb.MediaMultipartTest do
  @moduledoc """
  The parser of the media upload (task 0018, step 15) through the route
  `POST /api/admin/media`: a part after `file` answers 422 and its
  temporary file is gone before the action, a part `file` with an empty
  file name answers `fields.file` `["invalid_type"]`, a malformed body
  answers 400, part headers above 16 KiB answer 413 (ASVS 5.2.1), and
  neither answer leaves the cookie, the CSRF token or the session in the
  log or in the raised error (ASVS 16.2.5). An ENOSPC while the body
  streams answers 409 `storage_full`, also to a client that sends a body
  beyond the 8,000,000 bytes that Bandit drains, over a real socket; an
  EDQUOT counts as an ENOSPC, and any other error of the file system
  answers 500. Direct calls of `parse/5` show that an unknown exception
  becomes a parse error without its message and without the arguments of
  its stack frames.
  """
  use EspalierWeb.ConnCase, async: true

  import ExUnit.CaptureLog
  import Espalier.CredentialsFixtures, only: [user_with_role_fixture: 1]

  alias Espalier.Media.{Asset, ProcessWorker}
  alias Espalier.Repo
  alias Espalier.Test.FunctionPlug
  alias EspalierWeb.MediaMultipart
  alias Plug.Conn.Cookies

  @moduletag :tmp_dir

  # The leading bytes of a PNG; no request of this module reaches the ingest.
  @png <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, "not a whole image">>

  defmodule RaisingAdapter do
    @moduledoc """
    The body read of a conn for the direct calls of `parse/5`: a
    CaseClauseError whose term holds the state, as one over a conn would,
    and a FunctionClauseError for any other state, whose top stack frame
    holds the arguments.
    """
    def read_req_body({:case_clause, secret}, _opts), do: raise(CaseClauseError, term: secret)
  end

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_with_role_fixture(:author))}
  end

  describe "the parts" do
    test "a part after file answers 422 and the temporary file is gone before the action", %{
      conn: conn
    } do
      conn = post_upload(conn, multipart([file_part(@png), field_part("title", "Desk photo")]))

      assert json_response(conn, 422) == %{
               "error" => "validation_failed",
               "fields" => %{"title" => ["unexpected_field"]}
             }

      refute File.exists?(upload_path(conn))
      assert media_tmp_files() == []
      assert Repo.aggregate(Asset, :count) == 0
      assert all_enqueued(worker: ProcessWorker) == []
    end

    test "a part file with an empty file name answers 422 invalid_type", %{conn: conn} do
      conn = post_upload(conn, multipart([file_part("", "")]))

      assert json_response(conn, 422) == %{
               "error" => "validation_failed",
               "fields" => %{"file" => ["invalid_type"]}
             }

      assert media_tmp_files() == []
      assert Repo.aggregate(Asset, :count) == 0
    end
  end

  describe "malformed bodies" do
    test "an empty body and a body without its closing boundary answer 400 bad_request", %{
      conn: conn
    } do
      {content_type, _body} = multipart([file_part(@png)])

      for body <- [{content_type, ""}, multipart([file_part(@png)], close: false)] do
        %{answer: answer, log: log, secrets: secrets} = failing_upload(conn, 400, body)

        assert answer == %{"error" => "bad_request"}
        refute Enum.any?(secrets, &String.contains?(log, &1))
        assert media_tmp_files() == []
      end

      assert Repo.aggregate(Asset, :count) == 0
    end

    test "part headers above 16 KiB answer 413 without the credentials in the log", %{
      conn: conn
    } do
      long = String.duplicate("a", 20_000)

      for parts <- [
            [file_part(@png, long <> ".png")],
            [file_part(@png), field_part("title", "Desk photo", ~s(; note="#{long}"))]
          ] do
        %{answer: answer, log: log, secrets: secrets} =
          failing_upload(conn, 413, multipart(parts))

        assert answer == %{"error" => "request_too_large"}
        refute Enum.any?(secrets, &String.contains?(log, &1))
        assert media_tmp_files() == []
      end

      assert Repo.aggregate(Asset, :count) == 0
    end

    test "an unknown exception becomes a parse error without its message and frame arguments" do
      secret = "secret-#{System.unique_integer([:positive])}"

      for state <- [{:case_clause, secret}, {:no_clause, secret}] do
        conn = %Plug.Conn{
          adapter: {RaisingAdapter, state},
          req_headers: [{"content-type", "multipart/form-data; boundary=B"}]
        }

        {error, stacktrace} =
          try do
            MediaMultipart.parse(conn, "multipart", "form-data", %{}, [])
          rescue
            error -> {error, __STACKTRACE__}
          end

        assert %Plug.Parsers.ParseError{plug_status: 400} = error
        refute Exception.format(:error, error, stacktrace) =~ secret
      end
    end
  end

  describe "a full volume" do
    test "an ENOSPC while the body streams answers 409 storage_full", %{conn: conn} do
      # /dev/full answers every write with ENOSPC. A small body fails at the
      # close of the delayed write, a body above its buffer at the write,
      # and a body above one read at the write of the first read.
      Process.put({MediaMultipart, :sink}, "/dev/full")

      for content <- [@png, :binary.copy("x", 100_000), :binary.copy("x", 1_048_576 + 1)] do
        conn = post_upload(conn, multipart([file_part(content)]))
        assert json_response(conn, 409) == %{"error" => "storage_full"}
        assert media_tmp_files() == []
      end

      assert Repo.aggregate(Asset, :count) == 0
      assert all_enqueued(worker: ProcessWorker) == []
    end

    test "after a full volume the parser reads the rest of the part, so the 409 reaches a client that still sends" do
      parsers = Plug.Parsers.init(parsers: [MediaMultipart], pass: [])

      port =
        serve(fn conn ->
          Process.put({MediaMultipart, :sink}, "/dev/full")
          conn = Plug.Parsers.call(conn, parsers)
          status = if conn.body_params["file"] == "storage_full", do: 409, else: 500
          Plug.Conn.send_resp(conn, status, "")
        end)

      # 16 MiB: more than the first read of the parser, the 8,000,000 bytes
      # that Bandit reads of a body that the action left unread, and the
      # small socket buffers of both ends together, so a parser that stops
      # reading makes a send fail with the reset of the connection.
      {content_type, body} = multipart([file_part(:binary.copy("x", 16 * 1_048_576))])

      {:ok, socket} =
        :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false, sndbuf: 16_384], 5_000)

      on_exit(fn -> :gen_tcp.close(socket) end)

      head =
        "POST /api/admin/media HTTP/1.1\r\nhost: localhost\r\n" <>
          "content-type: #{content_type}\r\ncontent-length: #{byte_size(body)}\r\n\r\n"

      assert send_in_chunks(socket, head <> body) == :ok
      assert {:ok, "HTTP/1.1 409 Conflict\r\n" <> _rest} = :gen_tcp.recv(socket, 0, 10_000)
    end

    test "an exhausted disk quota counts as a full volume" do
      # No test can exhaust a disk quota, so the reasons go to the function
      # that reads the result of every operation on the temporary file.
      for reason <- [:enospc, :edquot] do
        assert MediaMultipart.file_result({:error, reason}, "write to", "/tmp/media-x") ==
                 :storage_full
      end

      assert_raise File.Error, ~r/could not write to "\/tmp\/media-x": permission denied/, fn ->
        MediaMultipart.file_result({:error, :eacces}, "write to", "/tmp/media-x")
      end

      assert MediaMultipart.file_result(:ok, "close", "/tmp/media-x") == :ok
      assert MediaMultipart.file_result({:ok, :file}, "open", "/tmp/media-x") == {:ok, :file}
    end

    test "any other error of the file system answers 500", %{conn: conn, tmp_dir: tmp_dir} do
      # A directory cannot be opened for writing (EISDIR).
      Process.put({MediaMultipart, :sink}, tmp_dir)

      %{answer: answer} = failing_upload(conn, 500, multipart([file_part(@png)]))

      assert answer == %{"error" => "internal_error"}
      assert media_tmp_files() == []
    end
  end

  ## Helpers

  # Starts Bandit on an ephemeral port with `fun` as the plug and returns
  # the port, so that a client sends the body over a real socket.
  # The receive buffer of 64 KiB turns off its automatic growth, which
  # could hold most of a test body.
  defp serve(fun) do
    options = [
      plug: {FunctionPlug, fun},
      ip: :loopback,
      port: 0,
      startup_log: false,
      thousand_island_options: [transport_options: [recbuf: 65_536]]
    ]

    pid = start_supervised!({Bandit, options}, id: make_ref())
    {:ok, {_address, port}} = ThousandIsland.listener_info(pid)
    port
  end

  # Sends `data` in blocks of 64 KiB, so that a send waits while the server
  # reads and fails once the server has closed the connection. A single
  # send of all the data would return once the data is queued.
  defp send_in_chunks(socket, data) when byte_size(data) <= 65_536,
    do: :gen_tcp.send(socket, data)

  defp send_in_chunks(socket, <<chunk::binary-size(65_536), rest::binary>>) do
    with :ok <- :gen_tcp.send(socket, chunk), do: send_in_chunks(socket, rest)
  end

  defp post_upload(conn, {content_type, body}) do
    conn
    |> with_csrf_token()
    |> put_req_header("content-type", content_type)
    |> dispatch(@endpoint, :post, "/api/admin/media", body)
  end

  # Sends an upload that the error view answers with `status` and that then
  # raises. Returns the decoded answer, the log of the request together
  # with the text that Bandit logs for the raised error (Exception.format/3,
  # for the statuses 500 to 599), and the values that neither may hold: the
  # cookie values, the CSRF token and the session key of the token.
  defp failing_upload(conn, status, {content_type, body}) do
    conn = conn |> with_csrf_token() |> put_req_header("content-type", content_type)

    cookies =
      conn
      |> get_req_header("cookie")
      |> Enum.flat_map(&(&1 |> Cookies.decode() |> Map.values()))

    assert cookies != []

    log =
      capture_log(fn ->
        {^status, _headers, answer} =
          assert_error_sent(status, fn ->
            try do
              dispatch(conn, @endpoint, :post, "/api/admin/media", body)
            rescue
              error ->
                send(self(), {:raised, Exception.format(:error, error, __STACKTRACE__)})
                reraise error, __STACKTRACE__
            end
          end)

        send(self(), {:answer, JSON.decode!(answer)})
      end)

    assert_received {:raised, raised}
    assert_received {:answer, answer}

    %{
      answer: answer,
      log: log <> raised,
      secrets: cookies ++ get_req_header(conn, "x-csrf-token") ++ ["user_token"]
    }
  end

  # A multipart/form-data body of `parts`; `close: false` leaves out the
  # closing boundary.
  defp multipart(parts, opts \\ []) do
    boundary = "espalier-test-#{System.unique_integer([:positive])}"

    body =
      IO.iodata_to_binary([
        for {headers, content} <- parts do
          ["--", boundary, "\r\n", Enum.map(headers, &[&1, "\r\n"]), "\r\n", content, "\r\n"]
        end,
        if(Keyword.get(opts, :close, true), do: ["--", boundary, "--\r\n"], else: [])
      ])

    {"multipart/form-data; boundary=" <> boundary, body}
  end

  defp file_part(content, filename \\ "photo.png") do
    {[
       ~s(Content-Disposition: form-data; name="file"; filename="#{filename}"),
       "Content-Type: application/octet-stream"
     ], content}
  end

  defp field_part(name, content, params \\ "") do
    {[~s(Content-Disposition: form-data; name="#{name}") <> params], content}
  end

  # The temporary file of the part, from the parameters of the request.
  defp upload_path(conn) do
    conn.body_params
    |> Map.values()
    |> Enum.find_value(fn
      %Plug.Upload{path: path} -> path
      _other -> nil
    end) || flunk("no upload in the request")
  end

  # The temporary files of the parser in the upload directory of this test
  # process, for the answers whose conn the test does not see.
  defp media_tmp_files do
    dir = "probe" |> Plug.Upload.random_file!() |> Path.dirname()
    dir |> File.ls!() |> Enum.filter(&String.starts_with?(&1, "media-"))
  end
end
