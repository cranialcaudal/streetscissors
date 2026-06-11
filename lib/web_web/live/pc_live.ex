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
    fs = build_fs()

    welcome_message = """
    César's Machine - DOS Terminal

    This is not meant to be a comprehensive or even complete description of various commands.
    Rather, the commands before you are presented as a cheat sheet, a starter. Knowing
    how to talk to your machine is awesome, I think.

    César Anthony Moreno                        #{Calendar.strftime(DateTime.utc_now(), "%a %d %b %Y %I:%M:%S %p %Z")}

    COMMANDS OF NOTE:
      $$ls$$ / $$dir$$      (list files)
      $$cd$$            (changes directory)
      $$read$$ / $$cat$$    (ffv short text files)
      $$view$$          (ffv image files)
      $$play$$          (play audio files)
      $$search$$ / $$grep$$   (keyword search)
      $$find$$          (locate any site asset)
      $$help$$          (more instructions)
      $$clear$$         (refresh terminal)
    """

    {:ok,
     assign(socket,
       cwd: ["C:"],
       history: [%{type: :info, content: welcome_message}],
       fs: fs,
       command: ""
     ), layout: false}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  def render(assigns) do
    ~H"""
    <div class="pc-container" id="pc-terminal" phx-hook="AutoScroll">
      <div class="pc-crt-overlay"></div>

      <div class="pc-header">
        <a href="/" class="pc-back-link">[← ESC to exit]</a>
        <div style="text-align: right;">
          <span style="opacity: 0.8; display: block;">MS-DOS Prompt - "César's Machine"</span>
          <span style="font-size: 0.85rem; opacity: 0.6;">
            TERMINAL v2.0 - ASSET DISCOVERY MODE
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
      "CAT",
      "CLS",
      "CLEAR",
      "HELP",
      "PWD",
      "SEARCH",
      "GREP",
      "FIND",
      "PS",
      "TOP",
      "SYS",
      "UNAME",
      "DATE",
      "WHOAMI",
      "HISTORY",
      "MAN",
      "EXIT",
      "LOGOUT",
      "ECHO",
      "HEAD",
      "TAIL",
      "CAL",
      "UPTIME"
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
          {output, new_cwd} = process_command(input, cwd, socket)

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
  defp process_command(input, cwd, socket) do
    parts = String.split(input, " ", parts: 2, trim: true)

    case parts do
      [cmd] -> handle_single_cmd(String.downcase(cmd), cwd, socket)
      [cmd, arg] -> handle_arg_cmd(String.downcase(cmd), arg, cwd, socket)
      _ -> {"Bad command or file name", cwd}
    end
  end

  defp handle_single_cmd("help", cwd, _socket), do: {get_help_text(), cwd}
  defp handle_single_cmd("ls", cwd, socket), do: list_dir(cwd, cwd, socket.assigns.fs)
  defp handle_single_cmd("dir", cwd, socket), do: list_dir(cwd, cwd, socket.assigns.fs)
  defp handle_single_cmd("pwd", cwd, _socket), do: {display_cwd(cwd), cwd}
  defp handle_single_cmd("ps", cwd, _socket), do: {simulated_ps(), cwd}
  defp handle_single_cmd("top", cwd, _socket), do: {simulated_ps(), cwd}
  defp handle_single_cmd("uname", cwd, _socket), do: {"EL CARNAL", cwd}
  defp handle_single_cmd("sys", cwd, _socket), do: {simulated_sys(), cwd}

  defp handle_single_cmd("date", cwd, _socket),
    do: {Calendar.strftime(DateTime.utc_now(), "%a %d %b %Y %I:%M:%S %p %Z"), cwd}

  defp handle_single_cmd("uptime", cwd, _socket),
    do: {"up 2 days, 4:12, 1 user, load average: 0.05, 0.12, 0.08", cwd}

  defp handle_single_cmd("whoami", cwd, _socket), do: {"cesar", cwd}
  defp handle_single_cmd("cal", cwd, _socket), do: {simulated_cal(), cwd}

  defp handle_single_cmd("history", cwd, socket),
    do: {format_history(socket.assigns.history), cwd}

  defp handle_single_cmd("man", cwd, _socket), do: {"What manual page do you want?", cwd}
  defp handle_single_cmd("cd", cwd, _socket), do: {display_cwd(cwd), cwd}
  defp handle_single_cmd("echo", cwd, _socket), do: {"", cwd}

  defp handle_single_cmd(cmd, cwd, _socket)
       when cmd in ["read", "cat", "view", "play", "search", "grep", "find", "head", "tail"] do
    {"Usage: #{String.upcase(cmd)} <target>", cwd}
  end

  defp handle_single_cmd(_, cwd, _socket), do: {"Bad command or file name", cwd}

  defp handle_arg_cmd("ls", target, cwd, socket),
    do: list_dir(parse_path(target, cwd), cwd, socket.assigns.fs)

  defp handle_arg_cmd("dir", target, cwd, socket),
    do: list_dir(parse_path(target, cwd), cwd, socket.assigns.fs)

  defp handle_arg_cmd("cd", target, cwd, socket),
    do: change_dir(parse_path(target, cwd), cwd, socket.assigns.fs)

  defp handle_arg_cmd("view", target, cwd, socket),
    do: view_file(parse_path(target, cwd), cwd, socket.assigns.fs, :image)

  defp handle_arg_cmd("play", target, cwd, socket),
    do: view_file(parse_path(target, cwd), cwd, socket.assigns.fs, :audio)

  defp handle_arg_cmd("read", target, cwd, socket),
    do: read_file(parse_path(target, cwd), cwd, socket.assigns.fs)

  defp handle_arg_cmd("cat", target, cwd, socket),
    do: read_file(parse_path(target, cwd), cwd, socket.assigns.fs)

  defp handle_arg_cmd("head", target, cwd, socket),
    do: read_file_partial(parse_path(target, cwd), cwd, socket.assigns.fs, :head)

  defp handle_arg_cmd("tail", target, cwd, socket),
    do: read_file_partial(parse_path(target, cwd), cwd, socket.assigns.fs, :tail)

  defp handle_arg_cmd("search", query, cwd, _socket), do: search_manuscripts(query, cwd)
  defp handle_arg_cmd("grep", query, cwd, _socket), do: search_manuscripts(query, cwd)
  defp handle_arg_cmd("find", query, cwd, socket), do: find_assets(query, cwd, socket.assigns.fs)
  defp handle_arg_cmd("man", cmd, cwd, _socket), do: {get_manual(cmd), cwd}
  defp handle_arg_cmd("echo", text, cwd, _socket), do: {text, cwd}

  defp handle_arg_cmd("uname", "-a", cwd, _socket),
    do: {"EL CARNAL 1.0.0-STREETSCISSORS #1 SMP Tue Mar 10 2026 x86_64 GNU/Linux", cwd}

  defp handle_arg_cmd(_, _, cwd, _socket), do: {"Bad command or file name", cwd}

  defp get_help_text do
    """
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
      $$read$$ / $$cat$$   (read text files; simulates cat)
      $$view$$ <file>   (render image files)
      $$play$$ <file>   (play audio files)
      $$search$$ / $$grep$$ (search documents for keywords)
      $$find$$ <query>  (locate any site asset by name)
      $$sys$$ / $$ps$$      (hardware and process vitals)
      $$clear$$         (refresh terminal)
      $$help$$          (display this manual)
      $$exit$$ / $$logout$$ (exits terminal)
    """
  end

  defp format_history(history) do
    history
    |> Enum.filter(&(&1.type == :command))
    |> Enum.map_join("\n", & &1.content)
  end

  defp get_manual(cmd) do
    case String.downcase(cmd) do
      "ls" -> "LS(1) - list directory contents"
      "dir" -> "DIR(1) - list directory contents"
      "cd" -> "CD(1) - change the working directory"
      "read" -> "READ(1) - read file contents (cat-like)"
      "cat" -> "CAT(1) - concatenate files and print on the standard output"
      "view" -> "VIEW(1) - render image files in the terminal"
      "play" -> "PLAY(1) - play audio files"
      "ps" -> "PS(1) - report a snapshot of the current processes"
      "sys" -> "SYS(1) - display system hardware vitals"
      "whoami" -> "WHOAMI(1) - print effective userid"
      "uname" -> "UNAME(1) - print system information"
      "find" -> "FIND(1) - locate files in the virtual filesystem"
      "echo" -> "ECHO(1) - display a line of text"
      "head" -> "HEAD(1) - output the first part of files"
      "tail" -> "TAIL(1) - output the last part of files"
      "cal" -> "CAL(1) - display a calendar"
      "date" -> "DATE(1) - print or set the system date and time"
      "uptime" -> "UPTIME(1) - tell how long the system has been running"
      "history" -> "HISTORY(1) - GNU History Library"
      _ -> "No manual entry for #{cmd}"
    end
  end

  defp simulated_cal do
    today = Date.utc_today()
    month_name = Calendar.strftime(today, "%B %Y")

    # Very simple static-ish calendar for the current month
    """
          #{month_name}
    Su Mo Tu We Th Fr Sa
                   1  2
     3  4  5  6  7  8  9
    10 11 12 13 14 15 16
    17 18 19 20 21 22 23
    24 25 26 27 28 29 30
    31
    """
  end

  defp read_file_partial(target_cwd, orig_cwd, fs, mode) do
    case get_node(target_cwd, fs) do
      {:file, contents} ->
        lines = String.split(contents, "\n")
        partial = if mode == :head, do: Enum.take(lines, 10), else: Enum.take(lines, -10)
        {Enum.join(partial, "\n"), orig_cwd}

      _ ->
        read_file(target_cwd, orig_cwd, fs)
    end
  end

  defp simulated_ps do
    """
    PID  TTY      TIME     CMD
    1    ?        00:00:01 el_carnal_init
    42   ?        00:00:15 la_anima_server
    108  tty1     00:00:00 sh
    109  tty1     00:00:00 ps
    """
  end

  defp simulated_sys do
    temp = Enum.random(42..58)
    uptime = "2 days, 4 hours, 12 minutes"

    """
    SYSTEM STATUS:
    --------------
    CPU TEMP:    #{temp}C
    LOAD AVG:    0.05, 0.12, 0.08
    UPTIME:      #{uptime}
    DISK USAGE:  [#####-----] 52%
    PHOSPHOR:    STABLE
    """
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

  defp find_assets(query, cwd, fs) do
    query_up = String.upcase(query)
    results = search_fs_node(fs, query_up, ["C:"])

    if Enum.empty?(results) do
      {"No files found matching '#{query}'.", cwd}
    else
      {"Matches found:\n\n" <> Enum.join(results, "\n"), cwd}
    end
  end

  defp search_fs_node(contents, query, path) do
    Enum.flat_map(contents, fn {name, node} ->
      current_path = path ++ [name]
      matches = if String.contains?(name, query), do: [Enum.join(current_path, "\\")], else: []

      case node do
        {:dir, children} -> matches ++ search_fs_node(children, query, current_path)
        _ -> matches
      end
    end)
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
    |> Map.put(
      "TUTORIAL",
      {:dir,
       %{
         "START.TXT" =>
           {:file,
            "LESSON 1: THE BASICS\n------------------\nWelcome. The terminal is about direct communication with the machine.\n\nType 'ls' to see what is around you.\nType 'cd <folder>' to enter a folder (e.g., cd DOCS).\nType 'cd ..' to go back to the previous folder.\nType 'cat <file>' to read a file.\n\nPRO TIP: Type 'clear' to wipe the screen at any time."},
         "ASSETS.TXT" =>
           {:file,
            "LESSON 2: DISCOVERY\n--------------------\nCésar's Machine is a hub for everything on this site.\n\nType 'find .jpg' to see every image path.\nType 'view IMAGES/PORTRAIT.JPG' to see a file directly.\nType 'play AUDIO/TEST_AUDIO.MP3' to hear audio assets.\n\nPRO TIP: Use 'man <command>' to see detailed manuals."},
         "POWER.TXT" =>
           {:file,
            "LESSON 3: EFFICIENCY\n--------------------\nLinux is built for speed.\n\nType 'grep ironman' to search all documents for a word.\nType 'history' to see your previous commands.\nType 'sys' to check hardware vitals.\n\nPRO TIP: Use the 'TAB' key to auto-complete filenames!"},
         "EXERCISES.TXT" =>
           {:file,
            "PRACTICE EXERCISES\n------------------\nCan you 'solve' the machine? Try these tasks:\n\n1. [BASIC] Find the 'START.TXT' file and read it using 'cat'.\n2. [NAV] Go into the 'IMAGES' folder and 'view' the portrait.\n3. [SEARCH] Find every file on the machine that ends in '.MD'.\n4. [DATA] Check the current date using 'date' and the calendar using 'cal'.\n5. [EXPERT] Use 'grep' to find every mention of 'baseball' in the DOCS.\n6. [VITALS] Check 'uptime' to see how long the server has been active.\n\nType 'help' if you get stuck."}
       }}
    )
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
