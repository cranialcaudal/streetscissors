defmodule Web.Scanner do
  @moduledoc """
  The scanner studio's context: the flatbed (`Web.Scanner.Bed`, which runs
  the scans `Web.Scanner.Driver` describes) and the path from strip scans to
  a published roll (`Web.Scanner.Pipeline`).
  """

  alias Web.Scanner.Pipeline

  defdelegate next_roll_number, to: Pipeline
  defdelegate format_dir_name(format), to: Pipeline
  defdelegate roll_folder_name(roll_num, date, format, color), to: Pipeline
  defdelegate roll_dir(roll_num, date, format, color), to: Pipeline
  defdelegate prepare_roll(roll_num, date, format, color), to: Pipeline
  defdelegate list_strips(roll_dir), to: Pipeline
  defdelegate next_strip_name(roll_dir), to: Pipeline
  defdelegate add_strip(roll_dir, source_path, client_name), to: Pipeline
  defdelegate rotate_strip(strip_path, degrees \\ 180), to: Pipeline
  defdelegate reorder_strips(roll_dir, ordered_filenames), to: Pipeline
  defdelegate delete_strip(roll_dir, filename), to: Pipeline
  defdelegate generate_frames_analysis(roll_dir, format, color), to: Pipeline
  defdelegate assemble_contact_sheet(roll_dir, roll_num, date, format, color), to: Pipeline
  defdelegate verify_conformance(roll_dir, sheet_path), to: Pipeline
  defdelegate publish_roll(roll_num, date, format, color), to: Pipeline
  defdelegate frame_region(roll_dir, frame), to: Pipeline
  defdelegate keeper_raw_path(roll_dir, frame), to: Pipeline
  defdelegate develop_keeper(roll_dir, frame), to: Pipeline
end
