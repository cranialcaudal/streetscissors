defmodule Web.Fitness.BiometricTest do
  # Not async: one describe points :fitness_path at an empty directory.
  use ExUnit.Case, async: false

  alias Web.Fitness.Biometric

  # Goals and height come from the fixture vault's biometric-goals.json (see
  # config/test.exs) — invented numbers, not anyone's real targets.

  describe "bmi/1" do
    # The CSV export used to hardcode a height, which misreported every entry.
    # Height now lives in one place: the vault.
    test "derives BMI from the vault's standing height" do
      assert Biometric.height_inches() == 70
      assert Biometric.bmi(%Biometric{weight_lbs: Decimal.new("150")}) == 21.5
    end

    test "takes an explicit height, for deriving many rows at once" do
      assert Biometric.bmi(%Biometric{weight_lbs: Decimal.new("150")}, 60) == 29.3
    end

    test "is nil without a weight" do
      refute Biometric.bmi(%Biometric{weight_lbs: nil})
    end
  end

  describe "goals/0" do
    test "reads the goals from the vault" do
      goals = Biometric.goals()

      assert goals[:protein_grams] == 130
      assert goals[:fiber_grams] == 30
      assert goals[:calories_in] == 2400
      assert goals[:active_calories] == 600
    end

    test "fills any field the file leaves out with the generic default" do
      goals = Biometric.goals()

      assert goals[:water_oz] == 64
      assert goals[:resting_hr] == 60
    end
  end

  describe "without a goals file" do
    setup do
      tmp = Path.join(System.tmp_dir!(), "biometric_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)
      prev = Application.get_env(:web, :fitness_path)
      Application.put_env(:web, :fitness_path, tmp)

      on_exit(fn ->
        Application.put_env(:web, :fitness_path, prev)
        File.rm_rf!(tmp)
      end)
    end

    test "scores against generic goals and leaves BMI blank" do
      assert Biometric.goals()[:calories_in] == 2000
      assert Biometric.height_inches() == nil
      refute Biometric.bmi(%Biometric{weight_lbs: Decimal.new("150")})
      assert Biometric.compute_score(%Biometric{calories_in: 2000}) == 100
    end
  end

  describe "compute_score/1 with a :target field" do
    test "scores a calorie intake at goal as perfect" do
      assert Biometric.compute_score(%Biometric{calories_in: 2400}) == 100
    end

    # A recomp budget is a number to hit, not a number to beat — which is the
    # whole reason :target exists alongside :higher.
    test "penalises overshooting the calorie goal, not just undershooting" do
      over = Biometric.compute_score(%Biometric{calories_in: 3000})
      under = Biometric.compute_score(%Biometric{calories_in: 1800})

      assert over == 50
      assert under == 50
    end

    test "bottoms out at 50% either side of the goal" do
      assert Biometric.compute_score(%Biometric{calories_in: 3600}) == 0
      assert Biometric.compute_score(%Biometric{calories_in: 1200}) == 0
    end

    test "ignores fields that were not recorded" do
      refute Biometric.compute_score(%Biometric{})
      assert Biometric.compute_score(%Biometric{fiber_grams: 30}) == 100
    end
  end

  test "compute_score/2 scores against the goals it is given" do
    goals = %{Biometric.goals() | calories_in: 1000}
    assert Biometric.compute_score(%Biometric{calories_in: 1000}, goals) == 100
  end
end
