<?php

return [
    'navigation' => [
        'documents' => 'Documents',
        'group' => 'Content',
    ],

    'document' => [
        'singular' => 'Document',
        'plural' => 'Documents',
        'title' => 'Title',
        'slug' => 'Slug',
        'content' => 'Content',
        'type' => 'Type',
        'is_global' => 'Global',
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

    'labels' => [
        'all_servers' => 'All Servers',
        'all_servers_helper' => 'Show on all servers (otherwise attach to specific servers below)',
        'published_helper' => 'Unpublished documents are only visible to admins',
        'sort_order_helper' => 'Lower numbers appear first',
    ],

    'form' => [
        'details_section' => 'Document Details',
    ],

    'table' => [
        'servers' => 'Servers',
        'updated_at' => 'Updated',
        'empty_heading' => 'No documents yet',
        'empty_description' => 'Create your first document to get started.',
    ],

    'permission_guide' => [
        'title' => 'Permission Guide',
        'description' => 'Understanding document visibility',
        'type_controls' => 'controls who can see the document.',
        'all_servers_controls' => 'controls where it appears.',
        'who_can_see' => 'Who Can See',
        'hierarchy_note' => 'Higher tiers can see all docs at their level and below (e.g., Server Admin sees Server Admin, Server Mod, and Player docs).',
    ],

    'messages' => [
        'version_restored' => 'Version :version restored successfully.',
        'no_documents' => 'No documents available.',
        'no_versions' => 'No versions yet.',
    ],

    'versions' => [
        'title' => 'Version History',
        'current_document' => 'Current Document',
        'current_version' => 'Current Version',
        'last_updated' => 'Last Updated',
        'last_edited_by' => 'Last Edited By',
        'version_number' => 'Version',
        'edited_by' => 'Edited By',
        'date' => 'Date',
        'change_summary' => 'Change Summary',
        'preview' => 'Preview',
        'restore' => 'Restore',
        'restore_confirm' => 'Are you sure you want to restore this version?',
        'restored' => 'Version restored successfully.',
    ],

    'server_panel' => [
        'title' => 'Server Documents',
        'no_documents' => 'No documents available',
        'no_documents_description' => 'There are no documents for this server yet.',
        'select_document' => 'Select a document',
        'select_document_description' => 'Choose a document from the list to view its contents.',
        'last_updated' => 'Last updated :time',
        'global' => 'Global',
    ],
];
