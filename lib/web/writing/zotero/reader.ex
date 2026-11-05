defmodule Web.Writing.Zotero.Reader do
  @moduledoc """
  A Zotero document opened for reading: its PDF or EPUB, its annotations and its notes, read from and written back to the author's Zotero library.

  **Documents.** An item's readable attachments are its PDF and EPUB files
  stored in Zotero (`imported_file`, `imported_url`); a linked file lives
  only on some other machine and cannot be read from here. A standalone
  attachment (a PDF with no parent item) is its own document.

  **Files** are fetched from Zotero's storage once and kept in a private
  cache (`config :web, :zotero_cache_path`, default a folder under the
  system's temporary directory), named by attachment key and the file's MD5,
  so a file changed in Zotero is fetched again. They are served only to the
  admin (`WebWeb.ZoteroFileController`).

  **Annotations** are Zotero's own: a highlight or underline made here is
  an annotation item under the attachment, with the position and sort index
  Zotero's reader uses, so it shows in Zotero after a sync, and the ones made
  in Zotero show here.

    * PDF: `{"pageIndex": n, "rects": [[x1, y1, x2, y2], …]}` in PDF points,
      sort index `PPPPP|OOOOOO|TTTTT` (page, character offset, top).
    * EPUB: a `FragmentSelector` holding an EPUB CFI, sort index
      `SSSSS|CCCCCCCC` (section, character offset).

  **Notes** are child notes of the parent item (an attachment cannot hold
  them), written as escaped HTML paragraphs.
  """

  alias Web.Writing.Zotero

  @kinds %{"application/pdf" => :pdf, "application/epub+zip" => :epub}
  @stored ~w(imported_file imported_url)
  @key_re ~r/^[A-Z0-9]{8}$/
  @md5_re ~r/^[a-f0-9]{32}$/
  @pdf_sort_re ~r/^\d{5}\|\d{6}\|\d{5}$/
  @epub_sort_re ~r/^\d{5}\|\d{8}$/
  @cfi_conforms "http://www.idpf.org/epub/linking/cfi/epub-cfi.html"

  # Zotero's own eight annotation colours, in the order its reader offers them.
  @colors [
    {"yellow", "#ffd400"},
    {"red", "#ff6666"},
    {"green", "#5fb236"},
    {"blue", "#2ea8e5"},
    {"purple", "#a28ae5"},
    {"magenta", "#e56eee"},
    {"orange", "#f19837"},
    {"gray", "#aaaaaa"}
  ]
  @color_names Map.new(@colors, fn {name, hex} -> {hex, name} end)

  @type attachment :: %{
          key: String.t(),
          title: String.t(),
          filename: String.t() | nil,
          content_type: String.t(),
          kind: :pdf | :epub,
          md5: String.t() | nil,
          parent_key: String.t() | nil
        }

  @doc "Whether `key` is shaped like a Zotero item key (eight capitals and digits)."
  def key?(key), do: is_binary(key) and Regex.match?(@key_re, key)

  @doc "Whether `md5` is a file hash as Zotero gives it."
  def md5?(md5), do: is_binary(md5) and Regex.match?(@md5_re, md5)

  @doc "Zotero's annotation colours as `{name, hex}`."
  def colors, do: @colors

  @doc """
  The document `key` names: `{:ok, %{item, attachments, notes_key}}`, where
  `item` is the parent's metadata (`Web.Writing.Zotero.from_api/1`),
  `attachments` its readable files, and `notes_key` the item notes belong
  under (nil for a standalone attachment). The key of an attachment with a
  parent opens the parent, with that attachment first.
  """
  def document(key) do
    with true <- key?(key) || {:error, :not_found},
         {:ok, raw} <- get_item(key) do
      data = raw["data"] || %{}

      cond do
        data["itemType"] == "attachment" and is_binary(data["parentItem"]) ->
          with {:ok, doc} <- document(data["parentItem"]) do
            {first, rest} = Enum.split_with(doc.attachments, &(&1.key == key))
            {:ok, %{doc | attachments: first ++ rest}}
          end

        data["itemType"] == "attachment" ->
          {:ok,
           %{
             item: Zotero.from_api(raw),
             attachments: raw |> List.wrap() |> readable(),
             notes_key: nil
           }}

        true ->
          with {:ok, children} <- children(key, "attachment") do
            {:ok, %{item: Zotero.from_api(raw), attachments: readable(children), notes_key: key}}
          end
      end
    end
  end

  @doc """
  The PDF and EPUB files in the Zotero folders `collections` (keys: the
  workbench passes its root folder and every folder inside it), most
  recently changed first, each as an item the workbench can list: `%{key,
  file_key, kind, title, authors, year, call_number, standalone?}`. `key` is
  the item a citation or a note belongs to (the file's parent, or the file
  itself when it stands alone), and `file_key` the file to open. A folder's
  files include those filed under its items, but not its subfolders', so
  each folder is asked for. A non-empty `q` searches the files' titles and,
  where Zotero has indexed it, their full text. No folders, no files: the
  rest of the library is never listed.
  """
  def files(collections, q \\ "") when is_list(collections) do
    q = q |> to_string() |> String.trim()

    with {:ok, client} <- Zotero.client(),
         {:ok, raws} <- folder_files(client, Enum.filter(collections, &key?/1), q) do
      files =
        raws
        |> Enum.uniq_by(& &1["key"])
        |> Enum.sort_by(&get_in(&1, ["data", "dateModified"]), :desc)
        |> readable()

      with {:ok, parents} <- parents(client, files) do
        {:ok, Enum.map(files, &listing(&1, Map.get(parents, &1.parent_key)))}
      end
    end
  end

  defp folder_files(client, collections, q) do
    params =
      [itemType: "attachment", sort: "dateModified", direction: "desc", limit: 100] ++
        if(q != "", do: [q: q, qmode: "everything"], else: [])

    Enum.reduce_while(collections, {:ok, []}, fn key, {:ok, acc} ->
      case Req.get(client.req,
             url: "/users/#{client.user_id}/collections/#{key}/items",
             params: params
           ) do
        {:ok, %{status: 200, body: raws}} when is_list(raws) -> {:cont, {:ok, acc ++ raws}}
        {:ok, %{status: status}} -> {:halt, {:error, http_error(status)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  # The files' parent items, fifty keys to a request (Zotero's limit).
  defp parents(client, files) do
    files
    |> Enum.map(& &1.parent_key)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.chunk_every(50)
    |> Enum.reduce_while({:ok, %{}}, fn keys, {:ok, acc} ->
      case Req.get(client.req,
             url: "/users/#{client.user_id}/items",
             params: [itemKey: Enum.join(keys, ","), limit: 50]
           ) do
        {:ok, %{status: 200, body: raws}} when is_list(raws) ->
          {:cont, {:ok, Enum.reduce(raws, acc, &Map.put(&2, &1["key"], Zotero.from_api(&1)))}}

        {:ok, %{status: status}} ->
          {:halt, {:error, http_error(status)}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp listing(file, parent) do
    %{
      key: (parent && parent.key) || file.key,
      file_key: file.key,
      kind: file.kind,
      title: (parent && parent.title) || file.filename || file.title,
      authors: (parent && parent.authors) || "",
      year: parent && parent.year,
      call_number: parent && parent.call_number,
      standalone?: is_nil(file.parent_key)
    }
  end

  defp readable(raws) do
    Enum.flat_map(raws, fn raw ->
      data = raw["data"] || %{}
      kind = Map.get(@kinds, data["contentType"])

      if kind && data["linkMode"] in @stored do
        [
          %{
            key: raw["key"] || data["key"],
            title: present(data["title"]) || present(data["filename"]) || "Attachment",
            filename: present(data["filename"]),
            content_type: data["contentType"],
            kind: kind,
            md5: if(md5?(data["md5"]), do: data["md5"]),
            parent_key: present(data["parentItem"])
          }
        ]
      else
        []
      end
    end)
  end

  @doc "The annotations under attachment `key`, in reading order (their sort index)."
  def annotations(key) do
    with {:ok, raws} <- children(key, "annotation") do
      {:ok, raws |> Enum.map(&parse_annotation/1) |> Enum.sort_by(& &1.sort_index)}
    end
  end

  defp parse_annotation(raw) do
    data = raw["data"] || %{}
    color = data["annotationColor"] |> to_string() |> String.downcase()

    %{
      key: raw["key"] || data["key"],
      version: raw["version"] || data["version"],
      type: data["annotationType"],
      text: to_string(data["annotationText"]),
      comment: to_string(data["annotationComment"]),
      color: color,
      color_name: Map.get(@color_names, color, "other"),
      page_label: to_string(data["annotationPageLabel"]),
      sort_index: to_string(data["annotationSortIndex"]),
      position: decode_position(data["annotationPosition"])
    }
  end

  defp decode_position(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, %{} = position} -> position
      _ -> %{}
    end
  end

  defp decode_position(_), do: %{}

  @doc """
  Makes a highlight or underline on `attachment` from a selection:
  `%{"type", "text", "position", "sort_index", "page_label", "color",
  "comment"}` (string keys, as the browser sends them). The position and sort
  index are checked against the attachment's kind before anything is written.
  Returns `{:ok, annotation}` or `{:error, reason}`.
  """
  def create_annotation(%{key: key, kind: kind}, params) when is_map(params) do
    with {:ok, payload} <- annotation_payload(kind, params),
         {:ok, client} <- Zotero.client(),
         {:ok, %{status: status, body: body}} when status in [200, 201] <-
           Req.post(client.req,
             url: "/users/#{client.user_id}/items",
             json: [Map.put(payload, "parentItem", key)]
           ) do
      case body do
        %{"successful" => %{"0" => created}} -> {:ok, parse_annotation(created)}
        %{"failed" => %{"0" => %{"message" => message}}} -> {:error, {:rejected, message}}
        _ -> {:error, :create_failed}
      end
    else
      {:ok, %{status: status}} -> {:error, http_error(status)}
      {:error, _} = error -> error
    end
  end

  @doc false
  def annotation_payload(kind, params) do
    type = params["type"] || "highlight"
    text = params["text"] |> to_string() |> String.trim()
    sort_index = to_string(params["sort_index"])
    position = params["position"]

    cond do
      type not in ~w(highlight underline) ->
        {:error, :bad_type}

      text == "" ->
        {:error, :no_text}

      not position_ok?(kind, position) ->
        {:error, :bad_position}

      not Regex.match?(sort_re(kind), sort_index) ->
        {:error, :bad_sort_index}

      true ->
        {:ok,
         %{
           "itemType" => "annotation",
           "annotationType" => type,
           "annotationText" => text,
           "annotationComment" => params["comment"] |> to_string() |> String.trim(),
           "annotationColor" => color_hex(params["color"]),
           "annotationPageLabel" => params["page_label"] |> to_string() |> String.slice(0, 40),
           "annotationSortIndex" => sort_index,
           "annotationPosition" => Jason.encode!(position),
           "tags" => []
         }}
    end
  end

  defp sort_re(:pdf), do: @pdf_sort_re
  defp sort_re(:epub), do: @epub_sort_re

  defp position_ok?(:pdf, %{"pageIndex" => page, "rects" => [_ | _] = rects})
       when is_integer(page) and page >= 0 do
    Enum.all?(rects, fn rect -> match?([_, _, _, _], rect) and Enum.all?(rect, &is_number/1) end)
  end

  defp position_ok?(:epub, %{
         "type" => "FragmentSelector",
         "conformsTo" => @cfi_conforms,
         "value" => "epubcfi(" <> _
       }),
       do: true

  defp position_ok?(_kind, _position), do: false

  defp color_hex(name) do
    case List.keyfind(@colors, name, 0) do
      {_, hex} -> hex
      nil -> "#ffd400"
    end
  end

  @doc """
  Changes an annotation's comment or colour (`%{"comment" => …, "color" =>
  name}`), over the version it was read at: `{:error, :conflict}` when it
  changed in Zotero since.
  """
  def update_annotation(key, version, changes) when is_map(changes) do
    patch =
      %{}
      |> then(
        &if(is_binary(changes["comment"]),
          do: Map.put(&1, "annotationComment", String.trim(changes["comment"])),
          else: &1
        )
      )
      |> then(
        &if(is_binary(changes["color"]),
          do: Map.put(&1, "annotationColor", color_hex(changes["color"])),
          else: &1
        )
      )

    write(:patch, key, version, json: patch)
  end

  @doc "Deletes an annotation, over the version it was read at."
  def delete_annotation(key, version), do: write(:delete, key, version, [])

  defp write(method, key, version, opts) do
    with true <- key?(key) || {:error, :not_found},
         {:ok, client} <- Zotero.client(),
         {:ok, %{status: status}} <-
           Req.request(
             client.req,
             [
               method: method,
               url: "/users/#{client.user_id}/items/#{key}",
               headers: [{"if-unmodified-since-version", to_string(version)}]
             ] ++ opts
           ) do
      if status == 204, do: :ok, else: {:error, http_error(status)}
    end
  end

  @doc "The notes under item `key`, as `%{key, version, text}`."
  def notes(nil), do: {:ok, []}

  def notes(key) do
    with {:ok, raws} <- children(key, "note") do
      {:ok,
       Enum.map(raws, fn raw ->
         data = raw["data"] || %{}

         %{
           key: raw["key"],
           version: raw["version"],
           text: data["note"] |> to_string() |> Web.Markdown.to_text()
         }
       end)}
    end
  end

  @doc "Adds a note under item `key`: `text` as escaped HTML paragraphs."
  def create_note(key, text) do
    text = String.trim(to_string(text))

    with true <- key?(key) || {:error, :not_found},
         true <- text != "" || {:error, :blank},
         {:ok, client} <- Zotero.client(),
         {:ok, %{status: status, body: body}} when status in [200, 201] <-
           Req.post(client.req,
             url: "/users/#{client.user_id}/items",
             json: [%{"itemType" => "note", "parentItem" => key, "note" => note_html(text)}]
           ) do
      if match?(%{"successful" => %{"0" => _}}, body), do: :ok, else: {:error, :create_failed}
    else
      {:ok, %{status: status}} -> {:error, http_error(status)}
      {:error, _} = error -> error
    end
  end

  defp note_html(text) do
    text
    |> String.split(~r/\n\s*\n/, trim: true)
    |> Enum.map_join(fn paragraph ->
      escaped = paragraph |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
      "<p>" <> String.replace(escaped, "\n", "<br/>") <> "</p>"
    end)
  end

  # ── Files ──────────────────────────────────────────────────────────────

  @doc "Where cached files are kept."
  def cache_root do
    Application.get_env(:web, :zotero_cache_path) ||
      Path.join(System.tmp_dir!(), "streetscissors-zotero")
  end

  @doc "The cached copy of attachment `key` at `md5`, if there is one."
  def cached_file(key, md5) do
    if key?(key) and (md5?(md5) or md5 == "none") do
      Enum.find_value([:pdf, :epub], fn kind ->
        path = cache_path(key, md5, kind)
        if File.regular?(path), do: {path, kind}
      end)
    end
  end

  @doc """
  The attachment's file on disk, fetched from Zotero's storage the first
  time: `{:ok, path}` or `{:error, :no_file}` when Zotero holds no file for
  it. One fetch at a time per attachment, however many requests ask.
  """
  def file(%{key: key, kind: kind} = attachment) do
    path = cache_path(key, attachment.md5 || "none", kind)

    if File.regular?(path) do
      {:ok, path}
    else
      :global.trans({__MODULE__, key}, fn ->
        if File.regular?(path), do: {:ok, path}, else: download(key, path)
      end)
    end
  end

  @doc "The attachment `key` as `file/1` needs it, read from Zotero."
  def attachment(key) do
    with true <- key?(key) || {:error, :not_found},
         {:ok, raw} <- get_item(key) do
      case readable([raw]) do
        [attachment] -> {:ok, attachment}
        [] -> {:error, :not_readable}
      end
    end
  end

  defp download(key, path) do
    File.mkdir_p!(Path.dirname(path))
    # The author's library, under the system's temporary directory: theirs alone.
    File.chmod(Path.dirname(path), 0o700)
    part = path <> ".part"

    with {:ok, client} <- Zotero.client() do
      result =
        Req.get(client.req,
          url: "/users/#{client.user_id}/items/#{key}/file",
          into: File.stream!(part),
          receive_timeout: 180_000,
          decode_body: false
        )

      case result do
        {:ok, %{status: 200}} ->
          File.rename!(part, path)
          # An older copy of a file since changed in Zotero.
          for old <- Path.wildcard(Path.join(cache_root(), key <> "-*")),
              old != path,
              do: File.rm(old)

          {:ok, path}

        {:ok, %{status: status}} ->
          File.rm(part)
          {:error, if(status == 404, do: :no_file, else: http_error(status))}

        {:error, reason} ->
          File.rm(part)
          {:error, reason}
      end
    end
  end

  defp cache_path(key, md5, kind), do: Path.join(cache_root(), "#{key}-#{md5}.#{kind}")

  # ── Requests ───────────────────────────────────────────────────────────

  defp get_item(key) do
    with {:ok, client} <- Zotero.client() do
      case Req.get(client.req, url: "/users/#{client.user_id}/items/#{key}") do
        {:ok, %{status: 200, body: %{} = raw}} -> {:ok, raw}
        {:ok, %{status: status}} -> {:error, http_error(status)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp children(key, item_type) do
    with true <- key?(key) || {:error, :not_found},
         {:ok, client} <- Zotero.client() do
      fetch_children(client, key, item_type, 0, [])
    end
  end

  # A hundred at a time: a long book can carry more highlights than one page holds.
  defp fetch_children(client, key, item_type, start, acc) do
    case Req.get(client.req,
           url: "/users/#{client.user_id}/items/#{key}/children",
           params: [itemType: item_type, limit: 100, start: start]
         ) do
      {:ok, %{status: 200, body: page} = resp} when is_list(page) ->
        total =
          case Req.Response.get_header(resp, "total-results") do
            [n | _] -> String.to_integer(n)
            [] -> 0
          end

        acc = acc ++ page

        if page != [] and length(acc) < total,
          do: fetch_children(client, key, item_type, start + length(page), acc),
          else: {:ok, acc}

      {:ok, %{status: status}} ->
        {:error, http_error(status)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp http_error(status) when status in [401, 403], do: :auth_failed
  defp http_error(404), do: :not_found
  defp http_error(412), do: :conflict
  defp http_error(status), do: {:http, status}

  defp present(nil), do: nil

  defp present(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present(_), do: nil
end
