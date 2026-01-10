# Part 3: Importing Eggs and Creating Servers

Import community game eggs and create your first game server.

---

## Understanding Nests and Eggs

| Term | Description |
|------|-------------|
| **Nest** | A category of game servers (e.g., "Minecraft", "Steam Games") |
| **Egg** | A specific server configuration within a nest (e.g., "Forge", "Paper", "Vanilla") |

Pterodactyl comes with some default eggs, but the community maintains hundreds more.

---

## Community Egg Repositories

The official community eggs are maintained by the Pelican project:

| Repository | Contents |
|------------|----------|
| [pelican-eggs/games-steamcmd](https://github.com/pelican-eggs/games-steamcmd) | 150+ Steam games (Satisfactory, Valheim, ARK, etc.) |
| [pelican-eggs/minecraft](https://github.com/pelican-eggs/minecraft) | All Minecraft variants (Forge, Paper, CurseForge, etc.) |
| [pelican-eggs/games-standalone](https://github.com/pelican-eggs/games-standalone) | Non-Steam games (Factorio, etc.) |

---

## Importing Eggs

### Step 1: Create a Nest (Optional)

If you want to organize Steam games separately:

1. Go to **Admin Panel** → **Nests**
2. Click **Create New**
3. Name: `Steam Games`
4. Description: `Game servers using SteamCMD`
5. Click **Save**

### Step 2: Download the Egg JSON

Find the game you want and get the raw JSON URL:

**Example URLs:**

| Game | Raw JSON URL |
|------|--------------|
| Satisfactory | `https://raw.githubusercontent.com/pelican-eggs/games-steamcmd/main/Satisfactory/egg-satisfactory.json` |
| Valheim | `https://raw.githubusercontent.com/pelican-eggs/games-steamcmd/main/Valheim/egg-valheim.json` |
| Palworld | `https://raw.githubusercontent.com/pelican-eggs/games-steamcmd/main/Palworld/egg-palworld.json` |
| ARK Survival Ascended | `https://raw.githubusercontent.com/pelican-eggs/games-steamcmd/main/Ark%20Survival%20Ascended/egg-ark-survival-ascended.json` |
| Core Keeper | `https://raw.githubusercontent.com/pelican-eggs/games-steamcmd/main/Core%20Keeper/egg-core-keeper.json` |
| Enshrouded | `https://raw.githubusercontent.com/pelican-eggs/games-steamcmd/main/Enshrouded/egg-enshrouded.json` |
| Conan Exiles | `https://raw.githubusercontent.com/pelican-eggs/games-steamcmd/main/Conan%20Exiles/egg-conan-exiles.json` |
| Icarus | `https://raw.githubusercontent.com/pelican-eggs/games-steamcmd/main/Icarus/egg-icarus.json` |
| CurseForge (Minecraft) | `https://raw.githubusercontent.com/pelican-eggs/minecraft/main/java/curseforge/egg-curse-forge.json` |
| Factorio | `https://raw.githubusercontent.com/pelican-eggs/games-standalone/main/factorio/factorio-vanilla/egg-factorio-vanilla.json` |

### Step 3: Import into Pterodactyl

1. Go to **Admin Panel** → **Nests** → Select your nest
2. Click **Import Egg**
3. Either:
   - Upload the downloaded JSON file, or
   - Paste the raw GitHub URL directly
4. Click **Import**

Repeat for each game you want to support.

---

## Creating a Game Server

### Step 1: Navigate to Server Creation

1. Go to **Admin Panel** → **Servers** → **Create New**

### Step 2: Core Details

| Field | Description |
|-------|-------------|
| Server Name | Display name (e.g., "Nerdz Minecraft") |
| Server Owner | Select or search for the user who will manage it |
| Server Description | Optional description |
| Start Server when Installed | Check to auto-start after install |

### Step 3: Allocation Management

| Field | Value |
|-------|-------|
| Node | Select your Wings node |
| Default Allocation | Pick an available port |
| Additional Allocations | Add more if the game needs multiple ports |

### Step 4: Resource Management

Recommended minimums by game type:

| Game Type | Memory | Disk | CPU |
|-----------|--------|------|-----|
| Minecraft (Vanilla/Paper) | 2048 MiB | 10 GB | 200% |
| Minecraft (Modded/Forge) | 4096 MiB | 20 GB | 400% |
| Valheim | 4096 MiB | 15 GB | 200% |
| Satisfactory | 8192 MiB | 25 GB | 400% |
| ARK | 16384 MiB | 100 GB | 400% |
| Palworld | 8192 MiB | 30 GB | 400% |

> [!TIP]
> Set CPU Limit to `0` for unlimited, or calculate as `threads × 100` (e.g., 4 threads = 400%).

### Step 5: Nest Configuration

1. **Nest**: Select the category (e.g., "Minecraft", "Steam Games")
2. **Egg**: Select the specific server type (e.g., "Forge Minecraft")
3. **Docker Image**: Usually auto-selected, leave default

### Step 6: Service Variables

These vary by egg. Common examples:

**Minecraft Forge:**
| Variable | Description | Default |
|----------|-------------|---------|
| Minecraft Version | Game version | `latest` |
| Build Type | `recommended` or `latest` | `recommended` |
| Server Jar File | JAR filename | `server.jar` |

**Steam Games:**
| Variable | Description |
|----------|-------------|
| Server Name | In-game server name |
| Server Password | Password to join (optional) |
| Max Players | Player limit |

### Step 7: Create and Monitor

1. Click **Create Server**
2. Go to the server's console page to watch installation progress
3. First startup downloads game files (can take 5-30 minutes for Steam games)

---

## Post-Install: Minecraft EULA

Minecraft servers require EULA acceptance before they'll run:

1. Server will start, create files, then exit with:
   ```
   You need to agree to the EULA in order to run the server.
   ```

2. Go to the server's **Files** tab (client view, not admin)
3. Open `eula.txt`
4. Change `eula=false` to `eula=true`
5. Save and **Start** the server

---

## Adding More Allocations

If you need more ports for additional servers:

1. Go to **Admin Panel** → **Nodes** → Your node → **Allocation**
2. Add new port ranges:
   - **IP Address**: `0.0.0.0`
   - **IP Alias**: `play.${SECRET_DOMAIN}`
   - **Ports**: e.g., `27015-27030` (for Source games)

**Don't forget to add port forwards in your router for new ranges!**

---

## Common Port Requirements

| Game | Default Port | Protocol | Additional Ports |
|------|--------------|----------|------------------|
| Minecraft | 25565 | TCP | - |
| Valheim | 2456 | UDP | 2457 (query) |
| Satisfactory | 7777 | UDP | 15000, 15777 |
| ARK | 7777 | UDP | 7778, 27015 (query) |
| Palworld | 8211 | UDP | 27015 (query) |
| Rust | 28015 | TCP/UDP | 28016 (RCON) |
| Factorio | 34197 | UDP | - |

---

## Troubleshooting Server Creation

### Server Stuck on "Installing"

Check Wings logs:
```bash
sudo docker logs wings-wings-1 --tail=50
```

Common causes:
- `/tmp/pterodactyl` mount issue (see Part 2 troubleshooting)
- Network issues downloading game files
- Disk space full

### Server Exits Immediately (Code 0)

- **Minecraft**: EULA not accepted (see above)
- **Steam games**: First run may exit to generate config files — just start again

### Server Crashes with OOM

Increase memory allocation in **Admin** → **Servers** → **Build Configuration**

### Can't Connect from Internet

1. Verify port forward exists for the game's port
2. Check allocation uses `0.0.0.0` (not a specific IP)
3. Test with `nc -zv play.${SECRET_DOMAIN} <port>` from outside network
