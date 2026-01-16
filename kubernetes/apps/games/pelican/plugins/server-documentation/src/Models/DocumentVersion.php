<?php

namespace Starter\ServerDocumentation\Models;

use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class DocumentVersion extends Model
{
    protected $table = 'document_versions';

    protected $fillable = [
        'document_id',
        'title',
        'content',
        'version_number',
        'edited_by',
        'change_summary',
    ];

    public function document(): BelongsTo
    {
        return $this->belongsTo(Document::class);
    }

    public function editor(): BelongsTo
    {
        return $this->belongsTo(User::class, 'edited_by');
    }

    public function getFormattedVersionAttribute(): string
    {
        return 'v' . $this->version_number;
    }
}
