alias Web.Cooking
alias Web.Repo

recipe_data = %{
  title: "The Engineered Protein Mac (The Thomistic Protocol)",
  commentary: """
### Commentary: The Theology of the Hack
We are modifying an "Ultra-Processed Food" (UPF). The original box is designed for shelf stability, not human flourishing. By introducing **Greek Yogurt (fermented life)** and **Collagen (structural integrity)**, we are attempting to "redeem" the industrial substrate.

* **The Chemistry:** Greek Yogurt is acidic (pH ~4). Without the baking soda buffer, it would break the cheese emulsion, resulting in a grainy, sour mess. The neutralization allows the protein to exist in a creamy state, mimicking the "bechamel" of high French cooking.
* **The Feedback:** Just as Aquinas posited that we understand the essence of things through their operations, we understand this dish not by reading the box, but by observing the viscosity change in Step 5.
  """,
  ingredients: [
    %{quantity: "1 Box", item: "Kraft Mac & Cheese (7.25 oz)", metadata: "The Substrate", group: :substrate},
    %{quantity: "1 Scoop (2 tbsp)", item: "Vital Proteins Collagen Peptides", metadata: "The Structural Hydrocolloid", group: :bio_hack},
    %{quantity: "3/8 cup", item: "Plain Greek Yogurt", metadata: "The Protein Mass", group: :bio_hack},
    %{quantity: "2 tbsp", item: "Unsalted Butter", metadata: "The Lipid Buffer", group: :bio_hack},
    %{quantity: "2 tbsp", item: "Whole Milk", metadata: "The Solvent", group: :bio_hack},
    %{quantity: "1/8 tsp", item: "Baking Soda", metadata: "The pH Neutralizer", group: :bio_hack},
    %{quantity: "3 tbsp", item: "Reserved Pasta Water", metadata: "The Starch Stabilizer", group: :bio_hack}
  ],
  steps: [
    %{action: "The Solvent Preparation", duration: "2 min", annotation: "Chemistry: The collagen dissolves effectively in cool liquid, preventing thermal shock later. The soda prepares the alkaline base."},
    %{action: "The Boil", duration: "8 min", annotation: "CRITICAL: Scoop out 3 tbsp cloudy water before draining."},
    %{action: "The Base Paste", duration: "1 min", annotation: "Anti-UPF Note: We are manually emulsifying the industrial salts (phosphates) with real lipids before hydration, preventing the \"plastic\" texture common in boxed foods."},
    %{action: "The Reaction (The Lawrence Moment)", duration: "30s", annotation: "Observation: The sauce will \"fluff\" and lighten as the acid neutralizes. Praxis: Brother Lawrence found the presence of God \"in the noise and clatter of his kitchen.\" In this mundane act of whisking to remove lumps, we practice intentionality."},
    %{action: "The Emulsion (The Aquinas Check)", duration: "1 min", annotation: "Praxis: Thomas Aquinas argued that knowledge comes through the senses. Taste the sauce here. Is it too thick? Add water. Too thin? Simmer. You are engaging in an immediate feedback loop with reality."}
  ]
}

IO.puts "Seeding Recipe..."
# Check for existing
existing = Repo.get_by(Web.Cooking.Recipe, title: recipe_data.title)

if existing do
  IO.puts "Recipe already exists, updating..."
  Web.Cooking.update_recipe(existing, recipe_data)
else
  Web.Cooking.create_recipe(recipe_data)
end
