<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Change enum to string for flexibility with new document types
        // MySQL requires a workaround to modify enum columns
        DB::statement("ALTER TABLE documents MODIFY COLUMN type VARCHAR(50) NOT NULL DEFAULT 'player'");

        // Migrate old 'admin' type to 'server_admin'
        DB::table('documents')->where('type', 'admin')->update(['type' => 'server_admin']);
    }

    public function down(): void
    {
        // Migrate back to old types
        DB::table('documents')->where('type', 'server_admin')->update(['type' => 'admin']);
        DB::table('documents')->whereIn('type', ['host_admin', 'server_mod'])->update(['type' => 'admin']);

        // Change back to enum
        DB::statement("ALTER TABLE documents MODIFY COLUMN type ENUM('admin', 'player') NOT NULL DEFAULT 'player'");
    }
};
