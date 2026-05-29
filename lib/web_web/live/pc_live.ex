defmodule WebWeb.PcLive do
  use WebWeb, :live_view

  @linux_guide (case File.read("priv/LINUX_POCKET_GUIDE.TXT") do
                  {:ok, content} -> content
                  _ -> "Linux Guide not found."
                end)

  @fitness_guide (case File.read("priv/SEVEN_DAY_FITNESS.TXT") do
                    {:ok, content} -> content
                    _ -> "Fitness regimen not found."
                  end)

  def mount(_params, _session, socket) do
    welcome_message = """
    César's Machine - DOS Terminal

    This is not meant to be a comprehensive or even complete description of various commands.
    Rather, the commands before you are presented as a cheat sheet, a starter. Knowing
    how to talk to your machine is awesome, I think.

    César Anthony Moreno                        Tue 10 Mar 2026 11:31:29 PM PDT

    COMMANDS OF NOTE:
      $$ls$$ / $$dir$$      (list files)
      $$cd$$            (changes directory)
      $$read$$          (ffv short text files)
      $$view$$          (ffv image files)
      $$play$$          (play audio files)
      $$search$$        (keyword search)
      $$help$$          (more instructions)
      $$clear$$         (refresh terminal)
    """

    fs = build_fs()

    {:ok,
     assign(socket,
       cwd: ["C:"],
       history: [
         %{type: :info, content: welcome_message}
       ],
       fs: fs,
       command: ""
     ), layout: false}
  end

  def render(assigns) do
    ~H"""
    <div class="pc-container" id="pc-terminal" phx-hook="AutoScroll">
      <div class="pc-crt-overlay"></div>
      <div class="pc-header">
        <a href="/" class="pc-back-link">[← ESC to exit]</a>
        <div style="text-align: right;">
          <span style="opacity: 0.8; display: block;">MS-DOS Prompt - "César's Machine"</span>
          <span style="font-size: 0.85rem; opacity: 0.6;">
            TYPE 'HELP' FOR INSTRUCTIONS PENDING VIRTUAL MOUNT
          </span>
        </div>
      </div>

      <div class="pc-output" id="pc-output-list">
        <%= for item <- @history do %>
          <div class="pc-history-item">
            <%= case item.type do %>
              <% :command -> %>
                <span class="pc-cmd-prompt">{item.cwd}</span> {item.content}
              <% :info -> %>
                <pre class="pc-info"><%= format_info(item.content) %></pre>
              <% :error -> %>
                <span class="pc-error">{item.content}</span>
              <% :image -> %>
                <div class="pc-media-wrapper">
                  <img src={item.url} alt="Requested image" class="pc-rendered-media" />
                  <div class="pc-media-caption">{item.filename}</div>
                </div>
              <% :audio -> %>
                <div class="pc-media-wrapper">
                  <audio controls class="pc-rendered-media pc-audio-player">
                    <source src={item.url} type="audio/mpeg" />
                    Your browser does not support the audio element.
                  </audio>
                  <div class="pc-media-caption">{item.filename}</div>
                </div>
            <% end %>
          </div>
        <% end %>

        <form phx-submit="run_command" class="pc-input-form">
          <span class="pc-cmd-prompt">{display_cwd(@cwd)}</span>
          <input
            type="text"
            name="command"
            value={@command}
            autocomplete="off"
            spellcheck="false"
            autofocus
            class="pc-input"
            id="pc-input"
            phx-hook="PcTerminal"
          />
        </form>
      </div>
    </div>
    """
  end

  def handle_event("tab_complete", %{"value" => current_input}, socket) do
    # Split by spaces but keep track of the last word
    parts = String.split(current_input, " ", trim: false)
    last_word = List.last(parts) || ""
    last_word_up = String.upcase(last_word)

    # Split last word by path separators to find the directory we are looking in
    path_parts = String.split(last_word_up, ["/", "\\"], trim: false)
    search_prefix = List.last(path_parts) || ""

    # Normalize search prefix to match FS (underscores)
    search_prefix_normalized = String.replace(search_prefix, "-", "_")

    dir_path_up = Enum.drop(path_parts, -1) |> Enum.join("/")

    cwd = socket.assigns.cwd
    fs = socket.assigns.fs

    # 1. Try local/relative completion first
    target_cwd =
      if dir_path_up == "" do
        cwd
      else
        parse_path(dir_path_up, cwd)
      end

    local_candidates =
      case get_node(target_cwd, fs) do
        {:dir, contents} -> Map.keys(contents)
        _ -> []
      end

    commands = [
      "DIR",
      "LS",
      "CD",
      "VIEW",
      "PLAY",
      "READ",
      "CLS",
      "CLEAR",
      "HELP",
      "PWD",
      "SEARCH",
      "GREP",
      "EXIT",
      "LOGOUT"
    ]

    # Initial command candidates if only one word
    initial_candidates =
      if length(parts) <= 1 and dir_path_up == "",
        do: commands ++ local_candidates,
        else: local_candidates

    matches =
      initial_candidates
      |> Enum.filter(&String.starts_with?(&1, search_prefix_normalized))
      |> Enum.sort()

    # 2. If no local matches, try global search across the whole FS (if no path was typed)
    matches =
      if matches == [] and dir_path_up == "" and search_prefix != "" do
        find_globally(search_prefix_normalized, fs)
      else
        matches
      end

    case matches do
      [] ->
        {:noreply, socket}

      [exact] ->
        # Single match: replace the last word entirely for reliability
        prefix_cmd = Enum.drop(parts, -1) |> Enum.join(" ")

        # If it was a local match, we might need to prepend the directory path typed
        final_word = if dir_path_up != "", do: dir_path_up <> "/" <> exact, else: exact
        new_val = (prefix_cmd <> " " <> final_word) |> String.downcase() |> String.trim()

        {:noreply,
         socket
         |> assign(command: new_val)
         |> push_event("update_terminal_input", %{value: new_val})}

      multiple ->
        # Multiple matches: find common prefix
        common = find_common_prefix(multiple)

        if String.length(common) > String.length(search_prefix_normalized) do
          prefix_cmd = Enum.drop(parts, -1) |> Enum.join(" ")
          final_word = if dir_path_up != "", do: dir_path_up <> "/" <> common, else: common
          new_val = (prefix_cmd <> " " <> final_word) |> String.downcase() |> String.trim()

          {:noreply,
           socket
           |> assign(command: new_val)
           |> push_event("update_terminal_input", %{value: new_val})}
        else
          {:noreply, socket}
        end
    end
  end

  def handle_event("run_command", %{"command" => input}, socket) do
    input = String.trim(input)
    history = socket.assigns.history
    cwd = socket.assigns.cwd

    # Intercept commands
    cond do
      String.downcase(input) in ["clear", "cls"] ->
        {:noreply, assign(socket, history: [], command: "")}

      String.downcase(input) in ["exit", "logout"] ->
        {:noreply, push_navigate(socket, to: ~p"/")}

      true ->
        new_history = history ++ [%{type: :command, content: input, cwd: display_cwd(cwd)}]

        if input == "" do
          {:noreply, assign(socket, history: new_history)}
        else
          {output, new_cwd} = process_command(input, cwd, socket.assigns.fs)

          final_history =
            case output do
              nil -> new_history
              %{type: _} = out -> new_history ++ [out]
              text -> new_history ++ [%{type: :info, content: text}]
            end

          {:noreply, assign(socket, history: final_history, cwd: new_cwd, command: "")}
        end
    end
  end

  defp find_globally(prefix, fs, current_path \\ []) do
    Enum.flat_map(fs, fn {name, node} ->
      new_path = current_path ++ [name]
      # Return results as relative paths from root-ish strings
      matches = if String.starts_with?(name, prefix), do: [Enum.join(new_path, "/")], else: []

      case node do
        {:dir, children} -> matches ++ find_globally(prefix, children, new_path)
        _ -> matches
      end
    end)
  end

  defp find_common_prefix([]), do: ""

  defp find_common_prefix([first | rest]) do
    Enum.reduce(rest, first, fn next, acc ->
      String.to_charlist(acc)
      |> Enum.zip(String.to_charlist(next))
      |> Enum.take_while(fn {a, b} -> a == b end)
      |> Enum.map(fn {a, _} -> a end)
      |> List.to_string()
    end)
  end

  # Command Processor
  defp process_command("clear", cwd, _fs) do
    # Hack to just clear screen? Actually we can't easily clear list unless we reset history.
    {%{type: :command, content: "", cwd: display_cwd(cwd), hidden: true}, cwd}
  end

  defp process_command("cls", cwd, _fs) do
    # Instructing frontend to clear could be complex with append-only, but since we re-render full history:
    # We will just return a special output and handle clearing at the caller level later. For now, let's just make cls print a blank line.
    {"", cwd}
  end

  defp process_command("help", cwd, _fs) do
    help_text = """
    Genesis
      El Carnal: the low level operating system (unix)
      La Anima: UI (user interface) for typing commands

    Parenthetical Key: for filing viewing (ffv)

    Standard Symbols: ^: press and hold CTRL key
                      ^D: press and hold CTRL, type D
                      ESC: escape key (exits terminal / La Anima)
                      TAB: auto-complete commands and files

    COMMANDS OF NOTE:
      $$ls$$ / $$dir$$      (sets the working directory file list)
      $$cd$$ <dir>      (changes directory; e.g. cd IMAGES, cd ..)
      $$pwd$$           (print working directory line)
      $$read$$ <file>   (ffv short text files; simulates cat)
      $$view$$ <file>   (ffv image files directly in std output)
      $$play$$ <file>   (play audio files natively via xmms)
      $$search$$ <query> (search manuscripts for keywords)
      $$clear$$         (refresh terminal)
      $$help$$          (display this manual)
      $$exit$$ / $$logout$$ (exits terminal / La Anima)
    """

    {help_text, cwd}
  end

  defp process_command(cmd, cwd, fs) do
    parts = String.split(cmd, " ", parts: 2, trim: true)

    case parts do
      ["dir"] -> list_dir(cwd, cwd, fs)
      ["dir", target] -> list_dir(parse_path(target, cwd), cwd, fs)
      ["ls"] -> list_dir(cwd, cwd, fs)
      ["ls", target] -> list_dir(parse_path(target, cwd), cwd, fs)
      ["cd"] -> {display_cwd(cwd), cwd}
      ["cd", target] -> change_dir(parse_path(target, cwd), cwd, fs)
      ["pwd"] -> {display_cwd(cwd), cwd}
      ["view", target] -> view_file(parse_path(target, cwd), cwd, fs, :image)
      ["play", target] -> view_file(parse_path(target, cwd), cwd, fs, :audio)
      ["read", target] -> read_file(parse_path(target, cwd), cwd, fs)
      ["search", query] -> search_manuscripts(query, cwd)
      ["grep", query] -> search_manuscripts(query, cwd)
      _ -> {"Bad command or file name", cwd}
    end
  end

  # File system traversal helpers
  defp list_dir(target_cwd, orig_cwd, fs) do
    case get_node(target_cwd, fs) do
      {:dir, contents} ->
        list =
          contents
          |> Map.keys()
          |> Enum.sort()
          |> Enum.join("   ")

        if list == "", do: {"(empty directory)", orig_cwd}, else: {list, orig_cwd}

      _ ->
        {"Path not found", orig_cwd}
    end
  end

  defp change_dir(target_cwd, orig_cwd, fs) do
    case get_node(target_cwd, fs) do
      {:dir, _} -> {nil, target_cwd}
      {:file, _} -> {"Not a directory", orig_cwd}
      _ -> {"Path not found", orig_cwd}
    end
  end

  defp view_file(target_cwd, orig_cwd, fs, expected_type) do
    case get_node(target_cwd, fs) do
      {^expected_type, url} ->
        filename = List.last(target_cwd)
        {%{type: expected_type, url: url, filename: filename}, orig_cwd}

      {:dir, _} ->
        {"Cannot #{expected_type} a directory. Access denied.", orig_cwd}

      {other_type, _} when other_type != expected_type ->
        {"File is not of type #{expected_type}. Access denied.", orig_cwd}

      _ ->
        {"File not found", orig_cwd}
    end
  end

  defp read_file(target_cwd, orig_cwd, fs) do
    case get_node(target_cwd, fs) do
      {:file, contents} ->
        {contents, orig_cwd}

      {:manuscript, category, slug} ->
        case Web.Manuscripts.get_manuscript(category, slug) do
          {:ok, content} -> {content, orig_cwd}
          _ -> {"Error reading manuscript.", orig_cwd}
        end

      {:dir, _} ->
        {"File is a directory. Access denied.", orig_cwd}

      {_, _} ->
        {"Binary file cannot be read as text.", orig_cwd}

      _ ->
        {"File not found", orig_cwd}
    end
  end

  defp search_manuscripts(query, cwd) do
    query_down = String.downcase(query)
    # Filter categories as requested: exclude faith and physical
    allowed_categories = Web.Manuscripts.list_categories() -- ["faith", "physical"]

    results =
      for category <- allowed_categories,
          file <- Web.Manuscripts.list_files(category) do
        {:ok, content} = Web.Manuscripts.get_manuscript(category, file.slug)

        if String.contains?(String.downcase(content), query_down) or
             String.contains?(String.downcase(file.title), query_down) do
          "C:\\DOCS\\#{String.upcase(category)}\\#{String.upcase(file.slug) |> String.replace("-", "_")}.MD"
        else
          nil
        end
      end
      |> Enum.reject(&is_nil/1)

    if Enum.empty?(results) do
      {"No matches found for '#{query}'.", cwd}
    else
      {"Search results for '#{query}':\n\n" <> Enum.join(results, "\n"), cwd}
    end
  end

  defp build_fs do
    base = %{
      "README.TXT" =>
        {:file,
         "Welcome to César's Machine\n-----------------\nThis is a virtual filesystem.\nHere you will find images and audio. Type 'help' for available commands."},
      "GUESTBK.TXT" => {:file, "A backdoor to the guestbook... coming soon."},
      "LINUX_POCKET_GUIDE.TXT" => {:file, @linux_guide},
      "SEVEN_DAY_FITNESS.TXT" => {:file, @fitness_guide},
      "IMAGES" =>
        {:dir,
         %{
           "PORTRAIT.JPG" => {:image, "/images/DSCF7590.JPG"},
           "SPOTIFY_PROFILE.JPG" => {:image, "/images/spotify_profile.jpg"}
         }},
      "AUDIO" =>
        {:dir,
         %{
           "TEST_AUDIO.MP3" => {:audio, "#"}
         }}
    }

    # Filter categories as requested: exclude faith and physical
    allowed_categories = Web.Manuscripts.list_categories() -- ["faith", "physical"]

    docs =
      for category <- allowed_categories, into: %{} do
        files =
          for f <- Web.Manuscripts.list_files(category), into: %{} do
            name = String.upcase(f.slug) |> String.replace("-", "_") |> Kernel.<>(".MD")
            {name, {:manuscript, category, f.slug}}
          end

        {String.upcase(category), {:dir, files}}
      end

    Map.put(base, "DOCS", {:dir, docs})
  end

  defp parse_path("/", _cwd), do: ["C:"]

  defp parse_path(target, cwd) do
    target_clean = target |> String.replace(~r/^C:[\/\\]?/i, "/")
    parts = String.split(target_clean, ["/", "\\"], trim: true)
    base = if String.starts_with?(target_clean, ["/", "\\"]), do: ["C:"], else: cwd
    navigate_path(parts, base)
  end

  defp navigate_path([], current), do: current
  defp navigate_path(["." | rest], current), do: navigate_path(rest, current)

  defp navigate_path([".." | rest], current) do
    if length(current) > 1 do
      navigate_path(rest, Enum.drop(current, -1))
    else
      navigate_path(rest, current)
    end
  end

  defp navigate_path([dir | rest], current) do
    navigate_path(rest, current ++ [String.upcase(dir)])
  end

  defp get_node(["C:"], fs), do: {:dir, fs}

  defp get_node(["C:" | rest], fs) do
    navigate(rest, fs)
  end

  defp navigate([], node), do: {:dir, node}

  defp navigate([segment | rest], current_dir) do
    # Normalize segment to match the underscored virtual filenames
    normalized_segment = String.replace(segment, "-", "_")

    case current_dir[normalized_segment] do
      {:dir, children} -> navigate(rest, children)
      other when rest == [] -> other
      _ -> nil
    end
  end

  defp display_cwd(["C:"]), do: "C:\\>"

  defp display_cwd(cwd_list) do
    path = Enum.join(cwd_list, "\\") |> String.replace("C:\\", "C:\\")
    "#{path}>"
  end

  defp format_info(content) do
    content
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
    |> String.replace(~r/\$\$(.*?)\$\$/, "<span class=\"pc-inverted\">\\1</span>")
    |> String.replace(~r/(-{10,})/, "<span class=\"pc-hr\">\\1</span>")
    |> Phoenix.HTML.raw()
  end
end
