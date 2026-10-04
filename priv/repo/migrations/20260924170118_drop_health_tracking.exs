defmodule Web.Repo.Migrations.DropHealthTracking do
  use Ecto.Migration

  # Health tracking is gone from the site: the /fitness/biometrics page and
  # the Health Auto Export webhook that fed it, and the Apple Health workouts
  # the Activities pages briefly paired with rides. Neither table ever
  # received a row in production — the phone side was never set up — so
  # nothing is lost. Nutrition lives in the fitness vault's markdown, not
  # here, and is untouched.
  def up do
    drop table(:health_workouts)
    drop table(:biometrics)

    execute "DELETE FROM site_settings WHERE key = 'health_webhook_token'"
  end

  def down do
    raise Ecto.MigrationError,
      message: "health tracking was removed; both tables were empty when dropped"
  end
end
