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

  # Everything the dispatcher accepts. Anything NOT in here is treated as a
  # jump target rather than an error, so `roll007` navigates. Tab completion
  # draws from this same list so the two cannot drift apart.
  @commands ~w(
    help ls dir cd pwd read cat view play open frames find search grep refresh
    ps top sys uname date uptime whoami cal history man echo head tail clear cls
    exit logout
  )

  def mount(_params, _session, socket) do
    index = Web.Pc.Index.build()

    counts =
      index
      |> Enum.frequencies_by(& &1.kind)
      |> then(fn c ->
        "#{Map.get(c, :sheet, 0)} rolls · #{Map.get(c, :frame, 0)} frames · " <>
          "#{Map.get(c, :post, 0)} posts · #{Map.get(c, :log, 0)} logs"
      end)

    welcome_message = """
    César's Machine — the short way round

    Type part of any name and press Enter. A contact sheet, a post, a log.
    One match opens it; several list themselves and you press the number.

    César Anthony Moreno                        #{Calendar.strftime(DateTime.utc_now(), "%a %d %b %Y %I:%M:%S %p %Z")}
    INDEXED: #{counts}

    COMMANDS OF NOTE:
      $$<name>$$        (just type it — roll007, or 7, and press Enter)
      $$open$$ <name>   (same thing, said out loud)
      $$ls$$ / $$cd$$       (look around)
      $$view$$ / $$cat$$    (render a sheet, or read a post, without leaving)
      $$frames$$ <roll> (list a roll's frames)
      $$find$$ / $$grep$$   (by name / by full text)
      $$help$$          (more instructions)
    """

    {:ok,
     assign(socket,
       cwd: ["C:"],
       history: [%{type: :info, content: welcome_message}],
       index: index,
       fs: build_fs(index),
       # Set when a jump was ambiguous; a bare digit then picks from this list.
       pending: [],
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

    # Split the last word on path separators to find the directory being
    # completed in. Case is preserved — completing against real filenames is
    # the whole point, and upcasing here used to make them unreachable.
    path_parts = String.split(last_word, ["/", "\\"], trim: false)
    search_prefix = List.last(path_parts) || ""
    search_prefix_normalized = search_prefix

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

    # Initial command candidates if only one word. Drawn from @commands so the
    # completer cannot drift out of step with what the dispatcher accepts.
    initial_candidates =
      if length(parts) <= 1 and dir_path_up == "",
        do: @commands ++ local_candidates,
        else: local_candidates

    target = String.downcase(search_prefix_normalized)

    matches =
      initial_candidates
      |> Enum.filter(&String.starts_with?(String.downcase(&1), target))
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
        # Never downcase: the completion may be a real filename whose case
        # matters, e.g. "Contact Sheets".
        new_val = String.trim(prefix_cmd <> " " <> final_word)

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
          # Never downcase: the completion may be a real filename whose case
          # matters, e.g. "Contact Sheets".
          new_val = String.trim(prefix_cmd <> " " <> final_word)

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

          case output do
            # A jump: say where we are going, then go. The line stays in the
            # scrollback so a back-button return shows what happened.
            {:navigate, route, note} ->
              {:noreply,
               socket
               |> assign(
                 history: new_history ++ [%{type: :info, content: note}],
                 cwd: new_cwd,
                 command: "",
                 pending: []
               )
               |> push_navigate(to: route)}

            # Re-read the content sources without reloading the page, for when
            # a roll or a post has just been added.
            {:refresh, _} ->
              index = Web.Pc.Index.build()

              {:noreply,
               assign(socket,
                 index: index,
                 fs: build_fs(index),
                 history:
                   new_history ++
                     [%{type: :info, content: "Index rebuilt — #{length(index)} entries."}],
                 cwd: new_cwd,
                 command: "",
                 pending: []
               )}

            # An ambiguous jump: remember the candidates so a bare digit picks.
            {:choices, matches, text} ->
              {:noreply,
               assign(socket,
                 history: new_history ++ [%{type: :info, content: text}],
                 cwd: new_cwd,
                 command: "",
                 pending: matches
               )}

            nil ->
              {:noreply,
               assign(socket, history: new_history, cwd: new_cwd, command: "", pending: [])}

            %{type: _} = out ->
              {:noreply,
               assign(socket,
                 history: new_history ++ [out],
                 cwd: new_cwd,
                 command: "",
                 pending: []
               )}

            text ->
              {:noreply,
               assign(socket,
                 history: new_history ++ [%{type: :info, content: text}],
                 cwd: new_cwd,
                 command: "",
                 pending: []
               )}
          end
        end
    end
  end

  defp find_globally(prefix, fs, current_path \\ []) do
    target = String.downcase(prefix)

    Enum.flat_map(fs, fn {name, node} ->
      new_path = current_path ++ [name]
      # Return results as relative paths from root-ish strings
      matches =
        if String.starts_with?(String.downcase(name), target),
          do: [Enum.join(new_path, "/")],
          else: []

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
  #
  # Anything that is not a known command is treated as a jump target rather
  # than rejected — typing `roll007` and pressing Enter is the whole point of
  # this terminal, and it used to answer "Bad command or file name".
  defp process_command(input, cwd, socket) do
    parts = String.split(input, " ", parts: 2, trim: true)

    case parts do
      [cmd] ->
        if known_command?(cmd),
          do: handle_single_cmd(String.downcase(cmd), cwd, socket),
          else: jump(input, cwd, socket)

      [cmd, arg] ->
        if known_command?(cmd),
          do: handle_arg_cmd(String.downcase(cmd), arg, cwd, socket),
          else: jump(input, cwd, socket)

      _ ->
        {"Bad command or file name", cwd}
    end
  end

  defp known_command?(cmd), do: String.downcase(cmd) in @commands

  # ── Jumping ───────────────────────────────────────────────────────

  # A bare digit means "the nth of those choices you just listed" when a list is
  # pending, and "roll n" otherwise. Rolls are numbers too, so the precedence
  # has to be stated somewhere; here it is.
  defp jump(input, cwd, socket) do
    pending = socket.assigns.pending

    case {Integer.parse(String.trim(input)), pending} do
      {{n, ""}, [_ | _]} when n > 0 ->
        case Enum.at(pending, n - 1) do
          nil -> {"No choice #{n}. #{length(pending)} were listed.", cwd}
          entry -> navigate_to(entry, cwd)
        end

      _ ->
        resolve_jump(input, cwd, socket)
    end
  end

  defp resolve_jump(query, cwd, socket) do
    case Web.Pc.Index.best(socket.assigns.index, query) do
      :none ->
        {"Nothing here matches '#{query}'. Try 'find #{query}' or 'grep #{query}'.", cwd}

      {:one, entry} ->
        navigate_to(entry, cwd)

      {:many, matches} ->
        shown = Enum.take(matches, 9)

        listing =
          shown
          |> Enum.with_index(1)
          |> Enum.map_join("\n", fn {entry, i} ->
            "  #{i}  #{pad(entry.name, 34)} #{route_for(entry)}"
          end)

        more =
          if length(matches) > 9,
            do: "\n\n(#{length(matches) - 9} more — narrow the search)",
            else: ""

        {{:choices, shown,
          "#{length(matches)} matches — press the number, or refine:\n\n#{listing}#{more}"}, cwd}
    end
  end

  defp navigate_to(entry, cwd) do
    {{:navigate, route_for(entry),
      "→ #{Web.Pc.Index.path(entry)}\n  opening #{route_for(entry)}"}, cwd}
  end

  # Routes are built here, through ~p, so they stay verified — which is why
  # Web.Pc.Index stores kind + id rather than a URL string.
  defp route_for(%{kind: :sheet, id: %{slug: slug}}), do: ~p"/negatives?slug=#{slug}"

  defp route_for(%{kind: :frame, id: %{roll_num: roll, frame: frame}}),
    do: ~p"/negatives/roll/#{roll}/frame/#{frame}"

  defp route_for(%{kind: :post, id: %{slug: slug}}), do: ~p"/blog/#{slug}"
  defp route_for(%{kind: :log, id: %{slug: slug}}), do: ~p"/logs/#{slug}"

  defp pad(text, width), do: String.pad_trailing(text, width)

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

  defp handle_single_cmd("refresh", cwd, _socket), do: {{:refresh, nil}, cwd}
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
    do:
      view_file(
        parse_path(target, cwd),
        cwd,
        socket.assigns.fs,
        :image,
        socket.assigns.index,
        target
      )

  defp handle_arg_cmd("play", target, cwd, socket),
    do:
      view_file(
        parse_path(target, cwd),
        cwd,
        socket.assigns.fs,
        :audio,
        socket.assigns.index,
        target
      )

  defp handle_arg_cmd("read", target, cwd, socket),
    do: read_file(parse_path(target, cwd), cwd, socket.assigns.fs, socket.assigns.index, target)

  defp handle_arg_cmd("cat", target, cwd, socket),
    do: read_file(parse_path(target, cwd), cwd, socket.assigns.fs, socket.assigns.index, target)

  defp handle_arg_cmd("head", target, cwd, socket),
    do:
      read_file_partial(
        parse_path(target, cwd),
        cwd,
        socket.assigns.fs,
        :head,
        socket.assigns.index,
        target
      )

  defp handle_arg_cmd("tail", target, cwd, socket),
    do:
      read_file_partial(
        parse_path(target, cwd),
        cwd,
        socket.assigns.fs,
        :tail,
        socket.assigns.index,
        target
      )

  defp handle_arg_cmd("open", target, cwd, socket), do: resolve_jump(target, cwd, socket)
  defp handle_arg_cmd("frames", roll, cwd, socket), do: list_roll_frames(roll, cwd, socket)
  defp handle_arg_cmd("search", query, cwd, socket), do: grep_content(query, cwd, socket)
  defp handle_arg_cmd("grep", query, cwd, socket), do: grep_content(query, cwd, socket)
  defp handle_arg_cmd("find", query, cwd, socket), do: find_by_name(query, cwd, socket)
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

    GETTING SOMEWHERE (the point of this machine)
      $$<name>$$         just type it and press Enter — roll007, or 7
      $$open$$ <name>    the same thing, said out loud
      <number>       picks from a list of matches you were just shown

      Names are the machine's own: roll007_2026-07-22_120_bw, not
      ROLL007_2026_07_22_120_BW. Case does not matter when you type them.

    LOOKING WITHOUT LEAVING
      $$ls$$ / $$dir$$       (list the working directory)
      $$cd$$ <dir>       (change directory; e.g. cd NEGATIVES, cd ..)
      $$pwd$$            (print working directory)
      $$view$$ <sheet>   (render a contact sheet or frame here)
      $$play$$ <log>     (play a captain's log here)
      $$read$$ / $$cat$$     (read a post as text)
      $$frames$$ <roll>  (list every frame on a roll)

    FINDING
      $$find$$ <query>   (by name — prints the path and the destination)
      $$grep$$ <query>   (by full text — post bodies and log notes)
      $$refresh$$        (rebuild the index after adding a roll or a post)

    THE MACHINE
      $$sys$$ / $$ps$$       (hardware and process vitals)
      $$clear$$          (wipe the screen)
      $$help$$           (display this manual)
      $$exit$$ / $$logout$$  (leave the terminal)

    TAB completes names. ESC exits.
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
      "find" -> "FIND(1) - locate content by name; prints path and destination"
      "open" -> "OPEN(1) - navigate to a piece of content. A bare name does the same."
      "frames" -> "FRAMES(1) - list the frames on a roll, e.g. 'frames 7'"
      "refresh" -> "REFRESH(1) - rebuild the content index without reloading"
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

  defp read_file_partial(target_cwd, orig_cwd, fs, mode, index, raw) do
    case get_node(target_cwd, fs) do
      {:file, contents} ->
        lines = String.split(contents, "\n")
        partial = if mode == :head, do: Enum.take(lines, 10), else: Enum.take(lines, -10)
        {Enum.join(partial, "\n"), orig_cwd}

      _ ->
        read_file(target_cwd, orig_cwd, fs, index, raw)
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

  # `view` and `play` render inline and stay put — the counterpart to `open`,
  # which navigates. Both accept a bare name as well as a path, so `view
  # roll007` works from anywhere without first cd-ing to the sheet.
  defp view_file(target_cwd, orig_cwd, fs, expected_type, index, raw) do
    case resolve_media(target_cwd, fs, index, raw) do
      {kind, %{media_url: url} = entry} when not is_nil(url) ->
        if media_kind(kind) == expected_type do
          {%{type: expected_type, url: url, filename: entry.file}, orig_cwd}
        else
          {"#{entry.file} is not something you can #{expected_type}.", orig_cwd}
        end

      {:dir, _} ->
        {"Cannot #{expected_type} a directory.", orig_cwd}

      {_, _} ->
        {"Not a #{expected_type} file.", orig_cwd}

      _ ->
        {"File not found. Try 'find #{raw}'.", orig_cwd}
    end
  end

  defp media_kind(:sheet), do: :image
  defp media_kind(:frame), do: :image
  defp media_kind(:log), do: :audio
  defp media_kind(other), do: other

  # Path first, then the index — so a name that is not in the current directory
  # still resolves.
  defp resolve_media(target_cwd, fs, index, raw) do
    case get_node(target_cwd, fs) do
      nil ->
        case Web.Pc.Index.search(index, raw) do
          [entry | _] -> {entry.kind, entry}
          [] -> nil
        end

      node ->
        node
    end
  end

  defp read_file(target_cwd, orig_cwd, fs, index, raw) do
    case resolve_media(target_cwd, fs, index, raw) do
      {:file, contents} ->
        {contents, orig_cwd}

      {:post, %{id: %{slug: slug}}} ->
        case Web.Blog.get_post(slug) do
          {:ok, post} -> {post.body, orig_cwd}
          _ -> {"Error reading file.", orig_cwd}
        end

      {:log, %{id: %{slug: slug}, label: label}} ->
        case Web.Audio.get_published_log_by_slug(slug) do
          {:ok, log} -> {"#{label}\n\n#{log.description || "(no notes)"}", orig_cwd}
          _ -> {"Error reading log.", orig_cwd}
        end

      {:dir, _} ->
        {"File is a directory.", orig_cwd}

      {kind, _} when kind in [:sheet, :frame] ->
        {"That is an image — use 'view' instead.", orig_cwd}

      _ ->
        {"File not found. Try 'find #{raw}'.", orig_cwd}
    end
  end

  # Searches every indexed name — sheets, frames, posts and logs — and prints
  # the real path alongside where Enter would take you. The old version only
  # matched names in the invented filesystem.
  defp find_by_name(query, cwd, socket) do
    case Web.Pc.Index.search(socket.assigns.index, query) do
      [] ->
        {"No names match '#{query}'.", cwd}

      matches ->
        shown = Enum.take(matches, 20)

        listing =
          Enum.map_join(shown, "\n", fn entry ->
            "  #{pad(Web.Pc.Index.path(entry), 52)} #{route_for(entry)}"
          end)

        more =
          if length(matches) > 20, do: "\n\n(#{length(matches) - 20} more)", else: ""

        {"#{length(matches)} matching '#{query}':\n\n#{listing}#{more}", cwd}
    end
  end

  # Full text, not just names: post bodies and log notes. Bodies are read once
  # per query inside the index rather than once per post per query.
  defp grep_content(query, cwd, socket) do
    case Web.Pc.Index.grep(socket.assigns.index, query) do
      [] ->
        {"No matches for '#{query}'.", cwd}

      hits ->
        listing =
          Enum.map_join(Enum.take(hits, 20), "\n\n", fn {entry, line} ->
            "  #{Web.Pc.Index.path(entry)}\n    #{line}"
          end)

        {"#{length(hits)} matching '#{query}':\n\n#{listing}", cwd}
    end
  end

  defp list_roll_frames(roll, cwd, socket) do
    frames =
      socket.assigns.index
      |> Web.Pc.Index.search(roll)
      |> Enum.filter(&(&1.kind == :frame))

    case frames do
      [] ->
        {"No frames for '#{roll}'. The roll folder may hold no scans yet.", cwd}

      frames ->
        listing =
          Enum.map_join(frames, "\n", fn entry ->
            "  #{pad(entry.file, 40)} #{route_for(entry)}"
          end)

        {"#{length(frames)} frames:\n\n#{listing}\n\nOpen one by name, e.g. #{hd(frames).name}",
         cwd}
    end
  end

  # The tree mirrors what is actually on the machine — real filenames, real
  # case, real extensions. It used to be almost entirely invented, and the one
  # real thing in it (blog posts) was mangled by `upcase` + "-"=>"_" into names
  # that existed nowhere on disk. Lookups are case-insensitive instead.
  defp build_fs(index) do
    base = %{
      "README.TXT" =>
        {:file,
         "César's Machine\n---------------\nThis is the fastest way around the site.\n\nType part of any name and press Enter — a contact sheet, a post, a log.\nOne match opens it. Several list themselves; press the number.\n\nEverything here is named the way it is named on the machine:\nroll007_2026-07-22_120_bw, not ROLL007_2026_07_22_120_BW.\n\nType 'help' for the full command list."},
      "LINUX_POCKET_GUIDE.TXT" => {:file, @linux_guide},
      "SEVEN_DAY_FITNESS.TXT" => {:file, @fitness_guide},
      "TUTORIAL" => {:dir, tutorial_files()}
    }

    base
    |> put_catalog()
    |> then(fn fs -> Enum.reduce(index, fs, &insert_entry/2) end)
  end

  defp insert_entry(entry, fs) do
    put_path(fs, entry.dir ++ [entry.file], {entry.kind, entry})
  end

  # Inserts a node at a nested path, creating {:dir, _} nodes on the way down.
  defp put_path(fs, [leaf], node), do: Map.put(fs, leaf, node)

  defp put_path(fs, [segment | rest], node) do
    children =
      case Map.get(fs, segment) do
        {:dir, existing} -> existing
        _ -> %{}
      end

    Map.put(fs, segment, {:dir, put_path(children, rest, node)})
  end

  # The real catalog.csv off the negatives volume — the index of the archive
  # belongs in the archive.
  defp put_catalog(fs) do
    case File.read(Web.Negatives.catalog_path()) do
      {:ok, contents} -> put_path(fs, ["NEGATIVES", "catalog.csv"], {:file, contents})
      _ -> fs
    end
  end

  defp tutorial_files do
    %{
      "START.TXT" =>
        {:file,
         "LESSON 1: GETTING SOMEWHERE FAST\n--------------------------------\nThis terminal is a navigator. The quickest way to use it is to type\npart of what you want and press Enter.\n\n  roll007        opens that contact sheet\n  roll007_03     opens frame 3 of that roll\n  7              same as roll007 — rolls answer to their number\n\nIf several things match they list themselves, and you press the number.\n\nPRO TIP: 'clear' wipes the screen. TAB completes names."},
      "LOOKING.TXT" =>
        {:file,
         "LESSON 2: LOOKING BEFORE YOU LEAP\n---------------------------------\nSometimes you want to see a thing without leaving the terminal.\n\n  ls             list what is here\n  cd NEGATIVES   move around\n  view roll007   render the contact sheet right here\n  cat <post>     read a post as text\n  frames 7       list every frame on roll 7\n\n'open' always navigates. 'view' and 'cat' always stay put."},
      "SEARCHING.TXT" =>
        {:file,
         "LESSON 3: FINDING THINGS\n------------------------\n  find 35mm      every name containing 35mm\n  grep ferry     full text — post bodies and log notes, not just names\n\nBoth print the real path and where Enter would take you.\n\nPRO TIP: 'man <command>' explains any command. 'refresh' rebuilds the\nindex if you have just added a roll or a post."}
    }
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

  # Segments keep the case they were typed in; `navigate/2` matches them
  # case-insensitively against the real names. Upcasing here is what made
  # `roll007_2026-07-22_120_bw` unreachable.
  defp navigate_path([dir | rest], current) do
    navigate_path(rest, current ++ [dir])
  end

  defp get_node(["C:"], fs), do: {:dir, fs}

  defp get_node(["C:" | rest], fs) do
    navigate(rest, fs)
  end

  defp navigate([], node), do: {:dir, node}

  defp navigate([segment | rest], current_dir) do
    case lookup(current_dir, segment) do
      {:dir, children} -> navigate(rest, children)
      other when rest == [] -> other
      _ -> nil
    end
  end

  # Case-insensitive by name, so `NEGATIVES` and `negatives` both resolve, and
  # a real filename typed in its real case always works. An exact hit wins so
  # the common path stays a plain map lookup.
  defp lookup(dir, segment) do
    case Map.get(dir, segment) do
      nil ->
        target = String.downcase(segment)

        Enum.find_value(dir, fn {name, node} ->
          if String.downcase(name) == target, do: node
        end)

      node ->
        node
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
