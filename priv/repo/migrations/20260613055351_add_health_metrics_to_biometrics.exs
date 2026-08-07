defmodule Web.Repo.Migrations.AddHealthMetricsToBiometrics do
  use Ecto.Migration

  def change do
    alter table(:biometrics) do
      add :hrv_ms, :integer
      add :active_calories, :integer
      add :vo2_max, :decimal
      add :spo2_percent, :decimal
      add :respiratory_rate, :decimal
      add :soreness, :integer
      add :energy, :integer
    end
  end
end
