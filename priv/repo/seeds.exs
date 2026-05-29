alias Web.Repo
alias Web.Fitness.Exercise

# Helper to upsert
upsert = fn attrs ->
  case Web.Fitness.get_exercise_by_slug(attrs.slug) do
    nil -> Web.Fitness.create_exercise(attrs)
    exercise -> Web.Fitness.update_exercise(exercise, attrs)
  end
end

exercises = [
  # --- MONDAY (Legs/Agility) ---
  %{
    name: "Progressive Run",
    slug: "progressive-run",
    description:
      "The progressive run is a foundational warmup designed to gradually elevate the heart rate and core temperature. Start with a brisk walk (RPE 3-4) for the first 2 minutes. Transition into a light jog by minute 5. Over the next 3 minutes, steadily increase your pace until you reach a steady-state running intensity (RPE 6-7). This method lubricates the joints and prepares the cardiovascular system for high-intensity work while minimizing the risk of sudden strain. Common mistakes include starting at top speed, which can lead to early fatigue and potential injury. Citations: NSCA Essentials of Strength Training.",
    muscle_group: "Cardiovascular System",
    video_url: "https://www.youtube.com/embed/v1Bj-0QYnIg",
    resources: "Great for raising core body temp safely.",
    settings: %{"distance" => "2 miles", "time" => "8:26 pace"}
  },
  %{
    name: "Dynamic Mobility",
    slug: "dynamic-mobility",
    description:
      "Dynamic mobility involves active movements where muscles go through a full range of motion. Focus on leg swings, hip circles, arm circles, and the 'World's Greatest Stretch' (a deep lunge with thoracic rotation). Unlike static stretching, dynamic work increases blood flow and improves active flexibility. It is best performed before a workout to prime the nervous system. Avoid rushing through movements; control and intention are key. Holding stretches too long pre-workout can actually decrease power output. Citations: Journal of Strength and Conditioning Research.",
    muscle_group: "Spine & Mobility",
    video_url:
      "https://www.youtube.com/embed/naW8u72lOzI|https://www.youtube.com/embed/Q-oOYQipCg8|https://www.youtube.com/embed/nG38sH8fwSM",
    resources: "Essential pre-workout ritual.",
    settings: %{"time" => "10 min"}
  },
  %{
    name: "Box Jumps",
    slug: "box-jumps",
    description:
      "Box jumps are a premier plyometric exercise for developing explosive power. Stand in front of a sturdy box (20-30 inches). Hinge at the hips, swing your arms back, and explosively jump, landing softly on the box with both feet flat. Ensure your knees do not cave inward on the landing. To protect your joints, always step down rather than jumping down. This exercise improves neuromuscular coordination and vertical power. Common mistakes include landing with locked knees or using a box that is too high, leading to scraped shins. Citations: American Council on Exercise (ACE).",
    muscle_group: "Quadriceps",
    video_url: "https://www.youtube.com/embed/kNIInK_Le8I",
    resources: "Develops fast-twitch fibers.",
    settings: %{"result" => "30 inches"}
  },
  %{
    name: "Walking Weighted Lunges",
    slug: "walking-lunges",
    description:
      "Walking weighted lunges build unilateral strength and stability. Hold dumbbells at your sides or a kettlebell in a goblet position. Take a controlled step forward, lowering your back knee until it nearly brushes the ground. Keep your front knee aligned over your ankle and your torso upright. This movement targets the glutes, quads, and hamstrings while challenging your balance. Avoid overstriding, which can destabilize the knee, or letting the front knee cave inward. Citations: NASM Essentials of Personal Fitness Training.",
    muscle_group: "Quadriceps",
    video_url: "https://www.youtube.com/embed/Pbmj6xPo-Hw",
    resources: "Excellent for functional leg strength.",
    settings: %{"weight" => "30 lbs"}
  },
  %{
    name: "Kettlebell Swings",
    slug: "kettlebell-swings",
    description:
      "The kettlebell swing is a dynamic posterior chain exercise. Stand with feet shoulder-width apart, hinge at the hips, and swing the bell back between your legs. Focus on a powerful hip snap to propel the bell to chest height—the arms should act merely as pendulums. This movement builds explosive power in the glutes and hamstrings while improving grip strength and cardiovascular endurance. Common mistakes include 'squatting' the weight up rather than hinging, or arching the lower back at the top. Citations: StrongFirst Kettlebell Manual.",
    muscle_group: "Hamstrings",
    video_url: "https://www.youtube.com/embed/YSxHifyI6s8",
    resources: "The king of posterior chain movements.",
    settings: %{"weight" => "30 lbs"}
  },
  %{
    name: "Hanging Leg Raises",
    slug: "hanging-leg-raises",
    description:
      "Hanging leg raises target the lower abdominals, crucial for developing the bottom part of the '8-pack'. Hang from a bar with a grip slightly wider than shoulder-width. Keep your legs straight (or bent kneed for a regression) and lift them until they are parallel to the floor, or ideally, touch the bar. Control the descent to avoid swinging. This exercise provides extreme isolation for the rectus abdominis without loading the spine. Citations: Jeff Cavaliere, Athlean-X.",
    muscle_group: "Abdominals",
    video_url: "https://www.youtube.com/embed/RuIdJSVTKO4",
    resources: "Lower ab isolation.",
    settings: %{"result" => "3 x 12", "weight" => "Bodyweight"}
  },
  %{
    name: "Cable Woodchoppers",
    slug: "cable-woodchoppers",
    description:
      "Cable woodchoppers (high-to-low) sculpt the serratus anterior and obliques, creating that tapered 'V-cut' look while reducing bulkiness under the armpits. Set the cable high. Pull the handle diagonally down across your body, ensuring the rotation comes from your torso, not just your arms. Pivot your back foot. This movement slims the waist by tightening the oblique sling. Citations: John Meadows.",
    muscle_group: "Abdominals",
    video_url: "https://www.youtube.com/embed/WKFHw415Vdw",
    resources: "Waist tapering and serratus definition.",
    settings: %{"result" => "3 x 15/side", "weight" => "30 lbs"}
  },
  %{
    name: "Pallof Press",
    slug: "pallof-press",
    description:
      "The Pallof press is the gold standard for anti-rotation core stability. Stand sideways to a cable column or band anchor. Hold the handle with both hands at your chest. Press the handle straight out, resisting the rotational pull of the weight/band that wants to twist your torso toward the anchor. Hold for a moment, then return. This trains the obliques, QL, and deep abdominal wall to stabilize the spine against lateral forces. Citations: Tony Gentilcore.",
    muscle_group: "Abdominals",
    video_url: "https://www.youtube.com/embed/tvzoG7Ua05Y",
    resources: "The ultimate anti-rotation builder.",
    settings: %{"result" => "3 x 12/side", "weight" => "25 lbs"}
  },
  %{
    name: "Goblet Lateral Lunges",
    slug: "goblet-lateral-lunges",
    description:
      "Goblet lateral lunges improve frontal plane mobility and strengthen the inner thighs. Hold a kettlebell or dumbbell at chest level. Take a large step to one side, sinking your hips back and down while keeping the opposite leg perfectly straight. Keep your chest upright and your feet flat on the floor. This exercise targets the gluteus medius and adductors, which are often neglected in traditional forward-back movements. Avoid letting the lunging knee collapse inward. Citations: Journal of Sports Science & Medicine.",
    muscle_group: "Gluteal Complex",
    video_url: "https://www.youtube.com/embed/w7Nx21o744A",
    resources: "Crucial for hip health and lateral stability.",
    settings: %{"result" => "3 x 12"}
  },
  %{
    name: "Single-Leg Calf Raises",
    slug: "calf-raises",
    description:
      "Single-leg calf raises isolate the gastrocnemius and soleus muscles while improving ankle stability. Stand on one leg on the edge of a step. Lower your heel as far as possible to feel a deep stretch, then drive upward onto the ball of your foot. Pause and squeeze at the top. This unilateral approach corrects muscle imbalances and enhances balance. Avoid 'bouncing' at the bottom; use a slow and controlled tempo to maximize muscle fiber recruitment. Citations: ExRx.net Exercise Directory.",
    muscle_group: "Triceps Surae",
    video_url: "https://www.youtube.com/embed/ElcvJ0kjt6c",
    resources: "Fixes calf imbalances.",
    settings: %{"result" => "3 x 15"}
  },
  %{
    name: "Plank",
    slug: "plank",
    description:
      "The plank is a premier isometric core exercise for spinal stability. Place your forearms on the ground with elbows directly under your shoulders. Maintain a perfectly straight line from your head to your heels by squeezing your glutes and bracing your abdominals as if preparing for a punch. This exercise builds endurance in the deep core stabilizers. Common mistakes include sagging the hips, which strains the lower back, or piking the hips too high, which reduces core engagement. Citations: Stuart McGill, 'Ultimate Back Fitness and Performance'.",
    muscle_group: "Abdominals",
    video_url: "https://www.youtube.com/embed/7iNKMEBOL1U",
    resources: "Foundational for core stability.",
    settings: %{"time" => "3 x 60s"}
  },
  %{
    name: "Dead Bug",
    slug: "dead-bug",
    description:
      "The dead bug is an essential exercise for learning core stability while moving limbs. Lie on your back with arms extended toward the ceiling and knees bent at 90 degrees (tabletop). Slowly lower the opposite arm and leg toward the floor while keeping your lower back pressed firmly into the mat. This 'anti-extension' movement protects the spine and improves motor control. The most common mistake is allowing the lower back to arch off the floor, which shifts the work away from the deep abdominals. Citations: American Physical Therapy Association (APTA).",
    muscle_group: "Abdominals",
    video_url: "https://www.youtube.com/embed/0XVbn86Btj0",
    resources: "Teaches limb coordination and spinal protection.",
    settings: %{"result" => "3 x 12/side"}
  },
  %{
    name: "Leg Press",
    slug: "leg-press",
    description:
      "The leg press allows for heavy loading of the quadriceps and glutes with spinal support. Place feet shoulder-width apart on the platform. Lower the weight until your knees are bent at 90 degrees, keeping your lower back pressed firmly against the pad (do not let your hips curl up!). Drive the weight back up through your mid-foot. This effectively builds raw leg strength without the balance demands of a squat. Citations: NSCA.",
    muscle_group: "Quadriceps",
    video_url: "https://www.youtube.com/embed/nDh_BlnLCGc",
    resources: "Heavy loading with back safety.",
    settings: %{"weight" => "160 lbs"}
  },
  %{
    name: "Leg Extensions",
    slug: "leg-extensions",
    description:
      "Leg extensions isolate the quadriceps, specifically the rectus femoris. Sit with your back against the pad and knees aligned with the machine's pivot point. Extend your legs until straight, squeezing the quads hard at the top. Lower slowly. This is excellent for defining the front of the thigh and strengthening the VMO (teardrop muscle) for knee tracking. Avoid 'kicking' the weight up with momentum. Citations: Journal of Physical Therapy Science.",
    muscle_group: "Quadriceps",
    video_url: "https://www.youtube.com/embed/swZQC689o9U",
    resources: "Isolation for quad definition.",
    settings: %{"weight" => "70 lbs"}
  },
  %{
    name: "Seated Leg Curls",
    slug: "leg-curls",
    description:
      "Seated leg curls target the hamstrings in a lengthened position. Sit with the lap pad secured tightly against your thighs to prevent lifting. Curl the weight down as far as possible, then control the return. This exercise balances quad dominance and protects the knee joint by strengthening the posterior chain. Avoid rushing the eccentric (lowering) phase. Citations: Hypertrophy Guidelines.",
    muscle_group: "Hamstrings",
    video_url: "https://www.youtube.com/embed/3tcjzbziRk0",
    resources: "Knee flexion strength.",
    settings: %{"weight" => "70 lbs"}
  },
  %{
    name: "Hip Abduction Machine",
    slug: "hip-abduction",
    description:
      "The hip abduction machine targets the gluteus medius and minimus (outer hip). Sit with pads on the outside of your knees and push your legs outward against resistance. This exercise is critical for pelvic stability and preventing 'knee valgus' (knees caving in). Control the return phase; don't let the weight stack slam. Citations: Journal of Physical Therapy.",
    muscle_group: "Gluteal Complex",
    video_url: "https://www.youtube.com/embed/OjI5OpV6IWA",
    resources: "Stability for the outer hip.",
    settings: %{"weight" => "80 lbs"}
  },
  %{
    name: "Hip Adduction Machine",
    slug: "hip-adduction",
    description:
      "The hip adduction machine targets the adductor group (inner thigh). Sit with pads on the inside of your knees and squeeze your legs together. These muscles are key stabilizers during squatting and running. Strengthening them balances the hip complex. Avoid jerking the weight; focus on a smooth squeeze. Citations: Sports Medicine.",
    muscle_group: "Gluteal Complex",
    video_url: "https://www.youtube.com/embed/CjAVezAggkI",
    resources: "Inner thigh strength and balance.",
    settings: %{"weight" => "80 lbs"}
  },

  # --- TUESDAY (Push) ---
  %{
    name: "Shoulder Activation",
    slug: "shoulder-activation",
    description:
      "Shoulder activation prep involves small, controlled movements to prime the rotator cuff and upper back. Focus on banded face pulls, pull-aparts, and 'Ys' and 'Ts'. The goal is to wake up the stabilizing muscles of the scapula before heavy pressing. Use light resistance; this is not a strength movement but a preparation step. Common mistakes include using too much resistance, causing the larger upper traps to take over and negating the focus on the smaller stabilizers. Citations: Eric Cressey, Shoulder Health Specialist.",
    muscle_group: "Deltoids",
    video_url: "https://www.youtube.com/embed/CU4Xc2qlLC0",
    resources: "Crucial for longevity in pressing movements.",
    settings: %{"time" => "10 min"}
  },
  %{
    name: "Plyometric Push-Ups",
    slug: "clap-pushups",
    description:
      "Plyometric push-ups are an advanced power movement for the chest and triceps. Perform a standard push-up but drive upward with enough force to launch your hands off the floor. Land softly with slightly bent elbows to absorb the impact. This exercise targets fast-twitch muscle fibers and improves upper-body 'snap'. It is highly effective for athletes needing explosive power. Avoid landing with locked elbows or losing core tension during the explosive phase. Citations: Journal of Applied Biomechanics.",
    muscle_group: "Pectoralis Major",
    video_url: "https://www.youtube.com/embed/Y-uF4F3mQIs",
    resources: "Increases upper body explosive power.",
    settings: %{"result" => "3x8 reps"}
  },
  %{
    name: "Incline Dumbbell Press",
    slug: "incline-db-press",
    description:
      "The incline dumbbell press targets the clavicular head of the pectoralis major (upper chest). Set the bench to a 30-45 degree angle. Press the dumbbells up, focusing on bringing the inner parts of the weights together at the top. Lower the weights until your elbows are just below your chest level to get a deep stretch. This angle builds a well-rounded chest and improves shoulder stability. Avoid setting the bench too steep, as it shifts the focus to the anterior deltoids. Citations: ACE Fitness Exercise Library.",
    muscle_group: "Pectoralis Major",
    video_url: "https://www.youtube.com/embed/gl8H4QLXKTo",
    resources: "Builds the upper chest shelf.",
    settings: %{"weight" => "35 lbs"}
  },
  %{
    name: "Single-Arm Landmine Press",
    slug: "landmine-press",
    description:
      "The single-arm landmine press is a versatile overhead pressing alternative. With one end of the barbell anchored, stand and press the other end up and slightly forward. This 'angled' press is often more joint-friendly than traditional overhead presses. It also builds core anti-rotation strength as you resist leaning to one side. Keep your core braced and lean slightly into the movement. Common mistakes include rotating the torso excessively or locking the knees. Citations: T-Nation 'The Landmine Press'.",
    muscle_group: "Deltoids",
    video_url: "https://www.youtube.com/embed/Sjb5meztfSE",
    resources: "Excellent for shoulder health and core stability.",
    settings: %{"weight" => "30 lbs"}
  },
  %{
    name: "Cable Lateral Raises",
    slug: "cable-lateral-raises",
    description:
      "Cable lateral raises provide constant tension on the medial deltoids throughout the entire range of motion. Set the cable to a low position. Raise the handle out to your side until your arm is parallel to the floor, focusing on leading with the elbow. Unlike dumbbells, cables do not lose tension at the bottom of the movement, leading to superior muscle activation. Avoid shrugging your shoulders (using your traps) or using momentum to jerk the weight up. Citations: Brad Schoenfeld, 'Science and Development of Muscle Hypertrophy'.",
    muscle_group: "Deltoids",
    video_url: "https://www.youtube.com/embed/Z5FA9aq3L6A",
    resources: "Provides constant tension for shoulder growth.",
    settings: %{"weight" => "10 lbs"}
  },
  %{
    name: "Tricep Dips",
    slug: "tricep-dips",
    description:
      "Tricep dips are a potent compound movement for the upper body. Using parallel bars, lower your body until your shoulders are slightly below your elbows, then drive back up to full extension. Keep your torso relatively upright to maintain the focus on the triceps. This exercise builds massive pressing power and arm thickness. Avoid flaring your elbows excessively or dropping too deep, which can cause shoulder impingement. Citations: Arnold Schwarzenegger, 'Encyclopedia of Modern Bodybuilding'.",
    muscle_group: "Triceps Brachii",
    video_url: "https://www.youtube.com/embed/5XkOdAtPn2Y",
    resources: "One of the best tricep mass builders.",
    settings: %{"result" => "Failure"}
  },
  %{
    name: "Pec Deck Fly",
    slug: "pec-deck-fly",
    description:
      "The pec deck fly isolates the chest muscles without tricep involvement. Sit with your back flat against the pad and elbows slightly bent. Bring the handles/pads together in front of your chest, squeezing the pecs hard at the peak. Slowly return to the starting position until you feel a deep stretch in the chest. This provides consistent tension throughout the movement, unlike dumbbells. Citations: ACE.",
    muscle_group: "Pectoralis Major",
    video_url: "https://www.youtube.com/embed/H4mVGHaK2f4",
    resources: "Isolation for inner chest development.",
    settings: %{"weight" => "70 lbs"}
  },
  %{
    name: "Russian Twists",
    slug: "russian-twists",
    description:
      "Russian twists target the internal and external obliques through rotational torque. Sit on the floor with knees bent and feet slightly elevated. Rotate your torso from side to side, touching the floor or a weight on each side. This exercise improves core stability and sport-specific rotational power. Ensure you are rotating your actual torso, not just moving your arms. Avoid rounding the lower back, which can lead to spinal strain. Citations: Mayo Clinic Health System.",
    muscle_group: "Abdominals",
    video_url: "https://www.youtube.com/embed/PkGPokybYaU",
    resources: "Enhances rotational power.",
    settings: %{"result" => "20 reps"}
  },
  %{
    name: "Hollow Body Hold",
    slug: "hollow-body-hold",
    description:
      "The hollow body hold is the fundamental core exercise of gymnastics. Lie on your back and lift your head, shoulders, and legs just off the floor. The most critical part is pressing your lower back firmly into the ground so there is no space between your back and the mat. This creates a 'bow' shape and generates immense full-body tension. It is the gold standard for core strength. If your back arches, the exercise is too difficult; modify by bending one or both knees. Citations: Gymnastics Bodies Foundation.",
    muscle_group: "Abdominals",
    video_url: "https://www.youtube.com/embed/BQCdzRPE9Ao",
    resources: "The gold standard for core tension.",
    settings: %{"time" => "45s"}
  },
  %{
    name: "Sledgehammer Baseball Swings",
    slug: "sledgehammer-baseball-swings",
    description:
      "Sledgehammer baseball swings mimic the rotational mechanics of a powerful batting stroke against a heavy tire. Stand sideways to the tire, mimicking your batting stance. Hold the sledgehammer like a bat. initiate the swing from the hips, rotating explosively and striking the side of the tire (or top, depending on tire setup) with a horizontal or slightly downward path. This builds immense rotational power, core stability, and forearm strength specific to swinging sports. Switch sides to balance muscular development. Citations: Rotational Power for Baseball.",
    muscle_group: "Abdominals",
    video_url: "https://www.youtube.com/embed/eR6-RiVusYk",
    resources: "Explosive sport-specific rotational power.",
    settings: %{"result" => "10/side"}
  },
  %{
    name: "Battle Ropes",
    slug: "battle-ropes",
    description:
      "Battle ropes (Long Rope Work) are a metabolic conditioning tool that heavily recruits the shoulders, triceps, and core. Perform alternating waves, double slams, or spirals to maintain high intensity. This exercise creates massive time-under-tension for the upper body 'pushing' muscles (anterior delts) while forcing the core to stabilize against the chaotic movement of the ropes. It is a perfect burnout for a push session. Avoid tense neck muscles; keep the movement in the arms and shoulders. Citations: Journal of Strength and Conditioning.",
    muscle_group: "Cardiovascular System",
    video_url: "https://www.youtube.com/embed/zw0OMi00X5g",
    resources: "Shoulder and lung capacity burnout.",
    settings: %{"time" => "30s"}
  },
  %{
    name: "Pool Medley & Tread",
    slug: "pool-medley",
    description:
      "A hybrid conditioning protocol combining medley swimming with vertical water treading to build full-body endurance, hip mobility, and lactic threshold.
\n### The Protocol
\n#### 1. Medley (4 Laps)
Complete 1 lap each of Backstroke, Butterfly, Breaststroke, and Freestyle.
*   *Technique:* Incorporate **hypoxic breathing** (every 3, 5, or 7 strokes) during freestyle to mimic 'air hunger' and build capacity.
\n#### 2. The Tread Sandwich
*   **1. Start:** Hold wall for 1 minute (static decompression or flutter kick).
*   **2. Middle:** Swim to middle → Tread water for 2 minutes.
*   **3. Far End:** Swim to end → Hold wall for 1 minute.
*   **4. Middle:** Swim back to middle → Tread water for 2 minutes.
*   **5. Return:** Swim to start → Hold wall for 1 minute.
\n*   *Travel Stroke:* Use **Backstroke** (Tue) or **Long-gliding Freestyle** (Thu) to travel between stations.
*   Focus on tight **streamlines** off every wall push—it's 'free speed' and resets your posture.
\n#### 3. Repeat
Cycle through the Medley and Tread phases 2-3 times.
\n#### 4. Cool Down
Finish with 2 laps of very easy Elementary Backstroke or Water Walking to flush lactate and recover for tomorrow.",
    muscle_group: "Cardiovascular System",
    video_url:
      "https://www.youtube.com/embed/XL4hKxarNGU|https://www.youtube.com/embed/S8oUnw_T7a4|https://www.youtube.com/embed/NKZEXHBz4-4|https://www.youtube.com/embed/Ij0QS8R-F8s|https://www.youtube.com/embed/l3TUZRQ2WEk",
    resources: "Hypoxic breathing (3-5-7 pattern) recommended during freestyle.",
    settings: %{"time" => "30 min"}
  },

  # --- WEDNESDAY (Posture/Boxing) ---
  %{
    name: "Shadowboxing",
    slug: "shadowboxing",
    description:
      "Shadowboxing is a versatile tool for cardiovascular conditioning and technical refinement. Maintain a balanced boxing stance, staying light on the balls of your feet. Throw punches (jabs, crosses, hooks, and uppercuts) while visualizing an opponent and moving your head to simulate defense. This exercise improves hand-eye coordination, balance, and rhythm. Ensure you rotate your hips and core into setiap punch rather than just using your arms. Common mistakes include overextending punches or dropping the hands when fatigued. Citations: 'Championship Fighting' by Jack Dempsey.",
    muscle_group: "Cardiovascular System",
    video_url: "https://www.youtube.com/embed/yrJE2unJ_m0",
    resources: "Perfect for warming up or end-of-session conditioning.",
    settings: %{"time" => "15 min"}
  },
  %{
    name: "Prone Y-T-W",
    slug: "ywt-raises",
    description:
      "Prone Y-T-W raises are essential for strengthening the postural muscles of the upper back. Lie face down with your forehead on the floor. Raise your arms into a 'Y' shape (thumbs up), then a 'T' shape (arms out to the side), and finally a 'W' shape (elbows pulled back). These positions target the lower and middle traps, which are often weak from prolonged sitting. Focus on squeezing your shoulder blades together and avoid lifting your neck off the floor. Citations: NASM Corrective Exercise Specialization.",
    muscle_group: "Trapezius",
    video_url: "https://www.youtube.com/embed/QdGTI4Lshg4",
    resources: "The gold standard for postural correction.",
    settings: %{"result" => "12 reps each"}
  },
  %{
    name: "Scapular Push-Ups",
    slug: "scap-pushups",
    description:
      "Scapular push-ups isolate the serratus anterior, a muscle crucial for shoulder stability. Start in a high plank position with arms perfectly straight. Allow your chest to sink toward the floor by pinching your shoulder blades together, then push through your palms to spread the blades as far apart as possible. Your elbows should never bend. This 'protrusion and retraction' movement improves scapular health and prevents shoulder impingement. Avoid sagging the lower back during the movement. Citations: Mike Reinold, Shoulder Rehabilitation Expert.",
    muscle_group: "Pectoralis Major",
    video_url: "https://www.youtube.com/embed/NKekqeudgWs",
    resources: "Builds a bulletproof shoulder foundation.",
    settings: %{"result" => "15 reps"}
  },
  %{
    name: "Reverse Snow Angels",
    slug: "reverse-snow-angels",
    description:
      "Reverse snow angels are a high-repetition endurance exercise for the upper back. Lie face down and lift your chest and arms slightly off the ground. Move your arms in a wide, controlled arc from your hips to over your head, mirroring the motion of a snow angel. This exercise targets the rhomboids, traps, and rear deltoids. Maintain constant tension and avoid touching the floor until the set is finished. Common mistakes include moving too fast or losing the contraction in the upper back. Citations: Kelly Starrett, 'Becoming a Supple Leopard'.",
    muscle_group: "Trapezius",
    video_url: "https://www.youtube.com/embed/FWaLM-RDvVs",
    resources: "Excellent for endurance in the postural muscles.",
    settings: %{"result" => "12 reps"}
  },
  %{
    name: "Push-Ups",
    slug: "pushups",
    description:
      "The standard push-up is the definitive upper-body bodyweight exercise. Place your hands slightly wider than shoulder-width and lower your body until your chest is an inch from the floor. Keep your elbows tucked at a 45-degree angle to protect your shoulders. Brace your core and glutes to maintain a straight line from head to toe. This movement builds strength in the chest, shoulders, and triceps. Avoid flaring your elbows out to 90 degrees or letting your hips sag. Citations: ACE Fitness Manual.",
    muscle_group: "Pectoralis Major",
    video_url: "https://www.youtube.com/embed/WDIpL0pjun0",
    resources: "The foundational pressing movement.",
    settings: %{"result" => "Failure"}
  },
  %{
    name: "Superman Lat Pulls",
    slug: "superman-lat-pulls",
    description:
      "Superman lat pulls combine lower back stabilization with lat activation. Lie face down with arms overhead. Lift your chest and legs off the ground into the 'Superman' position. From this isometric hold, pull your elbows down toward your ribs while squeezing your shoulder blades. This mimics a lat pulldown without the need for equipment. It is highly effective for building the 'V' taper and strengthening the erector spinae. Avoid craneing your neck upward; keep your gaze toward the floor. Citations: Men's Health Exercise Database.",
    muscle_group: "Latissimus Dorsi",
    video_url: "https://www.youtube.com/embed/v0g5fw3IJRQ",
    resources: "Back strength without equipment.",
    settings: %{"result" => "20 reps"}
  },
  %{
    name: "Prisoner Squats",
    slug: "prisoner-squats",
    description:
      "Prisoner squats add a postural challenge to the traditional air squat. Stand with feet shoulder-width apart and hands interlaced behind your head. Pull your elbows back to open the chest and engage the upper back. Squat down until your thighs are at least parallel to the floor, keeping your weight in your heels. This variation prevents 'chest collapse' during the squat and improves thoracic mobility. Common mistakes include letting the elbows drift forward or rounding the upper back. Citations: NASM Personal Training Guidelines.",
    muscle_group: "Quadriceps",
    video_url: "https://www.youtube.com/embed/bAhzgJ5Ayu0",
    resources: "Corrects squatting posture.",
    settings: %{"result" => "30 reps"}
  },
  %{
    name: "Reverse Lunges",
    slug: "reverse-lunges",
    description:
      "Reverse lunges are a knee-friendly unilateral leg exercise. Take a large step backward and lower your back knee until it nearly touches the ground. Your front shin should remain vertical to minimize stress on the knee joint. Drive through your front heel to return to the starting position. This exercise heavily targets the glutes and hamstrings while improving balance. Avoid 'crashing' the back knee into the floor or leaning excessively forward. Citations: Journal of Strength and Conditioning Research.",
    muscle_group: "Gluteal Complex",
    video_url: "https://www.youtube.com/embed/5frs7_F2SrU",
    resources: "A staple for functional leg development.",
    settings: %{"result" => "20 reps"}
  },
  %{
    name: "Side Plank Leg Lifts",
    slug: "side-plank-leg-lifts",
    description:
      "Side plank leg lifts target the lateral core and the hip abductors (gluteus medius). Hold a side plank on your forearm, maintaining a straight line from head to feet. While holding this position, lift your top leg toward the ceiling without rotating your hips. This exercise is critical for pelvic stability and preventing knee pain in runners. Ensure your bottom hip does not sag toward the floor. Avoid rushing the lift; control the eccentric phase carefully. Citations: McGill Core Stability Studies.",
    muscle_group: "Gluteal Complex",
    video_url: "https://www.youtube.com/embed/UltCxDaUBBI",
    resources: "Vital for hip and pelvic stability.",
    settings: %{"result" => "12/side"}
  },
  %{
    name: "Isometric Neck Holds",
    slug: "isometric-neck-holds",
    description:
      "Isometric neck holds build necessary strength and stability for the cervical spine, crucial for absorbing impact in boxing. Place your hand against your forehead, back of head, or side of head. Push your head into your hand while resisting the movement, keeping your neck perfectly neutral. Hold for time. This strengthens the neck flexors, extensors, and lateral stabilizers. Avoid holding your breath or straining the jaw. Citations: Boxing Science.",
    muscle_group: "Spine & Mobility",
    video_url: "https://www.youtube.com/embed/kwKq9n8ima4",
    resources: "Crucial for shock absorption.",
    settings: %{"time" => "10s/side"}
  },
  %{
    name: "Bicycle Crunches",
    slug: "bicycle-crunches",
    description:
      "Bicycle crunches are one of the most effective exercises for the rectus abdominis and obliques. Lie on your back and bring one knee toward your chest while rotating the opposite elbow to meet it. Extend the other leg straight out at a 45-degree angle. Alternate sides in a smooth, pedaling motion. Focus on the rotation of the ribcage rather than just moving your elbows. Avoid pulling on your neck, which can lead to strain. Citations: San Diego State University Core Study.",
    muscle_group: "Abdominals",
    video_url: "https://www.youtube.com/embed/wnuLak2onoA",
    resources: "The gold standard for ab activation.",
    settings: %{"result" => "100 reps"}
  },

  # --- THURSDAY (Pull) ---
  %{
    name: "Rowing Machine",
    slug: "rowing-machine",
    description:
      "Rowing provides a total-body cardiovascular workout that engages 86% of the body's muscles. Proper form follows a 'Legs-Core-Arms' sequence on the drive and 'Arms-Core-Legs' on the recovery. Push explosively with the legs, lean back slightly, and then pull the handle to your lower ribs. This exercise builds incredible aerobic capacity and muscular endurance. Avoid 'hunching' over at the catch or pulling solely with your arms. Citations: Concept2 Rowing Technique Guide.",
    muscle_group: "Cardiovascular System",
    video_url: "https://www.youtube.com/embed/ZN0J6qKCIrI",
    resources: "Unmatched full-body conditioning.",
    settings: %{"time" => "10-15 min"}
  },
  %{
    name: "Banded Pull-Aparts",
    slug: "banded-pull-aparts",
    description:
      "Banded pull-aparts are a simple but effective tool for improving posture and shoulder health. Hold a resistance band with arms straight in front of you. Pull the band apart until it touches your mid-chest, focusing on squeezing your shoulder blades together. This targets the rear deltoids and rhomboids, reversing the 'rounded shoulders' common in desk-bound individuals. Use a light band and high repetitions for best results. Avoid arching your lower back to complete the movement. Citations: Eric Cressey, 'The High Performance Back'.",
    muscle_group: "Trapezius",
    video_url: "https://www.youtube.com/embed/MnDpmNYUjbc",
    resources: "Excellent postural 'reset' tool.",
    settings: %{"time" => "10 min"}
  },
  %{
    name: "Lat Pulldowns",
    slug: "lat-pulldowns",
    description:
      "The lat pulldown is a staple vertical pulling movement. Sit at the machine and grasp the bar with a wide grip. Pull the bar down to your upper chest, focusing on pulling with your elbows and driving them toward your hips. This exercise builds lat width and back thickness. Maintain a slight lean back but avoid using momentum to swing the weight. Common mistakes include pulling the bar behind your neck or failing to reach a full stretch at the top. Citations: bodybuilding.com Exercise Library.",
    muscle_group: "Latissimus Dorsi",
    video_url: "https://www.youtube.com/embed/7JnP8dFbS14",
    resources: "Primary movement for back width.",
    settings: %{"weight" => "90 lbs"}
  },
  %{
    name: "Kelso Shrugs",
    slug: "kelso-shrugs",
    description:
      "Kelso shrugs are a unique horizontal shrugging movement that targets the mid and lower traps. Lie face down on an incline bench holding dumbbells. Shrug your shoulder blades back and together as if trying to pinch them. Unlike standard shrugs which move the weight 'up', Kelso shrugs move the weight 'back'. This improves scapular retraction and posture. Use a controlled tempo and a full squeeze at the top. Common mistakes include using excessive weight and shrugging toward the ears. Citations: Paul Kelso, 'The Kelso Shrug'.",
    muscle_group: "Trapezius",
    video_url: "https://www.youtube.com/embed/qKCuWRx-hKk",
    resources: "Advanced isolation for the mid-back.",
    settings: %{"weight" => "30 lbs"}
  },
  %{
    name: "Farmer's Carries",
    slug: "farmers-carries",
    description:
      "Farmer's carries are the ultimate functional strength movement. Hold a heavy dumbbell or kettlebell in each hand and walk for a set distance or time. Stand tall with your shoulders back and your core tightly braced. This exercise builds legendary grip strength, forearm size, and cardiovascular endurance. It is one of the most effective ways to translate gym strength into real-world utility. Avoid letting the weights swing or shrugging your shoulders during the walk. Citations: Dan John, Strength Coach.",
    muscle_group: "Abdominals",
    video_url: "https://www.youtube.com/embed/8OtwXwrJizk",
    resources: "The gold standard for work capacity.",
    settings: %{"distance" => "40-50 yds", "weight" => "40 lbs"}
  },
  %{
    name: "Single-Arm Cable Rows",
    slug: "single-arm-cable-rows",
    description:
      "Single-arm cable rows combine horizontal pulling with core stabilization. Pull the cable handle toward your hip while preventing your torso from rotating. This unilateral approach corrects back imbalances and engages the obliques as 'anti-rotators'. Focus on a full stretch at the start of the movement and a deep squeeze at the end. Use a staggered stance or squared stance depending on your stability needs. Avoid using your torso to 'jerk' the weight back. Citations: Charles Poliquin Training Principles.",
    muscle_group: "Latissimus Dorsi",
    video_url: "https://www.youtube.com/embed/1jN6qeXdvWA",
    resources: "Excellent for back symmetry and core stability.",
    settings: %{"weight" => "35 lbs"}
  },
  %{
    name: "Dead Hangs",
    slug: "dead-hangs",
    description:
      "Dead hangs are a simple but powerful exercise for grip strength and spinal health. Hang from a pull-up bar with a comfortable grip and let gravity decompress your spine. You can perform 'active' hangs by pulling your shoulders away from your ears, or 'passive' hangs for a deeper stretch. This exercise is also a pre-requisite for improving pull-up performance. It helps in stretching the lats and improving overall shoulder mobility. Avoid holding your breath during the hang. Citations: Ido Portal, 'The Hanging Challenge'.",
    muscle_group: "Spine & Mobility",
    video_url: "https://www.youtube.com/embed/0Bx_Ap7-EwU",
    resources: "Crucial for grip and spinal decompression.",
    settings: %{"time" => "Max Hold"}
  },
  %{
    name: "Incline Curls",
    slug: "incline-curls",
    description:
      "Incline curls put the biceps in a unique stretched position by keeping the arms behind the torso. Sit on an incline bench (45-60 degrees) and curl the dumbbells without moving your elbows forward. This stretch targets the long head of the biceps, which is responsible for the 'peak'. Maintain a controlled tempo, especially on the lowering phase, to maximize muscle fiber recruitment. Avoid using momentum or letting the elbows drift. Citations: Steve Reeves, 'Building the Classic Physique'.",
    muscle_group: "Biceps Brachii",
    video_url: "https://www.youtube.com/embed/DCe8f6vMe9A",
    resources: "The best exercise for bicep peaks.",
    settings: %{"weight" => "15 lbs"}
  },
  %{
    name: "Zottman Curls",
    slug: "zottman-curls",
    description:
      "Zottman curls are a hybrid movement that builds both the biceps and the forearms. Curl the weights up with palms facing toward you (supinated), then rotate your palms downward (pronated) at the top of the movement. Lower the weights slowly in this palms-down position to target the brachialis and brachioradialis. This exercise is highly efficient for total arm development. Ensure you rotate your wrists fully at the peak contraction for maximum benefit. Citations: George Zottman, 19th-century strongman.",
    muscle_group: "Biceps Brachii",
    video_url: "https://www.youtube.com/embed/D7bMA4WEKMI",
    resources: "Total arm and forearm development.",
    settings: %{"weight" => "15 lbs"}
  },
  %{
    name: "Dragon Flag",
    slug: "dragon-flag",
    description:
      "The dragon flag is an elite core exercise popularized by Bruce Lee. Lie on a bench and grip the edge behind your head. Lift your entire body as a single unit until you are resting on your upper back, then lower your body slowly until it is just above the bench. The body must remain perfectly straight throughout the movement. This builds extreme core stability and eccentric strength. Use a shorter range of motion or bend your knees as a modification if the full version is too difficult. Citations: Bruce Lee, 'The Art of Expressing the Human Body'.",
    muscle_group: "Abdominals",
    video_url: "https://www.youtube.com/embed/pvz7k5gO-DE",
    resources: "The ultimate test of core strength.",
    settings: %{"result" => "Failure"}
  },

  # --- FRIDAY (Sprint/Iso) ---
  %{
    name: "Shuttle Runs",
    slug: "shuttle-runs",
    description:
      "Shuttle runs (specifically the 5-10-5 yard drill) are a benchmark for agility and lateral quickness. Sprint 5 yards to your right, touch the line with your hand, sprint 10 yards to your left, touch that line, and sprint back to the center. The key is to drop your center of mass before the turn and drive explosively off your outside leg. This drill improves deceleration control and anaerobic power. Avoid rounding your turns; sharp, crisp plants are more efficient. Citations: NFL Combine Testing Protocol.",
    muscle_group: "Cardiovascular System",
    resources: "Develops elite agility and change-of-direction.",
    settings: %{"result" => "6 sets"}
  },
  %{
    name: "100m Dashes",
    slug: "100m-dash",
    description:
      "The 100-meter dash is the ultimate expression of human speed. Focus on the 'drive phase' for the first 20 meters, keeping your head down and body angled forward as you push off the ground. Transition into 'top-end speed' by maintaining an upright posture with high knee lift and powerful, rhythmic arm swings. Sprints are high-intensity intervals that boost metabolic rate and build explosive lower-body power. Avoid overstriding, which acts as a brake on your momentum. Citations: USA Track & Field (USATF) Sprint Mechanics.",
    muscle_group: "Cardiovascular System",
    resources: "The gold standard for pure speed.",
    settings: %{"result" => "5 sets"}
  },
  %{
    name: "Wall Sit",
    slug: "wall-sit",
    description:
      "The wall sit is a brutal isometric exercise for quad endurance. Lean against a wall and slide down until your thighs are parallel to the floor, forming a 90-degree angle at the knees and hips. Keep your back flat against the wall and your weight distributed through your heels. This builds mental toughness and creates significant time-under-tension for the quads. Avoid resting your hands on your knees or letting your knees cave inward. Citations: National Strength and Conditioning Association (NSCA).",
    muscle_group: "Quadriceps",
    resources: "Builds bulletproof quad endurance.",
    settings: %{"time" => "60s"}
  },
  %{
    name: "Low Push-up Hold",
    slug: "low-pushup-hold",
    description:
      "The low push-up hold is an isometric power-builder for the chest, shoulders, and triceps. Lower yourself to the midpoint of a push-up—where your chest is just an inch or two above the ground—and hold. This targets the 'sticking point' of the movement and builds immense stability in the shoulder girdle. Keep your core tight and elbows tucked. Avoid letting your hips sag or your head droop toward the floor. Citations: Pavel Tsatsouline, 'The Naked Warrior'.",
    muscle_group: "Pectoralis Major",
    resources: "Eliminates push-up sticking points.",
    settings: %{"time" => "45s"}
  },
  %{
    name: "Glute Bridge",
    slug: "glute-bridge",
    description:
      "Glute bridges are the foundation of posterior chain health. Lie on your back with knees bent and feet flat on the floor. Driving through your heels to lift your hips toward the ceiling, creating a straight line from knees to shoulders. Squeeze your glutes hard at the top of the movement. This exercise is essential for hip extension power and reversing the tightening effects of sitting. Avoid arching your lower back to reach higher; the movement should come from the hips. Citations: Bret Contreras, 'The Glute Lab'.",
    muscle_group: "Gluteal Complex",
    resources: "Foundational for glute activation.",
    settings: %{"time" => "45s"}
  },
  %{
    name: "L-Sit",
    slug: "l-sit",
    description:
      "The L-sit is a high-level gymnastics skill that builds incredible core and hip flexor strength. Supporting your weight with your hands (on the floor or bars), lift your legs until they are parallel to the floor, forming an 'L' shape. This requires immense shoulder depression and trunk tension. It is one of the most effective ways to build 'functional' core strength that translates to other lifts. Avoid shrugging your shoulders near your ears. Citations: Overcoming Gravity by Steven Low.",
    muscle_group: "Quadriceps",
    video_url: "https://www.youtube.com/embed/eywCpp0p7lg",
    resources: "An elite measure of core strength.",
    settings: %{"time" => "Max Hold"}
  },
  %{
    name: "Pigeon Stretch",
    slug: "pigeon-stretch",
    description:
      "The pigeon stretch is a premier yoga pose for opening the hips and stretching the glutes and piriformis. From a plank, bring one knee forward toward the opposite wrist and lower your hips to the mat. Keep your hips square and breathe into the tension. This stretch is vital for anyone with tight hips or lower back discomfort. Avoid forcing the front knee into position if it causes pain; modify by bringing the foot closer to the hip. Citations: Yoga Journal Anatomy Guide.",
    muscle_group: "Gluteal Complex",
    video_url: "https://www.youtube.com/embed/IsuBIWXEKpg",
    resources: "Superior hip opener for athletes.",
    settings: %{"time" => "3 min/side"}
  },
  %{
    name: "Couch Stretch",
    slug: "couch-stretch",
    description:
      "The couch stretch is widely considered the most effective way to open tight hip flexors and quads. Place one knee against a wall or the back of a couch, with your foot pointing upward. Step the opposite leg forward into a lunge and sit tall, squeezing your glute on the back leg. This stretch specifically targets the rectus femoris, which crosses both the hip and knee. Maintain an upright posture and avoid arching your lower back. Citations: Kelly Starrett, The Ready State.",
    muscle_group: "Quadriceps",
    resources: "The antidote to a desk-bound lifestyle.",
    settings: %{"time" => "2 min/side"}
  },

  # --- SATURDAY (Active Recovery) ---
  %{
    name: "Thoracic Extension",
    slug: "thoracic-extension",
    description:
      "Thoracic extension using a peanut or foam roller tackles the 'desk posture' hunch (kyphosis). Place the roller at the mid-back (not low back). Support your head with your hands, keep your hips on the ground, and gently extend your spine over the roller. This mobilizes the stiff T-spine vertebrae, allowing the scapula to move freely and reducing neck strain. Breath is key: exhale as you extend. Citations: Squat University.",
    muscle_group: "Spine & Mobility",
    video_url: "https://www.youtube.com/embed/sWawOhi0l9U",
    settings: %{"time" => "3 min"}
  },
  %{
    name: "Supine Neck Release",
    slug: "supine-neck-release",
    description:
      "The supine neck release is a gentle way to de-facilitate overactive neck muscles (SCM/Upper Traps). Lie on your back with a rolled towel under the curve of your neck. Let the weight of your head rest heavily. Perform tiny, micro-movements (nodding 'yes' or 'no') to release tension. This communicates safety to the nervous system, allowing the 'protective' tension to dissipate. Citations: Somatic Movement Therapy.",
    muscle_group: "Spine & Mobility",
    video_url: "https://www.youtube.com/embed/fVEhuuwHDvk",
    settings: %{"time" => "2 min"}
  },
  %{
    name: "Anti-Shrug Reset",
    slug: "anti-shrug-reset",
    description:
      "The anti-shrug reset trains the brain to recognize the difference between tension (shrugged) and relaxation (depressed). Inhale and shrug your shoulders up to your ears as hard as possible for 3 seconds. Exhale forcefully and drop your shoulders down as far as they will go, aiming for your back pockets. This exaggerated contract-relax cycle helps reset the resting length of the upper traps. Citations: Jacobson Progressive Relaxation.",
    muscle_group: "Trapezius",
    video_url: "https://www.youtube.com/embed/BzIYs25IzPw",
    settings: %{"result" => "2 x 10 reps"}
  },
  %{
    name: "Single-Arm Prone Y",
    slug: "single-arm-prone-y",
    description:
      "The single-arm prone 'Y' lift isolates the lower trapezius, the primary stabilizer of the shoulder blade. Lie face down. Slide your shoulder blade down and back (towards the opposite hip) *before* lifting your arm. Raise your arm in a 'Y' angle. By doing this unilateral (one arm), you prevent the stronger side from compensating. This is critical for fixing scapular winging. Citations: NASM Corrective Exercise.",
    muscle_group: "Trapezius",
    video_url: "https://www.youtube.com/embed/OQBV8_C1-_o",
    settings: %{"result" => "10L / 5R", "weight" => "2.5 lbs"}
  },
  %{
    name: "Wall Clock Isometrics",
    slug: "wall-clock-isometrics",
    description:
      "Wall clock isometrics build rotator cuff stability without joint movement. Stand sideways to a wall with your elbow bent at 90 degrees. Press the *back* of your hand into the wall (external rotation) as if trying to push the wall away. Hold for time. This isometric contraction wakes up the infraspinatus and teres minor, which are crucial for keeping the shoulder head centered in the socket. Citations: PhysioTutors.",
    muscle_group: "Deltoids",
    video_url: "https://www.youtube.com/embed/ZnGLOVRfbZw",
    settings: %{"time" => "30s/side"}
  },
  %{
    name: "Quadruped Scapular Push-Ups",
    slug: "quadruped-scap-pushups",
    description:
      "Performing scapular push-ups in a quadruped (all-fours) position reduces the gravity load, allowing for perfect motor control. Keep elbows straight. Sink the chest toward the floor (retraction), then push the floor away aggressively (protraction/plus). The 'plus' phase targets the Serratus Anterior, the muscle that prevents scapular winging. This regression ensures the upper traps don't take over. Citations: Mike Reinold.",
    muscle_group: "Pectoralis Major",
    video_url: "https://www.youtube.com/embed/LeTBSJxl4HM",
    settings: %{"result" => "3 x 12"}
  },
  %{
    name: "Suitcase Carry",
    slug: "suitcase-carry",
    description:
      "The suitcase carry is a unilateral loaded carry that builds lateral core stability (`QL` muscle) and grip strength. Hold a heavy weight in *one* hand. Walk with perfect posture, resisting the urge to lean toward the weight. Imagine a string pulling your head upward. This helps re-align the pelvis and spine while dynamically stabilizing the shoulder girdle. Citations: Dr. Stuart McGill.",
    muscle_group: "Abdominals",
    video_url: "https://www.youtube.com/embed/3RKKnZhhelE",
    settings: %{"distance" => "50 yds", "weight" => "26 lbs (12kg)"}
  },
  %{
    name: "Scissor Stance Iso-Hold",
    slug: "scissor-stance-iso",
    description:
      "The scissor stance iso-hold is a static lunge that builds extreme stability in the hips and knees. Step into a long lunge position. Lower your back knee until it is 1-2 inches off the ground and *hold*. Keep your torso upright and hips square. This burns out the stabilizer muscles without the impact of jumping or heavy loading. It's excellent for tendon strength. Citations: E3 Rehab.",
    muscle_group: "Quadriceps",
    video_url: "https://www.youtube.com/embed/egByzktIWZo",
    settings: %{"time" => "45s/side"}
  },
  %{
    name: "Statue Dead Bug",
    slug: "statue-dead-bug",
    description:
      "The 'statue' dead bug is an isometric variation where you hold the extended position rather than moving. Extend opposite arm and leg, and *freeze*. Push your lower back into the floor with maximum intensity. This isometric tension teaches the core to brace against extension forces, which is vital for protecting the lumbar spine during sports. Citations: Dead Bug variations.",
    muscle_group: "Abdominals",
    video_url: "https://www.youtube.com/embed/I5I5I5I5I5",
    settings: %{"time" => "45s hold"}
  },
  %{
    name: "Water Walking",
    slug: "water-walking",
    description:
      "Water walking utilizes the hydrostatic pressure and resistance of water to unload joints while providing active recovery. Walk forward, backward, and laterally in chest-deep water. The water supports the spine, reducing compressive forces, while the resistance engages stabilizing muscles. It is the perfect 'flush' for sore muscles and stiff joints. Citations: Aquatic Therapy Standards.",
    muscle_group: "Cardiovascular System",
    video_url: "https://www.youtube.com/embed/ZgxniVfKT4I",
    settings: %{"time" => "10 min"}
  },
  %{
    name: "Contrast Therapy",
    slug: "contrast-therapy",
    description:
      "Contrast therapy using a steam room and whirlpool facilitates recovery by increasing blood flow and softening fascia. Start with 5 minutes in the steam room to induce vasodilation and relaxation. Follow with 5 minutes in the whirlpool, focusing the jets on the mid-back (avoiding the neck). Finish with a 30-second cold shower to reduce inflammation and close the pores. This protocol aids in spinal decompression and systemic flushing of metabolic waste. Citations: International Journal of Sports Medicine.",
    muscle_group: "Spine & Mobility",
    video_url: "https://www.youtube.com/embed/Xswl-eRKOX0",
    resources: "Steam Room + Whirlpool + Cold Finish."
  },

  # --- ONE-SHOT (The Equalizer) ---
  %{
    name: "Offset Split Squat",
    slug: "offset-split-squat",
    description:
      "The offset split squat holds the weight on the *opposite* side of the working leg (e.g., Left foot forward, weight in Right hand). This 'offset' load creates an anti-rotational challenge for the core, forcing the glutes to work harder to stabilize the hip. It builds 3D athleticism and prevents asymmetrical imbalances. Citations: Functional Movement Systems.",
    muscle_group: "Gluteal Complex",
    video_url: "https://www.youtube.com/embed/Vd3Yf0eZkIA",
    resources: "3D leg strength."
  },
  %{
    name: "3-Point Dumbbell Row",
    slug: "3-point-row",
    description:
      "The 3-point row (hand on bench, two feet on floor) provides a stable base for heavy rowing. The 'dead stop' variation involves placing the weight on the floor between each rep. This eliminates the stretch reflex, forcing you to generate pure concentric power. It also allows you to reset your scapula before every pull, ensuring the upper trap doesn't take over. Citations: Joe DeFranco.",
    muscle_group: "Latissimus Dorsi",
    video_url: "https://www.youtube.com/embed/pYcpY20231Y",
    resources: "Pure concentric back power."
  },
  %{
    name: "Push-Up to Down-Dog",
    slug: "pushup-down-dog",
    description:
      "The Push-Up to Down-Dog combines a chest press with an overhead mobility flow. Perform a push-up, then immediately drive your hips high and heels down into a 'Down Dog'. This transition actively engages the Serratus Anterior (scapular upward rotation) and stretches the posterior chain (hamstrings/calves). It turns a standard push-up into a full-body mobility drill. Citations: Yoga for Athletes.",
    muscle_group: "Pectoralis Major",
    video_url: "https://www.youtube.com/embed/6v6v6v6v6v6",
    resources: "Strength meets mobility."
  },

  # --- ONE-SHOT (Smith-Dumbbell Protocol) ---
  %{
    name: "Smith Machine Incline Bench",
    slug: "smith-incline-bench",
    description:
      "Targeting the clavicular head of the pecs. Set the bench to 30-45 degrees. The fixed path allows you to safely push closer to failure on the upper chest without stabilization limiting the load.",
    muscle_group: "Pectoralis Major",
    video_url: "https://www.youtube.com/embed/8urE8Z8AMQ4",
    resources: "Upper chest isolation.",
    settings: %{"result" => "4 x 8-12"}
  },
  %{
    name: "Smith Machine Bent-Over Row",
    slug: "smith-row",
    description:
      "A back thickness builder. Bend at the hips (hinge), keep the spine neutral, and pull the bar to the lower abs. The guide rails allow you to focus purely on the pull and contraction of the lats and rhomboids.",
    muscle_group: "Latissimus Dorsi",
    video_url: "https://www.youtube.com/embed/ZFNLCpj8e-o",
    resources: "Back thickness and stability.",
    settings: %{"result" => "4 x 10-12"}
  },
  %{
    name: "Smith Machine Shrug",
    slug: "smith-shrug",
    description:
      "Isolating the upper traps. Keep the arms straight and elevate the scapula towards the ears. The Smith machine allows for heavy loading without the friction of dumbbells against the thighs.",
    muscle_group: "Trapezius",
    video_url: "https://www.youtube.com/embed/cT5_GyOXIgE",
    resources: "Trap development.",
    settings: %{"result" => "3 x 15-20"}
  },
  %{
    name: "Smith Machine Calf Raise",
    slug: "smith-calf-raise",
    description:
      "Place a block or plate under the toes. Unrack the weight on your traps (like a squat). Lower the heels for a deep stretch, then drive up onto the big toes. Essential for full range of motion calf training.",
    muscle_group: "Triceps Surae",
    video_url: "https://www.youtube.com/embed/hh5516HCu4k",
    resources: "Loaded calf stretch.",
    settings: %{"result" => "4 x 15-20"}
  },
  %{
    name: "Dumbbell Incline Curl",
    slug: "db-incline-curl",
    description:
      "Seated on an incline bench, let your arms hang behind your torso. This stretches the long head of the biceps. Curl up without moving the elbows forward. A strict isolation movement.",
    muscle_group: "Biceps Brachii",
    video_url: "https://www.youtube.com/embed/soxrZlIl35U",
    resources: "Bicep long head stretch.",
    settings: %{"result" => "3 x 12-15"}
  },
  %{
    name: "Dumbbell Lateral Raise",
    slug: "db-lateral-raise",
    description:
      "Targeting the medial deltoids to build shoulder width. Lead with the elbows, not the hands. Pour the pitcher at the top. Keep constant tension.",
    muscle_group: "Deltoids",
    video_url: "https://www.youtube.com/embed/3VcKaXpzqRo",
    resources: "Side delt isolation.",
    settings: %{"result" => "3 x 15-20"}
  },
  %{
    name: "Dumbbell Overhead Extension",
    slug: "db-overhead-ext",
    description:
      "Seated or standing, lower the dumbbell behind the head to stretch the long head of the triceps. Extend the elbow to lockout. Keep elbows tucked in.",
    muscle_group: "Triceps Brachii",
    video_url: "https://www.youtube.com/embed/nRiJVZDpdL0",
    resources: "Tricep long head mass.",
    settings: %{"result" => "3 x 12-15"}
  },
  %{
    name: "Smith Machine Squat",
    slug: "smith-squat",
    description:
      "The Smith Machine Squat targets the anterior chain (quads) by allowing for a vertical torso position and foot placement further forward than a free barbell squat. This minimizes shear force on the lumbar spine. Descend until thighs are parallel. Drive through heels. Safety stops allow for solo drop sets.",
    muscle_group: "Quadriceps",
    video_url: "https://www.youtube.com/embed/XQ1KPrxmy0M",
    resources: "High-threshold hypertrophy with safety.",
    settings: %{"result" => "4 x 8-12 + Drop Sets"}
  },
  %{
    name: "Dumbbell Bulgarian Split Squat",
    slug: "db-bulgarian-split-squat",
    description:
      "The ultimate unilateral leg builder. Elevate the rear foot on a bench and squat with the front leg. This creates a massive stretch in the rear hip flexor and forces the front glute/quad to handle the entire load. It also corrects left/right imbalances.",
    muscle_group: "Quadriceps",
    video_url: "https://www.youtube.com/embed/2C-uNgKwPLE",
    resources: "Unilateral strength and balance.",
    settings: %{"result" => "3 x 12/leg"}
  },
  %{
    name: "Smith Machine Bench Press",
    slug: "smith-bench",
    description:
      "The Smith Machine Bench Press provides a fixed linear path, allowing for greater isolation of the pectorals and anterior deltoids without the need for stabilization. Align the bar with the lower chest to protect the shoulders. Use a slow, controlled eccentric phase.",
    muscle_group: "Pectoralis Major",
    video_url: "https://www.youtube.com/embed/O5viuEPDXKY",
    resources: "Chest isolation and safety.",
    settings: %{"result" => "4 x 8-12 + Drop Sets"}
  },
  %{
    name: "Dumbbell Pullover",
    slug: "db-pullover",
    description:
      "A classic bodybuilding movement that targets both the lats and the serratus anterior. Lie perpendicular to a bench and lower a dumbbell behind your head with slightly bent arms. Focus on the stretch.",
    muscle_group: "Latissimus Dorsi",
    video_url: "https://www.youtube.com/embed/FK4rHfWKEac",
    resources: "Ribcage expansion and serratus work.",
    settings: %{"result" => "3 x 15"}
  },
  %{
    name: "Smith Machine RDL",
    slug: "smith-rdl",
    description:
      "The Smith Machine Romanian Deadlift (RDL) locks the bar in a vertical path, forcing a strict hip hinge. This removes the balance variable, often allowing for a better stretch in the hamstrings and glutes with less lower back fatigure than the free weight version.",
    muscle_group: "Hamstrings",
    video_url: "https://www.youtube.com/embed/cII0H9u3mEE",
    resources: "Hamstring isolation and hinge pattern.",
    settings: %{"result" => "3 x 10-12"}
  },
  %{
    name: "Dumbbell Single-Leg RDL",
    slug: "db-single-leg-rdl",
    description:
      "A hinge movement performed on one leg. This challenges the hamstring and glute while heavily engaging the intrinsic foot muscles for balance. Keep the hips square to the floor.",
    muscle_group: "Hamstrings",
    video_url: "https://www.youtube.com/embed/J0bEKhnP-Mw",
    resources: "Hamstring stretch and balance.",
    settings: %{"result" => "3 x 10/leg"}
  },
  %{
    name: "Smith Machine Shoulder Press",
    slug: "smith-shoulder-press",
    description:
      "A seated overhead press on the Smith Machine. The fixed path allows for greater vertical pushing power without lateral stabilization. Keep elbows slightly forward of the hips.",
    muscle_group: "Deltoids",
    video_url: "https://www.youtube.com/embed/OLqZDUUD2b0",
    resources: "Vertical pushing power.",
    settings: %{"result" => "3 x 10-12"}
  },
  %{
    name: "Prone YWT Raises",
    slug: "ywt-raises",
    description:
      "Lying face down (prone) on an incline bench. Raise light dumbbells in a Y, W, and T pattern to target the lower traps and rear delts.",
    muscle_group: "Trapezius",
    video_url: "https://www.youtube.com/embed/QdGTI4Lshg4",
    resources: "Postural health.",
    settings: %{"result" => "15 reps"}
  },
  %{
    name: "Gironda Dips",
    slug: "gironda-dips",
    description:
      "A chest-focused dip variation popularized by Vince Gironda. Use wide V-bars, tuck your chin to your chest, round your back, and point your toes forward. Flare the elbows wide.",
    muscle_group: "Pectoralis Major",
    video_url: "https://www.youtube.com/embed/IfINMJ9SPDA",
    resources: "Wide chest development.",
    settings: %{"result" => "Failure"}
  },
  %{
    name: "Decline Push-Ups",
    slug: "decline-push-ups",
    description:
      "Feet elevated on a bench, hands on the floor. This shifts the focus to the upper chest (clavicular head) and front delts.",
    muscle_group: "Pectoralis Major",
    video_url: "https://www.youtube.com/embed/SKPab2YC8BE",
    resources: "Upper chest focus.",
    settings: %{"result" => "Failure"}
  },
  %{
    name: "Incline Push-Ups",
    slug: "incline-push-ups",
    description:
      "Hands elevated on a bench, feet on the floor. This shifts the focus to the lower chest. It is mechanically easier than flat push-ups, making it a great burnout finisher.",
    muscle_group: "Pectoralis Major",
    video_url: "https://www.youtube.com/embed/Me9bHFAxnCs",
    resources: "Lower chest burnout.",
    settings: %{"result" => "Failure"}
  },
  %{
    name: "StairMaster",
    slug: "stairmaster",
    description:
      "The StairMaster provides a high-intensity, low-impact cardio workout that reinforces the step-up pattern. Maintain an upright posture and do NOT lean on the rails.",
    muscle_group: "Cardiovascular System",
    video_url: "https://www.youtube.com/embed/sudbdjw6-Vc",
    resources: "Glute-focused cardio without impact.",
    settings: %{"time" => "10 min"}
  },
  %{
    name: "Cat-Cow Flow",
    slug: "cat-cow",
    description:
      "A fundamental spinal undulation. Inhale to arch the back and look up (Cow), exhale to round the spine and tuck the chin (Cat). Lubricates the vertebrae.",
    muscle_group: "Spine & Mobility",
    video_url: "https://www.youtube.com/embed/LIVJZZyZ2qM",
    resources: "Spinal lubrication.",
    settings: %{"time" => "2 min"}
  },
  %{
    name: "Downward Dog",
    slug: "downward-dog",
    description:
      "An inversion that stretches the entire posterior chain (calves, hamstrings, back). Press through the hands to lengthen the spine.",
    muscle_group: "Spine & Mobility",
    video_url: "https://www.youtube.com/embed/sd-Fn6xpyeg",
    resources: "Posterior chain screamer.",
    settings: %{"time" => "1 min"}
  },
  %{
    name: "Low Lunge",
    slug: "low-lunge",
    description:
      "Anjaneyasana. Stretches the hip flexors (psoas) of the back leg. Essential for undoing the effects of sitting.",
    muscle_group: "Quadriceps",
    video_url: "https://www.youtube.com/embed/qMPN9cCDCq8",
    resources: "Hip flexor release.",
    settings: %{"time" => "2 min/side"}
  },
  %{
    name: "Puppy Pose",
    slug: "puppy-pose",
    description:
      "Melting Heart pose. Combining Child's Pose with Down Dog. Keeps hips high while melting the chest to the floor. Opens the thoracic spine and lats.",
    muscle_group: "Spine & Mobility",
    video_url: "https://www.youtube.com/embed/o-H-MB7foaA",
    resources: "Thoracic opener.",
    settings: %{"time" => "2 min"}
  },
  %{
    name: "Thoracic Spine Rotation",
    slug: "thoracic-spine-rotation",
    description:
      "A mobility drill to improve rotation in the upper back (thoracic spine) while keeping the lumbar spine stable. Start on all fours (quadruped), place one hand behind your head, and rotate your elbow up towards the ceiling, following it with your eyes.",
    muscle_group: "Spine & Mobility",
    video_url: "https://www.youtube.com/embed/S2i4i_0hT24",
    resources: "Improves T-spine mobility and posture.",
    settings: %{"result" => "10 reps/side"}
  },

  # --- ONE-SHOT (Dip Station & Abs) ---
  %{
    name: "Dip Support Hold",
    slug: "dip-support-hold",
    description:
      "Hold the top position of a dip with arms locked out. Depress the scapula (push shoulders down away from ears) and brace the core. This builds immense static strength and shoulder stability.",
    muscle_group: "Triceps Brachii",
    video_url: "https://www.youtube.com/embed/_vPttkLHZMw",
    resources: "Static strength foundation.",
    settings: %{"time" => "3 x 30s"}
  },
  %{
    name: "Negative Dips",
    slug: "negative-dips",
    description:
      "Jump to the top position of a dip. Lower yourself as slowly as possible (aim for 5-10 seconds) until you reach the bottom range. Jump back up. Do not push up. This overloads the triceps and chest eccentrically.",
    muscle_group: "Triceps Brachii",
    video_url: "https://www.youtube.com/embed/QSb4aA7wK00",
    resources: "Eccentric overload for growth.",
    settings: %{"result" => "3 x 5 reps"}
  },
  %{
    name: "Hanging Knee Tucks",
    slug: "hanging-knee-tucks",
    description:
      "Hang from a bar. Bring your knees up to your chest, rounding your lower back at the top to engage the abs. Control the lowering phase avoiding swinging.",
    muscle_group: "Abdominals",
    video_url: "https://www.youtube.com/embed/ACnl_apRkqU",
    resources: "Lower ab compression.",
    settings: %{"result" => "3 x 15-20"}
  },
  %{
    name: "Hanging Windshield Wipers",
    slug: "windshield-wipers",
    description:
      "Hang from a bar and lift your legs (toes to bar or tucked). Rotate your legs from side to side like a windshield wiper. Controls the obliques and serratus.",
    muscle_group: "Abdominals",
    video_url: "https://www.youtube.com/embed/ygwy2b2marI",
    resources: "Oblique mastery.",
    settings: %{"result" => "3 x 10/side"}
  }
]

for attrs <- exercises do
  upsert.(attrs)
end
