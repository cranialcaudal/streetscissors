# Streetscissors Content Architecture

The Phoenix backend has been refactored to support a modular, Obsidian-friendly Markdown structure. The `content` folder acts as the single source of truth for both blogs and the fitness portal.

## Root Directory (`/content/`)

```text
content/
├── another-blog/         # Standard markdown blog posts
├── fitness-blog/         # Standard markdown blog posts
├── latent-sensus/        # Standard markdown blog posts
├── sports-blog/          # Standard markdown blog posts
├── templates/            # Obsidian templates (IGNORED by Phoenix)
│   ├── blog-template.md
│   ├── fitness-module-template.md
│   └── fitness-weekly-template.md
└── fitness/              # The Modular Fitness Portal
    ├── modules/          # Reusable "Lego" blocks (IGNORED directly by router)
    └── weekly/           # Top-level wrappers (Parsed by Vault.ex)
```

## How the Fitness Portal Works (`/content/fitness/`)

The fitness system is built on a two-tier architecture: **Wrappers** and **Modules**.

### 1. The Modules (`/content/fitness/modules/`)
Modules are the granular building blocks. They contain the actual exercises, sets, reps, and YouTube links. 
- Example: `rotational-separation.md`, `ironman-long-run.md`, `universal-cooldown.md`.
- These files **cannot** be rendered on their own by the web app. They must be called by a Wrapper.

### 2. The Wrappers (`/content/fitness/weekly/`)
These are the files that represent the Tabs on the `/fitness/regimen` page (e.g., `monday.md`, `thursday.md`, `core-module.md`).

The backend `Vault.ex` engine reads the frontmatter of these files. The magic happens in the `modules:` array:

```yaml
---
title: Rotational Core & Stability
tab: Core
modules: core-warmup, core-anti-extension, core-anti-rotation, core-rotational-power
---
```

When the page loads, the Phoenix server reads this list, reaches into the `modules/` folder, grabs the content of those four files, and stitches them together vertically underneath the wrapper's introductory text.

### The Templates Directory (`/content/templates/`)
Because the `Manuscripts` controller explicitly only looks for the 4 specific blog folders, and the `Vault` controller explicitly only looks inside `fitness/weekly/` and `fitness/modules/`, the `templates/` directory is **completely invisible** to the web application. 

You can use this folder in Obsidian to easily duplicate and create new content without breaking the site.
