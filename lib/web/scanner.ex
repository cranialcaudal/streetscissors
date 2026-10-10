defmodule Web.Scanner do
  @moduledoc """
  The scanner studio's context: the flatbed (`Web.Scanner.Bed`, which runs
  the scans `Web.Scanner.Driver` describes) and the path from strip scans to
  a published roll (`Web.Scanner.Pipeline`).
  """

  alias Web.Scanner.Pipeline

  defdelegate next_roll_number, to: Pipeline
  defdelegate roll_in_progress(opts \\ []), to: Pipeline
  defdelegate format_dir_name(format), to: Pipeline
  defdelegate roll_folder_name(roll_num, date, format, color), to: Pipeline
  defdelegate roll_dir(roll_num, date, format, color), to: Pipeline
  defdelegate prepare_roll(roll_num, date, format, color), to: Pipeline
  defdelegate list_strips(roll_dir), to: Pipeline
  defdelegate next_strip_name(roll_dir), to: Pipeline
  defdelegate add_strip(roll_dir, source_path, client_name), to: Pipeline
  defdelegate rotate_strip(strip_path, degrees \\ 180), to: Pipeline
  defdelegate reorder_strips(roll_dir, ordered_filenames), to: Pipeline
  defdelegate unpublished_rolls(opts \\ []), to: Pipeline
  defdelegate generate_frames_analysis_for(roll_dir), to: Pipeline
  defdelegate delete_strip(roll_dir, filename), to: Pipeline
  defdelegate split_roll(roll_dir, from_file), to: Pipeline
  defdelegate generate_frames_analysis(roll_dir, format, color, opts \\ []), to: Pipeline
  defdelegate slide?(roll_dir), to: Pipeline
  defdelegate frames(roll_dir), to: Pipeline
  defdelegate add_pass(roll_dir, scan, dpi, strips, color, rows \\ nil), to: Pipeline
  defdelegate holder(roll_dir), to: Pipeline
  defdelegate relocate(roll_dir, scan, dpi, found, rows \\ nil), to: Pipeline
  defdelegate identify(rolls, scan, dpi, found, rows), to: Pipeline
  defdelegate pending_load(roll_dir), to: Pipeline
  defdelegate confirm_load(roll_dir), to: Pipeline
  defdelegate discard_load(roll_dir), to: Pipeline
  defdelegate remove_print(roll_dir, frame), to: Pipeline
  defdelegate finish_roll(roll_num, date, format, color), to: Pipeline
  defdelegate glass_rect(roll_dir, frame, margin), to: Pipeline

  defdelegate cut_from_band(roll_dir, frame, band, band_rect, frame_rect, dpi), to: Pipeline
  defdelegate printed_frames(roll_dir), to: Pipeline
  defdelegate suggested?(frame), to: Pipeline
  defdelegate record_selects(roll_dir, offered, chosen), to: Pipeline
  defdelegate read_selects(roll_dir), to: Pipeline
  defdelegate owed_singles(roll_dir), to: Pipeline
  defdelegate rotation(roll_dir, frame), to: Pipeline
  defdelegate turn_frame(roll_dir, frame), to: Pipeline
  defdelegate assemble_contact_sheet(roll_dir, roll_num, date, format, color), to: Pipeline
  defdelegate verify_conformance(roll_dir, sheet_path), to: Pipeline
  defdelegate publish_roll(roll_num, date, format, color), to: Pipeline
  defdelegate frame_region(roll_dir, frame), to: Pipeline
  defdelegate keeper_raw_path(roll_dir, frame), to: Pipeline
  defdelegate develop_keeper(roll_dir, frame), to: Pipeline
end
