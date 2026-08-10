---
name: markmap
description: Convert markdown outlines into interactive mind map visualizations using markmap-cli. Outputs interactive HTML or SVG. Great for content planning, topic research, and knowledge visualization.
---

# Markmap Mind Map Skill

Markmap transforms markdown lists into beautiful, interactive mind maps.

## Render Command
```bash
markmap content-plan.md                    # Interactive HTML (default)
markmap content-plan.md -o map.html        # Explicit output
markmap content-plan.md --no-open          # Don't auto-open browser
```

## Example: Content Strategy Map
```markdown
# AI Creator OS Content Plan

## YouTube Videos
### Tutorials
- How to install AI Creator OS
- VidIQ keyword research with Claude
- Building CapCut projects with AI
### Case Studies
- From script to published video in 30 minutes
- My complete content workflow

## Social Media
### TikTok
- 60-second tool demos
- Before/After automations
### LinkedIn
- Industry insights
- Workflow breakdowns
### X / Twitter
- Hot takes
- Thread series

## Tools Covered
### Video Production
- Remotion
- CapCut API
- ElevenLabs
### Analytics
- VidIQ
- AssemblyAI
### Publishing
- Blotato
```

## Workflow
1. Write the markdown outline based on user's topic
2. Save to a `.md` file
3. Run `markmap filename.md`
4. An interactive HTML mind map opens in the browser
5. Share the HTML file or take a screenshot

## Tips
- Use 2-3 heading levels for best visual results
- Bullet points become leaf nodes
- Add emoji to headings for visual variety
- The HTML output is self-contained and shareable
