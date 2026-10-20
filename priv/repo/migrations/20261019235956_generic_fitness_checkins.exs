defmodule Web.Repo.Migrations.GenericFitnessCheckins do
  use Ecto.Migration

  # A check-in's questions come from the vault (content/fitness/checkins.md,
  # Web.Fitness.Checks), not from columns: an Achilles' "quiet|talking|
  # angry", a knee's stairs test, a bodyweight. The day's answers are one map,
  # keyed by the check's id. The fixed pain/sleep/soreness/energy columns of
  # the first version held no rows when this ran.
  def change do
    alter table(:fitness_checkins) do
      add :answers, :map, null: false, default: %{}
      remove :pain, :integer
      remove :sleep_hours, :float
      remove :soreness, :integer
      remove :energy, :integer
    end
  end
end
