<?php

namespace Starter\ServerDocumentation\Filament\Admin\Resources\DocumentResource\Pages;

use Filament\Actions\Action;
use Filament\Actions\CreateAction;
use Filament\Resources\Pages\ListRecords;
use Illuminate\Support\HtmlString;
use Starter\ServerDocumentation\Filament\Admin\Resources\DocumentResource;

class ListDocuments extends ListRecords
{
    protected static string $resource = DocumentResource::class;

    protected function getHeaderActions(): array
    {
        return [
            Action::make('help')
                ->label('Permission Guide')
                ->icon('tabler-help')
                ->color('gray')
                ->modalHeading('Document Permission Guide')
                ->modalDescription(new HtmlString('
                    <div class="prose prose-sm dark:prose-invert max-w-none">
                        <p class="text-sm text-gray-500 dark:text-gray-400 mb-4">
                            <strong>Type</strong> controls <em>who</em> can see the document.
                            <strong>All Servers</strong> controls <em>where</em> it appears.
                        </p>

                        <table class="min-w-full text-sm">
                            <thead>
                                <tr class="border-b border-gray-200 dark:border-gray-700">
                                    <th class="text-left py-2 pr-4 font-medium">Type</th>
                                    <th class="text-left py-2 font-medium">Who Can See</th>
                                </tr>
                            </thead>
                            <tbody class="divide-y divide-gray-100 dark:divide-gray-800">
                                <tr>
                                    <td class="py-2 pr-4"><span class="inline-flex items-center px-2 py-1 text-xs font-medium rounded-md bg-danger-50 text-danger-700 dark:bg-danger-900/50 dark:text-danger-400">Host Admin</span></td>
                                    <td class="py-2 text-gray-600 dark:text-gray-300">Root Admins only</td>
                                </tr>
                                <tr>
                                    <td class="py-2 pr-4"><span class="inline-flex items-center px-2 py-1 text-xs font-medium rounded-md bg-warning-50 text-warning-700 dark:bg-warning-900/50 dark:text-warning-400">Server Admin</span></td>
                                    <td class="py-2 text-gray-600 dark:text-gray-300">Server owners + admins with Server Update/Create</td>
                                </tr>
                                <tr>
                                    <td class="py-2 pr-4"><span class="inline-flex items-center px-2 py-1 text-xs font-medium rounded-md bg-info-50 text-info-700 dark:bg-info-900/50 dark:text-info-400">Server Mod</span></td>
                                    <td class="py-2 text-gray-600 dark:text-gray-300">Subusers with control permissions (start/stop/restart)</td>
                                </tr>
                                <tr>
                                    <td class="py-2 pr-4"><span class="inline-flex items-center px-2 py-1 text-xs font-medium rounded-md bg-success-50 text-success-700 dark:bg-success-900/50 dark:text-success-400">Player</span></td>
                                    <td class="py-2 text-gray-600 dark:text-gray-300">Anyone with server access</td>
                                </tr>
                            </tbody>
                        </table>

                        <p class="text-sm text-gray-500 dark:text-gray-400 mt-4 mb-2"><strong>All Servers Toggle:</strong></p>
                        <ul class="text-sm text-gray-600 dark:text-gray-300 space-y-1 list-disc list-inside">
                            <li><strong>On</strong> → Document appears on every server</li>
                            <li><strong>Off</strong> → Must attach to specific servers</li>
                        </ul>

                        <p class="text-sm text-gray-500 dark:text-gray-400 mt-4 mb-2"><strong>Examples:</strong></p>
                        <ul class="text-sm text-gray-600 dark:text-gray-300 space-y-1 list-disc list-inside">
                            <li><strong>Player + All Servers</strong> → Welcome guide everyone sees everywhere</li>
                            <li><strong>Player + Specific Server</strong> → Rules for one server only</li>
                            <li><strong>Server Admin + All Servers</strong> → Company-wide admin procedures</li>
                            <li><strong>Server Mod + Specific Server</strong> → Mod notes for one server</li>
                        </ul>

                        <p class="text-xs text-gray-400 dark:text-gray-500 mt-4">
                            Higher tiers see all docs at their level and below (e.g., Server Admin sees Server Admin, Server Mod, and Player docs).
                        </p>
                    </div>
                '))
                ->modalSubmitAction(false)
                ->modalCancelActionLabel('Close'),
            CreateAction::make(),
        ];
    }
}
