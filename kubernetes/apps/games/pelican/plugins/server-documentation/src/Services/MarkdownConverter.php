<?php

namespace Starter\ServerDocumentation\Services;

use League\CommonMark\CommonMarkConverter;
use League\CommonMark\Environment\Environment;
use League\CommonMark\Extension\CommonMark\CommonMarkCoreExtension;
use League\CommonMark\Extension\GithubFlavoredMarkdownExtension;
use League\CommonMark\MarkdownConverter as LeagueMarkdownConverter;

class MarkdownConverter
{
    protected LeagueMarkdownConverter $markdownToHtml;

    public function __construct()
    {
        // Markdown to HTML converter with GitHub Flavored Markdown
        // Uses Pelican's bundled league/commonmark
        $environment = new Environment([
            'html_input' => 'allow',
            'allow_unsafe_links' => false,
        ]);
        $environment->addExtension(new CommonMarkCoreExtension());
        $environment->addExtension(new GithubFlavoredMarkdownExtension());

        $this->markdownToHtml = new LeagueMarkdownConverter($environment);
    }

    /**
     * Convert HTML content to Markdown using built-in converter.
     * Handles common HTML elements without external dependencies.
     */
    public function toMarkdown(string $html): string
    {
        // Clean up the HTML first
        $html = $this->cleanHtml($html);

        // Convert HTML to Markdown
        $markdown = $this->htmlToMarkdown($html);

        // Clean up the result
        $markdown = $this->cleanMarkdown($markdown);

        return $markdown;
    }

    /**
     * Convert Markdown content to HTML.
     */
    public function toHtml(string $markdown): string
    {
        return $this->markdownToHtml->convert($markdown)->getContent();
    }

    /**
     * Built-in HTML to Markdown converter.
     * Handles common elements used in documentation.
     */
    protected function htmlToMarkdown(string $html): string
    {
        // Preserve code blocks first (prevent processing inside them)
        $codeBlocks = [];
        $html = preg_replace_callback('/<pre[^>]*><code[^>]*>(.*?)<\/code><\/pre>/is', function ($matches) use (&$codeBlocks) {
            $placeholder = '{{CODE_BLOCK_' . count($codeBlocks) . '}}';
            $codeBlocks[$placeholder] = "```\n" . html_entity_decode(strip_tags($matches[1])) . "\n```";
            return $placeholder;
        }, $html);

        // Inline code
        $html = preg_replace('/<code[^>]*>(.*?)<\/code>/is', '`$1`', $html);

        // Headings
        $html = preg_replace('/<h1[^>]*>(.*?)<\/h1>/is', "\n# $1\n", $html);
        $html = preg_replace('/<h2[^>]*>(.*?)<\/h2>/is', "\n## $1\n", $html);
        $html = preg_replace('/<h3[^>]*>(.*?)<\/h3>/is', "\n### $1\n", $html);
        $html = preg_replace('/<h4[^>]*>(.*?)<\/h4>/is', "\n#### $1\n", $html);
        $html = preg_replace('/<h5[^>]*>(.*?)<\/h5>/is', "\n##### $1\n", $html);
        $html = preg_replace('/<h6[^>]*>(.*?)<\/h6>/is', "\n###### $1\n", $html);

        // Bold and italic
        $html = preg_replace('/<strong[^>]*>(.*?)<\/strong>/is', '**$1**', $html);
        $html = preg_replace('/<b[^>]*>(.*?)<\/b>/is', '**$1**', $html);
        $html = preg_replace('/<em[^>]*>(.*?)<\/em>/is', '*$1*', $html);
        $html = preg_replace('/<i[^>]*>(.*?)<\/i>/is', '*$1*', $html);

        // Strikethrough
        $html = preg_replace('/<del[^>]*>(.*?)<\/del>/is', '~~$1~~', $html);
        $html = preg_replace('/<s[^>]*>(.*?)<\/s>/is', '~~$1~~', $html);

        // Links
        $html = preg_replace_callback('/<a[^>]+href=["\']([^"\']+)["\'][^>]*>(.*?)<\/a>/is', function ($matches) {
            $url = $matches[1];
            $text = strip_tags($matches[2]);
            return "[$text]($url)";
        }, $html);

        // Images
        $html = preg_replace_callback('/<img[^>]+src=["\']([^"\']+)["\'][^>]*alt=["\']([^"\']*)["\'][^>]*\/?>/is', function ($matches) {
            return "![{$matches[2]}]({$matches[1]})";
        }, $html);
        $html = preg_replace_callback('/<img[^>]+src=["\']([^"\']+)["\'][^>]*\/?>/is', function ($matches) {
            return "![]({$matches[1]})";
        }, $html);

        // Blockquotes
        $html = preg_replace_callback('/<blockquote[^>]*>(.*?)<\/blockquote>/is', function ($matches) {
            $content = strip_tags($matches[1]);
            $lines = explode("\n", trim($content));
            return "\n" . implode("\n", array_map(fn($line) => '> ' . trim($line), $lines)) . "\n";
        }, $html);

        // Unordered lists
        $html = preg_replace_callback('/<ul[^>]*>(.*?)<\/ul>/is', function ($matches) {
            return $this->convertList($matches[1], '-');
        }, $html);

        // Ordered lists
        $html = preg_replace_callback('/<ol[^>]*>(.*?)<\/ol>/is', function ($matches) {
            return $this->convertList($matches[1], '1.');
        }, $html);

        // Horizontal rules
        $html = preg_replace('/<hr[^>]*\/?>/is', "\n---\n", $html);

        // Paragraphs
        $html = preg_replace('/<p[^>]*>(.*?)<\/p>/is', "\n$1\n", $html);

        // Line breaks
        $html = preg_replace('/<br[^>]*\/?>/is', "  \n", $html);

        // Tables (basic support)
        $html = preg_replace_callback('/<table[^>]*>(.*?)<\/table>/is', function ($matches) {
            return $this->convertTable($matches[1]);
        }, $html);

        // Strip remaining HTML tags
        $html = strip_tags($html);

        // Restore code blocks
        foreach ($codeBlocks as $placeholder => $code) {
            $html = str_replace($placeholder, $code, $html);
        }

        // Decode HTML entities
        $html = html_entity_decode($html, ENT_QUOTES | ENT_HTML5, 'UTF-8');

        return $html;
    }

    /**
     * Convert HTML list to Markdown.
     */
    protected function convertList(string $html, string $marker): string
    {
        $result = "\n";
        preg_match_all('/<li[^>]*>(.*?)<\/li>/is', $html, $matches);

        $index = 1;
        foreach ($matches[1] as $item) {
            $item = trim(strip_tags($item));
            if ($marker === '1.') {
                $result .= "{$index}. {$item}\n";
                $index++;
            } else {
                $result .= "{$marker} {$item}\n";
            }
        }

        return $result;
    }

    /**
     * Convert HTML table to Markdown.
     */
    protected function convertTable(string $html): string
    {
        $result = "\n";
        $headers = [];
        $rows = [];

        // Extract headers
        if (preg_match('/<thead[^>]*>(.*?)<\/thead>/is', $html, $theadMatch)) {
            preg_match_all('/<th[^>]*>(.*?)<\/th>/is', $theadMatch[1], $thMatches);
            $headers = array_map(fn($h) => trim(strip_tags($h)), $thMatches[1]);
        }

        // Extract rows
        if (preg_match('/<tbody[^>]*>(.*?)<\/tbody>/is', $html, $tbodyMatch)) {
            preg_match_all('/<tr[^>]*>(.*?)<\/tr>/is', $tbodyMatch[1], $trMatches);
            foreach ($trMatches[1] as $tr) {
                preg_match_all('/<td[^>]*>(.*?)<\/td>/is', $tr, $tdMatches);
                $rows[] = array_map(fn($d) => trim(strip_tags($d)), $tdMatches[1]);
            }
        } else {
            // No tbody, try direct tr
            preg_match_all('/<tr[^>]*>(.*?)<\/tr>/is', $html, $trMatches);
            $first = true;
            foreach ($trMatches[1] as $tr) {
                if ($first && empty($headers)) {
                    preg_match_all('/<t[hd][^>]*>(.*?)<\/t[hd]>/is', $tr, $cellMatches);
                    $headers = array_map(fn($h) => trim(strip_tags($h)), $cellMatches[1]);
                    $first = false;
                } else {
                    preg_match_all('/<td[^>]*>(.*?)<\/td>/is', $tr, $tdMatches);
                    $rows[] = array_map(fn($d) => trim(strip_tags($d)), $tdMatches[1]);
                }
            }
        }

        if (empty($headers)) {
            return $result;
        }

        // Build markdown table
        $result .= '| ' . implode(' | ', $headers) . " |\n";
        $result .= '| ' . implode(' | ', array_fill(0, count($headers), '---')) . " |\n";

        foreach ($rows as $row) {
            // Pad row if needed
            while (count($row) < count($headers)) {
                $row[] = '';
            }
            $result .= '| ' . implode(' | ', $row) . " |\n";
        }

        return $result;
    }

    /**
     * Clean HTML before markdown conversion.
     */
    protected function cleanHtml(string $html): string
    {
        // Remove style tags
        $html = preg_replace('/<style[^>]*>.*?<\/style>/is', '', $html);

        // Remove script tags
        $html = preg_replace('/<script[^>]*>.*?<\/script>/is', '', $html);

        // Remove HTML comments
        $html = preg_replace('/<!--.*?-->/s', '', $html);

        // Normalize whitespace in tags
        $html = preg_replace('/\s+/', ' ', $html);

        return trim($html);
    }

    /**
     * Clean up markdown output.
     */
    protected function cleanMarkdown(string $markdown): string
    {
        // Remove excessive blank lines (more than 2 consecutive)
        $markdown = preg_replace('/\n{3,}/', "\n\n", $markdown);

        // Trim whitespace from each line
        $lines = explode("\n", $markdown);
        $lines = array_map('rtrim', $lines);
        $markdown = implode("\n", $lines);

        // Trim overall
        return trim($markdown);
    }

    /**
     * Generate a safe filename for a document.
     */
    public function generateFilename(string $title, string $slug): string
    {
        $filename = !empty($slug) ? $slug : $this->sanitizeFilename($title);
        return $filename . '.md';
    }

    /**
     * Sanitize a string for use as a filename.
     */
    protected function sanitizeFilename(string $name): string
    {
        $name = strtolower(trim($name));
        $name = preg_replace('/\s+/', '-', $name);
        $name = preg_replace('/[^a-z0-9\-_]/', '', $name);
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

        return [[], $markdown];
    }
}
