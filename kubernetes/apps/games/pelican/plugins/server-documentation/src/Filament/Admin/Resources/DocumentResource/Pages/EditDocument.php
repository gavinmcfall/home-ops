<?php

namespace Starter\ServerDocumentation\Filament\Admin\Resources\DocumentResource\Pages;

use Filament\Actions\Action;
use Filament\Actions\ActionGroup;
use Filament\Actions\DeleteAction;
use Filament\Resources\Pages\EditRecord;
use Filament\Support\Enums\IconSize;
use Starter\ServerDocumentation\Filament\Admin\Resources\DocumentResource;

class EditDocument extends EditRecord
{
    protected static string $resource = DocumentResource::class;

    /** @return array<Action|ActionGroup> */
    protected function getHeaderActions(): array
    {
        return [
            Action::make('versions')
                ->label(trans('server-documentation::strings.versions.title'))
                ->icon('tabler-history')
                ->iconButton()
                ->iconSize(IconSize::ExtraLarge)
                ->url(fn () => DocumentResource::getUrl('versions', ['record' => $this->record]))
                ->badge(fn () => $this->record->versions()->count() ?: null),
            $this->getSaveFormAction()
                ->formId('form')
                ->iconButton()
                ->iconSize(IconSize::ExtraLarge)
                ->icon('tabler-device-floppy'),
            DeleteAction::make()
                ->iconButton()
                ->iconSize(IconSize::ExtraLarge),
        ];
    }

    protected function getFormActions(): array
    {
        return [];
    }

    protected function getRedirectUrl(): string
    {
        return $this->getResource()::getUrl('index');
    }
}
