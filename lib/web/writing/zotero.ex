defmodule Web.Writing.Zotero do
  @moduledoc """
  Client for the Zotero Web API v3 (`https://api.zotero.org`), connecting a piece's top Reading List with the author's Zotero folders.

  The root folder is `ZOTERO_COLLECTION` (default `streetscissors`); a
  piece can name its own with `zotero:` in its frontmatter
  (`Web.Writing.Document.project/1`).

    * **Read / Pull:** lists collections and subfolders under `streetscissors`,
      searches items, and pulls bibliographic citations, child notes, and PDF
      highlight annotations into the essay's top Reading List.
    * **Write / Push:** creates subfolders under `streetscissors`, adds new
      documents and child notes to Zotero, and pushes an essay's markdown
      Reading List items (and `> [!thought]` blocks) directly into a Zotero
      folder.

  Configured via `config :web, :zotero` (`ZOTERO_USER_ID`, `ZOTERO_API_KEY`, and
  optional `ZOTERO_COLLECTION` defaulting to `"streetscissors"` in `.env`).
  """

  @base_url "https://api.zotero.org"
  @item_limit 50
  @default_root_collection "streetscissors"

  @type item :: %{
          key: String.t(),
          title: String.t(),
          authors: String.t(),
          year: String.t() | nil,
          publication: String.t() | nil,
          call_number: String.t() | nil,
          url: String.t() | nil,
          citation_key: String.t() | nil,
          notes: [String.t()]
        }

  @doc "Whether `ZOTERO_API_KEY` (and `ZOTERO_USER_ID`) are configured."
  def configured? do
    case credentials() do
      %{user_id: uid, api_key: key} ->
        is_binary(uid) and String.trim(uid) != "" and is_binary(key) and String.trim(key) != ""

      _ ->
        false
    end
  end

  @doc "Name or key of the root Zotero folder for the site (defaults to `\"streetscissors\"`)."
  def root_collection_target do
    creds = credentials()
    presence(creds[:collection]) || @default_root_collection
  end

  @doc """
  Lists the user's Zotero collections, enriching each with its `parent_key`,
  `path` (e.g. `"streetscissors / Top Versus Bottom"`), and `in_root?` flag when
  it belongs to the configured root folder (`"streetscissors"`).

  Collections inside the root folder are sorted first (root folder at the top,
  followed by its subfolders alphabetically), followed by any other library
  collections.
  """
  def list_collections do
    with {:ok, auth} <- fetch_auth(),
         {:ok, %{status: 200, body: body}} when is_list(body) <-
           Req.get(req(auth),
             url: "/users/#{auth.user_id}/collections",
             params: [limit: 100]
           ) do
      raw_list =
        body
        |> Enum.map(&parse_collection/1)
        |> Enum.reject(&(&1.key == ""))

      {:ok, enrich_collections(raw_list, root_collection_target())}
    else
      {:ok, %{status: status}} when status in [401, 403] -> {:error, :auth_failed}
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Finds the configured root collection (e.g. `"streetscissors"`) among a list
  of collections (or fetches the list first).
  """
  def find_root_collection(collections \\ nil) do
    target = String.downcase(root_collection_target())

    list =
      case collections do
        list when is_list(list) -> {:ok, list}
        _ -> list_collections()
      end

    with {:ok, cols} <- list do
      Enum.find(cols, fn c ->
        String.downcase(c.key) == target or
          (is_nil(c.parent_key) and String.downcase(c.name) == target)
      end) ||
        Enum.find(cols, fn c -> String.downcase(c.name) == target end)
    else
      _ -> nil
    end
  end

  @doc """
  Creates a Zotero collection (folder). When `parent_key` is `:root` or `nil`,
  nests the new folder inside the `streetscissors` root collection if one
  exists.

  Idempotent: if a folder with `name` already exists under the resolved parent,
  returns `{:ok, existing}` instead of creating a duplicate.
  """
  def create_collection(name, parent_key \\ :root) when is_binary(name) do
    trimmed = String.trim(name)

    if trimmed == "" do
      {:error, :blank_name}
    else
      with {:ok, auth} <- fetch_auth(),
           {:ok, existing_cols} <- list_collections() do
        resolved_parent = resolve_parent_key(parent_key, existing_cols)

        case Enum.find(existing_cols, fn c ->
               c.parent_key == resolved_parent and
                 String.downcase(c.name) == String.downcase(trimmed)
             end) do
          %{} = found ->
            {:ok, found}

          nil ->
            payload = [
              %{
                "name" => trimmed,
                "parentCollection" => resolved_parent || false
              }
            ]

            case Req.post(req(auth),
                   url: "/users/#{auth.user_id}/collections",
                   json: payload
                 ) do
              {:ok, %{status: status, body: body}} when status in [200, 201] and is_map(body) ->
                case get_in(body, ["successful", "0"]) do
                  %{} = created_raw ->
                    col = parse_collection(created_raw)
                    all = enrich_collections([col | existing_cols], root_collection_target())
                    {:ok, Enum.find(all, &(&1.key == col.key)) || col}

                  _ ->
                    {:error, :create_failed}
                end

              {:ok, %{status: status}} when status in [401, 403] ->
                {:error, :auth_failed}

              {:ok, %{status: status}} ->
                {:error, {:http, status}}

              {:error, reason} ->
                {:error, reason}
            end
        end
      end
    end
  end

  @doc """
  Creates a bibliographic item in Zotero (optionally inside `collection_key`)
  and attaches any `notes` as child Zotero notes.

  Returns `{:ok, item}` formatted as a `t:item/0` map.
  """
  def create_item(attrs, collection_key \\ nil) when is_map(attrs) do
    title = presence(attrs[:title] || attrs["title"])

    if is_nil(title) do
      {:error, :blank_title}
    else
      with {:ok, auth} <- fetch_auth() do
        payload = build_item_payload(attrs, title, collection_key)

        case Req.post(req(auth),
               url: "/users/#{auth.user_id}/items",
               json: [payload]
             ) do
          {:ok, %{status: status, body: body}} when status in [200, 201] and is_map(body) ->
            case get_in(body, ["successful", "0"]) do
              %{} = created_raw ->
                item = parse_item(created_raw)

                notes =
                  normalize_notes(
                    attrs[:notes] || attrs["notes"] || attrs[:note] || attrs["note"]
                  )

                if notes != [] do
                  _ = create_child_notes(auth, item.key, notes)
                end

                {:ok, %{item | notes: notes}}

              _ ->
                {:error, :create_failed}
            end

          {:ok, %{status: status}} when status in [401, 403] ->
            {:error, :auth_failed}

          {:ok, %{status: status}} ->
            {:error, {:http, status}}

          {:error, reason} ->
            {:error, reason}
        end
      end
    end
  end

  @doc """
  Pushes a list of parsed markdown research checklist items (`%{text, thoughts, done?}`)
  into `collection_key` in Zotero, skipping any item whose title is already
  present in that collection.

  Returns `{:ok, %{created: [item], skipped: count}}` or `{:error, reason}`.
  """
  def sync_reading_list(research_items, collection_key)
      when is_list(research_items) and is_binary(collection_key) and collection_key != "" do
    with {:ok, existing} <- search_items(collection: collection_key, limit: 100) do
      existing_titles =
        existing
        |> Enum.map(&normalize_match_title(&1.title))
        |> MapSet.new()

      {created_rev, skipped, _seen} =
        Enum.reduce(research_items, {[], 0, existing_titles}, fn raw_entry, {acc, skip_n, seen} ->
          parsed = parse_markdown_reading_item(raw_entry)
          norm_title = normalize_match_title(parsed.title)

          if norm_title == "" or MapSet.member?(seen, norm_title) do
            {acc, skip_n + 1, seen}
          else
            case create_item(parsed, collection_key) do
              {:ok, item} ->
                {[item | acc], skip_n, MapSet.put(seen, norm_title)}

              {:error, _} ->
                {acc, skip_n + 1, seen}
            end
          end
        end)

      {:ok, %{created: Enum.reverse(created_rev), skipped: skipped}}
    end
  end

  @doc """
  Parses a single markdown reading-list item (`%{text: String.t(), thoughts: [String.t()]}`
  or a raw markdown string) into structured bibliographic fields ready for
  `create_item/2`.
  """
  def parse_markdown_reading_item(entry) when is_binary(entry) do
    parse_markdown_reading_item(%{text: entry, thoughts: []})
  end

  def parse_markdown_reading_item(%{text: raw_text} = entry) do
    thoughts = Map.get(entry, :thoughts, []) || []

    {line, _key} =
      raw_text
      |> String.trim()
      |> String.replace(~r/^[-*+]\s+\[[ xX]\]\s+/, "")
      |> Web.Writing.Citations.split_key()

    # Extract trailing " — Verify..." inline note if present
    {citation_part, inline_note} =
      case String.split(line, ~r/\s+(?:—|--)\s+/, parts: 2) do
        [cit, note] -> {String.trim(cit), String.trim(note)}
        [cit] -> {String.trim(cit), nil}
      end

    # Extract Call Number if present: *...Call Number: XYZ*
    call_number =
      case Regex.run(~r/\*(?:[^*]*?Call Number:\s*)([^*]+)\*/i, citation_part) do
        [_, cn] -> String.trim(cn)
        nil -> nil
      end

    citation_no_cn =
      Regex.replace(~r/\s*\*(?:[^*]*?Call Number:\s*)[^*]+\*\.?/i, citation_part, "")
      |> String.trim()

    # Extract leading **Author.**
    {authors_str, after_author} =
      case Regex.run(~r/^\*\*([^*]+?)\*\*\.?\s*(.*)$/s, citation_no_cn) do
        [_, auth, rest] ->
          {String.trim_trailing(String.trim(auth), "."), String.trim(rest)}

        nil ->
          {"", citation_no_cn}
      end

    # Extract URL if markdown link [Text](https://...) is present
    url =
      case Regex.run(~r/\[[^\]]+\]\((https?:\/\/[^)\s]+)\)/, after_author) do
        [_, u] -> u
        nil -> nil
      end

    # Determine title, publication, and item_type
    {item_type, title, publication} =
      extract_title_and_publication(after_author, authors_str, url)

    year = extract_year(citation_no_cn)

    notes =
      ([inline_note] ++ thoughts)
      |> Enum.reject(&(is_nil(&1) or String.trim(&1) == ""))
      |> Enum.uniq()

    %{
      item_type: item_type,
      title: title,
      authors: authors_str,
      year: year,
      publication: publication,
      call_number: call_number,
      url: url,
      notes: notes
    }
  end

  @doc """
  Searches top-level bibliographic items in the user's Zotero library (or inside
  a collection when `:collection` is given).

  Options:
    * `:q` — search query matching title, creator, year, or notes
    * `:collection` — collection key to scope the listing
    * `:limit` — maximum items to return (default #{@item_limit})
  """
  def search_items(opts \\ []) do
    with {:ok, auth} <- fetch_auth() do
      collection = Keyword.get(opts, :collection)
      q = Keyword.get(opts, :q, "") |> to_string() |> String.trim()
      limit = Keyword.get(opts, :limit, @item_limit)

      path =
        if is_binary(collection) and collection != "" do
          "/users/#{auth.user_id}/collections/#{collection}/items/top"
        else
          "/users/#{auth.user_id}/items/top"
        end

      params =
        [
          limit: limit,
          sort: "dateModified",
          direction: "desc",
          itemType: "-attachment || note || annotation"
        ] ++ if(q != "", do: [q: q, qmode: "everything"], else: [])

      case Req.get(req(auth), url: path, params: params) do
        {:ok, %{status: 200, body: body}} when is_list(body) ->
          {:ok, Enum.map(body, &parse_item/1)}

        {:ok, %{status: status}} when status in [401, 403] ->
          {:error, :auth_failed}

        {:ok, %{status: status}} ->
          {:error, {:http, status}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Fetches a single Zotero item along with all of its child notes and PDF
  highlight annotations (including annotations nested under a child PDF
  attachment).
  """
  def fetch_item_with_notes(item_key) when is_binary(item_key) do
    with {:ok, auth} <- fetch_auth(),
         {:ok, %{status: 200, body: raw}} when is_map(raw) <-
           Req.get(req(auth), url: "/users/#{auth.user_id}/items/#{item_key}") do
      item = parse_item(raw)
      notes = fetch_children_notes(auth, item_key, raw)
      {:ok, %{item | notes: notes}}
    else
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: status}} when status in [401, 403] -> {:error, :auth_failed}
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Fetches all top-level items in `collection_key`, enriched with their child
  notes and PDF annotations.
  """
  def fetch_collection_with_notes(collection_key) when is_binary(collection_key) do
    with {:ok, auth} <- fetch_auth(),
         {:ok, %{status: 200, body: body}} when is_list(body) <-
           Req.get(req(auth),
             url: "/users/#{auth.user_id}/collections/#{collection_key}/items/top",
             params: [limit: @item_limit, sort: "dateAdded", direction: "asc"]
           ) do
      items =
        Enum.map(body, fn raw ->
          item = parse_item(raw)
          notes = fetch_children_notes(auth, item.key, raw)
          %{item | notes: notes}
        end)

      {:ok, items}
    else
      {:ok, %{status: status}} when status in [401, 403] -> {:error, :auth_failed}
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  The top-level items of `collection_key` as CSL JSON (Zotero's own
  `format=csljson`), for an export's bibliography: more exact than a
  reading-list line, since Zotero keeps volume, pages, DOI and the rest.
  """
  def fetch_csl(collection_key) when is_binary(collection_key) do
    with {:ok, auth} <- fetch_auth(),
         {:ok, %{status: 200, body: body}} <-
           Req.get(req(auth),
             url: "/users/#{auth.user_id}/collections/#{collection_key}/items/top",
             params: [format: "csljson", limit: 100]
           ) do
      items =
        case body do
          %{"items" => items} when is_list(items) -> items
          items when is_list(items) -> items
          binary when is_binary(binary) -> binary |> Jason.decode!() |> Map.get("items", [])
          _ -> []
        end

      {:ok, items}
    else
      {:ok, %{status: status}} when status in [401, 403] -> {:error, :auth_failed}
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "The collection named `name` (case-insensitive) among `collections`, or nil."
  def find_collection(collections, name) when is_list(collections) and is_binary(name) do
    wanted = name |> String.trim() |> String.downcase()

    Enum.find(
      collections,
      &(String.downcase(&1.name) == wanted or String.downcase(&1.path) == wanted)
    )
  end

  @doc """
  Formats a Zotero item (and any child notes / PDF annotations) as a markdown
  reading-list entry with `> [!thought]` blocks.

  Items that already carry notes or annotations in Zotero are marked `- [x]`;
  items without notes are marked `- [ ]`. An item with a `:cite_key` ends its line
  with it as a block id (` ^boym2001`), the citation key `Web.Writing.Citations`
  reads.
  """
  def format_reading_item(%{title: title} = item) do
    box = if item.notes != [], do: "[x]", else: "[ ]"
    author_part = if item.authors != "", do: "**#{item.authors}.** ", else: ""

    title_part =
      if is_binary(item.url) and item.url != "" do
        "*[#{title}](#{item.url})*"
      else
        "*#{title}*"
      end

    pub_year =
      [item.publication, item.year]
      |> Enum.reject(&(is_nil(&1) or &1 == ""))
      |> Enum.join(", ")

    pub_part = if pub_year != "", do: " (#{pub_year}).", else: "."

    call_part =
      if is_binary(item.call_number) and item.call_number != "" do
        " *Call Number: #{item.call_number}*"
      else
        ""
      end

    key_part =
      case Map.get(item, :cite_key) do
        key when is_binary(key) and key != "" -> " ^" <> key
        _ -> ""
      end

    citation_line = "- #{box} #{author_part}#{title_part}#{pub_part}#{call_part}#{key_part}"

    thought_blocks =
      Enum.map(item.notes, fn note ->
        quoted =
          note
          |> String.split(~r/\r?\n/)
          |> Enum.map_join("\n", &"> #{&1}")

        "> [!thought]\n" <> quoted
      end)

    Enum.join([citation_line | thought_blocks], "\n")
  end

  # ── Collection tree & payload builders ────────────────────────────────

  defp parse_collection(raw) do
    data = raw["data"] || %{}
    meta = raw["meta"] || %{}

    parent =
      case data["parentCollection"] do
        false -> nil
        nil -> nil
        "" -> nil
        key when is_binary(key) -> key
        _ -> nil
      end

    %{
      key: raw["key"] || data["key"] || "",
      name: data["name"] || "Untitled",
      parent_key: parent,
      item_count: meta["numItems"] || 0,
      subcollection_count: meta["numCollections"] || 0,
      path: data["name"] || "Untitled",
      in_root?: false,
      is_root?: false
    }
  end

  defp enrich_collections(cols, root_target) do
    by_key = Map.new(cols, &{&1.key, &1})
    target_down = String.downcase(to_string(root_target || @default_root_collection))

    root =
      Enum.find(cols, fn c ->
        String.downcase(c.key) == target_down or
          (is_nil(c.parent_key) and String.downcase(c.name) == target_down)
      end) ||
        Enum.find(cols, fn c -> String.downcase(c.name) == target_down end)

    root_key = root && root.key

    cols
    |> Enum.map(fn col ->
      chain = ancestor_chain(col, by_key, [])
      path = Enum.map_join(chain, " / ", & &1.name)
      in_root? = root_key != nil and Enum.any?(chain, &(&1.key == root_key))
      is_root? = root_key != nil and col.key == root_key

      %{col | path: path, in_root?: in_root?, is_root?: is_root?}
    end)
    |> Enum.sort_by(fn c ->
      {if(c.is_root?, do: 0, else: if(c.in_root?, do: 1, else: 2)), String.downcase(c.path)}
    end)
  end

  defp ancestor_chain(col, by_key, seen) do
    if col.key in seen do
      [col]
    else
      case col.parent_key && Map.get(by_key, col.parent_key) do
        %{} = parent -> ancestor_chain(parent, by_key, [col.key | seen]) ++ [col]
        nil -> [col]
      end
    end
  end

  defp resolve_parent_key(:root, cols) do
    case find_root_collection(cols) do
      %{key: key} -> key
      nil -> nil
    end
  end

  defp resolve_parent_key(nil, _cols), do: nil
  defp resolve_parent_key("", _cols), do: nil
  defp resolve_parent_key(key, _cols) when is_binary(key), do: key

  defp build_item_payload(attrs, title, collection_key) do
    raw_type = presence(attrs[:item_type] || attrs["item_type"])
    pub = presence(attrs[:publication] || attrs["publication"])
    url = presence(attrs[:url] || attrs["url"])
    year = presence(attrs[:year] || attrs["year"])
    call_number = presence(attrs[:call_number] || attrs["call_number"])
    authors = attrs[:authors] || attrs["authors"] || ""

    item_type =
      cond do
        raw_type in [
          "book",
          "journalArticle",
          "newspaperArticle",
          "webpage",
          "report",
          "document"
        ] ->
          raw_type

        is_binary(url) and is_nil(pub) ->
          "webpage"

        true ->
          "book"
      end

    collections =
      cond do
        is_list(collection_key) ->
          collection_key |> Enum.map(&to_string/1) |> Enum.reject(&(&1 == "")) |> Enum.uniq()

        is_binary(collection_key) and collection_key != "" ->
          [collection_key]

        true ->
          []
      end

    base = %{
      "itemType" => item_type,
      "title" => title,
      "creators" => parse_creators_input(authors),
      "collections" => collections
    }

    base
    |> put_if_present("date", year)
    |> put_if_present("callNumber", call_number)
    |> put_if_present("url", url)
    |> put_publication_field(item_type, pub)
  end

  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, _key, ""), do: map
  defp put_if_present(map, key, val), do: Map.put(map, key, val)

  defp put_publication_field(map, _type, nil), do: map
  defp put_publication_field(map, _type, ""), do: map

  defp put_publication_field(map, "journalArticle", pub),
    do: Map.put(map, "publicationTitle", pub)

  defp put_publication_field(map, "newspaperArticle", pub),
    do: Map.put(map, "publicationTitle", pub)

  defp put_publication_field(map, "webpage", pub),
    do: Map.put(map, "websiteTitle", pub)

  defp put_publication_field(map, "report", pub),
    do: Map.put(map, "institution", pub)

  defp put_publication_field(map, _book_or_other, pub),
    do: Map.put(map, "publisher", pub)

  defp parse_creators_input(creators) when is_list(creators), do: creators

  defp parse_creators_input(authors_str) when is_binary(authors_str) do
    trimmed = String.trim(authors_str)

    if trimmed == "" do
      []
    else
      trimmed
      |> String.split(~r/\s*(?:;|&|\band\b)\s*/i, trim: true)
      |> Enum.map(fn part ->
        part = String.trim(part)

        case String.split(part, ",", parts: 2) do
          [last, first] ->
            %{
              "creatorType" => "author",
              "lastName" => String.trim(last),
              "firstName" => String.trim(first)
            }

          [single] ->
            words = String.split(single, ~r/\s+/, trim: true)

            if length(words) >= 2 and length(words) <= 3 and
                 not String.contains?(single, [
                   "/",
                   "Department",
                   "Committee",
                   "Press",
                   "News",
                   "Bureau"
                 ]) do
              {first_parts, [last]} = Enum.split(words, -1)

              %{
                "creatorType" => "author",
                "firstName" => Enum.join(first_parts, " "),
                "lastName" => last
              }
            else
              %{
                "creatorType" => "author",
                "name" => single
              }
            end
        end
      end)
    end
  end

  defp parse_creators_input(_), do: []

  defp create_child_notes(auth, parent_key, notes) do
    payload =
      Enum.map(notes, fn note ->
        html =
          note
          |> Phoenix.HTML.html_escape()
          |> Phoenix.HTML.safe_to_string()
          |> String.replace("\n", "<br/>")

        %{
          "itemType" => "note",
          "parentItem" => parent_key,
          "note" => "<p>#{html}</p>"
        }
      end)

    Req.post(req(auth),
      url: "/users/#{auth.user_id}/items",
      json: payload
    )
  end

  defp normalize_notes(nil), do: []

  defp normalize_notes(note) when is_binary(note) do
    trimmed = String.trim(note)
    if trimmed == "", do: [], else: [trimmed]
  end

  defp normalize_notes(notes) when is_list(notes) do
    notes
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp extract_title_and_publication(after_author, authors_str, url) do
    cond do
      # Quoted article title + italicized journal: "Title," *Journal* ...
      match = Regex.run(~r/^[""“]([^""”]+?)[""”],?\s*\*([^*]+)\*/, after_author) ->
        [_, article_title, journal] = match

        {"journalArticle", String.replace(article_title, ~r/^[\s,.]+|[\s,.]+$/, ""),
         String.trim(journal)}

      # Italicized book or report title: *Title* (Publisher, 2001)
      match = Regex.run(~r/^\*\[?([^*\]]+)\]?(?:\([^)]*\))?\*\s*(?:\(([^)]+)\))?/, after_author) ->
        [_, raw_title | rest] = match
        paren = List.first(rest) || ""
        pub = extract_publisher_from_paren(paren)

        type =
          if String.contains?(authors_str, ["Department", "SIGTARP", "U.S.", "Commission"]),
            do: "report",
            else: "book"

        {type, String.trim(raw_title), pub}

      true ->
        clean =
          after_author
          |> Web.Markdown.to_text()
          |> String.replace(~r/\s*\([^)]*\)\s*\.?$/, "")
          |> String.trim(" .")

        title = if clean != "", do: clean, else: Web.Markdown.to_text(after_author)
        type = if is_binary(url), do: "webpage", else: "document"
        {type, title, nil}
    end
  end

  defp extract_publisher_from_paren(paren) when is_binary(paren) do
    paren
    |> String.split(~r/[,;]/)
    |> List.first()
    |> to_string()
    |> String.trim()
    |> case do
      "" ->
        nil

      s ->
        if Regex.match?(~r/^\d{4}/, s), do: nil, else: s
    end
  end

  defp normalize_match_title(title) do
    title
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, " ")
    |> String.trim()
  end

  # ── Internal parsing & child extraction ───────────────────────────────

  defp fetch_children_notes(auth, item_key, raw_parent) do
    num_children = get_in(raw_parent, ["meta", "numChildren"]) || 0

    if num_children > 0 do
      case Req.get(req(auth),
             url: "/users/#{auth.user_id}/items/#{item_key}/children",
             params: [limit: 100]
           ) do
        {:ok, %{status: 200, body: children}} when is_list(children) ->
          extract_notes_and_annotations(auth, children)

        _ ->
          []
      end
    else
      []
    end
  end

  defp extract_notes_and_annotations(auth, children) do
    Enum.flat_map(children, fn child ->
      data = child["data"] || %{}
      type = data["itemType"]

      cond do
        type == "note" ->
          text = data["note"] |> to_string() |> Web.Markdown.to_text()
          if text != "", do: [text], else: []

        type == "annotation" ->
          case format_annotation(data) do
            nil -> []
            text -> [text]
          end

        type == "attachment" and (get_in(child, ["meta", "numChildren"]) || 0) > 0 ->
          att_key = child["key"] || data["key"]

          case Req.get(req(auth),
                 url: "/users/#{auth.user_id}/items/#{att_key}/children",
                 params: [limit: 100]
               ) do
            {:ok, %{status: 200, body: grand}} when is_list(grand) ->
              Enum.flat_map(grand, fn g ->
                g_data = g["data"] || %{}

                if g_data["itemType"] == "annotation",
                  do: List.wrap(format_annotation(g_data)),
                  else: []
              end)

            _ ->
              []
          end

        true ->
          []
      end
    end)
  end

  defp format_annotation(data) do
    quote_text = data["annotationText"] |> to_string() |> String.trim()
    comment = data["annotationComment"] |> to_string() |> String.trim()
    page = data["annotationPageLabel"] |> to_string() |> String.trim()
    page_suffix = if page != "", do: " (p. #{page})", else: ""

    cond do
      quote_text != "" and comment != "" ->
        "“#{quote_text}”#{page_suffix} — #{comment}"

      comment != "" ->
        comment

      quote_text != "" ->
        "“#{quote_text}”#{page_suffix}"

      true ->
        nil
    end
  end

  defp parse_item(raw) do
    data = raw["data"] || %{}
    key = raw["key"] || data["key"] || ""
    title = presence(data["title"]) || "Untitled"
    authors = format_creators(data["creators"] || [])
    year = extract_year(data["date"])

    publication =
      presence(data["publicationTitle"]) ||
        presence(data["publisher"]) ||
        presence(data["bookTitle"]) ||
        presence(data["websiteTitle"]) ||
        presence(data["institution"])

    call_number = presence(data["callNumber"])

    # Zotero 7's own field, else the line Better BibTeX pins into Extra.
    citation_key =
      presence(data["citationKey"]) ||
        case Regex.run(~r/^\s*Citation Key:\s*(\S+)/mi, to_string(data["extra"])) do
          [_, key] -> key
          nil -> nil
        end

    url =
      presence(data["url"]) ||
        case presence(data["DOI"]) do
          nil -> nil
          doi -> "https://doi.org/" <> String.replace_prefix(doi, "https://doi.org/", "")
        end

    %{
      key: key,
      title: title,
      authors: authors,
      year: year,
      publication: publication,
      call_number: call_number,
      url: url,
      citation_key: citation_key,
      notes: []
    }
  end

  defp format_creators(creators) when is_list(creators) do
    authors =
      creators
      |> Enum.filter(&(&1["creatorType"] in ["author", "editor", "contributor", nil]))
      |> Enum.map(fn c ->
        cond do
          presence(c["lastName"]) && presence(c["firstName"]) ->
            "#{String.trim(c["lastName"])}, #{String.trim(c["firstName"])}"

          presence(c["lastName"]) ->
            String.trim(c["lastName"])

          presence(c["name"]) ->
            String.trim(c["name"])

          true ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    case authors do
      [] -> ""
      [one] -> one
      [first, second] -> "#{first} & #{second}"
      [first | _rest] -> "#{first}, et al."
    end
  end

  defp format_creators(_), do: ""

  defp extract_year(nil), do: nil

  defp extract_year(date_str) when is_binary(date_str) do
    case Regex.run(~r/\b(1[789]\d{2}|20\d{2})\b/, date_str) do
      [_, year] -> year
      nil -> nil
    end
  end

  defp presence(nil), do: nil

  defp presence(val) when is_binary(val) do
    trimmed = String.trim(val)
    if trimmed == "", do: nil, else: trimmed
  end

  defp presence(_), do: nil

  defp credentials do
    Application.get_env(:web, :zotero, [])
    |> Map.new()
  end

  defp fetch_auth do
    creds = credentials()
    uid = creds[:user_id] && String.trim(to_string(creds[:user_id]))
    key = creds[:api_key] && String.trim(to_string(creds[:api_key]))

    if is_binary(uid) and uid != "" and is_binary(key) and key != "" do
      {:ok, %{user_id: uid, api_key: key}}
    else
      {:error, :not_configured}
    end
  end

  defp req(auth) do
    Req.new(
      base_url: @base_url,
      headers: [
        {"zotero-api-version", "3"},
        {"zotero-api-key", auth.api_key}
      ],
      retry: false,
      receive_timeout: 15_000
    )
    |> Req.merge(Application.get_env(:web, :zotero_req_options, []))
  end
end
