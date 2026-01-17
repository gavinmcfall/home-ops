<?php

namespace Starter\ServerDocumentation\Services;

use League\CommonMark\CommonMarkConverter;
use League\CommonMark\Environment\Environment;
use League\CommonMark\Extension\CommonMark\CommonMarkCoreExtension;
use League\CommonMark\Extension\GithubFlavoredMarkdownExtension;
use League\CommonMark\MarkdownConverter as LeagueMarkdownConverter;
use League\HTMLToMarkdown\HtmlConverter;

class MarkdownConverter
{
    protected HtmlConverter $htmlToMarkdown;
    protected LeagueMarkdownConverter $markdownToHtml;

    public function __construct()
    {
        // HTML to Markdown converter
        $this->htmlToMarkdown = new HtmlConverter([
            'strip_tags' => false,
            'hard_break' => true,
            'preserve_comments' => false,
            'strip_placeholder_links' => true,
        ]);

        // Markdown to HTML converter with GitHub Flavored Markdown
        $environment = new Environment([
            'html_input' => 'allow',
            'allow_unsafe_links' => false,
        ]);
        $environment->addExtension(new CommonMarkCoreExtension());
        $environment->addExtension(new GithubFlavoredMarkdownExtension());

        $this->markdownToHtml = new LeagueMarkdownConverter($environment);
    }

    /**
     * Convert HTML content to Markdown.
     */
    public function toMarkdown(string $html): string
    {
        // Clean up the HTML before conversion
        $html = $this->cleanHtml($html);

        return $this->htmlToMarkdown->convert($html);
    }

    /**
     * Convert Markdown content to HTML.
     */
    public function toHtml(string $markdown): string
    {
        return $this->markdownToHtml->convert($markdown)->getContent();
    }

    /**
     * Clean HTML before markdown conversion.
     */
    protected function cleanHtml(string $html): string
    {
        // Remove any style tags that might have been included
        $html = preg_replace('/<style[^>]*>.*?<\/style>/is', '', $html);

        // Remove empty paragraphs
        $html = preg_replace('/<p>\s*<\/p>/i', '', $html);

        // Normalize whitespace
        $html = preg_replace('/\s+/', ' ', $html);

        return trim($html);
    }

    /**
     * Generate a safe filename for a document.
     */
    public function generateFilename(string $title, string $slug): string
    {
        // Prefer slug if available, otherwise sanitize title
        $filename = !empty($slug) ? $slug : $this->sanitizeFilename($title);

        return $filename . '.md';
    }

    /**
     * Sanitize a string for use as a filename.
     */
    protected function sanitizeFilename(string $name): string
    {
        // Convert to lowercase and replace spaces with hyphens
        $name = strtolower(trim($name));
        $name = preg_replace('/\s+/', '-', $name);

        // Remove any character that isn't alphanumeric, hyphen, or underscore
        $name = preg_replace('/[^a-z0-9\-_]/', '', $name);

        // Remove multiple consecutive hyphens
        $name = preg_replace('/-+/', '-', $name);

        return $name ?: 'document';
    }

    /**
     * Add YAML frontmatter to markdown content.
     */
    public function addFrontmatter(string $markdown, array $metadata): string
    {
        $frontmatter = "---\n";
        foreach ($metadata as $key => $value) {
            if (is_bool($value)) {
                $value = $value ? 'true' : 'false';
            } elseif (is_array($value)) {
                $value = implode(', ', $value);
            }
            $frontmatter .= "{$key}: {$value}\n";
        }
        $frontmatter .= "---\n\n";

        return $frontmatter . $markdown;
    }

    /**
     * Parse YAML frontmatter from markdown content.
     * Returns [metadata, content] tuple.
     */
    public function parseFrontmatter(string $markdown): array
    {
        $pattern = '/^---\s*\n(.*?)\n---\s*\n(.*)$/s';

        if (preg_match($pattern, $markdown, $matches)) {
            $metadata = [];
            $lines = explode("\n", trim($matches[1]));

            foreach ($lines as $line) {
                if (str_contains($line, ':')) {
                    [$key, $value] = explode(':', $line, 2);
                    $key = trim($key);
                    $value = trim($value);

                    // Convert string booleans
                    if ($value === 'true') {
                        $value = true;
                    } elseif ($value === 'false') {
                        $value = false;
                    }

                    $metadata[$key] = $value;
                }
            }

            return [$metadata, trim($matches[2])];
        }

        // No frontmatter found
        return [[], $markdown];
    }
}
