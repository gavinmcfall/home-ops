<?php

return [
    'navigation' => [
        'documents' => 'Documents',
    ],

    'document' => [
        'title' => 'Title',
        'slug' => 'Slug',
        'content' => 'Content',
        'type' => 'Type',
        'is_global' => 'Global Document',
        'is_published' => 'Published',
        'sort_order' => 'Sort Order',
        'author' => 'Author',
        'last_edited_by' => 'Last Edited By',
        'version' => 'Version',
    ],

    'types' => [
        'host_admin' => 'Host Admin',
        'host_admin_description' => 'Root Admins only',
        'server_admin' => 'Server Admin',
        'server_admin_description' => 'Server owners + admins with Server Update/Create',
        'server_mod' => 'Server Mod',
        'server_mod_description' => 'Subusers with control permissions',
        'player' => 'Player',
        'player_description' => 'Anyone with server access',
    ],

    'messages' => [
        'version_restored' => 'Version :version restored successfully.',
        'no_documents' => 'No documents available.',
        'no_versions' => 'No versions yet.',
    ],

    'labels' => [
        'all_servers' => 'All Servers',
        'all_servers_helper' => 'Show on all servers (otherwise attach to specific servers below)',
        'published_helper' => 'Unpublished documents are only visible to admins',
        'sort_order_helper' => 'Lower numbers appear first',
    ],

    'permission_guide' => [
        'title' => 'Permission Guide',
        'description' => 'Understanding document visibility',
        'type_controls' => 'Type controls who can see the document.',
        'all_servers_controls' => 'All Servers controls where it appears.',
        'who_can_see' => 'Who Can See',
        'hierarchy_note' => 'Higher tiers can see all docs at their level and below.',
    ],
];
