---
name: mermaid
description: Generate Mermaid diagrams — flowcharts, sequence diagrams, Gantt charts, ER diagrams, Git graphs, pie charts, mind maps. Renders to SVG/PNG via mmdc CLI.
---

# Mermaid Diagram Skill

You are an expert in Mermaid diagram syntax. Always produce valid, complete Mermaid code.

## Render Command
```bash
mmdc -i diagram.mmd -o diagram.svg
mmdc -i diagram.mmd -o diagram.png -w 1920
```

## Diagram Types

### Flowchart
```mermaid
flowchart TD
    A[User Request] --> B{Has API Key?}
    B -->|Yes| C[Call ElevenLabs]
    B -->|No| D[Get API Key]
    D --> C
    C --> E[Generate Voiceover]
    E --> F[Add to CapCut Project]
```

### Sequence
```mermaid
sequenceDiagram
    Creator->>Claude: Create tutorial video
    Claude->>VidIQ: Research keywords
    VidIQ-->>Claude: Top keywords
    Claude->>Remotion: Render intro
    Claude->>ElevenLabs: Generate voiceover
    Claude-->>Creator: Video ready
```

### Gantt Chart
```mermaid
gantt
    title Content Production Schedule
    dateFormat YYYY-MM-DD
    section Script
    Research     :a1, 2026-04-20, 1d
    Write Script :after a1, 2d
    section Production
    Record       :2026-04-23, 1d
    Edit         :2026-04-24, 2d
    section Publishing
    Schedule     :2026-04-26, 1d
```

### ER Diagram
```mermaid
erDiagram
    VIDEO ||--o{ SCENE : contains
    SCENE ||--o{ ASSET : uses
    ASSET }|--|| MEDIA_FILE : references
```

### Git Graph
```mermaid
gitGraph
   commit id: "Initial setup"
   branch feature/video-pipeline
   commit id: "Add Remotion"
   commit id: "Add ElevenLabs"
   checkout main
   merge feature/video-pipeline
```

## Workflow
1. Write the Mermaid diagram code based on the user's request
2. Save to a `.mmd` file
3. Run `mmdc` to render
4. Display the output image
