# Manyfold 3D Library – Scan & Analysis

## 1. Context & Goals

This report documents a comprehensive scan and analysis of the 3D model library located at `/mnt/storage0/media/Library/3DModels` on the NAS. The primary goal is to prepare this library for ingestion into Manyfold, a 3D model management system.

The desired conceptual structure follows a hierarchical taxonomy:

```
3D Models / Type / Artist / Fandom / Model
```

Where:
- **Type**: Broad category (e.g., Bust, Chibi, Diorama, Functional, Statues, Warhammer, Weapon)
- **Artist**: Sculptor or studio name (e.g., Bulkamancer, Kiba Monster, NomNom Figures)
- **Fandom**: Intellectual property or universe (e.g., Pokemon, Marvel, Baldur's Gate 3, or "Original")
- **Model**: The specific model name, cleaned and human-readable

This analysis is read-only; no files have been moved, deleted, or modified.

## 2. High-level Stats

### 2.1 Overall Statistics

- **Total directories scanned**: 3,880
- **Total STL files**: 23,276
- **Total image files**: 12,303 (JPG: 9,128, PNG: 2,907, others)
- **Total archive files**: 2,436 (ZIP: 2,184, RAR: 194, 7Z: 58)
- **Total slicer project files**: 4,936 (LYS: 4,786, Chitubox: 150)
- **Total OBJ files**: 223
- **Total PDF documents**: 203

### 2.2 Directory Classification

Directories are classified by their primary content:

| Label | Count | Description |
|-------|-------|-------------|
| `model_dir` | 3,102 | Contains 3D models or archives |
| `render_only` | 468 | Contains only rendered images |
| `docs_only` | 53 | Contains only documentation |
| `misc` | 257 | Mixed content without clear category |

### 2.3 File Type Distribution

Number of directories containing each file type:

| File Type | Directories |
|-----------|-------------|
| 3D Models | 2,380 |
| Images | 2,102 |
| Archives | 954 |
| Slicer Projects | 696 |
| Other | 400 |
| Documents | 214 |

### 2.4 Top File Extensions

| Extension | Count | Description |
|-----------|-------|-------------|
| `.stl` | 23,276 | 3D model files |
| `.jpg` | 9,128 | Preview/render images |
| `.lys` | 4,786 | Lychee slicer projects |
| `.png` | 2,907 | Preview/render images |
| `.zip` | 2,184 | Archive files |
| `.obj` | 223 | Alternative 3D format |
| `.pdf` | 203 | Documentation |
| `.rar` | 194 | Archive files |
| `.chitubox` | 150 | Chitubox slicer projects |

## 3. Observations About Current Layout

### 3.1 Overall Structure

The library follows a somewhat consistent structure, with most models organized as:

```
<Type>/<Artist or Source>/<Fandom or Collection>/<Model Name>
```

However, there are significant variations and inconsistencies:

1. **Top-level categories are well-defined**: The most common top-level directories are:
   - `Statues` (2,827 instances) - The dominant category
   - `Functional` (521 instances) - Practical objects like storage, accessories
   - `Diorama` - Scene-based models
   - `Warhammer` - Miniatures and game pieces
   - `Chibi` (232 instances) - Stylized characters
   - `Bust` (124 instances) - Character busts

2. **Artist/Studio names are frequently present**:
   - `NomNom Figures` (899 instances)
   - `Rescale Miniatures` (859 instances)
   - `Bulkamancer` (174 instances)
   - `Kiba Monster` (194 instances)
   - `CA3D` (151 instances)
   - `OXO 3D` (143 instances)

3. **Fandoms are well-represented**:
   - `Pokemon` (253 instances)
   - `Marvel` (113 instances)
   - Various video game franchises (Overwatch, Final Fantasy, etc.)
   - Anime/manga properties (Dragon Ball, Naruto, etc.)

### 3.2 Render Organization

Rendered images are typically stored in dedicated subdirectories:

- **468 render-only directories** identified
- Most common names: `Renders` (65), `Render` (55), `Render Images` (13)
- However, **315 render-only directories have non-standard names** (e.g., `Instructions`, `Display`, or model-specific folders)
- Many renders appear to be mixed alongside model files rather than in dedicated folders

### 3.3 Archive vs. Extracted Files

A significant pattern emerged around archive files:

- **232 directories contain both archives and extracted STL files**
- This suggests models were downloaded as archives and then extracted, but the archives were retained
- Common pattern: A `.zip` file alongside its extracted contents in the same directory
- This creates redundancy and potential confusion about which version is "canonical"

### 3.4 Slicer Project Files

- **696 directories contain slicer project files** (primarily Lychee `.lys` files)
- These are pre-supported versions of models, often stored alongside unsupported versions
- Common subdirectory names: `Supported`, `Unsupported`, `Presupport`, `Lychee`

### 3.5 Functional Category Complexity

The `Functional` category contains highly nested structures:

- **789 directories exceed depth 6** in nesting
- Most extreme example: `Functional/Printable Accessories/Playmat Storage Tubes/Files/Stands/Modular desk stand/Themed Stands/Old Magic/printing_orientation`
- This category includes modular systems like:
  - `Omni 1/2/3` - Modular display and storage cases
  - `Playmat Storage Tubes`
  - Various organizational accessories

### 3.6 Messy Naming Conventions

Several problematic patterns were identified:

1. **Generic leaf directory names**:
   - `STL` appears 318 times as a directory name
   - `Supported` appears 132 times
   - `Beefed` appears 110 times (likely presupported versions)
   - These provide little information about the actual model

2. **Inconsistent capitalization and formatting**:
   - Mix of underscores, spaces, and hyphens
   - Inconsistent use of version numbers (v1, v2, final)
   - Technical suffixes mixed with model names

3. **Documentation scattered**:
   - 53 docs-only directories
   - PDFs and instructions not consistently organized
   - Some in dedicated `Instructions` folders, others mixed with models

## 4. Proposed Taxonomy

### 4.1 Target Structure

The canonical structure should be:

```
3D Models/<Type>/<Artist>/<Fandom>/<Model>/
```

Each model directory should ideally contain:
- Model files (STL, OBJ, etc.) as a single ZIP archive per model
- A preview image (PNG/JPG)
- Optional: Slicer project files
- Optional: Documentation (PDF, TXT)

### 4.2 Type Values

The following Type categories are recommended based on the library analysis:

| Type | Description | Example Use Cases |
|------|-------------|-------------------|
| `Bust` | Character busts and head/torso sculptures | Display pieces, portrait sculptures |
| `Chibi` | Stylized, super-deformed characters | Cute character figures |
| `Cosplay` | Wearable costume pieces | Props, armor, accessories |
| `Diorama` | Multi-figure scenes or bases | Display scenes, narrative compositions |
| `Functional` | Practical objects for real-world use | Storage, organizers, desk accessories, tool holders |
| `Keycaps` | Custom keyboard keycaps | Mechanical keyboard customization |
| `Miniature` | Tabletop gaming miniatures (non-Warhammer) | D&D, Pathfinder, other RPG minis |
| `Statue` | Full character statues | Display figures, collectibles |
| `Toy` | Articulated figures or playable objects | Action figures, fidget toys |
| `Warhammer` | Warhammer 40K/AoS miniatures | Official and fan-made Warhammer models |
| `Weapon` | Standalone weapons or props | Display weapons, cosplay props |

**Note**: `Statue` should be the default for full-figure character models. `Functional` is for objects with practical utility (storage boxes, tool holders, organizational items).

### 4.3 Artist Field

- Use the actual sculptor/studio name when identifiable
- Common artists: Bulkamancer, CA3D, Kiba Monster, NomNom Figures, OXO 3D, Rescale Miniatures, TitanForge
- Use `"Unknown"` when the artist cannot be determined
- For official game kits (e.g., Warhammer), consider using the manufacturer (e.g., "Games Workshop") or "Official"

### 4.4 Fandom Field

- Use the specific IP/franchise name when applicable:
  - Examples: Pokemon, Marvel, DC, Star Wars, Baldur's Gate 3, Dragon Ball, Overwatch
- Use `"Original"` for original character designs not tied to existing IP
- Use `"Unknown"` when fandom cannot be determined
- Normalize fandom names for consistency (e.g., "Dragon Ball" not "Dragonball" or "DBZ")

### 4.5 Model Field

- Clean, human-readable name derived from directory or file names
- Remove noise words: `stl`, `stls`, `pack`, `bundle`, `presupported`, `supported`, `final`, `v1`, `v2`
- Convert underscores to spaces
- Use title case
- Keep descriptive information (character names, variant info)

### 4.6 File Organization Within Model Directories

Each model directory should be structured as:

```
<Model>/
  ├── model.zip (containing all STL/OBJ files)
  ├── preview.png (or .jpg)
  ├── supported.lys (optional)
  └── instructions.pdf (optional)
```

## 5. Example Mappings

The following examples demonstrate how current paths would map to the proposed taxonomy:

### 5.1 Dioramas

| Current Path | Proposed Path | Type | Artist | Fandom | Model |
|--------------|---------------|------|--------|--------|-------|
| `Diorama/Unknown/Naruto/Hokage Mountain` | `3D Models/Diorama/Unknown/Naruto/Hokage Mountain` | Diorama | Unknown | Naruto | Hokage Mountain |
| `Diorama/Nomnom Figures/Dragon Ball/Vegeta vs Broly` | `3D Models/Diorama/Nomnom Figures/Dragon Ball/Vegeta Vs Broly` | Diorama | Nomnom Figures | Dragon Ball | Vegeta Vs Broly |
| `Diorama/Nomnom Figures/Overwatch/D.va` | `3D Models/Diorama/Nomnom Figures/Overwatch/D.Va` | Diorama | Nomnom Figures | Overwatch | D.Va |
| `Diorama/Bulkamancer/The Witcher/Ciri vs Manticore` | `3D Models/Diorama/Bulkamancer/The Witcher/Ciri Vs Manticore` | Diorama | Bulkamancer | The Witcher | Ciri Vs Manticore |
| `Diorama/Kiba Monster/Pokemon/Lugia vs Ho oh Diorama (battle of gods)/Diorama Lugia Hooh STL` | `3D Models/Diorama/Kiba Monster/Pokemon/Lugia vs Ho-Oh Battle of Gods` | Diorama | Kiba Monster | Pokemon | Lugia vs Ho-Oh Battle of Gods |

### 5.2 Statues

| Current Path | Proposed Path | Type | Artist | Fandom | Model |
|--------------|---------------|------|--------|--------|-------|
| `Statues/NomNom Figures/Pokemon/Charizard` | `3D Models/Statue/NomNom Figures/Pokemon/Charizard` | Statue | NomNom Figures | Pokemon | Charizard |
| `Statues/Bulkamancer/Baldurs Gate 3/Dame Aylin` | `3D Models/Statue/Bulkamancer/Baldurs Gate 3/Dame Aylin` | Statue | Bulkamancer | Baldurs Gate 3 | Dame Aylin |
| `Statues/CA3D/Marvel/Spider-Man` | `3D Models/Statue/CA3D/Marvel/Spider-Man` | Statue | CA3D | Marvel | Spider-Man |
| `Statues/OXO3D/Original Character/Summer Collection` | `3D Models/Statue/OXO3D/Original/Summer Collection` | Statue | OXO3D | Original | Summer Collection |

### 5.3 Warhammer

| Current Path | Proposed Path | Type | Artist | Fandom | Model |
|--------------|---------------|------|--------|--------|-------|
| `Warhammer/Warhammer 30K/IX Legion (Blood Angels)/Sanguinius, Primarch of the IX Legion` | `3D Models/Warhammer/Unknown/Warhammer 30K/Sanguinius Primarch` | Warhammer | Unknown | Warhammer 30K | Sanguinius Primarch |
| `Warhammer/Warhammer 40K/Adeptus Mechanicus/Kastelan Robots` | `3D Models/Warhammer/Official/Warhammer 40K/Kastelan Robots` | Warhammer | Official | Warhammer 40K | Kastelan Robots |

### 5.4 Functional

| Current Path | Proposed Path | Type | Artist | Fandom | Model |
|--------------|---------------|------|--------|--------|-------|
| `Functional/Printable Accessories/Omni 1 - 3D Printable - Modular Display Case for Miniatures` | `3D Models/Functional/Printable Accessories/Original/Omni 1 Display Case` | Functional | Printable Accessories | Original | Omni 1 Display Case |
| `Functional/Printable Accessories/Playmat Storage Tubes` | `3D Models/Functional/Printable Accessories/Original/Playmat Storage Tubes` | Functional | Printable Accessories | Original | Playmat Storage Tubes |

### 5.5 Chibi

| Current Path | Proposed Path | Type | Artist | Fandom | Model |
|--------------|---------------|------|--------|--------|-------|
| `Chibi/Artist Name/Pokemon/Pikachu Chibi` | `3D Models/Chibi/Artist Name/Pokemon/Pikachu` | Chibi | Artist Name | Pokemon | Pikachu |

### 5.6 Multi-Artist Collections

| Current Path | Proposed Path | Type | Artist | Fandom | Model |
|--------------|---------------|------|--------|--------|-------|
| `Diorama/OXO3D/Marvel/Summer Of Super Powers/OXO3D_Figures_Summer_Of_Super_Powers_2025_Diorama_Base_Split` | `3D Models/Diorama/OXO3D/Marvel/Summer Of Super Powers 2025` | Diorama | OXO3D | Marvel | Summer Of Super Powers 2025 |
| `Diorama/CA3D/Asterix & Obelisk/Asterix & Obelisk` | `3D Models/Diorama/CA3D/Original/Asterix & Obelisk` | Diorama | CA3D | Original | Asterix & Obelisk |

## 6. Problem Areas & Ambiguities

### 6.1 Deep Nesting Issues

**Problem**: 789 directories exceed depth 6, primarily in the `Functional` category.

**Example**: `Functional/Printable Accessories/Playmat Storage Tubes/Files/Stands/Modular desk stand/Themed Stands/Old Magic/printing_orientation`

**Recommendation**: Flatten these structures during migration. The deepest levels often represent build variants or file organization that should be consolidated into a single model directory with all variants included.

### 6.2 Archive Redundancy

**Problem**: 232 directories contain both archive files and extracted STL files.

**Impact**:
- Storage inefficiency
- Confusion about which version to use
- Potential for version mismatches

**Recommendation**:
- During migration, create a canonical ZIP archive for each model
- Remove redundant archives if STLs are already extracted
- If archive contains additional files not extracted, merge them

### 6.3 Generic Directory Names

**Problem**: Many directories use generic technical names rather than descriptive model names:
- `STL` (318 instances)
- `Supported` (132 instances)
- `Beefed` (110 instances)
- `Unsupported` (50 instances)

**Impact**: These names provide no information about the actual model content.

**Recommendation**:
- Look to parent directories for actual model names
- For "Supported" vs "Unsupported" variants, consider:
  - Making supported the default version
  - Including both in the same model directory with clear naming
  - Using Manyfold's variant or tag system

### 6.4 Render Organization Inconsistency

**Problem**:
- 468 render-only directories exist
- Only 65 are named "Renders", 55 named "Render"
- 315 have non-standard names like "Instructions", "Display", or model-specific names
- Many renders are mixed with model files

**Recommendation**:
- During migration, extract render images as preview images for parent models
- Consolidate multiple renders into a single preview per model (pick best/most representative)
- Use Manyfold's image preview feature rather than separate render directories

### 6.5 Artist Identification Challenges

**Problem**: Many models don't have clear artist attribution:
- Community remixes and fan sculpts
- Models from aggregate sites without creator info
- Official game pieces (especially Warhammer)

**Recommendation**:
- Use `"Unknown"` when artist can't be determined
- For official game kits, use manufacturer name or `"Official"`
- Consider manual review of high-value or popular models to research attribution
- Use Manyfold's Creator feature to track known artists

### 6.6 Fandom Ambiguity

**Problem**: Some models straddle multiple fandoms or have unclear IP association:
- Crossover characters
- "Inspired by" vs. directly from IP
- Generic fantasy/sci-fi models

**Recommendation**:
- Use primary/most prominent fandom
- Use `"Original"` for generic or heavily modified designs
- Leverage Manyfold's tagging system to add multiple fandom tags where appropriate

### 6.7 Type Classification Edge Cases

**Problem**: Some models don't fit neatly into categories:
- Large statues that could be dioramas
- Functional items themed after fandoms (Pokemon organizers, Marvel desk holders)
- Articulated figures vs. static statues

**Recommendation**:
- Prioritize function over form:
  - If it's meant to be used practically → `Functional`
  - If it's primarily for display → `Statue`, `Diorama`, etc.
- For articulated figures → `Toy`
- For multi-piece scenes → `Diorama`
- For single character display → `Statue` or `Bust`

### 6.8 Slicer Project Organization

**Problem**: 696 directories contain slicer projects, organized inconsistently:
- Sometimes in `Supported` subdirectories
- Sometimes alongside unsupported versions
- Multiple slicer formats (Lychee, Chitubox)

**Recommendation**:
- Include slicer projects in model archives
- Use clear naming: `model_name_supported.lys`
- Consider treating pre-supported versions as "variants" in Manyfold

### 6.9 Documentation Files

**Problem**: 53 docs-only directories, 214 directories with documentation total:
- Assembly instructions
- Licensing information
- Print settings recommendations
- Mixed with models vs. separate folders

**Recommendation**:
- Include relevant documentation in model archives
- Attach instructions to specific models in Manyfold
- Create a separate "Documentation" library or collection for general guides

### 6.10 Potential Duplicates

**Problem**: Some model names appear many times (5+ instances):
- Could be legitimate variants or collections
- Could be duplicates from different sources
- Could be models with generic names

**Recommendation**:
- Manual review of high-frequency model names
- Use Manyfold's duplicate detection features
- Consider consolidating true duplicates
- For variants (different scales, poses), use Manyfold's relationship/variant features

## 7. Recommended Next Steps

### 7.1 Phase 1: Validation & Refinement

1. **Manual Review Sample**:
   - Review 50-100 representative models across all Types
   - Validate taxonomy assignments
   - Identify additional edge cases
   - Refine Type/Artist/Fandom classification rules

2. **Create Comprehensive Mapping**:
   - Generate a machine-readable CSV/JSON mapping file:
     - Columns: `current_path`, `type`, `artist`, `fandom`, `model_name`, `target_path`
   - Include all 3,880 directories
   - Flag ambiguous cases for manual review
   - Include file inventory (STLs, renders, docs) per model

3. **Develop Artist & Fandom Dictionaries**:
   - Create canonical lists of recognized artists with name variants
   - Create canonical fandom names with aliases (e.g., "Dragon Ball" = "Dragonball" = "DBZ")
   - Use these for normalization during automated mapping

### 7.2 Phase 2: File Preparation

1. **Archive Creation Script**:
   - For each model directory:
     - Create a ZIP archive containing all STL/OBJ files
     - Include slicer projects if present
     - Include documentation if present
     - Name: `<model_name>.zip`
   - Extract best preview image
   - Generate manifest/inventory

2. **Deduplication Pass**:
   - Identify directories with both archives and extracted STLs
   - Remove redundant archives or extracted files (keep one canonical version)
   - Consolidate split model parts into single archives

3. **Render Consolidation**:
   - Extract preview images from render-only directories
   - Associate with parent model directories
   - Select 1-3 best preview images per model

### 7.3 Phase 3: Directory Restructuring

1. **Create New Directory Structure**:
   - Create target directory tree following `Type/Artist/Fandom/Model` structure
   - Use the mapping generated in Phase 1

2. **Migration Script**:
   - Copy (not move initially) files to new structure
   - Maintain original directory as backup
   - Log all operations for review
   - Validate file counts and sizes match

3. **Verification**:
   - Compare source vs. target directory trees
   - Verify no data loss
   - Spot-check random samples
   - Generate migration report

### 7.4 Phase 4: Manyfold Configuration

1. **Library Setup**:
   - Create Manyfold libraries for each Type (or group related Types)
   - Configure scan paths
   - Set up file watching for new additions

2. **Creator (Artist) Configuration**:
   - Import canonical artist list
   - Set up creator profiles with metadata
   - Link models to creators

3. **Collection & Tag Configuration**:
   - Create collections for Fandoms
   - Create tags for:
     - Scale/size (75mm, 178mm, etc.)
     - Support status (supported, unsupported)
     - Quality markers (presupported, beefed)
     - File types available (multi-part, single piece, modular)
   - Apply tags based on directory analysis

4. **Metadata Enhancement**:
   - Add descriptions to high-value models
   - Link related models (variants, parts of sets)
   - Add license information where available

### 7.5 Phase 5: Cleanup & Optimization

1. **Remove Redundancy**:
   - After successful migration and verification
   - Archive or delete old directory structure
   - Remove duplicate files identified during deduplication

2. **Optimize for Manyfold**:
   - Ensure preview images are web-optimized (reasonable resolution/size)
   - Validate ZIP archives are not corrupted
   - Ensure file naming conventions are consistent

3. **Documentation**:
   - Create usage guide for Manyfold library
   - Document taxonomy and tagging conventions
   - Create maintenance procedures for adding new models

### 7.6 Automation Considerations

**Scripting Recommendations**:
- Use Python for migration scripts (pathlib, shutil, zipfile)
- Generate detailed logs (INFO, WARNING, ERROR levels)
- Implement dry-run mode for testing
- Create rollback capability
- Parallelize where safe (file copying, archive creation)

**Safety Measures**:
- ALWAYS work on copies first
- Maintain checksums of original files
- Create incremental backups during migration
- Test migration on small subset first (e.g., one artist or fandom)

### 7.7 Timeline Estimate

This is purely for planning purposes - actual time will vary based on:
- Level of manual review desired
- Automation sophistication
- Storage/network speed
- Manyfold import performance

**Suggested phases**:
1. Validation & Mapping: Review and refine approach
2. File Preparation: Archive creation, deduplication
3. Migration: Copy to new structure
4. Manyfold Setup: Import and configure
5. Verification & Cleanup: Validate and optimize

## 8. Technical Notes

### 8.1 Scan Methodology

The analysis was performed using a Python script that:
- Recursively walked all 3,880 directories
- Categorized files by extension into: 3d_model, slicer, archive, image, doc, other
- Generated a JSON Lines summary with per-directory statistics
- Classified directories by primary content type
- Extracted path components for taxonomy inference

### 8.2 Data Files

The following temporary files were generated during analysis:
- `/tmp/3dmodels_dir_summary.jsonl` (on NAS) - Full directory inventory
- `/tmp/taxonomy_examples.json` (local) - Sample taxonomy mappings

These files can be used as input for migration scripting.

### 8.3 Manyfold Integration

Manyfold features relevant to this migration:
- **Libraries**: Organize models by Type or collection
- **Creators**: Track artists/sculptors
- **Collections**: Group related models (e.g., by fandom, theme, set)
- **Tags**: Flexible metadata (scale, support status, quality, etc.)
- **Links**: Connect related models or variants
- **Bulk editing**: Essential for applying tags and metadata at scale

### 8.4 Storage Considerations

Current library statistics:
- 3,880 directories
- 23,276 STL files
- 2,436 archives (potential redundancy)
- 12,303 images (many could be consolidated)

Estimated storage impact after optimization:
- Deduplication: ~10-15% reduction from removing redundant archives
- Render consolidation: ~20-30% reduction in image files
- Archive consolidation: Potential increase if creating per-model archives from loose files

---

**Report Generated**: 2025-11-21
**Library Path**: `/mnt/storage0/media/Library/3DModels` (NAS)
**Target Path**: To be determined during Phase 3
**Analysis Method**: Automated scan + manual taxonomy inference
**Status**: Read-only analysis complete, ready for migration planning
