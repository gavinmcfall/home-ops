# Server Documentation Plugin for Pelican Panel

A documentation management plugin for [Pelican Panel](https://pelican.dev) that allows administrators to create, organize, and distribute documentation to server users with granular permission-based visibility.

## Features

- **Rich Text Editor** - Full WYSIWYG editing with formatting, lists, code blocks, tables, and more
- **4-Tier Permission System** - Control who sees what documentation based on their role
- **Global & Server-Specific Docs** - Create documentation that appears on all servers or only specific ones
- **Version History** - Track changes with automatic versioning and restore previous versions
- **Markdown Import/Export** - Import `.md` files or export documents for backup/migration
- **Server Panel Integration** - Documents appear in the player's server sidebar
- **Admin Panel Integration** - Full CRUD management with filtering, search, and bulk actions

## Screenshots

### Admin Panel - Document List
![Admin Documents List](docs/images/admin-documents-list.png)
*Full document management with type badges, global indicators, and server counts*

### Admin Panel - Document Editor
<!-- TODO: Add screenshot -->
![Admin Document Editor](docs/images/admin-document-editor.png)
*Rich text editor with permission type selector and global toggle*

### Admin Panel - Permission Guide
<!-- TODO: Add screenshot -->
![Permission Guide Modal](docs/images/permission-guide-modal.png)
*Built-in guide explaining the permission hierarchy*

### Admin Panel - Server Mod View
![Server Mod Admin View](docs/images/server-mod-admin-view.png)
*Server moderators with admin access see the same documents but with limited sidebar*

### Server Panel - Player View
![Player Server View](docs/images/player-server-view.png)
*Players only see documents marked as "Player" type*

### Server Panel - Server Mod View
![Server Mod Server View](docs/images/server-mod-server-view.png)
*Server mods see "Server Mod" and "Player" documents, including the Moderator Handbook*

### Server Panel - Server Admin View
<!-- TODO: Add screenshot -->
![Server Admin Server View](docs/images/server-admin-server-view.png)
*Server admins see "Server Admin", "Server Mod", and "Player" documents*

### Admin Panel - Attach Documents to Server
<!-- TODO: Add screenshot -->
![Documents Relation Manager](docs/images/documents-relation-manager.png)
*Attach specific documents to individual servers*

### Version History
<!-- TODO: Add screenshot -->
![Version History](docs/images/version-history.png)
*View and restore previous document versions*

## The 4-Tier Permission System

### Why Custom Tiers?

Pelican Panel has two built-in permission contexts:
1. **Admin Panel** - Root admins and users with admin roles
2. **Server Panel** - Server owners and subusers with granular permissions

However, for documentation, we needed more nuance. A game server host typically has:
- **Infrastructure documentation** - Only for the hosting team (network configs, security policies)
- **Server administration guides** - For server owners renting/managing servers
- **Moderator handbooks** - For trusted users helping manage game servers
- **Player-facing docs** - Rules, guides, and welcome messages for everyone

Pelican's native permissions don't map cleanly to these roles, so we created a **virtual permission tier system** that infers user roles from their existing Pelican permissions.

### Permission Tiers

| Tier | Badge | Who Can See | How It's Determined |
|------|-------|-------------|---------------------|
| **Host Admin** | 🔴 Red | Root Admins only | `user.isRootAdmin()` |
| **Server Admin** | 🟠 Orange | Server owners + admins with Server Update/Create | Server ownership OR admin panel server permissions |
| **Server Mod** | 🔵 Blue | Subusers with control permissions | Has `control.*` subuser permissions (start/stop/restart/console) |
| **Player** | 🟢 Green | Anyone with server access | Default - anyone who can view the server |

### Hierarchy

Higher tiers see all documents at their level **and below**:
- **Host Admin** sees: Host Admin, Server Admin, Server Mod, Player
- **Server Admin** sees: Server Admin, Server Mod, Player
- **Server Mod** sees: Server Mod, Player
- **Player** sees: Player only

### Example Use Cases

| Document | Type | Global | Use Case |
|----------|------|--------|----------|
| Infrastructure Security Policy | Host Admin | Yes | Internal security guidelines for your hosting team |
| Server Administration Guide | Server Admin | Yes | SOPs for anyone managing a server |
| Moderator Handbook | Server Mod | Yes | Guidelines for trusted helpers with console access |
| Welcome to Our Servers! | Player | Yes | Community rules visible to all players |
| Minecraft Server Info | Player | No | Server-specific information for one server only |

## Installation

### Requirements
- Pelican Panel v1.0+
- PHP 8.2+

### Install via Admin Panel

1. Download the plugin zip or clone to your plugins directory
2. Navigate to **Admin Panel → Plugins**
3. Click **Install** next to "Server Documentation"
4. Run migrations when prompted

### Manual Installation

```bash
# Copy plugin to plugins directory
cp -r server-documentation /var/www/html/plugins/

# Install composer dependencies
cd /var/www/html/plugins/server-documentation
composer install --no-dev

# Run migrations
php /var/www/html/artisan migrate
```

## Usage

### Creating Documents

1. Go to **Admin Panel → Documents**
2. Click **New Document**
3. Fill in:
   - **Title** - Display name for the document
   - **Slug** - URL-friendly identifier (auto-generated from title)
   - **Type** - Permission tier (Host Admin, Server Admin, Server Mod, Player)
   - **All Servers** - Toggle to show on every server
   - **Published** - Toggle to hide from non-admins while drafting
   - **Sort Order** - Lower numbers appear first in lists
4. Write your content using the rich text editor
5. Click **Save**

### Attaching to Servers

If "All Servers" is disabled, you must attach the document to specific servers:

1. Edit the document
2. Scroll to the **Servers** relation manager
3. Click **Attach** and select servers

Or from the server side:
1. Go to **Admin Panel → Servers → [Server] → Documents tab**
2. Click **Attach** and select documents

### Importing Markdown

1. Go to **Admin Panel → Documents**
2. Click **Import Markdown**
3. Upload a `.md` file
4. Optionally enable "Use YAML Frontmatter" to extract metadata:

```yaml
---
title: My Document
slug: my-document
type: player
is_global: true
is_published: true
sort_order: 10
---

# Document Content

Your markdown content here...
```

### Exporting Documents

1. Edit any document
2. Click the **Download** icon in the header
3. Document downloads as `.md` with YAML frontmatter

### Version History

1. Edit any document
2. Click the **History** icon (shows badge with version count)
3. View previous versions with timestamps and editors
4. Click **Preview** to see old content
5. Click **Restore** to revert to a previous version

## Configuration

### Admin Permissions

By default, only Root Admins can manage documents in the admin panel. The plugin registers these Gates:

- `viewList document`
- `view document`
- `create document`
- `update document`
- `delete document`

To extend access to other admin roles, modify the `registerDocumentPermissions()` method in the ServiceProvider.

### Customization

The plugin uses Pelican's standard extensibility patterns:

```php
// In another plugin or service provider
use Starter\ServerDocumentation\Filament\Admin\Resources\DocumentResource;

// Modify the form
DocumentResource::modifyForm(function (Form $form) {
    return $form->schema([
        // Add custom fields
    ]);
});

// Modify the table
DocumentResource::modifyTable(function (Table $table) {
    return $table->columns([
        // Add custom columns
    ]);
});
```

## File Structure

```
server-documentation/
├── composer.json              # Dependencies (commonmark, html-to-markdown)
├── plugin.json                # Plugin metadata
├── database/migrations/       # Database schema
├── lang/en/strings.php        # Translations (i18n ready)
├── resources/
│   ├── css/                   # Document content styling
│   └── views/filament/        # Blade templates
└── src/
    ├── Models/                # Document, DocumentVersion
    ├── Policies/              # Permission logic
    ├── Providers/             # Service provider
    ├── Services/              # Markdown converter
    └── Filament/
        ├── Admin/             # Admin panel resources
        └── Server/            # Server panel pages
```

## Database Schema

```
documents
├── id, uuid
├── title, slug (unique)
├── content (HTML from rich editor)
├── type (host_admin, server_admin, server_mod, player)
├── is_global, is_published
├── sort_order
├── author_id, last_edited_by
├── timestamps, soft_deletes

document_versions
├── id, document_id
├── title, content (snapshot)
├── version_number
├── edited_by, change_summary
├── created_at

document_server (pivot)
├── document_id, server_id
├── sort_order
├── timestamps
```

## Contributing

This plugin was developed for [Pelican Panel](https://pelican.dev). Contributions welcome!

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) for details.

## Credits

- Built for [Pelican Panel](https://pelican.dev)
- Uses [League CommonMark](https://commonmark.thephpleague.com/) for Markdown parsing
- Uses [League HTML to Markdown](https://github.com/thephpleague/html-to-markdown) for export

---

*Pair-programmed with [Claude Code](https://claude.ai/code)*
