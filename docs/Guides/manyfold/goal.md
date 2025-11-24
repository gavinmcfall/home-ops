You are an AI coding assistant running inside VS Code with access to:

- The VS Code integrated terminal
- SSH (to connect to my NAS as `ssh truenas`)
- The local filesystem under `/home/gavin`
- Basic CLI tools (bash, python3, find, awk, etc.)

Your job is to:

1. SSH into my NAS
2. Deeply scan the 3D model library at `/mnt/storage0/media/Library/3DModels`
3. Analyse the folder/file layout
4. Generate a human-readable *Markdown report* describing the current state and suggested organisation model
5. Save that report as a `.md` file at:

   `/home/gavin/home-ops/.codex/Guides/manyfold/manyfold_3d_library_analysis.md`

Very important: **do not move, delete, rename, or modify any files** in the library. This pass is purely read/scan + report.

---

## 1. Connect to the NAS and move to the library

1. Open a VS Code integrated terminal.
2. SSH into the NAS:
  ```bash
  ssh truenas
  ```
3. Change to the 3D library root:

  ```bash
  cd /mnt/storage0/media/Library/3DModels
  ```

All subsequent scanning commands should run from this directory.

## 2. Perform a deep scan and build a machine-readable summary

Your goal in this step is to produce a per-directory summary that you can then reason about.

Create and run a Python one-liner/script (from this directory) that:

- Recursively walks all subdirectories
- For each directory, computes:
  - Counts per file category:
    - 3d_model (e.g. `.stl`, `.obj`, `.3mf`, `.step`, `.stp`, etc.)
    - slicer (e.g. `.gcode`, `.lys`, `.chitubox`, etc.)
    - archive (e.g. `.zip`, `.rar`, `.7z`, etc.)
    - image (e.g. `.png`, `.jpg`, `.jpeg`, `.webp`, etc.)
    - doc (e.g. `.pdf`, `.txt`, `.md`, `.docx`, etc.)
    - other
  - Counts per file extension
  - A few example filenames per extension
  - A simple label for the directory:
    - `model_dir` if it contains any 3D model file or archive
    - `render_only` if it only has images
    - `docs_only` if it only has docs
    - `misc` otherwise

- Writes one JSON object per directory (JSON Lines format) to a file such as:

  ```text
  /tmp/3dmodels_dir_summary.jsonl
  ```

Example fields per JSON record:

```json
{
  "directory": "relative/path/from/root",
  "label": "model_dir|render_only|docs_only|misc",
  "files_by_type": {
    "3d_model": 12,
    "image": 5,
    "archive": 1,
    "slicer": 0,
    "doc": 0,
    "other": 3
  },
  "ext_counts": {
    ".stl": 12,
    ".png": 5,
    ".zip": 1
  },
  "sample_files": {
    ".stl": "relative/path/example_model.stl",
    ".png": "relative/path/preview.png",
    ".zip": "relative/path/model_pack.zip"
  },
  "path_parts": ["Busts", "Bulkamancer", "Baldurs Gate 3", "Dame Aylin"]
}
```

After generating this file on the NAS, read it back into your own context (you can stream it, sample from it, or summarise in chunks).

## 3. Analyse the structure and infer a taxonomy

Using the JSON summary, infer:

### 3.1 High-level stats

Compute and later include in the report:

- Total number of directories scanned
  - Number of directories by `label`:
    - `model_dir`, `render_only`, `docs_only`, `misc`
  - Number of directories containing at least one of each category:
    - `3d_model`, `image`, `archive`, `slicer`, `doc`, `other`
- Any notable distributions (e.g. “many directories have both archives and STLs”, “many render-only subfolders named `Renders`,” etc.)

### 3.2 Model taxonomy

Based on directory names (`path_parts`) and example filenames, infer a taxonomy using:

- Type – broad category for the model, e.g.:
  - `Bust`, `Chibi`, `Cosplay`, `Diorama`, `Functional`, `Keycaps`, `Statues`, `Toys`, `Warhammer`, `Weapon`
    - Note: Statues if the primary kind, Functional is for physical things you might bring, like desks, or drawers
  - Artist – sculptor or studio name (e.g. `Bulkamancer`, `Kiba Monster`, `TitanForge`); use "Unknown" if unclear.
  - Fandom – IP / universe (e.g. `Baldurs Gate 3`, `Pokemon`, `Warhammer 40K`, `Star Wars`, `Berserk`, etc.), or `"Original"` / `"Unknown"` where appropriate.
  - Model name – a human-readable cleaned name derived from the leaf directory or key part of `path_parts`, removing noise like:
    - `stls`, `pack`, `bundle`, `presupported`, `supported`, `final`, `v1`, `v2`, etc.
    - Underscores converted to spaces, sensible capitalisation.

You do NOT need to output the full mapping per-directory in this pass, but you should:
- Determine whether a structure of `3D Models/<Type>/<Artist>/<Fandom>/<Model>/` is sensible for this library.
- Collect a handful (10–20) of clear, representative examples showing:
  - Current path
  - Inferred `Type`, `Artist`, `Fandom`, `Model`
  - Proposed target path

### 4. Generate the Markdown report

Now, create a Markdown file locally at:

`/home/gavin/home-ops/.codex/Guides/manyfold/manyfold_3d_library_analysis.md`

The report should be standalone and human-readable.

### 4.1 Recommended report structure

Use headings something like this:

1. `# Manyfold 3D Library – Scan & Analysis`
1. `## 1. Context & Goals`
    - Briefly describe:
    - That the library lives at /mnt/storage0/media/Library/3DModels on the NAS
    - That the goal is to prepare it for Manyfold ingestion
    - The desired conceptual structure: 3D Models / Type / Artist / Fandom / Model
1. `## 2. High-level Stats`
   - Total directories
    - Counts by label (model_dir, render_only, docs_only, misc)
    - Counts of directories that contain each category (3d_model, image, etc.)
1. `## 3. Observations About Current Layout`
    - Bullet points describing patterns such as:
      - Where Busts / Dioramas / Functional models seem to live
      - How renders are typically stored (e.g. Renders subfolder vs mixed in)
      - How often archives coexist with extracted STLs
      - Any messy / inconsistent patterns you can see
1. `## 4. Proposed Taxonomy`
    - Describe the intended structure:
      - Explain Type, Artist, Fandom, Model
      - Provide the canonical list of Type values you think makes sense
    - Mention how official kits vs fan sculpts might be treated
1. `## 5. Example Mappings`
    - For 10–20 good examples:
      - Show Current path
      - Show inferred Type, Artist, Fandom, Model
      - Show Proposed target path: `3D Models/<Type>/<Artist>/<Fandom>/<Model>/`
    - Use code blocks or tables for readability.
1. `## 6. Problem Areas & Ambiguities`
    - Describe:
      - Folders where Type/Artist/Fandom are unclear
      - Cases where many render-only or docs-only folders may need merging
      - Any obvious duplicates or messy naming conventions
1. `## 7. Recommended Next Steps`
    - Suggest a future workflow, e.g.:
      - Generating a machine-readable mapping (JSON/CSV) from old paths to new paths
      - Writing a script to actually move models into the new layout and create a zip per model
      - Configuring Manyfold Libraries, Creators, Collections, and Tags to match the taxonomy

The report should be written in clear, concise English, aimed at a technical user (me) who understands NAS, SSH, Docker, and Manyfold.

## 5. Safety & constraints
- Do not modify, move, or delete any model files in `/mnt/storage0/media/Library/3DModels` during this process.
- You may create temporary files like `/tmp/3dmodels_dir_summary.jsonl` on the NAS for the purpose of scanning.
- You may create or overwrite the final Markdown report at: `/home/gavin/home-ops/.codex/Guides/manyfold/manyfold_3d_library_analysis.md`
- You should log or print what you’re doing in the terminal so it’s reviewable.

## 6. Final deliverable

When done, there must exist a file:

`/home/gavin/home-ops/.codex/Guides/manyfold/manyfold_3d_library_analysis.md`

containing:
- A clear, structured analysis of the current 3D library
- A proposed taxonomy Type / Artist / Fandom / Model
- Concrete example mappings from current paths to proposed new layout
- Recommendations for next steps toward Manyfold migration.

Do not output the entire report in the chat window unless asked; the primary output should be the `.md` file at the specified path.
