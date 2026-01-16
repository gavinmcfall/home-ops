<?php

namespace Starter\ServerDocumentation\Models;

use App\Models\Server;
use App\Models\User;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Support\Str;

class Document extends Model
{
    use SoftDeletes;

    protected $table = 'documents';

    protected $fillable = [
        'uuid',
        'title',
        'slug',
        'content',
        'type',
        'is_global',
        'is_published',
        'author_id',
        'last_edited_by',
        'sort_order',
    ];

    protected $casts = [
        'is_global' => 'boolean',
        'is_published' => 'boolean',
    ];

    protected static function booted(): void
    {
        static::creating(function (Document $document) {
            $document->uuid ??= Str::uuid()->toString();
            $document->slug ??= Str::slug($document->title);
            $document->author_id ??= auth()->id();
        });

        static::updating(function (Document $document) {
            if ($document->isDirty(['title', 'content'])) {
                $document->createVersion();
                $document->last_edited_by = auth()->id();
            }
        });
    }

    // Relationships

    public function author(): BelongsTo
    {
        return $this->belongsTo(User::class, 'author_id');
    }

    public function lastEditor(): BelongsTo
    {
        return $this->belongsTo(User::class, 'last_edited_by');
    }

    public function servers(): BelongsToMany
    {
        return $this->belongsToMany(Server::class, 'document_server')
            ->withPivot('sort_order')
            ->withTimestamps()
            ->orderByPivot('sort_order');
    }

    public function versions(): HasMany
    {
        return $this->hasMany(DocumentVersion::class)
            ->orderByDesc('version_number');
    }

    // Version management

    public function createVersion(?string $changeSummary = null): DocumentVersion
    {
        $latestVersion = $this->versions()->max('version_number') ?? 0;

        return $this->versions()->create([
            'title' => $this->getOriginal('title') ?? $this->title,
            'content' => $this->getOriginal('content') ?? $this->content,
            'version_number' => $latestVersion + 1,
            'edited_by' => auth()->id(),
            'change_summary' => $changeSummary,
        ]);
    }

    public function restoreVersion(DocumentVersion $version): void
    {
        $this->updateQuietly([
            'title' => $version->title,
            'content' => $version->content,
            'last_edited_by' => auth()->id(),
        ]);

        $this->createVersion('Restored from version ' . $version->version_number);
    }

    public function getCurrentVersionNumber(): int
    {
        return $this->versions()->max('version_number') ?? 1;
    }

    // Scopes

    public function scopeAdmin(Builder $query): Builder
    {
        return $query->where('type', 'admin');
    }

    public function scopePlayer(Builder $query): Builder
    {
        return $query->where('type', 'player');
    }

    public function scopeGlobal(Builder $query): Builder
    {
        return $query->where('is_global', true);
    }

    public function scopePublished(Builder $query): Builder
    {
        return $query->where('is_published', true);
    }

    public function scopeForServer(Builder $query, Server $server): Builder
    {
        return $query->where(function (Builder $q) use ($server) {
            $q->whereHas('servers', fn (Builder $sub) => $sub->where('servers.id', $server->id))
                ->orWhere('is_global', true);
        });
    }

    // Helpers

    public function isAdminOnly(): bool
    {
        return $this->type === 'admin';
    }

    public function isPlayerVisible(): bool
    {
        return $this->type === 'player';
    }
}
